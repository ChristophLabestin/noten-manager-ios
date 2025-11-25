import Foundation
import Combine
import LocalAuthentication

@MainActor
final class BiometricAuthManager: ObservableObject {
    static let shared = BiometricAuthManager()

    @Published private(set) var biometryType: LABiometryType = .none
    @Published private(set) var isEnabledForActiveUser: Bool = false
    @Published private(set) var biometricsAvailable: Bool = false

    private let defaults = UserDefaults.standard
    private let keyPrefix = "biometric_enabled_"
    private var activeUserId: String?

    init() {
        refreshAvailability()
    }

    func setActiveUser(id: String?) {
        activeUserId = id
        refreshEnabledState()
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometryType = context.biometryType
    }

    func refreshEnabledState() {
        refreshAvailability()
        isEnabledForActiveUser = isEnabled(for: activeUserId)
    }

    func isEnabled(for userId: String?) -> Bool {
        guard let uid = userId, !uid.isEmpty else { return false }
        return defaults.bool(forKey: key(for: uid))
    }

    func setEnabled(_ enabled: Bool, for userId: String?) {
        guard let uid = userId, !uid.isEmpty else { return }
        defaults.set(enabled, forKey: key(for: uid))
        if uid == activeUserId {
            isEnabledForActiveUser = enabled
        }
    }

    func biometryName() -> String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometrie"
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Abbrechen"
        context.localizedFallbackTitle = "Code verwenden"
        var error: NSError?

        // deviceOwnerAuthentication erlaubt Face/Touch ID mit Passcode-Fallback
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            biometricsAvailable = false
            biometryType = context.biometryType
            return false
        }

        biometricsAvailable = true
        biometryType = context.biometryType

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    private func key(for uid: String) -> String {
        "\(keyPrefix)\(uid)"
    }
}
