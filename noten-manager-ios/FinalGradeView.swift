import SwiftUI
import CryptoKit

private enum HalfYearDropOption: Equatable {
    case none
    case one
    case two

    var persistedValue: Int? {
        switch self {
        case .none: return nil
        case .one: return 1
        case .two: return 2
        }
    }

    static func fromPersisted(_ v: Int?) -> HalfYearDropOption {
        if v == 1 { return .one }
        if v == 2 { return .two }
        return .none
    }
}

struct FinalGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var dropSelections: [String: HalfYearDropOption] = [:]
    @State private var maxDroppedHalfYears: Int = 3
    @State private var examPointsBySubject: [String: Double?] = [:]
    @State private var finalGradeToFixed: Int = 1
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false

    private var subjectsWithoutFachreferat: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var hasFachreferat: Bool {
        store.fachreferat != nil
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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if store.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: store.progress, total: 100)
                        Text(store.loadingLabel).font(.footnote)
                    }
                    .padding(.horizontal)
                }

                // Top-Karten: Abschlussnote + Prüfungsstatus (analog Web)
                VStack(spacing: 12) {
                    SummaryCard(title: "") {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Abschlussnote")
                                    .font(.headline)
                            }
                            Spacer()
                            let finalAvg = finalAverage
                            let gradeShown: String = {
                                if fobosoSummary.maxPoints > 0, let g = fobosoSummary.grade {
                                    return String(format: "%.\(finalGradeToFixed)f", g)
                                }
                                return formatAverage(finalAvg)
                            }()
                            Text(gradeShown)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(gradeColor(finalAverage).opacity(0.15))
                                .foregroundStyle(gradeColor(finalAverage))
                                .clipShape(Capsule())
                                .onTapGesture { toggleFinalGradeToFixed() }
                        }
                    }

                    if passFailStatus != .open {
                        SummaryCard(title: "") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .center) {
                                    Text("Prüfungsstatus")
                                        .font(.headline)
                                    Spacer()
                                    Text(passFailStatus == .passed ? "Bestanden" : "Nicht bestanden")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(
                                                    passFailStatus == .passed
                                                    ? Color.green.opacity(0.2)
                                                    : Color(hex: "#ef4444")
                                                )
                                        )
                                        .foregroundStyle(passFailStatus == .passed ? .green : .white)
                                }

                                if passFailStatus == .failed {
                                    VStack(alignment: .leading, spacing: 6) {
                                        if failedByHalfYearTooFew {
                                            failureReasonRow("zu wenige Halbjahre eingebracht")
                                        }
                                        if failedByHalfYearTooMany {
                                            failureReasonRow("zu viele Halbjahre eingebracht")
                                        }
                                        if failedByExamGrade {
                                            failureReasonRow("benötigter Schnitt nicht erreicht")
                                        }
                                        if failedByFinalGrade {
                                            failureReasonRow("benötigte Abschlussnote nicht erreicht")
                                        }
                                        if failedByMissingFachreferat {
                                            failureReasonRow("Fachreferat Note nicht eingetragen")
                                        }
                                        if failedBySubjectPoints {
                                            failureReasonRow("benötigte Punktzahl nicht erreicht")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Abiturnoten-Übersicht
                SummaryCard(title: "") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abiturnoten")
                            .font(.headline)
                        if examSubjectFinals.isEmpty {
                            Text("Trage deine Abiturnoten im Abitur-Bereich ein, um hier eine Übersicht zu sehen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(examSubjectFinals, id: \.subject.name) { entry in
                                    HStack {
                                        Text(entry.subject.name)
                                        Spacer()
                                        Text(formatAverage(entry.final))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(gradeColor(entry.final).opacity(0.15))
                                            .foregroundStyle(gradeColor(entry.final))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Erreichte Punkte
                if fobosoSummary.maxPoints > 0 {
                    SummaryCard(title: "") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Erreichte Punkte")
                                .font(.headline)
                            Text("\(Int(round(fobosoSummary.totalPoints))) / \(fobosoSummary.maxPoints)")
                                .font(.title3).bold()
                            Text("Prüfungen (zweifach): \(Int(round(fobosoSummary.examPointsDouble))) Punkte")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Halbjahresergebnisse: \(Int(round(fobosoSummary.halfYearPoints))) Punkte (\(halfYearSummary.count) HJE).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if fachreferatHalfYearSummary.count > 0 {
                                Text("Fachreferat: \(Int(round(fachreferatHalfYearSummary.totalPoints))) Punkte (\(fachreferatHalfYearSummary.count) HJE).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Fächer/ Halbjahre-Übersicht + Streichen
                HStack(spacing: 12) {
                    SummaryCard(title: "Fächer") {
                        Text("\(subjectsWithoutFachreferat.count)")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(chipBackgroundColor)
                            .foregroundStyle(chipForegroundColor)
                            .clipShape(Capsule())
                    }
                    SummaryCard(title: "Halbjahre") {
                        if maxDroppedHalfYears > 0 {
                            Text("\(selectedDropCount) / \(maxDroppedHalfYears)")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(chipBackgroundColor)
                                .foregroundStyle(chipForegroundColor)
                                .clipShape(Capsule())
                        } else {
                            Text("\(selectedDropCount)")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(chipBackgroundColor)
                                .foregroundStyle(chipForegroundColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal)

                // Gestrichene Halbjahre Liste
                SummaryCard(title: "") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gestrichene Halbjahre")
                            .font(.headline)
                        Text(
                            maxDroppedHalfYears > 0
                            ? "Du kannst insgesamt bis zu \(maxDroppedHalfYears) Halbjahre streichen."
                            : "Das Streichen von Halbjahren ist derzeit deaktiviert."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if droppedHalfYears.isEmpty {
                            Text("Du hast noch kein Halbjahr gestrichen.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(droppedHalfYears, id: \.subject.name) { entry in
                                    let subjectGrades = store.gradesBySubject[entry.subject.name] ?? []
                                    let droppedAverage = calculateHalfYearAverageForSubject(
                                        subjectGrades,
                                        entry.subject.type,
                                        entry.halfYear
                                    )
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(entry.subject.name)
                                            Text(entry.halfYear == 1 ? "1. Halbjahr" : "2. Halbjahr")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(formatAverage(droppedAverage))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(gradeColor(droppedAverage).opacity(0.15))
                                            .foregroundStyle(gradeColor(droppedAverage))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Fächerkarten zum Streichen
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fächer").font(.headline)
                    Text("Streiche die Noten des gewählten Halbjahres.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if subjectsWithoutFachreferat.isEmpty {
                        Text("Lege zuerst Fächer und Noten an, um deine Abschlussnote zu berechnen.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(sortedSubjects, id: \.name) { subject in
                                subjectCard(subject)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                if maxDroppedHalfYears > 0 && limitReached {
                    Text("Du hast bereits die maximal erlaubte Anzahl an gestrichenen Halbjahren ausgewählt. Entferne zuerst eine Auswahl, um ein weiteres Halbjahr zu streichen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                // Hinweis
                Text("Hinweis: Das Streichen von Halbjahren in dieser Ansicht dient nur dir selbst als Orientierung und Merkhilfe. Es werden keine Daten an deine Schule oder andere Dritte übermittelt. Offizielle Entscheidungen über gestrichene Halbjahren musst du gegebenenfalls separat bei deiner Schule beantragen bzw. mitteilen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            .padding(.vertical, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Abschlussnote")
                        .font(.headline)
                    Text("Halbjahre streichen & berechnen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button {
                        showExamSheet = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Klausurtermine anzeigen")

                    Button {
                        showHomeworkSheet = true
                    } label: {
                        Image(systemName: "checklist")
                            .imageScale(.large)
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
        .onAppear {
            // Initiale Drop-Selections aus persisted droppedHalfYear
            var next: [String: HalfYearDropOption] = [:]
            for s in store.subjects {
                next[s.name] = HalfYearDropOption.fromPersisted(s.droppedHalfYear)
            }
            dropSelections = next
            recomputeMaxDroppedHalfYears()
            Task { await loadExamPoints() }
        }
        .onChange(of: store.subjects) { _ in
            var next: [String: HalfYearDropOption] = [:]
            for s in store.subjects {
                let persisted = HalfYearDropOption.fromPersisted(s.droppedHalfYear)
                let prev = dropSelections[s.name] ?? .none
                next[s.name] = (s.droppedHalfYear == 1 || s.droppedHalfYear == 2) ? persisted : prev
            }
            dropSelections = next
            recomputeMaxDroppedHalfYears()
            Task { await loadExamPoints() }
        }
        .onChange(of: store.gradeYear) { _ in
            recomputeMaxDroppedHalfYears()
        }
    }

    // MARK: - UI Pieces

    @ViewBuilder
    private func subjectCard(_ subject: Subject) -> some View {
        let dropOption = dropSelections[subject.name] ?? .none
        let isHalfYear1Selected = dropOption == .one
        let isHalfYear2Selected = dropOption == .two
        let disableHalfYear1 = ((limitReached || maxDroppedHalfYears <= 0) && !isHalfYear1Selected) || isHalfYear2Selected
        let disableHalfYear2 = ((limitReached || maxDroppedHalfYears <= 0) && !isHalfYear2Selected) || isHalfYear1Selected

        let subjectGrades = store.gradesBySubject[subject.name] ?? []
        let firstHalfYearAverage = calculateHalfYearAverageForSubject(subjectGrades, subject.type, 1)
        let secondHalfYearAverage = calculateHalfYearAverageForSubject(subjectGrades, subject.type, 2)
        let subjectAverage = subjectAverageFor(subject: subject)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(subject.name).font(.headline)
                Spacer()
                Tag(
                    text: subject.type == 1 ? "Hauptfach" : "Nebenfach",
                    style: subject.type == 1 ? .main : .minor
                )
            }

            HStack {
                Text("Fach-Durchschnitt").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(formatAverage(subjectAverage))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(gradeColor(subjectAverage).opacity(0.15))
                    .foregroundStyle(gradeColor(subjectAverage))
                    .clipShape(Capsule())
            }

            HStack {
                Toggle(isOn: Binding(
                    get: { isHalfYear1Selected },
                    set: { _ in handleToggleHalfYear(subjectName: subject.name, halfYear: 1) }
                )) { Text("1. Halbjahr") }
                .disabled(disableHalfYear1)
                Spacer()
                Text(formatAverage(firstHalfYearAverage))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(gradeColor(firstHalfYearAverage).opacity(0.15))
                    .foregroundStyle(gradeColor(firstHalfYearAverage))
                    .clipShape(Capsule())
                    .opacity(isHalfYear1Selected ? 0.6 : 1.0)
            }

            HStack {
                Toggle(isOn: Binding(
                    get: { isHalfYear2Selected },
                    set: { _ in handleToggleHalfYear(subjectName: subject.name, halfYear: 2) }
                )) { Text("2. Halbjahr") }
                .disabled(disableHalfYear2)
                Spacer()
                Text(formatAverage(secondHalfYearAverage))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(gradeColor(secondHalfYearAverage).opacity(0.15))
                    .foregroundStyle(gradeColor(secondHalfYearAverage))
                    .clipShape(Capsule())
                    .opacity(isHalfYear2Selected ? 0.6 : 1.0)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func failureReasonRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("x")
                .font(.caption)
                .foregroundStyle(Color(hex: "#f87171"))
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color(hex: "#f87171"))
        }
    }

    // MARK: - Helpers (Port von React)

    private func calculateGradeWeightForSubject(_ subjectType: Int, _ grade: GradeWithId) -> Double {
        if subjectType == 1 {
            return grade.weight == 3 ? 2 : (grade.weight == 2 ? 2 : 1)
        }
        if subjectType == 0 {
            return grade.weight == 3 ? 2 : (grade.weight == 1 ? 2 : 1)
        }
        return 1
    }

    private func calculateHalfYearAverageForSubject(_ grades: [GradeWithId], _ subjectType: Int, _ halfYear: Int) -> Double? {
        let filtered = grades.filter { $0.halfYear == halfYear }
        guard !filtered.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in filtered {
            let w = calculateGradeWeightForSubject(subjectType, g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func subjectAverageFor(subject: Subject) -> Double? {
        let grades = filteredSubjectGrades[subject.name] ?? []
        guard !grades.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let w = calculateGradeWeightForSubject(subject.type, g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
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

    // MARK: - State Berechnungen (entspricht useMemo in React)

    private var selectedDropCount: Int {
        subjectsWithoutFachreferat.reduce(0) { sum, subject in
            let value = dropSelections[subject.name] ?? .none
            return sum + ((value == .one || value == .two) ? 1 : 0)
        }
    }

    private var filteredSubjectGrades: [String: [GradeWithId]] {
        var result: [String: [GradeWithId]] = [:]
        for subject in store.subjects {
            let grades = store.gradesBySubject[subject.name] ?? []
            let dropOption = dropSelections[subject.name] ?? .none
            let filtered = grades.filter { g in
                if dropOption == .one, g.halfYear == 1 { return false }
                if dropOption == .two, g.halfYear == 2 { return false }
                return true
            }
            result[subject.name] = filtered
        }
        return result
    }

    private var droppedHalfYears: [(subject: Subject, halfYear: Int)] {
        subjectsWithoutFachreferat.compactMap { s in
            let opt = dropSelections[s.name] ?? .none
            switch opt {
            case .one: return (s, 1)
            case .two: return (s, 2)
            default: return nil
            }
        }
    }

    private var examSubjects: [Subject] {
        subjectsWithoutFachreferat.filter { $0.examSubject == true }
    }

    private var subjectAverages: [(subject: Subject, average: Double?)] {
        subjectsWithoutFachreferat.map { s in
            (s, subjectAverageFor(subject: s))
        }
    }

    private var sortedSubjects: [Subject] {
        if subjectsWithoutFachreferat.isEmpty { return [] }

        func getSubjectAverageForSort(_ subject: Subject) -> Double? {
            let grades = filteredSubjectGrades[subject.name] ?? []
            guard !grades.isEmpty else { return nil }
            var total = 0.0, totalWeight = 0.0
            for g in grades {
                let w = calculateGradeWeightForSubject(subject.type, g)
                total += g.grade * w
                totalWeight += w
            }
            guard totalWeight > 0 else { return nil }
            return total / totalWeight
        }

        switch store.subjectSortMode {
        case .name:
            return subjectsWithoutFachreferat.sorted { $0.name.lowercased().localizedCompare($1.name.lowercased()) == .orderedAscending }
        case .name_desc:
            return subjectsWithoutFachreferat.sorted { $0.name.lowercased().localizedCompare($1.name.lowercased()) == .orderedDescending }
        case .average:
            return subjectsWithoutFachreferat.sorted { a, b in
                let a1 = getSubjectAverageForSort(a)
                let b1 = getSubjectAverageForSort(b)
                switch (a1, b1) {
                case (nil, nil):
                    return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (aa?, bb?):
                    return aa > bb
                }
            }
        case .average_worst:
            return subjectsWithoutFachreferat.sorted { a, b in
                let a1 = getSubjectAverageForSort(a)
                let b1 = getSubjectAverageForSort(b)
                switch (a1, b1) {
                case (nil, nil):
                    return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
                case (nil, _):
                    return true
                case (_, nil):
                    return false
                case let (aa?, bb?):
                    return aa < bb
                }
            }
        case .custom:
            if store.subjectSortOrder.isEmpty {
                return subjectsWithoutFachreferat.sorted { $0.name.lowercased().localizedCompare($1.name.lowercased()) == .orderedAscending }
            }
            let orderMap = Dictionary(uniqueKeysWithValues: store.subjectSortOrder.enumerated().map { ($1, $0) })
            return subjectsWithoutFachreferat.sorted { a, b in
                let ia = orderMap[a.name]
                let ib = orderMap[b.name]
                switch (ia, ib) {
                case (nil, nil):
                    return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                default:
                    return ia! < ib!
                }
            }
        }
    }

    private var gradesOnlyFinalAverage: Double? {
        guard !store.subjects.isEmpty else { return nil }
        var total = 0.0, totalWeight = 0.0
        for subject in store.subjects {
            let grades = filteredSubjectGrades[subject.name] ?? []
            for g in grades {
                let w = calculateGradeWeightForSubject(subject.type, g)
                total += g.grade * w
                totalWeight += w
            }
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private var abiturFinalAverage: Double? {
        let es = examSubjects
        guard !es.isEmpty else { return nil }
        var subjectFinals: [Double] = []

        for s in es {
            let examPoints = examPointsBySubject[s.name] ?? nil
            guard let ep = examPoints else { continue }

            let subjectGrades = store.gradesBySubject[s.name] ?? []
            let dropOption = dropSelections[s.name] ?? .none
            let isHalfYear1Dropped = (dropOption == .one)
            let isHalfYear2Dropped = (dropOption == .two)

            let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, s.type, 1)
            let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, s.type, 2)

            var components: [(value: Double, weight: Double)] = []
            if let f = first { components.append((f, 1)) }
            if let sec = second { components.append((sec, 1)) }
            components.append((ep, 2))

            let totalWeight = components.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { continue }
            let totalValue = components.reduce(0) { $0 + $1.value * $1.weight }
            subjectFinals.append(totalValue / totalWeight)
        }

        guard !subjectFinals.isEmpty else { return nil }
        let sum = subjectFinals.reduce(0, +)
        return sum / Double(subjectFinals.count)
    }

    private var finalAverage: Double? {
        abiturFinalAverage ?? gradesOnlyFinalAverage
    }

    private var examSubjectsWithPoints: [Subject] {
        examSubjects.filter { (examPointsBySubject[$0.name] ?? nil) != nil }
    }

    private var halfYearSummary: (totalPoints: Double, count: Int) {
        var totalPoints = 0.0
        var count = 0
        for subject in store.subjects {
            if subject.name == "Fachreferat" { continue }
            let subjectGrades = store.gradesBySubject[subject.name] ?? []
            let dropOption = dropSelections[subject.name] ?? .none
            let isHalfYear1Dropped = (dropOption == .one)
            let isHalfYear2Dropped = (dropOption == .two)
            let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, subject.type, 1)
            let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, subject.type, 2)
            if let f = first { totalPoints += f; count += 1 }
            if let s = second { totalPoints += s; count += 1 }
        }
        return (totalPoints, count)
    }

    private var fachreferatHalfYearSummary: (totalPoints: Double, count: Int) {
        guard let fr = store.fachreferat else { return (0, 0) }
        return (fr.grade, 1)
    }

    private var fobosoSummary: (examCount: Int,
                                halfYearCount: Int,
                                examPointsDouble: Double,
                                halfYearPoints: Double,
                                totalPoints: Double,
                                maxPoints: Int,
                                grade: Double?,
                                gradeRaw: Double?) {
        let examCount = examSubjectsWithPoints.count
        var examPointsDouble = 0.0
        for s in examSubjectsWithPoints {
            if let v = examPointsBySubject[s.name] ?? nil {
                examPointsDouble += v * 2.0
            }
        }
        let halfYearCount = halfYearSummary.count
        let halfYearPoints = halfYearSummary.totalPoints
        let fachreferatCount = fachreferatHalfYearSummary.count
        let fachreferatPoints = fachreferatHalfYearSummary.totalPoints

        let units = examCount * 2 + halfYearCount + fachreferatCount
        if units == 0 {
            return (examCount, halfYearCount, 0, 0, 0, 0, nil, nil)
        }
        let maxPoints = units * 15
        let totalPoints = examPointsDouble + halfYearPoints + fachreferatPoints
        let gradeRaw = 17.0 / 3.0 - (5.0 * totalPoints) / Double(maxPoints)

        let grade: Double
        if gradeRaw < 1 {
            grade = 1
        } else {
            grade = floor(gradeRaw * 10.0) / 10.0
        }

        return (examCount, halfYearCount, examPointsDouble, halfYearPoints, totalPoints, maxPoints, grade, gradeRaw)
    }

    private var subjectFinalResults: [(subject: Subject, finalPoints: Double?)] {
        let es = examSubjects
        guard !es.isEmpty else { return [] }
        var results: [(Subject, Double?)] = []
        for s in es {
            let examPoints = examPointsBySubject[s.name] ?? nil
            let subjectGrades = store.gradesBySubject[s.name] ?? []
            let dropOption = dropSelections[s.name] ?? .none
            let isHalfYear1Dropped = (dropOption == .one)
            let isHalfYear2Dropped = (dropOption == .two)
            let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, s.type, 1)
            let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(subjectGrades, s.type, 2)
            var components: [(Double, Double)] = []
            if let f = first { components.append((f, 1)) }
            if let sec = second { components.append((sec, 1)) }
            if let ep = examPoints { components.append((ep, 2)) }
            if components.isEmpty {
                results.append((s, nil))
                continue
            }
            let totalWeight = components.reduce(0) { $0 + $1.1 }
            let totalValue = components.reduce(0) { $0 + $1.0 * $1.1 }
            results.append((s, totalValue / totalWeight))
        }
        return results
    }

    private var hasAllExamPoints: Bool {
        let es = examSubjects
        guard !es.isEmpty else { return false }
        return es.allSatisfy { (examPointsBySubject[$0.name] ?? nil) != nil }
    }

    private var examAveragePoints: Double? {
        guard hasAllExamPoints else { return nil }
        let es = examSubjects
        guard !es.isEmpty else { return nil }
        var total = 0.0
        var count = 0
        for s in es {
            if let v = examPointsBySubject[s.name] ?? nil {
                total += v
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    private var subjectsBelowFourPoints: Int {
        guard hasAllExamPoints else { return 0 }
        return subjectFinalResults.reduce(0) { sum, entry in
            if let v = entry.finalPoints, v < 4 { return sum + 1 }
            return sum
        }
    }

    private var examResultAtLeastFour: Bool? {
        guard let avg = examAveragePoints else { return nil }
        return avg >= 4
    }

    private var finalGradeAtLeastFour: Bool? {
        guard hasAllExamPoints, fobosoSummary.maxPoints > 0, let g = fobosoSummary.grade else { return nil }
        return g <= 4
    }

    private let requiredHalfYearCount: Int = 17

    private var failedByHalfYearTooFew: Bool {
        halfYearSummary.count < requiredHalfYearCount
    }
    private var failedByHalfYearTooMany: Bool {
        halfYearSummary.count > requiredHalfYearCount
    }
    private var failedByHalfYearCount: Bool {
        failedByHalfYearTooFew || failedByHalfYearTooMany
    }
    private var failedByMissingFachreferat: Bool {
        !hasFachreferat
    }
    private var failedBySubjectPoints: Bool {
        hasAllExamPoints && ((subjectsBelowFourPoints == 1 && fobosoSummary.totalPoints < 130) || (subjectsBelowFourPoints >= 2 && fobosoSummary.totalPoints < 156))
    }
    private var failedByExamGrade: Bool {
        hasAllExamPoints && (examResultAtLeastFour == false)
    }
    private var failedByFinalGrade: Bool {
        hasAllExamPoints && (finalGradeAtLeastFour == false)
    }

    private enum PassFailStatus { case open, passed, failed }
    private var passFailStatus: PassFailStatus {
        let isFailed = failedByHalfYearCount || failedByMissingFachreferat || failedBySubjectPoints || failedByExamGrade || failedByFinalGrade
        let isPassed = !isFailed && hasAllExamPoints && halfYearSummary.count == requiredHalfYearCount && examResultAtLeastFour == true && finalGradeAtLeastFour == true
        if isFailed { return .failed }
        if isPassed { return .passed }
        return .open
    }

    private var examSubjectFinals: [(subject: Subject, final: Double?)] {
        examSubjectsWithPoints.map { s in
            let ep = examPointsBySubject[s.name] ?? nil
            return (s, ep)
        }
    }

    private var limitReached: Bool {
        maxDroppedHalfYears > 0 && selectedDropCount >= maxDroppedHalfYears
    }

    private func toggleFinalGradeToFixed() {
        finalGradeToFixed = (finalGradeToFixed == 1 ? 2 : 1)
    }

    // MARK: - Actions

    private func handleToggleHalfYear(subjectName: String, halfYear: Int) {
        let current = dropSelections[subjectName] ?? .none
        var next: HalfYearDropOption = current

        if (current == .one && halfYear == 1) || (current == .two && halfYear == 2) {
            next = .none
        } else {
            let currentSelectedCount = dropSelections.values.filter { $0 == .one || $0 == .two }.count
            let currentlyHasDrop = (current == .one || current == .two)
            let willAddNewDrop = !currentlyHasDrop

            if willAddNewDrop && maxDroppedHalfYears > 0 && currentSelectedCount >= maxDroppedHalfYears {
                return
            }
            next = (halfYear == 1 ? .one : .two)
        }

        dropSelections[subjectName] = next
        Task { await store.updateDroppedHalfYear(subjectName: subjectName, value: next.persistedValue) }
    }

    private func recomputeMaxDroppedHalfYears() {
        guard let gradeYear = store.gradeYear, (gradeYear == 12 || gradeYear == 13) else {
            // Fallback auf altes Verhalten
            maxDroppedHalfYears = 3
            return
        }
        let requiredHalfYears = (gradeYear == 12 ? 17 : 16)
        let totalHalfYears = subjectsWithoutFachreferat.count * 2
        let computed = max(0, totalHalfYears - requiredHalfYears)
        maxDroppedHalfYears = computed
    }

    private func loadExamPoints() async {
        guard let key = store.encryptionKey else {
            examPointsBySubject = [:]
            return
        }
        var next: [String: Double?] = [:]
        for s in store.subjects {
            var examPoints: Double? = nil
            if let enc = s.examPointsEncrypted {
                do {
                    let decrypted = try CryptoService.decryptString(enc, key: key)
                    if let num = Double(decrypted), num.isFinite {
                        examPoints = num
                    } else {
                        examPoints = nil
                    }
                } catch {
                    examPoints = nil
                }
            }
            next[s.name] = examPoints
        }
        examPointsBySubject = next
    }
}
