import SwiftUI

struct AddHomeworkPrefill {
    let subjectName: String?
    let title: String?
    let dueDate: Date?
}

struct AddHomeworkView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let preselectedSubjectName: String?
    let prefill: AddHomeworkPrefill?

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

    private let noSubjectLabel = "Kein Fach"

    private var prefilledSubject: String? {
        prefill?.subjectName?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var subjectOptions: [String] {
        var options = [noSubjectLabel] + subjects.map { $0.name }
        if let prefilledSubject, !options.contains(prefilledSubject) {
            options.append(prefilledSubject)
        }
        return options
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !subjectName.isEmpty else { return false }
        if hasDueDate {
            return true
        }
        return true
    }

    init(preselectedSubjectName: String? = nil, prefill: AddHomeworkPrefill? = nil) {
        self.prefill = prefill
        let defaultDueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _subjectName = State(initialValue: prefill?.subjectName ?? "")
        _title = State(initialValue: prefill?.title ?? "")
        _hasDueDate = State(initialValue: prefill?.dueDate != nil)
        _dueDate = State(initialValue: prefill?.dueDate ?? defaultDueDate)
        self.preselectedSubjectName = preselectedSubjectName ?? prefill?.subjectName
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if prefill != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "link.badge.plus")
                                .foregroundStyle(.blue)
                            Text("Daten aus geteiltem Link übernommen.")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

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
                                    Text("Gruppen-Aufgaben erscheinen bei allen Gruppenmitgliedern.")
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
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle("Hausaufgabe")
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
            .keyboardNavigationToolbar(
                focus: $focusedField,
                fields: [.title],
                label: nil,
                onDone: { hideKeyboard() }
            )
            .onAppear {
                applyInitialSubjectSelection()
                shareWithGroup = !store.groupIds.isEmpty
                selectedGroupId = store.groupIds.first
            }
            .onChange(of: store.subjects) {
                applyInitialSubjectSelection()
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
            if shareWithGroup {
                let sharedIds = try await store.addHomeworkToGroups(subjectName: subjectName, title: trimmedTitle, dueDate: due, reminderAt: reminder)
                if sharedIds.isEmpty {
                    try await store.addHomeworkToFirestore(
                        subjectName: subjectName,
                        title: trimmedTitle,
                        dueDate: due,
                        reminderAt: reminder,
                        importedFromShare: prefill != nil
                    )
                } else if let reminder {
                    // Reminder nur für die angelegten geteilten Einträge setzen
                    for item in sharedIds {
                        try await store.setUserReminderForSharedHomework(homeworkId: item.docId, reminderAt: reminder, groupId: item.groupId)
                    }
                }
            } else {
                try await store.addHomeworkToFirestore(
                    subjectName: subjectName,
                    title: trimmedTitle,
                    dueDate: due,
                    reminderAt: reminder,
                    importedFromShare: prefill != nil
                )
            }
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func applyInitialSubjectSelection() {
        // Falls das vorbefüllte Fach nicht existiert, auf "Kein Fach" setzen
        if let prefilledSubject,
           !subjects.contains(where: { $0.name == prefilledSubject }),
           !prefilledSubject.isEmpty {
            subjectName = noSubjectLabel
            return
        }

        if subjectName.isEmpty {
            if let pre = preselectedSubjectName,
               subjects.contains(where: { $0.name == pre }) {
                subjectName = pre
            } else if let prefilledSubject,
                      subjects.contains(where: { $0.name == prefilledSubject }) {
                subjectName = prefilledSubject
            } else if let first = subjects.first?.name {
                subjectName = first
            } else {
                subjectName = noSubjectLabel
            }
        }
    }
}
