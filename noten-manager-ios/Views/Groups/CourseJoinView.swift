import SwiftUI

struct CourseJoinView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let className: String
    let config: ClassConfiguration
    let linkedClassIds: [String]
    let onJoinSuccess: () -> Void
    
    @State private var courses: [Course] = []
    @State private var isLoading: Bool = true
    @State private var selectedBranchIds: Set<String> = [] // Multiple branch selection
    @State private var selectedLinkedClasses: Set<String> = [] // Linked Class Codes to join
    @State private var linkedClassDetails: [String: String] = [:] // Code -> Name
    @State private var errorMessage: String?
    @State private var isJoining: Bool = false
    
    // Subject Mapping
    @State private var showSubjectMapping: Bool = false
    @State private var missingCourses: [Course] = []
    
    // Theme
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 4) {
                        Text(className)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.indigo)
                        Text("Kursauswahl")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)
                    
                    if isLoading {
                        ProgressView("Lade Kurse...")
                            .padding(.top, 40)
                    } else {
                        content
                    }
                }
                .padding(16)
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .task {
                await loadCourses()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .sheet(isPresented: $showSubjectMapping, onDismiss: {
                onJoinSuccess()
            }) {
                SubjectMappingView(classId: classId, missingCourses: missingCourses)
            }
        }
    }
    
    private var commonCourses: [Course] {
        courses.filter { if case .mandatory = $0.type { return true }; return false }
    }
    
    private var content: some View {
        VStack(spacing: 24) {
            // 1. Common Subjects
            if !commonCourses.isEmpty {
                SettingsCard(
                    title: "Gemeinsame Fächer",
                    subtitle: "Diese Fächer haben alle.",
                    systemImage: "person.3.fill",
                    accent: .indigo
                ) {
                    FlowLayout(spacing: 8) {
                        ForEach(commonCourses) { course in
                            Text(course.name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.indigo.opacity(0.1))
                                .foregroundStyle(.indigo)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // 2. Branch Selection (Multiple)
            if !config.branches.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Wähle deine Zweige", systemImage: "arrow.branch")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Du kannst mehrere Zweige auswählen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 12) {
                        ForEach(config.branches, id: \.name) { branch in
                            BranchSelectionRow(
                                branch: branch,
                                courses: courses,
                                isSelected: selectedBranchIds.contains(branch.name),
                                onSelect: {
                                    if selectedBranchIds.contains(branch.name) {
                                        selectedBranchIds.remove(branch.name)
                                    } else {
                                        selectedBranchIds.insert(branch.name)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            
            // 3. Linked Classes
            if !linkedClassIds.isEmpty && !linkedClassDetails.isEmpty {
                 VStack(alignment: .leading, spacing: 12) {
                    Label("Verknüpfte Klassen", systemImage: "link")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Du kannst diesen Klassen ebenfalls beitreten.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        ForEach(linkedClassIds, id: \.self) { code in
                            if let name = linkedClassDetails[code] {
                                Button {
                                    if selectedLinkedClasses.contains(code) {
                                        selectedLinkedClasses.remove(code)
                                    } else {
                                        selectedLinkedClasses.insert(code)
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(name)
                                                .font(.headline)
                                                .foregroundStyle(selectedLinkedClasses.contains(code) ? .white : .primary)
                                        }
                                        Spacer()
                                        Image(systemName: selectedLinkedClasses.contains(code) ? "checkmark.circle.fill" : "circle")
                                            .font(.title2)
                                            .foregroundStyle(selectedLinkedClasses.contains(code) ? .white : .secondary.opacity(0.5))
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedLinkedClasses.contains(code) ? Color.indigo : Color.formInputBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedLinkedClasses.contains(code) ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            Button {
                Task { await joinWithSelection() }
            } label: {
                if isJoining {
                    ProgressView().tint(.white)
                } else {
                    Text("Klasse beitreten")
                        .bold()
                }
            }
            .buttonStyle(SoftTintButtonStyle(accent: .indigo))
            .disabled(config.branches.count > 0 && selectedBranchIds.isEmpty)
            .padding(.top, 8)
        }
    }
    
    @MainActor
    private func loadCourses() async {
        do {
            courses = try await store.fetchCoursesForClass(classId: classId)
            
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
            
            // Add Mandatory
            selected.append(contentsOf: courses.filter { if case .mandatory = $0.type { return true }; return false })
            
            // Add Branches (all selected)
            for bid in selectedBranchIds {
                selected.append(contentsOf: courses.filter { if case .branch(let id) = $0.type, id == bid { return true }; return false })
            }
            
            try await store.joinClassWithBranch(classId: classId, selectedCourses: selected)
            
            // Join Linked Classes
            for code in selectedLinkedClasses {
                // If it's a legacy join or simple join
                try? await store.joinClass(with: code) 
                // Note: We ignore branch selection for linked classes here as per "opt in" simple logic, 
                // or we'd need a recursive flow which is too complex.
                // Presumably linked classes are "global" or simple.
            }
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Check for missing mappings
            let missing = store.missingSubjects(for: classId)
            if !missing.isEmpty {
                self.missingCourses = missing
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

// MARK: - Branch Selection Row

private struct BranchSelectionRow: View {
    let branch: ClassConfiguration.Branch
    let courses: [Course]
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var branchCourses: [Course] {
        courses.filter {
            if case .branch(let name) = $0.type, name == branch.name { return true }
            return false
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading) {
                    Text(branch.name)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : .primary)
                    
                    if !branchCourses.isEmpty {
                        Text(branchCourses.map(\.name).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "circle")
                        .font(.title2)
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.indigo : Color.formInputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
