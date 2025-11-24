// AuthView.swift
import SwiftUI

struct AuthView: View {
    @ObservedObject var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var isLoginTab: Bool = true

    @State private var loginEmail: String = ""
    @State private var loginPassword: String = ""
    @State private var rememberMe: Bool = true

    @State private var registerName: String = ""
    @State private var registerEmail: String = ""
    @State private var registerPassword: String = ""
    @State private var registerPasswordConfirm: String = ""

    @State private var resetEmail: String = ""
    @State private var showResetSheet: Bool = false
    @State private var resetInfo: String?

    // Farben aus variables.scss
    private var primaryColor: Color { Color(hex: "#1e3a8a") }
    private var primaryHoverColor: Color { Color(hex: "#2563eb") }
    private var primaryDarkColor: Color { Color(hex: "#3b82f6") }
    private var textDarkColor: Color { Color(hex: "#111827") }
    private var textDarkDark: Color { Color(hex: "#f9fafb") }
    private var textMediumColor: Color { Color(hex: "#6b7280") }
    private var textMediumDark: Color { Color(hex: "#d1d5db") }
    private var errorColor: Color { Color(hex: "#dc2626") }

    private var accentPrimary: Color { colorScheme == .dark ? primaryDarkColor : primaryColor }
    private var accentSecondary: Color { colorScheme == .dark ? primaryDarkColor.opacity(0.85) : primaryHoverColor }

    private var labelColor: Color { colorScheme == .dark ? textDarkDark : textDarkColor }
    private var subLabelColor: Color { colorScheme == .dark ? textMediumDark : textMediumColor }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.82),
                Color.black.opacity(colorScheme == .dark ? 0.35 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.12 : 0.25),
                accentPrimary.opacity(0.24)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardShadow: Color { colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.14) }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentPrimary.opacity(colorScheme == .dark ? 0.32 : 0.24),
                Color(hex: "#eef2ff").opacity(colorScheme == .dark ? 0.1 : 0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var pillBackground: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.85) }

    private var inputBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.9),
                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 36)

                    VStack(alignment: .leading, spacing: 20) {
                        header
                        tabs

                        if isLoginTab {
                            loginForm
                        } else {
                            registerForm
                        }

                        if let error = authManager.errorMessage, !error.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(errorColor)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .background(cardBackground)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .shadow(color: cardShadow, radius: 28, x: 0, y: 12)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 18)
                }
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showResetSheet) {
            resetSheet
        }
        .onChange(of: isLoginTab) { _ in
            authManager.errorMessage = nil
        }
        .keyboardDismissToolbar()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentPrimary.opacity(0.92),
                                accentSecondary.opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isLoginTab ? "Account anmelden" : "Konto erstellen")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(labelColor)
                Text(isLoginTab
                     ? "Melde dich mit deinen Zugangsdaten an."
                     : "Registriere dich für den Noten Manager.")
                    .font(.subheadline)
                    .foregroundStyle(subLabelColor)
            }
            Spacer()
        }
    }

    private var tabs: some View {
        HStack(spacing: 8) {
            authTabButton(title: "Login", icon: "person.fill", isActive: isLoginTab) {
                isLoginTab = true
            }
            authTabButton(title: "Registrieren", icon: "sparkles", isActive: !isLoginTab) {
                isLoginTab = false
            }
        }
        .padding(6)
        .background(pillBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22), lineWidth: 1)
        )
    }

    private var loginForm: some View {
        VStack(spacing: 16) {
            InputField(
                title: "Email",
                placeholder: "example@email.com",
                text: $loginEmail,
                icon: "envelope.fill",
                isSecure: false,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor
            )

            InputField(
                title: "Passwort",
                placeholder: "********",
                text: $loginPassword,
                icon: "lock.fill",
                isSecure: true,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor
            )

            HStack(spacing: 12) {
                Toggle(isOn: $rememberMe) {
                    Text("Eingeloggt bleiben")
                        .font(.footnote)
                        .foregroundStyle(subLabelColor)
                }
                .toggleStyle(SwitchToggleStyle(tint: accentPrimary))

                Spacer()

                Button {
                    resetEmail = loginEmail
                    showResetSheet = true
                } label: {
                    Label("Passwort vergessen?", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                        .labelStyle(.titleOnly)
                        .foregroundStyle(accentPrimary)
                }
            }

            PrimaryButton(
                title: "Login",
                isLoading: authManager.isLoading,
                disabled: authManager.isLoading || loginEmail.isEmpty || loginPassword.isEmpty
            ) {
                Task {
                    await authManager.signIn(email: loginEmail, password: loginPassword)
                }
            }
        }
        .padding(.top, 4)
    }

    private var registerForm: some View {
        VStack(spacing: 16) {
            InputField(
                title: "Anzeigename",
                placeholder: "Name",
                text: $registerName,
                icon: "person.crop.circle.fill",
                isSecure: false,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor
            )

            InputField(
                title: "E-Mail",
                placeholder: "example@email.com",
                text: $registerEmail,
                icon: "envelope.fill",
                isSecure: false,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor
            )

            InputField(
                title: "Passwort",
                placeholder: "********",
                text: $registerPassword,
                icon: "lock.fill",
                isSecure: true,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor
            )

            InputField(
                title: "Passwort bestätigen",
                placeholder: "********",
                text: $registerPasswordConfirm,
                icon: "checkmark.shield.fill",
                isSecure: true,
                background: inputBackground,
                labelColor: subLabelColor,
                textColor: labelColor
            )

            PrimaryButton(
                title: "Registrieren",
                isLoading: authManager.isLoading,
                disabled: authManager.isLoading ||
                          registerName.isEmpty ||
                          registerEmail.isEmpty ||
                          registerPassword.isEmpty ||
                          registerPasswordConfirm.isEmpty
            ) {
                guard registerPassword == registerPasswordConfirm else {
                    authManager.errorMessage = "Passwörter stimmen nicht überein."
                    return
                }
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

    private var resetSheet: some View {
        NavigationStack {
            Form {
                Section("E-Mail für Passwort-Reset") {
                    TextField("E-Mail", text: $resetEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                        Task {
                            await authManager.resetPassword(email: resetEmail)
                            resetInfo = "E-Mail zum Zurücksetzen wurde gesendet (falls Konto existiert)."
                        }
                    }
                    .disabled(resetEmail.isEmpty)
                }
            }
            .keyboardDismissToolbar()
        }
    }

    private func authTabButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? tabActiveGradient : tabInactiveGradient)
            )
            .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isActive ? Color.white.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isActive ? Color.black.opacity(0.15) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
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

private var tabInactiveGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color.clear,
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
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

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(labelColor)

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.05),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(labelColor)
                }

                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(textColor)
                        .focused($focused)
                } else {
                    TextField(placeholder, text: $text)
                        .textContentType(.emailAddress)
                        .keyboardType(title.lowercased().contains("mail") ? .emailAddress : .default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(textColor)
                        .focused($focused)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: focused ? 1.2 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: focused ? 10 : 6, x: 0, y: 4)
        }
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
            .padding(.vertical, 12)
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
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.7 : 1.0)
    }
}
