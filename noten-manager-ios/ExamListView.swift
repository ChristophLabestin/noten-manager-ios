import SwiftUI
import FirebaseAuth

struct ExamListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var visibleInactiveCount: Int = 5
    @State private var editingExam: Exam? = nil
    @State private var examToDelete: Exam? = nil
    @State private var examForNewGrade: Exam? = nil
    @State private var joinCode: String = ""
    @State private var isCreatingGroup: Bool = false
    @State private var groupInfoMessage: String?
    @State private var groupErrorMessage: String?
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

                Section("Klausurtermine teilen") {
                    if let code = store.examGroupId, !code.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Du bist mit einer Klausurgruppe verbunden. Termine aus dieser Gruppe erscheinen automatisch in deiner Liste.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("Gruppencode:")
                                Text(code)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }

                        Button("Gruppe verlassen") {
                            Task {
                                await store.leaveExamGroup()
                                joinCode = ""
                                groupInfoMessage = nil
                                groupErrorMessage = nil
                            }
                        }
                        .foregroundColor(.red)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lege eine Klausurgruppe an oder tritt mit einem Code einer bestehenden Gruppe bei. So muss nur eine Person die Termine eintragen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task {
                                guard !isCreatingGroup else { return }
                                isCreatingGroup = true
                                groupErrorMessage = nil
                                defer { isCreatingGroup = false }
                                do {
                                    let code = try await store.createExamGroupIfNeeded()
                                    joinCode = code
                                    groupInfoMessage = "Neue Gruppe erstellt. Teile den Code mit deinen Mitschülern."
                                } catch {
                                    groupErrorMessage = error.localizedDescription
                                }
                            }
                        } label: {
                            if isCreatingGroup {
                                ProgressView()
                            } else {
                                Text("Neue Klausurgruppe erstellen")
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Einer bestehenden Gruppe beitreten")
                                .font(.subheadline)
                            TextField("Gruppencode", text: $joinCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled(true)
                        }

                        Button("Mit Code beitreten") {
                            Task {
                                groupErrorMessage = nil
                                groupInfoMessage = nil
                                do {
                                    try await store.joinExamGroup(with: joinCode)
                                    groupInfoMessage = "Erfolgreich der Klausurgruppe beigetreten."
                                } catch {
                                    groupErrorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let msg = groupInfoMessage {
                            Text(msg)
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        if let err = groupErrorMessage {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
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
            .alert(
                "Klausur löschen?",
                isPresented: Binding(
                    get: { examToDelete != nil },
                    set: { newValue in
                        if !newValue {
                            examToDelete = nil
                        }
                    }
                )
            ) {
                Button("Löschen", role: .destructive) {
                    if let exam = examToDelete {
                        Task { await deleteExam(exam) }
                    }
                }
                Button("Abbrechen", role: .cancel) {
                    examToDelete = nil
                }
            } message: {
                Text("Dieser Klausurtermin wird dauerhaft gelöscht.")
            }
            .sheet(item: $examForNewGrade) { exam in
                let note = noteForExam(exam)
                AddGradeView(
                    preselectedSubjectName: exam.subjectName,
                    preselectedWeight: exam.weight,
                    prefilledNote: note
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

                Text(formattedDateTime(exam.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if exam.reminderAt != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                        Text("Erinnerung aktiv")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }

                if exam.isShared {
                    Text("Geteilter Termin")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer()
            HStack(spacing: 12) {
                if exam.isShared && !isSharedOwner {
                    Button {
                        reminderExam = exam
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 16, weight: .regular))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Erinnerung für diese Klausur festlegen")
                } else {
                    if !exam.isShared {
                        if !isInactiveSection && !exam.isCompleted {
                            Button {
                                Task { await markCompleted(exam) }
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Als erledigt markieren")
                        } else {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
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

                    Button {
                        examToDelete = exam
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Klausur löschen")
                }
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

    private func deleteExam(_ exam: Exam) async {
        if exam.isShared {
            await store.deleteSharedExamFromGroup(id: exam.id)
        } else {
            await store.deleteExamFromFirestore(id: exam.id)
        }
        examToDelete = nil
    }
}
