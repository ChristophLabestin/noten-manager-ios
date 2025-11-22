import SwiftUI

struct AddSubjectView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var name: String = ""
    @State private var type: Int = 1 // 1 = Hauptfach, 0 = Nebenfach
    // Datum hat keine Funktion in der App, daher weggelassen
    @State private var isElective: Bool = false
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
                    .disabled(isElective)
                    Toggle("Wahlfach / nicht einbringbar", isOn: $isElective)
                        .onChange(of: isElective) { newVal in
                            if newVal { type = 0 }
                        }
                    Text("Wahlfächer fließen nicht in die Abschlussnote ein. Für Sport/Musik bitte als Wahlfach markieren.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if ["sport", "musik"].contains(lower) && !isElective {
                error = "Bitte markiere Sport oder Musik als nicht einbringbar (Wahlfach)."
                isSaving = false
                return
            }
            try await store.addSubjectToFirestore(
                name: trimmed,
                type: type,
                date: Date(),
                isElective: isElective
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
