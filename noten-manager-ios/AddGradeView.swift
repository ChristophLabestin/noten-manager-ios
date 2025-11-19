import SwiftUI
import CryptoKit

struct AddGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var subjectName: String = ""
    @State private var gradeText: String = ""
    @State private var weightText: String = "1"
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var halfYearSelection: Int = 0 // 0 = none, 1, 2
    @State private var isSaving: Bool = false
    @State private var error: String?

    private var subjects: [Subject] { store.subjects.filter { $0.name != "Fachreferat" } }
    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard Double(gradeText) != nil else { return false }
        guard Double(weightText) != nil else { return false }
        return true
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
                    TextField("Note (z. B. 10.0)", text: $gradeText)
                        .keyboardType(.decimalPad)
                    TextField("Gewicht (z. B. 1)", text: $weightText)
                        .keyboardType(.decimalPad)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Picker("Halbjahr", selection: $halfYearSelection) {
                        Text("—").tag(0)
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
                    subjectName = subjects.first?.name ?? ""
                }
            }
        }
    }

    private func save() async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        error = nil
        do {
            let grade = Double(gradeText) ?? 0
            let weight = Double(weightText) ?? 1
            let halfYear: Int? = (halfYearSelection == 0) ? nil : halfYearSelection
            _ = try await store.addGradeToFirestore(subjectId: subjectName, grade: grade, weight: weight, date: date, note: note.isEmpty ? nil : note, halfYear: halfYear, using: key)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
