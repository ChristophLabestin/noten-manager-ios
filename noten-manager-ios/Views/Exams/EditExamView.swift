import SwiftUI
import FirebaseAuth

struct EditExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let exam: Exam

    @State private var subjectName: String
    @State private var title: String
    @State private var notes: String
    @State private var date: Date
    @State private var includeTime: Bool
    @State private var time: Date
    @State private var examWeight: Int
    @State private var examAssessmentType: AssessmentType
    @State private var useCustomWeight: Bool
    @State private var customWeightText: String
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isCompleted: Bool
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var requiresGrade: Bool
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var personalNote: String = ""
    @State private var isSharing: Bool = false
    @State private var shareInfo: String?
    @State private var shareError: String?
    @State private var isUnsharing: Bool = false
    @State private var selectedGroupIds: Set<String> = []
    @State private var selectedClassIds: Set<String> = []
    @State private var selectedCourseIds: Set<String> = []
    @State private var autoSelectedGroupIds: Set<String> = []
    @State private var autoSelectedCourseIds: Set<String> = []
    @State private var shareWithGroup: Bool = false
    @FocusState private var focusedField: Field?
    @State private var fachreferatSubjectName: String = ""
    private let isFachreferatExam: Bool
    private let isGeneralEvent: Bool

    init(exam: Exam) {
        self.exam = exam
        _subjectName = State(initialValue: exam.subjectName)
        _title = State(initialValue: exam.title)
        _notes = State(initialValue: exam.notes ?? "")
        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: exam.date)
        let hasExactTime = exam.hasTime || !calendar.isDate(exam.date, equalTo: normalizedDate, toGranularity: .minute)
        _date = State(initialValue: normalizedDate)
        _includeTime = State(initialValue: hasExactTime)
        let initialTime = hasExactTime ? exam.date : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: exam.date) ?? exam.date)
        _time = State(initialValue: initialTime)
        let hasCustomWeight = exam.customWeight != nil
        let initialCustomWeightText = exam.customWeight.map { EditExamView.formatWeight($0) } ?? ""
        _examWeight = State(initialValue: exam.weight ?? 0)
        _examAssessmentType = State(initialValue: exam.assessmentType ?? .muendlich)
        _useCustomWeight = State(initialValue: hasCustomWeight)
        _customWeightText = State(initialValue: initialCustomWeightText)
        let initialReminder = exam.reminderAt ?? Date().addingTimeInterval(60 * 60)
        _hasReminder = State(initialValue: exam.reminderAt != nil)
        _reminderDate = State(initialValue: initialReminder)
        _isCompleted = State(initialValue: exam.isCompleted)
        _requiresGrade = State(initialValue: exam.requiresGrade ?? true)
        let trimmedSubject = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        isFachreferatExam = trimmedSubject.lowercased() == "fachreferat"
        isGeneralEvent = trimmedSubject.isEmpty && (exam.requiresGrade == false)
        _fachreferatSubjectName = State(initialValue: exam.subjectKey ?? "")
        
        // Initialize selection with current exam location
        if exam.isShared {
            if let gid = exam.groupId {
                _selectedGroupIds = State(initialValue: [gid])
                _shareWithGroup = State(initialValue: true)
            } else if let cid = exam.courseId {
                _selectedCourseIds = State(initialValue: [cid])
                _shareWithGroup = State(initialValue: true)
            } else if let clid = exam.classId {
                _selectedClassIds = State(initialValue: [clid])
                _shareWithGroup = State(initialValue: true)
            }
        }
    }

    private enum Field: Hashable {
        case title, notes
    }

    private var subjects: [Subject] {
        var result = store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
        // Ensure the exam's current subject is always in the list for shared exams
        let examSubjectName = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !examSubjectName.isEmpty && !result.contains(where: { $0.name == examSubjectName }) {
            // Create a placeholder subject for the picker
            let placeholderSubject = Subject(
                name: examSubjectName,
                type: 0,
                gradingMode: .withoutSchulaufgaben,
                date: Date()
            )
            result.insert(placeholderSubject, at: 0)
        }
        return result
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if !isGeneralEvent && !isFachreferatExam && subjectName.isEmpty { return false }
        if isFachreferatExam && fachreferatSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if allowWeights && useCustomWeight && parsedCustomWeight() == nil { return false }
        return true
    }

    private var sheetTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if isFachreferatExam { return "Fachreferat" }
        if isGeneralEvent { return "Termin" }
        return "Klausur"
    }

    private var allowWeights: Bool {
        !isGeneralEvent && !isFachreferatExam && !subjectName.isEmpty
    }

    private func gradingMode(for name: String) -> GradingMode {
        let subject = subjects.first(where: { $0.name == name })
        return subject?.gradingMode ?? ((subject?.type == 1) ? .withSchulaufgaben : .withoutSchulaufgaben)
    }

    private func weightOptions(for gradingMode: GradingMode) -> [(title: String, value: Int, type: AssessmentType)] {
        switch gradingMode {
        case .withSchulaufgaben:
            return [
                ("Schulaufgabe", 2, .schulaufgabe),
                ("Kurzarbeit", 2, .kurzarbeit),
                ("Mündlich / EX", 1, .muendlich)
            ]
        case .withoutSchulaufgaben:
            return [
                ("Kurzarbeit", 1, .kurzarbeit),
                ("Mündlich / EX", 1, .muendlich)
            ]
        }
    }

    private func selectedWeightLabel(for gradingMode: GradingMode) -> String {
        if useCustomWeight {
            if let custom = parsedCustomWeight() {
                return "Sonstige Leistung (\(EditExamView.formatWeight(custom))x)"
            }
            return "Sonstige Leistung"
        }
        let options = weightOptions(for: gradingMode)
        if let match = options.first(where: { $0.value == examWeight && $0.type == examAssessmentType }) {
            return match.title
        }
        let matches = options.filter { $0.value == examWeight }
        if matches.count == 1, let match = matches.first {
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

    private static func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func syncAssessmentTypeForCurrentWeight(gradingMode: GradingMode) {
        guard allowWeights, !useCustomWeight else { return }
        let options = weightOptions(for: gradingMode)
        if options.contains(where: { $0.value == examWeight && $0.type == examAssessmentType }) { return }
        let matches = options.filter { $0.value == examWeight }
        if let match = matches.first {
            examAssessmentType = match.type
        }
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

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isSharedOwner: Bool {
        exam.isShared && exam.creatorId == currentUserId
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Klausur bearbeiten",
                        subtitle: "Fach, Titel und Gewichtung",
                        systemImage: "calendar.badge.clock",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    if isFachreferatExam {
                                        Text("Fachreferat")
                                            .font(.headline)
                                        Text("Fachreferat (fest)")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Fach für das Fachreferat")
                                                .font(.subheadline)
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
                                        }
                                    } else if isGeneralEvent {
                                        Text("Fach")
                                            .font(.headline)
                                        Text("Kein Fach nötig")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(10)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    } else {
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
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Titel / Bezeichnung")
                                            .font(.headline)
                                        TextField("z. B. Kurzarbeit Mathematik", text: $title)
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

                                    if isGeneralEvent {
                                        Text("Keine Gewichtung nötig – anderer Termin.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if isFachreferatExam {
                                        Text("Keine Gewichtung – Fachreferat-Termin.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        let gm = gradingMode(for: subjectName)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("Art")
                                                .font(.headline)
                                            Menu {
                                                ForEach(weightOptions(for: gm), id: \.type) { option in
                                                    let isSelected = !useCustomWeight && examWeight == option.value && examAssessmentType == option.type
                                                    Button {
                                                        useCustomWeight = false
                                                        examWeight = option.value
                                                        examAssessmentType = option.type
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
                                                    Text(selectedWeightLabel(for: gm))
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
                                                if gm == .withSchulaufgaben {
                                                    return "Schulaufgaben zählen doppelt, Kurzarbeiten und Mündlich / EX einfach. Sonstige Leistungen können eigene Gewichtung haben"
                                                }
                                                return "Kurzarbeiten zählen doppelt, Mündlich / EX einfach. Sonstige Leistungen können eigene Gewichtung haben"
                                            }()
                                            Text(weightInfo)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
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
                        title: "Erinnerung & Status",
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

                                if !exam.isShared {
                                    Toggle("Als erledigt markieren", isOn: $isCompleted)
                                        .tint(.green)
                                }
                            }
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !exam.isShared && (!store.classIds.isEmpty || !store.courses.isEmpty) {
                        // For General Events, show ALL courses since there's no subject to filter by
                        let availableCourses: [Course] = {
                            if isGeneralEvent {
                                return Array(Dictionary(grouping: store.courses, by: { $0.id }).values.compactMap(\.first))
                            }
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
                        
                        if shareWithGroup {
                            SettingsSectionBox {
                                Button {
                                    Task { await shareToGroups() }
                                } label: {
                                    if isSharing {
                                        ProgressView()
                                    } else {
                                        Text("Teilen")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .blue))
                                .disabled(isSharing || (selectedClassIds.isEmpty && selectedCourseIds.isEmpty))
                            }
                            .padding(.top, -8)
                        }

                        if let shareInfo {
                            Text(shareInfo)
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 16)
                        }
                        if let shareError {
                            Text(shareError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                    } else if exam.isShared && isSharedOwner {
                         // Editing existing shared exam targets
                         let availableCourses: [Course] = {
                             if isGeneralEvent {
                                 return Array(Dictionary(grouping: store.courses, by: { $0.id }).values.compactMap(\.first))
                             }
                             let targetIds = Set(store.targetCourseIds(forLocalSubject: subjectName))
                             var matches = store.courses.filter { targetIds.contains($0.id) }
                             // Always include the current course the exam is shared to
                             if let cid = exam.courseId, !matches.contains(where: { $0.id == cid }) {
                                 if let currentCourse = store.courses.first(where: { $0.id == cid }) {
                                     matches.append(currentCourse)
                                 }
                             }
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
                         
                        if let shareInfo {
                            Text(shareInfo)
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 16)
                        }
                        if let shareError {
                            Text(shareError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                    }

                    if exam.isShared {
                        SettingsCard(
                            title: "Eigene Notiz",
                            subtitle: "Nur für dich sichtbar",
                            systemImage: "note.text",
                            accent: .teal
                        ) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Persönliche Notiz")
                                        .font(.headline)
                                    TextEditor(text: $personalNote)
                                        .frame(minHeight: 100)
                                        .scrollContentBackground(.hidden)
                                        .padding(10)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    if exam.isShared, isSharedOwner, let gid = exam.groupId {
                        SettingsCard(
                            title: "Teilen beenden",
                            subtitle: "Nur der Ersteller kann das Teilen stoppen",
                            systemImage: "xmark.circle",
                            accent: .red
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                Button(role: .destructive) {
                                    Task { await stopSharing(groupId: gid) }
                                } label: {
                                    if isUnsharing {
                                        ProgressView()
                                    } else {
                                        Text("Aus Gruppe entfernen")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .red))
                                .disabled(isUnsharing)
                                if let shareInfo {
                                    Text(shareInfo)
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                }
                                if let shareError {
                                    Text(shareError)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Klausur löschen")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .red))
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
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ToolbarLoadingIcon()
                        } else {
                            ToolbarIcon(symbol: "checkmark", showDot: false)
                        }
                    }
                    .accessibilityLabel("Speichern")
                    .disabled(!canSave || isSaving || (subjects.isEmpty && !isGeneralEvent && !isFachreferatExam))
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: date) { _, newValue in
                date = Calendar.current.startOfDay(for: newValue)
            }
            .onChange(of: subjectName) { _, newValue in
                if newValue.isEmpty {
                    useCustomWeight = false
                    customWeightText = ""
                }
            }
            .onAppear {
                // Only update selections for non-shared exams to avoid overwriting existing sharing targets
                if !exam.isShared {
                    updateSelectedGroupsForSubject(subjectName)
                }
                // For already shared exams, keep shareWithGroup = true (set in init)
                // For non-shared exams, only enable sharing toggle if targets are selected
                if exam.isShared {
                    shareWithGroup = true
                } else {
                    shareWithGroup = !selectedClassIds.isEmpty || !selectedCourseIds.isEmpty || !selectedGroupIds.isEmpty
                }
                syncAssessmentTypeForCurrentWeight(gradingMode: gradingMode(for: subjectName))
            }
            .onChange(of: subjectName) { _, newSubject in
                updateSelectedGroupsForSubject(newSubject)
                syncAssessmentTypeForCurrentWeight(gradingMode: gradingMode(for: newSubject))
            }
            .alert(
                "Klausur löschen?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Abbrechen", role: .cancel) { showDeleteConfirm = false }
                Button("Löschen", role: .destructive) {
                    Task { await deleteExam() }
                }
            } message: {
                Text("Dieser Klausurtermin wird dauerhaft gelöscht.")
            }
        }
        .keyboardNavigationToolbar(focus: $focusedField, fields: [.title, .notes])
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            error = "Bitte einen Titel für die Klausur eingeben."
            isSaving = false
            return
        }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        let allowWeights = self.allowWeights
        let customWeight = allowWeights && useCustomWeight ? parsedCustomWeight() : nil
        if allowWeights && useCustomWeight && customWeight == nil {
            error = "Bitte eine gültige Gewichtung für die sonstige Leistung angeben."
            isSaving = false
            return
        }
        if isFachreferatExam && fachreferatSubjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Bitte ein Fach für das Fachreferat auswählen."
            isSaving = false
            return
        }
        do {
            let examDate = combinedExamDate()
            let reminder: Date? = hasReminder ? reminderDate : nil
            let weightToStore: Int? = allowWeights && !useCustomWeight ? examWeight : nil
            let effectiveSubject = isFachreferatExam ? "Fachreferat" : subjectName
            let relatedSubjectRaw = isFachreferatExam ? fachreferatSubjectName.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let relatedSubject = (relatedSubjectRaw?.isEmpty == false) ? relatedSubjectRaw : nil
            let requiresGradeValue = isGeneralEvent ? false : requiresGrade
            let hasTime = includeTime
            if exam.isShared {
                if let gid = exam.groupId {
                    if store.wahlpflichtfachGroupIds.contains(gid) {
                        try await store.updateSharedExamInWpGroup(
                            wpGroupId: gid,
                            id: exam.id,
                            subjectName: effectiveSubject,
                            subjectKey: relatedSubject,
                            title: trimmedTitle,
                            notes: storedNotes,
                            date: examDate,
                            hasTime: hasTime,
                            weight: weightToStore,
                            customWeight: customWeight,
                            assessmentType: allowWeights && !useCustomWeight ? examAssessmentType : nil,
                            reminderAt: reminder
                        )
                    } else {
                        try await store.updateSharedExamInGroup(
                            groupId: gid,
                            id: exam.id,
                            subjectName: effectiveSubject,
                            subjectKey: relatedSubject,
                            title: trimmedTitle,
                            notes: storedNotes,
                            date: examDate,
                            hasTime: hasTime,
                            weight: weightToStore,
                            customWeight: customWeight,
                            assessmentType: allowWeights && !useCustomWeight ? examAssessmentType : nil,
                            reminderAt: reminder
                        )
                    }
                    try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminder, groupId: gid)
                    await store.setUserNoteForSharedExam(examId: exam.id, note: personalNote, groupId: gid)
                } else if let cid = exam.courseId {
                     // Course-level exams: nested path classes/{classId}/courses/{courseId}/exams
                     try await store.updateSharedExamInCourse(
                        courseId: cid,
                        id: exam.id,
                        subjectName: effectiveSubject,
                        subjectKey: relatedSubject,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: examDate,
                        hasTime: hasTime,
                        weight: weightToStore,
                        customWeight: customWeight,
                        assessmentType: allowWeights && !useCustomWeight ? examAssessmentType : nil,
                        reminderAt: reminder
                     )
                     try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminder, groupId: nil) 
                     await store.setUserNoteForSharedExam(examId: exam.id, note: personalNote, groupId: nil)
                } else if let clid = exam.classId {
                     // Class-level exams: classes/{classId}/exams
                     try await store.updateSharedExamInClass(
                        classId: clid,
                        id: exam.id,
                        subjectName: effectiveSubject,
                        subjectKey: relatedSubject,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: examDate,
                        hasTime: hasTime,
                        weight: weightToStore,
                        customWeight: customWeight,
                        assessmentType: allowWeights && !useCustomWeight ? examAssessmentType : nil,
                        reminderAt: reminder
                     )
                     try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminder, groupId: nil)
                     await store.setUserNoteForSharedExam(examId: exam.id, note: personalNote, groupId: nil)
                } else {
                    // Fallback or Error
                    error = "Keine Gruppe oder Kurs für diese geteilte Klausur gefunden."
                    isSaving = false
                    return
                }

                // Handle changes in sharing targets if owner
                if isSharedOwner {
                    await updateSharingTargets()
                }
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: effectiveSubject,
                    subjectKey: relatedSubject,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: examDate,
                    hasTime: hasTime,
                    weight: weightToStore,
                    customWeight: customWeight,
                    assessmentType: allowWeights && !useCustomWeight ? examAssessmentType : nil,
                    reminderAt: reminder,
                    isCompleted: isCompleted,
                    requiresGrade: requiresGradeValue
                )
            }
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteExam() async {
        guard !isDeleting else { return }
        isDeleting = true
        await store.deleteExam(exam)
        await MainActor.run {
            showDeleteConfirm = false
            dismiss()
        }
        isDeleting = false
    }

    private func shareToGroups() async {
        guard !isSharing else { return }
        shareError = nil
        shareInfo = nil
        isSharing = true
        
        // Determine override subject name
        // If subjectName is not in local subjects (e.g. "Termin" or "Fachreferat"), pass it.
        // Otherwise pass nil (use Course Name).
        let isLocalSubject = subjects.contains(where: { $0.name == subjectName })
        let overrideSubjectName = isLocalSubject ? nil : subjectName
        
        var createdAny = false
        
        // 1. Share to selected Courses
        for courseId in selectedCourseIds {
            do {
                _ = try await store.addExamToCourse(
                    courseId: courseId,
                    subjectName: overrideSubjectName,
                    title: title,
                    notes: notes,
                    date: combinedExamDate(),
                    hasTime: includeTime,
                    weight: useCustomWeight ? nil : examWeight,
                    customWeight: useCustomWeight ? parsedCustomWeight() : nil,
                    assessmentType: useCustomWeight ? nil : examAssessmentType,
                    reminderAt: hasReminder ? reminderDate : nil,
                    requiresGrade: requiresGrade
                )
                createdAny = true
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
            }
        }
        
        // 2. For selected classes: share to courses belonging to those classes (if any)
        for classId in selectedClassIds {
            // Find courses that belong to this class
            let classCoursesIds = store.courses.filter { $0.classId == classId }.map { $0.id }
            for courseId in classCoursesIds where !selectedCourseIds.contains(courseId) {
                do {
                    _ = try await store.addExamToCourse(
                        courseId: courseId,
                        subjectName: overrideSubjectName,
                        title: title,
                        notes: notes,
                        date: combinedExamDate(),
                        hasTime: includeTime,
                        weight: useCustomWeight ? nil : examWeight,
                        customWeight: useCustomWeight ? parsedCustomWeight() : nil,
                        assessmentType: useCustomWeight ? nil : examAssessmentType,
                        reminderAt: hasReminder ? reminderDate : nil,
                        requiresGrade: requiresGrade
                    )
                    createdAny = true
                } catch {
                    ErrorLoggingService.logErrorIfEnabled(error)
                }
            }
        }
        
        await MainActor.run {
            isSharing = false
            if createdAny {
                shareInfo = "Geteilt."
                dismiss()
            } else {
                shareError = "Teilen fehlgeschlagen."
            }
        }
    }

    private func stopSharing(groupId: String) async {
        guard !isUnsharing else { return }
        shareError = nil
        shareInfo = nil
        isUnsharing = true
        let success = await store.stopSharingExam(groupId: groupId, examId: exam.id)
        await MainActor.run {
            isUnsharing = false
            if success {
                shareInfo = "Teilen beendet."
                dismiss()
            } else {
                shareError = "Konnte Teilen nicht beenden."
            }
        }
    }

    private func updateSharingTargets() async {
        guard let currentId = currentUserId, exam.creatorId == currentId else { return }
        
        // 1. Check if the current source was deselected
        if let clid = exam.classId, !selectedClassIds.contains(clid) {
            await store.deleteSharedExamFromClass(classId: clid, id: exam.id)
        }
        if let cid = exam.courseId, !selectedCourseIds.contains(cid) {
            try? await store.deleteExamFromCourse(courseId: cid, examId: exam.id, classId: exam.classId)
        }
        if let gid = exam.groupId, !selectedGroupIds.contains(gid) {
            if store.wahlpflichtfachGroupIds.contains(gid) {
                await store.deleteSharedExamFromWpGroup(wpGroupId: gid, id: exam.id)
            } else {
                await store.deleteSharedExamFromGroup(groupId: gid, id: exam.id)
            }
        }

        // 2. Share to new targets
        let overrideSubjectName = subjects.contains(where: { $0.name == subjectName }) ? nil : subjectName
        let effectiveSubject = isFachreferatExam ? "Fachreferat" : subjectName
        let weightToStore = useCustomWeight ? nil : examWeight
        let customWeight = useCustomWeight ? parsedCustomWeight() : nil
        
        // Share to new Classes
        let targetClassIds = selectedClassIds.filter { $0 != exam.classId }
        for clid in targetClassIds {
            _ = try? await store.addExamToClass(
                classId: clid,
                subjectName: isGeneralEvent ? (overrideSubjectName ?? "Termin") : effectiveSubject,
                title: title,
                notes: notes,
                date: combinedExamDate(),
                hasTime: includeTime,
                weight: weightToStore,
                customWeight: customWeight,
                assessmentType: useCustomWeight ? nil : examAssessmentType,
                reminderAt: hasReminder ? reminderDate : nil,
                requiresGrade: requiresGrade
            )
        }
        
        // Share to new Wahlpflicht/Courses
        let targetCourseIds = selectedCourseIds.filter { $0 != exam.courseId }
        for cid in targetCourseIds {
            if let course = store.courses.first(where: { $0.id == cid }) {
                if case .wahlpflicht(let wpId) = course.type {
                    // Only share if not already the current source
                    if exam.groupId != wpId {
                        _ = try? await store.addExamToWahlpflichtfachGroup(
                            wpGroupId: wpId,
                            subjectName: isGeneralEvent ? (overrideSubjectName ?? "Termin") : effectiveSubject,
                            title: title,
                            notes: notes,
                            date: combinedExamDate(),
                            hasTime: includeTime,
                            weight: weightToStore,
                            customWeight: customWeight,
                            assessmentType: useCustomWeight ? nil : examAssessmentType,
                            reminderAt: hasReminder ? reminderDate : nil,
                            requiresGrade: requiresGrade
                        )
                    }
                } else {
                    _ = try? await store.addExamToCourse(
                        courseId: cid,
                        subjectName: overrideSubjectName,
                        title: title,
                        notes: notes,
                        date: combinedExamDate(),
                        hasTime: includeTime,
                        weight: weightToStore,
                        customWeight: customWeight,
                        assessmentType: useCustomWeight ? nil : examAssessmentType,
                        reminderAt: hasReminder ? reminderDate : nil,
                        requiresGrade: requiresGrade
                    )
                }
            }
        }
        
        // Share to new Social Groups
        let targetSocialGroupIds = Array(selectedGroupIds.filter { gid in
            gid != exam.groupId && (store.groupTypes[gid] == "social")
        })
        if !targetSocialGroupIds.isEmpty {
            _ = try? await store.addExamToGroups(
                subjectName: isGeneralEvent ? (overrideSubjectName ?? "Termin") : effectiveSubject,
                title: title,
                notes: notes,
                date: combinedExamDate(),
                hasTime: includeTime,
                weight: weightToStore,
                customWeight: customWeight,
                assessmentType: useCustomWeight ? nil : examAssessmentType,
                reminderAt: hasReminder ? reminderDate : nil,
                requiresGrade: requiresGrade,
                targetGroupIds: targetSocialGroupIds
            )
        }
        
    }

    private func updateSelectedGroupsForSubject(_ subject: String) {
        // Only update auto-selection if NOT editing an existing shared exam
        // (If editing, we want to respect the user's explicit choices or the exam's current state)
        if exam.isShared { return }

        // 1. Remove previously auto-selected courses
        selectedCourseIds.subtract(autoSelectedCourseIds)
        autoSelectedCourseIds.removeAll()
        
        // 2. If subject is valid, find new matches
        if !subject.isEmpty {
            let matchedCourses = Set(store.targetCourseIds(forLocalSubject: subject))
            if !matchedCourses.isEmpty {
                selectedCourseIds.formUnion(matchedCourses)
                autoSelectedCourseIds = matchedCourses
            }
        }
    }
}
