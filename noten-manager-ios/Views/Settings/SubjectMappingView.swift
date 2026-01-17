import SwiftUI

struct SubjectMappingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    let missingCourses: [Course]
    
    @State private var mappings: [String: String] = [:] // courseId -> selectedSubjectName (or "CREATE")
    @State private var createdSubjectNames: [String: String] = [:] // courseId -> newName
    
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 44))
                            .foregroundStyle(.indigo)
                        
                        Text("Fächer zuordnen")
                            .font(.title2.weight(.bold))
                        
                        Text("Für einige Fächer hast du noch keinen passenden Eintrag. Bitte ordne sie zu oder erstelle neue.")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    .padding(.top, 24)
                    
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
                                )
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    Button {
                        Task { await saveMappings() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Speichern & Fertig")
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
        }
        .interactiveDismissDisabled() 
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
                        try await store.addSubjectToFirestore(name: name, type: 0, date: Date()) // Default written/0
                        // Map it
                        try await store.saveCourseMapping(courseId: course.id, subjectName: name)
                    }
                } else {
                    // Mapping to existing
                    try await store.saveCourseMapping(courseId: course.id, subjectName: selection)
                }
            }
            
            dismiss()
        } catch {
            errorMessage = "Fehler beim Speichern: \(error.localizedDescription)"
        }
        
        isSaving = false
    }
}

private struct MappingCard: View {
    let course: Course
    let existingSubjects: [Subject]
    @Binding var selection: String
    @Binding var newName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.indigo)
                Text(course.name)
                    .font(.headline)
            }
            
            Picker("Aktion", selection: $selection) {
                Text("Neu erstellen").tag("CREATE")
                Divider()
                ForEach(existingSubjects) { subject in
                    Text("Zuordnen: \(subject.name)").tag(subject.name)
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .padding(8)
            .background(Color.formInputBackground)
            .cornerRadius(8)
            
            if selection == "CREATE" {
                TextField("Fachname", text: $newName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading, 4)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
