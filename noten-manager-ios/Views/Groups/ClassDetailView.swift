import SwiftUI
import FirebaseAuth

struct ClassDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    let classId: String
    
    @State private var isJoiningAll: Bool = false
    @State private var joinAllMessage: String?
    @State private var showCreateGroupSheet: Bool = false
    @State private var showCreateCourseSheet: Bool = false
    @State private var showAddGroupByCodeSheet: Bool = false
    @State private var showAddGroupsSheet: Bool = false
    @State private var showAddBranchSheet: Bool = false
    @State private var classCourses: [Course] = []
    @State private var isLoadingCourses: Bool = true
    
    private var schoolClass: SchoolClass? {
        store.classDetails[classId]
    }
    
    // Sort groups: unjoined first
    private var displayGroups: [GroupDetails] {
        guard let groups = schoolClass?.fetchedGroups else { return [] }
        return groups.sorted { g1, g2 in
            let j1 = store.groupIds.contains(g1.id)
            let j2 = store.groupIds.contains(g2.id)
            if j1 != j2 { return !j1 } // unjoined first
            return g1.name < g2.name
        }
    }
    
    private var isOwner: Bool {
        store.classOwners[classId] == Auth.auth().currentUser?.uid
    }
    
    private var animationsOn: Bool { store.animationsEnabled }
    
    private var unjoinedGroups: [GroupDetails] {
        displayGroups.filter { !store.groupIds.contains($0.id) }
    }
    
    private var addableGroups: [String] {
        let allClassGroupIds = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { !allClassGroupIds.contains($0) }
    }
    
    private var myCourses: [Course] {
        classCourses.filter { store.subscribedCourseIds.contains($0.id) }
    }
    
    private var otherCourses: [Course] {
        classCourses.filter { !store.subscribedCourseIds.contains($0.id) }
    }
    
    private var classBranches: [String] {
        // Get unique branch names from courses with .branch type
        var branches: [String] = []
        for course in classCourses {
            if case .branch(let name) = course.type, !branches.contains(name) {
                branches.append(name)
            }
        }
        return branches
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with Stats
                headerSection
                    .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 10)
                
                // Stats Row
                statsRow
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                
                // My Courses Section
                if !myCourses.isEmpty {
                    myCoursesSection
                        .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                }
                
                // Other Courses Section
                if !otherCourses.isEmpty || isOwner {
                    otherCoursesSection
                        .softFadeIn(enabled: animationsOn, delay: 0.18, offset: 12)
                }
                
                // Branches Section (groups merged as branches + add more)
                if isOwner || !classBranches.isEmpty {
                    branchesSection
                        .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                }
                
                // Warning hint
                if store.classIds.contains(classId) {
                    warningHint
                        .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 10)
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .task {
            await store.fetchClassDetails(classId: classId)
            await loadCourses()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showCreateCourseSheet = true
                    } label: {
                        Label("Neuer Kurs", systemImage: "book.fill")
                    }
                    
                    Button {
                        showAddGroupByCodeSheet = true
                    } label: {
                        Label("Gruppe hinzufügen (Code)", systemImage: "rectangle.and.pencil.and.ellipsis")
                    }
                    
                    Divider()
                    
                    Button {
                        showCreateGroupSheet = true
                    } label: {
                        Label("Neue Gruppe (Legacy)", systemImage: "person.3.fill")
                    }
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                }
            }
        }
        .sheet(isPresented: $showCreateGroupSheet) {
            ClassGroupCreationView(classId: classId)
                .environmentObject(store)
        }
        .sheet(isPresented: $showCreateCourseSheet) {
            ClassCourseCreationView(classId: classId, onCourseCreated: {
                Task { await loadCourses() }
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showAddGroupByCodeSheet) {
            AddGroupByCodeSheet(classId: classId, onComplete: {
                Task { await loadCourses() }
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showAddGroupsSheet) {
            AddGroupsToClassSheet(classId: classId, availableGroups: availableGroups, onComplete: {
                Task { await loadCourses() }
            })
            .environmentObject(store)
        }
        .sheet(isPresented: $showAddBranchSheet) {
            AddBranchSheet(classId: classId, onComplete: {
                Task { await loadCourses() }
            })
            .environmentObject(store)
        }
    }
    
    private func loadCourses() async {
        isLoadingCourses = true
        do {
            classCourses = try await store.fetchCoursesForClass(classId: classId)
        } catch {
            print("Failed to load courses: \(error)")
        }
        isLoadingCourses = false
    }
    
    // MARK: - Section Views
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.indigo.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "rectangle.stack.person.crop.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.indigo)
            }
            Text(store.classNames[classId] ?? "Klasse")
                .font(.title2.weight(.bold))
            if isOwner {
                PillBadge(text: "Owner", systemImage: "crown.fill", foreground: .indigo, background: .indigo.opacity(0.1))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
    
    private var statsRow: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatChip(title: "Mitglieder", value: "\(schoolClass?.memberCount ?? 0)", accent: .indigo)
            StatChip(title: "Kurse", value: "\(classCourses.count)", accent: .cyan)
            StatChip(title: "Gruppen", value: "\(displayGroups.count)", accent: .orange)
        }
    }
    
    private var myCoursesSection: some View {
        SettingsCard(
            title: "Meine Kurse",
            subtitle: "\(myCourses.count) abonnierte Kurse",
            systemImage: "person.fill.checkmark",
            accent: .green
        ) {
            VStack(spacing: 0) {
                ForEach(Array(myCourses.enumerated()), id: \.element.id) { index, course in
                    CourseRow(course: course, isOwner: isOwner, isSubscribed: true, onDelete: {
                        Task {
                            try? await store.deleteCourse(courseId: course.id)
                            await loadCourses()
                        }
                    })
                    
                    if index < myCourses.count - 1 {
                        Divider()
                            .opacity(0.5)
                            .padding(.leading, 54)
                    }
                }
            }
            .background(Color.formInputBackground.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var otherCoursesSection: some View {
        SettingsCard(
            title: "Weitere Kurse",
            subtitle: "\(otherCourses.count) weitere Kurse in dieser Klasse",
            systemImage: "book.fill",
            accent: .cyan
        ) {
            if isLoadingCourses {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if otherCourses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keine weiteren Kurse verfügbar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isOwner {
                        Text("Tippe auf + > 'Neuer Kurs' um einen Kurs hinzuzufügen.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(otherCourses.enumerated()), id: \.element.id) { index, course in
                        CourseRow(course: course, isOwner: isOwner, isSubscribed: false, onDelete: {
                            Task {
                                try? await store.deleteCourse(courseId: course.id)
                                await loadCourses()
                            }
                        })
                        
                        if index < otherCourses.count - 1 {
                            Divider()
                                .opacity(0.5)
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(Color.formInputBackground.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    private var branchesSection: some View {
        SettingsCard(
            title: "Zweige",
            subtitle: "\(classBranches.count) Zweige in dieser Klasse",
            systemImage: "arrow.triangle.branch",
            accent: .purple
        ) {
            VStack(spacing: 16) {
                if classBranches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noch keine Zweige erstellt.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Füge eine bestehende Gruppe als Zweig hinzu.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(classBranches, id: \.self) { branchName in
                        BranchDetailRow(
                            branchName: branchName,
                            courses: coursesForBranch(branchName),
                            store: store,
                            onSubscriptionChange: {
                                Task { await loadCourses() }
                            }
                        )
                    }
                }
                
                // Add Groups Buttons
                if isOwner {
                    VStack(spacing: 8) {
                        Button {
                            showAddBranchSheet = true
                        } label: {
                            Label("Neuer Zweig", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .purple))
                        
                        if !availableGroups.isEmpty {
                            Button {
                                showAddGroupsSheet = true
                            } label: {
                                Label("Gruppen auswählen (\(availableGroups.count))", systemImage: "person.3.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .purple))
                        }
                        
                        Button {
                            showAddGroupByCodeSheet = true
                        } label: {
                            Label("Gruppe hinzufügen (Code)", systemImage: "rectangle.and.pencil.and.ellipsis")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .purple))
                    }
                }
            }
        }
    }
    
    private func coursesForBranch(_ branchName: String) -> [Course] {
        classCourses.filter {
            if case .branch(let name) = $0.type { return name == branchName }
            return false
        }
    }
    
    private var availableGroups: [String] {
        // Groups that the user owns and aren't in any class
        let uid = Auth.auth().currentUser?.uid
        let allClassGroupIds = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { gid in
            !allClassGroupIds.contains(gid) &&
            !store.migratedGroupIds.contains(gid) &&
            store.groupOwners[gid] == uid
        }
    }
    
    private var warningHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.indigo)
            Text("Kurse sind der neue Weg, Inhalte zu teilen. Nutze 'Gruppen' nur für Kompatibilität mit älteren App-Versionen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.indigo.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Course Row

struct CourseRow: View {
    let course: Course
    let isOwner: Bool
    var isSubscribed: Bool = false
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    private var typeLabel: String {
        switch course.type {
        case .mandatory:
            return "Pflicht"
        case .branch(let name):
            return "Zweig: \(name)"
        case .elective:
            return "Wahlfach"
        }
    }
    
    private var accentColor: Color {
        isSubscribed ? .green : .cyan
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: isSubscribed ? "checkmark.circle.fill" : "book.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(course.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text(typeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isOwner {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .alert("Kurs löschen?", isPresented: $showDeleteConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Löschen", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Möchtest du \"\(course.name)\" wirklich löschen? Alle geteilten Klausuren und Hausaufgaben in diesem Kurs gehen verloren.")
        }
    }
}

// MARK: - Branch Detail Row

private struct BranchDetailRow: View {
    let branchName: String
    let courses: [Course]
    let store: GradesStore
    let onSubscriptionChange: () -> Void
    
    @State private var isExpanded: Bool = true
    @State private var isProcessing: Bool = false
    
    private var subscribedCount: Int {
        courses.filter { store.subscribedCourseIds.contains($0.id) }.count
    }
    
    private var isFullySubscribed: Bool {
        subscribedCount == courses.count && !courses.isEmpty
    }
    
    private var isPartiallySubscribed: Bool {
        subscribedCount > 0 && subscribedCount < courses.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Branch Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.purple.opacity(0.1))
                            .frame(width: 42, height: 42)
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 18))
                            .foregroundStyle(.purple)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(branchName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Text("\(subscribedCount)/\(courses.count) Kurse abonniert")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Subscribe/Unsubscribe toggle
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            Task { await toggleSubscription() }
                        } label: {
                            Image(systemName: isFullySubscribed ? "checkmark.circle.fill" : (isPartiallySubscribed ? "minus.circle.fill" : "circle"))
                                .font(.title2)
                                .foregroundStyle(isFullySubscribed ? .green : (isPartiallySubscribed ? .orange : .secondary.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            // Expanded Course List
            if isExpanded && !courses.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 12)
                    
                    ForEach(courses, id: \.id) { course in
                        HStack(spacing: 10) {
                            Image(systemName: store.subscribedCourseIds.contains(course.id) ? "checkmark.circle.fill" : "circle")
                                .font(.body)
                                .foregroundStyle(store.subscribedCourseIds.contains(course.id) ? .green : .secondary.opacity(0.4))
                            
                            Text(course.name)
                                .font(.subheadline)
                                .foregroundStyle(store.subscribedCourseIds.contains(course.id) ? .primary : .secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.leading, 34)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(Color.formInputBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @MainActor
    private func toggleSubscription() async {
        isProcessing = true
        
        do {
            if isFullySubscribed {
                // Unsubscribe from all
                try await store.unsubscribeFromBranch(branchCourses: courses)
            } else {
                // Subscribe to all
                try await store.subscribeToBranch(branchCourses: courses)
            }
            onSubscriptionChange()
        } catch {
            print("Subscription toggle failed: \(error)")
        }
        
        isProcessing = false
    }
}

// MARK: - Legacy Group Row

struct ClassGroupRow: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    let group: GroupDetails
    let classId: String
    let isJoined: Bool
    
    @State private var showRemoveConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Group Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isJoined ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .frame(width: 42, height: 42)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isJoined ? .green : .orange)
            }
            
            NavigationLink {
                GroupSubjectManagementView(groupId: group.id)
                    .environmentObject(store)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 4) {
                            if isJoined {
                                Label("Beigetreten", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Nicht beigetreten", systemImage: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                            Text("•")
                            Text("\(group.memberCount) Mitglieder")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            
            // Remove button
            Button {
                showRemoveConfirmation = true
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .alert("Gruppe entfernen?", isPresented: $showRemoveConfirmation) {
            Button("Abbrechen", role: .cancel) { }
            Button("Entfernen", role: .destructive) {
                Task {
                    try? await store.removeGroupFromClass(classId: classId, groupId: group.id)
                }
            }
        } message: {
            Text("Möchtest du \"\(group.name)\" aus dieser Klasse entfernen?")
        }
    }
}

// MARK: - Add Group By Code Sheet

struct AddGroupByCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let onComplete: () -> Void
    
    @State private var groupCode: String = ""
    @State private var branchName: String = ""
    @State private var isAdding: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gruppencode", text: $groupCode)
                        .textInputAutocapitalization(.characters)
                        .font(.body.monospaced())
                } header: {
                    Text("Gruppencode")
                } footer: {
                    Text("Der Code der bestehenden Gruppe, die du hinzufügen möchtest.")
                }
                
                Section {
                    TextField("Zweig-Name", text: $branchName)
                } header: {
                    Text("Zweig-Name")
                } footer: {
                    Text("Die Fächer dieser Gruppe werden als Kurse für diesen Zweig erstellt.")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Gruppe hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        Task { await addGroup() }
                    }
                    .disabled(groupCode.isEmpty || branchName.isEmpty || isAdding)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    @MainActor
    private func addGroup() async {
        isAdding = true
        errorMessage = nil
        
        do {
            try await store.addLegacyGroupToClass(classId: classId, groupCode: groupCode.trimmingCharacters(in: .whitespacesAndNewlines), branchName: branchName.trimmingCharacters(in: .whitespacesAndNewlines))
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isAdding = false
    }
}

// MARK: - Add Groups to Class Sheet

struct AddGroupsToClassSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let availableGroups: [String]
    let onComplete: () -> Void
    
    @State private var selectedGroups: Set<String> = []
    @State private var branchNames: [String: String] = [:]
    @State private var isAdding: Bool = false
    @State private var errorMessage: String?
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 40))
                            .foregroundStyle(.purple)
                            .padding(.bottom, 4)
                        
                        Text("Gruppen hinzufügen")
                            .font(.title3.weight(.bold))
                        
                        Text("Wähle Gruppen aus, die als Zweige hinzugefügt werden sollen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    
                    // Group Selection
                    SettingsCard(
                        title: "Deine Gruppen",
                        subtitle: "\(selectedGroups.count) von \(availableGroups.count) ausgewählt",
                        systemImage: "person.3.fill",
                        accent: .purple
                    ) {
                        if availableGroups.isEmpty {
                            Text("Keine verfügbaren Gruppen.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(availableGroups.enumerated()), id: \.element) { index, groupId in
                                    GroupBranchSelectionRow(
                                        groupId: groupId,
                                        groupName: store.groupNames[groupId] ?? "Unbenannt",
                                        isSelected: selectedGroups.contains(groupId),
                                        branchName: branchNames[groupId] ?? store.groupNames[groupId] ?? "",
                                        onToggle: {
                                            if selectedGroups.contains(groupId) {
                                                selectedGroups.remove(groupId)
                                                branchNames.removeValue(forKey: groupId)
                                            } else {
                                                selectedGroups.insert(groupId)
                                                branchNames[groupId] = store.groupNames[groupId] ?? ""
                                            }
                                        },
                                        onBranchNameChange: { newName in
                                            branchNames[groupId] = newName
                                        }
                                    )
                                    
                                    if index < availableGroups.count - 1 {
                                        Divider()
                                            .opacity(0.5)
                                            .padding(.leading, 54)
                                    }
                                }
                            }
                            .background(Color.formInputBackground.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    // Add Button
                    Button {
                        Task { await addGroups() }
                    } label: {
                        if isAdding {
                            ProgressView().tint(.purple)
                        } else {
                            Text("Zweige hinzufügen")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .purple))
                    .disabled(selectedGroups.isEmpty || isAdding)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(isDark ? .white : .black)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
    
    @MainActor
    private func addGroups() async {
        isAdding = true
        errorMessage = nil
        
        let groups = selectedGroups.map { gid in
            (groupId: gid, branchName: branchNames[gid] ?? store.groupNames[gid] ?? "Unbenannt")
        }
        
        do {
            try await store.addGroupsAsBranchesToClass(classId: classId, groups: groups)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isAdding = false
    }
}

// MARK: - Group Branch Selection Row

private struct GroupBranchSelectionRow: View {
    let groupId: String
    let groupName: String
    let isSelected: Bool
    var branchName: String
    let onToggle: () -> Void
    let onBranchNameChange: (String) -> Void
    
    @State private var localBranchName: String = ""
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? .purple : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupName)
                        .font(.subheadline.weight(.semibold))
                    Text("Gruppe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            if isSelected {
                HStack {
                    Text("Zweig-Name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Zweig", text: $localBranchName)
                        .font(.subheadline)
                        .padding(8)
                        .background(Color.formInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: localBranchName) { _, newValue in
                            onBranchNameChange(newValue)
                        }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            localBranchName = branchName
        }
    }
}

// MARK: - Add Branch Sheet

struct AddBranchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let onComplete: () -> Void
    
    @State private var branchName: String = ""
    @State private var subjects: [String] = []
    @State private var newSubjectText: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 40))
                            .foregroundStyle(.purple)
                            .padding(.bottom, 4)
                        
                        Text("Neuer Zweig")
                            .font(.title3.weight(.bold))
                        
                        Text("Erstelle einen neuen Zweig mit eigenen Fächern.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    
                    // Branch Name
                    SettingsCard(
                        title: "Zweig-Name",
                        subtitle: "z.B. Naturwissenschaft, Sprachen, etc.",
                        systemImage: "tag.fill",
                        accent: .purple
                    ) {
                        TextField("Zweig-Name", text: $branchName)
                            .font(.body)
                            .padding(12)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Subjects
                    SettingsCard(
                        title: "Fächer",
                        subtitle: "\(subjects.count) Fächer hinzugefügt",
                        systemImage: "book.fill",
                        accent: .blue
                    ) {
                        VStack(spacing: 12) {
                            // Subject chips
                            if !subjects.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(subjects, id: \.self) { subject in
                                        HStack(spacing: 4) {
                                            Text(subject)
                                                .font(.subheadline)
                                            Button {
                                                subjects.removeAll { $0 == subject }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            
                            // Add subject field
                            HStack {
                                TextField("Fach hinzufügen", text: $newSubjectText)
                                    .font(.body)
                                    .padding(12)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .onSubmit {
                                        addSubject()
                                    }
                                
                                Button {
                                    addSubject()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                }
                                .disabled(newSubjectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    // Create Button
                    Button {
                        Task { await createBranch() }
                    } label: {
                        if isCreating {
                            ProgressView().tint(.purple)
                        } else {
                            Text("Zweig erstellen")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .purple))
                    .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subjects.isEmpty || isCreating)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(isDark ? .white : .black)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
    
    private func addSubject() {
        let trimmed = newSubjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !subjects.contains(trimmed) else { return }
        subjects.append(trimmed)
        newSubjectText = ""
    }
    
    @MainActor
    private func createBranch() async {
        isCreating = true
        errorMessage = nil
        
        do {
            _ = try await store.addBranchToClass(
                classId: classId,
                branchName: branchName.trimmingCharacters(in: .whitespacesAndNewlines),
                subjects: subjects
            )
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onComplete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isCreating = false
    }
}
