import SwiftUI

struct AddExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let preselectedSubjectName: String?
    let isGeneralEvent: Bool
    let isFachreferatEvent: Bool

    @State private var subjectName: String = ""
    @State private var fachreferatSubjectName: String = ""
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Calendar.current.startOfDay(for: Date().addingTimeInterval(60 * 60 * 24))
    @State private var includeTime: Bool = false
    @State private var time: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var examWeight: Int = 0
    @State private var useCustomWeight: Bool = false
    @State private var customWeightText: String = ""
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var shareWithGroup: Bool = false
    @State private var selectedGroupIds: Set<String> = []
    @State private var selectedClassIds: Set<String> = []
    @State private var selectedCourseIds: Set<String> = []
    @State private var autoSelectedGroupIds: Set<String> = []
    @State private var autoSelectedCourseIds: Set<String> = []
    @FocusState private var focusedField: Field?

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if !isGeneralEvent && !isFachreferatEvent && subjectName.isEmpty { return false }
        if isFachreferatEvent && fachreferatSubjectName.isEmpty { return false }
        if !isGeneralEvent && !isFachreferatEvent && useCustomWeight && parsedCustomWeight() == nil { return false }
        return true
    }

    private func weightOptions(for subjectType: Int) -> [(title: String, value: Int)] {
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

    private func selectedWeightLabel(for subjectType: Int) -> String {
        if useCustomWeight {
            if let custom = parsedCustomWeight() {
                return "Sonstige Leistung (\(formatWeight(custom))x)"
            }
            return "Sonstige Leistung"
        }
        let options = weightOptions(for: subjectType)
        if let match = options.first(where: { $0.value == examWeight }) {
            return match.title
        }
        return "Art auswählen"
    }

    private func parsedCustomWeight() -> Double? {
        let cleaned = customWeightText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var sheetTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if isFachreferatEvent { return "Fachreferat" }
        if isGeneralEvent { return "Termin" }
        return "Klausur"
    }

    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func combinedExamDate() -> Date {
        if includeTime {
            return combine(date: date, with: time)
        }
        return Calendar.current.startOfDay(for: date)
    }

    private func combine(date: Date, with time: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComps = calendar.dateComponents([.hour, .minute], from: time)
        comps.hour = timeComps.hour
        comps.minute = timeComps.minute
        comps.second = 0
        return calendar.date(from: comps) ?? date
    }

    init(preselectedSubjectName: String? = nil, isGeneralEvent: Bool = false, isFachreferatEvent: Bool = false) {
        self.preselectedSubjectName = preselectedSubjectName
        self.isGeneralEvent = isGeneralEvent
        self.isFachreferatEvent = isFachreferatEvent
    }

    private enum Field: Hashable {
        case title, notes
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: isFachreferatEvent ? "Fachreferat-Termin" : (isGeneralEvent ? "Termin" : "Klausurtermin"),
                        subtitle: isFachreferatEvent ? "Fachreferat in der 12. Klasse" : (isGeneralEvent ? "Allgemeiner Termin ohne Fach" : "Fach, Titel und Gewichtung"),
                        systemImage: "calendar.badge.clock",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if !isGeneralEvent && !isFachreferatEvent {
                                SettingsSectionBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Fach")
                                            .font(.headline)
                                        Picker("Fach", selection: $subjectName) {
                                            Text("Bitte wählen").tag("")
                                            ForEach(subjects, id: \.name) { s in
                                                Text(s.name).tag(s.name)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .tint(.primary)
                                        .padding(10)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        if subjects.isEmpty {
                                            Text("Lege zuerst ein Fach an, um Klausuren zuzuordnen.")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            } else if isFachreferatEvent {
                                SettingsSectionBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Fach für das Fachreferat")
                                            .font(.headline)
                                        Picker("Fachreferat-Fach", selection: $fachreferatSubjectName) {
                                            Text("Bitte wählen").tag("")
                                            ForEach(subjects, id: \.name) { s in
                                                Text(s.name).tag(s.name)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .tint(.primary)
                                        .padding(10)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        if subjects.isEmpty {
                                            Text("Lege zuerst ein Fach an, um es dem Fachreferat zuzuordnen.")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Titel / Bezeichnung")
                                            .font(.headline)
                                        TextField(isGeneralEvent ? "z. B. Elternabend" : (isFachreferatEvent ? "Fachreferat" : "z. B. Kurzarbeit Mathematik"), text: $title)
                                            .textInputAutocapitalization(.sentences)
                                            .submitLabel(.next)
                                            .focused($focusedField, equals: .title)
                                            .onSubmit { focusedField = .notes }
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Notizen (optional)")
                                            .font(.subheadline)
                                        TextEditor(text: $notes)
                                            .frame(minHeight: 90)
                                            .textInputAutocapitalization(.sentences)
                                            .scrollContentBackground(.hidden)
                                            .focused($focusedField, equals: .notes)
                                            .padding(10)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    if !isGeneralEvent && !isFachreferatEvent {
                                        let subjectType = subjects.first(where: { $0.name == subjectName })?.type ?? 0
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Art")
                                                .font(.headline)
                                            Menu {
                                                ForEach(weightOptions(for: subjectType), id: \.value) { option in
                                                    let isSelected = !useCustomWeight && examWeight == option.value
                                                    Button {
                                                        useCustomWeight = false
                                                        examWeight = option.value
                                                    } label: {
                                                        HStack {
                                                            Text(option.title)
                                                            if isSelected {
                                                                Spacer()
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }

                                                Divider()

                                                let isCustomSelected = useCustomWeight
                                                Button {
                                                    useCustomWeight = true
                                                    if customWeightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        customWeightText = ""
                                                    }
                                                } label: {
                                                    HStack {
                                                        Text("Sonstige Leistung")
                                                        if isCustomSelected {
                                                            Spacer()
                                                            Image(systemName: "checkmark")
                                                        }
                                                    }
                                                }
                                            } label: {
                                                HStack {
                                                    Text(selectedWeightLabel(for: subjectType))
                                                        .font(.subheadline.weight(.semibold))
                                                    Spacer()
                                                    Image(systemName: "chevron.down")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .tint(.primary)
                                        }

                                        if useCustomWeight {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Gewichtung")
                                                    .font(.subheadline)
                                                TextField("Gewichtung z. B. 1 oder 2.5", text: $customWeightText)
                                                    .keyboardType(.decimalPad)
                                                    .padding(12)
                                                    .background(Color.formInputBackground)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                Text("Diese Gewichtung wird beim Verknüpfen einer Note übernommen.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            let weightInfo: String = {
                                                if subjectType == 1 {
                                                    return "Schulaufgaben zählen doppelt, Kurzarbeiten und Mündlich / EX einfach. Sonstige Leistungen können eigene Gewichtung haben"
                                                }
                                                return "Kurzarbeiten zählen doppelt, Mündlich / EX einfach. Sonstige Leistungen können eigene Gewichtung haben"
                                            }()
                                            Text(weightInfo)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else if isGeneralEvent {
                                        Text("Kein Fach nötig – keine Gewichtung.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if isFachreferatEvent {
                                        Text("Kein Fach nötig – hier nur den Termin eintragen und später die Fachreferat-Note hinterlegen.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Termin")
                                            .font(.headline)
                                        DatePicker(
                                            "Datum",
                                            selection: $date,
                                            displayedComponents: [.date]
                                        )
                                        Toggle("Uhrzeit hinzufügen", isOn: $includeTime)
                                            .tint(.indigo)
                                        if includeTime {
                                            DatePicker(
                                                "Uhrzeit",
                                                selection: $time,
                                                displayedComponents: [.hourAndMinute]
                                            )
                                            Text("90 Minuten vor Terminen mit Uhrzeit startet automatisch eine Live Activity mit Countdown.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Erinnerung",
                        subtitle: "Optionale Benachrichtigung",
                        systemImage: "bell.badge.fill",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Zusätzliche Erinnerung planen", isOn: $hasReminder)
                                    .tint(.orange)

                                if hasReminder {
                                    DatePicker(
                                        "Erinnerung",
                                        selection: $reminderDate,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                }
                            }
                        }
                    }

                    // Visibility & Sharing
                    // Visibility & Sharing
                    if !store.groupIds.isEmpty || !store.classIds.isEmpty || !store.courses.isEmpty {
                        // Filter courses relevant to the current subject
                        let availableCourses: [Course] = {
                            let targetIds = Set(store.targetCourseIds(forLocalSubject: subjectName))
                            let matches = store.courses.filter { targetIds.contains($0.id) }
                            return Array(Dictionary(grouping: matches, by: { $0.id }).values.compactMap(\.first))
                        }()
                        
                        ShareTargetSelector(
                            shareWithGroup: $shareWithGroup,
                            selectedGroupIds: $selectedGroupIds,
                            selectedClassIds: $selectedClassIds,
                            selectedCourseIds: $selectedCourseIds,
                            availableCourses: availableCourses,
                            autoSelectedGroupIds: autoSelectedGroupIds,
                            autoSelectedCourseIds: autoSelectedCourseIds
                        )
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity).onTapGesture { hideKeyboard() })
            .sheetNavigationTitle(sheetTitle)
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
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .imageScale(.medium)
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .accessibilityLabel("Speichern")
                    .disabled(!canSave || isSaving || (subjects.isEmpty && !isGeneralEvent && !isFachreferatEvent))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: date) { _, newValue in
                date = Calendar.current.startOfDay(for: newValue)
            }
            .onAppear {
                if subjectName.isEmpty {
                    if !isGeneralEvent && !isFachreferatEvent, let pre = preselectedSubjectName,
                       subjects.contains(where: { $0.name == pre }) {
                        subjectName = pre
                    } else if !isGeneralEvent && !isFachreferatEvent {
                        subjectName = subjects.first?.name ?? ""
                    } else if isFachreferatEvent {
                        subjectName = "Fachreferat"
                        if title.isEmpty { title = "Fachreferat" }
                        if fachreferatSubjectName.isEmpty {
                            if let pre = preselectedSubjectName,
                               subjects.contains(where: { $0.name == pre }) {
                                fachreferatSubjectName = pre
                            } else {
                                fachreferatSubjectName = subjects.first?.name ?? ""
                            }
                        }
                    } else {
                        subjectName = ""
                    }
                }
                // Initial update based on subject
                let initialSubject = isFachreferatEvent ? fachreferatSubjectName : subjectName
                updateSelectedGroupsForSubject(initialSubject)
                shareWithGroup = !selectedGroupIds.isEmpty
            }
            .onChange(of: subjectName) { _, newSubject in
                if !isGeneralEvent && !isFachreferatEvent {
                    updateSelectedGroupsForSubject(newSubject)
                    if !selectedGroupIds.isEmpty {
                        shareWithGroup = true
                    }
                }
            }
            .onChange(of: fachreferatSubjectName) { _, newSubject in
                if isFachreferatEvent {
                    updateSelectedGroupsForSubject(newSubject)
                    if !selectedGroupIds.isEmpty {
                        shareWithGroup = true
                    }
                }
            }
        }
        .alert("Doppelter Termin?", isPresented: $showDuplicateAlert) {
            Button("Trotzdem anlegen") {
                Task { await performSave() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Am \(date.formatted(date: .numeric, time: .omitted)) ist bereits eine Prüfung in \(conflictingExamSubject) eingetragen. Möchtest du diesen Termin trotzdem anlegen?")
        }
    }

    @State private var showDuplicateAlert: Bool = false
    @State private var conflictingExamSubject: String = ""

    private func save() async {
        guard !isSaving else { return }
        // Basic validation first
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = isGeneralEvent ? "Bitte einen Titel für den Termin eingeben." : "Bitte einen Titel für die Klausur eingeben."
            return
        }
        
        // Check for duplicates
        if await checkForDuplicates() {
            showDuplicateAlert = true
            return
        }
        
        await performSave()
    }
    
    private func checkForDuplicates() async -> Bool {
        let examDate = combinedExamDate()
        
        // No checks for general events
        if isGeneralEvent { return false }
        
        let dayStart = Calendar.current.startOfDay(for: examDate)
        
        // Check for ANY exam on that day (ignoring general events which have requiresGrade == false)
        if let conflict = store.allExams.first(where: { exam in
            let isExam = (exam.requiresGrade ?? true)
            let sameDate = Calendar.current.isDate(exam.date, inSameDayAs: dayStart)
            return isExam && sameDate
        }) {
            conflictingExamSubject = conflict.subjectName
            return true
        }
        return false
    }

    private func performSave() async {
        isSaving = true
        error = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            error = isGeneralEvent ? "Bitte einen Titel für den Termin eingeben." : "Bitte einen Titel für die Klausur eingeben."
            isSaving = false
            return
        }
        let allowWeights = !isGeneralEvent && !isFachreferatEvent && !subjectName.isEmpty
        let customWeight = allowWeights && useCustomWeight ? parsedCustomWeight() : nil
        if allowWeights && useCustomWeight && customWeight == nil {
            error = "Bitte eine gültige Gewichtung für die sonstige Leistung angeben."
            isSaving = false
            return
        }
        if isFachreferatEvent && fachreferatSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Bitte ein Fach für das Fachreferat auswählen."
            isSaving = false
            return
        }
        do {
            let examDate = combinedExamDate()
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
            let reminder: Date? = hasReminder ? reminderDate : nil
            let requiresGrade = isGeneralEvent ? false : true
            let effectiveSubject = isFachreferatEvent ? "Fachreferat" : subjectName
            let relatedSubjectRaw = isFachreferatEvent ? fachreferatSubjectName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let relatedSubject = (relatedSubjectRaw?.isEmpty == false) ? relatedSubjectRaw : nil
            let weightToStore: Int? = allowWeights && !useCustomWeight ? examWeight : nil
            let hasTime = includeTime
            
            if shareWithGroup {
                var createdAny = false
                
                // 1. Share to Courses
                for courseId in selectedCourseIds {
                    _ = try await store.addExamToCourse(
                        courseId: courseId,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: examDate,
                        hasTime: hasTime,
                        weight: weightToStore,
                        customWeight: customWeight,
                        reminderAt: reminder,
                        requiresGrade: requiresGrade
                    )
                    createdAny = true
                }
                
                // 2. Share to Groups (Legacy)
                let targetGroups = Array(selectedGroupIds.union(selectedClassIds.flatMap { store.classDetails[$0]?.groupIds ?? [] }))
                if !targetGroups.isEmpty {
                    let sharedIds = try await store.addExamToGroups(
                        subjectName: effectiveSubject,
                        subjectKey: relatedSubject,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: examDate,
                        hasTime: hasTime,
                        weight: weightToStore,
                        customWeight: customWeight,
                        reminderAt: reminder,
                        requiresGrade: requiresGrade,
                        targetGroupIds: targetGroups
                    )
                    
                    if !sharedIds.isEmpty {
                        createdAny = true
                        if let reminder {
                            for item in sharedIds {
                                try await store.setUserReminderForSharedExam(examId: item.docId, reminderAt: reminder, groupId: item.groupId)
                            }
                        }
                    }
                }
                
                // Fallback if nothing shared
                if !createdAny {
                    try await store.addExamToFirestore(
                        subjectName: effectiveSubject,
                        subjectKey: relatedSubject,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: examDate,
                        hasTime: hasTime,
                        weight: weightToStore,
                        customWeight: customWeight,
                        reminderAt: reminder,
                        requiresGrade: requiresGrade
                    )
                }
            } else {
                try await store.addExamToFirestore(
                    subjectName: effectiveSubject,
                    subjectKey: relatedSubject,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: examDate,
                    hasTime: hasTime,
                    weight: weightToStore,
                    customWeight: customWeight,
                    reminderAt: reminder,
                    requiresGrade: requiresGrade
                )
            }
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }
    
    private func updateSelectedGroupsForSubject(_ subject: String) {
        // 1. Remove previously auto-selected groups & courses
        selectedGroupIds.subtract(autoSelectedGroupIds)
        autoSelectedGroupIds.removeAll()
        selectedCourseIds.subtract(autoSelectedCourseIds)
        autoSelectedCourseIds.removeAll()
        
        // 2. If subject is valid, find new matches
        if !subject.isEmpty {
            let matchedGroups = Set(store.targetGroupIds(forLocalSubject: subject))
            if !matchedGroups.isEmpty {
                selectedGroupIds.formUnion(matchedGroups)
                autoSelectedGroupIds = matchedGroups
            }
            
            let matchedCourses = Set(store.targetCourseIds(forLocalSubject: subject))
            if !matchedCourses.isEmpty {
                selectedCourseIds.formUnion(matchedCourses)
                autoSelectedCourseIds = matchedCourses
            }
        }
    }
}
