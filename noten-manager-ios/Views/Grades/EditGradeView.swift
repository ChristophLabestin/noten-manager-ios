import SwiftUI
import CryptoKit

struct EditGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let grade: GradeWithId
    let subjectName: String
    let subjectType: Int
    let gradingMode: GradingMode

    @State private var gradeText: String
    @State private var weightChoice: WeightChoice
    @State private var customWeightText: String
    @State private var date: Date
    @State private var halfYear: Int
    @State private var note: String
    @State private var assessmentType: AssessmentType
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var error: String?
    @State private var linkToExam: Bool = false
    @State private var selectedLinkedExamId: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case grade, note }
    private enum WeightChoice: Hashable { case preset(Double), custom }

    init(grade: GradeWithId, subjectName: String, subjectType: Int, gradingMode: GradingMode? = nil) {
        self.grade = grade
        self.subjectName = subjectName
        self.subjectType = subjectType
        let resolvedMode = gradingMode ?? (subjectType == 1 ? .withSchulaufgaben : .withoutSchulaufgaben)
        self.gradingMode = resolvedMode

        _gradeText = State(initialValue: EditGradeView.formatGrade(grade.grade))
        if grade.weight < 0 {
            _weightChoice = State(initialValue: .custom)
            _customWeightText = State(initialValue: EditGradeView.formatWeight(abs(grade.weight)))
        } else {
            _weightChoice = State(initialValue: .preset(grade.weight))
            _customWeightText = State(initialValue: "")
        }
        _date = State(initialValue: grade.date)
        _halfYear = State(initialValue: grade.halfYear ?? 1)
        _note = State(initialValue: grade.note ?? "")
        _linkToExam = State(initialValue: grade.linkedExamId != nil)
        _selectedLinkedExamId = State(initialValue: grade.linkedExamId)
        let initialType = EditGradeView.initialAssessmentType(for: grade, gradingMode: resolvedMode)
        _assessmentType = State(initialValue: initialType)
    }

    private func weightOptions() -> [(title: String, value: Double, type: AssessmentType)] {
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

    private func selectedWeightLabel() -> String {
        switch weightChoice {
        case .preset(let value):
            if value == 3 { return "Fachreferat" }
            if let match = weightOptions().first(where: { $0.value == value }) {
                return match.title
            }
            return "Sonstige Leistung"
        case .custom:
            if let weight = parsedCustomWeight() {
                return "Sonstige Leistung (\(EditGradeView.formatWeight(weight))x)"
            }
            return "Sonstige Leistung"
        }
    }

    private func parsedCustomWeight() -> Double? {
        let cleaned = customWeightText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private func resolvedWeight() -> Double? {
        switch weightChoice {
        case .preset(let value):
            return value
        case .custom:
            guard let custom = parsedCustomWeight() else { return nil }
            return -abs(custom)
        }
    }

    private func updateAssessmentTypeForWeight(_ value: Double) {
        if let match = weightOptions().first(where: { $0.value == value }) {
            assessmentType = match.type
        }
    }

    private var isWeightLocked: Bool {
        linkToExam && selectedLinkedExamId != nil
    }

    private var canSave: Bool {
        guard store.encryptionKey != nil else { return false }
        guard let value = Double(gradeText),
              value >= 0, value <= 15 else { return false }
        if case .custom = weightChoice {
            return parsedCustomWeight() != nil
        }
        if linkToExam && selectedLinkedExamId == nil { return false }
        return true
    }

    private var sheetTitle: String {
        subjectName.isEmpty ? "Note bearbeiten" : subjectName
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Note bearbeiten",
                        subtitle: subjectName,
                        systemImage: "list.bullet.rectangle.portrait.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Note")
                                        .font(.headline)
                                    TextField("0–15", text: $gradeText)
                                        .keyboardType(.decimalPad)
                                        .submitLabel(.next)
                                        .focused($focusedField, equals: .grade)
                                        .padding(12)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Art")
                                            .font(.headline)
                                        Menu {
                                            ForEach(weightOptions(), id: \.value) { option in
                                                let isSelected: Bool = {
                                                    if case .preset(let value) = weightChoice {
                                                        return value == option.value
                                                    }
                                                    return false
                                                }()
                                                Button {
                                                    weightChoice = .preset(option.value)
                                                    assessmentType = option.type
                                                    customWeightText = ""
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

                                            let isCustomSelected = {
                                                if case .custom = weightChoice { return true }
                                                return false
                                            }()
                                            Button {
                                                weightChoice = .custom
                                                assessmentType = .muendlich
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
                                                Text(selectedWeightLabel())
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
                                        .disabled(isWeightLocked)
                                        .opacity(isWeightLocked ? 0.6 : 1.0)

                                        if case .custom = weightChoice {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Gewichtung")
                                                    .font(.subheadline)
                                                TextField("Gewichtung z. B. 1 oder 2.5", text: $customWeightText)
                                                    .keyboardType(.decimalPad)
                                                    .padding(12)
                                                    .background(Color.formInputBackground)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                                    .disabled(isWeightLocked)
                                                    .opacity(isWeightLocked ? 0.6 : 1.0)
                                                Text("Eigene Gewichtungen werden genau so in den Schnitt übernommen.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            let info: String = {
                                                if gradingMode == .withSchulaufgaben {
                                                    return "Schulaufgaben zählen doppelt, Kurzarbeiten und Mündlich / EX einfach."
                                                }
                                                return "Kurzarbeiten zählen doppelt, Mündlich / EX einfach."
                                            }()
                                            Text(info)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if isWeightLocked {
                                            Text("Gewichtung durch verknüpfte Prüfung festgelegt.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Halbjahr")
                                            .font(.headline)
                                        Picker("", selection: $halfYear) {
                                            Text("1. Hj").tag(1)
                                            Text("2. Hj").tag(2)
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Datum")
                                            .font(.headline)
                                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Prüfung verknüpfen",
                        subtitle: "Optional mit einem Termin verbinden",
                        systemImage: "link.circle.fill",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Mit Prüfung verknüpfen", isOn: $linkToExam)
                                    .tint(.orange)
                                    .onChange(of: linkToExam) { _, enabled in
                                        if enabled {
                                            ensureLinkedExamSelection()
                                        } else {
                                            selectedLinkedExamId = nil
                                        }
                                    }

                                if linkToExam {
                                    if linkableExams.isEmpty {
                                        Text("Keine wartenden Termine für dieses Fach gefunden.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 10) {
                                            ForEach(linkableExams) { exam in
                                                let isSelected = selectedLinkedExamId == exam.id
                                                Button {
                                                    selectedLinkedExamId = exam.id
                                                } label: {
                                                    HStack(alignment: .top, spacing: 10) {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(examTitle(exam))
                                                                .font(.body.weight(.semibold))
                                                                .foregroundStyle(.primary)
                                                                .lineLimit(2)
                                                            Text(examDateString(exam))
                                                                .font(.caption)
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        Spacer()
                                                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                                            .foregroundStyle(isSelected ? .orange : .secondary)
                                                    }
                                                    .padding(12)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .fill(Color(.secondarySystemBackground))
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .stroke(isSelected ? Color.orange.opacity(0.8) : Color(.separator).opacity(0.1), lineWidth: 1)
                                                    )
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            Text("Die ausgewählte Prüfung wird als erledigt markiert.")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
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
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Kommentar")
                                    .font(.headline)
                                TextField("Kommentar zur Leistung", text: $note, axis: .vertical)
                                    .lineLimit(3, reservesSpace: true)
                                    .submitLabel(.done)
                                    .focused($focusedField, equals: .note)
                                    .padding(12)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
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
                    .disabled(!canSave || isSaving)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                    .disabled(isSaving || isDeleting)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if linkToExam {
                    ensureLinkedExamSelection()
                    applyExamWeightIfAvailable(examId: selectedLinkedExamId)
                }
            }
            .onChange(of: selectedLinkedExamId) { _, newValue in
                if let date = examDate(for: newValue) {
                    halfYear = date < EditGradeView.switchDate ? 1 : 2
                }
                applyExamWeightIfAvailable(examId: newValue)
            }
            .onChange(of: linkToExam) { _, enabled in
                if enabled {
                    applyExamWeightIfAvailable(examId: selectedLinkedExamId)
                }
            }
            .alert("Note löschen?", isPresented: $showDeleteConfirm) {
                Button("Abbrechen", role: .cancel) { showDeleteConfirm = false }
                Button("Löschen", role: .destructive) {
                    Task { await deleteGrade() }
                }
            } message: {
                Text("Diese Note wird dauerhaft gelöscht.")
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        guard let key = store.encryptionKey else { return }
        guard let value = Double(gradeText) else { return }
        guard let resolvedWeight = resolvedWeight() else { return }
        isSaving = true
        error = nil

        do {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedNote = trimmedNote.isEmpty ? nil : trimmedNote
            if linkToExam && selectedLinkedExamId == nil {
                error = "Bitte eine Prüfung auswählen."
                isSaving = false
                return
            }
            try await store.updateGradeInFirestore(
                subjectId: subjectName,
                gradeId: grade.id,
                grade: value,
                weight: resolvedWeight,
                date: date,
                note: storedNote,
                halfYear: halfYear,
                linkedExamId: linkToExam ? selectedLinkedExamId : nil,
                assessmentType: assessmentType,
                using: key
            )
            await MainActor.run {
                dismiss()
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    private func deleteGrade() async {
        guard !isDeleting else { return }
        isDeleting = true
        error = nil
        do {
            try await store.deleteGradeFromFirestore(subjectId: subjectName, gradeId: grade.id)
            await MainActor.run { dismiss() }
        } catch let err {
            ErrorLoggingService.logErrorIfEnabled(err)
            self.error = err.localizedDescription
        }
        isDeleting = false
    }

    private static func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private static func formatGrade(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func ensureLinkedExamSelection() {
        guard linkToExam else { return }
        if let current = selectedLinkedExamId, linkableExams.contains(where: { $0.id == current }) {
            return
        }
        selectedLinkedExamId = linkableExams.first?.id
        applyExamWeightIfAvailable(examId: selectedLinkedExamId)
    }

    private var linkableExams: [Exam] {
        let now = Date()
        return store.allExams
            .filter { exam in
                let keepIfSelected = exam.id == selectedLinkedExamId
                if exam.isCompleted && !keepIfSelected { return false }
                if exam.date > now && !keepIfSelected { return false }
                return matchesSubject(for: exam)
            }
            .sorted { $0.date > $1.date }
    }

    private func matchesSubject(for exam: Exam) -> Bool {
        let target = subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if target.isEmpty { return true }
        if exam.subjectName.lowercased() == target { return true }
        if let mapped = store.resolveLocalSubjectNameForExam(exam)?.lowercased(), mapped == target {
            return true
        }
        return false
    }

    private func examTitle(_ exam: Exam) -> String {
        let name = exam.title.isEmpty ? "Ohne Titel" : exam.title
        let subject = exam.subjectName
        if subject.isEmpty { return name }
        return "\(name)"
    }

    private func examDateString(_ exam: Exam) -> String {
        EditGradeView.examDateFormatter.string(from: exam.date)
    }

    private func examDate(for examId: String?) -> Date? {
        guard let examId else { return nil }
        return store.allExams.first(where: { $0.id == examId })?.date
    }

    private func applyExamWeightIfAvailable(examId: String?) {
        guard let examId else { return }
        let exam = store.allExams.first(where: { $0.id == examId }) ?? store.sharedExams.first(where: { $0.id == examId })
        guard let exam = exam else { return }

        if let custom = exam.customWeight {
            weightChoice = .custom
            customWeightText = EditGradeView.formatWeight(custom)
        } else if let w = exam.weight {
            let doubleWeight = Double(w)
            weightChoice = .preset(doubleWeight)
            
            if let type = exam.assessmentType {
                assessmentType = type
            } else {
                updateAssessmentTypeForWeight(doubleWeight)
            }
        }
    }

    private static func initialAssessmentType(for grade: GradeWithId, gradingMode: GradingMode) -> AssessmentType {
        if let type = grade.assessmentType { return type }
        if gradingMode == .withSchulaufgaben, grade.weight >= 2 {
            return .schulaufgabe
        }
        if grade.weight == 1 {
            return .kurzarbeit
        }
        return .muendlich
    }

    private static var switchDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 13
        return Calendar.current.date(from: components) ?? Date()
    }

    private static let examDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }()
}
