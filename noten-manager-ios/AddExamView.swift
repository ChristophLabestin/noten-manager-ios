import SwiftUI

struct AddExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let preselectedSubjectName: String?

    @State private var subjectName: String = ""
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var examWeight: Int = 0
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var shareWithGroup: Bool = false

    private var subjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !subjectName.isEmpty
    }

    init(preselectedSubjectName: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Klausurtermin") {
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

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Titel / Bezeichnung")
                            .font(.subheadline.weight(.semibold))
                        TextField("z. B. Kurzarbeit Mathematik", text: $title)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

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

                    if !store.groupIds.isEmpty {
                        Toggle("Mit Gruppen teilen", isOn: $shareWithGroup)
                    }

                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Klausur hinzufügen")
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
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .onAppear {
                if subjectName.isEmpty {
                    if let pre = preselectedSubjectName,
                       subjects.contains(where: { $0.name == pre }) {
                        subjectName = pre
                    } else {
                        subjectName = subjects.first?.name ?? ""
                    }
                }
                shareWithGroup = !store.groupIds.isEmpty
            }
        }
        .keyboardDismissToolbar()
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
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
            let reminder: Date? = hasReminder ? reminderDate : nil
            let requiresGrade = true
            if shareWithGroup {
                let sharedIds = try await store.addExamToGroups(
                    subjectName: subjectName,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder,
                    requiresGrade: requiresGrade
                )
                if sharedIds.isEmpty {
                    try await store.addExamToFirestore(
                        subjectName: subjectName,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: date,
                        weight: examWeight,
                        reminderAt: reminder,
                        requiresGrade: requiresGrade
                    )
                } else if let reminder {
                    for item in sharedIds {
                        try await store.setUserReminderForSharedExam(examId: item.docId, reminderAt: reminder, groupId: item.groupId)
                    }
                }
            } else {
                try await store.addExamToFirestore(
                    subjectName: subjectName,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder,
                    requiresGrade: requiresGrade
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
