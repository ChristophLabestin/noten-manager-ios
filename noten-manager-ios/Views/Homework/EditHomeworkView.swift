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
    @State private var personalNote: String = ""
    @State private var isSharing: Bool = false
    @State private var isUnsharing: Bool = false
    @State private var shareInfo: String?
    @State private var shareError: String?
    @State private var shareLinkURL: URL?
    @State private var showShareSheet: Bool = false
    @State private var shareLinkError: String?

    @State private var isShared: Bool = false
    @State private var sharedId: String? = nil
    @State private var selectedGroupIds: Set<String> = []
    @State private var selectedClassIds: Set<String> = []
    @State private var selectedCourseIds: Set<String> = []
    @State private var autoSelectedGroupIds: Set<String> = []
    @State private var autoSelectedCourseIds: Set<String> = []
    @State private var shareWithGroup: Bool = false
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

    private let noSubjectLabel = "Kein Fach"
    @State private var loadedNote: Bool = false

    init(homework: Homework) {
        self.homework = homework
        let initialSubject = homework.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? noSubjectLabel : homework.subjectName
        _subjectName = State(initialValue: initialSubject)
        _title = State(initialValue: homework.title)
        let initialDue = homework.dueDate ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _hasDueDate = State(initialValue: homework.dueDate != nil)
        _dueDate = State(initialValue: initialDue)
        let initialReminder = homework.reminderAt ?? Date().addingTimeInterval(60 * 60)
        _hasReminder = State(initialValue: homework.reminderAt != nil)
        _reminderDate = State(initialValue: initialReminder)
        _isCompleted = State(initialValue: homework.isCompleted)
        _personalNote = State(initialValue: "")
        _loadedNote = State(initialValue: false)
        // isShared stays false by default, no model field to set from
    }

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var subjectOptions: [String] {
        var list = subjects.map { $0.name }
        if !list.contains(noSubjectLabel) {
            list.insert(noSubjectLabel, at: 0)
        }
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

    private var sheetTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Hausaufgabe bearbeiten" : trimmed
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

                    SettingsCard(
                        title: "Per Link teilen",
                        subtitle: "An Freund:innen senden, auch ohne Gruppe",
                        systemImage: "link",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                shareLinkError = nil
                                guard let url = HomeworkShareLinkBuilder.url(for: homework) else {
                                    shareLinkError = "Link konnte nicht erstellt werden."
                                    return
                                }
                                shareLinkURL = url
                                showShareSheet = true
                            } label: {
                                Label("Link erstellen & teilen", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                            .disabled(isSaving || isDeleting)

                            if let shareLinkURL {
                                Text(shareLinkURL.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            if let shareLinkError {
                                Text(shareLinkError)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
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
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Persönliche Notiz")
                                        .font(.headline)
                                    TextEditor(text: $personalNote)
                                        .frame(minHeight: 100)
                                        .scrollContentBackground(.hidden)
                                        .padding(10)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text("Nur für dich sichtbar, wird mit der Aufgabe gespeichert.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !homework.isShared && (!store.classIds.isEmpty || !store.courses.isEmpty) {
                        let availableCourses: [Course] = {
                            let targetIds = Set(store.targetCourseIds(forLocalSubject: subjectName))
                            let matches = store.courses.filter { targetIds.contains($0.id) }
                            return Array(Dictionary(grouping: matches, by: { $0.id }).values.compactMap(\.first))
                        }()
                        
                        ShareTargetSelector(
                            shareWithGroup: $shareWithGroup,
                            selectedGroupIds: $selectedGroupIds,
                            selectedClassIds: $selectedClassIds,
                            selectedCourseIds: $selectedCourseIds,
                            availableCourses: availableCourses,
                            autoSelectedGroupIds: autoSelectedGroupIds,
                            autoSelectedCourseIds: autoSelectedCourseIds
                        )
                        
                        if shareWithGroup {
                            SettingsSectionBox {
                                Button {
                                    Task { await shareToGroups() }
                                } label: {
                                    if isSharing {
                                        ProgressView()
                                    } else {
                                        Text("Teilen")
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .blue))
                                .disabled(isSharing || (selectedClassIds.isEmpty && selectedCourseIds.isEmpty))
                            }
                            .padding(.top, -8)
                        }

                        if let shareInfo {
                            Text(shareInfo)
                                .font(.footnote)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 16)
                        }
                        if let shareError {
                            Text(shareError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
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
                                .buttonStyle(SoftTintButtonStyle(accent: .red))
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
                    .buttonStyle(SoftTintButtonStyle(accent: .red))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity).onTapGesture { hideKeyboard() })
            .sheetNavigationTitle(sheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ToolbarLoadingIcon()
                        } else {
                            ToolbarIcon(symbol: "checkmark", showDot: false)
                        }
                    }
                    .accessibilityLabel("Speichern")
                    .disabled(!canSave || isSaving || subjects.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissToolbar()
            .sheet(isPresented: $showShareSheet) {
                if let shareLinkURL {
                    ShareSheet(activityItems: [shareLinkURL])
                } else {
                    Text("Kein Link verfügbar")
                }
            }
            .onAppear {
                if !loadedNote && homework.isShared {
                    personalNote = store.userNoteForHomework(homework) ?? ""
                    loadedNote = true
                }
                updateSelectedGroupsForSubject(subjectName)
                if homework.groupId != nil {
                    shareWithGroup = true
                } else {
                    shareWithGroup = (!selectedClassIds.isEmpty || !selectedCourseIds.isEmpty) && !homework.isShared
                }
            }
            .onChange(of: subjectName) { _, newSubject in
                updateSelectedGroupsForSubject(newSubject)
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
                await store.setUserNoteForSharedHomework(homeworkId: homework.id, note: personalNote, groupId: gid)
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
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func shareToGroups() async {
        guard !isSharing else { return }
        shareError = nil
        shareInfo = nil
        isSharing = true
        
        var createdAny = false
        
        // 1. Share to Courses
        for courseId in selectedCourseIds {
            do {
                _ = try await store.addHomeworkToCourse(
                    courseId: courseId,
                    title: title,
                    dueDate: hasDueDate ? dueDate : nil,
                    reminderAt: hasReminder ? reminderDate : nil
                )
                createdAny = true
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
            }
        }
        
        await MainActor.run {
            isSharing = false
            if createdAny {
                shareInfo = "Geteilt."
                dismiss()
            } else {
                shareError = "Teilen fehlgeschlagen."
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

    private func updateSelectedGroupsForSubject(_ subject: String) {
        // 1. Remove previously auto-selected courses
        selectedCourseIds.subtract(autoSelectedCourseIds)
        autoSelectedCourseIds.removeAll()
        
        // 2. If subject is valid, find new matches
        if subject != noSubjectLabel && !subject.isEmpty {
            let matchedCourses = Set(store.targetCourseIds(forLocalSubject: subject))
            if !matchedCourses.isEmpty {
                selectedCourseIds.formUnion(matchedCourses)
                autoSelectedCourseIds = matchedCourses
            }
        }
    }
}
