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
    @State private var shareWithGroup: Bool = false
    @State private var selectedGroupId: String?

    private var subjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var subjectOptions: [String] {
        ["Allgemein"] + subjects.map { $0.name }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !subjectName.isEmpty else { return false }
        if subjectName == "Allgemein" {
            return selectedGroupId != nil
        }
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
                        ForEach(subjectOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if subjects.isEmpty {
                        Text("Lege zuerst ein Fach an, um Hausaufgaben zuzuordnen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if subjectName == "Allgemein" {
                        if store.groupIds.isEmpty {
                            Text("Du bist in keiner Gruppe. Tritt einer Gruppe bei, um allgemeine Hausaufgaben anzulegen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Gruppe", selection: Binding(
                                get: { selectedGroupId ?? store.groupIds.first ?? "" },
                                set: { selectedGroupId = $0 }
                            )) {
                                ForEach(store.groupIds, id: \.self) { gid in
                                    Text(store.groupNames[gid] ?? gid).tag(gid)
                                }
                            }
                        }
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

                    if !store.groupIds.isEmpty && subjectName != "Allgemein" {
                        Toggle("Mit Gruppen teilen", isOn: $shareWithGroup)
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
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .onAppear {
                if subjectName.isEmpty {
                    if let pre = preselectedSubjectName,
                       subjects.contains(where: { $0.name == pre }) {
                        subjectName = pre
                    } else if let first = subjects.first?.name {
                        subjectName = first
                    } else {
                        subjectName = subjectOptions.first ?? ""
                    }
                }
                shareWithGroup = !store.groupIds.isEmpty
                selectedGroupId = store.groupIds.first
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
            error = "Bitte einen Titel für die Hausaufgabe eingeben."
            isSaving = false
            return
        }
        do {
            let due: Date? = hasDueDate ? dueDate : nil
            let reminder: Date? = hasReminder ? reminderDate : nil
            if subjectName == "Allgemein" {
                guard let gid = selectedGroupId ?? store.groupIds.first else {
                    error = "Bitte wähle eine Gruppe."
                    isSaving = false
                    return
                }
                let docId = try await store.addGeneralHomeworkToGroup(groupId: gid, title: trimmedTitle, dueDate: due, reminderAt: reminder)
                if let reminder {
                    try await store.setUserReminderForSharedHomework(homeworkId: docId, reminderAt: reminder, groupId: gid)
                }
            } else if shareWithGroup {
                let sharedIds = try await store.addHomeworkToGroups(subjectName: subjectName, title: trimmedTitle, dueDate: due, reminderAt: reminder)
                if sharedIds.isEmpty {
                    try await store.addHomeworkToFirestore(subjectName: subjectName, title: trimmedTitle, dueDate: due, reminderAt: reminder)
                } else if let reminder {
                    // Reminder nur für die angelegten geteilten Einträge setzen
                    for item in sharedIds {
                        try await store.setUserReminderForSharedHomework(homeworkId: item.docId, reminderAt: reminder, groupId: item.groupId)
                    }
                }
            } else {
                try await store.addHomeworkToFirestore(subjectName: subjectName, title: trimmedTitle, dueDate: due, reminderAt: reminder)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
