import SwiftUI

struct AddHomeworkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let preselectedSubjectName: String?

    @State private var subjectName: String = ""
    @State private var title: String = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var isSaving: Bool = false
    @State private var error: String?

    private var subjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !subjectName.isEmpty else { return false }
        if hasDueDate {
            return true
        }
        return true
    }

    init(preselectedSubjectName: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hausaufgabe") {
                    Picker("Fach", selection: $subjectName) {
                        ForEach(subjects, id: \.name) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    if subjects.isEmpty {
                        Text("Lege zuerst ein Fach an, um Hausaufgaben zuzuordnen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aufgabe")
                        TextEditor(text: $title)
                            .frame(minHeight: 80)
                            .textInputAutocapitalization(.sentences)
                    }

                    Toggle("Fälligkeitsdatum verwenden", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker(
                            "Fällig am",
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                    }

                    Toggle("Erinnerung planen", isOn: $hasReminder)

                    if hasReminder {
                        DatePicker(
                            "Erinnerung",
                            selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Hausaufgabe hinzufügen")
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
                    .disabled(!canSave || isSaving || subjects.isEmpty)
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
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            error = "Bitte einen Titel für die Hausaufgabe eingeben."
            isSaving = false
            return
        }
        do {
            let due: Date? = hasDueDate ? dueDate : nil
            try await store.addHomeworkToFirestore(
                subjectName: subjectName,
                title: trimmedTitle,
                dueDate: due,
                reminderAt: hasReminder ? reminderDate : nil
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
