import SwiftUI
import FirebaseAuth

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
    @State private var isDeleting: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var error: String?
    @State private var showPersonalNoteEditor: Bool = false
    @State private var isSharing: Bool = false
    @State private var isUnsharing: Bool = false
    @State private var shareInfo: String?
    @State private var shareError: String?

    @State private var isShared: Bool = false
    @State private var sharedId: String? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isSharedOwner: Bool {
        homework.isShared && homework.creatorId == currentUserId
    }

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
        // isShared stays false by default, no model field to set from
    }

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var subjectOptions: [String] {
        var list = subjects.map { $0.name }
        if !list.contains("Allgemein") {
            list.insert("Allgemein", at: 0)
        }
        if !list.contains(subjectName) && !subjectName.isEmpty {
            list.append(subjectName)
        }
        return list
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !subjectName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Hausaufgabe bearbeiten",
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
                        title: "Erinnerung & Status",
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

                                if store.homeworkGroupId != nil {
                                    Text("Wenn diese Aufgabe aus der Gruppe stammt, wird nur deine persönliche Erinnerung gespeichert.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Toggle("Als erledigt markieren", isOn: $isCompleted)
                                        .tint(.green)
                                }
                            }
                        }
                    }

                    if homework.isShared {
                        SettingsCard(
                            title: "Eigene Notiz",
                            subtitle: "Nur für dich sichtbar",
                            systemImage: "note.text",
                            accent: .teal
                        ) {
                            let currentNote = store.userNoteForHomework(homework) ?? ""
                            VStack(alignment: .leading, spacing: 10) {
                                if currentNote.isEmpty {
                                    Text("Keine Notiz gespeichert.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(currentNote)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(4)
                                }
                                Button("Eigene Notiz bearbeiten") {
                                    showPersonalNoteEditor = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    if !homework.isShared && !store.groupIds.isEmpty {
                        SettingsCard(
                            title: "Mit Gruppe teilen",
                            subtitle: "Aufgabe nachträglich veröffentlichen",
                            systemImage: "person.3.fill",
                            accent: .blue
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    Task { await shareToGroups() }
                                } label: {
                                    if isSharing {
                                        ProgressView()
                                    } else {
                                        Text("In Gruppe teilen")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSharing)

                                if let shareInfo {
                                    Text(shareInfo)
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                }
                                if let shareError {
                                    Text(shareError)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    if homework.isShared, isSharedOwner, let gid = homework.groupId {
                        SettingsCard(
                            title: "Teilen beenden",
                            subtitle: "Nur der Ersteller kann das Teilen stoppen",
                            systemImage: "xmark.circle",
                            accent: .red
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                Button(role: .destructive) {
                                    Task { await stopSharing(groupId: gid) }
                                } label: {
                                    if isUnsharing {
                                        ProgressView()
                                    } else {
                                        Text("Aus Gruppe entfernen")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .disabled(isUnsharing)

                                if let shareInfo {
                                    Text(shareInfo)
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                }
                                if let shareError {
                                    Text(shareError)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
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

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                        } else {
                            Text("Hausaufgabe löschen")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))
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
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .keyboardNavigationToolbar(
                focus: $focusedField,
                fields: [.title],
                label: nil,
                onDone: { hideKeyboard() }
            )
            .sheet(isPresented: $showPersonalNoteEditor) {
                PersonalNoteEditor(
                    title: "Eigene Notiz",
                    initialText: store.userNoteForHomework(homework) ?? "",
                    onSave: { text in
                        Task { await store.setUserNoteForSharedHomework(homeworkId: homework.id, note: text, groupId: homework.groupId) }
                    }
                )
            }
            .alert(
                "Hausaufgabe löschen?",
                isPresented: $showDeleteConfirm
            ) {
                Button("Abbrechen", role: .cancel) { showDeleteConfirm = false }
                Button("Löschen", role: .destructive) {
                    Task { await deleteHomework() }
                }
            } message: {
                Text("Diese Hausaufgabe wird dauerhaft gelöscht.")
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
            if homework.isShared, let gid = homework.groupId {
                try await store.updateSharedHomeworkInGroup(
                    groupId: gid,
                    id: homework.id,
                    subjectName: subjectName,
                    title: trimmedTitle,
                    dueDate: due
                )
                if hasReminder {
                    try await store.setUserReminderForSharedHomework(homeworkId: homework.id, reminderAt: reminder, groupId: gid)
                }
            } else {
                try await store.updateHomeworkInFirestore(
                    id: homework.id,
                    subjectName: subjectName,
                    title: trimmedTitle,
                    dueDate: due,
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

    private func shareToGroups() async {
        guard !isSharing else { return }
        shareError = nil
        shareInfo = nil
        isSharing = true
        let success = await store.shareHomeworkToGroups(homeworkId: homework.id)
        await MainActor.run {
            isSharing = false
            if success {
                shareInfo = "In Gruppe geteilt."
                dismiss()
            } else {
                shareError = "Teilen fehlgeschlagen. Prüfe Gruppen und versuche es erneut."
            }
        }
    }

    private func stopSharing(groupId: String) async {
        guard !isUnsharing else { return }
        shareError = nil
        shareInfo = nil
        isUnsharing = true
        let success = await store.stopSharingHomework(groupId: groupId, homeworkId: homework.id)
        await MainActor.run {
            isUnsharing = false
            if success {
                shareInfo = "Teilen beendet."
                dismiss()
            } else {
                shareError = "Konnte Teilen nicht beenden."
            }
        }
    }

    private func deleteHomework() async {
        guard !isDeleting else { return }
        isDeleting = true
        do {
            if homework.isShared, let gid = homework.groupId {
                await store.deleteSharedHomeworkFromGroup(groupId: gid, id: homework.id)
            } else {
                await store.deleteHomeworkFromFirestore(id: homework.id)
            }
            await MainActor.run {
                showDeleteConfirm = false
                dismiss()
            }
        }
        isDeleting = false
    }
}
