import SwiftUI

struct ExamReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let exam: Exam

    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(exam: Exam) {
        self.exam = exam
        _hasReminder = State(initialValue: exam.reminderAt != nil)
        _reminderDate = State(initialValue: exam.reminderAt ?? Date().addingTimeInterval(60 * 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Erinnerung für Klausur") {
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
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        do {
            let reminderAt: Date? = hasReminder ? reminderDate : nil
            if exam.isShared {
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminderAt)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    title: exam.title,
                    notes: exam.notes,
                    date: exam.date,
                    weight: exam.weight,
                    reminderAt: reminderAt,
                    isCompleted: exam.isCompleted
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
