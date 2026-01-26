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
    @State private var showLinkClassSheet: Bool = false
    @State private var showSubjectMapping: Bool = false

    @State private var classCourses: [Course] = []
    @State private var linkedElectiveGroups: [WahlpflichtfachGroup] = []
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
    
    fileprivate enum BranchItem: Hashable {
        case mandatory
        case standard(name: String)
        case elective(group: WahlpflichtfachGroup)
        
        var name: String {
            switch self {
            case .mandatory: return "Gemeinsame Fächer"
            case .standard(let name): return name
            case .elective(let group): return group.name
            }
        }
    }

    private var allBranches: [BranchItem] {
        var items: [BranchItem] = []
        
        // Mandatory (if any exist)
        if classCourses.contains(where: { $0.type == .mandatory }) {
            items.append(.mandatory)
        }
        
        // Standard Branches
        var branches: Set<String> = []
        for course in classCourses {
            if case .branch(let name) = course.type {
                branches.insert(name)
            }
        }
        items.append(contentsOf: branches.map { .standard(name: $0) })
        
        // Electives
        items.append(contentsOf: linkedElectiveGroups.map { .elective(group: $0) })
        
        // Sort: Mandatory first, then Standard Branches, then Electives
        return items.sorted { lhs, rhs in
            func priority(_ item: BranchItem) -> Int {
                switch item {
                case .mandatory: return 0
                case .standard: return 1
                case .elective: return 2
                }
            }
            let p1 = priority(lhs)
            let p2 = priority(rhs)
            if p1 != p2 { return p1 < p2 }
            return lhs.name < rhs.name
        }
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
                

                
                // Branches Section (groups merged as branches + add more)
                if isOwner || !allBranches.isEmpty {
                    branchesSection
                        .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                }
                

                


                if store.classIds.contains(classId) {
                    VStack(spacing: 12) {
                        Divider()
                            .padding(.vertical, 8)
                        
                        Button {
                            showSubjectMapping = true
                        } label: {
                            Label("Fach-Verknüpfungen verwalten", systemImage: "arrow.left.arrow.right")
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                        
                        Text("Hier kannst du einstellen, welche Kurse dieser Klasse mit deinen lokalen Fächern verknüpft sind.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 16)
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
                    
                    Button {
                        showLinkClassSheet = true
                    } label: {
                        Label("Wahlpflichtfach verknüpfen", systemImage: "link")
                    }
                    
                    Divider()
                    
                    Button {
                        showCreateGroupSheet = true
                    } label: {
                        Label("Neue Gruppe (Legacy)", systemImage: "person.3.fill")
                    }
                    
                    Divider()
                    
                    Button {
                        showAddBranchSheet = true
                    } label: {
                        Label("Zweig hinzufügen", systemImage: "arrow.triangle.branch")
                    }
                    
                    Button {
                        showAddGroupsSheet = true
                    } label: {
                        Label("Bestehende Gruppe hinzufügen", systemImage: "person.2.badge.plus")
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
        .sheet(isPresented: $showLinkClassSheet) {
            LinkClassSheet(sourceClassId: classId)
                .environmentObject(store)
        }
        .sheet(isPresented: $showSubjectMapping) {
            SubjectMappingView(classId: classId, courses: myCourses)
                .environmentObject(store)
        }
    }
    
    private func loadCourses() async {
        isLoadingCourses = true
        do {
            classCourses = try await store.fetchCoursesForClass(classId: classId)
            
            // Load electives if linked
            if let linkedIds = store.classDetails[classId]?.linkedWahlpflichtfachGroupIds, !linkedIds.isEmpty {
                var fetched: [WahlpflichtfachGroup] = []
                for gid in linkedIds {
                    if let group = try? await store.fetchWahlpflichtfachGroupInfo(with: gid) {
                        fetched.append(group)
                    }
                }
                self.linkedElectiveGroups = fetched
            } else {
                self.linkedElectiveGroups = []
            }
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
            title: "Kurs-Angebote",
            subtitle: "\(allBranches.count) Gruppen verfügbar",
            systemImage: "square.stack.3d.up.fill",
            accent: .indigo
        ) {
            VStack(spacing: 16) {
                if allBranches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noch keine Fächer verfügbar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Füge Kurse, Zweige oder Wahlpflichtfächer hinzu.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ForEach(allBranches, id: \.self) { item in
                        BranchDetailRow(
                            item: item,
                            classCourses: classCourses,
                            store: store,
                            classId: classId,
                            onSubscriptionChange: { wasJoined in
                                Task { 
                                    await loadCourses() 
                                    if wasJoined {
                                        // If a group was joined, show mapping
                                        self.showSubjectMapping = true
                                    }
                                }
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
    

}

// MARK: - Course Row

struct CourseRow: View {
    let course: Course
    let isOwner: Bool
    var isSubscribed: Bool = false
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    private var typeLabel: String {
        guard let type = course.type else { return "Unbekannt" }
        switch type {
        case .mandatory:
            return "Pflicht"
        case .branch(let name):
            return "Zweig: \(name)"
        case .elective:
            return "Wahlfach"
        case .wahlpflicht(let groupId):
            return "Wahlpflicht: \(store.wahlpflichtfachGroupNames[groupId] ?? "Unbenannt")"
        }
    }
    
    private func hasLocalSubject(name: String) -> Bool {
        store.subjects.contains { $0.name.lowercased() == name.lowercased() }
    }
    
    private var accentColor: Color {
        if isSubscribed { return .green }
        return hasLocalSubject(name: course.name) ? .cyan : .indigo
    }
    
    @EnvironmentObject var store: GradesStore
    @State private var isProcessing: Bool = false
    
    var body: some View {
        Button {
            Task {
                isProcessing = true
                try? await store.toggleCourseSubscription(course: course)
                isProcessing = false
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accentColor.opacity(0.1))
                        .frame(width: 42, height: 42)
                    
                    if isProcessing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        let existsLocally = hasLocalSubject(name: course.name)
                        Image(systemName: isSubscribed ? "checkmark.circle.fill" : (existsLocally ? "circle" : "plus.circle.fill"))
                            .font(.system(size: 18))
                            .foregroundStyle(accentColor)
                    }
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
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Branch/Elective Detail Row

private struct BranchDetailRow: View {
    let item: ClassDetailView.BranchItem
    let classCourses: [Course]
    let store: GradesStore
    let classId: String
    let onSubscriptionChange: (Bool) -> Void
    
    @State private var isExpanded: Bool = false // Collapsed by default
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String?
    
    // Computed props
    private var coursesToDisplay: [Course] {
        switch item {
        case .mandatory:
             return classCourses.filter { $0.type == .mandatory }
        case .standard(let name):
            return classCourses.filter {
                if case .branch(let n) = $0.type { return n == name }
                return false
            }
        case .elective(let group):
            // Show actual courses if joined, otherwise dummy courses from metadata
            let joinedCourses = classCourses.filter {
                 if case .wahlpflicht(let gid) = $0.type { return gid == group.id }
                 return false
            }
            if !joinedCourses.isEmpty { return joinedCourses }
            
            // Should show placeholders from metadata if not joined or no courses yet?
            // "group.subjects" gives us names. We can simulate Course objects for display or just list names?
            // To keep UI consistent, let's just use the names.
            // But wait, the UI expects [Course].
            // Let's create dummy courses for display if not joined.
            return group.subjects.map { subjectName in
                Course(
                    id: UUID().uuidString,
                    name: subjectName,
                    subjectKey: nil,
                    classId: nil,
                    type: .wahlpflicht(group.id),
                    gradingMode: nil,
                    ownerId: nil,
                    joinCode: nil,
                    createdAt: Date()
                )
            }
        }
    }
    
    private var isJoined: Bool {
        switch item {
        case .mandatory:
             // Mandatory is "joined" if any are subscribed? Or all?
             // Let's use subscribedCount > 0
             return subscribedCount > 0
        case .standard:
            // For branches, "joined" means at least one course subscribed?
            // Or use the previous logic: isFullySubscribed / isPartiallySubscribed
            return subscribedCount > 0
        case .elective(let group):
            return store.wahlpflichtfachGroupIds.contains(group.id)
        }
    }
    
    private var subscribedCount: Int {
        switch item {
        case .mandatory:
            return coursesToDisplay.filter { store.subscribedCourseIds.contains($0.id) }.count
        case .standard:
            return coursesToDisplay.filter { store.subscribedCourseIds.contains($0.id) }.count
        case .elective(let group):
            return store.wahlpflichtfachGroupIds.contains(group.id) ? coursesToDisplay.count : 0
        }
    }
    
    // For standard branch logic
    private var isFullySubscribed: Bool {
        subscribedCount == coursesToDisplay.count && !coursesToDisplay.isEmpty
    }
    
    private var isPartiallySubscribed: Bool {
        subscribedCount > 0 && subscribedCount < coursesToDisplay.count
    }
    
    private func hasLocalSubject(name: String) -> Bool {
        store.subjects.contains { $0.name.lowercased() == name.lowercased() }
    }
    
    private var isAnySubjectMissingLocally: Bool {
        coursesToDisplay.contains { !hasLocalSubject(name: $0.name) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(headerColor.opacity(0.1))
                            .frame(width: 42, height: 42)
                        Image(systemName: headerIcon)
                            .font(.system(size: 18))
                            .foregroundStyle(headerColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Text(subtitleText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Toggle Action
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            Task { await toggleSubscription() }
                        } label: {
                            statusIcon
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
            
            // Expanded List
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 12)
                    
                    if coursesToDisplay.isEmpty {
                        Text("Keine Kurse verfügbar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(coursesToDisplay, id: \.self) { course in
                            HStack(spacing: 11) {
                                let active = isCourseActive(course)
                                let existsLocally = hasLocalSubject(name: course.name)
                                
                                Image(systemName: active ? "checkmark.circle.fill" : (existsLocally ? "circle" : "plus.circle.fill"))
                                    .font(.system(size: 16))
                                    .foregroundStyle(active ? .green : (existsLocally ? .secondary.opacity(0.4) : headerColor))
                                
                                Text(course.name)
                                    .font(.subheadline)
                                    .foregroundStyle(active ? .primary : .secondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 22)
                            .padding(.leading, 34)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .background(Color.formInputBackground.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            if let error = errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(4)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(4)
                    .padding(.bottom, 40)
            }
        }
    }
    
    private var headerColor: Color {
        switch item {
        case .mandatory: return .indigo
        case .standard: return .purple
        case .elective: return .teal
        }
    }
    
    private var headerIcon: String {
        switch item {
        case .mandatory: return "person.3.fill"
        case .standard: return "arrow.triangle.branch"
        case .elective: return "star.fill"
        }
    }
    
    private var subtitleText: String {
        switch item {
        case .mandatory, .standard:
            return "\(subscribedCount)/\(coursesToDisplay.count) Kurse abonniert"
        case .elective(let group):
            let subjects = group.subjects.joined(separator: ", ")
            return subjects.isEmpty ? "\(coursesToDisplay.count) Fächer" : subjects
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item {
        case .mandatory, .standard:
            if isFullySubscribed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else if isPartiallySubscribed {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: isAnySubjectMissingLocally ? "plus.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isAnySubjectMissingLocally ? headerColor : .secondary.opacity(0.5))
            }
        case .elective:
             if isJoined {
                 Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
             } else {
                 Image(systemName: isAnySubjectMissingLocally ? "plus.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isAnySubjectMissingLocally ? headerColor : .secondary.opacity(0.5))
             }
        }
    }
    
    private func isCourseActive(_ course: Course) -> Bool {
        switch item {
        case .mandatory, .standard:
            return store.subscribedCourseIds.contains(course.id)
        case .elective:
            // If the group is joined, we assume all subjects in it are "active" conceptually,
            // or we check if we actually subscribed to them.
            // In the "elective" model, joining the group usually subscribes to the courses.
            // If we are just showing dummy courses from metadata, they aren't in subscribedCourseIds.
            // If we are showing real courses, we check subscription.
            if store.wahlpflichtfachGroupIds.contains(course.type?.associatedId ?? "") {
                 // For display purposes, if the group is joined, show checkmark?
                 // Real check:
                 return store.subscribedCourseIds.contains(course.id) || isJoined
            }
            return false
        }
    }
    
    private var associatedId: String? {
        if case .wahlpflicht(let id) = coursesToDisplay.first?.type { return id }
        return nil
    }

    @MainActor
    private func toggleSubscription() async {
        isProcessing = true
        var wasJoined = false
        defer { 
            isProcessing = false 
            onSubscriptionChange(wasJoined)
        }
        
        do {
            switch item {
            case .mandatory, .standard:
                if isFullySubscribed {
                    try await store.unsubscribeFromBranch(branchCourses: coursesToDisplay)
                } else {
                    try await store.subscribeToBranch(branchCourses: coursesToDisplay)
                    wasJoined = true
                }
                
            case .elective(let group):
                if isJoined {
                    await store.leaveWahlpflichtfachGroup(code: group.id, inClass: classId)
                } else {
                    try await store.joinWahlpflichtfachGroup(with: group.id, inClass: classId)
                    wasJoined = true
                }
            }
        } catch {
            errorMessage = "Fehler: \(error.localizedDescription)"
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                errorMessage = nil
            }
        }
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

// MARK: - Link Class Sheet

struct LinkClassSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let sourceClassId: String
    
    @State private var targetCode: String = ""
    @State private var isLinking: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Wahlpflichtfach-Code", text: $targetCode)
                        .textInputAutocapitalization(.characters)
                        .font(.body.monospaced())
                } header: {
                    Text("Wahlpflichtfach verknüpfen")
                } footer: {
                    Text("Füge ein bestehendes Wahlpflichtfach per Code zu dieser Klasse hinzu.")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Wahlpflichtfach verknüpfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verknüpfen") {
                        Task { await linkClass() }
                    }
                    .disabled(targetCode.isEmpty || isLinking)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    @MainActor
    private func linkClass() async {
        isLinking = true
        errorMessage = nil
        
        do {
            try await store.linkWahlpflichtfachToClass(classId: sourceClassId, wahlpflichtfachGroupId: targetCode)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLinking = false
    }
}
