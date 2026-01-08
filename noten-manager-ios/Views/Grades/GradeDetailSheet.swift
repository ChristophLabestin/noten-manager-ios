import SwiftUI
import Foundation

struct GradeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let grade: GradeWithId
    let subjectName: String
    let subjectType: Int
    let onEdit: (GradeWithId) -> Void
    let onDelete: (GradeWithId) -> Void

    private var weightOptions: [(title: String, value: Double)] {
        if subjectType == 0 {
            return [
                ("Kurzarbeit", 1),
                ("Mündlich / EX", 0)
            ]
        }
        return [
            ("Schulaufgabe", 2),
            ("Kurzarbeit", 1),
            ("Mündlich / EX", 0)
        ]
    }

    private var weightLabel: String {
        if grade.weight == 3 { return "Fachreferat" }
        if let match = weightOptions.first(where: { $0.value == grade.weight }) {
            return match.title
        }
        let effective = abs(grade.weight)
        if let match = weightOptions.first(where: { $0.value == effective }) {
            return match.title
        }
        return "Sonstige Leistung (\(formatWeight(effective))x)"
    }

    private var halfYearLabel: String {
        if (grade.halfYear ?? 1) == 1 { return "1. Halbjahr" }
        return "2. Halbjahr"
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .none
        fmt.locale = .autoupdatingCurrent
        fmt.calendar = .autoupdatingCurrent
        return fmt.string(from: grade.date)
    }

    private var linkedExam: Exam? {
        guard let id = grade.linkedExamId else { return nil }
        if let local = store.allExams.first(where: { $0.id == id }) {
            return local
        }
        return store.sharedExams.first(where: { $0.id == id })
    }

    private var sheetTitle: String {
        subjectName.isEmpty ? "Note" : subjectName
    }

    private var effectiveWeight: Double {
        store.effectiveGradeWeight(subjectType: subjectType, rawWeight: grade.weight)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Note",
                        subtitle: subjectName.isEmpty ? "Unbekanntes Fach" : subjectName,
                        systemImage: "checkmark.seal.fill",
                        accent: .indigo
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .center, spacing: 10) {
                                    Text(String(format: "%.1f", grade.grade))
                                        .font(.title.weight(.bold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(gradeColor(grade.grade).opacity(0.2))
                                        .foregroundStyle(gradeColor(grade.grade))
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    detailRow(title: "Art", value: weightLabel, icon: "chart.bar.fill", tint: .orange)
                                }
                                detailRow(title: "Datum", value: formattedDate, icon: "calendar", tint: .indigo)
                            }
                        }
                    }

                    SettingsCard(
                        title: "Details",
                        subtitle: "Gewicht & Halbjahr",
                        systemImage: "doc.text.magnifyingglass",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                detailRow(title: "Gewichtung (Schnitt)", value: formatWeight(effectiveWeight), icon: "scalemass", tint: .indigo)
                                detailRow(title: "Halbjahr", value: halfYearLabel, icon: "calendar", tint: .blue)
                            }
                        }
                    }

                    SettingsCard(
                        title: "Notiz",
                        subtitle: "Optional",
                        systemImage: "note.text",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            if let note = grade.note, !note.isEmpty {
                                Text(note)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                Text("Keine Notiz hinterlegt.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let exam = linkedExam {
                        SettingsCard(
                            title: "Verknüpfte Prüfung",
                            subtitle: exam.title.isEmpty ? "Prüfung" : exam.title,
                            systemImage: "calendar.badge.clock",
                            accent: .mint
                        ) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    detailRow(title: "Termin", value: exam.date.formatted(date: .abbreviated, time: .omitted), icon: "calendar", tint: .mint)
                                    detailRow(title: "Status", value: exam.isCompleted ? "Erledigt" : "Offen", icon: exam.isCompleted ? "checkmark.circle" : "hourglass", tint: exam.isCompleted ? .green : .orange)
                                    if let notes = exam.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .sheetNavigationTitle(sheetTitle)
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
            ToolbarItem(placement: .confirmationAction) {
                    Button("Bearbeiten") {
                        onEdit(grade)
                        dismiss()
                    }
                }
            }
        }
    }

    private func detailRow(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func gradeColor(_ value: Double) -> Color {
        if value >= 7 { return .green }
        if value >= 4 { return .orange }
        return .red
    }

    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
