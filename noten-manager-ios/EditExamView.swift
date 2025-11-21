import SwiftUI
import FirebaseAuth

struct EditExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let exam: Exam

    @State private var subjectName: String
    @State private var title: String
    @State private var date: Date
    @State private var examWeight: Int
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isCompleted: Bool
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(exam: Exam) {
        self.exam = exam
        _subjectName = State(initialValue: exam.subjectName)
        _title = State(initialValue: exam.title)
        _date = State(initialValue: exam.date)
        _examWeight = State(initialValue: exam.weight ?? 0)
        let initialReminder = exam.reminderAt ?? Date().addingTimeInterval(60 * 60)
        _hasReminder = State(initialValue: exam.reminderAt != nil)
        _reminderDate = State(initialValue: initialReminder)
        _isCompleted = State(initialValue: exam.isCompleted)
    }

    private var subjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !subjectName.isEmpty
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isSharedOwner: Bool {
        exam.isShared && exam.creatorId == currentUserId
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Klausur bearbeiten") {
                    Picker("Fach", selection: $subjectName) {
                        ForEach(subjects, id: \.name) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    if subjects.isEmpty {
                        Text("Lege zuerst ein Fach an, um Klausuren zuzuordnen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notiz")
                    TextEditor(text: $title)
                        .frame(minHeight: 80)
                        .textInputAutocapitalization(.sentences)
                }

                let subjectType = subjects.first(where: { $0.name == subjectName })?.type ?? 0
                Picker("Art", selection: $examWeight) {
                    if subjectType == 0 {
                        Text("Kurzarbeit").tag(1)
                        Text("Mündlich / EX").tag(0)
                    } else {
                        Text("Schulaufgabe").tag(2)
                        Text("Kurzarbeit").tag(1)
                        Text("Mündlich / EX").tag(0)
                    }
                }

                    DatePicker(
                        "Datum & Uhrzeit",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    Toggle("Zusätzliche Erinnerung planen", isOn: $hasReminder)

                    if hasReminder {
                        DatePicker(
                            "Erinnerung",
                            selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }

                    if !exam.isShared {
                        Toggle("Als erledigt markieren", isOn: $isCompleted)
                            .tint(.green)
                    }
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Klausur bearbeiten")
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
            error = "Bitte einen Titel für die Klausur eingeben."
            isSaving = false
            return
        }
        do {
            let reminder: Date? = hasReminder ? reminderDate : nil
            if exam.isShared {
                try await store.updateSharedExamInGroup(
                    id: exam.id,
                    subjectName: subjectName,
                    title: trimmedTitle,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder
                )
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminder)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: subjectName,
                    title: trimmedTitle,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder,
                    isCompleted: isCompleted
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
