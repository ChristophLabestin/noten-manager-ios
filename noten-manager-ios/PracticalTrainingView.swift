import SwiftUI
import CryptoKit

struct PracticalTrainingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var gradeText: String = ""
    @State private var company: String = ""
    @State private var note: String = ""
    @State private var halfYearSelection: Int = 1
    @State private var editingId: String?
    @State private var error: String?
    @State private var isSaving: Bool = false

    private var canSave: Bool {
        guard store.schoolType == .fos else { return false }
        guard store.encryptionKey != nil else { return false }
        guard let g = Double(gradeText), (0...15).contains(g) else { return false }
        return true
    }

    private var sortedPracticalGrades: [PracticalGradeEntry] {
        let entries = store.practicalPerformance?.grades ?? []
        return entries.sorted { lhs, rhs in
            if let lh = lhs.halfYear, let rh = rhs.halfYear, lh != rh {
                return lh < rh
            }
            if let lh = lhs.halfYear, rhs.halfYear == nil { return true }
            if lhs.halfYear == nil, let rh = rhs.halfYear { return false }
            return lhs.date < rhs.date
        }
    }

    private var nextHalfYearSuggestion: Int {
        if !sortedPracticalGrades.contains(where: { $0.halfYear == 1 }) { return 1 }
        if !sortedPracticalGrades.contains(where: { $0.halfYear == 2 }) { return 2 }
        return 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deine Praktikumsnoten") {
                    if sortedPracticalGrades.isEmpty {
                        Text("Trage zuerst die Note des ersten Praktikums ein. Danach kannst du die zweite hinzufügen.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedPracticalGrades) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(label(for: entry))
                                        .font(.headline)
                                    if let company = entry.company, !company.isEmpty {
                                        Text(company)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let note = entry.note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(String(format: "%.1f", entry.grade))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(Color.blue)
                                    .clipShape(Capsule())
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                startEditing(entry)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await delete(entry) }
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section(editingId == nil ? "Praktikumsnote hinzufügen" : "Praktikumsnote bearbeiten") {
                    Picker("Halbjahr", selection: $halfYearSelection) {
                        Text("1. Halbjahr").tag(1)
                        Text("2. Halbjahr").tag(2)
                    }
                    .pickerStyle(.segmented)

                    TextField("Punkte (0–15)", text: $gradeText)
                        .keyboardType(.decimalPad)
                    TextField("Unternehmen (optional)", text: $company)
                    TextField("Notiz (optional)", text: $note)
                }

                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(editingId == nil ? "Hinzufügen" : "Speichern")
                        }
                    }
                    .disabled(!canSave || isSaving)

                    if editingId != nil {
                        Button("Eingabe zurücksetzen") {
                            resetForm()
                        }
                        .disabled(isSaving)
                    }

                    if store.practicalPerformance != nil {
                        Button(role: .destructive) {
                            Task { await deleteAllEntries() }
                        } label: {
                            Text("Alle Praktikumsnoten löschen")
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Praktikum")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .onAppear {
                syncFromStore()
            }
            .onChange(of: store.practicalPerformance) { _ in
                syncFromStore()
            }
        }
    }

    private func label(for entry: PracticalGradeEntry) -> String {
        if let hy = entry.halfYear {
            return hy == 1 ? "1. Praktikum" : "2. Praktikum"
        }
        return "Praktikum"
    }

    private func syncFromStore() {
        resetForm()
    }

    private func save() async {
        guard !isSaving else { return }
        guard let key = store.encryptionKey else {
            error = "Schlüssel noch nicht geladen."
            return
        }
        guard let gradeValue = Double(gradeText), (0...15).contains(gradeValue) else {
            error = "Bitte eine gültige Punktzahl (0–15) eingeben."
            return
        }
        isSaving = true
        error = nil
        do {
            let cleanCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try await store.upsertPracticalGrade(
                id: editingId,
                grade: gradeValue,
                halfYear: halfYearSelection,
                note: cleanNote.isEmpty ? nil : cleanNote,
                company: cleanCompany.isEmpty ? nil : cleanCompany,
                using: key
            )
            resetForm()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func startEditing(_ entry: PracticalGradeEntry) {
        editingId = entry.id
        gradeText = String(entry.grade)
        company = entry.company ?? ""
        note = entry.note ?? ""
        halfYearSelection = entry.halfYear ?? nextHalfYearSuggestion
    }

    private func resetForm() {
        editingId = nil
        gradeText = ""
        company = ""
        note = ""
        halfYearSelection = nextHalfYearSuggestion
        error = nil
    }

    private func delete(_ entry: PracticalGradeEntry) async {
        guard let key = store.encryptionKey else {
            error = "Schlüssel noch nicht geladen."
            return
        }
        isSaving = true
        error = nil
        do {
            try await store.deletePracticalGrade(id: entry.id, using: key)
            resetForm()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }

    private func deleteAllEntries() async {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        do {
            try await store.deletePracticalPerformance()
            resetForm()
        } catch let err {
            error = err.localizedDescription
        }
        isSaving = false
    }
}
