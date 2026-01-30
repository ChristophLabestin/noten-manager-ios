// MigrationInfoSheet.swift
import SwiftUI

/// Sheet displayed on first app launch after migration to inform users about data changes
struct MigrationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var store: GradesStore
    
    @State private var showSupportSheet: Bool = false
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header illustration
                    headerSection
                    
                    // Info cards
                    migrationInfoCard
                    
                    checkDataCard
                    
                    supportCard
                    
                    // Confirm button
                    confirmButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .background(
                ThemedBackground(
                    isDark: store.darkMode,
                    isFeminine: store.theme == "feminine",
                    intensity: store.themeBackgroundIntensity
                )
            )
            .navigationTitle("Wichtige Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        store.markMigrationInfoExamined()
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
        .sheet(isPresented: $showSupportSheet) {
            SupportAccessRequestSheet()
                .environmentObject(store)
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.indigo.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Datenmigration abgeschlossen")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            
            Text("Wir haben deine Daten auf das neue System übertragen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Cards
    
    private var migrationInfoCard: some View {
        SettingsCard(
            title: "Was ist passiert?",
            subtitle: "Hintergrund zur Änderung",
            systemImage: "info.circle.fill",
            accent: .blue
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Um dir neue Funktionen und eine bessere Erfahrung bieten zu können, haben wir das Datensystem aktualisiert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Text("Alle deine Noten, Fächer und Einstellungen wurden automatisch migriert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var checkDataCard: some View {
        SettingsCard(
            title: "Bitte überprüfen",
            subtitle: "Checke deine Daten",
            systemImage: "checklist",
            accent: .orange
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    checkItem(icon: "book.fill", text: "Alle Fächer vorhanden?")
                    checkItem(icon: "list.number", text: "Alle Noten korrekt?")
                    checkItem(icon: "calendar", text: "Halbjahre richtig zugeordnet?")
                    checkItem(icon: "star.fill", text: "Prüfungs- und Abiturnoten da?")
                }
            }
        }
    }
    
    private func checkItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(width: 20)
            
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
    
    private var supportCard: some View {
        SettingsCard(
            title: "Etwas fehlt?",
            subtitle: "Wir helfen dir weiter",
            systemImage: "person.fill.questionmark",
            accent: .indigo
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Falls etwas nicht übertragen wurde oder fehlt, kannst du dich jederzeit an unser Support-Team wenden.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Text("Du findest den Support-Kontakt auch jederzeit später in den Einstellungen unter \"Hilfe & Support\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showSupportSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "headphones.circle.fill")
                                .font(.subheadline.weight(.semibold))
                            Text("Support kontaktieren")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                }
            }
        }
    }
    
    // MARK: - Button
    
    private var confirmButton: some View {
        Button {
            store.markMigrationInfoExamined()
            dismiss()
        } label: {
            Text("Alles geprüft, verstanden!")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(SoftTintButtonStyle(accent: .blue))
    }
}

#Preview {
    MigrationInfoSheet()
        .environmentObject(GradesStore())
}
