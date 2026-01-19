import SwiftUI
import FirebaseAuth
#if os(iOS)
import UIKit
#endif

struct HomeworkListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var visibleCompletedCount: Int = 5
    @State private var editingHomework: Homework? = nil
    @State private var reminderHomework: Homework? = nil
    @State private var shareURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var shareError: String? = nil
    @State private var detailHomework: Homework? = nil
    @State private var showAddHomeworkSheet: Bool = false
    private let noSubjectLabel = "Kein Fach"

    private var openHomeworks: [Homework] {
        linkedHomeworks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                let l = sortKey(for: lhs)
                let r = sortKey(for: rhs)
                if l.priority != r.priority { return l.priority < r.priority }
                return l.date < r.date
            }
    }

    private var completedHomeworks: [Homework] {
        linkedHomeworks
            .filter { $0.isCompleted }
            .sorted {
                let a = $0.dueDate ?? $0.createdAt
                let b = $1.dueDate ?? $1.createdAt
                return a > b
            }
    }

    private var linkedHomeworks: [Homework] {
        store.allHomeworks.filter { hw in
            // Immer anzeigen, wenn es eine Gruppen-Hausaufgabe ist (User ist ja bereits in der Gruppe, sonst wäre sie nicht in allHomeworks)
            if hw.isShared { return true }
            if hw.isImportedFromShare { return true }
            let cleanedSubject = hw.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedSubject.isEmpty || cleanedSubject == noSubjectLabel { return true }
            if let resolved = store.resolveLocalSubjectNameForHomework(hw),
               store.subjects.contains(where: { $0.name == resolved }) {
                return true
            }
            return store.subjects.contains(where: { $0.name == hw.subjectName })
        }
    }

    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.homeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }

    private func resolvedSubjectName(for hw: Homework) -> String {
        let fallback = hw.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            return noSubjectLabel
        }
        return store.resolveLocalSubjectNameForHomework(hw) ?? hw.subjectName
    }

    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Offene Hausaufgaben",
                        subtitle: "Aktuelle Aufgaben",
                        systemImage: "checklist",
                        accent: .indigo
                    ) {
                        if openHomeworks.isEmpty {
                            Text("Du hast aktuell keine offenen Hausaufgaben.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(openHomeworks) { hw in
                                    homeworkRow(hw)
                                }
                            }
                        }
                    }

                    if !completedHomeworks.isEmpty {
                        SettingsCard(
                            title: "Erledigt",
                            subtitle: "Abgeschlossen",
                            systemImage: "checkmark.seal.fill",
                            accent: .green
                        ) {
                            LazyVStack(spacing: 10) {
                                ForEach(Array(completedHomeworks.prefix(visibleCompletedCount))) { hw in
                                    homeworkRow(hw)
                                }
                                if completedHomeworks.count > visibleCompletedCount {
                                    Button {
                                        visibleCompletedCount += 5
                                    } label: {
                                        Text("Weitere 5 anzeigen")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(SoftTintButtonStyle(accent: .green))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Schließen")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddHomework()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Hausaufgabe hinzufügen")
                }
            }
            .onAppear { visibleCompletedCount = 5 }
            .sheet(item: $editingHomework) { hw in
                EditHomeworkView(homework: hw)
                    .environmentObject(store)
            }
            .sheet(item: $reminderHomework) { hw in
                LocalHomeworkReminderSheet(homework: hw)
                    .environmentObject(store)
            }
            .sheet(item: $detailHomework) { hw in
                HomeworkDetailSheet(homework: hw, onEdit: { editingHomework = $0 })
                    .environmentObject(store)
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareURL {
                    ShareSheet(activityItems: [shareURL])
                } else {
                    Text("Kein Link verfügbar")
                }
            }
            .alert("Link konnte nicht erstellt werden", isPresented: Binding(
                get: { shareError != nil },
                set: { isPresented in
                    if !isPresented { shareError = nil }
                }
            )) {
                Button("OK", role: .cancel) {
                    shareError = nil
                }
            } message: {
                Text(shareError ?? "Unbekannter Fehler.")
            }
            .sheet(isPresented: $showAddHomeworkSheet) {
                NavigationStack {
                    AddHomeworkView()
                        .environmentObject(store)
                }
            }
        }
    }

    private func showAddHomework() {
        showAddHomeworkSheet = true
    }

    @ViewBuilder
    private func homeworkRow(_ hw: Homework) -> some View {
        let treatedCompleted = hw.isCompleted
        let badge = badgeState(for: hw, treatedCompleted: treatedCompleted)
        let personalNote = store.userNoteForHomework(hw)
        
        // Determine Accent Color from Badge or Default
        let accentColor: Color = badge?.color ?? .blue
        
        let hasActiveReminder = hw.reminderAt != nil && (hw.reminderAt! > Date())

        HStack(alignment: .center, spacing: 16) {
            
            // 1. Date Block Anchor (Left)
            if let due = hw.dueDate {
                VStack(spacing: 0) {
                    Text(hwDayFormatter.string(from: due))
                        .font(.title3.weight(.bold))
                    Text(hwMonthFormatter.string(from: due).uppercased())
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(accentColor)
                .frame(width: 50, height: 50)
                .background(accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                 // Fallback Icon Block
                ZStack {
                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                     Image(systemName: "doc.text")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 50, height: 50)
            }
            
            // 2. Info Content (Center)
            VStack(alignment: .leading, spacing: 4) {
                // Top Meta Row: Subject + Context
                HStack(spacing: 4) {
                    let subjectName = resolvedSubjectName(for: hw)
                    Text(subjectName.isEmpty ? "Allgemein" : subjectName.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    if hw.isShared {
                        Image(systemName: "person.2.fill") // Group Icon
                            .font(.caption2)
                            .foregroundStyle(.blue)
                         
                         let contextName = store.resolveContextName(groupId: hw.groupId, courseId: hw.courseId).replacingOccurrences(of: resolvedSubjectName(for: hw), with: "").trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
                         if !contextName.isEmpty {
                             Text("• \(contextName)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                         }
                    } else if hw.isImportedFromShare {
                         Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                
                // Title
                Text(hw.title)
                    .font(.headline)
                    .foregroundStyle(treatedCompleted ? .secondary : .primary)
                    .strikethrough(treatedCompleted)
                    .lineLimit(2)
                
                 if let personalNote, !personalNote.isEmpty {
                     Text("Note: \(personalNote)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                 }
            }
            
            Spacer(minLength: 0)
            
            // 3. Actions (Right)
            VStack(alignment: .trailing, spacing: 12) {
                // Reminder Bell
                if !treatedCompleted {
                    Button {
                        reminderHomework = hw
                    } label: {
                        Image(systemName: hw.reminderAt != nil ? "bell.fill" : "bell")
                            .font(.subheadline)
                            .foregroundStyle(hw.reminderAt != nil ? .orange : Color.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                // Completion Toggle
                Button {
                    Task {
                        if treatedCompleted {
                            await markNotCompleted(hw)
                        } else {
                            await markCompleted(hw)
                        }
                    }
                } label: {
                    Image(systemName: treatedCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
                         .font(.system(size: 28)) // Consistent size with exam row
                         .foregroundStyle(treatedCompleted ? .orange : Color.secondary.opacity(0.3)) // Subtle checkmark if open
                }
                .buttonStyle(.plain)
                
                // Context Menu (Hidden in plain view, accessible via long press or if we add ... button)
                // Integrating ... button into the stack if we want it explicit:
            }
            // Add Overlay Menu button or just rely on tap for detail?
            // ExamRow uses a "..." menu button if no primary action. Here we almost always have primary actions.
            // Let's add a Menu button at the bottom of the stack or replace one action?
            // Actually, let's put the Menu on the whole row or just rely on Tap -> Detail -> Edit.
            // The previous design had explicit "Bearbeiten" buttons.
            // Let's Add a small "..." button at the very top or bottom of the stack if space permits?
            // Better: User taps row for detail. Context Menu on the row.
        }
        .padding(12)
        .background(Color.formSectionBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { detailHomework = hw }
        .contextMenu {
             Button { editingHomework = hw } label: { Label("Bearbeiten", systemImage: "pencil") }
             Button { presentShareLink(for: hw) } label: { Label("Teilen", systemImage: "square.and.arrow.up") }
             Button { reminderHomework = hw } label: { Label("Erinnerung", systemImage: "bell") }
             Button {
                 Task { await treatedCompleted ? markNotCompleted(hw) : markCompleted(hw) }
             } label: {
                 Label(treatedCompleted ? "Als offen markieren" : "Erledigen", systemImage: treatedCompleted ? "arrow.uturn.backward" : "checkmark")
             }
        }
    }

    private func presentShareLink(for hw: Homework) {
        shareError = nil
        guard let url = HomeworkShareLinkBuilder.url(for: hw) else {
            shareError = "Der Link konnte nicht erstellt werden."
            return
        }
        shareURL = url
        showShareSheet = true
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func markCompleted(_ hw: Homework) async {
        if hw.isShared {
            await store.setUserCompletedForSharedHomework(homeworkId: hw.id, completed: true)
        } else {
            await store.setHomeworkCompleted(id: hw.id, completed: true)
        }
        await MainActor.run {
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
        }
    }

    private func markNotCompleted(_ hw: Homework) async {
        if hw.isShared {
            await store.setUserCompletedForSharedHomework(homeworkId: hw.id, completed: false)
        } else {
            await store.setHomeworkCompleted(id: hw.id, completed: false)
        }
        await MainActor.run {
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif
        }
    }

    private func toggleReminder(_ hw: Homework) async {
        let newValue: Date? = (hw.reminderAt == nil) ? Date().addingTimeInterval(3600) : nil
        do {
            if hw.isShared {
                try await store.setUserReminderForSharedHomework(homeworkId: hw.id, reminderAt: newValue, groupId: hw.groupId)
            } else {
                try await store.updateHomeworkInFirestore(
                    id: hw.id,
                    subjectName: hw.subjectName,
                    title: hw.title,
                    dueDate: hw.dueDate,
                    reminderAt: newValue,
                    isCompleted: hw.isCompleted
                )
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // Optional: Fehlerbehandlung oder Logging
        }
    }

    private func reminderIconName(_ hw: Homework) -> String {
        return hw.reminderAt == nil ? "bell" : "bell.fill"
    }

    private func reminderIconColor(_ hw: Homework) -> Color {
        return hw.reminderAt == nil ? .secondary : .green
    }

    private func reminderAccessibilityLabel(_ hw: Homework) -> String {
        return "Erinnerung bearbeiten"
    }

    private func shortReminder(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return hwReminderTimeFormatter.string(from: date)
        }
        return "\(hwReminderDateFormatter.string(from: date))\n\(hwReminderTimeFormatter.string(from: date))"
    }

    private func attentionBadge(_ text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func actionButton(icon: String, tint: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sortKey(for hw: Homework) -> (priority: Int, date: Date) {
        let cal = Calendar.current
        let now = Date()
        if let due = hw.dueDate {
            let startToday = cal.startOfDay(for: now)
            
            if hw.isCompleted {
                return (3, due)
            }
            if due < startToday {
                return (-1, due) // Overdue -> Highest Priority (top of list)
            }
            if cal.isDateInToday(due) {
                return (0, due)
            }
            if cal.isDateInTomorrow(due) {
                return (1, due)
            }
            return (2, due)
        }
        let date = hw.createdAt
        let priority = hw.isCompleted ? 3 : 2
        return (priority, date)
    }

    private func badgeState(for hw: Homework, treatedCompleted: Bool) -> (text: String, color: Color, icon: String?)? {
        let cal = Calendar.current
        if treatedCompleted {
            return ("Erledigt", .green, "checkmark")
        }
        guard let due = hw.dueDate else { return nil }
        if cal.isDateInToday(due) {
            return ("Fällig", .red, nil)
        }
        if cal.isDateInTomorrow(due) {
            return ("Morgen fällig", .orange, nil)
        }
        
        let startToday = cal.startOfDay(for: Date())
        if due < startToday {
            return ("Überfällig", .red, "exclamationmark.circle.fill")
        }
        
        return ("Geplant", .green, nil)
    }
}

private struct LocalHomeworkReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let homework: Homework

    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(homework: Homework) {
        self.homework = homework
        _hasReminder = State(initialValue: homework.reminderAt != nil)
        _reminderDate = State(initialValue: homework.reminderAt ?? Date().addingTimeInterval(60 * 60))
    }

    private var sheetTitle: String {
        let trimmed = homework.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Erinnerung" : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Erinnerung",
                        subtitle: "Eigene Erinnerung einstellen",
                        systemImage: "bell.badge",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Erinnerung aktivieren", isOn: $hasReminder)
                                    .tint(.orange)

                                if hasReminder {
                                    DatePicker(
                                        "",
                                        selection: $reminderDate,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                }
                            }
                        }
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .sheetNavigationTitle(sheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .imageScale(.medium)
                        }
                    }
                    .accessibilityLabel("Speichern")
                    .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        let reminderAt: Date? = hasReminder ? reminderDate : nil
        do {
            if homework.isShared {
                try await store.setUserReminderForSharedHomework(homeworkId: homework.id, reminderAt: reminderAt)
            } else {
                try await store.updateHomeworkInFirestore(
                    id: homework.id,
                    subjectName: homework.subjectName,
                    title: homework.title,
                    dueDate: homework.dueDate,
                    reminderAt: reminderAt,
                    isCompleted: homework.isCompleted
                )
            }
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}

private let hwReminderDateFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .medium
    fmt.timeStyle = .none
    return fmt
}()

private let hwReminderTimeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.dateStyle = .none
    fmt.timeStyle = .short
    return fmt
}()

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
