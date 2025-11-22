import SwiftUI
import CryptoKit

struct AddFachreferatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    // Optional vorselektiertes Fach (z. B. von SubjectDetail)
    let preselectedSubjectName: String?

    @State private var subjectName: String = ""
    @State private var gradeText: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var error: String?

    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard Double(gradeText) != nil else { return false }
        return true
    }

    init(preselectedSubjectName: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fachreferat") {
                    Picker("Fach", selection: $subjectName) {
                        ForEach(store.subjects.filter { $0.name != "Fachreferat" }, id: \.name) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    TextField("Note (z. B. 10.0)", text: $gradeText)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    TextField("Notiz (optional)", text: $note)
                        .submitLabel(.done)
                        .onSubmit { hideKeyboard() }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle(store.fachreferat == nil ? "Fachreferat" : "Fachreferat bearbeiten")
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
                       store.subjects.contains(where: { $0.name == pre && $0.name != "Fachreferat" }) {
                        subjectName = pre
                    } else {
                        subjectName = store.fachreferat?.subjectName
                            ?? store.subjects.first(where: { $0.name != "Fachreferat" })?.name
                            ?? ""
                    }
                }
                if let fr = store.fachreferat {
                    gradeText = String(fr.grade)
                    date = fr.date
                    note = fr.note ?? ""
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
            let grade = Double(gradeText) ?? 0
            try await store.setFachreferatToFirestore(subjectName: subjectName, grade: grade, date: date, note: note.isEmpty ? nil : note, using: key)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
