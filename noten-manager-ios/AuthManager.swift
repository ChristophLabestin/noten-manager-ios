import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

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

    var currentUser: User? {
        Auth.auth().currentUser
    }

    private var authHandle: AuthStateDidChangeListenerHandle?

    func startListeningAuthState() {
        if authHandle != nil { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isAuthenticated = (user != nil)
            if let uid = user?.uid, OfflineModeManager.shared.isOnline {
                OfflineModeManager.shared.recordOnlineLogin(uid: uid)
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
            await MainActor.run { self.isLoading = false }
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
            let profile = UserProfile(id: uid, name: name, email: email, encryptionSalt: saltB64)
            try await FirestoreService.shared.setUserProfile(profile: profile, onboardingCompleted: false)
            OfflineModeManager.shared.recordOnlineLogin(uid: uid)

            await MainActor.run { self.isLoading = false }
        } catch {
            await MainActor.run {
                self.errorMessage = self.mapAuthError(error)
                self.isLoading = false
            }
        }
    }

    func sendVerificationEmail() async -> String? {
        guard let user = Auth.auth().currentUser else { return "Kein angemeldeter Nutzer." }
        do {
            try await user.sendEmailVerification()
            return nil
        } catch {
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
            await MainActor.run {
                self.isLoading = false
                self.isAuthenticated = true
            }
            return .success
        } catch {
            await MainActor.run {
                self.errorMessage = self.mapAuthError(error)
                self.isLoading = false
            }
            return .failure
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            OfflineModeManager.shared.clearOfflineData()
        } catch {
            self.errorMessage = "Abmelden fehlgeschlagen: \(error.localizedDescription)"
        }
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
}
