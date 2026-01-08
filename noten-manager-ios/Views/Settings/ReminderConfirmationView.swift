import SwiftUI

struct ReminderConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme

    private var accentColor: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : Color(hex: "#2563eb")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Card 1: Success Confirmation
                        SettingsCard(
                            title: "Erinnerung gesetzt",
                            subtitle: "Später entscheiden",
                            systemImage: "bell.badge.fill",
                            accent: .orange
                        ) {
                            SettingsSectionBox {
                                Text("Deine Wahl wurde erfolgreich gespeichert. Wir lassen dir den Vortritt und melden uns später.")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .softFadeIn(enabled: store.animationsEnabled, delay: 0.05, offset: 12)

                        // Card 2: Timing Details
                        SettingsCard(
                            title: "Terminierung",
                            subtitle: "Januar 2026",
                            systemImage: "calendar.badge.clock",
                            accent: .indigo
                        ) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Wir werden dich am **24. Januar 2026** (7 Tage vorher) und am **31. Januar 2026** rechtzeitig an das exklusive Early-Bird Angebot erinnern.")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)

                                    HStack(spacing: 8) {
                                        Image(systemName: "sparkles")
                                            .foregroundStyle(.orange)
                                        Text("Inklusive aller Pro-Features")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .softFadeIn(enabled: store.animationsEnabled, delay: 0.12, offset: 12)

                        Spacer(minLength: 20)

                        // Action Buttons
                        VStack(spacing: 12) {
                            Button {
                                dismiss()
                            } label: {
                                Text("Alles klar")
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: accentColor))

                            Button {
                                LaunchOfferNotificationManager.disableReminders()
                                dismiss()
                            } label: {
                                Text("Erinnerungen deaktivieren")
                                    .font(.footnote)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .secondary))
                        }
                        .softFadeIn(enabled: store.animationsEnabled, delay: 0.20, offset: 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .sheetNavigationTitle("Bestätigung")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
    }
}

#Preview {
    ReminderConfirmationView()
        .environmentObject(GradesStore())
}

#Preview {
    ReminderConfirmationView()
        .environmentObject(GradesStore())
}
