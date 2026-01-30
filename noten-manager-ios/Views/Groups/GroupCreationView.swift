import SwiftUI

struct GroupCreationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedSubjects: Set<String> = []
    @State private var manualSubjectsList: [String] = []
    @State private var newManualSubject: String = ""
    @State private var selectedClassId: String? = nil
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Area
                    VStack(spacing: 4) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                            .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                        
                        Text("Neue Gruppe erstellen")
                            .font(.title3.weight(.bold))
                            .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                        
                        Text("Teile Noten und Termine mit anderen Studenten.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                    }
                    .padding(.top, 16)

                    // Group Name Input
                    SettingsCard(
                        title: "Gruppenname",
                        subtitle: "Wie soll die Gruppe heißen?",
                        systemImage: "pencil.line",
                        accent: .indigo
                    ) {
                        TextField("Name", text: $name)
                            .font(.title3)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)

                    // Class Selection
                    SettingsCard(
                        title: "Zu Klasse hinzufügen",
                        subtitle: "Optional: Gruppe einer Klasse zuordnen",
                        systemImage: "rectangle.stack.badge.person.crop.fill",
                        accent: .indigo
                    ) {
                        Picker("Klasse wählen", selection: $selectedClassId) {
                            Text("Keine Klasse").tag(String?.none)
                            ForEach(store.classIds, id: \.self) { cid in
                                Text(store.classNames[cid] ?? "Unbekannt").tag(String?.some(cid))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.22, offset: 12)
                    
                    // Subject Selection
                    SettingsCard(
                        title: "Fächer auswählen",
                        subtitle: "Aus vorhandenen Fächern wählen",
                        systemImage: "book.closed.fill",
                        accent: .cyan
                    ) {
                        if store.availableSubjectsForNewGroup().isEmpty {
                            Text("Keine verfügbaren Fächer zum Teilen.")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(store.availableSubjectsForNewGroup().enumerated()), id: \.element.name) { index, subj in
                                    let isSelected = selectedSubjects.contains(subj.name)
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if isSelected {
                                                selectedSubjects.remove(subj.name)
                                            } else {
                                                selectedSubjects.insert(subj.name)
                                            }
                                        }
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                    } label: {
                                        HStack {
                                            Text(subj.name)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(isSelected ? Color.cyan : .secondary.opacity(0.5))
                                        }
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if index < store.availableSubjectsForNewGroup().count - 1 {
                                        Divider()
                                            .padding(.leading, 4)
                                    }
                                }
                            }
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)

                    // Manual Subjects
                    SettingsCard(
                        title: "Fächer manuell hinzufügen",
                        subtitle: "Namen einzeln hinzufügen",
                        systemImage: "plus.circle.fill",
                        accent: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if !manualSubjectsList.isEmpty {
                                FlowLayout(spacing: 8) {
                                    ForEach(manualSubjectsList, id: \.self) { subj in
                                        HStack(spacing: 4) {
                                            Text(subj)
                                                .font(.subheadline.weight(.medium))
                                            Button {
                                                withAnimation {
                                                    manualSubjectsList.removeAll { $0 == subj }
                                                }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.15))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            
                            HStack {
                                TextField("Z.B. Mathe", text: $newManualSubject)
                                    .font(.body)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.formInputBackground)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                    )
                                    .onSubmit { addManualSubject() }
                                
                                Button {
                                    addManualSubject()
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.headline)
                                        .padding(12)
                                        .background(Circle().fill(Color.orange.opacity(0.2)))
                                        .foregroundStyle(.orange)
                                }
                                .disabled(newManualSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.28, offset: 12)
                    
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .softFadeIn(enabled: true)
                    }
                    
                    // Create Button
                    Button {
                        Task { await createGroup() }
                    } label: {
                        if isCreating {
                            ProgressView()
                                .tint(.indigo)
                        } else {
                            Text("Gruppe erstellen")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    .softFadeIn(enabled: animationsOn, delay: 0.3, offset: 12)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(isDark ? .white : .black)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @MainActor
    private func createGroup() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        
        do {
            var subjectsList = Array(selectedSubjects)
            for m in manualSubjectsList {
                if !subjectsList.contains(m) {
                    subjectsList.append(m)
                }
            }
            
            // Auch das aktuell Getippte hinzufügen, falls noch nicht in der Liste
            let currentManual = newManualSubject.trimmingCharacters(in: .whitespacesAndNewlines)
            if !currentManual.isEmpty && !subjectsList.contains(currentManual) {
                subjectsList.append(currentManual)
            }
            
            let groupId = try await store.createSharedGroup(name: trimmed, subjects: subjectsList)
            
            if let classId = selectedClassId {
                try? await store.addGroupToClass(classId: classId, groupId: groupId)
            }
            
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
    
    private func addManualSubject() {
        let trimmed = newManualSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if !manualSubjectsList.contains(trimmed) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                manualSubjectsList.append(trimmed)
            }
        }
        newManualSubject = ""
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

