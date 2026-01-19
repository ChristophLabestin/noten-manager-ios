import SwiftUI

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var store: GradesStore
    
    struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let systemImage: String
        let accent: Color
    }
    
    private let features: [Feature] = [
        Feature(
            title: "Das neue Klassen-System",
            description: "Wechsle nahtlos von Gruppen zu Klassen für eine bessere Zusammenarbeit.",
            systemImage: "graduationcap.fill",
            accent: .indigo
        ),
        Feature(
            title: "Offizielle Notenlogik",
            description: "Präzise Berechnungen und Abitur-Prognosen nach offiziellen FOBOSO-Regeln.",
            systemImage: "divide.circle.fill",
            accent: .orange
        ),
        Feature(
            title: "Detaillierte Berechnung",
            description: "Tippe auf die Gesamtschnitt-Karte im Home-Screen, um die exakte MSS-Berechnung zu sehen.",
            systemImage: "function",
            accent: .purple
        ),
        Feature(
            title: "Kalender & Termine",
            description: "Behalte den Überblick über deine Prüfungen und Hausaufgaben in der neuen Kalenderansicht.",
            systemImage: "calendar",
            accent: .blue
        ),
        Feature(
            title: "Neu: Privacy Mode",
            description: "Schütze deine Noten elegant vor fremden Blicken mit Face ID oder Touch ID.",
            systemImage: "lock.shield.fill",
            accent: .cyan
        ),
        Feature(
            title: "Neu: PDF Report Card",
            description: "Exportiere deine Notenübersicht in einem komplett neu gestalteten, modernen Design.",
            systemImage: "doc.richtext.fill",
            accent: .green
        )
    ]
    
    var body: some View {
        ZStack {
            ThemedBackground(
                isDark: colorScheme == .dark,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            )
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 80, height: 80)
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 40)
                    
                    Text("Das ist neu!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Entdecke die neuesten Funktionen für deinen Schulalltag.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.bottom, 30)
                
                // Features List
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(features) { feature in
                            FeatureRow(feature: feature)
                        }
                        
                        // Full Changelog Link
                        Link(destination: URL(string: "https://fosbos-notenmanager.de/changelog")!) {
                            HStack {
                                Text("Vollständiges Änderungsprotokoll")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.vertical, 10)
                        }
                        .padding(.top, 10)

                        // Action Button
                        Button {
                            // Mark as seen
                            if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                                store.updateLastSeenVersion(to: currentVersion)
                            }
                            dismiss()
                        } label: {
                            Text("Loslegen")
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .blue, font: .headline.weight(.bold), verticalPadding: 16))
                        .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

private struct FeatureRow: View {
    let feature: WhatsNewSheet.Feature
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var store: GradesStore
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(feature.accent.opacity(colorScheme == .dark ? 0.2 : 0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: feature.systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(feature.accent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(feature.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.formCardBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(feature.accent.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    WhatsNewSheet()
        .environmentObject(GradesStore())
}
