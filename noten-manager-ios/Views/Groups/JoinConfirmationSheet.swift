import SwiftUI

struct JoinConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let preview: JoinPreview
    let onConfirm: () -> Void
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon & Header
                        VStack(spacing: 12) {
                            Image(systemName: preview.type == .schoolClass ? "rectangle.stack.fill" : "person.3.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(preview.type == .schoolClass ? .indigo : .orange)
                                .padding(.bottom, 8)
                                .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                            
                            Text(preview.name)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                                .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                            
                            Text(preview.type == .schoolClass ? "Schulklasse" : "Soziale Gruppe")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                                .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                        }
                        .padding(.top, 20)
                        
                        VStack(spacing: 20) {
                            // Info Section
                            SettingsCard(
                                title: "Informationen",
                                subtitle: "Details zur \(preview.type == .schoolClass ? "Klasse" : "Gruppe")",
                                systemImage: "info.circle.fill",
                                accent: preview.type == .schoolClass ? .indigo : .orange
                            ) {
                                VStack(spacing: 16) {
                                    InfoRow(icon: "number", label: "ID / Code", value: preview.id)
                                    
                                    if let memberCount = preview.memberCount {
                                        InfoRow(icon: "person.2.fill", label: "Mitglieder", value: "\(memberCount)")
                                    }
                                    
                                    InfoRow(icon: "pencil.and.outline", label: "Prüfungen", value: "\(preview.examCount)")
                                }
                                .padding(.vertical, 4)
                            }
                            .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)
                            
                            // Branches Section
                            if let branches = preview.branches {
                                SettingsCard(
                                    title: "Fachzweige",
                                    subtitle: "Verfügbare Zweige dieser Klasse",
                                    systemImage: "checklist",
                                    accent: .indigo
                                ) {
                                    VStack(spacing: 12) {
                                        ForEach(branches, id: \.self) { branch in
                                            SimpleRow(icon: "arrow.triangle.branch", label: branch, color: .indigo)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .softFadeIn(enabled: animationsOn, delay: 0.3, offset: 12)
                            }
                            
                            // Electives Section
                            if let electives = preview.wahlpflichtGroups {
                                SettingsCard(
                                    title: "Wahlpflichtgruppen",
                                    subtitle: "Verknüpfte Fächergruppen",
                                    systemImage: "star.fill",
                                    accent: .teal
                                ) {
                                    VStack(spacing: 12) {
                                        ForEach(electives, id: \.self) { elective in
                                            SimpleRow(icon: "star.fill", label: elective, color: .teal)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .softFadeIn(enabled: animationsOn, delay: 0.35, offset: 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        Spacer(minLength: 40)
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button {
                                onConfirm()
                                dismiss()
                            } label: {
                                Text("Bestätigen & Beitreten")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: preview.type == .schoolClass ? .indigo : .orange))
                            .softFadeIn(enabled: animationsOn, delay: 0.35, offset: 12)
                            
                            Button {
                                dismiss()
                            } label: {
                                Text("Abbrechen")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .softFadeIn(enabled: animationsOn, delay: 0.4, offset: 12)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Schließen")
                }
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.body.weight(.bold))
                .monospacedDigit()
        }
    }
}

private struct SimpleRow: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
            }
            
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
