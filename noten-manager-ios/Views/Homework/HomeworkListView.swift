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
    @State private var homeworkToDelete: Homework? = nil
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
                    VStack(alignment: .leading, spacing: 4) {
                       Text("Hausaufgaben")
                           .font(.title2.weight(.bold))
                       Text("Gedrückt halten für weitere Optionen")
                           .font(.subheadline)
                           .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
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
                                    HomeworkRowView(
                                        homework: hw,
                                        onToggleReminder: { reminderHomework = hw },
                                        onToggleCompletion: {
                                            Task { await markCompleted(hw) }
                                        },
                                        onTap: { detailHomework = hw }
                                    ) {
                                        Button { editingHomework = hw } label: { Label("Bearbeiten", systemImage: "pencil") }
                                        Button { presentShareLink(for: hw) } label: { Label("Teilen", systemImage: "square.and.arrow.up") }
                                        Button { reminderHomework = hw } label: { Label("Erinnerung", systemImage: "bell") }
                                        Button {
                                            Task { await markCompleted(hw) }
                                        } label: {
                                            Label("Erledigen", systemImage: "checkmark")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            homeworkToDelete = hw
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    }
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
                                    HomeworkRowView(
                                        homework: hw,
                                        onToggleReminder: { reminderHomework = hw },
                                        onToggleCompletion: {
                                            Task { await markNotCompleted(hw) }
                                        },
                                        onTap: { detailHomework = hw }
                                    ) {
                                        Button { editingHomework = hw } label: { Label("Bearbeiten", systemImage: "pencil") }
                                        Button { presentShareLink(for: hw) } label: { Label("Teilen", systemImage: "square.and.arrow.up") }
                                        Button {
                                            Task { await markNotCompleted(hw) }
                                        } label: {
                                            Label("Als offen markieren", systemImage: "arrow.uturn.backward")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            homeworkToDelete = hw
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    }
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
                        ToolbarIcon(symbol: "chevron.down", showDot: false)
                    }
                    .accessibilityLabel("Schließen")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddHomework()
                    } label: {
                        ToolbarIcon(symbol: "plus", showDot: false)
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
                HomeworkReminderView(homework: hw)
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
            .alert("Hausaufgabe löschen?", isPresented: Binding(
                get: { homeworkToDelete != nil },
                set: { if !$0 { homeworkToDelete = nil } }
            )) {
                Button("Löschen", role: .destructive) {
                    if let hw = homeworkToDelete {
                        Task {
                            await store.deleteHomework(hw)
                            homeworkToDelete = nil
                        }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Bist du sicher? Dies kann nicht widerrufen werden.")
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
