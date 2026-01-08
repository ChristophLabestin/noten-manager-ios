import SwiftUI
import CryptoKit

struct EditPraktikumGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let entry: PracticalGradeEntry

    @State private var gradeText: String
    @State private var company: String
    @State private var note: String
    @State private var halfYear: Int
    @State private var date: Date
    @State private var isSaving: Bool = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case grade, company, note }

    init(entry: PracticalGradeEntry) {
        self.entry = entry
        _gradeText = State(initialValue: String(format: "%.1f", entry.grade))
        _company = State(initialValue: entry.company ?? "")
        _note = State(initialValue: entry.note ?? "")
        _halfYear = State(initialValue: entry.halfYear ?? 1)
        _date = State(initialValue: entry.date)
    }

    private var parsedGrade: Double? {
        Double(
            gradeText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var canSave: Bool {
        guard store.schoolType == .fos else { return false }
        guard store.encryptionKey != nil else { return false }
        guard let value = parsedGrade, value >= 0, value <= 15 else { return false }
        return !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Praktikumsnote bearbeiten",
                        subtitle: halfYear == 1 ? "1. Praktikum" : "2. Praktikum",
                        systemImage: "slider.horizontal.3",
                        accent: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Punkte (0–15)")
                                        .font(.headline)
                                    TextField("z. B. 12,0", text: $gradeText)
                                        .keyboardType(.decimalPad)
                                        .submitLabel(.next)
                                        .focused($focusedField, equals: .grade)
                                        .onSubmit { focusedField = .company }
                                        .padding(12)
                                        .background(Color.formInputBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Halbjahr")
                                            .font(.headline)
                                        Picker("", selection: $halfYear) {
                                            Text("1. Hj").tag(1)
                                            Text("2. Hj").tag(2)
                                        }
                                        .pickerStyle(.segmented)
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Datum")
                                            .font(.headline)
                                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                                    }
                                }
                            }

                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Unternehmen (optional)")
                                            .font(.subheadline.weight(.semibold))
                                        TextField("Name des Betriebs", text: $company)
                                            .submitLabel(.next)
                                            .focused($focusedField, equals: .company)
                                            .onSubmit { focusedField = .note }
                                            .padding(12)
                                            .background(Color.formInputBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Notiz (optional)")
                                            .font(.subheadline.weight(.semibold))
                                        TextField("Kommentar oder Aufgabe", text: $note)
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity).onTapGesture { hideKeyboard() })
            .sheetNavigationTitle("Praktikumsnote")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.medium)
                            .foregroundStyle(Color.primary)
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
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .accessibilityLabel("Speichern")
                    .disabled(!canSave)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func save() async {
        guard !isSaving else { return }
        guard let key = store.encryptionKey else { return }
        guard let value = parsedGrade else { return }
        isSaving = true
        error = nil
        do {
            let trimmedCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try await store.upsertPracticalGrade(
                id: entry.id,
                grade: value,
                halfYear: halfYear,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                company: trimmedCompany.isEmpty ? nil : trimmedCompany,
                date: date,
                using: key
            )
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
