import SwiftUI

struct EditHomeworkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let homework: Homework

    @State private var subjectName: String
    @State private var title: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isCompleted: Bool
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(homework: Homework) {
        self.homework = homework
        _subjectName = State(initialValue: homework.subjectName)
        _title = State(initialValue: homework.title)
        let initialDue = homework.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _hasDueDate = State(initialValue: homework.dueDate != nil)
        _dueDate = State(initialValue: initialDue)
        let initialReminder = homework.reminderAt ?? Date().addingTimeInterval(60 * 60)
        _hasReminder = State(initialValue: homework.reminderAt != nil)
        _reminderDate = State(initialValue: initialReminder)
        _isCompleted = State(initialValue: homework.isCompleted)
    }

    private var subjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !subjectName.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Hausaufgabe bearbeiten") {
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

                    Toggle("Als erledigt markieren", isOn: $isCompleted)
                        .tint(.green)
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Hausaufgabe bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
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
            let reminder: Date? = hasReminder ? reminderDate : nil
            try await store.updateHomeworkInFirestore(
                id: homework.id,
                subjectName: subjectName,
                title: trimmedTitle,
                dueDate: due,
                reminderAt: reminder,
                isCompleted: isCompleted
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
