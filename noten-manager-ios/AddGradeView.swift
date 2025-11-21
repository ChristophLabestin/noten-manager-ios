import SwiftUI
import CryptoKit

struct AddGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    // Neu: optionale Vorauswahl (z. B. von SubjectDetail oder Prüfung)
    let preselectedSubjectName: String?
    let preselectedWeight: Int?
    let prefilledNote: String?

    @State private var subjectName: String = ""
    @State private var gradeText: String = ""
    @State private var gradeWeight: Int = 0
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var halfYearSelection: Int = AddGradeView.defaultHalfYear()
    @State private var isSaving: Bool = false
    @State private var error: String?

    private var subjects: [Subject] { store.subjects.filter { $0.name != "Fachreferat" } }
    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard let value = Double(gradeText),
              value >= 0, value <= 15 else { return false }
        return true
    }

    init(preselectedSubjectName: String? = nil, preselectedWeight: Int? = nil, prefilledNote: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
        self.preselectedWeight = preselectedWeight
        self.prefilledNote = prefilledNote
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
                halfYearSelection = AddGradeView.defaultHalfYear()
            }
        }
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
            let weight = Double(gradeWeight)
            let halfYear: Int? = halfYearSelection
            _ = try await store.addGradeToFirestore(subjectId: subjectName, grade: grade, weight: weight, date: date, note: note.isEmpty ? nil : note, halfYear: halfYear, using: key)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private static func defaultHalfYear() -> Int {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 23
        let calendar = Calendar.current
        let switchDate = calendar.date(from: components) ?? Date()
        return Date() < switchDate ? 1 : 2
    }
}
