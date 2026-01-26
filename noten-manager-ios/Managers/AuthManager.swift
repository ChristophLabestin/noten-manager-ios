import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import SwiftUI


enum SignInResult {
    case success
    case wrongPassword
    case failure
}

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isNewRegistration: Bool = false

    var currentUser: User? {
        Auth.auth().currentUser
    }

    init() {
        if Auth.auth().currentUser != nil {
            self.isAuthenticated = true
        }
    }

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var appleAuthHandler: AppleAuthHandler?

    func startListeningAuthState() {
        if authHandle != nil { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            withAnimation {
                self?.isAuthenticated = (user != nil)
            }
            if let uid = user?.uid, OfflineModeManager.shared.isOnline {
                OfflineModeManager.shared.recordOnlineLogin(uid: uid)
            }
            if user != nil {
                FcmTokenManager.syncCachedTokenIfPossible()
                FcmTokenManager.refreshAndSyncCurrentToken()
            }

        }
    }

    @MainActor deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // Login
    func signIn(email: String, password: String) async -> SignInResult {
        guard !isLoading else { return .failure }
        await MainActor.run { self.isLoading = true; self.errorMessage = nil }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            OfflineModeManager.shared.recordOnlineLogin(uid: result.user.uid)
            await MainActor.run {
                withAnimation {
                    self.isLoading = false
                }
            }

            return .success
        } catch {
            var outcome: SignInResult = .failure
            if let authError = AuthErrorCode(_bridgedNSError: error as NSError),
               authError.code == .wrongPassword {
                outcome = .wrongPassword
            }
            await MainActor.run {
                self.errorMessage = self.mapAuthError(error)
                self.isLoading = false
            }
            await ErrorLoggingService.logError(error, context: ["flow": "signIn"])
            return outcome
        }
    }

    // Registrierung
    func signUp(name: String, email: String, password: String) async {
        guard !isLoading else { return }
        await MainActor.run { self.isLoading = true; self.errorMessage = nil }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            try? await result.user.sendEmailVerification()
            let uid = result.user.uid

            let saltB64 = CryptoService.generateSalt(length: 16)
            var profile = UserProfile(id: uid, name: name, email: email, encryptionSalt: saltB64)
            profile.registeredInVersion = "1.3"
            profile.registrationPlatform = "ios"
            try await FirestoreService.shared.setUserProfile(profile: profile, onboardingCompleted: false)
            OfflineModeManager.shared.recordOnlineLogin(uid: uid)

            await MainActor.run {
                withAnimation {
                    self.isNewRegistration = true
                    self.isLoading = false
                }
            }

        } catch {
            await MainActor.run {
                self.errorMessage = self.mapAuthError(error)
                self.isLoading = false
            }
            await ErrorLoggingService.logError(error, context: ["flow": "signUp"])
        }
    }

    func sendVerificationEmail() async -> String? {
        guard let user = Auth.auth().currentUser else { return "Kein angemeldeter Nutzer." }
        do {
            try await user.sendEmailVerification()
            return nil
        } catch {
            await ErrorLoggingService.logError(error, context: ["flow": "sendVerificationEmail"])
            return mapAuthError(error)
        }
    }

    // Passwort zurücksetzen
    func resetPassword(email: String) async {
        guard !isLoading else { return }
        await MainActor.run { self.isLoading = true; self.errorMessage = nil }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            await MainActor.run { self.isLoading = false }
        } catch {
            await MainActor.run {
                self.errorMessage = self.mapAuthError(error)
                self.isLoading = false
            }
            await ErrorLoggingService.logError(error, context: ["flow": "resetPassword"])
        }
    }

    @MainActor
    func signInWithGoogle(presenting viewController: UIViewController?) async -> SignInResult {
        guard !isLoading else { return .failure }
        guard let viewController else {
            errorMessage = "Kein aktives Fenster für Google Login gefunden."
            return .failure
        }
        await MainActor.run { self.isLoading = true; self.errorMessage = nil }
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                await MainActor.run {
                    self.errorMessage = "Google Client ID fehlt."
                    self.isLoading = false
                }
                return .failure
            }

            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            guard let idToken = result.user.idToken?.tokenString else {
                await MainActor.run {
                    self.errorMessage = "Kein Google Token erhalten."
                    self.isLoading = false
                }
                return .failure
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            let authResult = try await Auth.auth().signIn(with: credential)
            OfflineModeManager.shared.recordOnlineLogin(uid: authResult.user.uid)
            
            if authResult.additionalUserInfo?.isNewUser == true {
                let salt = CryptoService.generateSalt(length: 16)
                var profile = UserProfile(
                    id: authResult.user.uid,
                    name: authResult.user.displayName ?? "Google Nutzer",
                    email: authResult.user.email ?? "",
                    encryptionSalt: salt
                )
                profile.registeredInVersion = "1.3"
                profile.registrationPlatform = "ios"
                try? await FirestoreService.shared.setUserProfile(profile: profile, onboardingCompleted: false)
            }

            await MainActor.run {
                withAnimation {
                    self.isLoading = false
                    self.isNewRegistration = authResult.additionalUserInfo?.isNewUser == true
                    self.isAuthenticated = true
                }
            }

            return .success
        } catch {
            await MainActor.run {
                self.errorMessage = self.mapAuthError(error)
                self.isLoading = false
            }
            await ErrorLoggingService.logError(error, context: ["flow": "signInWithGoogle"])
            return .failure
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            OfflineModeManager.shared.clearOfflineData()
            withAnimation {
                self.isNewRegistration = false
            }
        } catch {
            self.errorMessage = "Abmelden fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // Apple Sign-In
    @MainActor
    func signInWithApple(presentationAnchor: ASPresentationAnchor?) async -> SignInResult {
        guard !isLoading else { return .failure }
        guard let anchor = presentationAnchor else {
            errorMessage = "Kein Fenster für Apple Login gefunden."
            return .failure
        }
        isLoading = true
        errorMessage = nil

        let rawNonce = randomNonceString()
        do {
            let appleCredential = try await performAppleAuthorization(
                anchor: anchor,
                hashedNonce: sha256(rawNonce)
            )
            return await completeAppleSignIn(appleCredential: appleCredential, rawNonce: rawNonce)
        } catch {
            isLoading = false
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return .failure
            }
            if error is ASAuthorizationError {
                errorMessage = "Apple Login fehlgeschlagen: \(error.localizedDescription)"
            } else {
                errorMessage = mapAuthError(error)
            }
            await ErrorLoggingService.logError(error, context: ["flow": "signInWithApple"])
            return .failure
        }
    }

    @MainActor
    func signInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async -> SignInResult {
        guard !isLoading else { return .failure }
        isLoading = true
        errorMessage = nil
        return await completeAppleSignIn(appleCredential: credential, rawNonce: rawNonce)
    }

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) -> String {
        let nonce = randomNonceString()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        return nonce
    }

    private func mapAuthError(_ error: Error) -> String {
        let ns = error as NSError

        // Nutze ausschließlich das Bridging; falls das fehlschlägt, Standardtext zurückgeben
        if let authError = AuthErrorCode(_bridgedNSError: ns) {
            switch authError.code {
            case .invalidEmail:
                return "Ungültige E-Mail-Adresse."
            case .wrongPassword:
                return "Falsches Passwort."
            case .invalidCredential:
                return "Anmeldedaten ungültig. Bitte E-Mail und Passwort prüfen."
            case .userNotFound:
                return "Kein Benutzer mit dieser E-Mail gefunden."
            case .emailAlreadyInUse:
                return "Diese E-Mail wird bereits verwendet."
            case .weakPassword:
                return "Passwort ist zu schwach."
            case .networkError:
                return "Netzwerkfehler. Bitte später erneut versuchen."
            default:
                return "Anmeldung fehlgeschlagen. Bitte E-Mail/Passwort prüfen oder später erneut versuchen."
            }
        } else {
            return "Anmeldung fehlgeschlagen. Bitte E-Mail/Passwort prüfen oder später erneut versuchen."
        }
    }

    private func performAppleAuthorization(anchor: ASPresentationAnchor, hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            let handler = AppleAuthHandler(anchor: anchor) { [weak self] result in
                continuation.resume(with: result)
                self?.appleAuthHandler = nil
            }
            appleAuthHandler = handler

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = hashedNonce

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = handler
            controller.presentationContextProvider = handler
            controller.performRequests()
        }
    }

    @MainActor
    private func completeAppleSignIn(appleCredential: ASAuthorizationAppleIDCredential, rawNonce: String) async -> SignInResult {
        guard let idTokenData = appleCredential.identityToken,
              let idTokenString = String(data: idTokenData, encoding: .utf8) else {
            errorMessage = "Apple-Token fehlt."
            isLoading = false
            return .failure
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: rawNonce,
            fullName: appleCredential.fullName
        )

        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            OfflineModeManager.shared.recordOnlineLogin(uid: authResult.user.uid)

            if authResult.additionalUserInfo?.isNewUser == true {
                let formatter = PersonNameComponentsFormatter()
                let fullNameString = appleCredential.fullName.flatMap { formatter.string(from: $0) }
                let trimmedName = fullNameString?.trimmingCharacters(in: .whitespacesAndNewlines)
                let email = authResult.user.email
                    ?? appleCredential.email
                    ?? "\(authResult.user.uid)@privaterelay.appleid.com"
                let resolvedName = (trimmedName?.isEmpty == false ? trimmedName : nil)
                    ?? authResult.user.displayName
                    ?? email.components(separatedBy: "@").first
                    ?? "Apple Nutzer"

                let salt = CryptoService.generateSalt(length: 16)
                var profile = UserProfile(
                    id: authResult.user.uid,
                    name: resolvedName,
                    email: email,
                    encryptionSalt: salt
                )
                profile.registeredInVersion = "1.3"
                profile.registrationPlatform = "ios"
                try? await FirestoreService.shared.setUserProfile(
                    profile: profile,
                    onboardingCompleted: false
                )
            }

            withAnimation {
                isLoading = false
                isNewRegistration = authResult.additionalUserInfo?.isNewUser == true
                isAuthenticated = true
            }

            return .success
        } catch {
            isLoading = false
            errorMessage = mapAuthError(error)
            await ErrorLoggingService.logError(error, context: ["flow": "completeAppleSignIn"])
            return .failure
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        guard length > 0 else { return "" }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        for _ in 0..<length {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status != errSecSuccess {
                // Fallback to a weaker source instead of crashing; still better than aborting login flow.
                random = UInt8.random(in: 0..<UInt8.max)
            }
            result.append(charset[Int(random % UInt8(charset.count))])
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

private final class AppleAuthHandler: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private let completion: (Result<ASAuthorizationAppleIDCredential, Error>) -> Void

    init(anchor: ASPresentationAnchor, completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.anchor = anchor
        self.completion = completion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            completion(.success(credential))
        } else {
            completion(.failure(NSError(domain: "AppleAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültige Apple-Credential"])))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
}
