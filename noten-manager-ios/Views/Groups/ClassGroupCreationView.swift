import SwiftUI

struct ClassGroupCreationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    let classId: String
    
    @State private var creationMode: Int = 0 // 0: Existing Subject, 1: Manual
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Mode 0: Select Subject
    @State private var selectedSubjectName: String = ""
    
    // Mode 1: Manual
    @State private var manualSubjectName: String = ""
    @State private var manualSubjectType: Int = 0 // 0: Standard
    
    private var availableSubjects: [String] {
        // Simple list of user's subject names
        store.subjects.map { $0.name }.sorted()
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Picker("Modus", selection: $creationMode) {
                    Text("Aus Fächern").tag(0)
                    Text("Manuell").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .padding(.bottom)
                
                if creationMode == 0 {
                    Section {
                        if availableSubjects.isEmpty {
                             Text("Keine eigenen Fächer gefunden.")
                                 .foregroundStyle(.secondary)
                        } else {
                            Picker("Fach wählen", selection: $selectedSubjectName) {
                                ForEach(availableSubjects, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                        }
                    } header: {
                        Text("Fach auswählen")
                    } footer: {
                        Text("Wähle ein Fach aus deiner Liste, um eine Gruppe dafür zu erstellen.")
                    }
                } else {
                    Section {
                        TextField("Fachname", text: $manualSubjectName)
                        // Type picker can be expanded later if Subject types are dynamic
                    } header: {
                        Text("Neues Fach erstellen")
                    } footer: {
                        Text("Erstelle eine Gruppe für ein Fach, das du noch nicht angelegt hast.")
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Gruppe erstellen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Erstellen") {
                        Task { await createGroup() }
                    }
                    .disabled(isLoading || (creationMode == 1 && manualSubjectName.isEmpty) || (creationMode == 0 && availableSubjects.isEmpty))
                }
            }
            .onAppear {
                if let first = availableSubjects.first {
                    selectedSubjectName = first
                }
            }
        }
    }
    
    private func createGroup() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let groupId: String
            
            if creationMode == 0 {
                // Use Existing Subject logic
                // store.createSharedGroup takes [String]
                if selectedSubjectName.isEmpty { selectedSubjectName = availableSubjects.first ?? "" }
                guard !selectedSubjectName.isEmpty else { 
                    errorMessage = "Bitte wähle ein Fach."
                    isLoading = false
                    return 
                }
                groupId = try await store.createSharedGroup(name: selectedSubjectName, subjects: [selectedSubjectName])
            } else {
                // Manual
                groupId = try await store.createManualGroup(groupName: manualSubjectName, subjectName: manualSubjectName, type: manualSubjectType)
            }
            
            // Add to Class
            try await store.addGroupToClass(classId: classId, groupId: groupId)
            
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}
