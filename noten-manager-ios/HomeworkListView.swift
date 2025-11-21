import SwiftUI
import FirebaseAuth
#if os(iOS)
import UIKit
#endif

struct HomeworkListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var visibleInactiveCount: Int = 5
    @State private var editingHomework: Homework? = nil
    @State private var reminderHomework: Homework? = nil

    private var activeHomeworks: [Homework] {
        store.allHomeworks.filter { $0.isActive }.sorted {
            let a = $0.dueDate ?? $0.createdAt
            let b = $1.dueDate ?? $1.createdAt
            return a < b
        }
    }

    private var inactiveHomeworks: [Homework] {
        store.allHomeworks.filter { !$0.isActive }.sorted {
            let a = $0.dueDate ?? $0.createdAt
            let b = $1.dueDate ?? $1.createdAt
            return a > b
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
            List {
                Section("Aktive Hausaufgaben") {
                    if activeHomeworks.isEmpty {
                        Text("Du hast aktuell keine aktiven Hausaufgaben.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeHomeworks) { hw in
                            homeworkRow(hw)
                        }
                    }
                }

                if !inactiveHomeworks.isEmpty {
                    Section("Erledigt / überfällig") {
                        ForEach(Array(inactiveHomeworks.prefix(visibleInactiveCount))) { hw in
                            homeworkRow(hw, isInactiveSection: true)
                        }

                        if inactiveHomeworks.count > visibleInactiveCount {
                            Button {
                                visibleInactiveCount += 5
                            } label: {
                                Text("Weitere 5 anzeigen")
                            }
                        }
                    }
                }

            }
            .navigationTitle("Hausaufgaben")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Schließen")
                    }
                }
            }
            .onAppear {
                visibleInactiveCount = 5
            }
            .sheet(item: $editingHomework) { hw in
                EditHomeworkView(homework: hw)
                    .environmentObject(store)
            }
            .sheet(item: $reminderHomework) { hw in
                LocalHomeworkReminderSheet(homework: hw)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func homeworkRow(_ hw: Homework, isInactiveSection: Bool = false) -> some View {
        let currentUserId = Auth.auth().currentUser?.uid
        let isSharedOwner = hw.isShared && hw.creatorId == currentUserId
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(hw.title)
                    .font(.body)
                    .lineLimit(2)
                if !hw.subjectName.isEmpty {
                    Text(hw.subjectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hw.isShared {
                    let name = hw.groupId.flatMap { store.groupNames[$0] } ?? hw.groupId ?? ""
                    if !name.isEmpty {
                        Text("Gruppe: \(name)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let due = hw.dueDate {
                    Text("Fällig am \(formattedDate(due))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Kein Fälligkeitsdatum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if hw.isShared {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.blue)
                        Text("Geteilte Hausaufgabe")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                // Glocke
                Button {
                    reminderHomework = hw
                } label: {
                    Image(systemName: reminderIconName(hw))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(reminderIconColor(hw))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Erinnerung bearbeiten")
                .contextMenu {
                    Button("Erinnerung bearbeiten…") { reminderHomework = hw }
                    if hw.reminderAt != nil {
                        Button("Erinnerung entfernen", role: .destructive) {
                            Task { await toggleReminder(hw) }
                        }
                    }
                }

                // Bearbeiten-Button direkt neben der Glocke
                Button {
                    editingHomework = hw
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hausaufgabe bearbeiten")

                // Status / Aktionen
                if hw.isShared {
                    if isSharedOwner {
                        if hw.isCompleted {
                            Button {
                                Task { await markNotCompleted(hw) }
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Als nicht erledigt markieren")
                        } else if !isInactiveSection {
                            Button {
                                Task { await markCompleted(hw) }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Als erledigt markieren")
                        }
                    } else {
                        if !isInactiveSection && !hw.isCompleted {
                            Button {
                                Task { await markCompleted(hw) }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        if hw.isCompleted {
                            Button {
                                Task { await markNotCompleted(hw) }
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } else {
                    if hw.isCompleted {
                        Button {
                            Task { await markNotCompleted(hw) }
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    } else if !isInactiveSection {
                        Button {
                            Task { await markCompleted(hw) }
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isInactiveSection && !hw.isCompleted {
                Button {
                    Task { await markCompleted(hw) }
                } label: {
                    Label("Erledigt", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            }
            if hw.isCompleted {
                Button {
                    Task { await markNotCompleted(hw) }
                } label: {
                    Label("Nicht erledigt", systemImage: "arrow.uturn.backward.circle")
                }
                .tint(.orange)
            }
        }
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Erinnerung für Hausaufgabe") {
                    Toggle("Zusätzliche Erinnerung aktivieren", isOn: $hasReminder)

                    if hasReminder {
                        DatePicker(
                            "Erinnerungszeitpunkt",
                            selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Erinnerung festlegen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Speichern") }
                    }
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
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
