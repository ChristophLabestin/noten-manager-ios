import SwiftUI

private enum EditableGroupType {
    case branch
    case wahlpflicht
}

private struct EditableSubject: Identifiable, Hashable {
    let id: String
    var name: String
    var hasSchulaufgabe: Bool
    var courseId: String?
}

private struct EditableGroup: Identifiable {
    let id: String
    var name: String
    var originalName: String?
    var subjects: [EditableSubject]
    var newSubject: String
    var type: EditableGroupType
    var groupId: String?
    var isNew: Bool
}

struct ClassEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let classId: String

    @State private var className: String = ""
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var classCourses: [Course] = []
    @State private var commonSubjects: [EditableSubject] = []
    @State private var electiveSubjects: [EditableSubject] = []
    @State private var branchGroups: [EditableGroup] = []
    @State private var wahlpflichtGroups: [EditableGroup] = []

    @State private var newCommonSubject: String = ""
    @State private var isLoadingCourses = true

    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }

    private var schoolClass: SchoolClass? {
        store.classDetails[classId]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)

                        Text("Klasse bearbeiten")
                            .font(.title3.weight(.bold))

                        Text("Passe Fächer, Zweige und Wahlpflichtfächer an.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)

                    // Name
                    SettingsCard(
                        title: "Klassenname",
                        subtitle: "Z.B. '10b' oder 'Mathe LK'",
                        systemImage: "pencil",
                        accent: .indigo
                    ) {
                        TextField("Name", text: $className)
                            .font(.title3)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }

                    // Common Subjects
                    SettingsCard(
                        title: "Gemeinsame Fächer",
                        subtitle: "Fächer, die jeder in der Klasse hat",
                        systemImage: "book.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if commonSubjects.isEmpty {
                                Text("Keine gemeinsamen Fächer vorhanden.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach($commonSubjects) { $subject in
                                        SubjectCreationRow(
                                            name: subject.name,
                                            hasSA: Binding(
                                                get: { subject.hasSchulaufgabe },
                                                set: { newValue in
                                                    subject.hasSchulaufgabe = newValue
                                                    Task { await updateSubjectGradingMode(subject: subject) }
                                                }
                                            ),
                                            onDelete: {
                                                Task { await deleteSubject(subject: subject, groupType: nil, groupId: nil) }
                                            }
                                        )
                                    }
                                }
                            }

                            HStack {
                                TextField("Neues Fach hinzufügen...", text: $newCommonSubject)
                                    .onSubmit { Task { await addCommonSubject() } }
                                    .submitLabel(.done)

                                Button {
                                    Task { await addCommonSubject() }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.indigo)
                                        .font(.title2)
                                }
                                .disabled(newCommonSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(10)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    // Branches
                    VStack(spacing: 16) {
                        ForEach($branchGroups) { $group in
                            EditableSubjectGroupCard(
                                group: $group,
                                titlePlaceholder: "Zweigname (z.B. Wirtschaft)",
                                subtitle: "Zweig-spezifische Fächer",
                                icon: "arrow.branch",
                                color: .orange,
                                isSaving: isSaving,
                                onRename: { groupId in
                                    Task { await renameGroup(groupId: groupId, type: .branch) }
                                },
                                onAddSubject: { groupId in
                                    Task { await addSubject(to: groupId, type: .branch) }
                                },
                                onCreateGroup: { groupId in
                                    Task { await createGroup(groupId: groupId, type: .branch) }
                                },
                                onDeleteGroup: { groupId in
                                    Task { await removeGroup(groupId: groupId, type: .branch) }
                                },
                                onDeleteSubject: { subject in
                                    Task { await deleteSubject(subject: subject, groupType: .branch, groupId: group.id) }
                                },
                                onToggleSubject: { subject, newValue in
                                    Task { await updateSubjectGradingMode(subject: subject, overrideValue: newValue) }
                                }
                            )
                        }

                        Button {
                            withAnimation {
                                branchGroups.append(
                                    EditableGroup(
                                        id: UUID().uuidString,
                                        name: "",
                                        originalName: nil,
                                        subjects: [],
                                        newSubject: "",
                                        type: .branch,
                                        groupId: nil,
                                        isNew: true
                                    )
                                )
                            }
                        } label: {
                            Label("Zweig hinzufügen (z.B. Sozial)", systemImage: "arrow.branch")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                )
                        }
                        .foregroundStyle(.primary)
                    }

                    // Wahlpflichtfächer
                    VStack(spacing: 16) {
                        ForEach($wahlpflichtGroups) { $group in
                            EditableSubjectGroupCard(
                                group: $group,
                                titlePlaceholder: "Name (z.B. Informatik)",
                                subtitle: "Fächer dieser Gruppe",
                                icon: "star.fill",
                                color: .teal,
                                isSaving: isSaving,
                                onRename: { groupId in
                                    Task { await renameGroup(groupId: groupId, type: .wahlpflicht) }
                                },
                                onAddSubject: { groupId in
                                    Task { await addSubject(to: groupId, type: .wahlpflicht) }
                                },
                                onCreateGroup: { groupId in
                                    Task { await createGroup(groupId: groupId, type: .wahlpflicht) }
                                },
                                onDeleteGroup: { groupId in
                                    Task { await removeGroup(groupId: groupId, type: .wahlpflicht) }
                                },
                                onDeleteSubject: { subject in
                                    Task { await deleteSubject(subject: subject, groupType: .wahlpflicht, groupId: group.groupId ?? group.id) }
                                },
                                onToggleSubject: { subject, newValue in
                                    Task { await updateSubjectGradingMode(subject: subject, overrideValue: newValue) }
                                }
                            )
                        }

                        Button {
                            withAnimation {
                                wahlpflichtGroups.append(
                                    EditableGroup(
                                        id: UUID().uuidString,
                                        name: "",
                                        originalName: nil,
                                        subjects: [],
                                        newSubject: "",
                                        type: .wahlpflicht,
                                        groupId: nil,
                                        isNew: true
                                    )
                                )
                            }
                        } label: {
                            Label("Wahlpflichtfach hinzufügen (z.B. IT)", systemImage: "star")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                )
                        }
                        .foregroundStyle(.primary)
                    }

                    if !electiveSubjects.isEmpty {
                        SettingsCard(
                            title: "Wahlfächer",
                            subtitle: "Zusätzliche Fächer",
                            systemImage: "star.circle.fill",
                            accent: .teal
                        ) {
                            VStack(spacing: 8) {
                                ForEach($electiveSubjects) { $subject in
                                    SubjectCreationRow(
                                        name: subject.name,
                                        hasSA: Binding(
                                            get: { subject.hasSchulaufgabe },
                                            set: { newValue in
                                                subject.hasSchulaufgabe = newValue
                                                Task { await updateSubjectGradingMode(subject: subject) }
                                            }
                                        ),
                                        color: .teal,
                                        onDelete: {
                                            Task { await deleteSubject(subject: subject, groupType: nil, groupId: nil) }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    // Danger Zone
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Gefahrenzone")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)

                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Klasse löschen", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        Task { await saveChanges() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let cls = schoolClass {
                    className = cls.name
                }
                Task { await loadCourses() }
            }
            .alert("Klasse löschen?", isPresented: $showDeleteConfirmation) {
                Button("Abbrechen", role: .cancel) { }
                Button("Löschen", role: .destructive) {
                    Task { await deleteClass() }
                }
            } message: {
                Text("Möchtest du die Klasse \"\(schoolClass?.name ?? "")\" wirklich unwiderruflich löschen? Alle assoziierten Daten werden entfernt.")
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadCourses() async {
        isLoadingCourses = true
        await store.fetchClassDetails(classId: classId)
        if let fetched = try? await store.fetchCoursesForClass(classId: classId) {
            classCourses = fetched.sorted { $0.name < $1.name }
        }
        await ensureWahlpflichtNames()
        rebuildEditState()
        isLoadingCourses = false
    }

    @MainActor
    private func refreshClassData() async {
        await store.fetchClassDetails(classId: classId)
        if let fetched = try? await store.fetchCoursesForClass(classId: classId) {
            classCourses = fetched.sorted { $0.name < $1.name }
        }
        await ensureWahlpflichtNames()
        rebuildEditState()
    }

    @MainActor
    private func ensureWahlpflichtNames() async {
        guard let linkedGroupIds = schoolClass?.linkedWahlpflichtfachGroupIds else { return }
        for groupId in linkedGroupIds {
            if store.wahlpflichtfachGroupNames[groupId] == nil {
                if let group = try? await store.fetchWahlpflichtfachGroupInfo(with: groupId) {
                    store.wahlpflichtfachGroupNames[groupId] = group.name
                    store.wahlpflichtfachGroupOwners[groupId] = group.ownerId
                }
            }
        }
    }

    @MainActor
    private func rebuildEditState() {
        let courses = classCourses
        commonSubjects = courses
            .filter { course in
                if let type = course.type, case .mandatory = type { return true }
                return false
            }
            .map { course in
                EditableSubject(
                    id: course.id,
                    name: course.name,
                    hasSchulaufgabe: (course.gradingMode ?? .withSchulaufgaben) == .withSchulaufgaben,
                    courseId: course.id
                )
            }

        electiveSubjects = courses
            .filter { course in
                if let type = course.type, case .elective = type { return true }
                return false
            }
            .map { course in
                EditableSubject(
                    id: course.id,
                    name: course.name,
                    hasSchulaufgabe: (course.gradingMode ?? .withSchulaufgaben) == .withSchulaufgaben,
                    courseId: course.id
                )
            }

        let branchNamesFromConfig = schoolClass?.config?.branches?.map { $0.name } ?? []
        let branchNamesFromCourses = Set(courses.compactMap { course -> String? in
            guard let type = course.type, case .branch(let name) = type else { return nil }
            return name
        })
        let branchNames = Array(Set(branchNamesFromConfig).union(branchNamesFromCourses)).sorted()

        branchGroups = branchNames.map { name in
            let subjects = courses
                .filter { course in
                    guard let type = course.type, case .branch(let branchName) = type else { return false }
                    return branchName == name
                }
                .map { course in
                    EditableSubject(
                        id: course.id,
                        name: course.name,
                        hasSchulaufgabe: (course.gradingMode ?? .withSchulaufgaben) == .withSchulaufgaben,
                        courseId: course.id
                    )
                }
            return EditableGroup(
                id: "branch:\(name)",
                name: name,
                originalName: name,
                subjects: subjects,
                newSubject: "",
                type: .branch,
                groupId: nil,
                isNew: false
            )
        }

        let linkedGroupIds = schoolClass?.linkedWahlpflichtfachGroupIds ?? []
        wahlpflichtGroups = linkedGroupIds.map { gid in
            let subjects = courses
                .filter { course in
                    guard let type = course.type, case .wahlpflicht(let id) = type else { return false }
                    return id == gid
                }
                .map { course in
                    EditableSubject(
                        id: course.id,
                        name: course.name,
                        hasSchulaufgabe: (course.gradingMode ?? .withSchulaufgaben) == .withSchulaufgaben,
                        courseId: course.id
                    )
                }
            let name = store.wahlpflichtfachGroupNames[gid] ?? "Wahlpflichtfach"
            return EditableGroup(
                id: "wp:\(gid)",
                name: name,
                originalName: name,
                subjects: subjects,
                newSubject: "",
                type: .wahlpflicht,
                groupId: gid,
                isNew: false
            )
        }
    }

    // MARK: - Actions

    @MainActor
    private func saveChanges() async {
        guard !className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            if className != schoolClass?.name {
                try await store.updateClass(classId: classId, name: className)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func addCommonSubject() async {
        let trimmed = newCommonSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if commonSubjects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            newCommonSubject = ""
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.addCourseToClass(classId: classId, name: trimmed, type: .mandatory, gradingMode: .withSchulaufgaben)
            newCommonSubject = ""
            await refreshClassData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renameGroup(groupId: String, type: EditableGroupType) async {
        switch type {
        case .branch:
            guard let index = branchGroups.firstIndex(where: { $0.id == groupId }) else { return }
            let oldName = branchGroups[index].originalName ?? branchGroups[index].name
            let newName = branchGroups[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != oldName else { return }
            isSaving = true
            defer { isSaving = false }
            do {
                try await store.updateBranch(classId: classId, oldName: oldName, newName: newName)
                branchGroups[index].originalName = newName
                await refreshClassData()
            } catch {
                errorMessage = "Fehler beim Umbenennen: \(error.localizedDescription)"
            }
        case .wahlpflicht:
            guard let index = wahlpflichtGroups.firstIndex(where: { $0.id == groupId }) else { return }
            guard let gid = wahlpflichtGroups[index].groupId else { return }
            let oldName = wahlpflichtGroups[index].originalName ?? wahlpflichtGroups[index].name
            let newName = wahlpflichtGroups[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty, newName != oldName else { return }
            isSaving = true
            defer { isSaving = false }
            do {
                try await store.updateWahlpflichtfachGroupName(groupId: gid, name: newName)
                wahlpflichtGroups[index].originalName = newName
                await refreshClassData()
            } catch {
                errorMessage = "Fehler beim Umbenennen: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func addSubject(to groupId: String, type: EditableGroupType) async {
        switch type {
        case .branch:
            guard let index = branchGroups.firstIndex(where: { $0.id == groupId }) else { return }
            let group = branchGroups[index]
            let trimmed = group.newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if group.isNew {
                if !branchGroups[index].subjects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    branchGroups[index].subjects.append(
                        EditableSubject(id: UUID().uuidString, name: trimmed, hasSchulaufgabe: true, courseId: nil)
                    )
                }
                branchGroups[index].newSubject = ""
                return
            }
            if group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Bitte gib dem Zweig zuerst einen Namen."
                return
            }
            if group.originalName != nil && group.name != group.originalName {
                errorMessage = "Bitte speichere den neuen Zweignamen zuerst."
                return
            }
            if group.subjects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                branchGroups[index].newSubject = ""
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                try await store.addCourseToClass(classId: classId, name: trimmed, type: .branch(group.name), gradingMode: .withSchulaufgaben)
                branchGroups[index].newSubject = ""
                await refreshClassData()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .wahlpflicht:
            guard let index = wahlpflichtGroups.firstIndex(where: { $0.id == groupId }) else { return }
            let group = wahlpflichtGroups[index]
            let trimmed = group.newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if group.isNew {
                if !wahlpflichtGroups[index].subjects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    wahlpflichtGroups[index].subjects.append(
                        EditableSubject(id: UUID().uuidString, name: trimmed, hasSchulaufgabe: true, courseId: nil)
                    )
                }
                wahlpflichtGroups[index].newSubject = ""
                return
            }
            guard let gid = group.groupId else { return }
            if group.subjects.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                wahlpflichtGroups[index].newSubject = ""
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                _ = try await store.addSubjectToWahlpflichtfachGroup(
                    classId: classId,
                    groupId: gid,
                    subject: .init(name: trimmed, hasSchulaufgabe: true)
                )
                wahlpflichtGroups[index].newSubject = ""
                await refreshClassData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func createGroup(groupId: String, type: EditableGroupType) async {
        switch type {
        case .branch:
            guard let index = branchGroups.firstIndex(where: { $0.id == groupId }) else { return }
            let group = branchGroups[index]
            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                errorMessage = "Bitte gib einen Namen für den Zweig ein."
                return
            }
            guard !group.subjects.isEmpty else {
                errorMessage = "Bitte füge mindestens ein Fach hinzu."
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                let configs = group.subjects.map { GradesStore.ClassCreationConfiguration.SubjectConfig(name: $0.name, hasSchulaufgabe: $0.hasSchulaufgabe) }
                _ = try await store.addBranchToClass(classId: classId, branchName: trimmedName, subjects: configs)
                branchGroups.remove(at: index)
                await refreshClassData()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .wahlpflicht:
            guard let index = wahlpflichtGroups.firstIndex(where: { $0.id == groupId }) else { return }
            let group = wahlpflichtGroups[index]
            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                errorMessage = "Bitte gib einen Namen für das Wahlpflichtfach ein."
                return
            }
            guard !group.subjects.isEmpty else {
                errorMessage = "Bitte füge mindestens ein Fach hinzu."
                return
            }
            isSaving = true
            defer { isSaving = false }
            do {
                let configs = group.subjects.map { GradesStore.ClassCreationConfiguration.SubjectConfig(name: $0.name, hasSchulaufgabe: $0.hasSchulaufgabe) }
                _ = try await store.addWahlpflichtfachGroupToClass(classId: classId, name: trimmedName, subjects: configs)
                wahlpflichtGroups.remove(at: index)
                await refreshClassData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func removeGroup(groupId: String, type: EditableGroupType) async {
        switch type {
        case .branch:
            guard let index = branchGroups.firstIndex(where: { $0.id == groupId }) else { return }
            if branchGroups[index].isNew {
                branchGroups.remove(at: index)
                return
            }
            let name = branchGroups[index].name
            isSaving = true
            defer { isSaving = false }
            do {
                try await store.removeBranch(classId: classId, branchName: name)
                await refreshClassData()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .wahlpflicht:
            guard let index = wahlpflichtGroups.firstIndex(where: { $0.id == groupId }) else { return }
            if wahlpflichtGroups[index].isNew {
                wahlpflichtGroups.remove(at: index)
                return
            }
            guard let gid = wahlpflichtGroups[index].groupId else { return }
            isSaving = true
            defer { isSaving = false }
            do {
                try await store.unlinkWahlpflichtfachGroup(classId: classId, groupId: gid)
                await refreshClassData()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func deleteSubject(subject: EditableSubject, groupType: EditableGroupType?, groupId: String?) async {
        if subject.courseId == nil {
            if let groupId, let index = branchGroups.firstIndex(where: { $0.id == groupId }) {
                branchGroups[index].subjects.removeAll { $0.id == subject.id }
                return
            }
            if groupType == .wahlpflicht, let groupId, let index = wahlpflichtGroups.firstIndex(where: { $0.groupId == groupId || $0.id == groupId }) {
                wahlpflichtGroups[index].subjects.removeAll { $0.id == subject.id }
                return
            }
            commonSubjects.removeAll { $0.id == subject.id }
            electiveSubjects.removeAll { $0.id == subject.id }
            return
        }

        guard let courseId = subject.courseId else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if groupType == .wahlpflicht, let gid = groupId {
                try await store.removeSubjectFromWahlpflichtfachGroup(classId: classId, groupId: gid, courseId: courseId, subjectName: subject.name)
            } else {
                try await store.deleteCourse(courseId: courseId)
            }
            await refreshClassData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func updateSubjectGradingMode(subject: EditableSubject, overrideValue: Bool? = nil) async {
        guard let courseId = subject.courseId else { return }
        let value = overrideValue ?? subject.hasSchulaufgabe
        let mode: GradingMode = value ? .withSchulaufgaben : .withoutSchulaufgaben
        do {
            try await store.updateCourseGradingMode(courseId: courseId, classId: classId, gradingMode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteClass() async {
        isSaving = true
        await store.archiveClass(classId: classId)
        dismiss()
    }
}

private struct EditableSubjectGroupCard: View {
    @Binding var group: EditableGroup

    let titlePlaceholder: String
    let subtitle: String
    let icon: String
    let color: Color
    let isSaving: Bool
    let onRename: (String) -> Void
    let onAddSubject: (String) -> Void
    let onCreateGroup: (String) -> Void
    let onDeleteGroup: (String) -> Void
    let onDeleteSubject: (EditableSubject) -> Void
    let onToggleSubject: (EditableSubject, Bool) -> Void

    private var canCreate: Bool {
        !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !group.subjects.isEmpty
    }

    private var nameChanged: Bool {
        guard let original = group.originalName else { return false }
        return group.name.trimmingCharacters(in: .whitespacesAndNewlines) != original
    }

    var body: some View {
        SettingsCard(
            title: group.name.isEmpty ? "Neu" : group.name,
            subtitle: subtitle,
            systemImage: icon,
            accent: color
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField(titlePlaceholder, text: $group.name)
                        .font(.headline)
                        .padding(10)
                        .background(Color.formInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !group.isNew && nameChanged {
                        Button("Speichern") {
                            onRename(group.id)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.15))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                        .disabled(isSaving)
                    }
                }

                Divider()

                if !group.subjects.isEmpty {
                    VStack(spacing: 8) {
                        ForEach($group.subjects) { $subject in
                            SubjectCreationRow(
                                name: subject.name,
                                hasSA: Binding(
                                    get: { subject.hasSchulaufgabe },
                                    set: { newValue in
                                        subject.hasSchulaufgabe = newValue
                                        onToggleSubject(subject, newValue)
                                    }
                                ),
                                color: color,
                                onDelete: {
                                    onDeleteSubject(subject)
                                }
                            )
                        }
                    }
                }

                HStack {
                    TextField("Fach hinzufügen...", text: $group.newSubject)
                        .font(.subheadline)
                        .onSubmit { onAddSubject(group.id) }
                        .submitLabel(.done)

                    Button {
                        onAddSubject(group.id)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(color)
                    }
                    .disabled(group.newSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(8)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if group.isNew {
                    Button {
                        onCreateGroup(group.id)
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                            Text("Erstellen")
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(canCreate ? color : .secondary)
                        .padding(.top, 4)
                    }
                    .disabled(!canCreate || isSaving)
                }

                Button(role: .destructive) {
                    onDeleteGroup(group.id)
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text(group.isNew ? "Entfernen" : "Entfernen")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
            }
        }
    }
}
