import SwiftUI

struct AddExamView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let preselectedSubjectName: String?

    @State private var subjectName: String = ""
    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var date: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var examWeight: Int = 0
    @State private var hasReminder: Bool = false
    @State private var reminderDate: Date = Date().addingTimeInterval(60 * 60)
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var shareWithGroup: Bool = false
    @FocusState private var focusedField: Field?

    private var subjects: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !subjectName.isEmpty
    }

    init(preselectedSubjectName: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
    }

    private enum Field: Hashable {
        case title, notes
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Klausurtermin",
                        subtitle: "Fach, Titel und Gewichtung",
                        systemImage: "calendar.badge.clock",
                        accent: .indigo
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Fach")
                                        .font(.headline)
                                    Picker("Fach", selection: $subjectName) {
                                        ForEach(subjects, id: \.name) { s in
                                            Text(s.name).tag(s.name)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.primary)
                                    .padding(10)
                                    .background(Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                    if subjects.isEmpty {
                                        Text("Lege zuerst ein Fach an, um Klausuren zuzuordnen.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Titel / Bezeichnung")
                                            .font(.headline)
                                        TextField("z. B. Kurzarbeit Mathematik", text: $title)
                                            .textInputAutocapitalization(.sentences)
                                            .submitLabel(.next)
                                            .focused($focusedField, equals: .title)
                                            .onSubmit { focusedField = .notes }
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Notizen (optional)")
                                            .font(.subheadline)
                                        TextEditor(text: $notes)
                                            .frame(minHeight: 90)
                                            .textInputAutocapitalization(.sentences)
                                            .scrollContentBackground(.hidden)
                                            .focused($focusedField, equals: .notes)
                                            .padding(10)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    let subjectType = subjects.first(where: { $0.name == subjectName })?.type ?? 0
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Art")
                                            .font(.headline)
                                        Picker("", selection: $examWeight) {
                                            if subjectType == 0 {
                                                Text("Kurzarbeit").tag(1)
                                                Text("Mündlich / EX").tag(0)
                                            } else {
                                                Text("Schulaufgabe").tag(2)
                                                Text("Kurzarbeit").tag(1)
                                                Text("Mündlich / EX").tag(0)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Termin")
                                            .font(.headline)
                                        DatePicker(
                                            "Datum & Uhrzeit",
                                            selection: $date,
                                            displayedComponents: [.date, .hourAndMinute]
                                        )
                                    }
                                }
                            }
                        }
                    }

                    SettingsCard(
                        title: "Erinnerung & Teilen",
                        subtitle: "Optionale Benachrichtigung",
                        systemImage: "bell.badge.fill",
                        accent: .orange
                    ) {
                        SettingsSectionBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Zusätzliche Erinnerung planen", isOn: $hasReminder)
                                    .tint(.orange)

                                if hasReminder {
                                    DatePicker(
                                        "Erinnerung",
                                        selection: $reminderDate,
                                        displayedComponents: [.date, .hourAndMinute]
                                    )
                                }

                                if !store.groupIds.isEmpty {
                                    Toggle("Mit Gruppen teilen", isOn: $shareWithGroup)
                                        .tint(.orange)
                                    Text("Geteilte Termine werden für alle Gruppenmitglieder sichtbar.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
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
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))
            .navigationTitle("Klausur hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(!canSave || isSaving || subjects.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardNavigationAccessory(
                        focus: $focusedField,
                        fields: [.title, .notes],
                        label: nil,
                        onDone: { hideKeyboard() }
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .onAppear {
                if subjectName.isEmpty {
                    if let pre = preselectedSubjectName,
                       subjects.contains(where: { $0.name == pre }) {
                        subjectName = pre
                    } else {
                        subjectName = subjects.first?.name ?? ""
                    }
                }
                shareWithGroup = !store.groupIds.isEmpty
            }
        }
        .modifier(KeyboardToolbarInset(height: 64))
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            error = "Bitte einen Titel für die Klausur eingeben."
            isSaving = false
            return
        }
        do {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
            let reminder: Date? = hasReminder ? reminderDate : nil
            let requiresGrade = true
            if shareWithGroup {
                let sharedIds = try await store.addExamToGroups(
                    subjectName: subjectName,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder,
                    requiresGrade: requiresGrade
                )
                if sharedIds.isEmpty {
                    try await store.addExamToFirestore(
                        subjectName: subjectName,
                        title: trimmedTitle,
                        notes: storedNotes,
                        date: date,
                        weight: examWeight,
                        reminderAt: reminder,
                        requiresGrade: requiresGrade
                    )
                } else if let reminder {
                    for item in sharedIds {
                        try await store.setUserReminderForSharedExam(examId: item.docId, reminderAt: reminder, groupId: item.groupId)
                    }
                }
            } else {
                try await store.addExamToFirestore(
                    subjectName: subjectName,
                    title: trimmedTitle,
                    notes: storedNotes,
                    date: date,
                    weight: examWeight,
                    reminderAt: reminder,
                    requiresGrade: requiresGrade
                )
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
