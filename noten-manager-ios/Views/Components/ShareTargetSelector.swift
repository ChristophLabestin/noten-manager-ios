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
            subtitle: shareWithGroup ? "Wird mit ausgewählten Klassen/Kursen geteilt" : "Nur für dich sichtbar",
            systemImage: shareWithGroup ? "person.3.fill" : "lock.fill",
            accent: shareWithGroup ? .indigo : .secondary
        ) {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Segmented Visibility Picker
                Picker("Sichtbarkeit", selection: $shareWithGroup.animation(.snappy)) {
                    Label("Privat", systemImage: "lock.fill").tag(false)
                    Label("Teilen", systemImage: "person.3.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)
                
                if shareWithGroup {
                    SettingsSectionBox {
                        VStack(alignment: .leading, spacing: 20) {
                            if store.courses.isEmpty && store.classIds.isEmpty {
                                // Empty State
                                HStack(spacing: 12) {
                                    Image(systemName: "person.2.slash.fill")
                                        .font(.title2)
                                        .foregroundStyle(.secondary.opacity(0.5))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Keine Ziele verfügbar")
                                            .font(.headline)
                                        Text("Tritt erst einer Klasse oder einem Kurs bei.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                            } else {
                                // Summary Info
                                if !selectedCourseIds.isEmpty || !selectedClassIds.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "info.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.indigo)
                                        let classCount = selectedClassIds.count
                                        let courseCount = selectedCourseIds.count
                                        let text = [
                                            classCount > 0 ? "\(classCount) \(classCount == 1 ? "Klasse" : "Klassen")" : nil,
                                            courseCount > 0 ? "\(courseCount) \(courseCount == 1 ? "Kurs" : "Kurse")" : nil
                                        ].compactMap { $0 }.joined(separator: " & ")
                                        
                                        Text("Geteilt mit \(text)")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                }

                                // 2. Classes Section (Primary Classes)
                                if !store.classIds.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Meine Klassen")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                        
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
                                
                                // 3. Courses Section (Specific Subjects/Branches)
                                if !availableCourses.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Teilnehmende Kurse")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                        
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
                                
                                // 4. Social Groups Section
                                let socialGroupIds = store.groupIds.filter { store.groupTypes[$0] == "social" }.sorted()
                                if !socialGroupIds.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Soziale Gruppen")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .textCase(.uppercase)
                                        
                                        FlowLayout(spacing: 8) {
                                            ForEach(socialGroupIds, id: \.self) { gid in
                                                GroupSelectionChip(
                                                    groupId: gid,
                                                    isSelected: selectedGroupIds.contains(gid),
                                                    isAutoSelected: autoSelectedGroupIds.contains(gid),
                                                    isImplicitlySelected: false
                                                ) {
                                                    toggleGroup(gid)
                                                }
                                            }
                                        }
                                    }
                                }

                                Text("Geteilte Einträge sind für alle Mitglieder des Ziels sichtbar.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("Dieser Eintrag ist nur für dich sichtbar und wird nicht synchronisiert.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.vertical, 4)
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
    
    private func courseLabel(for course: Course) -> String {
        let uniqueClassIds = Set(store.classIds)
        let showClassName = uniqueClassIds.count > 1
        
        if let classId = course.classId, let className = store.classNames[classId], let type = course.type {
            switch type {
            case .mandatory:
                return showClassName ? className : "Klasse"
            case .branch(let branchName):
                return showClassName ? "\(className) (\(branchName))" : branchName
            case .elective:
                return showClassName ? "\(course.name) (\(className))" : course.name
            case .wahlpflicht(let groupId):
                 let groupName = store.wahlpflichtfachGroupNames[groupId] ?? "Wahlpflicht"
                 return showClassName ? "\(groupName) (\(className))" : groupName
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
