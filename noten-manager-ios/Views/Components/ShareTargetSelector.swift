import SwiftUI

struct ShareTargetSelector: View {
    @EnvironmentObject var store: GradesStore
    @Binding var shareWithGroup: Bool
    @Binding var selectedGroupIds: Set<String>
    @Binding var selectedClassIds: Set<String>
    // New: Course Selection
    @Binding var selectedCourseIds: Set<String>
    
    // Courses filtered and passed from parent
    var availableCourses: [Course] = []
    
    // Optional: Highlight groups/courses that are auto-selected (e.g. by subject match)
    var autoSelectedGroupIds: Set<String> = []
    var autoSelectedCourseIds: Set<String> = []
    
    var body: some View {
        SettingsCard(
            title: "Sichtbarkeit & Teilen",
            subtitle: shareWithGroup ? "Wird mit ausgewählten Kurse/Gruppen geteilt" : "Nur für dich sichtbar",
            systemImage: shareWithGroup ? "person.3.fill" : "lock.fill",
            accent: shareWithGroup ? .indigo : .secondary
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 16) {
                    // Main Toggle
                    Toggle(isOn: $shareWithGroup.animation(.snappy)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mit Kursen/Gruppen teilen")
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
                        if store.courses.isEmpty && store.groupIds.isEmpty && store.classIds.isEmpty {
                            // No groups available
                            HStack(spacing: 12) {
                                Image(systemName: "person.3.slash.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Keine Kurse oder Gruppen")
                                        .font(.headline)
                                    Text("Du bist noch keinen Kursen beigetreten.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 8)
                        } else {
                            // Selection Area
                            VStack(alignment: .leading, spacing: 20) {
                                
                                // 1. Courses Section (Branch Level)
                                if !availableCourses.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Klassen / Zweige", systemImage: "macwindow.on.rectangle")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        
                                        // Courses filtered by parent. Sort by label.
                                        let uniqueCourses = availableCourses.sorted { c1, c2 in
                                            courseLabel(for: c1) < courseLabel(for: c2)
                                        }
                                        
                                        FlowLayout(spacing: 8) {
                                            ForEach(uniqueCourses, id: \.id) { course in
                                                CourseSelectionChip(
                                                    course: course,
                                                    label: courseLabel(for: course),
                                                    isSelected: selectedCourseIds.contains(course.id),
                                                    isAutoSelected: autoSelectedCourseIds.contains(course.id)
                                                ) {
                                                    toggleCourse(course.id)
                                                }
                                            }
                                        }
                                    }
                                }
                                
                                // 2. Classes Section (Legacy/Groups)
                                if !store.classIds.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Label("Klassen (Gruppen)", systemImage: "rectangle.stack.fill")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        
                                        // Deduplicate class IDs to prevent crashes
                                        let uniqueClassIds = Array(Set(store.classIds)).sorted()
                                        FlowLayout(spacing: 8) {
                                            ForEach(uniqueClassIds, id: \.self) { cid in
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
                                
                                // 3. Groups Section (Legacy & Social)
                                 let classAssociatedGroupIds = Set(store.classDetails.values.flatMap(\.groupIds))
                                 let hiddenGroupIds = store.migratedGroupIds.union(classAssociatedGroupIds)
                                 let visibleGroupIds = store.groupIds.filter { !hiddenGroupIds.contains($0) }
                                 
                                 let socialGroupIds = visibleGroupIds.filter { store.groupTypes[$0] == "social" }
                                 let legacyGroupIds = visibleGroupIds.filter { store.groupTypes[$0] != "social" }
                                 
                                 if !socialGroupIds.isEmpty {
                                     VStack(alignment: .leading, spacing: 10) {
                                         Label("Soziale Gruppen", systemImage: "person.2.fill")
                                             .font(.footnote.weight(.semibold))
                                             .foregroundStyle(.secondary)
                                         
                                         let sortedSocial = socialGroupIds.sorted { (store.groupNames[$0] ?? "").localizedCaseInsensitiveCompare(store.groupNames[$1] ?? "") == .orderedAscending }
                                         FlowLayout(spacing: 8) {
                                             ForEach(sortedSocial, id: \.self) { gid in
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
                                 
                                 if !legacyGroupIds.isEmpty {
                                     VStack(alignment: .leading, spacing: 10) {
                                         Label("Themengruppen (Fächer)", systemImage: "person.3.fill")
                                             .font(.footnote.weight(.semibold))
                                             .foregroundStyle(.secondary)
                                         
                                         let sortedLegacy = legacyGroupIds.sorted { (store.groupNames[$0] ?? "").localizedCaseInsensitiveCompare(store.groupNames[$1] ?? "") == .orderedAscending }
                                         FlowLayout(spacing: 8) {
                                             ForEach(sortedLegacy, id: \.self) { gid in
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
                                        .padding(.top, 2)
                                    Text("Geteilte Einträge sind für alle Mitglieder sichtbar.")
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
    
    private func toggleCourse(_ id: String) {
        if selectedCourseIds.contains(id) {
            selectedCourseIds.remove(id)
        } else {
            selectedCourseIds.insert(id)
        }
    }
    
    private func toggleClass(_ cid: String) {
        if selectedClassIds.contains(cid) {
            selectedClassIds.remove(cid)
        } else {
            selectedClassIds.insert(cid)
        }
    }
    
    private func toggleGroup(_ gid: String) {
        if selectedGroupIds.contains(gid) {
            selectedGroupIds.remove(gid)
        } else {
            selectedGroupIds.insert(gid)
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
    
    private func courseLabel(for course: Course) -> String {
        if let classId = course.classId, let className = store.classNames[classId] {
            switch course.type {
            case .mandatory:
                return className
            case .branch(let branchName):
                return "\(className) (\(branchName))"
            case .elective:
                return "\(course.name) (\(className))"
            }
        }
        return course.name
    }
}

struct CourseSelectionChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let course: Course
    let label: String
    let isSelected: Bool
    let isAutoSelected: Bool
    let action: () -> Void
    
    private var backgroundColor: Color {
        if isSelected {
            return .indigo
        }
        // Safe alternative to Color.formInputBackground avoiding UI dynamic provider crash
        if colorScheme == .dark {
            return Color(red: 0.16, green: 0.16, blue: 0.18)
        } else {
            return Color(uiColor: .systemGray6)
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .lineLimit(1)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
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
                    .fill(backgroundColor)
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

// MARK: - Subviews

struct ClassSelectionChip: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    let classId: String
    let isSelected: Bool
    let action: () -> Void
    
    private var backgroundColor: Color {
        if isSelected {
            return .indigo
        }
        if colorScheme == .dark {
            return Color(red: 0.16, green: 0.16, blue: 0.18)
        } else {
            return Color(uiColor: .systemGray6)
        }
    }
    
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
                    .fill(backgroundColor)
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
    @Environment(\.colorScheme) private var colorScheme
    let groupId: String
    let isSelected: Bool
    let isAutoSelected: Bool
    let isImplicitlySelected: Bool
    let action: () -> Void
    
    private var backgroundColor: Color {
        if isSelected {
            return .indigo
        }
        if isImplicitlySelected {
            return .indigo.opacity(0.3)
        }
        if colorScheme == .dark {
            return Color(red: 0.16, green: 0.16, blue: 0.18)
        } else {
            return Color(uiColor: .systemGray6)
        }
    }
    
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
                    .fill(backgroundColor)
            )
            .foregroundStyle(isSelected ? .white : (isImplicitlySelected ? .white : .primary))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected || isImplicitlySelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isImplicitlySelected)
    }
}
