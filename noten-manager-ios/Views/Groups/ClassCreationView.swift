import SwiftUI

struct ClassCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var name: String = ""
    @State private var commonSubjects: [String] = ["Mathematik", "Deutsch", "Englisch"]
    @State private var newCommonSubject: String = ""
    
    struct BranchInput: Identifiable {
        let id = UUID()
        var name: String
        var subjects: [String]
        var newSubject: String = ""
    }
    @State private var branches: [BranchInput] = []
    
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    // Subject Mapping after creation
    @State private var showSubjectMapping: Bool = false
    @State private var createdClassId: String?
    @State private var missingCourses: [Course] = []
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "plus.rectangle.fill.on.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                        
                        Text("Neue Klasse erstellen")
                            .font(.title3.weight(.bold))
                        
                        Text("Definiere Fächer und Zweige zentral.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    
                    // 1. Name
                    SettingsCard(
                        title: "Klassenname",
                        subtitle: "Z.B. '10b' oder 'Mathe LK'",
                        systemImage: "pencil",
                        accent: .indigo
                    ) {
                        TextField("Name", text: $name)
                            .font(.title3)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }
                    
                    // 2. Common Subjects
                    SettingsCard(
                        title: "Gemeinsame Fächer",
                        subtitle: "Fächer, die jeder in der Klasse hat",
                        systemImage: "book.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            FlowLayout(spacing: 8) {
                                ForEach(commonSubjects, id: \.self) { subject in
                                    HStack(spacing: 4) {
                                        Text(subject)
                                        Button {
                                            commonSubjects.removeAll { $0 == subject }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption2.bold())
                                        }
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.indigo.opacity(0.1))
                                    .foregroundStyle(.indigo)
                                    .clipShape(Capsule())
                                }
                            }
                            
                            HStack {
                                TextField("Neues Fach hinzufügen...", text: $newCommonSubject)
                                    .onSubmit { addCommonSubject() }
                                    .submitLabel(.done)
                                
                                Button {
                                    addCommonSubject()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.indigo)
                                        .font(.title2)
                                }
                                .disabled(newCommonSubject.isEmpty)
                            }
                            .padding(10)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    
                    // 3. Branches
                    VStack(spacing: 16) {
                        ForEach($branches) { $branch in
                            BranchEditCard(branch: $branch) {
                                branches.removeAll { $0.id == branch.id }
                            }
                        }
                        
                        Button {
                            withAnimation {
                                branches.append(BranchInput(name: "", subjects: []))
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
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    // Create Button
                    Button {
                        Task { await createClass() }
                    } label: {
                        if isCreating {
                            ProgressView().tint(.indigo)
                        } else {
                            Text("Klasse erstellen")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
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
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showSubjectMapping, onDismiss: {
            dismiss()
        }) {
            if let classId = createdClassId {
                SubjectMappingView(classId: classId, missingCourses: missingCourses)
                    .environmentObject(store)
            }
        }
    }
    
    private func addCommonSubject() {
        let trimmed = newCommonSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !commonSubjects.contains(trimmed) {
            withAnimation {
                commonSubjects.append(trimmed)
                newCommonSubject = ""
            }
        }
    }
    
    @MainActor
    private func createClass() async {
        isCreating = true
        errorMessage = nil
        
        // Validation
        if branches.contains(where: { $0.name.isEmpty }) {
            errorMessage = "Bitte gib allen Zweigen einen Namen."
            isCreating = false
            return
        }
        
        let config = GradesStore.ClassCreationConfiguration(
            name: name,
            commonSubjects: commonSubjects,
            branches: branches.map { b in
                GradesStore.ClassCreationConfiguration.BranchConfig(
                    name: b.name,
                    subjects: b.subjects
                )
            }
        )
        
        do {
            let classId = try await store.createClassWithCourses(config: config)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Check for missing subject mappings
            let missing = store.missingSubjects(for: classId)
            if !missing.isEmpty {
                self.createdClassId = classId
                self.missingCourses = missing
                self.showSubjectMapping = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isCreating = false
    }
}

struct BranchEditCard: View {
    @Binding var branch: ClassCreationView.BranchInput
    let onDelete: () -> Void
    
    var body: some View {
        SettingsCard(
            title: branch.name.isEmpty ? "Neuer Zweig" : branch.name,
            subtitle: "Zweig-spezifische Fächer",
            systemImage: "arrow.branch",
            accent: .orange
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Branch Name
                TextField("Zweigname (z.B. Wirtschaft)", text: $branch.name)
                    .font(.headline)
                    .padding(10)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Divider()
                
                // Subjects
                FlowLayout(spacing: 8) {
                    ForEach(branch.subjects, id: \.self) { subject in
                        HStack(spacing: 4) {
                            Text(subject)
                            Button {
                                branch.subjects.removeAll { $0 == subject }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.bold())
                            }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    }
                }
                
                HStack {
                    TextField("Fach hinzufügen...", text: $branch.newSubject)
                        .font(.subheadline)
                        .onSubmit { addSubject() }
                    
                    Button {
                        addSubject()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .disabled(branch.newSubject.isEmpty)
                }
                .padding(8)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Delete Branch
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Zweig entfernen")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private func addSubject() {
        let trimmed = branch.newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !branch.subjects.contains(trimmed) {
            withAnimation {
                branch.subjects.append(trimmed)
                branch.newSubject = ""
            }
        }
    }
}
    

