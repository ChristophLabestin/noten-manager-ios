import SwiftUI

struct SubjectCalculationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let subject: Subject
    let halfYearFilter: Int? // nil = all, 1, 2
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let filter = halfYearFilter {
                        halfYearCard(halfYear: filter)
                    } else {
                        halfYearCard(halfYear: 1)
                        halfYearCard(halfYear: 2)
                        
                        // Summary of both
                        summaryCard
                    }
                }
                .padding(16)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .navigationTitle(subject.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func halfYearCard(halfYear: Int) -> some View {
        let comp = store.computeHalfYearFoboso(subject: subject, halfYear: halfYear)
        let average = store.bestAvailableHalfYearValue(subject: subject, halfYear: halfYear)
        
        SettingsCard(
            title: "\(halfYear). Halbjahr",
            subtitle: nil,
            systemImage: "calendar",
            accent: .blue
        ) {
            VStack(spacing: 12) {
                if comp.schulaufgaben.isEmpty && comp.otherAvg == nil {
                    Text("Keine Noten in diesem Halbjahr.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    // Formula Visual
                    HStack(alignment: .top, spacing: 0) {
                        // Schulaufgaben
                        if !comp.schulaufgaben.isEmpty {
                            VStack(alignment: .center, spacing: 4) {
                                Text("Schulaufgaben")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                ForEach(comp.schulaufgaben, id: \.self) { sa in
                                    Text(String(format: "%.1f", sa))
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            Text("+")
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                        }
                        
                        // Mündlich
                        if let other = comp.otherAvg {
                            VStack(alignment: .center, spacing: 4) {
                                Text("Mündlich (Ø)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f", other))
                                    .font(.subheadline.monospacedDigit())
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        Text("=")
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                        
                        // Result
                        VStack(alignment: .center, spacing: 4) {
                            Text("Schnitt")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(average != nil ? String(format: "%.2f", average!) : "-")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                    
                    if let dropped = subject.droppedHalfYear, dropped == halfYear {
                        HStack {
                            Image(systemName: "nosign")
                            Text("Dieses Halbjahr ist gestrichen.")
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
    
    private var summaryCard: some View {
        let v1 = store.bestAvailableHalfYearValue(subject: subject, halfYear: 1)
        let v2 = store.bestAvailableHalfYearValue(subject: subject, halfYear: 2)
        
        return SettingsCard(
            title: "Gesamt",
            subtitle: "Jahresdurchschnitt",
            systemImage: "function",
            accent: .indigo
        ) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Berechnung")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("(\(v1 != nil ? String(format: "%.1f", v1!) : "-") + \(v2 != nil ? String(format: "%.1f", v2!) : "-")) ÷ 2")
                        .font(.subheadline.monospacedDigit())
                }
                Spacer()
                
                let avg = ((v1 ?? 0) + (v2 ?? 0)) / ((v1 != nil ? 1 : 0) + (v2 != nil ? 1 : 0))
                Text(String(format: "%.2f", avg))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.indigo)
            }
        }
    }
}
