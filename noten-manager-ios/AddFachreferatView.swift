import SwiftUI
import CryptoKit

struct AddFachreferatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    // Optional vorselektiertes Fach (z. B. von SubjectDetail)
    let preselectedSubjectName: String?

    @State private var subjectName: String = ""
    @State private var gradeText: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var showDeleteAlert: Bool = false
    @FocusState private var focusedField: Field?

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard Double(gradeText) != nil else { return false }
        return true
    }

    init(preselectedSubjectName: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
    }

    private enum Field: Hashable {
        case grade, note
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: store.fachreferat == nil ? "Fachreferat" : "Fachreferat bearbeiten",
                        subtitle: "Fach, Note und Datum",
                        systemImage: "doc.text.fill",
                        accent: .pink
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
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Note")
                                            .font(.headline)
                                        TextField("z. B. 10.0", text: $gradeText)
                                            .keyboardType(.decimalPad)
                                            .submitLabel(.next)
                                            .focused($focusedField, equals: .grade)
                                            .onSubmit { focusedField = .note }
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    DatePicker("Datum", selection: $date, displayedComponents: .date)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Notiz (optional)")
                                            .font(.subheadline)
                                        TextField("Kommentar hinzufügen", text: $note)
                                            .submitLabel(.done)
                                            .focused($focusedField, equals: .note)
                                            .onSubmit { hideKeyboard() }
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
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

                    if store.fachreferat != nil {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Fachreferat löschen")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine"))
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
                    .disabled(!canSave || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    KeyboardNavigationAccessory(
                        focus: $focusedField,
                        fields: [.grade, .note],
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
                           subjects.contains(where: { $0.name == pre && $0.name != "Fachreferat" }) {
                            subjectName = pre
                        } else {
                            subjectName = store.fachreferat?.subjectName
                            ?? subjects.first(where: { $0.name != "Fachreferat" })?.name
                            ?? ""
                        }
                    }
                if let fr = store.fachreferat {
                    gradeText = String(fr.grade)
                    date = fr.date
                    note = fr.note ?? ""
                }
            }
            .alert("Fachreferat löschen?", isPresented: $showDeleteAlert) {
                Button("Löschen", role: .destructive) {
                    Task { await deleteFachreferat() }
                }
                Button("Abbrechen", role: .cancel) { }
            } message: {
                Text("Diese Fachreferat-Note wird dauerhaft gelöscht.")
            }
        }
        .modifier(KeyboardToolbarInset(height: 64))
    }

    private func save() async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        error = nil
        do {
            let grade = Double(gradeText) ?? 0
            try await store.setFachreferatToFirestore(subjectName: subjectName, grade: grade, date: date, note: note.isEmpty ? nil : note, using: key)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteFachreferat() async {
        guard !isSaving else { return }
        isSaving = true
        await store.deleteFachreferat()
        await MainActor.run {
            dismiss()
        }
        isSaving = false
    }
}
