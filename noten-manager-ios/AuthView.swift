// AuthView.swift
import SwiftUI

struct AuthView: View {
    @ObservedObject var authManager: AuthManager

    @Environment(\.colorScheme) private var colorScheme

    @State private var isLoginTab: Bool = true

    // Login Felder
    @State private var loginEmail: String = ""
    @State private var loginPassword: String = ""
    @State private var rememberMe: Bool = true

    // Register Felder
    @State private var registerName: String = ""
    @State private var registerEmail: String = ""
    @State private var registerPassword: String = ""
    @State private var registerPasswordConfirm: String = ""

    // Reset
    @State private var resetEmail: String = ""
    @State private var showResetSheet: Bool = false
    @State private var resetInfo: String?

    // Farben aus variables.scss (vereinfacht)
    private var primaryColor: Color { Color(hex: "#1e3a8a") }
    private var primaryHoverColor: Color { Color(hex: "#2563eb") }
    private var textDarkColor: Color { Color(hex: "#111827") }
    private var textMediumColor: Color { Color(hex: "#6b7280") }
    private var errorColor: Color { Color(hex: "#dc2626") }

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(hex: "#1f2937") : .white
    }

    private var cardShadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.7) : Color.black.opacity(0.18)
    }

    private var tabsBackgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255).opacity(0.9)
            : Color(red: 238 / 255, green: 241 / 255, blue: 246 / 255)
    }

    private var inputBackgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color(red: 180 / 255, green: 180 / 255, blue: 180 / 255, opacity: 0.4)
    }

    private var inputTextColor: Color {
        colorScheme == .dark ? Color(hex: "#f9fafb") : textDarkColor
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 16) {
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
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(cardBackgroundColor)
                .cornerRadius(32)
                .shadow(color: cardShadowColor, radius: 32, x: 0, y: 18)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .sheet(isPresented: $showResetSheet) {
            resetSheet
        }
        .onChange(of: isLoginTab) { _ in
            authManager.errorMessage = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isLoginTab ? "Account anmelden" : "Konto erstellen")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(textDarkColor)
            Text(isLoginTab
                 ? "Melde dich mit deinen Zugangsdaten an."
                 : "Registriere dich für den Noten Manager.")
            .font(.subheadline)
            .foregroundStyle(textMediumColor)
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            authTabButton(title: "Login", isActive: isLoginTab) {
                isLoginTab = true
            }
            authTabButton(title: "Registrieren", isActive: !isLoginTab) {
                isLoginTab = false
            }
        }
        .padding(4)
        .background(tabsBackgroundColor)
        .clipShape(Capsule())
    }

    private func authTabButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isActive ? Color.white : Color.clear)
                .foregroundStyle(isActive ? textDarkColor : textMediumColor)
                .clipShape(Capsule())
                .shadow(color: isActive ? Color.black.opacity(0.16) : .clear,
                        radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var loginForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Email:")
                    .font(.footnote)
                    .foregroundStyle(textMediumColor)
                TextField("example@email.com", text: $loginEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(inputBackgroundColor)
                    .foregroundStyle(inputTextColor)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Passwort:")
                    .font(.footnote)
                    .foregroundStyle(textMediumColor)
                SecureField("********", text: $loginPassword)
                    .textContentType(.password)
                    .padding(10)
                    .background(inputBackgroundColor)
                    .foregroundStyle(inputTextColor)
                    .cornerRadius(10)
            }

            HStack(spacing: 12) {
                Toggle(isOn: $rememberMe) {
                    Text("Eingeloggt bleiben")
                        .font(.footnote)
                        .foregroundStyle(textMediumColor)
                }

                Spacer()

                Button {
                    resetEmail = loginEmail
                    showResetSheet = true
                } label: {
                    Text("Passwort vergessen?")
                        .font(.footnote)
                        .foregroundStyle(primaryHoverColor)
                }
            }

            Button {
                Task {
                    await authManager.signIn(email: loginEmail, password: loginPassword)
                }
            } label: {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Login")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [primaryColor, primaryHoverColor]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(authManager.isLoading || loginEmail.isEmpty || loginPassword.isEmpty)
        }
        .padding(.top, 4)
    }

    private var registerForm: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anzeigename:")
                    .font(.footnote)
                    .foregroundStyle(textMediumColor)
                TextField("Name", text: $registerName)
                    .textContentType(.name)
                    .padding(10)
                    .background(inputBackgroundColor)
                    .foregroundStyle(inputTextColor)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("E-Mail:")
                    .font(.footnote)
                    .foregroundStyle(textMediumColor)
                TextField("example@email.com", text: $registerEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(inputBackgroundColor)
                    .foregroundStyle(inputTextColor)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Passwort:")
                    .font(.footnote)
                    .foregroundStyle(textMediumColor)
                SecureField("********", text: $registerPassword)
                    .textContentType(.newPassword)
                    .padding(10)
                    .background(inputBackgroundColor)
                    .foregroundStyle(inputTextColor)
                    .cornerRadius(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Passwort bestätigen:")
                    .font(.footnote)
                    .foregroundStyle(textMediumColor)
                SecureField("********", text: $registerPasswordConfirm)
                    .textContentType(.newPassword)
                    .padding(10)
                    .background(inputBackgroundColor)
                    .foregroundStyle(inputTextColor)
                    .cornerRadius(10)
            }

            Button {
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
            } label: {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Registrieren")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [primaryColor, primaryHoverColor]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(authManager.isLoading ||
                      registerName.isEmpty ||
                      registerEmail.isEmpty ||
                      registerPassword.isEmpty ||
                      registerPasswordConfirm.isEmpty)
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
                    }.disabled(resetEmail.isEmpty)
                }
            }
        }
    }
}
