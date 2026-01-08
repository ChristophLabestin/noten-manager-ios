import SwiftUI

struct GroupCreationView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedSubjects: Set<String> = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var animationsOn: Bool { store.animationsEnabled }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Group Name Input
                    SettingsCard(
                        title: "Gruppenname",
                        subtitle: "Wie soll die Gruppe heißen?",
                        systemImage: "pencil.line",
                        accent: .indigo
                    ) {
                        TextField("Name", text: $name)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                    
                    // Subject Selection
                    SettingsCard(
                        title: "Fächer auswählen",
                        subtitle: "Optional: Noten teilen",
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
                    .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                    
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
                    .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .navigationTitle("Neue Gruppe")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity)
            )
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
    }
    
    @MainActor
    private func createGroup() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        
        do {
            let subjects = selectedSubjects.isEmpty ? [] : Array(selectedSubjects)
             _ = try await store.createSharedGroup(name: trimmed, subjects: subjects)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}
