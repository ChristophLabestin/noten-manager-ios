import SwiftUI

struct MSSDetailedCalculationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let halfYearFilter: HomeView.HalfYearFilter
    
    private var filterInt: Int? {
        switch halfYearFilter {
        case .all: return nil
        case .one: return 1
        case .two: return 2
        }
    }
    
    private var breakdown: (items: [GradeCalculationService.CalculationBreakdownItem], total: Double, divisor: Double, average: Double?) {
        GradeCalculationService.calculateOverallAverageDetailed(
            subjects: store.subjects,
            halfYearValueProvider: { subject, hy in
                store.bestAvailableHalfYearValue(subject: subject, halfYear: hy)
            },
            droppedHalfYearProvider: { subject in
                subject.droppedHalfYear
            },
            halfYearFilter: filterInt,
            fachreferat: filterInt == nil ? store.fachreferat : nil,
            seminar: filterInt == nil ? store.seminarPerformance : nil,
            practical: filterInt == nil ? store.practicalPerformance : nil,
            examPoints: filterInt == nil ? store.examPoints : [:],
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12
        )
    }
    
    var body: some View {
        ZStack {
            ThemedBackground(
                isDark: store.darkMode,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    
                    let categories = Array(Set(breakdown.items.map { $0.category })).sorted()
                    ForEach(categories, id: \.self) { category in
                        sectionView(category: category)
                    }

                    if breakdown.items.isEmpty {
                        Text("Keine Noten für die Berechnung verfügbar.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 20)
                    }
                    
                    HelpCenterLink(
                        title: "Hilfe zur Berechnung",
                        subtitle: "Details zu Gewichtungen, HJE und Gesamtpunktzahl",
                        section: .calc,
                        accent: .indigo
                    )
                    .padding(.top, 4)

                    Text("Diese Berechnung basiert auf den offiziellen MSS-Regeln (Bayerische Schulordnung). Rundungsdifferenzen sind möglich.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
        }
        .navigationTitle("MSS Berechnung")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .imageScale(.medium)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var summaryCard: some View {
        SettingsCard(
            title: "Gesamtschnitt",
            subtitle: "Summe der Punkte ÷ Anzahl der Wertungen",
            systemImage: "function",
            accent: .indigo
        ) {
            VStack(spacing: 0) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading) {
                        Text("Summe")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f", breakdown.total))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .privacyBlur()
                    }
                    
                    Spacer()
                    
                    Text("÷")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("Teiler")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f", breakdown.divisor))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .privacyBlur()
                    }
                    
                    Spacer()
                    
                    Text("=")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Schnitt")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(breakdown.average.map { String(format: "%.2f", $0) } ?? "-")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(gradeColor(breakdown.average))
                            .privacyBlur()
                    }
                }
                .padding(.vertical, 8)
                .monospacedDigit()
            }
        }
    }
    
    private func sectionView(category: String) -> some View {
        let items = breakdown.items.filter { $0.category == category }
        let categoryIcon: String = {
            switch category {
            case "Fächer": return "books.vertical.fill"
            case "Zusatzleistung": return "star.fill"
            case "Prüfungen": return "graduationcap.fill"
            default: return "list.bullet"
            }
        }()
        let categoryColor: Color = {
            switch category {
            case "Fächer": return .blue
            case "Zusatzleistung": return .orange
            case "Prüfungen": return .purple
            default: return .gray
            }
        }()
        
        return SettingsCard(
            title: category,
            subtitle: nil,
            systemImage: categoryIcon,
            accent: categoryColor
        ) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            
                            if item.weight != 1.0 {
                                Text("Gewichtung: \(String(format: "%g", item.weight))x")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(0.05))
                                    )
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Text(String(format: "%.1f", item.value))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .privacyBlur()
                    }
                    .padding(.vertical, 10)
                    
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 0)
                    }
                }
            }
        }
    }
    
    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if store.isPrivacyModeActive { return .primary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }
}
