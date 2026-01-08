import SwiftUI
import StoreKit
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @EnvironmentObject var store: GradesStore
    @ObservedObject private var notificationInbox = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}

    enum HalfYearFilter: Hashable {
        case all
        case one
        case two
    }

    @State private var halfYear: HalfYearFilter = .all
    @State private var isEditingOrder: Bool = false
    @State private var customOrderWorkingCopy: [String] = []
    @AppStorage("isSubjectGridView") private var isGridView: Bool = false
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false

    // Navigation-States für echte Seiten (kein Sheet)
    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinalGrade: Bool = false


    @State private var greeting: String = ""
    @State private var displayName: String = ""
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false
    @State private var showNotifications: Bool = false
    @State private var selectedSubject: Subject? = nil
    @State private var subjectLinkActive: Bool = false
    @State private var showPraktikumDetail: Bool = false
    @State private var upcomingHoliday: HolidayWindow?

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

    private var animationsOn: Bool { store.animationsEnabled }

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
                    filtered.append(
                        Grade(
                            grade: gw.grade,
                            weight: gw.weight,
                            date: gw.date,
                            note: gw.note,
                            halfYear: gw.halfYear,
                            linkedExamId: gw.linkedExamId
                        )
                    )
                }
            }
            result[subject.name] = filtered
        }
        if let fr = store.fachreferat {
            result["Fachreferat"] = [
                Grade(grade: fr.grade, weight: 3, date: fr.date, note: fr.note, halfYear: nil, linkedExamId: nil)
            ]
        }
        if let practical = store.practicalPerformance {
            let entries = practical.grades.map { entry in
                Grade(
                    grade: entry.grade,
                    weight: 0,
                    date: entry.date,
                    note: entry.note ?? entry.company,
                    halfYear: entry.halfYear,
                    linkedExamId: nil
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

    private func moveSpecialSubjectsToEnd(_ subjects: [Subject]) -> [Subject] {
        var arr = subjects
        var tail: [Subject] = []

        if let idx = arr.firstIndex(where: { $0.name == "Fachreferat" }) {
            tail.append(arr.remove(at: idx))
        }
        if store.schoolType == .fos, let idx = arr.firstIndex(where: { $0.name == "Praktikum" }) {
            tail.append(arr.remove(at: idx))
        }

        arr.append(contentsOf: tail)
        return arr
    }

    private func customOrderMap() -> [String: Int]? {
        guard !store.subjectSortOrder.isEmpty else { return nil }
        var map: [String: Int] = [:]
        for (idx, name) in store.subjectSortOrder.enumerated() {
            map[name] = idx
        }
        return map
    }

    private func countLabel(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }

    private func sortedSubjects(subjectGrades: [String: [Grade]]) -> [Subject] {
        let base = baseSubjectsList()
        switch store.subjectSortMode {
        case .name:
            return moveSpecialSubjectsToEnd(base.sorted(by: comparatorNameAsc()))
        case .name_desc:
            return moveSpecialSubjectsToEnd(base.sorted(by: comparatorNameDesc()))
        case .average:
            return moveSpecialSubjectsToEnd(base.sorted(by: comparatorAverageBestFirst(subjectGrades: subjectGrades)))
        case .average_worst:
            return moveSpecialSubjectsToEnd(base.sorted(by: comparatorAverageWorstFirst(subjectGrades: subjectGrades)))
        case .custom:
            if let map = customOrderMap() {
                return base.sorted(by: comparatorCustom(orderMap: map))
            } else {
                return moveSpecialSubjectsToEnd(base.sorted(by: comparatorNameAsc()))
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

    private func openSubject(_ subject: Subject) {
        selectedSubject = subject
        subjectLinkActive = true
    }

    @ViewBuilder
    private func subjectRowAny(subject: Subject,
                               subjectGrades: [String: [Grade]],
                               fachreferatSubjectName: String?) -> some View {
        let grades = subjectGrades[subject.name] ?? []
        let row = SubjectRowView(
            subject: subject,
            grades: grades,
            fachreferatSubjectName: fachreferatSubjectName
        )
        .contentShape(Rectangle())

        if subject.name == "Praktikum" {
            Button {
                showPraktikumDetail = true
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            Button {
                openSubject(subject)
            } label: {
                row
            }
            .buttonStyle(.plain)
        }
    }

    private func subjectGridItemAny(subject: Subject,
                                    subjectGrades: [String: [Grade]],
                                    fachreferatSubjectName: String?) -> some View {
        let grades = subjectGrades[subject.name] ?? []
        let item = SubjectGridItemView(
            subject: subject,
            grades: grades,
            fachreferatSubjectName: fachreferatSubjectName
        )
        .contentShape(Rectangle())

        if subject.name == "Praktikum" {
            return AnyView(
                Button {
                    showPraktikumDetail = true
                } label: {
                    item
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(
                Button {
                    openSubject(subject)
                } label: {
                    item
                }
                .buttonStyle(.plain)
            )
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

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "de_DE")
        fmt.dateFormat = "EEEE, d. MMMM yyyy"
        return fmt.string(from: Date())
    }

    // MARK: - Header & Overview

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateString)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !displayName.isEmpty {
                ViewThatFits(in: .horizontal) {
                    Text("\(greeting), \(displayName)")
                        .font(.title2.weight(.bold))
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(greeting),")
                        Text(displayName)
                    }
                    .font(.title2.weight(.bold))
                }
                .foregroundStyle(.primary)
            } else {
                Text(greeting)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewStats: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatChip(title: "Gesamt-Ø", value: formatAverage(overallComputed), accent: .indigo)
                StatChip(title: "Fächer", value: "\(subjectsWithoutFachreferat.count)", accent: .cyan)
                StatChip(title: "Noten", value: "\(totalGradesCountComputed)", accent: .orange)
            }
            upcomingStatusChips
        }
    }

    private var upcomingStatuses: [UpcomingStatus] {
        var items: [UpcomingStatus] = []
        if overdueHomeworksCount > 0 {
            items.append(
                UpcomingStatus(
                    title: countLabel(overdueHomeworksCount, singular: "Hausaufgabe fällig", plural: "Hausaufgaben fällig"),
                    count: overdueHomeworksCount,
                    systemImage: "exclamationmark.triangle.fill",
                    accent: .orange
                )
            )
        }
        if homeworkDueTomorrowCount > 0 {
            items.append(
                UpcomingStatus(
                    title: countLabel(homeworkDueTomorrowCount, singular: "Hausaufgabe morgen", plural: "Hausaufgaben morgen"),
                    count: homeworkDueTomorrowCount,
                    systemImage: "clock.badge.exclamationmark",
                    accent: .yellow
                )
            )
        }
        if upcomingExamsNextTwoWeeksCount > 0 {
            items.append(
                UpcomingStatus(
                    title: countLabel(upcomingExamsNextTwoWeeksCount, singular: "Klausur steht an", plural: "Klausuren stehen an"),
                    count: upcomingExamsNextTwoWeeksCount,
                    systemImage: "calendar.badge.clock",
                    accent: .red
                )
            )
        }
        return items
    }

    private var upcomingStatusChips: some View {
        Group {
            if upcomingStatuses.count <= 1 {
                if let status = upcomingStatuses.first {
                    UpcomingStatusChip(status: status, fillsWidth: true)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(upcomingStatuses) { status in
                            UpcomingStatusChip(status: status, fillsWidth: false)
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
                HStack(spacing: 8) {
                    if enableDrag {
                        Button {
                            toggleEditMode(sortedNames: sortedSubjectsComputed.map { $0.name })
                        } label: {
                            Image(systemName: isEditingOrder ? "checkmark" : "arrow.up.arrow.down")
                                .font(.caption.weight(.semibold))
                                .imageScale(.medium)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill((isEditingOrder ? Color.green : Color.cyan).opacity(0.16))
                                )
                                .overlay(
                                    Circle()
                                        .stroke((isEditingOrder ? Color.green : Color.cyan).opacity(0.22), lineWidth: 1)
                                )
                                .foregroundStyle(isEditingOrder ? Color.green : Color.cyan)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isGridView.toggle()
                        }
                    } label: {
                        Image(systemName: isGridView ? "list.bullet" : "squareshape.split.2x2")
                            .font(.caption.weight(.semibold))
                            .imageScale(.medium)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.cyan.opacity(0.16))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.cyan.opacity(0.22), lineWidth: 1)
                            )
                            .foregroundStyle(Color.cyan)
                    }
                    .buttonStyle(.plain)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HalfYearFilterRow(halfYear: $halfYear)
                Text("Ein Fach antippen, um Details und Noten zu öffnen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }



    private func holidayNoticeCard(info: HolidayWindow) -> some View {
        SettingsCard(
            title: "Ferien voraus",
            subtitle: holidaySubtitle(info: info),
            systemImage: "sun.max.fill",
            accent: .orange
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(holidayMessage(info: info))
                    .font(.body)
            }
        }
    }

    private func holidaySubtitle(info: HolidayWindow) -> String {
        let name = friendlyHolidayName(info.name)
        let startText = holidayDateFormatter.string(from: info.start)
        return "\(name) ab \(startText)"
    }

    private func holidayMessage(info: HolidayWindow) -> String {
        let lower = info.name.lowercased()
        let range = holidayRangeText(info: info)
        if lower.contains("sommer") {
            return "Nächste Woche starten die Sommerferien in Bayern (\(range))."
        } else if lower.contains("pfingst") {
            return "Die Pfingstferien stehen vor der Tür (\(range))."
        } else if lower.contains("oster") {
            return "Osterferien nächste Woche (\(range))."
        } else if lower.contains("herbst") || lower.contains("winter") || lower.contains("weihnacht") {
            return "Nächste Woche starten die \(friendlyHolidayName(info.name)) (\(range))."
        } else {
            return "Nächste Woche sind Ferien in Bayern (\(range))."
        }
    }

    private func friendlyHolidayName(_ raw: String) -> String {
        let trimmed = raw.replacingOccurrences(of: "bayern", with: "", options: .caseInsensitive)
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
    }

    private func holidayRangeText(info: HolidayWindow) -> String {
        let start = holidayDateFormatter.string(from: info.start)
        let end = holidayDateFormatter.string(from: info.end)
        return "\(start) – \(end)"
    }

    private var holidayDateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM."
        fmt.locale = Locale(identifier: "de_DE")
        fmt.calendar = Calendar(identifier: .gregorian)
        return fmt
    }


    @ViewBuilder
    private var sortingModeSection: some View {
        if isEditingOrder {
            Section {
                SettingsCard(
                    title: "Sortierung wählen",
                    subtitle: "Wähle eine Standard-Sortierung oder ziehe Fächer frei an ihre Position.",
                    systemImage: "arrow.up.arrow.down.square",
                    accent: .blue
                ) {
                    Picker("Modus", selection: Binding(
                        get: { store.subjectSortMode },
                        set: { newMode in
                            Task {
                                await store.updateSubjectSortMode(mode: newMode)
                            }
                        }
                    )) {
                        ForEach(SubjectSortMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.blue)
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listSectionSeparator(.hidden)
        }
    }

    private func applyModeToWorkingCopy() {
        let base = baseSubjectsList()
        let reordered: [Subject]
        switch store.subjectSortMode {
        case .name:
            reordered = moveSpecialSubjectsToEnd(base.sorted(by: comparatorNameAsc()))
        case .name_desc:
            reordered = moveSpecialSubjectsToEnd(base.sorted(by: comparatorNameDesc()))
        case .average:
            reordered = moveSpecialSubjectsToEnd(base.sorted(by: comparatorAverageBestFirst(subjectGrades: subjectGradesComputed)))
        case .average_worst:
            reordered = moveSpecialSubjectsToEnd(base.sorted(by: comparatorAverageWorstFirst(subjectGrades: subjectGradesComputed)))
        case .custom:
            return
        }
        customOrderWorkingCopy = reordered.map { $0.name }
    }

    @ViewBuilder
    private var loadingSection: some View {
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
    }

    @ViewBuilder
    private var topContentSection: some View {
        Section {
            homeHeader
                .softFadeIn(enabled: animationsOn, delay: 0.01, offset: 10)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            overviewStats
                .softFadeIn(enabled: animationsOn, delay: 0.04, offset: 12)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if let upcomingHoliday {
                holidayNoticeCard(info: upcomingHoliday)
                    .softFadeIn(enabled: animationsOn, delay: 0.07, offset: 10)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            subjectsControlCard
                .softFadeIn(enabled: animationsOn, delay: 0.10, offset: 12)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)



            sortingModeSection
                .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 10)
        }
        .listSectionSeparator(.hidden)
    }

    @ViewBuilder
    private var subjectListSection: some View {
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
                    
                    // If we were in a fixed mode, atomize the switch to custom mode with the new order
                    if store.subjectSortMode != .custom {
                        Task {
                            await store.updateSubjectSortPreferences(mode: .custom, order: customOrderWorkingCopy)
                        }
                    } else {
                        // Just update the custom order
                        Task {
                            await store.updateSubjectCustomOrder(order: customOrderWorkingCopy)
                        }
                    }
                }
            } else if isGridView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(sortedSubjectsComputed.enumerated()), id: \.element.id) { entry in
                        let subject = entry.element
                        let delay = 0.14 + Double(entry.offset) * 0.03
                        subjectGridItemAny(
                            subject: subject,
                            subjectGrades: subjectGradesComputed,
                            fachreferatSubjectName: store.fachreferat?.subjectName
                        )
                        .softFadeIn(enabled: animationsOn, delay: delay, offset: 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(Array(sortedSubjectsComputed.enumerated()), id: \.element.name) { entry in
                    let subject = entry.element
                    let delay = 0.14 + Double(entry.offset) * 0.04
                    subjectRowAny(
                        subject: subject,
                        subjectGrades: subjectGradesComputed,
                        fachreferatSubjectName: store.fachreferat?.subjectName
                    )
                    .softFadeIn(enabled: animationsOn, delay: delay, offset: 14)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listSectionSeparator(.hidden)
    }

    var body: some View {
        List {
            loadingSection
            topContentSection
            subjectListSection
        }
        .environment(\.editMode, .constant(editModeBinding))
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .listSectionSpacing(0)
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showNotifications = true
                } label: {
                    ToolbarIcon(
                        symbol: "bell",
                        showDot: notificationInbox.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !launchOfferPurchased)
                    )
                }
                .accessibilityLabel("Benachrichtigungen")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 0) {
                    Button {
                        onOpenCreationMenu()
                    } label: {
                        ToolbarIcon(symbol: "plus", showDot: false)
                    }
                    .accessibilityLabel("Neu hinzufügen")
                    
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
        .navigationDestination(isPresented: $subjectLinkActive) {
            if let subject = selectedSubject {
                if subject.name == "Fachreferat" {
                    FachreferatDetailView(subject: subject)
                        .environmentObject(store)
                } else {
                    SubjectDetailView(subject: subject)
                        .environmentObject(store)
                }
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $showPraktikumDetail) {
            PraktikumDetailView()
                .environmentObject(store)
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            AppSettingsView().environmentObject(store)
        }
        .navigationDestination(isPresented: $navigateToFinalGrade) {
            AbiturExamView().environmentObject(store)
        }

        .sheet(isPresented: $showHomeworkSheet) {
            HomeworkListView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsInboxView(
                inbox: notificationInbox,
                onSelectNotification: { item in
                    handleNotificationSelection(item)
                },
                onOpenImportant: {
                    // Startet den Kaufprozess via LaunchOfferNotificationManager Flow
                    NotificationCenter.default.post(name: .openLaunchOffer, object: nil)
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showExamSheet) {
            ExamListView()
                .environmentObject(store)
        }
        .onAppear {
            computeGreeting()
            Task { await loadUserDisplayName() }
            Task { await loadUpcomingHolidayNotice() }
        }
        .onChange(of: store.showHolidayHints) { _, enabled in
            if enabled {
                Task { await loadUpcomingHolidayNotice() }
            } else {
                upcomingHoliday = nil
            }
        }
        .onChange(of: subjectLinkActive) { _, active in
            if !active {
                selectedSubject = nil
            }
        }
        .onChange(of: store.subjectSortMode) { _, newMode in
            if isEditingOrder {
                if newMode == .custom {
                    // Restore from persistent custom order
                    customOrderWorkingCopy = store.subjectCustomOrder
                } else {
                    // Apply the fixed mode reordering
                    applyModeToWorkingCopy()
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleEditMode(sortedNames: [String]) {
        if isEditingOrder {
            // Only save the current working copy as the NEW custom baseline 
            // if we are actually in custom mode (or just switched to it).
            if store.subjectSortMode == .custom {
                Task {
                    await store.updateSubjectSortPreferences(mode: .custom, order: customOrderWorkingCopy)
                }
            }
            isEditingOrder = false
        } else {
            // Wenn wir den Modus öffnen, ist die Basis IMMER die gespeicherte Custom-Reihenfolge.
            if store.subjectCustomOrder.isEmpty {
                customOrderWorkingCopy = sortedNames
            } else {
                // Wir nehmen die gespeicherte Custom-Reihenfolge, filtern aber Fächer raus, die evtl. nicht mehr da sind
                customOrderWorkingCopy = store.subjectCustomOrder.filter { sortedNames.contains($0) }
                // Und fügen neue Fächer, die noch nicht in der Custom-Reihenfolge waren, am Ende an
                let missing = sortedNames.filter { !store.subjectCustomOrder.contains($0) }
                customOrderWorkingCopy.append(contentsOf: missing)
            }
            
            // Wenn wir aktuell einen festen Sortier-Modus haben (z.B. Beste zuerst), 
            // dann wenden wir diesen JETZT auf die Working Copy an.
            if store.subjectSortMode != .custom {
                applyModeToWorkingCopy()
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

    private func handleNotificationSelection(_ item: NotificationInboxItem) {
        if let _ = item.homeworkId {
            showHomeworkSheet = true
        } else if let _ = item.examId {
            showExamSheet = true
        } else if item.kind == .daily {
            showHomeworkSheet = true
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
            ErrorLoggingService.logErrorIfEnabled(error)
            displayName = ""
        }
    }

    private func loadUpcomingHolidayNotice() async {
        guard store.showHolidayHints else { return }
        let info = await HolidaysService.shared.upcomingHolidayWithin(days: 7, from: Date())
        await MainActor.run {
            self.upcomingHoliday = info
        }
    }

}

struct LaunchMessageSheetView: View {
    @EnvironmentObject private var store: GradesStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onLater: () -> Void
    let onPurchaseSuccess: () -> Void

    @State private var purchaseStatusMessage: String?
    @State private var purchaseStatusIsError: Bool = false
    @State private var showOfferCodeSheet = false

    private var accentPrimary: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : Color(hex: "#2563eb")
    }

    private var ctaAccent: Color {
        if store.theme == "feminine" {
            return colorScheme == .dark ? Color(hex: "#f9a8d4") : Color(hex: "#f472b6")
        }
        return colorScheme == .dark ? Color(hex: "#93c5fd") : Color(hex: "#3b82f6")
    }

    private var cardBackground: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return store.theme == "feminine" ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
    }

    private var cardBorder: Color {
        accentPrimary.opacity(colorScheme == .dark ? 0.24 : 0.12)
    }

    private var heroGradient: LinearGradient {
        if store.theme == "feminine" {
            let colors: [Color]
            if colorScheme == .dark {
                colors = [
                    Color(hex: "#be123c"),
                    Color(hex: "#db2777"),
                    Color(hex: "#f472b6")
                ]
            } else {
                colors = [
                    Color(hex: "#fb7185"),
                    Color(hex: "#f472b6"),
                    Color(hex: "#fbcfe8")
                ]
            }
            return LinearGradient(
                gradient: Gradient(colors: colors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        let colors: [Color]
        if colorScheme == .dark {
            colors = [
                Color(hex: "#1d4ed8"),
                Color(hex: "#0284c7"),
                Color(hex: "#0ea5e9")
            ]
        } else {
            colors = [
                Color(hex: "#60a5fa"),
                Color(hex: "#38bdf8"),
                Color(hex: "#22d3ee")
            ]
        }
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                ctaAccent,
                accentPrimary.opacity(colorScheme == .dark ? 0.9 : 1)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var spotlightPriceFont: Font {
        .system(size: 42, weight: .bold, design: .rounded)
    }

    private var offerDisplayPrice: String {
        let price = storeKit.product?.displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let price, !price.isEmpty {
            return price
        }
        return "3,99€"
    }

    private var yearlyDisplayPrice: String {
        let price = storeKit.subscriptionProduct?.displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let price, !price.isEmpty {
            return price
        }
        return "9,99€"
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                heroSection
                priceSpotlight
                benefitsList
                Spacer(minLength: 8)
                ctaSection
                finePrint
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(
            ThemedBackground(
                isDark: store.darkMode,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            )
        )
        .task {
            if storeKit.product == nil || storeKit.subscriptionProduct == nil || storeKit.monthlySubscriptionProduct == nil {
                await storeKit.loadProduct()
            }
        }
        .offerCodeRedemption(isPresented: $showOfferCodeSheet) { result in
            switch result {
            case .success:
                onPurchaseSuccess()
            case .failure(let error):
                print("Offer code redemption failed: \(error)")
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("EARLY-BIRD")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                    )
                Label("Kostenpflichtig ab 01.02.2026", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            Text("Pro für immer freischalten")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text("Als Dank für deine frühe Nutzung bekommst du das einmalige Early-Bird Upgrade statt Abo.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.2),
            radius: 10,
            x: 0,
            y: 6
        )
    }

    private var priceSpotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Einmaliger Preis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(offerDisplayPrice)
                        .font(spotlightPriceFont)
                        .foregroundStyle(.primary)
                    Text("einmalig")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ctaAccent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(offerDisplayPrice)
                        .font(spotlightPriceFont)
                        .foregroundStyle(.primary)
                    Text("einmalig")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ctaAccent)
                }
            }
            Text("Lifetime Pro inkl. aller Features • statt \(yearlyDisplayPrice) pro Jahr ab 01.02.2026")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Im Abo enthalten")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            featureRow(
                title: "Voller Zugriff auf Noten Manager",
                subtitle: "Alle Funktionen ohne Einschränkungen."
            )
            featureRow(
                title: "Alles an einem Ort",
                subtitle: "Noten, Prüfungen und Hausaufgaben."
            )
            featureRow(
                title: "Erinnerungen & Live-Aktivitäten",
                subtitle: "Wichtige Termine im Blick."
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                handlePurchase()
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Early-Bird Upgrade sichern")
                            .font(.headline.weight(.bold))
                        HStack(spacing: 6) {
                            Text(offerDisplayPrice)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(ctaAccent)
                            Text("einmalig • dauerhaft Pro")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if storeKit.isProcessingPurchase {
                        ProgressView()
                            .tint(ctaAccent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ctaAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(highlightGradient, lineWidth: 1.5)
                )
                .shadow(
                    color: ctaAccent.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    radius: 8,
                    x: 0,
                    y: 5
                )
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isProcessingPurchase || storeKit.product == nil)

            Button("Später entscheiden") {
                onLater()
                dismiss()
            }
            .buttonStyle(SoftTintButtonStyle(accent: Color(.secondaryLabel)))
            .disabled(storeKit.isProcessingPurchase)

            if let message = purchaseStatusMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(purchaseStatusIsError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if storeKit.product == nil {
                Text("Produkte werden geladen...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var finePrint: some View {
        VStack(spacing: 6) {
            Text("Einmaliger Kauf, kein Abo. Pro bleibt dauerhaft und lässt sich über deine Apple ID wiederherstellen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showOfferCodeSheet = true
            } label: {
                Text("Code einlösen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ctaAccent)
                    .underline()
            }
            .buttonStyle(.plain)

            Button {
                handleRestore()
            } label: {
                Text("Käufe wiederherstellen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ctaAccent)
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isRestoring)
        }
        .padding(.top, 2)
    }

    private func featureRow(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ctaAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handlePurchase() {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        Task {
            if storeKit.product == nil {
                purchaseStatusMessage = "Produkte werden geladen. Bitte erneut versuchen."
                purchaseStatusIsError = false
                await storeKit.loadProduct()
                return
            }
            let result = await storeKit.purchaseLaunchOffer()
            switch result {
            case .success:
                onPurchaseSuccess()
                dismiss()
            case .pending:
                purchaseStatusMessage = "Der Kauf wird noch geprüft. Wir schalten die Vollversion frei, sobald der Vorgang abgeschlossen ist."
                purchaseStatusIsError = false
            case .cancelled:
                purchaseStatusMessage = "Kauf abgebrochen."
                purchaseStatusIsError = false
            case .failed(let failure):
                purchaseStatusMessage = purchaseFailureMessage(failure)
                purchaseStatusIsError = true
            }
        }
    }

    private func handleRestore() {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        Task {
            let result = await storeKit.restorePurchases()
            switch result {
            case .success(let found):
                if found {
                    onPurchaseSuccess()
                    dismiss()
                    return
                }
                purchaseStatusMessage = "Keine Käufe zum Wiederherstellen gefunden."
                purchaseStatusIsError = false
            case .failed(let failure):
                purchaseStatusMessage = restoreFailureMessage(failure)
                purchaseStatusIsError = true
            }
        }
    }

    private func restoreFailureMessage(_ failure: StoreKitManager.RestoreFailure) -> String {
        switch failure {
        case .network:
            return "Keine Internetverbindung. Bitte später erneut versuchen."
        case .notAllowed:
            return "Wiederherstellen ist auf diesem Gerät nicht erlaubt."
        case .unknown:
            return "Wiederherstellung fehlgeschlagen. Bitte später erneut versuchen."
        }
    }

    private func purchaseFailureMessage(_ failure: StoreKitManager.PurchaseFailure) -> String {
        switch failure {
        case .offerExpired:
            return "Das Angebot ist abgelaufen."
        case .productUnavailable:
            return "Das Produkt ist aktuell nicht verfügbar. Bitte später erneut versuchen."
        case .network:
            return "Keine Internetverbindung. Bitte später erneut versuchen."
        case .notAllowed:
            return "Käufe sind auf diesem Gerät nicht erlaubt."
        case .verificationFailed:
            return "Kauf konnte nicht bestätigt werden. Bitte später erneut versuchen."
        case .unknown:
            return "Kauf konnte nicht abgeschlossen werden. Bitte später erneut versuchen."
        }
    }

}

struct SubscriptionOfferSheetView: View {
    @EnvironmentObject private var store: GradesStore
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onLater: () -> Void
    let onPurchaseSuccess: () -> Void

    @State private var purchaseStatusMessage: String?
    @State private var purchaseStatusIsError: Bool = false
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var showOfferCodeSheet = false

    private enum SubscriptionPlan: String, CaseIterable {
        case yearly
        case monthly

        var productId: String {
            switch self {
            case .yearly:
                return "noten_manager_pro_yearly"
            case .monthly:
                return "noten_manager_pro_monthly"
            }
        }

        var title: String {
            switch self {
            case .yearly:
                return "Jahresabo"
            case .monthly:
                return "Monatsabo"
            }
        }

        var periodLabel: String {
            switch self {
            case .yearly:
                return "Jahr"
            case .monthly:
                return "Monat"
            }
        }

        var detail: String {
            switch self {
            case .yearly:
                return "Bester Preis"
            case .monthly:
                return "Flexibel monatlich"
            }
        }
    }

    private var accentPrimary: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : Color(hex: "#2563eb")
    }

    private var ctaAccent: Color {
        if store.theme == "feminine" {
            return colorScheme == .dark ? Color(hex: "#f9a8d4") : Color(hex: "#f472b6")
        }
        return colorScheme == .dark ? Color(hex: "#93c5fd") : Color(hex: "#3b82f6")
    }

    private var cardBackground: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return store.theme == "feminine" ? Color(hex: "#fff1f7") : Color(hex: "#eef2ff")
    }

    private var cardBorder: Color {
        accentPrimary.opacity(colorScheme == .dark ? 0.24 : 0.12)
    }

    private var heroGradient: LinearGradient {
        if store.theme == "feminine" {
            let colors: [Color]
            if colorScheme == .dark {
                colors = [
                    Color(hex: "#be123c"),
                    Color(hex: "#db2777"),
                    Color(hex: "#f472b6")
                ]
            } else {
                colors = [
                    Color(hex: "#fb7185"),
                    Color(hex: "#f472b6"),
                    Color(hex: "#fbcfe8")
                ]
            }
            return LinearGradient(
                gradient: Gradient(colors: colors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        let colors: [Color]
        if colorScheme == .dark {
            colors = [
                Color(hex: "#1d4ed8"),
                Color(hex: "#0284c7"),
                Color(hex: "#0ea5e9")
            ]
        } else {
            colors = [
                Color(hex: "#60a5fa"),
                Color(hex: "#38bdf8"),
                Color(hex: "#22d3ee")
            ]
        }
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var highlightGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                ctaAccent,
                accentPrimary.opacity(colorScheme == .dark ? 0.9 : 1)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var yearlyDisplayPrice: String {
        let price = storeKit.subscriptionProduct?.displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let price, !price.isEmpty {
            return price
        }
        return "9,99€"
    }

    private var monthlyDisplayPrice: String {
        let price = storeKit.monthlySubscriptionProduct?.displayPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        if let price, !price.isEmpty {
            return price
        }
        return "1,99€"
    }

    private var ctaDetailLine: String {
        let price = priceValue(for: selectedPlan)
        return "\(selectedPlan.title) • danach \(price) / \(selectedPlan.periodLabel)"
    }

    private var selectedSubscriptionAvailable: Bool {
        switch selectedPlan {
        case .yearly:
            return storeKit.subscriptionProduct != nil
        case .monthly:
            return storeKit.monthlySubscriptionProduct != nil
        }
    }

    private var yearlySavingsText: String? {
        let yearlyPrice = storeKit.subscriptionProduct?.price ?? Decimal(9.99)
        let monthlyPrice = storeKit.monthlySubscriptionProduct?.price ?? Decimal(1.99)
        let yearlyFromMonthly = monthlyPrice * Decimal(12)
        guard yearlyFromMonthly > 0 else { return nil }
        let savings = yearlyFromMonthly - yearlyPrice
        guard savings > 0 else { return nil }
        let percent = (savings / yearlyFromMonthly) * Decimal(100)
        let percentValue = NSDecimalNumber(decimal: percent).doubleValue
        let percentRounded = Int(percentValue.rounded())
        let formatStyle = storeKit.subscriptionProduct?.priceFormatStyle
            ?? storeKit.monthlySubscriptionProduct?.priceFormatStyle
        let savingsText: String
        if let formatStyle {
            savingsText = savings.formatted(formatStyle)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = Locale.current
            savingsText = formatter.string(from: NSDecimalNumber(decimal: savings))
                ?? String(format: "%.2f€", NSDecimalNumber(decimal: savings).doubleValue)
        }
        if percentRounded > 0 {
            return "Spare \(savingsText) bei jährlicher Zahlung (\(percentRounded)%)."
        }
        return "Spare \(savingsText) pro Jahr."
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 14) {
                heroSection
                planSelection
                benefitsList
                Spacer(minLength: 6)
                ctaSection
                finePrint
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .background(
            ThemedBackground(
                isDark: store.darkMode,
                isFeminine: store.theme == "feminine",
                intensity: store.themeBackgroundIntensity
            )
        )
        .task {
            if storeKit.subscriptionProduct == nil || storeKit.monthlySubscriptionProduct == nil {
                await storeKit.loadProduct()
            }
        }
        .offerCodeRedemption(isPresented: $showOfferCodeSheet) { result in
            switch result {
            case .success:
                onPurchaseSuccess()
            case .failure(let error):
                // StoreKit handles UI for failure usually, but we can log
                print("Offer code redemption failed: \(error)")
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("PRO ABO")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                    )
                Label("7 Tage gratis", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Text("Noten Manager Pro")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Teste 7 Tage kostenlos und entscheide dich danach für Jahres- oder Monatsabo.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(heroGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.2),
            radius: 10,
            x: 0,
            y: 6
        )
    }

    private var planSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Abo wählen")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                planCard(.yearly)
                planCard(.monthly)
            }
            if let savingsText = yearlySavingsText {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                    Text(savingsText)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ctaAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(ctaAccent.opacity(colorScheme == .dark ? 0.22 : 0.14))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Im Abo enthalten")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            featureRow(
                title: "Voller Zugriff auf Noten Manager",
                subtitle: "Alle Funktionen ohne Einschränkungen."
            )
            featureRow(
                title: "Alles an einem Ort",
                subtitle: "Noten, Prüfungen und Hausaufgaben."
            )
            featureRow(
                title: "Erinnerungen & Live-Aktivitäten",
                subtitle: "Wichtige Termine im Blick."
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button {
                handlePurchase()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("7 Tage gratis starten")
                            .font(.headline.weight(.bold))
                        Text(ctaDetailLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if storeKit.isProcessingSubscriptionPurchase {
                        ProgressView()
                            .tint(ctaAccent)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ctaAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(highlightGradient, lineWidth: 1.5)
                )
                .shadow(
                    color: ctaAccent.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    radius: 8,
                    x: 0,
                    y: 5
                )
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isProcessingSubscriptionPurchase || !selectedSubscriptionAvailable)

            if let message = purchaseStatusMessage, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(purchaseStatusIsError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if !selectedSubscriptionAvailable {
                Text("Produkte werden geladen...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var finePrint: some View {
        VStack(spacing: 6) {
            Text(finePrintText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button {
                showOfferCodeSheet = true
            } label: {
                Text("Code einlösen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ctaAccent)
                    .underline()
            }
            .buttonStyle(.plain)

            Button {
                handleRestore()
            } label: {
                Text("Käufe wiederherstellen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ctaAccent)
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isRestoring)
        }
        .padding(.top, 2)
    }

    private func handlePurchase() {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        Task {
            if !selectedSubscriptionAvailable {
                purchaseStatusMessage = "Produkte werden geladen. Bitte erneut versuchen."
                purchaseStatusIsError = false
                await storeKit.loadProduct()
                return
            }
            let result = await storeKit.purchaseSubscription(productId: selectedPlan.productId)
            switch result {
            case .success:
                onPurchaseSuccess()
                dismiss()
            case .pending:
                purchaseStatusMessage = "Der Kauf wird noch geprüft. Wir schalten die Vollversion frei, sobald der Vorgang abgeschlossen ist."
                purchaseStatusIsError = false
            case .cancelled:
                purchaseStatusMessage = "Kauf abgebrochen."
                purchaseStatusIsError = false
            case .failed(let failure):
                purchaseStatusMessage = purchaseFailureMessage(failure)
                purchaseStatusIsError = true
            }
        }
    }

    private func handleRestore() {
        purchaseStatusMessage = nil
        purchaseStatusIsError = false
        Task {
            let result = await storeKit.restorePurchases()
            switch result {
            case .success(let found):
                if found {
                    onPurchaseSuccess()
                    dismiss()
                    return
                }
                purchaseStatusMessage = "Keine Käufe zum Wiederherstellen gefunden."
                purchaseStatusIsError = false
            case .failed(let failure):
                purchaseStatusMessage = restoreFailureMessage(failure)
                purchaseStatusIsError = true
            }
        }
    }

    private func restoreFailureMessage(_ failure: StoreKitManager.RestoreFailure) -> String {
        switch failure {
        case .network:
            return "Keine Internetverbindung. Bitte später erneut versuchen."
        case .notAllowed:
            return "Wiederherstellen ist auf diesem Gerät nicht erlaubt."
        case .unknown:
            return "Wiederherstellung fehlgeschlagen. Bitte später erneut versuchen."
        }
    }

    private var finePrintText: String {
        let price = priceValue(for: selectedPlan)
        return "7 Tage kostenlos, danach \(price) / \(selectedPlan.periodLabel). Automatische Verlängerung, jederzeit kündbar."
    }

    private func priceValue(for plan: SubscriptionPlan) -> String {
        switch plan {
        case .yearly:
            return yearlyDisplayPrice
        case .monthly:
            return monthlyDisplayPrice
        }
    }

    private func featureRow(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ctaAccent)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        let priceLabel = priceLabel(for: plan)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedPlan = plan
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(ctaAccent)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Text(priceLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? ctaAccent : .primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(plan.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackground)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(highlightGradient, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cardBorder, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func priceLabel(for plan: SubscriptionPlan) -> String {
        "\(priceValue(for: plan)) / \(plan.periodLabel)"
    }

    private func purchaseFailureMessage(_ failure: StoreKitManager.PurchaseFailure) -> String {
        switch failure {
        case .offerExpired:
            return "Das Angebot ist abgelaufen."
        case .productUnavailable:
            return "Das Produkt ist aktuell nicht verfügbar. Bitte später erneut versuchen."
        case .network:
            return "Keine Internetverbindung. Bitte später erneut versuchen."
        case .notAllowed:
            return "Käufe sind auf diesem Gerät nicht erlaubt."
        case .verificationFailed:
            return "Kauf konnte nicht bestätigt werden. Bitte später erneut versuchen."
        case .unknown:
            return "Kauf konnte nicht abgeschlossen werden. Bitte später erneut versuchen."
        }
    }
}

struct SubjectRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore

    private struct SubjectAccent {
        let primary: Color
        let secondary: Color
    }

    let subject: Subject
    let grades: [Grade]
    let fachreferatSubjectName: String?

    private func avg(_ subject: Subject) -> Double? {
        guard !grades.isEmpty else { return nil }
        func calculateGradeWeight(_ subject: Subject, _ grade: Grade) -> Double {
            if subject.name == "Fachreferat" { return 3 }
            if subject.name == "Praktikum" { return 1 }
            return store.effectiveGradeWeight(subjectType: subject.type, rawWeight: grade.weight)
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

    private func descriptor(for average: Double?, gradesCount: Int, isFachreferat: Bool, isPraktikum: Bool) -> String {
        if isFachreferat {
            return gradesCount == 0 ? "Fachreferat noch nicht hinterlegt" : "Einmalige Bewertung gespeichert"
        }
        if gradesCount == 0 {
            return isPraktikum ? "Noch keine Noten erfasst" : "Noch keine Noten erfasst"
        }
        guard let avg = average else { return "Noch keine Noten erfasst" }
        if avg >= 10 { return "Sehr starker Schnitt" }
        if avg >= 7 { return "Stabiler Schnitt" }
        if avg >= 4 { return "Ausbaufähig – dranbleiben" }
        return "Roter Bereich – Schritt für Schritt"
    }

    private func progress(for average: Double) -> Double {
        let clamped = max(0, min(15, average))
        return clamped / 15
    }

    private func accent(for subject: Subject) -> SubjectAccent {
        let feminine = store.theme == "feminine"

        let mainPrimary = feminine ? Color(hex: "#ec4899") : Color(hex: "#2563eb")
        let mainSecondary = feminine ? Color(hex: "#c084fc") : Color(hex: "#38bdf8")
        let minorPrimary = feminine ? Color(hex: "#a855f7") : Color(hex: "#0ea5e9")
        let minorSecondary = feminine ? Color(hex: "#f472b6") : Color(hex: "#22c55e")
        let electivePrimary = feminine ? Color(hex: "#f97316") : Color(hex: "#6b7280")
        let electiveSecondary = feminine ? Color(hex: "#fb7185") : Color(hex: "#94a3b8")

        if subject.name == "Fachreferat" {
            return SubjectAccent(
                primary: feminine ? Color(hex: "#d946ef") : Color(hex: "#8b5cf6"),
                secondary: feminine ? Color(hex: "#f472b6") : Color(hex: "#60a5fa")
            )
        }

        if subject.name == "Praktikum" {
            return SubjectAccent(
                primary: Color(hex: "#f59e0b"),
                secondary: Color(hex: "#fcd34d")
            )
        }

        if subject.isElective {
            return SubjectAccent(
                primary: electivePrimary,
                secondary: electiveSecondary
            )
        }

        if subject.type == 1 {
            return SubjectAccent(
                primary: mainPrimary,
                secondary: mainSecondary
            )
        }

        return SubjectAccent(
            primary: minorPrimary,
            secondary: minorSecondary
        )
    }

    private func cardBaseColors() -> (Color, Color) {
        if colorScheme == .dark {
            if store.theme == "feminine" {
                return (Color(hex: "#1b1022"), Color(hex: "#120a16"))
            }
            return (Color(hex: "#0b1220"), Color(hex: "#111827"))
        }
        if store.theme == "feminine" {
            return (Color(hex: "#fff1f7"), Color(hex: "#fff7fb"))
        }
        return (Color(hex: "#eef2ff"), Color(hex: "#f8fafc"))
    }

    private func cardSurface(accent: SubjectAccent) -> some View {
        let base = cardBaseColors()
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [base.0, base.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.primary.opacity(colorScheme == .dark ? 0.10 : 0.06),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    private func cardStroke(accent: SubjectAccent) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(
                accent.primary.opacity(colorScheme == .dark ? 0.20 : 0.12),
                lineWidth: 1
            )
    }

    private func gradePillBackground(_ color: Color) -> some View {
        Capsule(style: .continuous)
            .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1)
            )
    }

    var body: some View {
        let average = avg(subject)
        let gradesCount = grades.count

        let isFachreferat = subject.name == "Fachreferat"
        let isPraktikum = subject.name == "Praktikum"
        let isSport = subject.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "sport"
        let accent = accent(for: subject)

        let displayName: String = {
            if isFachreferat, let frName = fachreferatSubjectName, !frName.isEmpty {
                return "Fachreferat in \(frName)"
            }
            if isPraktikum {
                return "Praktikum (11.)"
            }
            return subject.name
        }()

        let tag: Tag? = {
            if isFachreferat {
                return nil
            } else if isPraktikum {
                return Tag(text: "Praktikum", style: .minor)
            } else if isSport {
                return Tag(text: "Nicht einbringbar", style: .elective)
            } else if subject.isElective {
                return Tag(text: "Wahlfach", style: .elective)
            }
            return Tag(text: subject.type == 1 ? "Hauptfach" : "Nebenfach", style: subject.type == 1 ? .main : .minor)
        }()

        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let tag {
                        tag
                    }
                }

                Text(descriptor(for: average, gradesCount: gradesCount, isFachreferat: isFachreferat, isPraktikum: isPraktikum))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let avg = average {
                    GeometryReader { geo in
                        let ratio = progress(for: avg)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08),
                                            Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accent.primary, accent.secondary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 6)
                    .padding(.trailing, 8)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(formatAverage(average))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(gradePillBackground(gradeClassColor(average)))
                    .foregroundStyle(gradeClassColor(average))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(cardSurface(accent: accent))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(cardStroke(accent: accent))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08),
            radius: 6,
            x: 0,
            y: 4
        )
    }
}

struct Tag: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme

    enum Style { case main, minor, elective }
    let text: String
    let style: Style

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { colorScheme == .dark }

    private func palette() -> (Color, Color, Color) {
        if isDark {
            let base: Color
            if isFeminine {
                switch style {
                case .main:
                    base = Color(hex: "#f472b6")
                case .minor:
                    base = Color(hex: "#c084fc")
                case .elective:
                    base = Color(hex: "#fb923c")
                }
            } else {
                switch style {
                case .main:
                    base = Color(hex: "#60a5fa")
                case .minor:
                    base = Color(hex: "#34d399")
                case .elective:
                    base = Color(hex: "#fb923c")
                }
            }
            return (
                base.opacity(0.20),
                Color(hex: "#e2e8f0"),
                base.opacity(0.32)
            )
        }

        if isFeminine {
            switch style {
            case .main:
                return (Color(hex: "#fce7f3"), Color(hex: "#9d174d"), Color(hex: "#f9a8d4"))
            case .minor:
                return (Color(hex: "#fae8ff"), Color(hex: "#6b21a8"), Color(hex: "#d8b4fe"))
            case .elective:
                return (Color(hex: "#ffedd5"), Color(hex: "#9a3412"), Color(hex: "#fdba74"))
            }
        }

        switch style {
        case .main:
            return (Color(hex: "#dbeafe"), Color(hex: "#1e3a8a"), Color(hex: "#93c5fd"))
        case .minor:
            return (Color(hex: "#dcfce7"), Color(hex: "#166534"), Color(hex: "#86efac"))
        case .elective:
            return (Color(hex: "#ffedd5"), Color(hex: "#9a3412"), Color(hex: "#fdba74"))
        }
    }

    var body: some View {
        let colors = palette()
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(colors.0.opacity(isDark ? 0.20 : 0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(colors.2.opacity(isDark ? 0.30 : 0.22), lineWidth: 1)
            )
            .foregroundStyle(colors.1)
    }
}

private struct UpcomingStatus: Identifiable {
    let id = UUID()
    let title: String
    let count: Int?
    let systemImage: String
    let accent: Color
}

private struct UpcomingStatusChip: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore

    let status: UpcomingStatus
    let fillsWidth: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let countText {
                Text(countText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(status.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(status.accent.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    )
            }

            Text(status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: status.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(status.accent)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: !fillsWidth, vertical: false)
        .background(tileSurface)
        .overlay(tileBorder)
    }

    private var countText: String? {
        guard let count = status.count else { return nil }
        return "\(count)"
    }

    private var tileSurface: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tileTop, tileBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                status.accent.opacity(colorScheme == .dark ? 0.08 : 0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
    }

    private var tileBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(status.accent.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
    }

    private var tileTop: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#1b1022") : Color(hex: "#0b1220")
        }
        return store.theme == "feminine" ? Color(hex: "#fff5fb") : Color(hex: "#f1f5ff")
    }

    private var tileBottom: Color {
        if colorScheme == .dark {
            return store.theme == "feminine" ? Color(hex: "#120a16") : Color(hex: "#111827")
        }
        return store.theme == "feminine" ? Color(hex: "#fffafb") : Color(hex: "#f8fafc")
    }
}

// MARK: - Extracted small views for HomeView body

private struct HalfYearFilterRow: View {
    @Binding var halfYear: HomeView.HalfYearFilter

    var body: some View {
        SegmentedPicker(
            selection: $halfYear,
            options: [
                SegmentedPickerOption(title: "Alle", value: .all),
                SegmentedPickerOption(title: "1. Hj", value: .one),
                SegmentedPickerOption(title: "2. Hj", value: .two)
            ],
            accent: .cyan
        )
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

struct SubjectGridItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var store: GradesStore

    let subject: Subject
    let grades: [Grade]
    let fachreferatSubjectName: String?

    private func avg(_ subject: Subject) -> Double? {
        guard !grades.isEmpty else { return nil }
        func calculateGradeWeight(_ subject: Subject, _ grade: Grade) -> Double {
            if subject.name == "Fachreferat" { return 3 }
            if subject.name == "Praktikum" { return 1 }
            return store.effectiveGradeWeight(subjectType: subject.type, rawWeight: grade.weight)
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
        return String(format: "%.1f", v)
    }

    private func gradeClassColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private func progress(for average: Double) -> Double {
        let clamped = max(0, min(15, average))
        return clamped / 15
    }

    private struct SubjectAccent {
        let primary: Color
        let secondary: Color
    }

    private func accent(for subject: Subject) -> SubjectAccent {
        let feminine = store.theme == "feminine"
        let mainPrimary = feminine ? Color(hex: "#ec4899") : Color(hex: "#2563eb")
        let mainSecondary = feminine ? Color(hex: "#c084fc") : Color(hex: "#38bdf8")
        let minorPrimary = feminine ? Color(hex: "#a855f7") : Color(hex: "#0ea5e9")
        let minorSecondary = feminine ? Color(hex: "#f472b6") : Color(hex: "#22c55e")
        let electivePrimary = feminine ? Color(hex: "#f97316") : Color(hex: "#6b7280")
        let electiveSecondary = feminine ? Color(hex: "#fb7185") : Color(hex: "#94a3b8")

        if subject.name == "Fachreferat" {
            return SubjectAccent(
                primary: feminine ? Color(hex: "#d946ef") : Color(hex: "#8b5cf6"),
                secondary: feminine ? Color(hex: "#f472b6") : Color(hex: "#60a5fa")
            )
        }
        if subject.name == "Praktikum" {
            return SubjectAccent(primary: Color(hex: "#f59e0b"), secondary: Color(hex: "#fcd34d"))
        }
        if subject.isElective {
            return SubjectAccent(primary: electivePrimary, secondary: electiveSecondary)
        }
        if subject.type == 1 {
            return SubjectAccent(primary: mainPrimary, secondary: mainSecondary)
        }
        return SubjectAccent(primary: minorPrimary, secondary: minorSecondary)
    }

    private func cardBaseColors() -> (Color, Color) {
        if colorScheme == .dark {
            if store.theme == "feminine" {
                return (Color(hex: "#1b1022"), Color(hex: "#120a16"))
            }
            return (Color(hex: "#0b1220"), Color(hex: "#111827"))
        }
        if store.theme == "feminine" {
            return (Color(hex: "#fff1f7"), Color(hex: "#fff7fb"))
        }
        return (Color(hex: "#eef2ff"), Color(hex: "#f8fafc"))
    }

    private func gradePillBackground(_ color: Color) -> some View {
        Capsule(style: .continuous)
            .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(color.opacity(colorScheme == .dark ? 0.30 : 0.20), lineWidth: 1)
            )
    }

    var body: some View {
        let average = avg(subject)
        let accent = accent(for: subject)
        let base = cardBaseColors()
        let isFachreferat = subject.name == "Fachreferat"
        let isPraktikum = subject.name == "Praktikum"

        let displayName: String = {
            if isFachreferat, let frName = fachreferatSubjectName, !frName.isEmpty {
                return frName
            }
            if isPraktikum {
                return "Praktikum"
            }
            return subject.name
        }()

        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(colorScheme == .dark ? .white : Color(hex: "#0f172a"))
                    
                    if isFachreferat {
                        Text("Fachreferat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent.primary.opacity(0.8))
                    } else if isPraktikum {
                        Text("11. Klasse")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent.primary.opacity(0.8))
                    } else {
                        Text(subject.type == 1 ? "Hauptfach" : (subject.isElective ? "Wahlfach" : "Nebenfach"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent.primary.opacity(0.8))
                    }
                }
                Spacer(minLength: 4)
                
                Text(formatAverage(average))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(gradeClassColor(average))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(gradePillBackground(gradeClassColor(average)))
            }

            if let avg = average {
                GeometryReader { geo in
                    let ratio = progress(for: avg)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [accent.primary, accent.secondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * ratio)
                    }
                }
                .frame(height: 5)
            } else {
                Spacer().frame(height: 5)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [base.0, base.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [accent.primary.opacity(colorScheme == .dark ? 0.10 : 0.05), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.primary.opacity(colorScheme == .dark ? 0.20 : 0.10), lineWidth: 1)
        )
    }
}
