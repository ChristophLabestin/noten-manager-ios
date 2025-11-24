import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var store: GradesStore

    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false

    private var subjectsWithoutFachreferat: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private func grades(for subject: Subject) -> [Grade] {
        let list = store.gradesBySubject[subject.name] ?? []
        return list.map { gw in
            Grade(
                grade: gw.grade,
                weight: gw.weight,
                date: gw.date,
                note: gw.note,
                halfYear: gw.halfYear
            )
        }
    }

    private func subjectAverage(_ subject: Subject) -> Double? {
        let list = grades(for: subject)
        guard !list.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in list {
            let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private var overallAverageValue: Double? {
        guard !subjectsWithoutFachreferat.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for subject in subjectsWithoutFachreferat {
            if subject.isElective { continue }
            let list = grades(for: subject)
            for g in list {
                let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
                total += g.grade * w
                totalWeight += w
            }
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func halfYearAverage(_ halfYear: Int) -> Double? {
        guard halfYear == 1 || halfYear == 2 else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for subject in subjectsWithoutFachreferat {
            if subject.isElective { continue }
            let list = grades(for: subject).filter { $0.halfYear == halfYear }
            for g in list {
                let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
                total += g.grade * w
                totalWeight += w
            }
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private var totalGradesCount: Int {
        subjectsWithoutFachreferat.reduce(0) { partial, subject in
            partial + (store.gradesBySubject[subject.name]?.count ?? 0)
        }
    }

    private var sortedByAverageDesc: [Subject] {
        subjectsWithoutFachreferat.sorted { a, b in
            let avgA = subjectAverage(a)
            let avgB = subjectAverage(b)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (a1?, b1?):
                return a1 > b1
            }
        }
    }

    private var topSubjects: [Subject] {
        sortedByAverageDesc.prefix(3).filter { subjectAverage($0) != nil }
    }

    private var bottomSubjects: [Subject] {
        let sortedAsc = subjectsWithoutFachreferat.sorted { a, b in
            let avgA = subjectAverage(a)
            let avgB = subjectAverage(b)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (a1?, b1?):
                return a1 < b1
            }
        }
        return sortedAsc.prefix(3).filter { subjectAverage($0) != nil }
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.2f", v)
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    private var chipForegroundColor: Color {
        if isFeminine {
            return Color(hex: isDark ? "#f472b6" : "#ec4899")
        }
        return .blue
    }

    private var chipBackgroundColor: Color {
        if isFeminine {
            return chipForegroundColor.opacity(isDark ? 0.30 : 0.15)
        }
        return Color.blue.opacity(0.1)
    }

    private var themedBackground: some View {
        Group {
            if isDark {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#1f2937"),
                        Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 800
                )
            } else if isFeminine {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#fdf2ff"),
                        Color(hex: "#fdf2f8"),
                        Color(hex: "#fef2f2")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 238 / 255, green: 242 / 255, blue: 255 / 255),
                        Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255),
                        Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }

    private var hasHomeworkDueTomorrow: Bool {
        let cal = Calendar.current
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }
    }

    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }

    var body: some View {
        ZStack {
            themedBackground

            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Notenüberblick",
                        subtitle: "Durchschnitt, Fächer & Noten",
                        systemImage: "chart.bar.doc.horizontal.fill",
                        accent: .indigo
                    ) {
                        SettingsSectionBox {
                            HStack(spacing: 10) {
                                StatChip(title: "Gesamt-Ø", value: formatAverage(overallAverageValue), accent: .indigo)
                                StatChip(title: "Fächer", value: "\(subjectsWithoutFachreferat.count)", accent: .cyan)
                                StatChip(title: "Noten", value: "\(totalGradesCount)", accent: .orange)
                            }
                        }
                    }

                    // Halbjahresvergleich
                    let hj1 = halfYearAverage(1)
                    let hj2 = halfYearAverage(2)
                    if hj1 != nil || hj2 != nil {
                        SettingsCard(
                            title: "Halbjahresvergleich",
                            subtitle: nil,
                            systemImage: "rectangle.split.2x1",
                            accent: .cyan
                        ) {
                            SettingsSectionBox {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("1. Halbjahr")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(formatAverage(hj1))
                                            .font(.body)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(gradeColor(hj1).opacity(0.15))
                                            .foregroundStyle(gradeColor(hj1))
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("2. Halbjahr")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(formatAverage(hj2))
                                            .font(.body)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(gradeColor(hj2).opacity(0.15))
                                            .foregroundStyle(gradeColor(hj2))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    // Top-Fächer
                    if !topSubjects.isEmpty {
                        SettingsCard(
                            title: "Deine Top-Fächer",
                            subtitle: "Aktuell beste Durchschnittsnoten",
                            systemImage: "arrow.up.right.circle.fill",
                            accent: .green
                        ) {
                            SettingsSectionBox {
                                VStack(spacing: 8) {
                                    ForEach(topSubjects, id: \.name) { subject in
                                        NavigationLink {
                                            SubjectDetailView(subject: subject)
                                                .environmentObject(store)
                                        } label: {
                                            subjectInsightRow(subject: subject)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Fächer mit Potenzial
                    if !bottomSubjects.isEmpty {
                        SettingsCard(
                            title: "Fächer mit Potenzial",
                            subtitle: "Hier lohnt sich extra Vorbereitung",
                            systemImage: "arrow.down.forward.and.arrow.up.backward.circle.fill",
                            accent: .orange
                        ) {
                            SettingsSectionBox {
                                VStack(spacing: 8) {
                                    ForEach(bottomSubjects, id: \.name) { subject in
                                        NavigationLink {
                                            SubjectDetailView(subject: subject)
                                                .environmentObject(store)
                                        } label: {
                                            subjectInsightRow(subject: subject)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // Alle Fächer
                    if !subjectsWithoutFachreferat.isEmpty {
                        SettingsCard(
                            title: "Übersicht aller Fächer",
                            subtitle: nil,
                            systemImage: "list.bullet.rectangle.portrait.fill",
                            accent: .cyan
                        ) {
                            SettingsSectionBox {
                                VStack(spacing: 8) {
                                    ForEach(sortedByAverageDesc, id: \.name) { subject in
                                        NavigationLink {
                                            SubjectDetailView(subject: subject)
                                                .environmentObject(store)
                                        } label: {
                                            subjectOverviewRow(subject: subject)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Lege zuerst Fächer an, um Insights zu sehen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Insights")
                        .font(.headline)
                    Text("Deine Noten im Überblick")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {
                    Button {
                        showExamSheet = true
                    } label: {
                        ToolbarIcon(symbol: "calendar.badge.clock", showDot: hasOverdueExams)
                    }
                    .accessibilityLabel("Klausurtermine anzeigen")

                    Button {
                        showHomeworkSheet = true
                    } label: {
                        ToolbarIcon(symbol: "checklist", showDot: hasOverdueHomeworks || hasHomeworkDueTomorrow)
                    }
                    .accessibilityLabel("Aktive Hausaufgaben anzeigen")
                }
            }
        }
        .sheet(isPresented: $showHomeworkSheet) {
            HomeworkListView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showExamSheet) {
            ExamListView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func subjectInsightRow(subject: Subject) -> some View {
        let avg = subjectAverage(subject)
        let gradesCount = store.gradesBySubject[subject.name]?.count ?? 0

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    if subject.isElective {
                        Tag(text: "Wahlfach", style: .elective)
                    } else {
                        Tag(
                            text: subject.type == 1 ? "Hauptfach" : "Nebenfach",
                            style: subject.type == 1 ? .main : .minor
                        )
                    }
                    Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formatAverage(avg))
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(gradeColor(avg).opacity(0.15))
                .foregroundStyle(gradeColor(avg))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
private func subjectOverviewRow(subject: Subject) -> some View {
        let avg = subjectAverage(subject)
        let gradesCount = store.gradesBySubject[subject.name]?.count ?? 0

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatAverage(avg))
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(gradeColor(avg).opacity(0.12))
                .foregroundStyle(gradeColor(avg))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
        )
    }
}
