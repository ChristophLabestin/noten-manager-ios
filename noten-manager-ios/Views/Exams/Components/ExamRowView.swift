import SwiftUI

struct ExamRowView<Actions: View>: View {
    let exam: Exam
    @EnvironmentObject var store: GradesStore
    
    // Callbacks
    var onToggleReminder: (() -> Void)?
    var onMarkCompleted: (() -> Void)?
    var onUndoCompleted: (() -> Void)?
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
        onTap: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.exam = exam
        self.showStatusIcon = showStatusIcon
        self.onToggleReminder = onToggleReminder
        self.onMarkCompleted = onMarkCompleted
        self.onUndoCompleted = onUndoCompleted
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
        HStack(alignment: .top, spacing: 16) {
            // Main Content Area (Button)
            Button {
                onTap?()
            } label: {
                HStack(alignment: .top, spacing: 16) {
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(resolvedSubjectName.uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            
                            if exam.isShared {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
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
                        
                        if let context = contextName {
                            Text(context)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        
                        // Reminder Indicator
                        if let reminder = exam.reminderAt, reminder > Date() {
                            HStack(spacing: 4) {
                                Image(systemName: "bell.fill")
                                    .font(.caption2)
                                Text(reminderTimeFormatter.string(from: reminder))
                                    .font(.caption2)
                            }
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 3. Status Indicator / Menu (Right)
            VStack(alignment: .trailing, spacing: 12) {
                Menu {
                    actions
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(90))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)


            }
        }
        .padding(12)
        .background(Color.formSectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Helpers
    
    private var resolvedSubjectName: String {
        if exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "fachreferat",
           let related = exam.subjectKey, !related.isEmpty {
            return "Fachreferat • \(related)"
        }
        return store.resolveLocalSubjectNameForExam(exam) ?? exam.subjectName
    }
    
    private var contextName: String? {
        guard exam.isShared else { return nil }
        let name = store.resolveContextName(groupId: exam.groupId, courseId: exam.courseId)
            .replacingOccurrences(of: resolvedSubjectName, with: "")
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
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
