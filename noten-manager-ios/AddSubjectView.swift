import SwiftUI

struct AddSubjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var name: String = ""
    @State private var type: Int = 1 // 1 = Hauptfach, 0 = Nebenfach
    @State private var date: Date = Date()
    @State private var isSaving: Bool = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Fach") {
                    TextField("Name", text: $name)
                    Picker("Typ", selection: $type) {
                        Text("Hauptfach").tag(1)
                        Text("Nebenfach").tag(0)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Fach anlegen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Speichern") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        do {
            try await store.addSubjectToFirestore(name: name.trimmingCharacters(in: .whitespacesAndNewlines), type: type, date: date)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
