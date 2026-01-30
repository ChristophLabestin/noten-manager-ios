import SwiftUI

struct ExamRowView<Actions: View>: View {
    let exam: Exam
    @EnvironmentObject var store: GradesStore
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Callbacks
    var onToggleReminder: (() -> Void)?
    var onMarkCompleted: (() -> Void)?
    var onUndoCompleted: (() -> Void)?
    var onAddGrade: (() -> Void)?
    var onTap: (() -> Void)?
    
    // Config
    var showStatusIcon: Bool
    var showActions: Bool
    
    // Actions Builder for Menu
    @ViewBuilder let actions: Actions
    
    init(
        exam: Exam,
        showStatusIcon: Bool = true,
        showActions: Bool = true,
        onToggleReminder: (() -> Void)? = nil,
        onMarkCompleted: (() -> Void)? = nil,
        onUndoCompleted: (() -> Void)? = nil,
        onAddGrade: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.exam = exam
        self.showStatusIcon = showStatusIcon
        self.showActions = showActions
        self.onToggleReminder = onToggleReminder
        self.onMarkCompleted = onMarkCompleted
        self.onUndoCompleted = onUndoCompleted
        self.onAddGrade = onAddGrade
        self.onTap = onTap
        self.actions = actions()
    }
    
    private var isOverdueAttention: Bool {
        (exam.requiresGrade ?? true) && !exam.isCompleted && !exam.isActive
    }
    
    private var accentColor: Color {
        if isOverdueAttention { return .orange }
        if exam.isCompleted { return .green }
        return .blue
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            
            // 1. Date Block (Left)
            dateBlock
            
            // 2. Info Content (Center)
            VStack(alignment: .leading, spacing: 6) {
                // Top Meta Row
                HStack(spacing: 6) {
                    Text(resolvedSubjectName.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accentColor.opacity(0.8))
                    
                    if isSharedExam {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                         
                         if let sharing = sharingLabel {
                            Text(sharing.replacingOccurrences(of: "Geteilt mit ", with: ""))
                               .font(.system(size: 10, weight: .medium))
                               .foregroundStyle(.blue)
                         }
                    }
                }
                
                // Title
                Text(exam.title)
                    .font(.headline)
                    .foregroundStyle(exam.isCompleted ? .secondary : .primary)
                    .strikethrough(exam.isCompleted)
                    .lineLimit(2)
                
                // Date and Time Row
                Text("\(examDateFormatter.string(from: exam.date))\(exam.hasTime ? " • " + reminderTimeFormatter.string(from: exam.date) : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
            
            // 3. Actions (Right)
            if showActions {
                VStack(alignment: .trailing, spacing: 14) {
                    // Reminder Bell
                    if !exam.isCompleted {
                        Button {
                            onToggleReminder?()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(exam.reminderAt != nil ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08))
                                    .frame(width: 34, height: 34)
                                Image(systemName: exam.reminderAt != nil ? "bell.fill" : "bell")
                                    .font(.subheadline)
                                    .foregroundStyle(exam.reminderAt != nil ? .orange : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Add Grade Button (Only for overdue exams needing attention)
                    if let onAddGrade = onAddGrade, !exam.isCompleted, !exam.isActive {
                         Button {
                             onAddGrade()
                         } label: {
                             ZStack {
                                 Circle()
                                     .fill(Color.blue.opacity(0.15))
                                     .frame(width: 36, height: 36)
                                 Image(systemName: "pencil")
                                      .font(.system(size: 16, weight: .semibold))
                                      .foregroundStyle(.blue)
                             }
                         }
                         .buttonStyle(.plain)
                    } else if let onUndo = onUndoCompleted, exam.isCompleted {
                         Button {
                             onUndo()
                         } label: {
                             ZStack {
                                  Circle()
                                      .fill(Color.orange.opacity(0.15))
                                      .frame(width: 36, height: 36)
                                  Image(systemName: "arrow.uturn.backward")
                                       .font(.system(size: 16, weight: .semibold))
                                       .foregroundStyle(.orange)
                             }
                         }
                         .buttonStyle(.plain)
                    } else if showStatusIcon && exam.isCompleted {
                        // Status Icon (Only for completed exams)
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Image(systemName: "checkmark.circle.fill")
                                 .font(.system(size: 24))
                                 .foregroundStyle(.green)
                        }
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
    
    // MARK: - Date Block
    
    @ViewBuilder
    private var dateBlock: some View {
        VStack(spacing: 0) {
            Text(examDayFormatter.string(from: exam.date))
                .font(.title3.weight(.bold))
            Text(examMonthFormatter.string(from: exam.date).uppercased())
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
        .opacity(exam.isCompleted ? 0.6 : 1.0)
    }
    
    // MARK: - Helpers
    
    private var resolvedSubjectName: String {
        if exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fachreferat",
           let related = exam.subjectKey, !related.isEmpty {
            return "Fachreferat • \(related)"
        }
        return store.resolveLocalSubjectNameForExam(exam) ?? exam.subjectName
    }
    
    private var isSharedExam: Bool {
        exam.isShared || exam.courseId != nil || exam.groupId != nil || exam.classId != nil
    }
    
    private var sharingLabel: String? {
        guard isSharedExam else { return nil }
        let name = store.resolveContextName(groupId: exam.groupId, courseId: exam.courseId, classId: exam.classId)
        return name.isEmpty ? nil : "Geteilt mit \(name)"
    }
    
    // MARK: - Formatters
    
    private let examDayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd"
        return fmt
    }()
    
    private let examMonthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt
    }()
    
    private let reminderTimeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt
    }()
    
    private let examDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }()
}
