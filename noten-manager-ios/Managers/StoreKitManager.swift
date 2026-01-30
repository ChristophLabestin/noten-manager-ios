import Foundation
import Combine
import StoreKit
import FirebaseAuth

@MainActor
final class StoreKitManager: ObservableObject {
    enum PurchaseOutcome: Equatable {
        case success
        case pending
        case cancelled
        case failed(PurchaseFailure)
    }

    enum PurchaseFailure: Equatable {
        case offerExpired
        case productUnavailable
        case network
        case notAllowed
        case verificationFailed
        case unknown
    }

    enum RestoreOutcome: Equatable {
        case success(found: Bool)
        case failed(RestoreFailure)
    }

    enum RestoreFailure: Equatable {
        case network
        case notAllowed
        case unknown
    }

    private let launchOfferProductId = "earlybird_lifetime"
    private let subscriptionProductId = "noten_manager_pro_yearly"
    private let monthlySubscriptionProductId = "noten_manager_pro_monthly"
    private let subscriptionGroupId = "21865065"
    private let purchaseDefaultsKey = "launchOfferPurchased"
    private let subscriptionDefaultsKey = "proSubscriptionActive"

    @Published private(set) var product: Product?
    @Published private(set) var subscriptionProduct: Product?
    @Published private(set) var monthlySubscriptionProduct: Product?
    @Published private(set) var lastProductLoadError: String?
    @Published private(set) var isProcessingPurchase = false
    @Published private(set) var isProcessingSubscriptionPurchase = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isSubscriptionActive = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
        isSubscriptionActive = UserDefaults.standard.bool(forKey: subscriptionDefaultsKey)
        Task { [weak self] in
            await self?.loadProduct()
        }
        Task { [weak self] in
            await self?.refreshPurchasedStatus()
        }
        Task { [weak self] in
            await self?.refreshSubscriptionStatus()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [
                launchOfferProductId,
                subscriptionProductId,
                monthlySubscriptionProductId
            ])
            product = products.first(where: { $0.id == launchOfferProductId })
            subscriptionProduct = products.first(where: { $0.id == subscriptionProductId })
            monthlySubscriptionProduct = products.first(where: { $0.id == monthlySubscriptionProductId })
            var missing: [String] = []
            if product == nil { missing.append(launchOfferProductId) }
            if subscriptionProduct == nil { missing.append(subscriptionProductId) }
            if monthlySubscriptionProduct == nil { missing.append(monthlySubscriptionProductId) }
            if missing.isEmpty {
                lastProductLoadError = nil
            } else {
                lastProductLoadError = "Missing products: \(missing.joined(separator: ", "))"
            }
        } catch {
            product = nil
            subscriptionProduct = nil
            monthlySubscriptionProduct = nil
            lastProductLoadError = error.localizedDescription
        }
    }

    func purchaseLaunchOffer() async -> PurchaseOutcome {
        guard LaunchOfferNotificationManager.isOfferActive() else {
            return .failed(.offerExpired)
        }
        if isProcessingPurchase {
            return .pending
        }
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

        if product == nil {
            await loadProduct()
        }
        guard let product else {
            return .failed(.productUnavailable)
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                do {
                    let transaction = try checkVerified(verification)
                    await transaction.finish()
                    setPurchased(true)
                    if let uid = Auth.auth().currentUser?.uid {
                        await FirestoreService.shared.updateUserPurchaseMetadata(uid: uid, type: "lifetime", tier: nil)
                    }
                    return .success
                } catch {
                    return .failed(.verificationFailed)
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed(.unknown)
            }
        } catch {
            return .failed(mapPurchaseError(error))
        }
    }

    func purchaseSubscription(productId: String) async -> PurchaseOutcome {
        if isProcessingSubscriptionPurchase {
            return .pending
        }
        isProcessingSubscriptionPurchase = true
        defer { isProcessingSubscriptionPurchase = false }

        if subscriptionProduct(for: productId) == nil {
            await loadProduct()
        }
        guard let subscriptionProduct = subscriptionProduct(for: productId) else {
            return .failed(.productUnavailable)
        }

        do {
            let result = try await subscriptionProduct.purchase()
            switch result {
            case .success(let verification):
                do {
                    let transaction = try checkVerified(verification)
                    await transaction.finish()
                    setSubscriptionActive(true)
                    if let uid = Auth.auth().currentUser?.uid {
                        let tier = productId == subscriptionProductId ? "yearly" : "monthly"
                        await FirestoreService.shared.updateUserPurchaseMetadata(uid: uid, type: "subscription", tier: tier)
                    }
                    return .success
                } catch {
                    return .failed(.verificationFailed)
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed(.unknown)
            }
        } catch {
            return .failed(mapPurchaseError(error))
        }
    }

    func restorePurchases() async -> RestoreOutcome {
        if isRestoring {
            return .failed(.unknown)
        }
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            let foundLifetime = await refreshPurchasedStatus()
            let foundSubscription = await refreshSubscriptionStatus()
            return .success(found: foundLifetime || foundSubscription)
        } catch {
            return .failed(mapRestoreError(error))
        }
    }

    @discardableResult
    func refreshPurchasedStatus() async -> Bool {
        var hasPurchase = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productID == launchOfferProductId else { continue }
            if transaction.revocationDate == nil {
                hasPurchase = true
                break
            }
        }
        setPurchased(hasPurchase)
        return hasPurchase
    }

    @discardableResult
    func refreshSubscriptionStatus() async -> Bool {
        if subscriptionProduct == nil && monthlySubscriptionProduct == nil {
            await loadProduct()
        }
        guard let subscription = subscriptionStatusProduct()?.subscription else {
            setSubscriptionActive(false)
            return false
        }
        if subscription.subscriptionGroupID != subscriptionGroupId {
            let active = await subscriptionStatusFromEntitlements()
            setSubscriptionActive(active)
            return active
        }
        do {
            let statuses = try await subscription.status
            let active = statuses.contains { status in
                isActiveSubscriptionState(status.state)
            }
            setSubscriptionActive(active)
            return active
        } catch {
            setSubscriptionActive(false)
            return false
        }
    }

    private func subscriptionStatusFromEntitlements() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard transaction.productID == subscriptionProductId || transaction.productID == monthlySubscriptionProductId else {
                continue
            }
            if isActiveSubscriptionTransaction(transaction) {
                return true
            }
        }
        return false
    }

    @discardableResult
    func refreshAllStatus() async -> Bool {
        let lifetime = await refreshPurchasedStatus()
        let subscription = await refreshSubscriptionStatus()
        return lifetime || subscription
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == launchOfferProductId {
                let active = transaction.revocationDate == nil
                setPurchased(active)
                await transaction.finish()
                continue
            }
            if transaction.productID == subscriptionProductId {
                let active = isActiveSubscriptionTransaction(transaction)
                setSubscriptionActive(active)
                await transaction.finish()
                continue
            }
            if transaction.productID == monthlySubscriptionProductId {
                let active = isActiveSubscriptionTransaction(transaction)
                setSubscriptionActive(active)
                await transaction.finish()
                continue
            }
            await transaction.finish()
        }
    }

    private func subscriptionProduct(for productId: String) -> Product? {
        switch productId {
        case subscriptionProductId:
            return subscriptionProduct
        case monthlySubscriptionProductId:
            return monthlySubscriptionProduct
        default:
            return nil
        }
    }

    private func subscriptionStatusProduct() -> Product? {
        subscriptionProduct ?? monthlySubscriptionProduct
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func setPurchased(_ purchased: Bool) {
        UserDefaults.standard.set(purchased, forKey: purchaseDefaultsKey)
    }

    private func setSubscriptionActive(_ active: Bool) {
        isSubscriptionActive = active
        UserDefaults.standard.set(active, forKey: subscriptionDefaultsKey)
    }

    private func isActiveSubscriptionTransaction(_ transaction: Transaction) -> Bool {
        if transaction.revocationDate != nil {
            return false
        }
        let expiry = transaction.expirationDate ?? .distantFuture
        return expiry > Date()
    }

    private func isActiveSubscriptionState(_ state: Product.SubscriptionInfo.RenewalState) -> Bool {
        switch state {
        case .subscribed, .inGracePeriod:
            return true
        default:
            return false
        }
    }

    private func mapPurchaseError(_ error: Error) -> PurchaseFailure {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .networkError:
                return .network
            case .notAvailableInStorefront:
                return .productUnavailable
            case .notEntitled:
                return .notAllowed
            default:
                return .unknown
            }
        }
        if (error as? URLError) != nil {
            return .network
        }
        return .unknown
    }

    private func mapRestoreError(_ error: Error) -> RestoreFailure {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .networkError:
                return .network
            case .notEntitled:
                return .notAllowed
            default:
                return .unknown
            }
        }
        if (error as? URLError) != nil {
            return .network
        }
        return .unknown
    }

}
