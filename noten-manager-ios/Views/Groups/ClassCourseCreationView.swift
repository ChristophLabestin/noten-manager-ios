import SwiftUI

struct ClassCourseCreationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    let classId: String
    let onCourseCreated: () -> Void
    
    @State private var courseName: String = ""
    @State private var selectedType: CourseType = .mandatory
    @State private var selectedBranchName: String = ""
    @State private var availableBranches: [String] = []
    @State private var gradingMode: GradingMode = .withSchulaufgaben
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kursname", text: $courseName)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Z.B. 'Mathematik' oder 'Physik'")
                }
                
                Section {
                    Picker("Typ", selection: $selectedType) {
                        Text("Pflichtfach (Alle)").tag(CourseType.mandatory)
                        if !availableBranches.isEmpty {
                            ForEach(availableBranches, id: \.self) { branch in
                                Text("Zweig: \(branch)").tag(CourseType.branch(branch))
                            }
                        }
                        Text("Wahlfach").tag(CourseType.elective)
                    }
                } header: {
                    Text("Kurstyp")
                } footer: {
                    Text("Pflichtfächer sind für alle sichtbar. Zweig-Kurse nur für Schüler des jeweiligen Zweigs.")
                }
                Section {
                    Picker("Notensystem", selection: $gradingMode) {
                        Text("Mit Schulaufgaben").tag(GradingMode.withSchulaufgaben)
                        Text("Ohne Schulaufgaben").tag(GradingMode.withoutSchulaufgaben)
                    }
                } header: {
                    Text("Bewertung")
                } footer: {
                    Text("Bestimmt, ob dieses Fach Schulaufgaben (große Leistungsnachweise) beinhaltet.")
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Neuer Kurs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        Task { await createCourse() }
                    }
                    .disabled(courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
            .task {
                await loadBranches()
            }
        }
    }
    
    private func loadBranches() async {
        do {
            let info = try await store.fetchClassInfo(with: classId)
            if let config = info.config {
                availableBranches = config.branches?.map { $0.name } ?? []
            }
        } catch {
            print("Failed to load class config: \(error)")
        }
    }
    
    private func createCourse() async {
        isCreating = true
        errorMessage = nil
        
        let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Bitte gib einen Namen ein."
            isCreating = false
            return
        }
        
        do {
            try await store.addCourseToClass(classId: classId, name: trimmedName, type: selectedType, gradingMode: gradingMode)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            onCourseCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isCreating = false
    }
}
