import SwiftUI

struct CourseJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let className: String
    let config: ClassConfiguration?
    let linkedClassIds: [String]
    let onJoinSuccess: () -> Void
    
    init(classId: String, className: String, config: ClassConfiguration?, linkedClassIds: [String], onJoinSuccess: @escaping () -> Void) {
        self.classId = classId
        self.className = className
        self.config = config
        self.linkedClassIds = linkedClassIds
        self.onJoinSuccess = onJoinSuccess
    }
    
    @State private var courses: [Course] = []
    @State private var isLoading: Bool = true
    @State private var selectedMandatoryIds: Set<String> = []
    @State private var selectedBranchIds: Set<String> = [] 
    @State private var selectedElectiveIds: Set<String> = []
    @State private var selectedWahlpflichtIds: Set<String> = []

    // Cached Lists for Performance
    @State private var mandatoryCourses: [Course] = []
    @State private var electiveCourses: [Course] = []
    @State private var wahlpflichtCourses: [Course] = []

    @State private var selectedLinkedClasses: Set<String> = [] 
    @State private var linkedClassDetails: [String: String] = [:] 
    @State private var errorMessage: String?
    @State private var isJoining: Bool = false
    
    // Subject Mapping
    @State private var showSubjectMapping: Bool = false
    @State private var joinedCourses: [Course] = []
    
    // Theme
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var accentColor: Color { .indigo }
    
    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(accentColor.opacity(0.12))
                                    .frame(width: 80, height: 80)
                                Image(systemName: "rectangle.stack.person.crop.fill")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundStyle(accentColor)
                            }
                            
                            VStack(spacing: 4) {
                                Text(className)
                                    .font(.title.weight(.bold))
                                    .multilineTextAlignment(.center)
                                Text("Fast geschafft! Wähle deine Kurse aus.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 24)
                        
                        if isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                Text("Kurse werden geladen...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        } else {
                            content
                        }
                    }
                    .padding(20)
                }
            }
            .task {
                await loadCourses()
            }
            .sheet(isPresented: $showSubjectMapping, onDismiss: {
                onJoinSuccess()
            }) {
                SubjectMappingView(classId: classId, courses: joinedCourses)
            }
        }
    }
    
    // Computed properties removed for performance
    
    @State private var linkedElectiveGroups: [WahlpflichtfachGroup] = []
    
    // Unified Branch Item
    fileprivate enum BranchItem: Hashable {
        case standard(name: String)
        case elective(group: WahlpflichtfachGroup)
        
        var name: String {
            switch self {
            case .standard(let n): return n
            case .elective(let g): return g.name
            }
        }
    }
    
    private var allBranches: [BranchItem] {
        var items: [BranchItem] = []
        
        // Standard Branches
        let branchNames = Set(courses.compactMap { course -> String? in
            if case .branch(let name) = course.type { return name }
            return nil
        })
        items.append(contentsOf: branchNames.map { .standard(name: $0) })
        
        // Electives (from Metadata, mirroring ClassDetailView)
        items.append(contentsOf: linkedElectiveGroups.map { .elective(group: $0) })
        
        return items.sorted { $0.name < $1.name }
    }
    
    // Derived courses for display (Real + Dummy)
    private func coursesForItem(_ item: BranchItem) -> [Course] {
        switch item {
        case .standard(let name):
            return courses.filter { if case .branch(let n) = $0.type { return n == name }; return false }
        case .elective(let group):
            let real = courses.filter { if case .wahlpflicht(let id) = $0.type { return id == group.id }; return false }
            if !real.isEmpty { return real }
            
            // Dummy courses from metadata (ClassDetailView logic)
            return group.subjects.map { subjectName in
                Course(
                    id: "dp_\(group.id)_\(subjectName.replacingOccurrences(of: " ", with: "_"))", // stable placeholder id
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
    
    private var content: some View {
        VStack(spacing: 32) {
            // 1. Common Subjects (Gemeinsame)
            if !mandatoryCourses.isEmpty {
                SettingsCard(
                    title: "Gemeinsame",
                    subtitle: "Diese Fächer sind für alle in der Klasse verpflichtend.",
                    systemImage: "lock.open.fill",
                    accent: accentColor
                ) {
                    VStack(spacing: 0) {
                        ForEach(Array(mandatoryCourses.enumerated()), id: \.element.id) { index, course in
                            CourseSelectionRow(
                                course: course,
                                isSelected: selectedMandatoryIds.contains(course.id),
                                accent: accentColor
                            ) {
                                if selectedMandatoryIds.contains(course.id) {
                                    selectedMandatoryIds.remove(course.id)
                                } else {
                                    selectedMandatoryIds.insert(course.id)
                                }
                            }
                            
                            if index < mandatoryCourses.count - 1 {
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

            
            // 2. Branches & Wahlpflicht (Unified)
            if !allBranches.isEmpty {
                SettingsCard(
                    title: "Zweige & Wahlpflicht",
                    subtitle: "Wähle passenden Optionen für dich aus.",
                    systemImage: "arrow.triangle.branch",
                    accent: .orange
                ) {
                    VStack(spacing: 16) {
                        ForEach(allBranches, id: \.self) { item in
                            BranchSelectionRow(
                                item: item,
                                courses: coursesForItem(item),
                                selectedCourseIds: selectedIdsForItem(item),
                                onToggleCourse: { courseId in
                                    toggleCourse(courseId, item: item)
                                },
                                onToggleBranch: {
                                    toggleAll(item: item)
                                }
                            )
                        }
                    }
                    .background(Color.formInputBackground.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            
            // 3. Independent Electives (Wahlfächer)
            if !electiveCourses.isEmpty {
                SettingsCard(
                    title: "Wahlfächer",
                    subtitle: "Zusätzliche Fächer, die du freiwillig belegst.",
                    systemImage: "star.fill",
                    accent: .teal
                ) {
                    VStack(spacing: 0) {
                        ForEach(Array(electiveCourses.enumerated()), id: \.element.id) { index, course in
                            CourseSelectionRow(
                                course: course,
                                isSelected: selectedElectiveIds.contains(course.id),
                                accent: .teal
                            ) {
                                if selectedElectiveIds.contains(course.id) {
                                    selectedElectiveIds.remove(course.id)
                                } else {
                                    selectedElectiveIds.insert(course.id)
                                }
                            }
                            
                            if index < electiveCourses.count - 1 {
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
            
            // 4. Linked Classes
            if !linkedClassIds.isEmpty && !linkedClassDetails.isEmpty {
                SettingsCard(
                    title: "Verknüpfte Klassen",
                    subtitle: "Du kannst diesen Klassen ebenfalls beitreten.",
                    systemImage: "link",
                    accent: .blue
                ) {
                    VStack(spacing: 0) {
                        ForEach(Array(linkedClassIds.enumerated()), id: \.element) { index, code in
                            if let name = linkedClassDetails[code] {
                                Button {
                                    if selectedLinkedClasses.contains(code) {
                                        selectedLinkedClasses.remove(code)
                                    } else {
                                        selectedLinkedClasses.insert(code)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.blue.opacity(0.1))
                                                .frame(width: 42, height: 42)
                                            Image(systemName: selectedLinkedClasses.contains(code) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18))
                                                .foregroundStyle(selectedLinkedClasses.contains(code) ? .blue : .secondary.opacity(0.5))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            
                                            Text("Verknüpfte Klasse")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                
                                if index < linkedClassIds.count - 1 {
                                    Divider()
                                        .opacity(0.5)
                                        .padding(.leading, 54)
                                }
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
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task { await joinWithSelection() }
            } label: {
                if isJoining {
                    ProgressView().tint(.white)
                } else {
                    Text("Setup abschließen")
                        .font(.headline)
                }
            }
            .buttonStyle(PremiumOnboardingButtonStyle(accent: accentColor))
            .disabled({
                 // Logic: If branches exist, user must have selected at least one course from one branch? 
                 // Or just not block them?
                 // User request says "don't want courses listed individually".
                 // Let's assume standard validation: If branches exist, check if any branch logic is satisfied.
                 // For now, lenient:
                 return false
            }())
            .padding(.top, 16)
        }
    }
    
    // Helper for Unified Branch Logic
    // NOTE: coursesForItem is defined above with correct dummy logic.
    
    private func selectedIdsForItem(_ item: BranchItem) -> Set<String> {
        switch item {
        case .standard: return selectedBranchIds
        case .elective: return selectedWahlpflichtIds
        }
    }
    
    private func toggleCourse(_ courseId: String, item: BranchItem) {
        switch item {
        case .standard:
            if selectedBranchIds.contains(courseId) { selectedBranchIds.remove(courseId) }
            else { selectedBranchIds.insert(courseId) }
        case .elective:
            if selectedWahlpflichtIds.contains(courseId) { selectedWahlpflichtIds.remove(courseId) }
            else { selectedWahlpflichtIds.insert(courseId) }
        }
    }
    
    private func toggleAll(item: BranchItem) {
        let itemCourses = coursesForItem(item)
        let ids = itemCourses.map { $0.id }
        
        // Check if all selected
        let currentSelected: Set<String>
        switch item {
        case .standard: currentSelected = selectedBranchIds
        case .elective: currentSelected = selectedWahlpflichtIds
        }
        
        let allSelected = ids.allSatisfy { currentSelected.contains($0) }
        
        if allSelected {
            // Deselect all
            switch item {
            case .standard: ids.forEach { selectedBranchIds.remove($0) }
            case .elective: ids.forEach { selectedWahlpflichtIds.remove($0) }
            }
        } else {
            // Select all
            switch item {
            case .standard: ids.forEach { selectedBranchIds.insert($0) }
            case .elective: ids.forEach { selectedWahlpflichtIds.insert($0) }
            }
        }
    }
    
    @MainActor
    private func loadCourses() async {
        isLoading = true // Ensure loading state is shown
        do {
            // First load class details (gets WP Group names correctly)
            await store.fetchClassDetails(classId: classId)
            
            courses = try await store.fetchCoursesForClass(classId: classId)
            
            // Load linked elective groups (metadata) like ClassDetailView
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
            
            // Categorize courses
            mandatoryCourses = courses.filter {
                if let type = $0.type, case .mandatory = type { return true }
                return false
            }
            
            // Important: Log how many mandatory we found
            print("Loaded \(courses.count) courses. Mandatory: \(mandatoryCourses.count)")

            electiveCourses = courses.filter { if let type = $0.type, case .elective = type { return true }; return false }
            wahlpflichtCourses = courses.filter { if let type = $0.type, case .wahlpflicht(_) = type { return true }; return false }
            
            // Initialize selection - Preselect Mandatory
            selectedMandatoryIds = Set(mandatoryCourses.map { $0.id })
            
            // Load linked class names
            for code in linkedClassIds {
                if let info = try? await store.fetchClassInfo(with: code) {
                    linkedClassDetails[code] = info.name
                }
            }
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    @MainActor
    private func joinWithSelection() async {
        isJoining = true
        errorMessage = nil
        do {
            var selected: [Course] = []
            // 1. Mandatory Subjects
            selected.append(contentsOf: mandatoryCourses.filter { selectedMandatoryIds.contains($0.id) })
            
            // 2. Unified Branches (Standard + Wahlpflicht)
            for item in allBranches {
                let itemCourses = coursesForItem(item)
                let selectedIds = selectedIdsForItem(item)
                selected.append(contentsOf: itemCourses.filter { selectedIds.contains($0.id) })
            }
            
            // 3. Independent Electives
            selected.append(contentsOf: electiveCourses.filter { selectedElectiveIds.contains($0.id) })
            
            // 1. Join Class & Standard Courses
            try await store.joinClassWithBranch(classId: classId, selectedCourses: selected)
            
            // 2. Join Elective Groups explicitly
            // Identify selected groups
            // Iterate all branches, if it is .elective and is selected
            for item in allBranches {
                if case .elective(let group) = item {
                    // Check if *any* course in this group is selected
                    // Since we use unified `coursesForItem`, we can check IDs
                    let itemCourses = coursesForItem(item)
                    let ids = itemCourses.map { $0.id }
                    let isSelected = ids.contains { selectedWahlpflichtIds.contains($0) }
                    
                    if isSelected {
                        try? await store.joinWahlpflichtfachGroup(with: group.id, inClass: classId)
                    }
                }
            }
            
            // Join Linked Classes
            for code in selectedLinkedClasses {
                try? await store.joinClass(with: code) 
            }
            
            // Automatic Subject Creation for New Users
            if store.subjects.isEmpty {
                print("🆕 New User detected: Automatically creating subjects for selected courses...")
                var createdNames: Set<String> = []
                
                for course in selected {
                    let subjectName = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !subjectName.isEmpty else { continue }
                    
                    // Avoid creating duplicates if user selected multiple courses with same name (unlikely but possible)
                    if !createdNames.contains(subjectName) {
                        do {
                            // Create Subject
                            // Type 0 = Standard/Basic Subject (safe default)
                            try await store.addSubjectToFirestore(name: subjectName, type: 0, date: Date())
                            createdNames.insert(subjectName)
                            print("✅ Created subject: \(subjectName)")
                        } catch {
                            print("⚠️ Failed to auto-create subject '\(subjectName)': \(error)")
                        }
                    }
                    
                    // Map Course to Subject
                    do {
                        try await store.saveCourseMapping(courseId: course.id, subjectName: subjectName)
                    } catch {
                         print("⚠️ Failed to map course '\(course.name)' to subject: \(error)")
                    }
                }
                
                // Refresh subjects locally to ensure UI updates and subsequent checks pass
                // (firestore listener should handle this, but slight delay might trigger missing check)
                // We'll rely on the 'missing' check below. If it's too fast, we might need a small delay or manual fetch.
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s wait for Firestore propagation
            }
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Store joined courses for mapping view
            self.joinedCourses = selected
            
            // Always show subject mapping to confirm selections
            if !selected.isEmpty {
                self.showSubjectMapping = true
            } else {
                onJoinSuccess()
            }
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isJoining = false
    }
}

// MARK: - Reusable Selection Row

// MARK: - Course Selection Row (Matches ClassDetailView CourseRow)

private struct CourseSelectionRow: View {
    let course: Course
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.1))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? accent : .secondary.opacity(0.5))
                }
            
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

// MARK: - Branch Selection Row (Matches ClassDetailView BranchDetailRow)

private struct BranchSelectionRow: View {
    let item: CourseJoinView.BranchItem
    let courses: [Course]
    let selectedCourseIds: Set<String>
    let onToggleCourse: (String) -> Void
    let onToggleBranch: () -> Void
    
    @State private var isExpanded: Bool = false
    
    private var selectedCount: Int {
        courses.filter { selectedCourseIds.contains($0.id) }.count
    }
    
    private var isFullySelected: Bool {
        selectedCount == courses.count && !courses.isEmpty
    }
    
    private var isPartiallySelected: Bool {
        selectedCount > 0 && selectedCount < courses.count
    }
    
    // Style Helpers
    private var headerColor: Color {
        switch item {
        case .standard: return .purple
        case .elective: return .teal
        }
    }
    
    private var headerIcon: String {
        switch item {
        case .standard: return "arrow.triangle.branch"
        case .elective: return "star.fill"
        }
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
                        
                        Text("\(selectedCount)/\(courses.count) ausgewählt")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Toggle All Button
                    Button {
                        onToggleBranch()
                    } label: {
                        Image(systemName: isFullySelected ? "checkmark.circle.fill" : (isPartiallySelected ? "minus.circle.fill" : "circle"))
                            .font(.title2)
                            .foregroundStyle(isFullySelected ? .green : (isPartiallySelected ? .orange : .secondary.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    
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
                        Button {
                            onToggleCourse(course.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedCourseIds.contains(course.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.body)
                                    .foregroundStyle(selectedCourseIds.contains(course.id) ? .green : .secondary.opacity(0.4))
                                
                                Text(course.name)
                                    .font(.subheadline)
                                    .foregroundStyle(selectedCourseIds.contains(course.id) ? .primary : .secondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.leading, 34)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
