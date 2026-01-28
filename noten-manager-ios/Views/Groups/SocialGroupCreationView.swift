import SwiftUI

struct SocialGroupCreationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Area
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(0.15))
                                .frame(width: 80, height: 80)
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.indigo)
                        }
                        .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                        
                        VStack(spacing: 4) {
                            Text("Soziale Gruppe erstellen")
                                .font(.title3.weight(.bold))
                            
                            Text("Teile Hausaufgaben und Termine ganz unkompliziert – ohne feste Fächerliste.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                    }
                    .padding(.top, 24)

                    // Group Name Input
                    SettingsCard(
                        title: "Gruppenname",
                        subtitle: "Wie soll deine Gruppe heißen?",
                        systemImage: "pencil.line",
                        accent: .indigo
                    ) {
                        TextField("Z.B. Lerngruppe 12b", text: $name)
                            .font(.body)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                    
                    if let error = errorMessage {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .softFadeIn(enabled: true)
                    }
                    
                    // Info Box
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fachunabhängig")
                                .font(.subheadline.weight(.semibold))
                            Text("In dieser Gruppe kannst du Einträge für jedes beliebige Fach teilen. Es gibt keine vordefinierten Fächer.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.indigo.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                    
                    // Create Button
                    Button {
                        Task { await createGroup() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(.indigo)
                        } else {
                            Text("Gruppe erstellen")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        ToolbarIcon(symbol: "chevron.down", showDot: false)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @MainActor
    private func createGroup() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        
        do {
            _ = try await store.createSocialGroup(name: trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
