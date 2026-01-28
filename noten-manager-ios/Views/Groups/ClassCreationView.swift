import SwiftUI

struct ClassCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var name: String = ""
    struct SubjectInput: Identifiable, Hashable {
        let id = UUID()
        var name: String
        var hasSchulaufgabe: Bool = true
    }
    
    @State private var commonSubjects: [SubjectInput] = [
        SubjectInput(name: "Mathematik"),
        SubjectInput(name: "Deutsch"),
        SubjectInput(name: "Englisch")
    ]
    @State private var newCommonSubject: String = ""
    
    struct SubjectGroupInput: Identifiable {
        let id = UUID()
        var name: String
        var subjects: [SubjectInput]
        var newSubject: String = ""
    }
    
    @State private var branches: [SubjectGroupInput] = []
    @State private var electives: [SubjectGroupInput] = []
    
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    // Subject Mapping after creation
    @State private var showSubjectMapping: Bool = false
    @State private var createdClassId: String?
    @State private var joinedCourses: [Course] = []
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    
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
                        
                        Text("Definiere Fächer, Zweige und Wahlpflichtfächer.")
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
                            VStack(spacing: 8) {
                                ForEach($commonSubjects) { $subject in
                                    SubjectCreationRow(
                                        name: subject.name,
                                        hasSA: $subject.hasSchulaufgabe,
                                        onDelete: {
                                            commonSubjects.removeAll { $0.id == subject.id }
                                        }
                                    )
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
                    
                    // 3. Branches (Zweige)
                    VStack(spacing: 16) {
                        ForEach($branches) { $branch in
                            SubjectGroupEditCard(
                                name: $branch.name,
                                subjects: $branch.subjects,
                                newSubject: $branch.newSubject,
                                titlePlaceholder: "Zweigname (z.B. Wirtschaft)",
                                subtitle: "Zweig-spezifische Fächer",
                                icon: "arrow.branch",
                                color: .orange,
                                onDelete: { branches.removeAll { $0.id == branch.id } }
                            )
                        }
                        
                        Button {
                            withAnimation {
                                branches.append(SubjectGroupInput(name: "", subjects: []))
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
                    
                    // 4. Electives (Wahlpflichtfächer)
                    VStack(spacing: 16) {
                        ForEach($electives) { $elective in
                            SubjectGroupEditCard(
                                name: $elective.name,
                                subjects: $elective.subjects,
                                newSubject: $elective.newSubject,
                                titlePlaceholder: "Name (z.B. Informatik)",
                                subtitle: "Fächer dieser Gruppe",
                                icon: "star.fill",
                                color: .teal,
                                onDelete: { electives.removeAll { $0.id == elective.id } }
                            )
                        }
                        
                        Button {
                            withAnimation {
                                electives.append(SubjectGroupInput(name: "", subjects: []))
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
        .sheet(isPresented: $showSubjectMapping, onDismiss: {
            dismiss()
        }) {
            if let classId = createdClassId {
                SubjectMappingView(classId: classId, courses: joinedCourses)
                    .environmentObject(store)
            }
        }
    }
    
    private func addCommonSubject() {
        let trimmed = newCommonSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !commonSubjects.contains(where: { $0.name == trimmed }) {
            withAnimation {
                commonSubjects.append(SubjectInput(name: trimmed))
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
        if electives.contains(where: { $0.name.isEmpty }) {
            errorMessage = "Bitte gib allen Wahlpflichtfächern einen Namen."
            isCreating = false
            return
        }
        
        let config = GradesStore.ClassCreationConfiguration(
            name: name,
            commonSubjects: commonSubjects.map { GradesStore.ClassCreationConfiguration.SubjectConfig(name: $0.name, hasSchulaufgabe: $0.hasSchulaufgabe) },
            branches: branches.map { b in
                GradesStore.ClassCreationConfiguration.BranchConfig(
                    name: b.name,
                    subjects: b.subjects.map { GradesStore.ClassCreationConfiguration.SubjectConfig(name: $0.name, hasSchulaufgabe: $0.hasSchulaufgabe) }
                )
            },
            wahlpflichtSubjects: electives.map { e in
                GradesStore.ClassCreationConfiguration.WahlpflichtConfig(
                    name: e.name,
                    subjects: e.subjects.map { GradesStore.ClassCreationConfiguration.SubjectConfig(name: $0.name, hasSchulaufgabe: $0.hasSchulaufgabe) }
                )
            }
        )
        
        do {
            let classId = try await store.createClassWithCourses(config: config)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Check for missing subject mappings (should be none for new class, but good to keep)
            let missing = store.missingSubjects(for: classId)
            if !missing.isEmpty {
                self.createdClassId = classId
                self.joinedCourses = missing
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

// MARK: - Reusable Edit Card

struct SubjectGroupEditCard: View {
    @Binding var name: String
    @Binding var subjects: [ClassCreationView.SubjectInput]
    @Binding var newSubject: String
    
    let titlePlaceholder: String
    let subtitle: String
    let icon: String
    let color: Color
    let onDelete: () -> Void
    
    var body: some View {
        SettingsCard(
            title: name.isEmpty ? "Neu" : name,
            subtitle: subtitle,
            systemImage: icon,
            accent: color
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Name Input
                TextField(titlePlaceholder, text: $name)
                    .font(.headline)
                    .padding(10)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Divider()
                
                if !subjects.isEmpty {
                    VStack(spacing: 8) {
                        ForEach($subjects) { $subject in
                            SubjectCreationRow(
                                name: subject.name,
                                hasSA: $subject.hasSchulaufgabe,
                                color: color,
                                onDelete: {
                                    subjects.removeAll { $0.id == subject.id }
                                }
                            )
                        }
                    }
                }
                
                // Add Subject Input
                HStack {
                    TextField("Fach hinzufügen...", text: $newSubject)
                        .font(.subheadline)
                        .onSubmit { addSubject() }
                        .submitLabel(.done)
                    
                    Button {
                        addSubject()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(color)
                    }
                    .disabled(newSubject.isEmpty)
                }
                .padding(8)
                .background(Color.formInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Delete Button
                Button(role: .destructive, action: onDelete) {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                        Text("Entfernen")
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
        let trimmed = newSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !subjects.contains(where: { $0.name == trimmed }) {
            withAnimation {
                subjects.append(ClassCreationView.SubjectInput(name: trimmed))
                newSubject = ""
            }
        }
    }
}

struct SubjectCreationRow: View {
    let name: String
    @Binding var hasSA: Bool
    var color: Color = .indigo
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                
                Text(hasSA ? "Mit Schulaufgaben" : "ohne Schulaufgaben")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    hasSA.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("SA")
                        .font(.system(size: 10, weight: .black))
                    Image(systemName: hasSA ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(hasSA ? color.opacity(0.15) : Color.secondary.opacity(0.1))
                .foregroundStyle(hasSA ? color : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(hasSA ? color.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.7))
                    .padding(8)
                    .background(Color.red.opacity(0.05))
                    .clipShape(Circle())
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.formInputBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }
}

