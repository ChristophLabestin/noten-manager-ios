import SwiftUI
import CryptoKit

struct AddPraktikumGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    let preselectedHalfYear: Int?

    @State private var useSubGrades: Bool = false
    @State private var guidanceGradeText: String = ""
    @State private var deepeningGradeText: String = ""
    @State private var activityGradeText: String = ""
    
    @State private var gradeText: String = ""
    @State private var company: String = ""
    @State private var note: String = ""
    @State private var halfYear: Int = 1
    @State private var date: Date = Date()
    @State private var isSaving: Bool = false
    @State private var error: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case grade, company, note, guidance, deepening, activity }

    init(preselectedHalfYear: Int? = nil) {
        self.preselectedHalfYear = preselectedHalfYear
    }

    private var parsedGrade: Double? {
        if useSubGrades {
            return calculatedAverage
        }
        return Double(
            gradeText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var parsedGuidance: Double? {
        Double(guidanceGradeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var parsedDeepening: Double? {
        Double(deepeningGradeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var parsedActivity: Double? {
        Double(activityGradeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private var calculatedAverage: Double? {
        guard let g = parsedGuidance, let d = parsedDeepening, let a = parsedActivity else { return nil }
        // FOBOSO § 13: (Anleitung + Vertiefung + 2 * Tätigkeit) / 4
        // Rounds to 2 decimal places to match generic grade logic before cutting? 
        // Actually FOBOSO says points are whole numbers usually, but internship grade contributes to "Jahresfortgang".
        // Let's keep one decimal precision for display.
        let raw = (g + d + (2 * a)) / 4.0
        return raw
    }

    private var canSave: Bool {
        guard store.schoolType == .fos else { return false }
        guard store.encryptionKey != nil else { return false }
        guard let value = parsedGrade, value >= 0, value <= 15 else { return false }
        return !isSaving
    }

    private var suggestedHalfYear: Int {
        if let preselectedHalfYear { return preselectedHalfYear }
        let entries = store.practicalPerformance?.grades ?? []
        if !entries.contains(where: { $0.halfYear == 1 }) { return 1 }
        if !entries.contains(where: { $0.halfYear == 2 }) { return 2 }
        return 1
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: "Praktikumsnote",
                        subtitle: "Punkte, Halbjahr & Termin",
                        systemImage: "briefcase.fill",
                        accent: .orange
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Einzelnoten (FOBOSO)", isOn: $useSubGrades.animation())
                                        .tint(.orange)
                                    
                                    if useSubGrades {
                                        Divider()
                                        
                                        // Guidance
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("Anleitung") // Praktische Anleitung
                                                Spacer()
                                                if let g = parsedGuidance {
                                                    Text(String(format: "%.0f Pkt", g)).foregroundStyle(.secondary).font(.caption)
                                                }
                                            }
                                            .font(.subheadline)
                                            
                                            TextField("Punkte (Schule)", text: $guidanceGradeText)
                                                .keyboardType(.decimalPad)
                                                .focused($focusedField, equals: .guidance)
                                                .padding(10)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        
                                        // Deepening
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("Vertiefung") // Praktische Vertiefung
                                                Spacer()
                                                if let d = parsedDeepening {
                                                    Text(String(format: "%.0f Pkt", d)).foregroundStyle(.secondary).font(.caption)
                                                }
                                            }
                                            .font(.subheadline)
                                            
                                            TextField("Punkte (Schule)", text: $deepeningGradeText)
                                                .keyboardType(.decimalPad)
                                                .focused($focusedField, equals: .deepening)
                                                .padding(10)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        
                                        // Activity
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("Tätigkeit (x2)") // Praktische Tätigkeit
                                                Spacer()
                                                if let a = parsedActivity {
                                                    Text(String(format: "%.0f Pkt (zählt doppelt)", a)).foregroundStyle(.secondary).font(.caption)
                                                }
                                            }
                                            .font(.subheadline)
                                            
                                            TextField("Punkte (Betrieb)", text: $activityGradeText)
                                                .keyboardType(.decimalPad)
                                                .focused($focusedField, equals: .activity)
                                                .padding(10)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        
                                        Divider()
                                        
                                        HStack {
                                            Text("Berechnete Note")
                                                .font(.headline)
                                            Spacer()
                                            if let avg = calculatedAverage {
                                                Text(String(format: "%.2f", avg))
                                                    .font(.title3.weight(.bold))
                                                    .monospacedDigit()
                                                    .foregroundStyle(.orange)
                                            } else {
                                                Text("–")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    } else {
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

                            Text("Es können maximal zwei Praktikumsnoten (1. und 2. Halbjahr) hinterlegt werden.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
            .keyboardDismissToolbar()
            .hideKeyboardOnTap()
            .onAppear {
                halfYear = suggestedHalfYear
            }
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
                grade: value,
                halfYear: halfYear,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                company: trimmedCompany.isEmpty ? nil : trimmedCompany,
                date: date,
                guidanceGrade: useSubGrades ? parsedGuidance : nil,
                deepeningGrade: useSubGrades ? parsedDeepening : nil,
                activityGrade: useSubGrades ? parsedActivity : nil,
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
