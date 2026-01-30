import SwiftUI
import FirebaseAuth

struct GroupMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var className: String = ""
    @State private var selectedGroups: Set<String> = []
    @State private var branchNames: [String: String] = [:] // groupId -> branchName/targetName
    @State private var isWahlpflicht: [String: Bool] = [:] // groupId -> true if Wahlpflicht
    @State private var hasSchulaufgabe: [String: Bool] = [:] // groupId -> true if has Schulaufgaben
    @State private var isMerging: Bool = false
    @State private var errorMessage: String?
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    // Only show unmigrated independent groups owned by the user
    private var availableGroups: [String] {
        let uid = Auth.auth().currentUser?.uid
        let allClassGroups = Set(store.classDetails.values.flatMap { $0.groupIds })
        return store.groupIds.filter { gid in
            !allClassGroups.contains(gid) &&
            !store.migratedGroupIds.contains(gid) &&
            store.groupOwners[gid] == uid
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                        
                        Text("Gruppen zusammenführen")
                            .font(.title3.weight(.bold))
                        
                        Text("Wähle mehrere Gruppen aus, um sie zu einer Klasse zusammenzuführen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    
                    // Class Name
                    SettingsCard(
                        title: "Klassenname",
                        subtitle: "Name der neuen Klasse",
                        systemImage: "pencil",
                        accent: .indigo
                    ) {
                        TextField("z.B. 12b", text: $className)
                            .font(.title3)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.formInputBackground)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }
                    
                    // Group Selection
                    SettingsCard(
                        title: "Gruppen auswählen",
                        subtitle: "\(selectedGroups.count) von \(availableGroups.count) ausgewählt",
                        systemImage: "person.3.fill",
                        accent: .cyan
                    ) {
                        if availableGroups.isEmpty {
                            Text("Keine unabhängigen Gruppen verfügbar.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(availableGroups.enumerated()), id: \.element) { index, groupId in
                                    GroupSelectionRow(
                                        groupId: groupId,
                                        groupName: store.groupNames[groupId] ?? "Unbenannt",
                                        isSelected: selectedGroups.contains(groupId),
                                        branchName: branchNames[groupId] ?? store.groupNames[groupId] ?? "",
                                        isWahlpflicht: isWahlpflicht[groupId] ?? false,
                                        hasSA: hasSchulaufgabe[groupId] ?? true,
                                        onToggle: {
                                            if selectedGroups.contains(groupId) {
                                                selectedGroups.remove(groupId)
                                                branchNames.removeValue(forKey: groupId)
                                                isWahlpflicht.removeValue(forKey: groupId)
                                                hasSchulaufgabe.removeValue(forKey: groupId)
                                            } else {
                                                selectedGroups.insert(groupId)
                                                branchNames[groupId] = store.groupNames[groupId] ?? ""
                                                isWahlpflicht[groupId] = false // Default to Branch
                                                hasSchulaufgabe[groupId] = true // Default to with SA
                                            }
                                        },
                                        onBranchNameChange: { newName in
                                            branchNames[groupId] = newName
                                        },
                                        onTypeToggle: { isWP in
                                            isWahlpflicht[groupId] = isWP
                                        },
                                        onSAToggle: { hasSA in
                                            hasSchulaufgabe[groupId] = hasSA
                                        }
                                    )
                                    
                                    if index < availableGroups.count - 1 {
                                        Divider()
                                            .opacity(0.5)
                                            .padding(.leading, 54)
                                    }
                                }
                            }
                            .background(Color.formInputBackground.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    
                    // Merge Button
                    Button {
                        Task { await mergeGroups() }
                    } label: {
                        if isMerging {
                            ProgressView().tint(.indigo)
                        } else {
                            Text("Klasse erstellen")
                        }
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                    .disabled(className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedGroups.isEmpty || isMerging)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .keyboardDismissToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        ToolbarIcon(symbol: "chevron.down", showDot: false)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
    
    @MainActor
    private func mergeGroups() async {
        isMerging = true
        errorMessage = nil
        
        let groups = selectedGroups.map { gid in
            (
                groupId: gid,
                targetName: branchNames[gid] ?? store.groupNames[gid] ?? "Unbenannt",
                isWahlpflicht: isWahlpflicht[gid] ?? false,
                hasSchulaufgabe: hasSchulaufgabe[gid] ?? true
            )
        }
        
        do {
            _ = try await store.mergeGroupsIntoClass(className: className, groups: groups)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
        
        isMerging = false
    }
}

// MARK: - Group Selection Row

private struct GroupSelectionRow: View {
    let groupId: String
    let groupName: String
    let isSelected: Bool
    var branchName: String
    var isWahlpflicht: Bool
    var hasSA: Bool
    let onToggle: () -> Void
    let onBranchNameChange: (String) -> Void
    let onTypeToggle: (Bool) -> Void
    let onSAToggle: (Bool) -> Void
    
    @State private var localBranchName: String = ""
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? (isWahlpflicht ? .orange : .green) : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupName)
                        .font(.subheadline.weight(.semibold))
                    Text("Legacy Gruppe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    HStack(spacing: 4) {
                        Picker("Typ", selection: Binding(
                            get: { isWahlpflicht },
                            set: { onTypeToggle($0) }
                        )) {
                            Text("Zweig").tag(false)
                            Text("Wahlpflicht").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                        .labelsHidden()
                        
                        Button {
                            onSAToggle(!hasSA)
                        } label: {
                            Text("SA")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(hasSA ? Color.indigo : Color.secondary.opacity(0.2))
                                .foregroundStyle(hasSA ? .white : .secondary)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            if isSelected {
                HStack {
                    Text(isWahlpflicht ? "WP-Name:" : "Zweig-Name:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextField("Name", text: $localBranchName)
                        .font(.subheadline)
                        .padding(8)
                        .background(Color.formInputBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: localBranchName) { _, newValue in
                            onBranchNameChange(newValue)
                        }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            localBranchName = branchName
        }
    }
}
