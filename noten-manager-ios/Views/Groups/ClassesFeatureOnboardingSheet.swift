import SwiftUI

struct ClassesFeatureOnboardingSheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var animationsOn: Bool { store.animationsEnabled }
    private var accentColor: Color { .indigo }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.12))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "rectangle.stack.person.crop.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 20)
                    
                    VStack(spacing: 8) {
                        Text("Willkommen bei den Klassen")
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        
                        Text("Ein neues Level an Organisation für deinen Schulalltag.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 15)
                }
                .padding(.top, 40)
                
                // Feature Cards
                VStack(spacing: 16) {
                    onboardingRow(
                        icon: "square.grid.2x2.fill",
                        title: "Klassen-Struktur",
                        description: "Klassen bündeln jetzt alle deine Kurse an einem Ort. Das sorgt für automatische Synchronisation und perfekte Übersicht.",
                        delay: 0.3
                    )
                    
                    onboardingRow(
                        icon: "arrow.triangle.merge",
                        title: "Migration & Gruppen",
                        description: "Bestehende Lerngruppen können einfach in eine Klasse umgewandelt werden, um die neuen Vorteile zu nutzen.",
                        delay: 0.4
                    )
                    
                    onboardingRow(
                        icon: "person.2.fill",
                        title: "Klassen vs. Sozial",
                        description: "Klassen sind für den offiziellen Unterricht gedacht, während soziale Gruppen für alles Unabhängige bleiben.",
                        delay: 0.5
                    )
                }
                .padding(.horizontal)
                
                // Help Center Link
                HelpCenterLink(
                    title: "Mehr Details im Help Center",
                    subtitle: "Erfahre alles über die neuen Features.",
                    section: .classesGroups,
                    accent: accentColor
                )
                .padding(.horizontal)
                .softFadeIn(enabled: animationsOn, delay: 0.6, offset: 10)
                
                Spacer()
                
                // Action Button
                HStack {
                    Spacer()
                    Button {
                        store.markClassesOnboardingSeen()
                        dismiss()
                    } label: {
                        Text("Loslegen")
                            .font(.headline)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: accentColor, verticalPadding: 10))
                    .frame(width: 160) // Drastically fixed width
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .softFadeIn(enabled: animationsOn, delay: 0.7, offset: 5)
            }
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .interactiveDismissDisabled()
    }
    
    private func onboardingRow(icon: String, title: String, description: String, delay: Double) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(GradeCardStyle.surface(colorScheme: colorScheme, theme: store.theme, accent: accentColor))
        .overlay(GradeCardStyle.border(colorScheme: colorScheme, accent: accentColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
    }
}
