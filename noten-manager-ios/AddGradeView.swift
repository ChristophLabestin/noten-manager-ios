import SwiftUI
import CryptoKit

struct AddGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    // Neu: optionale Vorauswahl (z. B. von SubjectDetail oder Prüfung)
    let preselectedSubjectName: String?
    let preselectedWeight: Int?
    let prefilledNote: String?

    let linkedExamId: String?
    let markLinkedExamCompletedByDefault: Bool

    @State private var subjectName: String = ""
    @State private var gradeText: String = ""
    @State private var weightChoice: WeightChoice = .preset(0)
    @State private var customWeightText: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var halfYearSelection: Int = AddGradeView.defaultHalfYear()
    @State private var isSaving: Bool = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

    @State private var linkToExam: Bool = false
    @State private var selectedLinkedExamId: String? = nil

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }
    private var isWeightLocked: Bool {
        linkToExam && selectedLinkedExamId != nil
    }
    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard let value = Double(gradeText),
              value >= 0, value <= 15 else { return false }
        if case .custom = weightChoice, parsedCustomWeight() == nil { return false }
        if linkToExam && selectedLinkedExamId == nil { return false }
        return true
    }

    private var linkableExams: [Exam] {
        let now = Date()
        return store.allExams
            .filter { exam in
                let keepIfSelected = exam.id == selectedLinkedExamId
                if exam.isCompleted && !keepIfSelected { return false }
                if exam.date > now && !keepIfSelected { return false }
                let subjectMatches = matchesSubject(for: exam)
                return subjectMatches
            }
            .sorted { $0.date > $1.date }
    }

    init(preselectedSubjectName: String? = nil, preselectedWeight: Int? = nil, prefilledNote: String? = nil, linkedExamId: String? = nil, markLinkedExamCompletedByDefault: Bool = false) {
        self.preselectedSubjectName = preselectedSubjectName
        self.preselectedWeight = preselectedWeight
        self.prefilledNote = prefilledNote
        self.linkedExamId = linkedExamId
        self.markLinkedExamCompletedByDefault = markLinkedExamCompletedByDefault
    }

    private enum Field: Hashable {
        case grade, note
    }

    private enum WeightChoice: Hashable {
        case preset(Double)
        case custom
    }

    private func weightOptions(for subjectType: Int) -> [(title: String, value: Double)] {
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
        switch weightChoice {
        case .preset(let value):
            let options = weightOptions(for: subjectType)
            if let match = options.first(where: { $0.value == value }) {
                return match.title
            }
            return "Art auswählen"
        case .custom:
            if let weight = parsedCustomWeight() {
                return "Sonstige Leistung (\(formatWeight(weight))x)"
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

    private func formatWeight(_ value: Double) -> String {
        if value == floor(value) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Note erfassen",
                        subtitle: "Fach, Gewichtung und Halbjahr",
                        systemImage: "list.bullet.rectangle.portrait.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Fach")
                                        .font(.headline)
                                    Picker("Fach", selection: $subjectName) {
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
                                        Text("Lege zuerst ein Fach an, um eine Note zuzuordnen.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Leistung")
                                        .font(.headline)

                                    TextField("Note (0–15)", text: $gradeText)
                                        .keyboardType(.numberPad)
                                        .submitLabel(.next)
                                        .focused($focusedField, equals: .grade)
                                        .onSubmit { focusedField = .note }
                                        .padding(12)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    let subjectType = subjects.first(where: { $0.name == subjectName })?.type ?? 0

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Art")
                                            .font(.subheadline)

                                        Menu {
                                            ForEach(weightOptions(for: subjectType), id: \.value) { option in
                                                let isSelected: Bool = {
                                                    if case .preset(let value) = weightChoice {
                                                        return value == option.value
                                                    }
                                                    return false
                                                }()
                                                Button {
                                                    weightChoice = .preset(option.value)
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
                                                Text("Die eingetragene Gewichtung wird genau so in den Durchschnitt übernommen.")
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
                                        if isWeightLocked {
                                            Text("Gewichtung durch verknüpfte Prüfung festgelegt.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Halbjahr")
                                            .font(.subheadline)
                                        Picker("", selection: $halfYearSelection) {
                                            Text("1. Hj").tag(1)
                                            Text("2. Hj").tag(2)
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    DatePicker("Datum", selection: $date, displayedComponents: .date)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Notiz (optional)")
                                            .font(.subheadline)
                                        TextField("Kommentar zur Leistung", text: $note)
                                            .submitLabel(.done)
                                            .focused($focusedField, equals: .note)
                                            .onSubmit { hideKeyboard() }
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }

                        HelpCenterLink(
                            title: "Hilfe zur Berechnung",
                            subtitle: "Gewichtungen & Notendurchschnitt im Help Center",
                            section: .calc,
                            accent: .indigo
                        )
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
                                    .onChange(of: linkToExam) { enabled in
                                        if enabled {
                                            ensureLinkedExamSelection()
                                        } else {
                                            selectedLinkedExamId = nil
                                        }
                                    }

                                if linkToExam {
                                    if linkableExams.isEmpty {
                                        Text("Keine offenen Termine für dieses Fach gefunden.")
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
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Speichern") }
                    }
                    .disabled(!canSave || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardNavigationAccessory(
                        focus: $focusedField,
                        fields: [.grade, .note],
                        label: nil,
                        onDone: { hideKeyboard() }
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .onAppear {
                if subjectName.isEmpty {
                    if let pre = preselectedSubjectName,
                       subjects.contains(where: { $0.name == pre }) {
                        subjectName = pre
                    } else {
                        subjectName = subjects.first?.name ?? ""
                    }
                }
                if let w = preselectedWeight {
                    weightChoice = .preset(Double(w))
                } else {
                    weightChoice = .preset(0)
                }

                if let noteText = prefilledNote, note.isEmpty {
                    note = noteText
                }

                if let examId = linkedExamId {
                    selectedLinkedExamId = examId
                    linkToExam = true
                }
                if let examId = linkedExamId {
                    if let sharedExam = store.sharedExams.first(where: { $0.id == examId }), let mapped = store.resolveLocalSubjectNameForExam(sharedExam) {
                        if store.subjects.contains(where: { $0.name == mapped }) {
                            subjectName = mapped
                        }
                    }
                }
                let referenceDate = examDate(for: selectedLinkedExamId) ?? Date()
                halfYearSelection = AddGradeView.defaultHalfYear(referenceDate: referenceDate)

                if markLinkedExamCompletedByDefault {
                    linkToExam = true
                }
                ensureLinkedExamSelection()
                applyExamWeightIfAvailable(examId: selectedLinkedExamId)
            }
            .onChange(of: subjectName) { _ in
                if linkToExam {
                    ensureLinkedExamSelection()
                }
            }
            .onChange(of: selectedLinkedExamId) { newValue in
                if let date = examDate(for: newValue) {
                    halfYearSelection = AddGradeView.defaultHalfYear(referenceDate: date)
                }
                applyExamWeightIfAvailable(examId: newValue)
            }
        }
        .modifier(KeyboardToolbarInset(height: 64))
    }

    private func save() async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        error = nil
        do {
            guard let grade = Double(gradeText), grade >= 0, grade <= 15 else {
                error = "Bitte eine gültige Note zwischen 0 und 15 eingeben."
                isSaving = false
                return
            }
            if linkToExam && selectedLinkedExamId == nil {
                error = "Bitte eine Prüfung auswählen."
                isSaving = false
                return
            }
            let weight: Double
            switch weightChoice {
            case .preset(let preset):
                weight = preset
            case .custom:
                guard let custom = parsedCustomWeight(), custom > 0 else {
                    error = "Bitte eine Gewichtung größer als 0 eingeben."
                    isSaving = false
                    return
                }
                weight = -custom
            }
            let halfYear: Int? = halfYearSelection

            let finalNote: String? = {
                var base = note.isEmpty ? nil : note
                if linkToExam, let _ = selectedLinkedExamId {
                    if let b = base, !b.isEmpty {
                        base = b + " — verknüpft mit Prüfung"
                    } else {
                        base = "verknüpft mit Prüfung"
                    }
                }
                return base
            }()
            let linkedExamId = linkToExam ? selectedLinkedExamId : nil
            let gradeId = try await store.addGradeToFirestore(
                subjectId: subjectName,
                grade: grade,
                weight: weight,
                date: date,
                note: finalNote,
                halfYear: halfYear,
                linkedExamId: linkedExamId,
                using: key
            )
            if linkToExam, let examId = selectedLinkedExamId {
                if store.sharedExams.contains(where: { $0.id == examId }) {
                    await store.setUserCompletedForSharedExam(examId: examId, completed: true)
                } else {
                    await store.setExamCompleted(id: examId, completed: true)
                }
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func ensureLinkedExamSelection() {
        guard linkToExam else { return }
        if let current = selectedLinkedExamId, linkableExams.contains(where: { $0.id == current }) {
            return
        }
        selectedLinkedExamId = linkableExams.first?.id
        applyExamWeightIfAvailable(examId: selectedLinkedExamId)
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
        examDateFormatter.string(from: exam.date)
    }

    private func examDate(for examId: String?) -> Date? {
        guard let examId else { return nil }
        return store.allExams.first(where: { $0.id == examId })?.date
    }

    private func applyExamWeightIfAvailable(examId: String?) {
        guard let examId else { return }
        if let exam = store.allExams.first(where: { $0.id == examId }) {
            if let w = exam.weight {
                weightChoice = .preset(Double(w))
            }
            return
        }
        if let exam = store.sharedExams.first(where: { $0.id == examId }) {
            if let w = exam.weight {
                weightChoice = .preset(Double(w))
            }
        }
    }

    private static func defaultHalfYear(referenceDate: Date = Date()) -> Int {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 13
        let calendar = Calendar.current
        let switchDate = calendar.date(from: components) ?? Date()
        return referenceDate < switchDate ? 1 : 2
    }
}

private let examDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .none
    return fmt
}()
