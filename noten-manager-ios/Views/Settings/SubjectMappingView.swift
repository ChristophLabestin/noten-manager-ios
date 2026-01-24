import SwiftUI

struct SubjectMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let missingCourses: [Course]
    
    @State private var mappings: [String: String] = [:] // courseId -> selectedSubjectName (or "CREATE")
    @State private var createdSubjectNames: [String: String] = [:] // courseId -> newName
    @State private var matchConfidences: [String: Double] = [:] // courseId -> confidence
    
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var didAutoPopulate: Bool = false
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
    /// Number of courses that have a suggested match (not CREATE)
    private var suggestedMatchCount: Int {
        mappings.values.filter { $0 != "CREATE" }.count
    }
    
    /// All courses that will create new subjects
    private var createCount: Int {
        mappings.values.filter { $0 == "CREATE" }.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    // Quick Summary
                    if didAutoPopulate {
                        quickSummary
                    }
                    
                    // Course mapping cards
                    VStack(spacing: 16) {
                        ForEach(missingCourses) { course in
                            MappingCard(
                                course: course,
                                existingSubjects: store.subjects,
                                selection: Binding(
                                    get: { mappings[course.id] ?? "CREATE" },
                                    set: { mappings[course.id] = $0 }
                                ),
                                newName: Binding(
                                    get: { createdSubjectNames[course.id] ?? course.name },
                                    set: { createdSubjectNames[course.id] = $0 }
                                ),
                                confidence: matchConfidences[course.id]
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    // Confirm button
                    Button {
                        Task { await saveMappings() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Alle übernehmen", systemImage: "checkmark.circle.fill")
                                .bold()
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Später") {
                        dismiss()
                    }
                    .font(.subheadline)
                }
            }
            .onAppear {
                autoPopulateSuggestions()
            }
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 44))
                .foregroundStyle(.indigo)
            
            Text("Fächer zuordnen")
                .font(.title2.weight(.bold))
            
            Text("Bitte bestätige die Zuordnung deiner Fächer.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.top, 24)
    }
    
    private var quickSummary: some View {
        VStack(spacing: 8) {
            if suggestedMatchCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.green)
                    Text("\(suggestedMatchCount) automatisch erkannt")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            
            if createCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.orange)
                    Text("\(createCount) neu erstellen")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Logic
    
    private func autoPopulateSuggestions() {
        guard !didAutoPopulate else { return }
        
        for course in missingCourses {
            if let match = store.suggestSubjectMatch(for: course) {
                // Pre-select the suggested subject
                mappings[course.id] = match.subject.name
                matchConfidences[course.id] = match.confidence
            } else {
                // No match - offer to create
                mappings[course.id] = "CREATE"
                createdSubjectNames[course.id] = course.name
            }
        }
        
        didAutoPopulate = true
    }
    
    @MainActor
    private func saveMappings() async {
        isSaving = true
        errorMessage = nil
        
        do {
            for course in missingCourses {
                let selection = mappings[course.id] ?? "CREATE"
                
                if selection == "CREATE" {
                    let name = createdSubjectNames[course.id] ?? course.name
                    // Double check if subject exists now (maybe created in previous loop iteration?)
                    if store.subjects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        // Just map it
                        try await store.saveCourseMapping(courseId: course.id, subjectName: name)
                    } else {
                        // Create Subject
                        try await store.addSubjectToFirestore(name: name, type: 0, date: Date())
                        // Map it
                        try await store.saveCourseMapping(courseId: course.id, subjectName: name)
                    }
                } else {
                    // Mapping to existing subject
                    try await store.saveCourseMapping(courseId: course.id, subjectName: selection)
                }
            }
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            dismiss()
        } catch {
            errorMessage = "Fehler beim Speichern: \(error.localizedDescription)"
        }
        
        isSaving = false
    }
}

// MARK: - Mapping Card

private struct MappingCard: View {
    let course: Course
    let existingSubjects: [Subject]
    @Binding var selection: String
    @Binding var newName: String
    let confidence: Double?
    
    private var isMatched: Bool {
        selection != "CREATE"
    }
    
    private var confidenceLabel: String? {
        guard let conf = confidence, isMatched else { return nil }
        if conf >= 0.9 {
            return "Perfekte Übereinstimmung"
        } else if conf >= 0.7 {
            return "Gute Übereinstimmung"
        } else {
            return "Mögliche Übereinstimmung"
        }
    }
    
    private var confidenceColor: Color {
        guard let conf = confidence else { return .secondary }
        if conf >= 0.9 { return .green }
        if conf >= 0.7 { return .blue }
        return .orange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with course name
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isMatched ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: isMatched ? "checkmark.circle.fill" : "plus.circle.fill")
                        .foregroundStyle(isMatched ? .green : .orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.headline)
                    
                    if let label = confidenceLabel {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(confidenceColor)
                    }
                }
                
                Spacer()
            }
            
            // Picker for action
            Picker("Aktion", selection: $selection) {
                if isMatched {
                    // Show matched option first
                    Text("→ \(selection)").tag(selection)
                    Divider()
                }
                Text("Neu erstellen").tag("CREATE")
                Divider()
                ForEach(existingSubjects.filter { $0.name != selection }) { subject in
                    Text(subject.name).tag(subject.name)
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .padding(8)
            .background(Color.formInputBackground)
            .cornerRadius(8)
            
            // Text field for new subject name
            if selection == "CREATE" {
                TextField("Fachname", text: $newName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMatched ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
