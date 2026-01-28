import SwiftUI

struct ClassEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    let classId: String
    
    @State private var className: String = ""
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Branch editing state
    @State private var editingBranchId: String?
    @State private var editingBranchName: String = ""
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    private var schoolClass: SchoolClass? {
        store.classDetails[classId]
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.indigo)
                            .padding(.bottom, 4)
                        
                        Text("Klasse bearbeiten")
                            .font(.title3.weight(.bold))
                        
                        Text("Hier kannst du den Namen, Zweige und verknüpfte Gruppen verwalten.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 16)
                    
                    // General Section
                    SettingsCard(
                        title: "Allgemein",
                        subtitle: "Grundlegende Einstellungen",
                        systemImage: "gearshape.fill",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Klassenname")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            TextField("Name (z.B. 10a)", text: $className)
                                .font(.body)
                                .padding(12)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    
                    // Branches Section
                    if let branches = schoolClass?.config?.branches, !branches.isEmpty {
                        SettingsCard(
                            title: "Zweige",
                            subtitle: "Verwalte die Zweige dieser Klasse",
                            systemImage: "arrow.triangle.branch",
                            accent: .purple
                        ) {
                            if branches.isEmpty {
                                Text("Keine Zweige vorhanden.")
                                    .foregroundStyle(.secondary)
                                    .padding()
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                                        BranchEditRow(
                                            branchName: branch.name,
                                            isEditing: editingBranchId == branch.name,
                                            editName: $editingBranchName,
                                            onEdit: {
                                                editingBranchId = branch.name
                                                editingBranchName = branch.name
                                            },
                                            onSave: {
                                                Task { await updateBranchName(oldName: branch.name) }
                                            },
                                            onCancel: {
                                                editingBranchId = nil
                                            },
                                            onDelete: {
                                                Task { await deleteBranch(name: branch.name) }
                                            }
                                        )
                                        
                                        if index < branches.count - 1 {
                                            Divider()
                                                .opacity(0.5)
                                                .padding(.leading, 12)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Electives Section
                    if let linkedGroupIds = schoolClass?.linkedWahlpflichtfachGroupIds, !linkedGroupIds.isEmpty {
                        SettingsCard(
                            title: "Wahlpflichtfächer",
                            subtitle: "Verknüpfte Gruppen",
                            systemImage: "star.fill",
                            accent: .teal
                        ) {
                            VStack(spacing: 0) {
                                ForEach(Array(linkedGroupIds.enumerated()), id: \.element) { index, groupId in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(store.groupNames[groupId] ?? "Unbenannt")
                                                .font(.subheadline.weight(.medium))
                                            Text("Gruppe")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            Task { await unlinkGroup(groupId: groupId) }
                                        } label: {
                                            Image(systemName: "link.badge.minus")
                                                .foregroundStyle(.red)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 12)
                                    
                                    if index < linkedGroupIds.count - 1 {
                                        Divider()
                                            .opacity(0.5)
                                            .padding(.leading, 12)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Danger Zone
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Gefahrenzone")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.leading, 4)
                        
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Klasse löschen", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.top, 8)
                    
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding()
                    }
                }
                .padding(16)
            }
            .background(ThemedBackground(isDark: isDark, isFeminine: isFeminine, intensity: store.themeBackgroundIntensity))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        Task { await saveChanges() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                if let cls = schoolClass {
                    className = cls.name
                }
            }
            .alert("Klasse löschen?", isPresented: $showDeleteConfirmation) {
                Button("Abbrechen", role: .cancel) { }
                Button("Löschen", role: .destructive) {
                    Task { await deleteClass() }
                }
            } message: {
                Text("Möchtest du die Klasse \"\(schoolClass?.name ?? "")\" wirklich unwiderruflich löschen? Alle assoziierten Daten werden entfernt.")
            }
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func saveChanges() async {
        guard !className.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        
        do {
            if className != schoolClass?.name {
                try await store.updateClass(classId: classId, name: className)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    @MainActor
    private func updateBranchName(oldName: String) async {
        let newName = editingBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != oldName else {
            editingBranchId = nil
            return
        }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await store.updateBranch(classId: classId, oldName: oldName, newName: newName)
            editingBranchId = nil
            // Refresh logic handled by listeners usually, but local state might need help if store isn't immediate
        } catch {
            errorMessage = "Fehler beim Umbenennen: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func deleteBranch(name: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.removeBranch(classId: classId, branchName: name)
        } catch {
            errorMessage = "Fehler beim Löschen: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func unlinkGroup(groupId: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await store.unlinkWahlpflichtfachGroup(classId: classId, groupId: groupId)
        } catch {
            errorMessage = "Fehler beim Trennen: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func deleteClass() async {
        isSaving = true
        await store.archiveClass(classId: classId)
        dismiss()
    }
}

// MARK: - Subviews

struct BranchEditRow: View {
    let branchName: String
    let isEditing: Bool
    @Binding var editName: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            if isEditing {
                TextField("Name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(onSave)
                
                Button(action: onSave) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                }
                
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            } else {
                Text(branchName)
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.indigo)
                }
                .padding(.trailing, 8)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }
}
