import SwiftUI
import StoreKit
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    @EnvironmentObject var store: GradesStore
    @EnvironmentObject var biometricManager: BiometricAuthManager
    @EnvironmentObject var offlineManager: OfflineModeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var notificationInbox = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}
    var onToggleOfflineBanner: () -> Void = {}

    enum HalfYearFilter: Hashable {
        case all
        case one
        case two
    }

    @State private var halfYear: HalfYearFilter = .all
    @State private var isEditingOrder: Bool = false
    @State private var customOrderWorkingCopy: [String] = []
    // isSubjectGridView is now managed by GradesStore
    // showNextExamCard is now managed by GradesStore
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false

    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinalGrade: Bool = false
    @State private var showMigrationInfoSheet: Bool = false
    @State private var showDebugSheet: Bool = false
    @State private var showWhatsNewSheet: Bool = false


    @State private var greeting: String = ""
    @State private var displayName: String = ""
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false
    @State private var showNotifications: Bool = false
    @State private var showDailySummarySheet: Bool = false
    @State private var selectedSubject: Subject? = nil
    @State private var subjectLinkActive: Bool = false
    @State private var showPraktikumDetail: Bool = false
    @State private var upcomingHoliday: HolidayWindow?
    @State private var detailExam: Exam?
    @State private var detailHomework: Homework?
    @State private var editingExam: Exam?
    @State private var editingHomework: Homework?

    private var subjectsWithoutFachreferat: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var hasFachreferat: Bool {
        store.fachreferat != nil
    }

    private var hasSeminar: Bool {
        store.seminarPerformance != nil
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
        func halfValue(_ half: Int) -> Double? {
            // Check if this half-year is dropped
            if let dropped = subject.droppedHalfYear, dropped == half {
                return nil
            }
            return store.bestAvailableHalfYearValue(subject: subject, halfYear: half)
        }
        switch halfYear {
        case .one:
            if let fixed = subject.fixedAverageHalfYear1 { return fixed }
            return halfValue(1)
        case .two:
            if let fixed = subject.fixedAverageHalfYear2 { return fixed }
            return halfValue(2)
        case .all:
            if let fixed = subject.fixedAverageYearly { return fixed }
            let v1 = halfValue(1)
            let v2 = halfValue(2)
            switch (v1, v2) {
            case let (a?, b?):
                return (a + b) / 2.0
            case let (a?, nil):
                return a
            case let (nil, b?):
                return b
            default:
                return nil
            }
        }
    }

    private func baseSubjectsList() -> [Subject] {
        var base = subjectsWithoutFachreferat
        if hasFachreferat {
            base.append(Subject(name: "Fachreferat", type: 0, date: Date()))
        }
        if hasSeminar {
            base.append(Subject(name: "Seminar", type: 0, date: Date()))
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

    // MARK: - Daily Summary Helper
    
    private var tomorrowSummaryData: DailySummaryData {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        
        let exams: [Exam] = store.allExams.filter { exam in
            !exam.isCompleted && cal.isDate(exam.date, inSameDayAs: tomorrow)
        }
        
        let homeworks: [Homework] = store.allHomeworks.filter { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDate(due, inSameDayAs: tomorrow)
        }
        
        return DailySummaryData(exams: exams, homeworks: homeworks, date: tomorrow)
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

    private func handlePrivacyToggle() {
        if store.isPrivacyModeActive {
            // Unblur - require Face ID if enabled
            if biometricManager.isEnabledForActiveUser {
                Task {
                    let success = await biometricManager.authenticate(reason: "Noten anzeigen")
                    if success {
                        store.updatePrivacyMode(active: false)
                    }
                }
            } else {
                store.updatePrivacyMode(active: false)
            }
        } else {
            // Blur - no auth needed to blur
            store.updatePrivacyMode(active: true)
        }
    }

    // MARK: - Overall formatting

    private func halfValue(_ subject: Subject, half: Int) -> Double? {
        store.bestAvailableHalfYearValue(subject: subject, halfYear: half)
    }

    private func overallAverage() -> Double? {
        let filter: Int? = {
            switch halfYear {
            case .one: return 1
            case .two: return 2
            case .all: return nil
            }
        }()
        return GradeCalculationService.calculateOverallAverage(
            subjects: store.subjects,
            halfYearValueProvider: { subject, hy in
                store.bestAvailableHalfYearValue(subject: subject, halfYear: hy)
            },
            droppedHalfYearProvider: { subject in
                subject.droppedHalfYear
            },
            halfYearFilter: filter,
            fachreferat: filter == nil ? store.fachreferat : nil,
            seminar: filter == nil ? store.seminarPerformance : nil,
            practical: filter == nil ? store.practicalPerformance : nil,
            examPoints: filter == nil ? store.examPoints : [:],
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12
        )
    }

    private func formatAverage(_ value: Double?) -> String {
        store.formatMSS(value)
    }

    private func gradeColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if store.isPrivacyModeActive { return .primary }
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
            fachreferatSubjectName: fachreferatSubjectName,
            halfYearFilter: halfYear
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
        overallAverage()
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
        VStack(alignment: .leading, spacing: 12) {
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

    private var overallGradeCard: some View {
        let average = overallComputed
        let grade1to6 = pointsToGrade(average)
        
        return HStack(spacing: 0) {
            // Point Format (0-15)
            VStack(alignment: .leading, spacing: 4) {
                Text("Punkte (Ø)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Text(formatAverage(average))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .privacyBlur()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
                .frame(height: 44)
                .padding(.horizontal, 20)
            
            // Grade Format (1-6)
            VStack(alignment: .leading, spacing: 4) {
                Text("Note (Ø)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Text(grade1to6)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(gradeColor(average))
                    .monospacedDigit()
                    .privacyBlur()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(GradeCardStyle.surface(colorScheme: colorScheme, theme: store.theme, accent: .indigo))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(GradeCardStyle.border(colorScheme: colorScheme, accent: .indigo))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08),
            radius: 8,
            x: 0,
            y: 4
        )
        .onTapGesture {
            showDebugSheet = true
        }
    }

    private var overallGradeCardWithHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            overallGradeCard
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Tippe auf die Gesamtschnitt-Karte für Details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
    
    // Helper to convert points (0-15) to grade (1-6)
    // Formula approximation: 17 - Points / 3 ... roughly
    // Or standard Oberstufe table mapping.
    // Using standard formula: Grade = (17 - Points) / 3
    private func pointsToGrade(_ points: Double?) -> String {
        guard let p = points else { return "-" }
        let grade = (17.0 - p) / 3.0
        return String(format: "%.\(store.mssDecimalPrecision)f", grade)
    }

    private var nextAppointmentView: some View {
        Group {
            if let next = getNextAppointment() {
                nextAppointmentCard(next: next)
            }
        }
    }

    private func nextAppointmentCard(next: AppointmentType) -> some View {
        let accent: Color
        let systemImage: String
        let title: String
        let subject: String
        let appointmentTitle: String
        let date = next.date
        let isOverdue = date < Date()

        switch next {
        case .exam(let exam):
            accent = isOverdue ? .red : .blue
            systemImage = isOverdue ? "calendar.badge.exclamationmark" : "calendar.badge.clock"
            title = isOverdue ? "Überfällige Prüfung" : "Nächste Prüfung"
            subject = store.resolveLocalSubjectNameForExam(exam) ?? exam.subjectName
            appointmentTitle = exam.title
        case .homework(let hw):
            accent = isOverdue ? .red : .green
            systemImage = isOverdue ? "doc.badge.ellipsis" : "doc.text.fill"
            title = isOverdue ? "Überfällige Hausaufgabe" : "Nächste Hausaufgabe"
            subject = store.resolveLocalSubjectNameForHomework(hw) ?? hw.subjectName
            appointmentTitle = hw.title
        }

        return SettingsCard(
            title: title,
            subtitle: relativeDateString(for: date),
            systemImage: systemImage,
            accent: accent
        ) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(subject.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent.opacity(0.8))
                    
                    Text(appointmentTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    let sharing = {
                        switch next {
                        case .exam(let e): return store.resolveContextName(groupId: e.groupId, courseId: e.courseId)
                        case .homework(let h): return store.resolveContextName(groupId: h.groupId, courseId: h.courseId)
                        }
                    }()
                    
                    if !sharing.isEmpty {
                        Text("Geteilt mit \(sharing)")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.5)
            }
            .padding(.top, 4)
        }
        .onTapGesture {
            switch next {
            case .exam(let exam): detailExam = exam
            case .homework(let hw): detailHomework = hw
            }
        }
    }
    
    enum AppointmentType {
        case exam(Exam)
        case homework(Homework)
        
        var date: Date {
            switch self {
            case .exam(let e): return e.date
            case .homework(let h): return h.dueDate ?? Date.distantFuture
            }
        }
    }
    
    private func getNextAppointment() -> AppointmentType? {
        let now = Date()
        
        // Filter exams in future
        let nextExam = store.allExams
            .filter { !$0.isCompleted && $0.date > now }
            .min { $0.date < $1.date }
            
        // Filter homework in future
        let nextHomework = store.allHomeworks
            .filter { !$0.isCompleted && ($0.dueDate ?? Date.distantFuture) > now }
            .min { ($0.dueDate ?? Date.distantFuture) < ($1.dueDate ?? Date.distantFuture) }
            
        if let exam = nextExam, let hw = nextHomework {
            return exam.date < (hw.dueDate ?? Date.distantFuture) ? .exam(exam) : .homework(hw)
        } else if let exam = nextExam {
            return .exam(exam)
        } else if let hw = nextHomework {
            return .homework(hw)
        }
        return nil
    }
    
    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var subjectsControlCard: some View {
        SettingsCard(
            title: "Fächer & Noten",
            subtitle: "\(subjectsWithoutFachreferat.count) Fächer • \(totalGradesCountComputed) Noten",
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
                        let newValue = !store.showSubjectsAsGrid
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.showSubjectsAsGrid = newValue
                        }
                        Task {
                            await store.updatePreferences(showSubjectsAsGrid: newValue)
                        }
                    } label: {
                        Image(systemName: store.showSubjectsAsGrid ? "list.bullet" : "squareshape.split.2x2")
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
            EmptyView()
        }
    }

    private func holidaySubtitle(info: HolidayWindow) -> String {
        let name = friendlyHolidayName(info.name)
        let startText = holidayDateFormatter.string(from: info.start)
        return "\(name) ab \(startText)"
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
    private var topContentSection: some View {
        Section {
            homeHeader
                .softFadeIn(enabled: animationsOn, delay: 0.01, offset: 10)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            overallGradeCardWithHint
                .softFadeIn(enabled: animationsOn, delay: 0.04, offset: 12)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if store.showNextExamCard {
                nextAppointmentView
                    .softFadeIn(enabled: animationsOn, delay: 0.07, offset: 10)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            subjectsControlCard
                .softFadeIn(enabled: animationsOn, delay: 0.10, offset: 12)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            
            if let upcomingHoliday {
                holidayNoticeCard(info: upcomingHoliday)
                    .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 10)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            sortingModeSection
                .softFadeIn(enabled: animationsOn, delay: 0.14, offset: 10)
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
                        fachreferatSubjectName: store.fachreferat?.subjectName,
                        halfYearFilter: halfYear
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
            } else if store.showSubjectsAsGrid {
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
                HStack(spacing: 0) {
                    if offlineManager.isOfflineModeActive {
                        Button {
                            onToggleOfflineBanner()
                        } label: {
                            ToolbarIcon(symbol: "wifi.slash", showDot: false)
                        }
                        .accessibilityLabel("Offline-Modus aktiv")
                    }

                    Button {
                        showNotifications = true
                    } label: {
                        ToolbarIcon(
                            symbol: "bell",
                            showDot: notificationInbox.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !launchOfferPurchased)
                        )
                    }
                    .accessibilityLabel("Benachrichtigungen")

                    Button {
                        handlePrivacyToggle()
                    } label: {
                        ToolbarIcon(
                            symbol: store.isPrivacyModeActive ? "eye.slash.fill" : "eye.fill",
                            showDot: false
                        )
                    }
                    .accessibilityLabel(store.isPrivacyModeActive ? "Privatsphäre-Modus deaktivieren" : "Privatsphäre-Modus aktivieren")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    NavigationLink(destination: CalendarPageView().environmentObject(store)) {
                        ToolbarIcon(symbol: "calendar", showDot: false)
                    }
                    .accessibilityLabel("Kalender öffnen")

                    Button {
                        onOpenCreationMenu()
                    } label: {
                        ToolbarIcon(symbol: "plus", showDot: false)
                    }
                    .accessibilityLabel("Neu hinzufügen")
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
        .sheet(isPresented: $showDebugSheet) {
            NavigationStack {
                MSSDetailedCalculationView(halfYearFilter: halfYear)
                    .environmentObject(store)
            }
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
            // Show migration info sheet on first launch if needed
            if store.shouldShowMigrationInfo {
                showMigrationInfoSheet = true
            }


        }
        .sheet(isPresented: $showMigrationInfoSheet) {
            MigrationInfoSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showWhatsNewSheet, onDismiss: {
            // Log that it has been seen when dismissed (via swipe or button)
            if let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                store.updateLastSeenVersion(to: currentVersion)
            }
        }) {
            WhatsNewSheet()
                .environmentObject(store)
        }
        .onChange(of: store.initialSyncSettled) { _, settled in
             if settled {
                 let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                 let versionMismatch = !currentVersion.isEmpty && store.lastSeenVersion != currentVersion
                 // Logic to determine if user should see it
                 // e.g. only if not a fresh install, or if we want to show it on fresh install too?
                 // Existing logic had `isLegacyOrOlder`.
                 // Assuming we want to show it if version changed.
                 
                 // If store.registeredInVersion is nil, it might be a fresh install.
                 // Usually What's New is for updates.
                 // Preserving existing logic:
                 // Let's rely on version mismatch primarily.
                 
                 
                 if versionMismatch && !showMigrationInfoSheet {
                     // Don't show "What's New" if the user just registered in this version
                     if store.registeredInVersion != currentVersion {
                         showWhatsNewSheet = true
                     }
                 }
             }
        }
        .sheet(isPresented: $showDailySummarySheet) {
            DailySummarySheet(data: tomorrowSummaryData)
                .environmentObject(store)
        }
        .onChange(of: store.shouldShowMigrationInfo) { _, show in
            if show { showMigrationInfoSheet = true }
        }
        .sheet(item: $detailExam) { exam in
            ExamDetailSheet(exam: exam, onEdit: { editingExam = $0 })
                .environmentObject(store)
        }
        .sheet(item: $detailHomework) { hw in
            HomeworkDetailSheet(homework: hw, onEdit: { editingHomework = $0 })
                .environmentObject(store)
        }
        .sheet(item: $editingExam) { exam in
            EditExamView(exam: exam)
                .environmentObject(store)
        }
        .sheet(item: $editingHomework) { hw in
            EditHomeworkView(homework: hw)
                .environmentObject(store)
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
            showDailySummarySheet = true
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
        let info = await HolidaysService.shared.upcomingHolidayWithin(days: 14, from: Date())
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroSection
                priceSpotlight
                benefitsList
                Spacer(minLength: 8)
                ctaSection
                finePrint
            }
            .frame(maxWidth: .infinity, alignment: .top)
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
                Task {
                    let activated = await storeKit.refreshAllStatus()
                    await MainActor.run {
                        if activated {
                            onPurchaseSuccess()
                            dismiss()
                        } else {
                            purchaseStatusMessage = "Code eingelöst. Wir prüfen den Kauf und schalten Pro frei, sobald er bestätigt ist."
                            purchaseStatusIsError = false
                        }
                    }
                }
            case .failure(let error):
                print("Offer code redemption failed: \(error)")
                purchaseStatusMessage = "Code konnte nicht eingelöst werden."
                purchaseStatusIsError = true
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
            ScrollView(showsIndicators: false) {
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
                purchaseStatusMessage = nil
                purchaseStatusIsError = false
                onPurchaseSuccess()
                dismiss()
                Task {
                    let activated = await storeKit.refreshAllStatus()
                    await MainActor.run {
                        if activated {
                            onPurchaseSuccess()
                            dismiss()
                        } else {
                            purchaseStatusMessage = "Code eingelöst. Wir prüfen den Kauf und schalten Pro frei, sobald er bestätigt ist."
                            purchaseStatusIsError = false
                        }
                    }
                }
            case .failure(let error):
                // StoreKit handles UI for failure usually, but we can log
                print("Offer code redemption failed: \(error)")
                purchaseStatusMessage = "Code konnte nicht eingelöst werden."
                purchaseStatusIsError = true
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

            Button {
                showOfferCodeSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "tag.fill")
                        .font(.caption.weight(.semibold))
                    Text("Rabattcode Einlösen")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

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
                handleRestore()
            } label: {
                Text("Käufe wiederherstellen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ctaAccent)
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(storeKit.isRestoring)
#if DEBUG
            Button {
                NotificationCenter.default.post(name: .toggleSubscriptionOfferSheet, object: nil)
            } label: {
                Text("Debug: Abo-Sheet toggeln")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
#endif
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
    let halfYearFilter: HomeView.HalfYearFilter

    private func fobosoValueText(_ comp: HalfYearComputation) -> String {
        if let raw = comp.rawFinal {
            return String(format: "%.\(store.mssDecimalPrecision)f", raw)
        }
        if let other = comp.otherAvg {
            return String(format: "%.\(store.mssDecimalPrecision)f", other)
        }
        if let min = comp.pointsMin, let max = comp.pointsMax {
            return "\(min)–\(max)"
        }
        return "–"
    }

    private func halfValue(_ subject: Subject, half: Int) -> Double? {
        store.bestAvailableHalfYearValue(subject: subject, halfYear: half)
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.\(store.mssDecimalPrecision)f", v)
    }

    private func gradeClassColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if store.isPrivacyModeActive { return .primary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private func descriptor(for average: Double?, gradesCount: Int, isFachreferat: Bool, isPraktikum: Bool, isSeminar: Bool) -> String {
        if isFachreferat {
            return gradesCount == 0 ? "Fachreferat noch nicht hinterlegt" : "Einmalige Bewertung gespeichert"
        }
        if isSeminar {
            return average == nil ? "Seminar noch nicht bewertet" : "Seminarfach-Leistung"
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

        if subject.name == "Seminar" {
            return SubjectAccent(
                primary: Color(hex: "#4f46e5"),
                secondary: Color(hex: "#6366f1")
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

    private func currentDisplay() -> (average: Double?, displayValue: String) {
        // Special handling for Fachreferat: grade is stored in store.fachreferat, not gradesBySubject
        if subject.name == "Fachreferat" {
            if let fr = store.fachreferat {
                // Use fixed grade override if available, otherwise use calculated grade
                let grade = fr.fixedGrade ?? fr.grade
                return (grade, String(format: "%.0f", grade))
            }
            return (nil, "–")
        }
        
        // Special handling for Seminar
        if subject.name == "Seminar" {
             if let sem = store.seminarPerformance, let points = GradeCalculationService.calculateSeminarFinalPoints(sem) {
                 return (points, String(format: "%.0f", points))
             }
             return (nil, "–")
        }
        
        let droppedHalf = subject.droppedHalfYear
        switch halfYearFilter {
        case .one:
            if let fixed = subject.fixedAverageHalfYear1 {
                return (fixed, String(format: "%.\(store.mssDecimalPrecision)f", fixed))
            }
            // If half-year 1 is dropped, show nil
            if droppedHalf == 1 {
                return (nil, "–")
            }
            let value = halfValue(subject, half: 1)
            return (value, value.map { String(format: "%.\(store.mssDecimalPrecision)f", $0) } ?? "–")
        case .two:
            if let fixed = subject.fixedAverageHalfYear2 {
                return (fixed, String(format: "%.\(store.mssDecimalPrecision)f", fixed))
            }
            // If half-year 2 is dropped, show nil
            if droppedHalf == 2 {
                return (nil, "–")
            }
            let value = halfValue(subject, half: 2)
            return (value, value.map { String(format: "%.\(store.mssDecimalPrecision)f", $0) } ?? "–")
        case .all:
            if let fixed = subject.fixedAverageYearly {
                return (fixed, String(format: "%.\(store.mssDecimalPrecision)f", fixed))
            }
            let v1 = droppedHalf == 1 ? nil : halfValue(subject, half: 1)
            let v2 = droppedHalf == 2 ? nil : halfValue(subject, half: 2)
            if let a = v1, let b = v2 {
                let avg = (a + b) / 2.0
                return (avg, String(format: "%.\(store.mssDecimalPrecision)f", avg))
            }
            if let one = v1 ?? v2 {
                return (one, String(format: "%.\(store.mssDecimalPrecision)f", one))
            }
            return (nil, "–")
        }
    }

    var body: some View {
        let display = currentDisplay()
        let average = display.average
        let displayValue = display.displayValue
        let gradesCount = grades.count
        let isDropped = (subject.droppedHalfYear != nil && !grades.isEmpty && average == nil)

        let isFachreferat = subject.name == "Fachreferat"
        let isSeminar = subject.name == "Seminar"
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
            } else if isSeminar {
                return Tag(text: "Seminar", style: .main)
            } else if isPraktikum {
                return Tag(text: "Praktikum", style: .minor)
            } else if isSport {
                return Tag(text: "Nicht einbringbar", style: .elective)
            } else if subject.isElective {
                return Tag(text: "Wahlfach", style: .elective)
            }
            let mode = subject.gradingMode ?? (subject.type == 1 ? .withSchulaufgaben : .withoutSchulaufgaben)
            switch mode {
            case .withSchulaufgaben:
                return nil
            case .withoutSchulaufgaben:
                return nil
            }
        }()

        return HStack(alignment: .center, spacing: 10) {
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

                Text(descriptor(for: average, gradesCount: gradesCount, isFachreferat: isFachreferat, isPraktikum: isPraktikum, isSeminar: isSeminar))
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
                Text(displayValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .privacyBlur()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(gradePillBackground(gradeClassColor(average)))
                    .foregroundStyle(gradeClassColor(average))
                    .clipShape(Capsule())
                    .opacity(isDropped ? 0.5 : 1.0)
                    .saturation(isDropped ? 0.3 : 1.0)
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
        if subject.name == "Fachreferat" {
             if let fr = store.fachreferat { return fr.fixedGrade ?? fr.grade }
             return nil
        }
        if subject.name == "Seminar" {
             if let sem = store.seminarPerformance { return GradeCalculationService.calculateSeminarFinalPoints(sem) }
             return nil
        }
        if let fixed = subject.fixedAverageYearly { return fixed }
        let droppedHalf = subject.droppedHalfYear
        let v1 = droppedHalf == 1 ? nil : store.bestAvailableHalfYearValue(subject: subject, halfYear: 1)
        let v2 = droppedHalf == 2 ? nil : store.bestAvailableHalfYearValue(subject: subject, halfYear: 2)
        switch (v1, v2) {
        case let (a?, b?):
            return (a + b) / 2.0
        case let (a?, nil):
            return a
        case let (nil, b?):
            return b
        default:
            return nil
        }
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "–" }
        return String(format: "%.\(store.mssDecimalPrecision)f", v)
    }

    private func gradeClassColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        if store.isPrivacyModeActive { return .primary }
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
        if subject.name == "Seminar" {
            return SubjectAccent(
                primary: Color(hex: "#4f46e5"),
                secondary: Color(hex: "#6366f1")
            )
        }
        
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
        let isDropped = (subject.droppedHalfYear != nil && !grades.isEmpty && average == nil)
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
                    } else if subject.isElective {
                        Text("Wahlfach")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent.primary.opacity(0.8))
                    }
                }
                Spacer(minLength: 4)
                
                Text(formatAverage(average))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .privacyBlur()
                    .foregroundStyle(gradeClassColor(average))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(gradePillBackground(gradeClassColor(average)))
                    .opacity(isDropped ? 0.5 : 1.0)
                    .saturation(isDropped ? 0.3 : 1.0)
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
