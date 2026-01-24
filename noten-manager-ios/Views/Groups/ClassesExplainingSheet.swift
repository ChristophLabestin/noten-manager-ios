import SwiftUI

struct ClassesExplainingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var accentColor: Color { .indigo }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(accentColor.opacity(0.12))
                                .frame(width: 70, height: 70)
                            Image(systemName: "rectangle.stack.person.crop.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(accentColor)
                        }
                        
                        Text("Klassen & Gruppen")
                            .font(.title2.weight(.bold))
                        
                        Text("Hier erfährst du den Unterschied zwischen den beiden Konzepten.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 24)
                    
                    // Comparison
                    VStack(spacing: 16) {
                        explainingRow(
                            icon: "rectangle.stack.fill",
                            title: "Klassen (Geführt)",
                            description: "Klassen bündeln alle Fächer eines Schulverbandes. Wenn du einer Klasse beitrittst, erhältst du automatisch Zugriff auf alle zugehörigen Kurse und Gruppen.",
                            accent: .indigo
                        )
                        
                        explainingRow(
                            icon: "person.2.fill",
                            title: "Soziale Gruppen (Privat)",
                            description: "Ideal für Lerngruppen oder Projekte. Du kannst flexibel Hausaufgaben und Termine teilen, ohne an eine feste Fächerstruktur gebunden zu sein.",
                            accent: .purple
                        )
                        
                        explainingRow(
                            icon: "arrow.triangle.merge",
                            title: "Migration",
                            description: "Bestehende Gruppen können in Klassen umgewandelt werden, um die Vorteile der neuen Struktur zu nutzen.",
                            accent: .cyan
                        )
                    }
                    .padding(.horizontal)
                    
                    // Synchronization Info
                    SettingsSectionBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Synchronisation", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Text("In beiden Formaten werden Hausaufgaben und Prüfungstermine für alle Mitglieder synchronisiert. Deine Noten und persönlichen Notizen bleiben immer privat auf deinem Gerät.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("Verstanden")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: accentColor))
                    .padding(.horizontal)
                    .padding(.bottom, 30)
                }
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
    
    private func explainingRow(icon: String, title: String, description: String, accent: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
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
        .padding()
        .background(Color.formCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
