import SwiftUI
import CryptoKit

struct AddFachreferatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    // Optional vorselektiertes Fach (z. B. von SubjectDetail)
    let preselectedSubjectName: String?

    @State private var subjectName: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var isSaving: Bool = false
    @State private var error: String?
    @State private var showDeleteAlert: Bool = false
    @State private var presentationGradeText: String = ""
    @State private var paperGradeText: String = ""
    @State private var presentationWeight: Double = 0.5 // Default 50:50
    
    @FocusState private var focusedField: Field?

    private var subjects: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var canSave: Bool {
        guard let _ = store.encryptionKey else { return false }
        guard !subjectName.isEmpty else { return false }
        guard Double(presentationGradeText) != nil else { return false }
        guard Double(paperGradeText) != nil else { return false }
        return true
    }

    init(preselectedSubjectName: String? = nil) {
        self.preselectedSubjectName = preselectedSubjectName
    }

    private enum Field: Hashable {
        case note, presentationGrade, paperGrade
    }

    private var sheetTitle: String {
        store.fachreferat == nil ? "Fachreferat" : "Fachreferat bearbeiten"
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    SettingsCard(
                        title: store.fachreferat == nil ? "Fachreferat" : "Fachreferat bearbeiten",
                        subtitle: "Fach, Einzelnoten und Datum",
                        systemImage: "doc.text.fill",
                        accent: .pink
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            SettingsSectionBox {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Fach")
                                        .font(.headline)
                                    Picker("Fach", selection: $subjectName) {
                                        Text("Bitte wählen").tag("")
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
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Presentation
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Vortrag / Präsentation")
                                                .font(.subheadline)
                                            TextField("z. B. 12.0", text: $presentationGradeText)
                                                .keyboardType(.decimalPad)
                                                .submitLabel(.next)
                                                .focused($focusedField, equals: .presentationGrade)
                                                .onSubmit { focusedField = .paperGrade }
                                                .padding(12)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        
                                        // Paper
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Schriftliche Ausarbeitung")
                                                .font(.subheadline)
                                            TextField("z. B. 10.0", text: $paperGradeText)
                                                .keyboardType(.decimalPad)
                                                .submitLabel(.next)
                                                .focused($focusedField, equals: .paperGrade)
                                                .onSubmit { focusedField = .note }
                                                .padding(12)
                                                .background(Color.formInputBackground)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        }
                                        
                                        // Weighting Slider
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text("Gewichtung")
                                                    .font(.subheadline)
                                                Spacer()
                                                Text("\(Int(presentationWeight * 100))% Vortrag : \(Int((1 - presentationWeight) * 100))% Schriftlich")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Slider(value: $presentationWeight, in: 0...1, step: 0.01)
                                                .tint(.pink)
                                        }
                                        
                                        HStack {
                                            Text("Berechnete Note:")
                                                .font(.subheadline.bold())
                                            Spacer()
                                            if let p = Double(presentationGradeText), let s = Double(paperGradeText) {
                                                let avg = p * presentationWeight + s * (1 - presentationWeight)
                                                Text(String(format: "%.2f", avg))
                                                    .font(.headline)
                                                    .foregroundStyle(.pink)
                                            } else {
                                                Text("–")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.top, 4)
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
                        .buttonStyle(SoftTintButtonStyle(accent: .red))
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity).onTapGesture { hideKeyboard() })
            .sheetNavigationTitle(sheetTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ToolbarLoadingIcon()
                        } else {
                            ToolbarIcon(symbol: "checkmark", showDot: false)
                        }
                    }
                    .accessibilityLabel("Speichern")
                    .disabled(!canSave || isSaving)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDismissToolbar()
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
                    date = fr.date
                    note = fr.note ?? ""
                    
                    if let pg = fr.presentationGrade {
                        presentationGradeText = String(pg)
                    }
                    if let sg = fr.paperGrade {
                        paperGradeText = String(sg)
                    }
                    if let w = fr.presentationWeight {
                        presentationWeight = w
                    }
                    if fr.presentationGrade == nil, fr.paperGrade == nil {
                        let fallback = String(fr.grade)
                        presentationGradeText = fallback
                        paperGradeText = fallback
                    }
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
    }

    private func save() async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        error = nil
        do {
            let p = Double(presentationGradeText) ?? 0
            let s = Double(paperGradeText) ?? 0
            let grade = p * presentationWeight + s * (1 - presentationWeight)
            
            try await store.setFachreferatToFirestore(
                subjectName: subjectName,
                grade: grade,
                date: date,
                note: note.isEmpty ? nil : note,
                presentationGrade: p,
                paperGrade: s,
                presentationWeight: presentationWeight,
                using: key
            )
            dismiss()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
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
