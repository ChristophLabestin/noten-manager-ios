// AuthView.swift
import SwiftUI
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit
import LocalAuthentication
import AuthenticationServices

enum AuthField: Hashable {
    case loginEmail, loginPassword
    case registerName, registerEmail, registerPassword
}

struct AuthView: View {
    @ObservedObject var authManager: AuthManager
    @EnvironmentObject var biometricManager: BiometricAuthManager
    @EnvironmentObject var offlineManager: OfflineModeManager
    @Environment(\.colorScheme) private var colorScheme

    @Namespace private var tabNamespace

    @State private var isLoginTab: Bool = true

    @State private var loginEmail: String = ""
    @State private var loginPassword: String = ""
    @State private var enableBiometricLogin: Bool = false
    @State private var applyBiometricAfterLogin: Bool = false
    @State private var biometricOptionAvailable: Bool = false
    @State private var loginFailedAttempts: Int = 0

    @State private var registerName: String = ""
    @State private var registerEmail: String = ""
    @State private var registerPassword: String = ""
    @State private var resetEmail: String = ""
    @State private var showResetSheet: Bool = false
    @State private var resetInfo: String?
    @State private var appleNonce: String?

    @FocusState private var activeField: AuthField?

    // Farben aus variables.scss
    private var primaryColor: Color { Color(hex: "#1e3a8a") }
    private var primaryDarkColor: Color { Color(hex: "#3b82f6") }
    private var textDarkColor: Color { Color(hex: "#111827") }
    private var textDarkDark: Color { Color(hex: "#f9fafb") }
    private var textMediumColor: Color { Color(hex: "#6b7280") }
    private var textMediumDark: Color { Color(hex: "#d1d5db") }
    private var errorColor: Color { Color(hex: "#dc2626") }

    private var accentPrimary: Color { colorScheme == .dark ? primaryDarkColor : primaryColor }
    private var labelColor: Color { colorScheme == .dark ? textDarkDark : textDarkColor }
    private var subLabelColor: Color { colorScheme == .dark ? textMediumDark : textMediumColor }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentPrimary.opacity(colorScheme == .dark ? 0.32 : 0.16),
                Color(hex: "#0b1021").opacity(colorScheme == .dark ? 0.82 : 0.12),
                Color(hex: "#eef2ff").opacity(colorScheme == .dark ? 0.12 : 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backgroundLayers: some View {
        ZStack {
            backgroundGradient
            Circle()
                .fill(accentPrimary.opacity(colorScheme == .dark ? 0.35 : 0.25))
                .frame(width: 360, height: 360)
                .blur(radius: 130)
                .offset(x: -120, y: -210)

            Circle()
                .fill(Color(hex: "#f59e0b").opacity(colorScheme == .dark ? 0.25 : 0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 150)
                .offset(x: 180, y: 120)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.28),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
        }
    }

    private var pillBackground: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82) }

    private var inputBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.07 : 0.98),
                Color.white.opacity(colorScheme == .dark ? 0.03 : 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var currentFields: [AuthField] {
        isLoginTab
        ? [.loginEmail, .loginPassword]
        : [.registerName, .registerEmail, .registerPassword]
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayers
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    formCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .hideKeyboardOnTap()
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .sheet(isPresented: $showResetSheet) {
            resetSheet
        }
        .onChange(of: isLoginTab) { _, _ in
            authManager.errorMessage = nil
            loginFailedAttempts = 0
            activeField = nil
        }
        .onAppear {
            KeyboardToolbarAppearance.configure()
            biometricManager.refreshAvailability()
            biometricOptionAvailable = biometricManager.biometricsAvailable
            let lastId = offlineManager.lastLoginUserId ?? offlineManager.cachedSnapshot?.userId
            enableBiometricLogin = biometricManager.isEnabled(for: lastId)
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuth in
            if isAuth && applyBiometricAfterLogin {
                let uid = authManager.currentUser?.uid ?? offlineManager.lastLoginUserId ?? offlineManager.cachedSnapshot?.userId
                biometricManager.setActiveUser(id: uid)
                biometricManager.setEnabled(true, for: uid)
                applyBiometricAfterLogin = false
            }
            if !isAuth {
                applyBiometricAfterLogin = false
            }
        }
        .keyboardNavigationToolbar(
            focus: $activeField,
            fields: currentFields,
            label: "Tastatur schließen",
            onDone: { hideKeyboard() }
        )
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            authHeader
            tabs

            if isLoginTab {
                loginForm
            } else {
                registerForm
            }

            if let error = authManager.errorMessage, !error.isEmpty {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(errorColor)
                        .font(.footnote.weight(.bold))
                    Text(error)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(errorColor)
                    Spacer()
                }
                .padding(12)
                .background(errorColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            socialLoginSection

            HStack(spacing: 10) {
                Image(systemName: "shield.checkerboard")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accentPrimary)
                Text("Daten werden verschlüsselt synchronisiert und bleiben auf allen Geräten geschützt.")
                    .font(.caption)
                    .foregroundStyle(subLabelColor)
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private var authHeader: some View {
        VStack(spacing: 10) {
            authHero
            Text(isLoginTab ? "Willkommen zurück" : "Neuer Account")
                .font(.title2.weight(.bold))
                .foregroundStyle(labelColor)
                .multilineTextAlignment(.center)
            Text(isLoginTab
                 ? "Melde dich an und synchronisiere deine Noten."
                 : "Erstelle dein Konto, sichere deine Leistungen.")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(subLabelColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    private var authHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(colorScheme == .dark ? 0.55 : 0.35),
                            Color.cyan.opacity(colorScheme == .dark ? 0.28 : 0.22),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(colorScheme == .dark ? 2 : -2))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.38),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.1
                )
                .frame(width: 98, height: 98)

            Image("AppIconPreviewDefault")
                .resizable()
                .scaledToFit()
                .frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18),
                    radius: 10,
                    x: 0,
                    y: 6
                )
        }
    }

    private var tabs: some View {
        HStack(spacing: 10) {
            authTabButton(title: "Login", icon: "person.fill", isActive: isLoginTab) {
                isLoginTab = true
            }
            authTabButton(title: "Registrieren", icon: "sparkles", isActive: !isLoginTab) {
                isLoginTab = false
            }
        }
        .padding(6)
        .background(pillBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var loginForm: some View {
        VStack(spacing: 8) {
            InputField(
                title: "E-Mail",
                placeholder: "example@email.com",
                text: $loginEmail,
                icon: "envelope.fill",
                isSecure: false,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor,
                accent: accentPrimary,
                field: .loginEmail,
                focus: $activeField,
                allowsReveal: false
            )

            InputField(
                title: "Passwort",
                placeholder: "********",
                text: $loginPassword,
                icon: "lock.fill",
                isSecure: true,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor,
                accent: accentPrimary,
                field: .loginPassword,
                focus: $activeField,
                allowsReveal: true
            )

            VStack(spacing: 8) {
                if biometricOptionAvailable {
                    biometricToggleRow
                }

                if loginFailedAttempts >= 2 {
                    Button {
                        resetEmail = loginEmail
                        showResetSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.footnote.weight(.semibold))
                            Text("Passwort vergessen?")
                                .font(.footnote.weight(.semibold))
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accentPrimary)
                }
            }

            PrimaryButton(
                title: "Login",
                isLoading: authManager.isLoading,
                disabled: authManager.isLoading || loginEmail.isEmpty || loginPassword.isEmpty
            ) {
                applyBiometricAfterLogin = biometricOptionAvailable && enableBiometricLogin
                Task {
                    let result = await authManager.signIn(email: loginEmail, password: loginPassword)
                    switch result {
                    case .success:
                        loginFailedAttempts = 0
                    case .wrongPassword, .failure:
                        loginFailedAttempts += 1
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var registerForm: some View {
        VStack(spacing: 8) {
            InputField(
                title: "Anzeigename",
                placeholder: "Name",
                text: $registerName,
                icon: "person.crop.circle.fill",
                isSecure: false,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor,
                accent: accentPrimary,
                field: .registerName,
                focus: $activeField,
                allowsReveal: false
            )

            InputField(
                title: "E-Mail",
                placeholder: "example@email.com",
                text: $registerEmail,
                icon: "envelope.fill",
                isSecure: false,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor,
                accent: accentPrimary,
                field: .registerEmail,
                focus: $activeField,
                allowsReveal: false
            )

            InputField(
                title: "Passwort",
                placeholder: "********",
                text: $registerPassword,
                icon: "lock.fill",
                isSecure: true,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor,
                accent: accentPrimary,
                field: .registerPassword,
                focus: $activeField,
                allowsReveal: true,
                textContentType: .newPassword
            )

            PrimaryButton(
                title: "Registrieren",
                isLoading: authManager.isLoading,
                disabled: authManager.isLoading ||
                          registerName.isEmpty ||
                          registerEmail.isEmpty ||
                          registerPassword.isEmpty
            ) {
                Task {
                    await authManager.signUp(
                        name: registerName,
                        email: registerEmail,
                        password: registerPassword
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    private var socialLoginSection: some View {
        VStack(spacing: 10) {
            HStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                Text("oder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(subLabelColor)
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
            }

            VStack(spacing: 10) {
                SignInWithAppleButton(.signIn) { request in
                    appleNonce = authManager.configureAppleRequest(request)
                } onCompletion: { result in
                    switch result {
                    case .success(let auth):
                        guard
                            let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                            let nonce = appleNonce
                        else {
                            appleNonce = nil
                            authManager.errorMessage = "Apple Login fehlgeschlagen. Bitte erneut versuchen."
                            return
                        }
                        appleNonce = nil
                        Task { await authManager.signInWithApple(credential: credential, rawNonce: nonce) }
                    case .failure(let error):
                        appleNonce = nil
                        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                            return
                        }
                        authManager.errorMessage = "Apple Login fehlgeschlagen: \(error.localizedDescription)"
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .disabled(authManager.isLoading)
                .opacity(authManager.isLoading ? 0.7 : 1)

                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        Image("GoogleIcon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                        Text("Mit Google anmelden")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(Color(hex: "#3c4043"))
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Color(hex: "#dadce0"), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(authManager.isLoading)
                .opacity(authManager.isLoading ? 0.7 : 1)
            }
        }
        .padding(.top, 6)
    }

    private func signInWithGoogle() async {
        guard let presenter = topViewController() else {
            authManager.errorMessage = "Kein Fenster für Google Login gefunden."
            return
        }
        _ = await authManager.signInWithGoogle(presenting: presenter)
    }

    private func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC = base
            ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
                .windows.first { $0.isKeyWindow }?
                .rootViewController

        if let nav = baseVC as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = baseVC?.presentedViewController {
            return topViewController(base: presented)
        }
        return baseVC
    }

    private var resetSheet: some View {
        NavigationStack {
            Form {
                Section("E-Mail für Passwort-Reset") {
                    TextField("E-Mail", text: $resetEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Wir senden dir einen Link zum Zurücksetzen an diese Adresse.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let info = resetInfo {
                    Text(info).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Passwort zurücksetzen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showResetSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") {
                        let email = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !email.isEmpty else {
                            resetInfo = "Bitte gib deine E-Mail ein."
                            return
                        }
                        Task {
                            await authManager.resetPassword(email: email)
                            resetInfo = "E-Mail zum Zurücksetzen wurde gesendet (falls Konto existiert)."
                        }
                    }
                    .disabled(authManager.isLoading)
                }
            }
            .keyboardDismissToolbar()
            .onAppear {
                if resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resetEmail = loginEmail
                }
            }
        }
    }

    private func authTabButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                action()
            }
        } label: {
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tabActiveGradient)
                        .matchedGeometryEffect(id: "tabActiveBackground", in: tabNamespace)
                        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
                }

                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
    }

    private var biometricToggleRow: some View {
        HStack(spacing: 10) {
            Text("\(biometricManager.biometryName()) aktivieren")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(labelColor)
            Spacer()
            Toggle("", isOn: $enableBiometricLogin)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: accentPrimary))
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06), lineWidth: 1)
        )
    }
}

// MARK: - Reusable Views

private var tabActiveGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(hex: "#1e3a8a"),
            Color(hex: "#2563eb")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct InputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let icon: String
    let isSecure: Bool
    let background: LinearGradient
    let labelColor: Color
    let textColor: Color
    let accent: Color
    let field: AuthField
    let focus: FocusState<AuthField?>.Binding
    let allowsReveal: Bool
    let textContentType: UITextContentType?

    @State private var isRevealed: Bool = false

    private var isFocused: Bool { focus.wrappedValue == field }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(labelColor)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.08))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Group {
                    if isSecure && !isRevealed {
                        SecureField(placeholder, text: $text)
                            .textContentType(resolvedContentType ?? .password)
                    } else {
                        TextField(placeholder, text: $text)
                            .textContentType(resolvedContentType)
                            .keyboardType(title.lowercased().contains("mail") ? .emailAddress : .default)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(textColor)
                .focused(focus, equals: field)

                if isSecure && allowsReveal {
                    Button {
                        isRevealed.toggle()
                        focus.wrappedValue = field
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(subtleIconColor)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 11)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isFocused
                        ? accent.opacity(0.7)
                        : Color.white.opacity(0.18),
                        lineWidth: isFocused ? 1.4 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: isFocused ? 10 : 5, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                focus.wrappedValue = field
            }
        }
    }

    private var subtleIconColor: Color {
        isFocused ? accent : labelColor.opacity(0.7)
    }

    private var resolvedContentType: UITextContentType? {
        if let explicit = textContentType {
            return explicit
        }
        if title.lowercased().contains("mail") {
            return .emailAddress
        }
        return nil
    }

    init(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        isSecure: Bool,
        background: LinearGradient,
        labelColor: Color,
        textColor: Color,
        accent: Color,
        field: AuthField,
        focus: FocusState<AuthField?>.Binding,
        allowsReveal: Bool = false,
        textContentType: UITextContentType? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.isSecure = isSecure
        self.background = background
        self.labelColor = labelColor
        self.textColor = textColor
        self.accent = accent
        self.field = field
        self.focus = focus
        self.allowsReveal = allowsReveal
        self.textContentType = textContentType
    }
}

private struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: "#1e3a8a"),
                        Color(hex: "#2563eb")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }
}
