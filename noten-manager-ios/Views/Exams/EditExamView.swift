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
    }

    private enum Field: Hashable {
        case title, notes
    }

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
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
                ("Kurzarbeit", 1, .kurzarbeit),
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

    private static func formatWeight(_ value: Double) -> String {
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
                                                ForEach(weightOptions(for: gm), id: \.title) { option in
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

                                    if allowWeights && !subjectName.isEmpty {
                                        Toggle("Note verknüpfen erforderlich", isOn: $requiresGrade)
                                            .tint(.indigo)
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

                    if !exam.isShared && !store.groupIds.isEmpty && !subjectName.isEmpty && !isGeneralEvent && !isFachreferatExam {
                        SettingsCard(
                            title: "Mit Gruppe teilen",
                            subtitle: "Klausur nachträglich veröffentlichen",
                            systemImage: "person.3.fill",
                            accent: .blue
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                if !store.classIds.isEmpty || !store.groupIds.isEmpty {
                                    VStack(alignment: .leading, spacing: 16) {
                                        // Classes Section
                                        if !store.classIds.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Label("Klassen", systemImage: "rectangle.stack.fill")
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                
                                                FlowLayout(spacing: 8) {
                                                    ForEach(store.classIds, id: \.self) { cid in
                                                        let name = store.classNames[cid] ?? "Klasse"
                                                        let classGroups = Set(store.classDetails[cid]?.groupIds ?? [])
                                                        let isFullySelected = !classGroups.isEmpty && classGroups.isSubset(of: selectedGroupIds)
                                                        
                                                        Button {
                                                            withAnimation(.snappy) {
                                                                if isFullySelected {
                                                                    selectedGroupIds.subtract(classGroups)
                                                                } else {
                                                                    selectedGroupIds.formUnion(classGroups)
                                                                }
                                                            }
                                                        } label: {
                                                            HStack(spacing: 6) {
                                                                Text(name)
                                                                if isFullySelected {
                                                                    Image(systemName: "checkmark")
                                                                        .font(.caption.bold())
                                                                }
                                                            }
                                                            .font(.subheadline.weight(.medium))
                                                            .padding(.horizontal, 12)
                                                            .padding(.vertical, 8)
                                                            .background(isFullySelected ? Color.indigo : Color.indigo.opacity(0.1))
                                                            .foregroundStyle(isFullySelected ? .white : .indigo)
                                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                            }
                                        }

                                        // Groups Section
                                        if !store.groupIds.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Label("Einzelne Gruppen", systemImage: "person.3.fill")
                                                    .font(.footnote.weight(.semibold))
                                                    .foregroundStyle(.secondary)
                                                
                                                FlowLayout(spacing: 8) {
                                                    ForEach(store.groupIds, id: \.self) { gid in
                                                        let name = store.groupNames[gid] ?? gid
                                                        let isSelected = selectedGroupIds.contains(gid)
                                                        
                                                        Button {
                                                            withAnimation(.snappy) {
                                                                if isSelected {
                                                                    selectedGroupIds.remove(gid)
                                                                } else {
                                                                    selectedGroupIds.insert(gid)
                                                                }
                                                            }
                                                        } label: {
                                                            HStack(spacing: 6) {
                                                                Text(name)
                                                                if isSelected {
                                                                    Image(systemName: "checkmark")
                                                                        .font(.caption.bold())
                                                                }
                                                            }
                                                            .font(.subheadline.weight(.medium))
                                                            .padding(.horizontal, 12)
                                                            .padding(.vertical, 8)
                                                            .background(isSelected ? Color.orange : Color.orange.opacity(0.1))
                                                            .foregroundStyle(isSelected ? .white : .orange)
                                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(16)
                                    .background(Color.secondary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }

                                Button {
                                    Task { await shareToGroups() }
                                } label: {
                                    if isSharing {
                                        ProgressView()
                                    } else {
                                        Text("In Gruppe teilen")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .blue))
                                .disabled(isSharing || selectedGroupIds.isEmpty)

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
                if selectedGroupIds.isEmpty, let first = store.groupIds.first {
                    selectedGroupIds = [first]
                }
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
                guard let gid = exam.groupId else {
                    error = "Keine Gruppe für diese Klausur gefunden."
                    isSaving = false
                    return
                }
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
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminder, groupId: gid)
                await store.setUserNoteForSharedExam(examId: exam.id, note: personalNote, groupId: gid)
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
        if exam.isShared, let gid = exam.groupId {
            await store.deleteSharedExamFromGroup(groupId: gid, id: exam.id)
        } else {
            await store.deleteExamFromFirestore(id: exam.id)
        }
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
        let success = await store.shareExamToGroups(
            examId: exam.id,
            targetGroupIds: Array(selectedGroupIds)
        )
        await MainActor.run {
            isSharing = false
            if success {
                shareInfo = "In Gruppe geteilt."
                dismiss()
            } else {
                shareError = "Teilen fehlgeschlagen. Prüfe Gruppen und versuche es erneut."
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
}
