import SwiftUI

struct HomeworkReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let homework: Homework

    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(homework: Homework) {
        self.homework = homework
        _hasReminder = State(initialValue: homework.reminderAt != nil)
        _reminderDate = State(initialValue: homework.reminderAt ?? Date().addingTimeInterval(60 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Erinnerung für Hausaufgabe") {
                    Toggle("Zusätzliche Erinnerung aktivieren", isOn: $hasReminder)

                    if hasReminder {
                        DatePicker(
                            "Erinnerungszeitpunkt",
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
            .navigationTitle("Erinnerung festlegen")
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
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        let reminderAt: Date? = hasReminder ? reminderDate : nil
        do {
            if homework.isShared {
                try await store.setUserReminderForSharedHomework(homeworkId: homework.id, reminderAt: reminderAt)
            } else {
                try await store.updateHomeworkInFirestore(
                    id: homework.id,
                    subjectName: homework.subjectName,
                    title: homework.title,
                    dueDate: homework.dueDate,
                    reminderAt: reminderAt,
                    isCompleted: homework.isCompleted
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
