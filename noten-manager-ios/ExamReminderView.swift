import SwiftUI

struct ExamReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let exam: Exam

    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(exam: Exam) {
        self.exam = exam
        _hasReminder = State(initialValue: exam.reminderAt != nil)
        _reminderDate = State(initialValue: exam.reminderAt ?? Date().addingTimeInterval(60 * 60))
    }

    private var sheetTitle: String {
        let trimmed = exam.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let subject = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return subject.isEmpty ? "Erinnerung" : subject
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
                    Button("Abbrechen") {
                        dismiss()
                    }
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
        do {
            let reminderAt: Date? = hasReminder ? reminderDate : nil
            let normalizedDate = exam.date
            if exam.isShared {
                try await store.setUserReminderForSharedExam(examId: exam.id, reminderAt: reminderAt)
            } else {
                try await store.updateExamInFirestore(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    subjectKey: exam.subjectKey,
                    title: exam.title,
                    notes: exam.notes,
                    date: normalizedDate,
                    hasTime: exam.hasTime,
                    weight: exam.weight,
                    customWeight: exam.customWeight,
                    reminderAt: reminderAt,
                    isCompleted: exam.isCompleted
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
