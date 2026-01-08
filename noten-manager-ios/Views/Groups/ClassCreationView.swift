import SwiftUI

struct ClassCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var name: String = ""
    @State private var selectedGroupIds: Set<String> = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    
    private var independentGroups: [String] {
        let allClassGroups = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { !allClassGroups.contains($0) }
    }
    
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
                            .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 12)
                        
                        Text("Neue Klasse erstellen")
                            .font(.title3.weight(.bold))
                            .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)
                        
                        Text("Verwalte mehrere Gruppen zentral in einer Klasse.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .softFadeIn(enabled: animationsOn, delay: 0.15, offset: 12)
                    }
                    .padding(.top, 16)
                    
                    // Input
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.2, offset: 12)
                    
                    // Independent Groups Selection
                    if !independentGroups.isEmpty {
                        SettingsCard(
                            title: "Gruppen hinzufügen",
                            subtitle: "Unabhängige Gruppen zuordnen",
                            systemImage: "person.3.fill",
                            accent: .indigo
                        ) {
                            VStack(spacing: 0) {
                                ForEach(Array(independentGroups.enumerated()), id: \.element) { index, gid in
                                    let isSelected = selectedGroupIds.contains(gid)
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            if isSelected {
                                                selectedGroupIds.remove(gid)
                                            } else {
                                                selectedGroupIds.insert(gid)
                                            }
                                        }
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(store.groupNames[gid] ?? "Unbekannte Gruppe")
                                                    .foregroundStyle(.primary)
                                                Text("\(store.groupMemberIds[gid]?.count ?? 0) Mitglieder")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(isSelected ? Color.indigo : .secondary.opacity(0.5))
                                        }
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if index < independentGroups.count - 1 {
                                        Divider()
                                            .padding(.leading, 4)
                                    }
                                }
                            }
                        }
                        .softFadeIn(enabled: animationsOn, delay: 0.22, offset: 12)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    // Button
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
                    .softFadeIn(enabled: animationsOn, delay: 0.25, offset: 12)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
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
    private func createClass() async {
        isCreating = true
        errorMessage = nil
        do {
            let classId = try await store.createClass(name: name)
            
            // Add selected groups
            for gid in selectedGroupIds {
                try? await store.addGroupToClass(classId: classId, groupId: gid)
            }
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        isCreating = false
    }
}
