import SwiftUI
import FirebaseAuth

struct ExamListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let subjectFilter: String?
    let alternateSubjectNames: [String]

    @State private var visibleCompletedCount: Int = 5
    @State private var editingExam: Exam? = nil
    @State private var examForNewGrade: Exam? = nil
    @State private var reminderExam: Exam? = nil
    @State private var detailExam: Exam? = nil

    init(subjectFilter: String? = nil, alternateSubjectNames: [String] = []) {
        self.subjectFilter = subjectFilter
        self.alternateSubjectNames = alternateSubjectNames
    }

    private var upcomingExams: [Exam] {
        let now = Date()
        return filteredExams
            .filter { !$0.isCompleted && $0.date > now }
            .sorted { $0.date < $1.date }
    }

    private var waitingForGradeExams: [Exam] {
        let now = Date()
        return filteredExams
            .filter { !$0.isCompleted && $0.date <= now }
            .sorted { $0.date > $1.date }
    }

    private var completedExams: [Exam] {
        filteredExams
            .filter { $0.isCompleted }
            .sorted { $0.date > $1.date }
    }

    private var filteredExams: [Exam] {
        guard let subjectFilter else { return store.allExams }
        let candidates = ([subjectFilter] + alternateSubjectNames).map { $0.lowercased() }
        return store.allExams.filter { exam in
            let name = exam.subjectName.lowercased()
            return candidates.contains(name)
        }
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Anstehend") {
                    if upcomingExams.isEmpty {
                        Text("Du hast aktuell keine anstehenden Klausuren.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(upcomingExams) { exam in
                            examRow(exam)
                        }
                    }
                }

                if !waitingForGradeExams.isEmpty {
                    Section("Wartet auf Note") {
                        ForEach(waitingForGradeExams) { exam in
                            examRow(exam)
                        }
                    }
                }

                if !completedExams.isEmpty {
                    Section("Erledigt") {
                        ForEach(Array(completedExams.prefix(visibleCompletedCount))) { exam in
                            examRow(exam)
                        }

                        if completedExams.count > visibleCompletedCount {
                            Button {
                                visibleCompletedCount += 5
                            } label: {
                                Text("Weitere 5 anzeigen")
                            }
                        }
                    }
                }

            }
            .navigationTitle("Klausurtermine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                visibleCompletedCount = 5
            }
            .sheet(item: $editingExam) { exam in
                EditExamView(exam: exam)
                    .environmentObject(store)
            }
            .sheet(item: $examForNewGrade) { exam in
                let note = noteForExam(exam)
                AddGradeView(
                    preselectedSubjectName: exam.subjectName,
                    preselectedWeight: exam.weight,
                    prefilledNote: note,
                    linkedExamId: exam.id,
                    markLinkedExamCompletedByDefault: true
                )
                .environmentObject(store)
            }
            .sheet(item: $reminderExam) { exam in
                ExamReminderView(exam: exam)
                    .environmentObject(store)
            }
            .sheet(item: $detailExam) { exam in
                ExamDetailSheet(exam: exam)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func examRow(_ exam: Exam) -> some View {
        let now = Date()
        let isOverdueAttention = !exam.isCompleted && exam.date < now
        let attentionTag = isOverdueAttention ? "Wartet auf Note" : nil
        let attentionColor: Color = .red
        let showReminder = !exam.isCompleted && exam.date > now

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(exam.title)
                        .font(.body)
                        .lineLimit(2)
                    if let tag = attentionTag {
                        attentionBadge(tag, color: attentionColor)
                    }
                }
                if !exam.subjectName.isEmpty {
                    Text(exam.subjectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(formattedExamDate(exam.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !exam.isShared && now >= exam.date && !exam.isCompleted {
                    Text("noch keine Note verknüpft")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if exam.isShared {
                    let name = exam.groupId.flatMap { store.groupNames[$0] } ?? exam.groupId ?? ""
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.small)
                            Text("Geteilter Termin")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        if !name.isEmpty {
                            Text("Gruppe: \(name)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if showReminder {
                    Button {
                        reminderExam = exam
                    } label: {
                        Image(systemName: reminderIconName(exam))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(reminderIconColor(exam))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Erinnerung bearbeiten")
                    .contextMenu {
                        Button("Erinnerung bearbeiten…") { reminderExam = exam }
                        if exam.reminderAt != nil {
                            Button("Erinnerung entfernen", role: .destructive) {
                                Task { await toggleReminder(exam) }
                            }
                        }
                    }
                }

                if !exam.isCompleted {
                    Button {
                        examForNewGrade = exam
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Note hinzufügen")
                }

                Button {
                    editingExam = exam
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Klausur bearbeiten")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            detailExam = exam
        }
    }

    private func formattedExamDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func noteForExam(_ exam: Exam) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: exam.date)
        return "Geschrieben am \(dateString)"
    }

    private func attentionBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func markCompleted(_ exam: Exam) async {
        await store.setExamCompleted(id: exam.id, completed: true)
    }

    private func toggleReminder(_ exam: Exam) async {
        let newValue: Date? = (exam.reminderAt == nil) ? Date().addingTimeInterval(3600) : nil
        let normalizedDate = Calendar.current.startOfDay(for: exam.date)
        do {
            if exam.isShared {
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: newValue, groupId: exam.groupId)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    title: exam.title,
                    notes: exam.notes,
                    date: normalizedDate,
                    weight: exam.weight,
                    reminderAt: newValue,
                    isCompleted: exam.isCompleted
                )
            }
        } catch {
            // Optional: Fehlerbehandlung oder Logging
        }
    }

    private func reminderIconName(_ exam: Exam) -> String {
        return exam.reminderAt == nil ? "bell" : "bell.fill"
    }

    private func reminderIconColor(_ exam: Exam) -> Color {
        return exam.reminderAt == nil ? .secondary : .green
    }

    private func reminderAccessibilityLabel(_ exam: Exam) -> String {
        return "Erinnerung bearbeiten"
    }
}

struct ExamDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    let exam: Exam

    private var groupName: String {
        guard let gid = exam.groupId else { return "" }
        return store.groupNames[gid] ?? gid
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        fmt.timeStyle = .none
        return fmt.string(from: exam.date)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    Text(exam.title.isEmpty ? "Ohne Titel" : exam.title)
                        .font(.headline)
                    Text(formattedDate)
                        .foregroundStyle(.secondary)
                }

                Section("Fach & Gruppe") {
                    Text(exam.subjectName.isEmpty ? "Unbekanntes Fach" : exam.subjectName)
                    if !groupName.isEmpty {
                        Text("Gruppe: \(groupName)")
                            .foregroundStyle(.secondary)
                    }
                }

                if let notes = exam.notes, !notes.isEmpty {
                    Section("Notizen") {
                        Text(notes)
                            .font(.body)
                    }
                }

                Section("Details") {
                    Text("Art: \(weightLabel)")
                    Text(exam.requiresGrade == false ? "Note nicht erforderlich" : "Note erforderlich")
                        .foregroundStyle(.secondary)
                    if let reminder = exam.reminderAt {
                        Text("Erinnerung: \(formattedDateTime(reminder))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Keine Erinnerung").foregroundStyle(.secondary)
                    }
                    Text(exam.isCompleted ? "Status: Erledigt" : "Status: Offen")
                        .foregroundStyle(exam.isCompleted ? .green : .primary)
                }
            }
            .navigationTitle("Klausurdetails")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private var weightLabel: String {
        switch exam.weight {
        case 2: return "Schulaufgabe"
        case 1: return "Kurzarbeit"
        default: return "Mündlich / EX"
        }
    }
}
