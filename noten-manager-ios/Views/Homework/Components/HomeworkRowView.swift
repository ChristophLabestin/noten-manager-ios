import SwiftUI

struct HomeworkRowView<Actions: View>: View {
    let homework: Homework
    @EnvironmentObject var store: GradesStore
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Callbacks
    var onToggleReminder: (() -> Void)?
    var onToggleCompletion: (() -> Void)?
    var onTap: (() -> Void)?
    
    // Config
    var showStatusBadge: Bool
    var showCompletionToggle: Bool
    var showReminderButton: Bool
    
    // Actions Builder for Menu
    @ViewBuilder let actions: Actions
    
    init(
        homework: Homework,
        showStatusBadge: Bool = true,
        showCompletionToggle: Bool = true,
        showReminderButton: Bool = true,
        onToggleReminder: (() -> Void)? = nil,
        onToggleCompletion: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.homework = homework
        self.showStatusBadge = showStatusBadge
        self.showCompletionToggle = showCompletionToggle
        self.showReminderButton = showReminderButton
        self.onToggleReminder = onToggleReminder
        self.onToggleCompletion = onToggleCompletion
        self.onTap = onTap
        self.actions = actions()
    }
    
    private var treatedCompleted: Bool {
        homework.isCompleted
    }
    
    private var badge: (text: String, color: Color, systemImage: String)? {
        let cal = Calendar.current
        if treatedCompleted {
            return ("Erledigt", .green, "checkmark.circle.fill")
        }
        guard let due = homework.dueDate else { return nil }
        
        let startToday = cal.startOfDay(for: Date())
        if cal.isDateInToday(due) {
            return ("Fällig", .red, "clock.fill")
        }
        if cal.isDateInTomorrow(due) {
            return ("Morgen", .orange, "calendar")
        }
        if due < startToday {
            return ("Überfällig", .red, "exclamationmark.triangle.fill")
        }
        
        return ("Geplant", .blue, "calendar")
    }
    
    private var accentColor: Color {
        badge?.color ?? .blue
    }
    
    private var resolvedSubjectName: String {
        let fallback = homework.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            return "Allgemein"
        }
        return store.resolveLocalSubjectNameForHomework(homework) ?? homework.subjectName
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            
            // 1. Left Side: Date Block
            dateBlock
            
            // 2. Info Content (Center)
            VStack(alignment: .leading, spacing: 6) {
                // Top Meta Row
                HStack(spacing: 6) {
                    Text(resolvedSubjectName.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accentColor.opacity(0.8))
                    
                    if homework.isShared || homework.courseId != nil || homework.groupId != nil {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                         
                         let contextName = store.resolveContextName(groupId: homework.groupId, courseId: homework.courseId)
                         if !contextName.isEmpty {
                             Text(contextName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.blue)
                         }
                    } else if homework.isImportedFromShare {
                         Image(systemName: "link")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }
                
                // Title
                Text(homework.title)
                    .font(.headline)
                    .foregroundStyle(treatedCompleted ? .secondary : .primary)
                    .strikethrough(treatedCompleted)
                    .lineLimit(2)
                
                // Bottom Row: Pill + Note
                HStack(spacing: 8) {
                    if showStatusBadge, let badge = badge, !treatedCompleted {
                        PillBadge(
                            text: badge.text,
                            systemImage: badge.systemImage,
                            foreground: badge.color,
                            background: badge.color.opacity(0.12)
                        )
                        .scaleEffect(0.85, anchor: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    if let personalNote = store.userNoteForHomework(homework), !personalNote.isEmpty {
                        HStack(spacing: 4) {
                            if badge == nil || treatedCompleted || !showStatusBadge {
                                Image(systemName: "note.text")
                                    .font(.caption2)
                            }
                            Text(personalNote)
                               .font(.caption2)
                               .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
            
            Spacer(minLength: 0)
            
            // 3. Actions (Right)
            if showReminderButton || showCompletionToggle {
                VStack(alignment: .trailing, spacing: 14) {
                    // Reminder Bell
                    if showReminderButton, !treatedCompleted {
                        Button {
                            onToggleReminder?()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(homework.reminderAt != nil ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08))
                                    .frame(width: 34, height: 34)
                                Image(systemName: homework.reminderAt != nil ? "bell.fill" : "bell")
                                    .font(.subheadline)
                                    .foregroundStyle(homework.reminderAt != nil ? .orange : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Completion Toggle
                    if showCompletionToggle {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                onToggleCompletion?()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(treatedCompleted ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                                    .frame(width: 36, height: 36)
                                Image(systemName: treatedCompleted ? "checkmark.circle.fill" : "circle")
                                     .font(.system(size: 24))
                                     .foregroundStyle(treatedCompleted ? .green : Color.secondary.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(
            GradeCardStyle.surface(colorScheme: colorScheme, theme: store.theme, accent: accentColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            GradeCardStyle.border(colorScheme: colorScheme, accent: accentColor, cornerRadius: 20)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu { actions }
        .softFadeIn(enabled: true)
    }
    
    @ViewBuilder
    private var dateBlock: some View {
        if let due = homework.dueDate {
            VStack(spacing: 0) {
                Text(hwDayFormatter.string(from: due))
                    .font(.title3.weight(.bold))
                Text(hwMonthFormatter.string(from: due).uppercased())
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(
                LinearGradient(
                    colors: [accentColor, accentColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: accentColor.opacity(0.3), radius: 4, x: 0, y: 2)
            .opacity(treatedCompleted ? 0.6 : 1.0)
        } else {
             // Fallback Icon Block
            ZStack {
                 RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                 Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
            .opacity(treatedCompleted ? 0.6 : 1.0)
        }
    }
    
    // MARK: - Formatters
    
    private let hwDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd"
        return fmt
    }()
    
    private let hwMonthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt
    }()
}
