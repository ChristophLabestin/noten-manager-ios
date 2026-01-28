// SupportAccessRequestSheet.swift
import SwiftUI
import FirebaseAuth

/// Sheet for requesting or managing admin support access to user data.
struct SupportAccessRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var message: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?
    @State private var showConfirmGrant: Bool = false
    @State private var showConfirmRevoke: Bool = false
    
    // Notification preferences
    @State private var notifyByPush: Bool = true
    @State private var notifyByEmail: Bool = true
    @State private var notificationEmail: String = ""
    
    // Data access permissions
    @State private var allowGradeDecryption: Bool = false
    
    private var hasActiveAccess: Bool {
        store.adminAccessGranted && (store.adminAccessExpiresAt ?? .distantPast) > Date()
    }
    
    private var remainingTime: String {
        guard let expires = store.adminAccessExpiresAt else { return "—" }
        let remaining = expires.timeIntervalSince(Date())
        if remaining <= 0 { return "Abgelaufen" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) Minuten"
    }
    
    private var formValid: Bool {
        let hasMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
        let hasNotificationMethod = notifyByPush || notifyByEmail
        let emailValid = !notifyByEmail || !notificationEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasMessage && hasNotificationMethod && emailValid
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if hasActiveAccess {
                        activeAccessCard
                    } else {
                        requestAccessCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
            .alert("Zugriff gewähren?", isPresented: $showConfirmGrant) {
                Button("Abbrechen", role: .cancel) {}
                Button("Bestätigen") {
                    Task { await grantAccess() }
                }
            } message: {
                Text("Du gewährst dem Support-Team 24 Stunden Zugriff auf deine Daten. Du kannst den Zugriff jederzeit widerrufen.")
            }
            .alert("Zugriff widerrufen?", isPresented: $showConfirmRevoke) {
                Button("Abbrechen", role: .cancel) {}
                Button("Widerrufen", role: .destructive) {
                    Task { await revokeAccess() }
                }
            } message: {
                Text("Der Support-Zugriff wird sofort beendet.")
            }
            .onAppear {
                // Pre-fill email from user account if available
                if notificationEmail.isEmpty {
                    notificationEmail = Auth.auth().currentUser?.email ?? ""
                }
            }
        }
    }
    
    // MARK: - Cards
    
    private var activeAccessCard: some View {
        SettingsCard(
            title: "Zugriff aktiv",
            subtitle: "Support-Team kann deine Daten einsehen",
            systemImage: "person.badge.key.fill",
            accent: .green
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                                .font(.title3.weight(.semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Zugriff gewährt")
                                .font(.headline)
                            Text("Verbleibend: \(remainingTime)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    
                    Text("Das Support-Team kann deine Daten einsehen, um dein Problem zu beheben. Der Zugriff endet automatisch nach 24 Stunden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showConfirmRevoke = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.shield.fill")
                                .font(.subheadline.weight(.semibold))
                            Text("Zugriff widerrufen")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                }
            }
        }
    }
    
    private var requestAccessCard: some View {
        SettingsCard(
            title: "Support-Zugriff anfordern",
            subtitle: "Bei Problemen mit deinen Daten",
            systemImage: "person.badge.key.fill",
            accent: .indigo
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Wenn du ein Problem hast, das wir nur durch Einsicht in deine Daten lösen können, kannst du uns temporär Zugriff gewähren.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beschreibe dein Problem")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text("mind. 10 Zeichen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Notification preferences section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Benachrichtigung bei Lösung")
                            .font(.subheadline.weight(.semibold))
                        
                        Toggle(isOn: $notifyByPush) {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundStyle(.orange)
                                Text("Push-Benachrichtigung")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .indigo))
                        
                        Toggle(isOn: $notifyByEmail) {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                    .foregroundStyle(.blue)
                                Text("E-Mail")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .indigo))
                        
                        if notifyByEmail {
                            TextField("E-Mail-Adresse", text: $notificationEmail)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .padding(12)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        
                        if !notifyByPush && !notifyByEmail {
                            Text("Bitte wähle mindestens eine Benachrichtigungsmethode.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Data access permissions section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Datenzugriff")
                            .font(.subheadline.weight(.semibold))
                        
                        Toggle(isOn: $allowGradeDecryption) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open.fill")
                                    .foregroundStyle(.purple)
                                Text("Notenwerte entschlüsseln")
                                    .font(.subheadline)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .purple))
                        
                        Text("Erlaubt dem Support, deine Notenwerte zu sehen. Ohne diese Option sind Noten nur verschlüsselt sichtbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                            Text("Zugriff gilt für max. 24 Stunden")
                                .font(.footnote)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundStyle(.blue)
                            Text("Du kannst jederzeit widerrufen")
                                .font(.footnote)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Automatisches Ende nach Lösung")
                                .font(.footnote)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    Button {
                        showConfirmGrant = true
                    } label: {
                        HStack(spacing: 8) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "key.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(isSubmitting ? "Wird aktiviert…" : "Zugriff gewähren")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(!formValid || isSubmitting)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func grantAccess() async {
        guard formValid else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await store.grantAdminAccess(
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                notifyByPush: notifyByPush,
                notifyByEmail: notifyByEmail,
                email: notifyByEmail ? notificationEmail.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                allowGradeDecryption: allowGradeDecryption
            )
            message = ""
            // Sheet stays open to show active access state
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isSubmitting = false
    }
    
    private func revokeAccess() async {
        isSubmitting = true
        errorMessage = nil
        do {
            try await store.revokeAdminAccess()
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
        }
        isSubmitting = false
    }
}
