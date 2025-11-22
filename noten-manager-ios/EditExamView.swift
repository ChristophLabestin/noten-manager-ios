import SwiftUI
import FirebaseAuth

struct EditExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let exam: Exam

    @State private var subjectName: String
    @State private var title: String
    @State private var notes: String
    @State private var date: Date
    @State private var examWeight: Int
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isCompleted: Bool
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var requiresGrade: Bool
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false

    init(exam: Exam) {
        self.exam = exam
        _subjectName = State(initialValue: exam.subjectName)
        _title = State(initialValue: exam.title)
        _notes = State(initialValue: exam.notes ?? "")
        _date = State(initialValue: exam.date)
        _examWeight = State(initialValue: exam.weight ?? 0)
        let initialReminder = exam.reminderAt ?? Date().addingTimeInterval(60 * 60)
        _hasReminder = State(initialValue: exam.reminderAt != nil)
        _reminderDate = State(initialValue: initialReminder)
        _isCompleted = State(initialValue: exam.isCompleted)
        _requiresGrade = State(initialValue: exam.requiresGrade ?? true)
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

                TextField("Titel / Bezeichnung", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notizen (optional)")
                    TextEditor(text: $notes)
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

                    Toggle("Note verknüpfen erforderlich", isOn: $requiresGrade)

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
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Klausur löschen")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                .background(.thinMaterial)
            }
            .alert(
                "Klausur löschen?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Abbrechen", role: .cancel) { showDeleteConfirm = false }
                Button("Löschen", role: .destructive) {
                    Task { await deleteExam() }
                }
            } message: {
                Text("Dieser Klausurtermin wird dauerhaft gelöscht.")
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
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        do {
            let reminder: Date? = hasReminder ? reminderDate : nil
            if exam.isShared {
                guard let gid = exam.groupId else {
                    error = "Keine Gruppe für diese Klausur gefunden."
                    isSaving = false
                    return
                }
                try await store.updateSharedExamInGroup(
                    groupId: gid,
                    id: exam.id,
                    subjectName: subjectName,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder
                )
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminder, groupId: gid)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: subjectName,
                    title: trimmedTitle,
                    notes: storedNotes,
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

    private func deleteExam() async {
        guard !isDeleting else { return }
        isDeleting = true
        if exam.isShared, let gid = exam.groupId {
            await store.deleteSharedExamFromGroup(groupId: gid, id: exam.id)
        } else {
            await store.deleteExamFromFirestore(id: exam.id)
        }
        await MainActor.run {
            showDeleteConfirm = false
            dismiss()
        }
        isDeleting = false
    }
}
