import SwiftUI
import FirebaseAuth
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ExamListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let subjectFilter: String?
    let alternateSubjectNames: [String]

    @State private var visibleCompletedCount: Int = 5
    @State private var editingExam: Exam? = nil
    @State private var examForNewGrade: Exam? = nil
    @State private var fachreferatExam: Exam? = nil
    @State private var reminderExam: Exam? = nil
    @State private var detailExam: Exam? = nil
    @State private var subjectDetail: Subject? = nil
    @State private var showAddChooser: Bool = false
    @State private var showAddExamSheet: Bool = false
    @State private var showAddGeneralExamSheet: Bool = false
    @State private var showAddFachreferatSheet: Bool = false
    @State private var shareURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var shareError: String? = nil
    @State private var examToDelete: Exam? = nil
    @State private var rescheduleExam: Exam? = nil
    @State private var rescheduleDate: Date = Date()
    @State private var showRescheduleSheet: Bool = false

    init(subjectFilter: String? = nil, alternateSubjectNames: [String] = []) {
        self.subjectFilter = subjectFilter
        self.alternateSubjectNames = alternateSubjectNames
    }

    private var upcomingExams: [Exam] {
        filteredExams
            .filter { $0.isActive }
            .sorted { $0.date < $1.date }
    }

    private var waitingForGradeExams: [Exam] {
        filteredExams
            .filter { !$0.isCompleted && !$0.isActive }
            .sorted { $0.date > $1.date }
    }

    private var completedExams: [Exam] {
        filteredExams
            .filter { $0.isCompleted }
            .sorted { $0.date > $1.date }
    }

    private var filteredExams: [Exam] {
        guard let subjectFilter else { return linkedExams }
        let candidates = ([subjectFilter] + alternateSubjectNames).map { $0.lowercased() }
        return linkedExams.filter { exam in
            let name = exam.subjectName.lowercased()
            // Nur anzeigen, wenn Fach verknüpft ist (Subject oder Mapping)
            if let resolved = store.resolveLocalSubjectNameForExam(exam) {
                let resolvedLower = resolved.lowercased()
                if candidates.contains(resolvedLower) { return true }
            }
            return candidates.contains(name)
        }
    }

    private var linkedExams: [Exam] {
        store.allExams.filter { exam in
            // Immer anzeigen, wenn es ein Gruppen-Termin ist
            if exam.isShared { return true }
            let trimmed = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased() == "fachreferat" || trimmed.lowercased() == "termin" {
                return true
            }
            if let resolved = store.resolveLocalSubjectNameForExam(exam),
               store.subjects.contains(where: { $0.name == resolved }) {
                return true
            }
            return store.subjects.contains(where: { $0.name == exam.subjectName })
        }
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var sheetTitle: String {
        if let subjectFilter, !subjectFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subjectFilter
        }
        return "Klausuren"
    }

    private func resolvedSubjectName(for exam: Exam) -> String {
        if exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fachreferat",
           let related = exam.subjectKey, !related.isEmpty {
            return "Fachreferat • \(related)"
        }
        return store.resolveLocalSubjectNameForExam(exam) ?? exam.subjectName
    }

    @ViewBuilder
    private var listContent: some View {
        VStack(spacing: 16) {
            upcomingSection
            waitingForGradeSection
            completedSection
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        SettingsCard(
            title: "Anstehend",
            subtitle: "Kommende Termine",
            systemImage: "calendar",
            accent: .indigo
        ) {
            if upcomingExams.isEmpty {
                Text("Du hast aktuell keine anstehenden Klausuren.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(upcomingExams) { exam in
                        ExamRowView(exam: exam, showStatusIcon: false, onToggleReminder: {
                            reminderExam = exam
                        }, onMarkCompleted: {
                            Task { await markExamCompleted(exam) }
                        }, onUndoCompleted: nil, onTap: {
                            detailExam = exam
                        }) {
                            contextMenuContent(for: exam)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var waitingForGradeSection: some View {
        if !waitingForGradeExams.isEmpty {
            SettingsCard(
                title: "Wartet auf Note",
                subtitle: "Bereits geschrieben",
                systemImage: "hourglass.circle.fill",
                accent: .orange
            ) {
                LazyVStack(spacing: 10) {
                    ForEach(waitingForGradeExams) { exam in
                        ExamRowView(exam: exam, showStatusIcon: false, onToggleReminder: {
                            reminderExam = exam
                        }, onMarkCompleted: {
                            Task { await markExamCompleted(exam) }
                        }, onUndoCompleted: nil, onTap: {
                            detailExam = exam
                        }) {
                            contextMenuContent(for: exam)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !completedExams.isEmpty {
            SettingsCard(
                title: "Erledigt",
                subtitle: "Abgeschlossene Klausuren",
                systemImage: "checkmark.seal.fill",
                accent: .green
            ) {
                LazyVStack(spacing: 10) {
                    ForEach(Array(completedExams.prefix(visibleCompletedCount))) { exam in
                        ExamRowView(exam: exam, showStatusIcon: false, onToggleReminder: nil, onMarkCompleted: nil, onUndoCompleted: {
                            Task { await markExamNotCompleted(exam) }
                        }, onTap: {
                            detailExam = exam
                        }) {
                            contextMenuContent(for: exam)
                        }
                        .contextMenu { contextMenuContent(for: exam) }
                    }
                    if completedExams.count > visibleCompletedCount {
                        let remaining = completedExams.count - visibleCompletedCount
                        let nextBatch = min(5, remaining)
                        Button {
                            visibleCompletedCount += nextBatch
                        } label: {
                            Text("Weitere \(nextBatch) anzeigen")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .green))
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenuContent(for exam: Exam) -> some View {
        if !exam.isCompleted {
            Button {
                if isFachreferatExam(exam) { fachreferatExam = exam } else { examForNewGrade = exam }
            } label: {
                Label("Note eintragen", systemImage: "pencil")
            }
            Button {
                reminderExam = exam
            } label: {
                Label("Erinnerung", systemImage: reminderIconName(exam))
            }
        } else {
             Button {
                Task { await markExamNotCompleted(exam) }
            } label: {
                Label("Als offen markieren", systemImage: "arrow.uturn.backward")
            }
        }
        
        Button {
            presentShareLink(for: exam)
        } label: {
            Label("Teilen", systemImage: "square.and.arrow.up")
        }
        
        Divider()
        
        Button(role: .destructive) {
            examToDelete = exam
        } label: {
            Label("Löschen", systemImage: "trash")
        }
        
        // Migration option for legacy exams
        if exam.groupId != nil && exam.courseId == nil && exam.classId == nil && store.activeClassId != nil {
            Button {
                Task {
                    if let activeClass = store.activeClassId {
                        // Attempt to find a matching course in the active class
                        let matchingCourse = store.courses.first { 
                            $0.classId == activeClass && $0.subjectKey == exam.subjectKey 
                        }
                        try? await store.migrateSharedExamToClass(
                            exam: exam, 
                            targetClassId: activeClass, 
                            targetCourseId: matchingCourse?.id
                        )
                    }
                }
            } label: {
                Label("In Klasse verschieben", systemImage: "arrow.right.doc.on.clipboard")
            }
        }
    }

    private var bodyContent: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                listContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .toolbar { toolbarContent }
        }
        .onAppear {
            visibleCompletedCount = 5
            autoCompleteGeneralExams()
        }
    }

    var body: some View {
        secondarySheets(primarySheets(bodyContent))

            .alert("Link konnte nicht erstellt werden", isPresented: Binding(
                get: { shareError != nil },
                set: { isPresented in
                    if !isPresented { shareError = nil }
                }
            )) {
                Button("OK", role: .cancel) { shareError = nil }
            } message: {
                if let shareError {
                    Text(shareError)
                }
            }

            .alert("Prüfung löschen?", isPresented: Binding(
                get: { examToDelete != nil },
                set: { if !$0 { examToDelete = nil } }
            )) {
                Button("Löschen", role: .destructive) {
                    if let exam = examToDelete {
                        Task { await deleteExamConfirmed(exam) }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Bist du sicher? Dies kann nicht widerrufen werden.")
            }
        .onChange(of: store.allExams) { _, _ in
            autoCompleteGeneralExams()
        }
    }





    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                ToolbarIcon(symbol: "chevron.down", showDot: false)
            }
            .accessibilityLabel("Schließen")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showAddChooser = true
            } label: {
                ToolbarIcon(symbol: "plus", showDot: false)
            }
        }
    }

    private func primarySheets(_ content: some View) -> some View {
        content
            .sheet(item: $editingExam) { exam in
                EditExamView(exam: exam)
                    .environmentObject(store)
            }
            .sheet(item: $examForNewGrade) { exam in
                let note = noteForExam(exam)
                AddGradeView(
                    preselectedSubjectName: exam.subjectName,
                    preselectedWeight: exam.weight,
                    preselectedCustomWeight: exam.customWeight,
                    prefilledNote: note,
                    linkedExamId: exam.id,
                    markLinkedExamCompletedByDefault: true
                )
                .environmentObject(store)
            }
            .sheet(item: $fachreferatExam, onDismiss: completeFachreferatExamIfNeeded) { exam in
                NavigationStack {
                    AddFachreferatView(preselectedSubjectName: exam.subjectKey ?? exam.subjectName)
                        .environmentObject(store)
                }
            }
            .sheet(item: $reminderExam) { exam in
                ExamReminderView(exam: exam)
                    .environmentObject(store)
            }
            .sheet(item: $detailExam) { exam in
                ExamDetailSheet(exam: exam, onEdit: { editingExam = $0 })
                    .environmentObject(store)
            }
    }

    private func secondarySheets(_ content: some View) -> some View {
        content
            .sheet(item: $subjectDetail) { subject in
                SubjectDetailView(subject: subject)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAddChooser) {
                ExamAddChooserView(
                    onExam: { showAddExamSheet = true },
                    onGeneral: { showAddGeneralExamSheet = true },
                    onFachreferat: (store.gradeYear == 12 ? { showAddFachreferatSheet = true } : nil)
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showAddExamSheet) {
                NavigationStack {
                    AddExamView(preselectedSubjectName: subjectFilter)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showAddGeneralExamSheet) {
                NavigationStack {
                    AddExamView(isGeneralEvent: true)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showAddFachreferatSheet) {
                NavigationStack {
                    AddExamView(isFachreferatEvent: true)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareURL {
                    ShareSheet(activityItems: [shareURL])
                } else {
                    Text("Kein Link verfügbar")
                }
            }
            .sheet(isPresented: $showRescheduleSheet) {
                NavigationStack {
                    ZStack {
                        ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 16) {
                            SettingsCard(
                                title: "Nachtermin",
                                subtitle: "Neues Datum wählen",
                                systemImage: "calendar.badge.clock",
                                accent: .blue
                            ) {
                                SettingsSectionBox {
                                    DatePicker("Neuer Termin", selection: $rescheduleDate, displayedComponents: rescheduleExam?.hasTime == true ? [.date, .hourAndMinute] : [.date])
                                        .tint(.blue)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .navigationTitle("Nachtermin wählen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showRescheduleSheet = false
                            } label: {
                                ToolbarIcon(symbol: "chevron.down", showDot: false)
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                if let exam = rescheduleExam {
                                    Task {
                                        try? await store.rescheduleExam(exam: exam, newDate: rescheduleDate)
                                        showRescheduleSheet = false
                                        rescheduleExam = nil
                                    }
                                }
                            } label: {
                                ToolbarIcon(symbol: "checkmark", showDot: false)
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
    }



    private func formattedExamDate(_ exam: Exam) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = exam.hasTime ? .short : .none
        return formatter.string(from: exam.date)
    }

    private func noteForExam(_ exam: Exam) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = exam.hasTime ? .short : .none
        let dateString = formatter.string(from: exam.date)
        return "Geschrieben am \(dateString)"
    }

    private func examHasLinkedGrade(_ exam: Exam) -> Bool {
        linkedGrade(for: exam) != nil
    }

    private func linkedGrade(for exam: Exam) -> GradeWithId? {
        for list in store.gradesBySubject.values {
            if let match = list.first(where: { $0.linkedExamId == exam.id }) {
                return match
            }
        }
        return nil
    }

    private func subjectForExam(_ exam: Exam) -> Subject? {
        let resolved = resolvedSubjectName(for: exam)
        return store.subjects.first(where: { $0.name == resolved })
    }

    private func isFachreferatExam(_ exam: Exam) -> Bool {
        exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fachreferat" && (store.gradeYear == 12)
    }

    private func isGeneralExam(_ exam: Exam) -> Bool {
        let trimmed = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let noWeights = exam.weight == nil && exam.customWeight == nil
        return trimmed.isEmpty && (exam.requiresGrade == false) && noWeights
    }

    private func autoCompleteGeneralExams() {
        let now = Date()
        let cal = Calendar.current
        for exam in store.allExams where isGeneralExam(exam) && !exam.isCompleted {
            let cutoff: Date = {
                if exam.hasTime {
                    return exam.date
                }
                let start = cal.startOfDay(for: exam.date)
                return cal.date(byAdding: .day, value: 1, to: start) ?? exam.date
            }()
            if now >= cutoff {
                Task { await markExamCompleted(exam) }
            }
        }
    }



    private func markExamCompleted(_ exam: Exam) async {
        if exam.isShared {
            await store.setUserCompletedForSharedExam(examId: exam.id, completed: true, groupId: exam.groupId)
        } else {
            await store.setExamCompleted(id: exam.id, completed: true)
        }
    }

    private func presentShareLink(for exam: Exam) {
        shareError = nil
        let subject = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = HomeworkShareLinkBuilder.url(
            title: exam.title,
            subjectName: subject.isEmpty ? exam.subjectKey : subject,
            dueDate: exam.date
        ) else {
            shareError = "Der Link konnte nicht erstellt werden."
            return
        }
        shareURL = url
        showShareSheet = true
    }

    private func completeFachreferatExamIfNeeded() {
        guard let exam = fachreferatExam else { return }
        fachreferatExam = nil
        guard store.fachreferat != nil else { return }
        Task {
            await store.setExamCompleted(id: exam.id, completed: true)
        }
    }

    private func markExamNotCompleted(_ exam: Exam) async {
        if exam.isShared {
            await store.setUserCompletedForSharedExam(examId: exam.id, completed: false, groupId: exam.groupId)
        } else {
            await store.setExamCompleted(id: exam.id, completed: false)
        }
    }

    private func toggleReminder(_ exam: Exam) async {
        let newValue: Date? = (exam.reminderAt == nil) ? Date().addingTimeInterval(3600) : nil
        let normalizedDate = exam.date
        do {
            if exam.isShared {
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: newValue, groupId: exam.groupId)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    subjectKey: exam.subjectKey,
                    title: exam.title,
                    notes: exam.notes,
                    date: normalizedDate,
                    hasTime: exam.hasTime,
                    weight: exam.weight,
                    customWeight: exam.customWeight,
                    assessmentType: exam.assessmentType,
                    reminderAt: newValue,
                    isCompleted: exam.isCompleted
                )
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // Optional: Fehlerbehandlung oder Logging
        }
    }

    private func reminderIconName(_ exam: Exam) -> String {
        return exam.reminderAt == nil ? "bell" : "bell.fill"
    }

    private func reminderIconColor(_ exam: Exam) -> Color {
        return exam.reminderAt == nil ? .secondary : .green
    }

    private func reminderAccessibilityLabel(_ exam: Exam) -> String {
        return "Erinnerung bearbeiten"
    }

    private func shortReminder(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return reminderTimeFormatter.string(from: date)
        }
        return "\(reminderDateFormatter.string(from: date))\n\(reminderTimeFormatter.string(from: date))"
    }

    private func deleteExamConfirmed(_ exam: Exam) async {
        if exam.isShared {
            if let gid = exam.groupId {
                if store.wahlpflichtfachGroupIds.contains(gid) {
                    await store.deleteSharedExamFromWpGroup(wpGroupId: gid, id: exam.id)
                } else {
                    await store.deleteSharedExamFromGroup(groupId: gid, id: exam.id)
                }
            } else if let cid = exam.courseId {
                // Course-level exams: nested path classes/{classId}/courses/{courseId}/exams
                try? await store.deleteExamFromCourse(courseId: cid, examId: exam.id)
            } else if let clid = exam.classId {
                // Class-level exams: classes/{classId}/exams
                await store.deleteSharedExamFromClass(classId: clid, id: exam.id)
            }
        } else {
            await store.deleteExamFromFirestore(id: exam.id)
        }
    }
}

struct ExamDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    let exam: Exam
    let onEdit: ((Exam) -> Void)?
    @State private var noteCopied: Bool = false
    @State private var showReschedulePicker: Bool = false
    @State private var rescheduleDate: Date = Date()
    @State private var showDeleteAlert: Bool = false

    init(exam: Exam, onEdit: ((Exam) -> Void)? = nil) {
        self.exam = exam
        self.onEdit = onEdit
    }

    private var groupName: String {
        guard let gid = exam.groupId else { return "" }
        return store.groupNames[gid] ?? gid
    }

    private var sharingInfo: String? {
        let name = store.resolveContextName(groupId: exam.groupId, courseId: exam.courseId, classId: exam.classId)
        return name.isEmpty ? nil : "Diese Prüfung ist geteilt mit \(name)"
    }

    private var potentialDuplicate: Exam? {
        guard !exam.isShared else { return nil } // Only local exams can be merged into shared ones
        let resolveLocal = store.resolveLocalSubjectNameForExam(exam) ?? exam.subjectName
        let normalizedLocal = resolveLocal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        return store.allExams.first { candidate in
            guard candidate.id != exam.id else { return false }
            guard candidate.isShared else { return false } // Must be shared
            
            // Check Date (Day precision)
            if !Calendar.current.isDate(candidate.date, inSameDayAs: exam.date) { return false }
            
            // Check Subject
            let resolveCandidate = store.resolveLocalSubjectNameForExam(candidate) ?? candidate.subjectName
            let normalizedCandidate = resolveCandidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            return normalizedCandidate == normalizedLocal
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = exam.hasTime ? .short : .none
        return fmt.string(from: exam.date)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Klausur",
                        subtitle: examTitle,
                        systemImage: "calendar.badge.clock",
                        accent: .indigo
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 10) {
                                detailRow(
                                    title: "Termin",
                                    value: formattedDate,
                                    icon: "calendar",
                                    tint: .indigo
                                )
                                if !isGeneralEvent {
                                    detailRow(
                                        title: "Fach",
                                        value: subjectDisplay,
                                        icon: "book.closed.fill",
                                        tint: .mint
                                    )
                                }
                                if !groupName.isEmpty {
                                    detailRow(
                                        title: "Gruppe",
                                        value: groupName,
                                        icon: "person.3.fill",
                                        tint: .blue
                                    )
                                }
                                if let info = sharingInfo {
                                    detailRow(
                                        title: "Geteilt mit",
                                        value: info,
                                        icon: "shareplay",
                                        tint: .purple
                                    )
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Details",
                        subtitle: "Art, Status & Erinnerung",
                        systemImage: "doc.text.magnifyingglass",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                if !isGeneralEvent {
                                    detailRow(
                                        title: "Art",
                                        value: weightLabel,
                                        icon: "chart.bar.fill",
                                        tint: .orange
                                    )
                                }
                                detailRow(
                                    title: "Status",
                                    value: exam.isCompleted ? "Erledigt" : "Offen",
                                    icon: exam.isCompleted ? "checkmark.circle.fill" : "circle",
                                    tint: exam.isCompleted ? .green : .secondary
                                )
                                if !isGeneralEvent {
                                    detailRow(
                                        title: "Note erforderlich",
                                        value: exam.requiresGrade == false ? "Nein" : "Ja",
                                        icon: "graduationcap.fill",
                                        tint: .purple
                                    )
                                }
                                detailRow(
                                    title: "Erinnerung",
                                    value: reminderLabel,
                                    icon: reminderIcon,
                                    tint: reminderTint
                                )
                            }
                        }
                    }


                    
                    if let duplicate = potentialDuplicate {
                        SettingsCard(
                            title: "Doppelter Eintrag?",
                            subtitle: "Ähnliche Prüfung gefunden",
                            systemImage: "exclamationmark.triangle.fill",
                            accent: .red
                        ) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Wir haben eine geteilte Prüfung am selben Tag im selben Fach gefunden.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    Button {
                                        Task {
                                            try? await store.mergeLocalExamIntoShared(localExam: exam, sharedExam: duplicate)
                                            dismiss()
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "arrow.merge")
                                            Text("Zusammenführen")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                                }
                            }
                        }
                    }

                    if let notes = exam.notes, !notes.isEmpty {
                        SettingsCard(
                            title: "Notizen",
                            subtitle: nil,
                            systemImage: "note.text",
                            accent: .cyan,
                            trailing: {
                                Button {
                                    copyToClipboard(notes)
                                    noteCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        noteCopied = false
                                    }
                                } label: {
                                    Label(noteCopied ? "kopiert" : "Kopieren",
                                          systemImage: noteCopied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(TinyTintButtonStyle(accent: noteCopied ? .green : .cyan))
                                .animation(.easeInOut(duration: 0.2), value: noteCopied)
                            }
                        ) {
                            SettingsSectionBox {
                                Text(notes)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let gradeInfo = linkedGrade, let subject = subjectForExam {
                        SettingsCard(
                            title: "Verknüpfte Note",
                            subtitle: "Tippen für Fachdaten",
                            systemImage: "checkmark.seal.fill",
                            accent: .green
                        ) {
                            SettingsSectionBox {
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                        .environmentObject(store)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(.green)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(subject.name)")
                                                .font(.headline)
                                                .foregroundStyle(Color.primary)
                                            Text("Note: \(String(format: "%.1f", gradeInfo.grade)) • Gewicht: \(String(format: "%.1f", gradeInfo.weight))")
                                                .font(.footnote)
                                                .foregroundStyle(Color.primary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Color.primary)
                                    }
                                    .padding(10)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    if !exam.isCompleted && exam.requiresGrade == true && Date() > exam.date {
                        SettingsCard(
                            title: "Nachtermin",
                            subtitle: "Prüfung verschieben",
                            systemImage: "calendar.badge.exclamationmark",
                            accent: .red
                        ) {
                            SettingsSectionBox {
                                Button {
                                    rescheduleDate = Date()
                                    showReschedulePicker = true
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.red.opacity(0.15))
                                                .frame(width: 36, height: 36)
                                            Image(systemName: "arrow.uturn.right")
                                                .foregroundStyle(.red)
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Nachtermin eintragen")
                                                .font(.headline)
                                                .foregroundStyle(Color.primary)
                                            Text("Setzt Prüfung auf neuen Termin")
                                                .font(.caption)
                                                .foregroundStyle(Color.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Color.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        SettingsCard(
                            title: "Löschen",
                            subtitle: "Unwiderruflich entfernen",
                            systemImage: "trash",
                            accent: .red
                        ) {
                            SettingsSectionBox {
                                Text("Klausur löschen")
                                    .font(.headline)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheet(isPresented: $showReschedulePicker) {
                NavigationStack {
                    Form {
                        DatePicker("Neuer Termin", selection: $rescheduleDate, displayedComponents: exam.hasTime ? [.date, .hourAndMinute] : [.date])
                    }
                    .navigationTitle("Nachtermin wählen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showReschedulePicker = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Speichern") {
                                Task {
                                    try? await store.rescheduleExam(exam: exam, newDate: rescheduleDate)
                                    showReschedulePicker = false
                                    dismiss()
                                }
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
            }
            .alert("Prüfung löschen?", isPresented: $showDeleteAlert) {
                Button("Löschen", role: .destructive) {
                    Task { await deleteExamConfirmed() }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Bist du sicher? Dies kann nicht widerrufen werden.")
            }
            .presentationDetents([.fraction(0.85), .large])
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
                if let onEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onEdit(exam)
                            dismiss()
                        } label: {
                            ToolbarIcon(symbol: "slider.horizontal.3", showDot: false)
                        }
                        .accessibilityLabel("Bearbeiten")
                    }
                }
            }
        }
    }

    private func deleteExamConfirmed() async {
        if exam.isShared {
            if let gid = exam.groupId {
                if store.wahlpflichtfachGroupIds.contains(gid) {
                    await store.deleteSharedExamFromWpGroup(wpGroupId: gid, id: exam.id)
                } else {
                    await store.deleteSharedExamFromGroup(groupId: gid, id: exam.id)
                }
            } else if let cid = exam.courseId {
                // Course-level exams: nested path classes/{classId}/courses/{courseId}/exams
                try? await store.deleteExamFromCourse(courseId: cid, examId: exam.id)
            } else if let clid = exam.classId {
                // Class-level exams: classes/{classId}/exams
                await store.deleteSharedExamFromClass(classId: clid, id: exam.id)
            }
        } else {
            await store.deleteExamFromFirestore(id: exam.id)
        }
        dismiss()
    }

    private func formattedDateTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private var examTitle: String {
        exam.title.isEmpty ? "Ohne Titel" : exam.title
    }

    private var subjectDisplay: String {
        let trimmed = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "fachreferat" {
            if let key = exam.subjectKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Fachreferat (\(key))"
            }
            return "Fachreferat"
        }
        return trimmed.isEmpty ? "Ohne Fach" : exam.subjectName
    }

    private var isGeneralEvent: Bool {
        let trimmed = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty && (exam.requiresGrade == false)
    }

    private var isFachreferat: Bool {
        exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fachreferat"
    }

    private var weightLabel: String {
        let trimmed = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "fachreferat" {
            if let key = exam.subjectKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Fachreferat (\(key))"
            }
            return "Fachreferat"
        }
        if exam.weight == nil && exam.customWeight == nil {
            return "Keine Gewichtung"
        }
        if let custom = exam.customWeight {
            return "Sonstige Leistung (\(formatWeight(custom))×)"
        }
        switch exam.weight {
        case 2: return "Schulaufgabe"
        case 1: return "Kurzarbeit"
        default: return "Mündlich / EX"
        }
    }

    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private var reminderLabel: String {
        if let reminder = exam.reminderAt {
            return formattedDateTime(reminder)
        }
        return "Keine Erinnerung"
    }

    private var reminderIcon: String {
        exam.reminderAt == nil ? "bell" : "bell.fill"
    }

    private var reminderTint: Color {
        exam.reminderAt == nil ? .secondary : .green
    }

    private var linkedGrade: GradeWithId? {
        store.gradesBySubject.values
            .compactMap { list in list.first { $0.linkedExamId == exam.id } }
            .first
    }

    private var subjectForExam: Subject? {
        let resolved = store.resolveLocalSubjectNameForExam(exam) ?? exam.subjectName
        return store.subjects.first(where: { $0.name == resolved })
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

    private func copyToClipboard(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#else
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
#endif
    }
}

private struct TinyTintButtonStyle: ButtonStyle {
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(accent.opacity(0.12))
            .foregroundStyle(accent)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ExamAddChooserView: View {
    let onExam: () -> Void
    let onGeneral: () -> Void
    let onFachreferat: (() -> Void)?
    @EnvironmentObject private var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Hinzufügen")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(primaryText)
                        Text("Was möchtest du anlegen?")
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)
                    }

                    VStack(spacing: 12) {
                        actionRow(icon: "calendar.badge.clock", title: "Klausurtermin", subtitle: "Prüfung mit Fach & Gewichtung", action: onExam)
                        if let onFachreferat {
                            actionRow(icon: "book", title: "Fachreferat-Termin", subtitle: "12. Klasse, mit Fachreferat verknüpfen", action: onFachreferat)
                        }
                        actionRow(icon: "calendar", title: "Anderer Termin", subtitle: "Ohne Fach und Gewichtung", action: onGeneral)
                    }
                    .padding(.top, 4)

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
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
            }
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                action()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(accentPrimary.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tileBackground)
                    .shadow(color: shadowColor, radius: 12, x: 0, y: 6)
            )
        }
        .buttonStyle(.plain)
    }

    private var accentPrimary: Color {
        if store.theme == "feminine" {
            return Color(hex: store.darkMode ? "#f472b6" : "#ec4899")
        }
        return .indigo
    }

    private var primaryText: Color {
        store.darkMode ? Color.white : Color(hex: "#0f172a")
    }

    private var secondaryText: Color {
        store.darkMode ? Color.white.opacity(0.75) : Color.secondary
    }

    private var tileBackground: LinearGradient {
        let top = accentPrimary.opacity(store.darkMode ? 0.16 : 0.08)
        let bottom = Color(.secondarySystemBackground)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12)
    }
}

struct PersonalNoteEditor: View {
    let title: String
    let initialText: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(16)
            .sheetNavigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(text)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Speichern")
                }
            }
        }
        .onAppear { text = initialText }
    }
}

private let reminderDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .none
    return fmt
}()

private let reminderTimeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .none
    fmt.timeStyle = .short
    return fmt
}()

private let examDayFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "dd"
    return fmt
}()

private let examMonthFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM"
    return fmt
}()
