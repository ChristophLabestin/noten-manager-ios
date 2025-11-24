import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @EnvironmentObject var store: GradesStore

    enum HalfYearFilter: Equatable {
        case all
        case one
        case two
    }

    @State private var halfYear: HalfYearFilter = .all
    @State private var isEditingOrder: Bool = false
    @State private var customOrderWorkingCopy: [String] = []

    // Navigation-States für echte Seiten (kein Sheet)
    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinalGrade: Bool = false

    @State private var greeting: String = ""
    @State private var displayName: String = ""
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false

    private var subjectsWithoutFachreferat: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var hasFachreferat: Bool {
        store.fachreferat != nil
    }

    private var hasPracticalPerformance: Bool {
        guard let perf = store.practicalPerformance else { return false }
        return !perf.grades.isEmpty
    }

    // MARK: - Data preparation

    private func filteredSubjectGrades() -> [String: [Grade]] {
        var result: [String: [Grade]] = [:]
        for subject in store.subjects {
            let gradesWithId = store.gradesBySubject[subject.name] ?? []
            var filtered: [Grade] = []
            filtered.reserveCapacity(gradesWithId.count)
            for gw in gradesWithId {
                let matches: Bool
                switch halfYear {
                case .all:
                    matches = true
                case .one:
                    matches = (gw.halfYear == 1)
                case .two:
                    matches = (gw.halfYear == 2)
                }
                if matches {
                    filtered.append(Grade(grade: gw.grade, weight: gw.weight, date: gw.date, note: gw.note, halfYear: gw.halfYear))
                }
            }
            result[subject.name] = filtered
        }
        if let fr = store.fachreferat {
            result["Fachreferat"] = [
                Grade(grade: fr.grade, weight: 3, date: fr.date, note: fr.note, halfYear: nil)
            ]
        }
        if let practical = store.practicalPerformance {
            let entries = practical.grades.map { entry in
                Grade(
                    grade: entry.grade,
                    weight: 0,
                    date: entry.date,
                    note: entry.note ?? entry.company,
                    halfYear: entry.halfYear
                )
            }
            if !entries.isEmpty {
                result["Praktikum"] = entries
            }
        }
        return result
    }

    private func getSubjectAverage(_ subject: Subject, subjectGrades: [String: [Grade]]) -> Double? {
        let grades = subjectGrades[subject.name] ?? []
        guard !grades.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func baseSubjectsList() -> [Subject] {
        var base = subjectsWithoutFachreferat
        if hasFachreferat {
            base.append(Subject(name: "Fachreferat", type: 0, date: Date()))
        }
        if hasPracticalPerformance {
            base.append(Subject(name: "Praktikum", type: 0, date: Date()))
        }
        return base
    }

    // MARK: - Sorting helpers

    private func comparatorNameAsc() -> (Subject, Subject) -> Bool {
        { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
        }
    }

    private func comparatorNameDesc() -> (Subject, Subject) -> Bool {
        { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedDescending
        }
    }

    private func comparatorAverageBestFirst(subjectGrades: [String: [Grade]]) -> (Subject, Subject) -> Bool {
        { a, b in
            let avgA = getSubjectAverage(a, subjectGrades: subjectGrades)
            let avgB = getSubjectAverage(b, subjectGrades: subjectGrades)
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

    private func comparatorAverageWorstFirst(subjectGrades: [String: [Grade]]) -> (Subject, Subject) -> Bool {
        { a, b in
            let avgA = getSubjectAverage(a, subjectGrades: subjectGrades)
            let avgB = getSubjectAverage(b, subjectGrades: subjectGrades)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return true
            case (_, nil):
                return false
            case let (a1?, b1?):
                return a1 < b1
            }
        }
    }

    private func comparatorCustom(orderMap: [String: Int]) -> (Subject, Subject) -> Bool {
        { a, b in
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

    private func customOrderMap() -> [String: Int]? {
        guard !store.subjectSortOrder.isEmpty else { return nil }
        var map: [String: Int] = [:]
        for (idx, name) in store.subjectSortOrder.enumerated() {
            map[name] = idx
        }
        return map
    }

    private func sortedSubjects(subjectGrades: [String: [Grade]]) -> [Subject] {
        let base = baseSubjectsList()
        switch store.subjectSortMode {
        case .name:
            return base.sorted(by: comparatorNameAsc())
        case .name_desc:
            return base.sorted(by: comparatorNameDesc())
        case .average:
            return base.sorted(by: comparatorAverageBestFirst(subjectGrades: subjectGrades))
        case .average_worst:
            return base.sorted(by: comparatorAverageWorstFirst(subjectGrades: subjectGrades))
        case .custom:
            if let map = customOrderMap() {
                return base.sorted(by: comparatorCustom(orderMap: map))
            } else {
                return base.sorted(by: comparatorNameAsc())
            }
        }
    }

    // MARK: - Overall formatting

    private func overallAverage(subjectGrades: [String: [Grade]]) -> Double? {
        guard !store.subjects.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for subject in store.subjects {
            if subject.isElective { continue }
            let grades = subjectGrades[subject.name] ?? []
            for g in grades {
                let w = store.calculateGradeWeightForOverall(subject: subject, grade: g)
                total += g.grade * w
                totalWeight += w
            }
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

    private var enableDrag: Bool {
        store.subjects.count > 1
    }

    // MARK: - Small subviews for body

    @ViewBuilder
    private func subjectRowAny(subject: Subject,
                               subjectGrades: [String: [Grade]],
                               fachreferatSubjectName: String?) -> some View {
        let grades = subjectGrades[subject.name] ?? []
        if subject.name == "Fachreferat" || subject.name == "Praktikum" {
            SubjectRowView(
                subject: subject,
                grades: grades,
                fachreferatSubjectName: fachreferatSubjectName
            )
            .contentShape(Rectangle())
        } else {
            NavigationLink(value: subject) {
                SubjectRowView(
                    subject: subject,
                    grades: grades,
                    fachreferatSubjectName: fachreferatSubjectName
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived computed properties to simplify body

    private var subjectGradesComputed: [String: [Grade]] {
        filteredSubjectGrades()
    }

    private var sortedSubjectsComputed: [Subject] {
        sortedSubjects(subjectGrades: subjectGradesComputed)
    }

    private var overallComputed: Double? {
        overallAverage(subjectGrades: subjectGradesComputed)
    }

    private var totalGradesCountComputed: Int {
        subjectGradesComputed.values.reduce(0) { $0 + $1.count }
    }

    private var subjectByNameComputed: [String: Subject] {
        var map: [String: Subject] = [:]
        for s in baseSubjectsList() { map[s.name] = s }
        return map
    }

    private var editModeBinding: EditMode {
        isEditingOrder ? .active : .inactive
    }

    // MARK: - Overdue indicators

    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate {
                return due < now
            }
            if let reminder = hw.reminderAt {
                return reminder < now
            }
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

    private var overdueHomeworksCount: Int {
        let now = Date()
        return store.allHomeworks.filter { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate {
                return due < now
            }
            if let reminder = hw.reminderAt {
                return reminder < now
            }
            return false
        }.count
    }

    private var homeworkDueTomorrowCount: Int {
        let cal = Calendar.current
        return store.allHomeworks.filter { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }.count
    }

    private var overdueExamsCount: Int {
        let now = Date()
        return store.allExams.filter { exam in
            !exam.isCompleted && exam.date < now
        }.count
    }

    private var upcomingExamsNextTwoWeeksCount: Int {
        let now = Date()
        guard let twoWeeks = Calendar.current.date(byAdding: .day, value: 14, to: now) else { return 0 }
        return store.allExams.filter { exam in
            !exam.isCompleted && exam.date >= now && exam.date <= twoWeeks
        }.count
    }

    // MARK: - Header & Overview

    private var compactOverview: some View {
        SettingsCard(
            title: greeting.isEmpty ? "Willkommen" : greeting,
            subtitle: displayName.isEmpty ? nil : displayName,
            systemImage: "hand.wave.fill",
            accent: .indigo,
            trailing: {
                if let year = store.activeSchoolYearId {
                    PillBadge(
                        text: year,
                        systemImage: "calendar",
                        foreground: Color.cyan,
                        background: Color.cyan.opacity(0.14)
                    )
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatChip(title: "Gesamt-Ø", value: formatAverage(overallComputed), accent: .indigo)
                    StatChip(title: "Fächer", value: "\(subjectsWithoutFachreferat.count)", accent: .cyan)
                    StatChip(title: "Noten", value: "\(totalGradesCountComputed)", accent: .orange)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if overdueHomeworksCount > 0 {
                            PillBadge(
                                text: "Hausaufgaben fällig: \(overdueHomeworksCount)",
                                systemImage: "exclamationmark.triangle.fill",
                                foreground: .orange,
                                background: Color.orange.opacity(0.16)
                            )
                        }
                        if homeworkDueTomorrowCount > 0 {
                            PillBadge(
                                text: "Hausaufgaben morgen: \(homeworkDueTomorrowCount)",
                                systemImage: "clock.badge.exclamationmark",
                                foreground: .yellow,
                                background: Color.yellow.opacity(0.16)
                            )
                        }
                        if upcomingExamsNextTwoWeeksCount > 0 {
                            PillBadge(
                                text: "\(upcomingExamsNextTwoWeeksCount) Klausuren stehen an",
                                systemImage: "calendar.badge.clock",
                                foreground: .red,
                                background: Color.red.opacity(0.12)
                            )
                        }
                        if overdueHomeworksCount == 0 && homeworkDueTomorrowCount == 0 && upcomingExamsNextTwoWeeksCount == 0 {
                            PillBadge(
                                text: "Alles im Plan",
                                systemImage: "checkmark.circle.fill",
                                foreground: .green,
                                background: Color.green.opacity(0.14)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var subjectsControlCard: some View {
        SettingsCard(
            title: "Fächer & Noten",
            subtitle: "Filter und Reihenfolge",
            systemImage: "text.book.closed",
            accent: .cyan,
            trailing: {
                if enableDrag {
                    Button {
                        toggleEditMode(sortedNames: sortedSubjectsComputed.map { $0.name })
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(isEditingOrder ? "Fertig" : "Sortieren")
                        }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.16))
                            .foregroundStyle(Color.cyan)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        ) {
            HStack(alignment: .center, spacing: 4) {
                HalfYearFilterRow(halfYear: $halfYear)
            }
        }
    }


    // MARK: - Body

    var body: some View {
        List {
            if store.isLoading {
                Section {
                    SettingsCard(
                        title: "Sync läuft...",
                        subtitle: store.loadingLabel,
                        systemImage: "arrow.triangle.2.circlepath",
                        accent: .cyan
                    ) {
                        ProgressView(value: store.progress, total: 100)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)
            }

            Section {
                compactOverview
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                subjectsControlCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)

            Section {
                if isEditingOrder && enableDrag {
                    ForEach(customOrderWorkingCopy, id: \.self) { name in
                        SubjectRowView(
                            subject: subjectByNameComputed[name] ?? Subject(name: name, type: 0, date: Date()),
                            grades: subjectGradesComputed[name] ?? [],
                            fachreferatSubjectName: store.fachreferat?.subjectName
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { indices, newOffset in
                        customOrderWorkingCopy.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } else {
                    ForEach(sortedSubjectsComputed, id: \.name) { subject in
                        subjectRowAny(
                            subject: subject,
                            subjectGrades: subjectGradesComputed,
                            fachreferatSubjectName: store.fachreferat?.subjectName
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listSectionSeparator(.hidden)
        }
        .environment(\.editMode, .constant(editModeBinding))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSpacing(0)
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))

        // Unsichtbare NavigationLinks (NavigationStack-Ziele)
        .background(
            NavigationLinksBackground(
                navigateToSettings: $navigateToSettings,
                navigateToFinalGrade: $navigateToFinalGrade
            ).environmentObject(store)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolbarTitleView(title: "Übersicht", subtitle: "Fächer & Noten")
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
        .onAppear {
            computeGreeting()
            Task { await loadUserDisplayName() }
        }
    }

    // MARK: - Actions

    private func toggleEditMode(sortedNames: [String]) {
        if isEditingOrder {
            Task {
                await store.updateSubjectSortPreferences(mode: .custom, order: customOrderWorkingCopy)
            }
            isEditingOrder = false
        } else {
            if store.subjectSortOrder.isEmpty {
                customOrderWorkingCopy = sortedNames
            } else {
                customOrderWorkingCopy = store.subjectSortOrder
                    .filter { sortedNames.contains($0) } +
                    sortedNames.filter { !store.subjectSortOrder.contains($0) }
            }
            isEditingOrder = true
        }
    }

    private func computeGreeting() {
        let hours = Calendar.current.component(.hour, from: Date())
        if hours >= 6 && hours < 11 {
            greeting = "Guten Morgen"
        } else if hours >= 11 && hours < 17 {
            greeting = "Hallo"
        } else if hours >= 17 && hours < 22 {
            greeting = "Guten Abend"
        } else {
            greeting = "Gute Nacht"
        }
    }

    private func loadUserDisplayName() async {
        if let dn = Auth.auth().currentUser?.displayName, !dn.isEmpty {
            displayName = dn
            return
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            displayName = ""
            return
        }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            if let data = snap.data() {
                if let dn = data["displayName"] as? String, !dn.isEmpty {
                    displayName = dn
                } else if let n = data["name"] as? String, !n.isEmpty {
                    displayName = n
                } else {
                    displayName = ""
                }
            }
        } catch {
            displayName = ""
        }
    }
}



struct SegmentButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(active ? activeBackground : Color.clear)
                .foregroundStyle(active ? activeTextColor : inactiveTextColor)
                .clipShape(Capsule())
                .shadow(
                    color: active ? shadowColor : .clear,
                    radius: active ? 4 : 0,
                    x: 0,
                    y: active ? 2 : 0
                )
        }
        .buttonStyle(.plain)
    }

    private var activeBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white
    }

    private var activeTextColor: Color {
        colorScheme == .dark ? Color.white : Color(hex: "#111827")
    }

    private var inactiveTextColor: Color {
        colorScheme == .dark ? Color(hex: "#d1d5db") : Color(hex: "#6b7280")
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.16)
    }
}

struct SubjectRowView: View {
    let subject: Subject
    let grades: [Grade]
    let fachreferatSubjectName: String?

    private func avg(_ subject: Subject) -> Double? {
        guard !grades.isEmpty else { return nil }
        func calculateGradeWeight(_ subject: Subject, _ grade: Grade) -> Double {
            if subject.name == "Fachreferat" { return 3 }
            if subject.name == "Praktikum" { return 1 }
            let t = subject.type
            if t == 1 {
                return (grade.weight == 3 ? 2 : (grade.weight == 2 ? 2 : 1))
            }
            if t == 0 {
                return (grade.weight == 3 ? 2 : (grade.weight == 1 ? 2 : 1))
            }
            return 1
        }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let w = calculateGradeWeight(subject, g)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.2f", v)
    }

    private func gradeClassColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    var body: some View {
        let average = avg(subject)
        let gradesCount = grades.count

        let isFachreferat = subject.name == "Fachreferat"
        let isPraktikum = subject.name == "Praktikum"
        let displayName: String = {
            if isFachreferat, let frName = fachreferatSubjectName, !frName.isEmpty {
                return "Fachreferat in \(frName)"
            }
            if isPraktikum {
                return "Praktikum (11.)"
            }
            return subject.name
        }()

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    if isFachreferat {
                        Tag(text: "Halbjahresleistung", style: .main)
                    } else if isPraktikum {
                        Tag(text: "Praktikum", style: .minor)
                        Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if subject.isElective {
                        Tag(text: "Wahlfach", style: .elective)
                        Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Tag(text: subject.type == 1 ? "Hauptfach" : "Nebenfach", style: subject.type == 1 ? .main : .minor)
                        Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Text(formatAverage(average))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(gradeClassColor(average).opacity(0.15))
                .foregroundStyle(gradeClassColor(average))
                .clipShape(Capsule())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.15), lineWidth: 1)
        )
    }
}

struct Tag: View {
    @EnvironmentObject var store: GradesStore

    enum Style { case main, minor, elective }
    let text: String
    let style: Style

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    private var primaryDefault: Color { Color(hex: "#1e3a8a") }          // $color-primary
    private var primaryFeminine: Color { Color(hex: "#ec4899") }        // $color-primary-feminine
    private var textMedium: Color { Color(hex: "#6b7280") }             // $color-text-medium
    private var textDarkDark: Color { Color(hex: "#f9fafb") }           // $color-text-dark-dark

    private var bgBlueBase: Color { Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255) }
    private var bgGrayBase: Color { Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255) }
    private var bgPinkBase: Color { Color(red: 236 / 255, green: 72 / 255, blue: 153 / 255) }

    private var backgroundColor: Color {
        if isFeminine {
            switch style {
            case .main:
                // body.theme-feminine .subject-tag / .subject-tag--main
                return bgPinkBase.opacity(isDark ? 0.8 : 0.18)
            case .minor:
                // body.theme-feminine .subject-tag--minor
                return bgPinkBase.opacity(isDark ? 0.55 : 0.08)
            case .elective:
                return bgGrayBase.opacity(isDark ? 0.45 : 0.10)
            }
        }

        if isDark {
            // body.dark-mode .subject-tag / .subject-tag--minor
            switch style {
            case .main:
                return bgBlueBase.opacity(0.35)
            case .minor:
                return bgGrayBase.opacity(0.55)
            case .elective:
                return bgGrayBase.opacity(0.35)
            }
        }

        // Light + default theme
        switch style {
        case .main:
            return bgBlueBase.opacity(0.12)
        case .minor:
            return bgGrayBase.opacity(0.18)
        case .elective:
            return bgGrayBase.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        if isFeminine {
            if isDark {
                // body.theme-feminine.dark-mode -> immer heller Text
                return textDarkDark
            }
            switch style {
            case .main:
                return primaryFeminine
            case .minor:
                return bgPinkBase.opacity(0.85)
            case .elective:
                return textMedium
            }
        }

        if isDark {
            // body.dark-mode .subject-tag / .subject-tag--minor
            return textDarkDark
        }

        // Light + default theme
        switch style {
        case .main:
            return primaryDefault
        case .minor:
            return textMedium
        case .elective:
            return textMedium
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
}

// MARK: - Extracted small views for HomeView body

private struct HalfYearFilterRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var halfYear: HomeView.HalfYearFilter

    var body: some View {
        HStack(spacing: 6) {
            SegmentButton(title: "Alle", active: halfYear == .all) { halfYear = .all }
            SegmentButton(title: "1. Hj", active: halfYear == .one) { halfYear = .one }
            SegmentButton(title: "2. Hj", active: halfYear == .two) { halfYear = .two }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(toggleBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(toggleStroke, lineWidth: 1)
        )
        .shadow(color: toggleShadow, radius: 8, x: 0, y: 4)
    }

    private var toggleBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color(.systemBackground)
    }

    private var toggleStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    private var toggleShadow: Color {
        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.12)
    }
}


private struct ToolbarTitleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .allowsHitTesting(false)
    }
}

private struct NavigationLinksBackground: View {
    @EnvironmentObject var store: GradesStore
    @Binding var navigateToSettings: Bool
    @Binding var navigateToFinalGrade: Bool

    var body: some View {
        Group {
            NavigationLink(
                destination: AppSettingsView().environmentObject(store),
                isActive: $navigateToSettings
            ) { EmptyView() }
            NavigationLink(
                destination: AbiturExamView().environmentObject(store),
                isActive: $navigateToFinalGrade
            ) { EmptyView() }
        }
    }
}
