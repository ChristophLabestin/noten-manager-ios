import SwiftUI

struct ShareTargetSelector: View {
    @EnvironmentObject var store: GradesStore
    @Binding var shareWithGroup: Bool
    @Binding var selectedGroupIds: Set<String>
    @Binding var selectedClassIds: Set<String>
    
    // Optional: Highlight groups that are auto-selected (e.g. by subject match)
    var autoSelectedGroupIds: Set<String> = []
    
    var body: some View {
        SettingsCard(
            title: "Sichtbarkeit & Teilen",
            subtitle: shareWithGroup ? "Wird mit ausgewählten Gruppen geteilt" : "Nur für dich sichtbar",
            systemImage: shareWithGroup ? "person.3.fill" : "lock.fill",
            accent: shareWithGroup ? .indigo : .secondary
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 16) {
                    // Main Toggle
                    Toggle(isOn: $shareWithGroup.animation(.snappy)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mit Gruppe teilen")
                                .font(.body)
                                .foregroundStyle(.primary)
                            if !shareWithGroup {
                                Text("Aktivieren, um diesen Eintrag für andere sichtbar zu machen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.indigo)
                    
                    if shareWithGroup {
                        if store.groupIds.isEmpty && store.classIds.isEmpty {
                            // No groups available
                            HStack(spacing: 12) {
                                Image(systemName: "person.3.slash.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Keine Gruppen gefunden")
                                        .font(.headline)
                                    Text("Du bist noch keinen Gruppen oder Klassen beigetreten.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        } else {
                            // Selection Area
                            VStack(alignment: .leading, spacing: 20) {
                                
                                // Classes Section
                                if !store.classIds.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Klassen", systemImage: "rectangle.stack.fill")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        
                                        FlowLayout(spacing: 8) {
                                            ForEach(store.classIds, id: \.self) { cid in
                                                ClassSelectionChip(
                                                    classId: cid,
                                                    isSelected: selectedClassIds.contains(cid)
                                                ) {
                                                    toggleClass(cid)
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Groups Section
                                if !store.groupIds.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Gruppen", systemImage: "person.3.fill")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        
                                        FlowLayout(spacing: 8) {
                                            ForEach(store.groupIds, id: \.self) { gid in
                                                GroupSelectionChip(
                                                    groupId: gid,
                                                    isSelected: selectedGroupIds.contains(gid),
                                                    isAutoSelected: autoSelectedGroupIds.contains(gid),
                                                    isImplicitlySelected: isGroupImplicitlySelected(gid)
                                                ) {
                                                    toggleGroup(gid)
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // Info Footer
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.indigo)
                                    Text("Geteilte Einträge sind für alle Mitglieder der ausgewählten Gruppen sichtbar und können von diesen bearbeitet werden (z.B. Notizen).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color.indigo.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }
    
    private func toggleClass(_ cid: String) {
        withAnimation(.snappy) {
            if selectedClassIds.contains(cid) {
                selectedClassIds.remove(cid)
            } else {
                selectedClassIds.insert(cid)
            }
        }
    }
    
    private func toggleGroup(_ gid: String) {
        withAnimation(.snappy) {
            if selectedGroupIds.contains(gid) {
                selectedGroupIds.remove(gid)
            } else {
                selectedGroupIds.insert(gid)
            }
        }
    }
    
    private func isGroupImplicitlySelected(_ gid: String) -> Bool {
        // Check if this group belongs to any selected class
        for cid in selectedClassIds {
             if let details = store.classDetails[cid], details.groupIds.contains(gid) {
                 return true
             }
        }
        return false
    }
}

// MARK: - Subviews

struct ClassSelectionChip: View {
    @EnvironmentObject var store: GradesStore
    let classId: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(store.classNames[classId] ?? "Klasse")
                    .lineLimit(1)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.indigo : Color.formInputBackground)
            )
            .foregroundStyle(isSelected ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GroupSelectionChip: View {
    @EnvironmentObject var store: GradesStore
    let groupId: String
    let isSelected: Bool
    let isAutoSelected: Bool
    let isImplicitlySelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(store.groupNames[groupId] ?? "Gruppe")
                    .lineLimit(1)
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                } else if isImplicitlySelected {
                     Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                } else if isAutoSelected {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.indigo : (isImplicitlySelected ? Color.indigo.opacity(0.3) : Color.formInputBackground))
            )
            .foregroundStyle(isSelected ? .white : (isImplicitlySelected ? .white : .primary))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected || isImplicitlySelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isImplicitlySelected) // Maybe disable explicit toggle if implicitly selected? Or allow overriding? 
        // User wants "share it seperately so i can share it with everyone in the class and/or with specific groups"
        // If I select a class, it shares with everyone in the class (all groups).
        // If I deselect a class, I might want to keep one group.
        // So they should be independent.
        // But if I select the class, the group is effectively selected.
        // Let's keep it simple: Class selection implies group selection backend-wise, but visual state can separate them.
        // If I select class, I show group as implicitly selected.
    }
}
