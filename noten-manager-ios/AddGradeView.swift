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
    @State private var gradeWeight: Int = 0
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var halfYearSelection: Int = AddGradeView.defaultHalfYear()
    @State private var isSaving: Bool = false
    @State private var error: String?

    @State private var linkToExam: Bool = false
    @State private var selectedLinkedExamId: String? = nil

    private var subjects: [Subject] { store.subjects.filter { $0.name != "Fachreferat" } }
    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard let value = Double(gradeText),
              value >= 0, value <= 15 else { return false }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Fach & Leistung") {
                    Picker("Fach", selection: $subjectName) {
                        ForEach(subjects, id: \.name) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    TextField("Note (0–15)", text: $gradeText)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }

                    // Art & Halbjahr wie im React-Client:
                    // Hauptfach: Schulaufgabe (2), Kurzarbeit (1), Mündlich/EX (0)
                    // Nebenfach: Kurzarbeit (1), Mündlich/EX (0)
                    let subjectType = subjects.first(where: { $0.name == subjectName })?.type ?? 0
                    Picker("Art", selection: $gradeWeight) {
                        if subjectType == 0 {
                            Text("Kurzarbeit").tag(1)
                            Text("Mündlich / EX").tag(0)
                        } else {
                            Text("Schulaufgabe").tag(2)
                            Text("Kurzarbeit").tag(1)
                            Text("Mündlich / EX").tag(0)
                        }
                    }

                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Picker("Halbjahr", selection: $halfYearSelection) {
                        Text("1. Hj").tag(1)
                        Text("2. Hj").tag(2)
                    }
                    .pickerStyle(.segmented)
                    TextField("Notiz (optional)", text: $note)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                Section("Prüfung verknüpfen") {
                    Toggle("Mit Prüfung verknüpfen", isOn: $linkToExam)
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
                                                .foregroundStyle(isSelected ? .blue : .secondary)
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
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
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Note hinzufügen")
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
                // Standardmäßig Mündlich / EX oder vorselektiertes Gewicht
                if let w = preselectedWeight {
                    gradeWeight = w
                } else {
                    gradeWeight = 0
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
            }
        }
        .keyboardDismissToolbar()
    }

    private func save() async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        error = nil
        do {
            guard let grade = Double(gradeText) else {
                error = "Bitte eine gültige Note zwischen 0 und 15 eingeben."
                isSaving = false
                return
            }
            if linkToExam && selectedLinkedExamId == nil {
                error = "Bitte eine Prüfung auswählen."
                isSaving = false
                return
            }
            let weight = Double(gradeWeight)
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
            let gradeId = try await store.addGradeToFirestore(subjectId: subjectName, grade: grade, weight: weight, date: date, note: finalNote, halfYear: halfYear, using: key)
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
