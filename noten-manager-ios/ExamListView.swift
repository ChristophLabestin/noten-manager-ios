import SwiftUI
import FirebaseAuth

struct ExamListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var visibleInactiveCount: Int = 5
    @State private var editingExam: Exam? = nil
    @State private var examForNewGrade: Exam? = nil
    @State private var reminderExam: Exam? = nil

    private var activeExams: [Exam] {
        store.allExams.filter { $0.isActive }.sorted {
            $0.date < $1.date
        }
    }

    private var inactiveExams: [Exam] {
        store.allExams.filter { !$0.isActive }.sorted {
            $0.date > $1.date
        }
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Bevorstehende Klausuren") {
                    if activeExams.isEmpty {
                        Text("Du hast aktuell keine anstehenden Klausuren.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeExams) { exam in
                            examRow(exam)
                        }
                    }
                }

                if !inactiveExams.isEmpty {
                    Section("Vergangene / erledigte Klausuren") {
                        ForEach(Array(inactiveExams.prefix(visibleInactiveCount))) { exam in
                            examRow(exam, isInactiveSection: true)
                        }

                        if inactiveExams.count > visibleInactiveCount {
                            Button {
                                visibleInactiveCount += 5
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
                visibleInactiveCount = 5
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
        }
    }

    @ViewBuilder
    private func examRow(_ exam: Exam, isInactiveSection: Bool = false) -> some View {
        let isSharedOwner = exam.isShared && exam.creatorId == currentUserId

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(exam.title)
                    .font(.body)
                    .lineLimit(2)
                if !exam.subjectName.isEmpty {
                    Text(exam.subjectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if exam.isShared {
                    let name = exam.groupId.flatMap { store.groupNames[$0] } ?? exam.groupId ?? ""
                    if !name.isEmpty {
                        Text("Gruppe: \(name)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Text(formattedDateTime(exam.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !exam.isShared && Date() >= exam.date && !exam.isCompleted {
                    Text("noch keine Note verknüpft")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                // Erinnerung-Hinweis nur per Icon in der Aktion, kein Text/zusätzliches Icon hier

                if exam.isShared {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.blue)
                            .imageScale(.small)
                        Text("Geteilter Termin")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                // Glocke: zeigt Status (grau = aus, grün = an) und öffnet Reminder-Editor
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

                Button {
                    editingExam = exam
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .regular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Klausur bearbeiten")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            examForNewGrade = exam
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func noteForExam(_ exam: Exam) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateString = formatter.string(from: exam.date)
        return "Geschrieben am \(dateString)"
    }

    private func markCompleted(_ exam: Exam) async {
        await store.setExamCompleted(id: exam.id, completed: true)
    }

    private func toggleReminder(_ exam: Exam) async {
        let newValue: Date? = (exam.reminderAt == nil) ? Date().addingTimeInterval(3600) : nil
        do {
            if exam.isShared {
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: newValue, groupId: exam.groupId)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    title: exam.title,
                    date: exam.date,
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
