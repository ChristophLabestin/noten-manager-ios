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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
    }

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
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
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Hausaufgabe",
                        subtitle: "Fach, Aufgabe und Fälligkeit",
                        systemImage: "checklist",
                        accent: .cyan
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Fach")
                                        .font(.headline)
                                    Picker("Fach", selection: $subjectName) {
                                        ForEach(subjectOptions, id: \.self) { name in
                                            Text(name).tag(name)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.primary)
                                    .padding(10)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Gruppe")
                                                    .font(.subheadline)
                                                Picker("Gruppe", selection: Binding(
                                                    get: { selectedGroupId ?? store.groupIds.first ?? "" },
                                                    set: { selectedGroupId = $0 }
                                                )) {
                                                    ForEach(store.groupIds, id: \.self) { gid in
                                                        Text(store.groupNames[gid] ?? gid).tag(gid)
                                                    }
                                                }
                                                .pickerStyle(.menu)
                                                .padding(10)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                        }
                                    }
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Aufgabe")
                                            .font(.headline)
                                        TextEditor(text: $title)
                                            .frame(minHeight: 90)
                                            .textInputAutocapitalization(.sentences)
                                            .scrollContentBackground(.hidden)
                                            .focused($focusedField, equals: .title)
                                            .padding(10)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    Toggle("Fälligkeitsdatum verwenden", isOn: $hasDueDate)
                                        .tint(.cyan)

                                    if hasDueDate {
                                        DatePicker(
                                            "Fällig am",
                                            selection: $dueDate,
                                            displayedComponents: .date
                                        )
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Erinnerung & Teilen",
                        subtitle: "Benachrichtigungen für die Aufgabe",
                        systemImage: "bell.badge.fill",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Erinnerung planen", isOn: $hasReminder)
                                    .tint(.orange)

                                if hasReminder {
                                    DatePicker(
                                        "Erinnerung",
                                        selection: $reminderDate,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                }

                                if !store.groupIds.isEmpty && subjectName != "Allgemein" {
                                    Toggle("Mit Gruppen teilen", isOn: $shareWithGroup)
                                        .tint(.orange)
                                    Text("Geteilte Aufgaben erscheinen bei allen Gruppenmitgliedern.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))
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
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardNavigationAccessory(
                        focus: $focusedField,
                        fields: [.title],
                        label: nil,
                        onDone: { hideKeyboard() }
                    )
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
        .modifier(KeyboardToolbarInset(height: 64))
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
