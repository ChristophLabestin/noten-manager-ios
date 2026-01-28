import SwiftUI

struct ExamRowView<Actions: View>: View {
    let exam: Exam
    @EnvironmentObject var store: GradesStore
    
    // Callbacks
    var onToggleReminder: (() -> Void)?
    var onMarkCompleted: (() -> Void)?
    var onUndoCompleted: (() -> Void)?
    var onAddGrade: (() -> Void)?
    var onTap: (() -> Void)?
    
    // Config
    var showStatusIcon: Bool
    
    // Actions Builder for Menu
    @ViewBuilder let actions: Actions
    
    init(
        exam: Exam,
        showStatusIcon: Bool = true,
        onToggleReminder: (() -> Void)? = nil,
        onMarkCompleted: (() -> Void)? = nil,
        onUndoCompleted: (() -> Void)? = nil,
        onAddGrade: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.exam = exam
        self.showStatusIcon = showStatusIcon
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
        if isOverdueAttention { return .red }
        if exam.isCompleted { return .green }
        return .blue
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            
            // 1. Date Box (Left)
            VStack(spacing: 0) {
                Text(examDayFormatter.string(from: exam.date))
                    .font(.title3.weight(.bold))
                Text(examMonthFormatter.string(from: exam.date).uppercased())
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(accentColor)
            .frame(width: 50, height: 50)
            .background(accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // 2. Info Content (Center)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(resolvedSubjectName.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    if isSharedExam {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                         
                         if let sharing = sharingLabel {
                            Text("• \(sharing.replacingOccurrences(of: "Geteilt mit ", with: ""))")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                         }
                    }
                    
                    if exam.hasTime {
                        Text("• \(reminderTimeFormatter.string(from: exam.date))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(exam.title)
                    .font(.headline)
                    .foregroundStyle(exam.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                    .strikethrough(exam.isCompleted)
            }
            
            Spacer(minLength: 0)
            
            // 3. Status Indicator / Menu (Right)
            VStack(alignment: .trailing, spacing: 12) {
                // Reminder Bell
                if !exam.isCompleted {
                    Button {
                        onToggleReminder?()
                    } label: {
                        Image(systemName: exam.reminderAt != nil ? "bell.fill" : "bell")
                            .font(.subheadline)
                            .foregroundStyle(exam.reminderAt != nil ? .orange : Color.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                // Add Grade Button (Only for waiting exams)
                if let onAddGrade = onAddGrade, !exam.isCompleted, !exam.isActive {
                     Button {
                         onAddGrade()
                     } label: {
                         Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                     }
                     .buttonStyle(.plain)
                } else if let onUndo = onUndoCompleted, exam.isCompleted {
                     Button {
                         onUndo()
                     } label: {
                         Image(systemName: "arrow.uturn.backward.circle")
                              .font(.system(size: 28))
                              .foregroundStyle(.orange)
                     }
                     .buttonStyle(.plain)
                } else if showStatusIcon {
                    // Fallback Status Icon if standard view
                     Image(systemName: exam.isCompleted ? "checkmark.circle.fill" : "circle")
                         .font(.title2)
                         .foregroundStyle(exam.isCompleted ? .green : .secondary)
                }
            }
        }
        .padding(12)
        .background(Color.formSectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu { actions }
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
}
