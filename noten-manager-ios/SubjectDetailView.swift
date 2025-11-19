import SwiftUI
import CryptoKit
import FirebaseAuth

struct SubjectDetailView: View {
    @EnvironmentObject var store: GradesStore
    let subject: Subject

    enum HalfYearFilter: Hashable { case all, one, two }

    @State private var halfYear: HalfYearFilter = .all

    // Inline-Editing State
    @State private var editingGradeId: String? = nil
    @State private var editedGradeValue: String = ""
    @State private var editedWeight: Double = 1
    @State private var editedDate: Date = Date()
    @State private var editedHalfYear: Int = 1
    @State private var editedNoteInline: String = ""
    @State private var isSaving: Bool = false

    // Notiz Sheet
    @State private var showNoteSheet: Bool = false
    @State private var noteEditGradeId: String? = nil
    @State private var noteEditText: String = ""

    // Löschen
    @State private var deleteConfirmGradeId: String? = nil

    // Toolbar State
    @State private var isSigningOut: Bool = false

    // BottomNav Navigation
    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinal: Bool = false
    @State private var navigateToSubjects: Bool = false

    private var allGrades: [GradeWithId] {
        store.gradesBySubject[subject.name] ?? []
    }

    private var filteredGrades: [GradeWithId] {
        allGrades.filter { g in
            switch halfYear {
            case .all: return true
            case .one: return g.halfYear == 1
            case .two: return g.halfYear == 2
            }
        }
    }

    private var sortedGrades: [GradeWithId] {
        filteredGrades.sorted { $0.date > $1.date }
    }

    private func calculateGradeWeightForSubject(subjectType: Int, weight: Double) -> Double {
        if subjectType == 1 {
            return (weight == 3 ? 2 : (weight == 2 ? 2 : 1))
        }
        if subjectType == 0 {
            return (weight == 3 ? 2 : (weight == 1 ? 2 : 1))
        }
        return 1
    }

    private func averageForSubject() -> Double? {
        guard !filteredGrades.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in filteredGrades {
            let w = calculateGradeWeightForSubject(subjectType: subject.type, weight: g.weight)
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    private func formatAverage(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.2f", v)
    }

    private func gradeColor(_ value: Double) -> Color {
        if value >= 7 { return .green }
        if value >= 4 { return .orange }
        return .red
    }

    private func avgColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        return gradeColor(v)
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Halbjahresfilter im pill-förmigen Container (wie Home-Layout)
                HStack {
                    HStack(spacing: 4) {
                        SegmentButton(title: "Alle", active: halfYear == .all) { halfYear = .all }
                        SegmentButton(title: "1. Hj", active: halfYear == .one) { halfYear = .one }
                        SegmentButton(title: "2. Hj", active: halfYear == .two) { halfYear = .two }
                    }
                    .padding(4)
                    .background(toggleBackground)
                    .clipShape(Capsule())
                    .shadow(color: toggleShadow, radius: 8, x: 0, y: 4)

                    Spacer()
                }
                .padding(.horizontal)

                // Summary
                HStack(spacing: 12) {
                    SummaryCard(title: "Durchschnitt") {
                        let avg = averageForSubject()
                        Text(formatAverage(avg))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(avgColor(avg).opacity(0.15))
                            .foregroundStyle(avgColor(avg))
                            .clipShape(Capsule())
                    }
                    SummaryCard(title: "Noten") {
                        Text("\(allGrades.count)")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)

                // Details
                if subject.teacher != nil || subject.alias != nil || subject.email != nil || subject.room != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details").font(.title3).bold()
                        VStack(spacing: 8) {
                            if let t = subject.teacher, !t.isEmpty {
                                detailRow(label: "Lehrkraft", value: t)
                            }
                            if let a = subject.alias, !a.isEmpty {
                                detailRow(label: "Kürzel", value: a)
                            }
                            if let e = subject.email, !e.isEmpty {
                                detailRow(label: "E-Mail", value: e, isEmail: true)
                            }
                            if let r = subject.room, !r.isEmpty {
                                detailRow(label: "Raum", value: r)
                            }
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                }

                // Notenliste
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noten").font(.title3).bold()
                    Text("Tippe auf eine Note, um diese zu bearbeiten")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if sortedGrades.isEmpty {
                        Text("Keine Noten vorhanden").foregroundStyle(.secondary).padding(.top, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(sortedGrades, id: \.id) { g in
                                gradeCard(g)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 6) {
                    Text(subject.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subject.type == 1 ? "Hauptfach" : "Nebenfach")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(subject.type == 1 ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                        .foregroundStyle(subject.type == 1 ? .blue : .gray)
                        .clipShape(Capsule())
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await signOut() }
                } label: {
                    if isSigningOut {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.title3)
                    }
                }
                .accessibilityLabel("Abmelden")
                .disabled(isSigningOut)
            }
        }
        .sheet(isPresented: $showNoteSheet) {
            NavigationStack {
                Form {
                    Section("Notiz") {
                        TextEditor(text: $noteEditText)
                            .frame(minHeight: 120)
                    }
                }
                .navigationTitle("Notiz bearbeiten")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { showNoteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Speichern") { Task { await saveNote() } }
                            .disabled(noteEditGradeId == nil)
                    }
                }
            }
        }
        .confirmationDialog("Note löschen?", isPresented: .constant(deleteConfirmGradeId != nil), presenting: deleteConfirmGradeId) { gid in
            Button("Löschen", role: .destructive) {
                Task { await deleteGrade(gradeId: gid) }
            }
            Button("Abbrechen", role: .cancel) {
                deleteConfirmGradeId = nil
            }
        } message: { _ in
            Text("Möchtest du diese Note wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.")
        }
        .background(
            Group {
                NavigationLink(
                    destination: AppSettingsView().environmentObject(store),
                    isActive: $navigateToSettings
                ) { EmptyView() }
                NavigationLink(
                    destination: AbiturExamView().environmentObject(store),
                    isActive: $navigateToFinal
                ) { EmptyView() }
                NavigationLink(
                    destination: SubjectsManageView().environmentObject(store),
                    isActive: $navigateToSubjects
                ) { EmptyView() }
            }
        )
    }

    // MARK: - Helpers (Optik)

    private var toggleBackground: Color {
        colorScheme == .dark
            ? Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.9)
            : .white
    }

    private var toggleShadow: Color {
        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.12)
    }

    @ViewBuilder
    private func detailRow(label: String, value: String, isEmail: Bool = false) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            if isEmail, let url = URL(string: "mailto:\(value)") {
                Link(value, destination: url).font(.subheadline)
            } else {
                Text(value).font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func gradeCard(_ grade: GradeWithId) -> some View {
        let isEditing = (editingGradeId == grade.id)

        VStack(spacing: 8) {
            HStack(alignment: .top) {
                // Meta links
                VStack(alignment: .leading, spacing: 6) {
                    // Typ / Gewicht
                    if isEditing {
                        Picker("Typ", selection: $editedWeight) {
                            if subject.type == 0 {
                                Text("Fachreferat").tag(3.0)
                                Text("Kurzarbeit").tag(1.0)
                                Text("Mündlich").tag(0.0)
                            } else {
                                Text("Fachreferat").tag(3.0)
                                Text("Schulaufgabe").tag(2.0)
                                Text("Kurzarbeit").tag(1.0)
                                Text("Mündlich").tag(0.0)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    } else {
                        Text(grade.weight == 0 ? "Mündlich" :
                             grade.weight == 1 ? "Kurzarbeit" :
                             grade.weight == 2 ? "Schulaufgabe" : "Fachreferat")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Halbjahr
                    if isEditing {
                        Picker("Halbjahr", selection: $editedHalfYear) {
                            Text("1. Hj").tag(1)
                            Text("2. Hj").tag(2)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 160)
                    } else if let hj = grade.halfYear {
                        Text(hj == 1 ? "1. Hj" : "2. Hj")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Datum
                    if isEditing {
                        DatePicker("", selection: $editedDate, displayedComponents: .date)
                            .labelsHidden()
                    } else {
                        Text(grade.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Note rechts
                if isEditing {
                    TextField("Note", text: $editedGradeValue)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(String(format: "%.1f", grade.grade))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(gradeColor(grade.grade).opacity(0.15))
                        .foregroundStyle(gradeColor(grade.grade))
                        .clipShape(Capsule())
                }
            }

            HStack {
                // Notiz
                if let note = grade.note, !note.isEmpty {
                    Button("Notiz anzeigen") {
                        openNoteEditor(for: grade.id, current: note)
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                } else {
                    Button("Notiz hinzufügen") {
                        openNoteEditor(for: grade.id, current: "")
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                }

                Spacer()

                // Aktionen
                if isSaving {
                    ProgressView().padding(.trailing, 8)
                }

                if isEditing {
                    Button {
                        Task { await saveInlineEdit(gradeId: grade.id) }
                    } label: {
                        Label("Speichern", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Button {
                        cancelInlineEdit()
                    } label: {
                        Label("Abbrechen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        startInlineEdit(grade)
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        deleteConfirmGradeId = grade.id
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if !isEditing {
                startInlineEdit(grade)
            }
        }
    }

    private func startInlineEdit(_ grade: GradeWithId) {
        editingGradeId = grade.id
        editedGradeValue = String(grade.grade)
        editedWeight = grade.weight
        editedDate = grade.date
        editedHalfYear = grade.halfYear ?? 1
        editedNoteInline = grade.note ?? ""
    }

    private func cancelInlineEdit() {
        editingGradeId = nil
        editedGradeValue = ""
        editedNoteInline = ""
    }

    private func saveInlineEdit(gradeId: String) async {
        guard !isSaving, let key = store.encryptionKey else { return }
        isSaving = true
        defer { isSaving = false }
        let value = Double(editedGradeValue) ?? 0
        do {
            try await store.updateGradeInFirestore(
                subjectId: subject.name,
                gradeId: gradeId,
                grade: value,
                weight: editedWeight,
                date: editedDate,
                note: editedNoteInline.isEmpty ? nil : editedNoteInline,
                halfYear: editedHalfYear,
                using: key
            )
            editingGradeId = nil
        } catch {
            // Optional: Fehler anzeigen
        }
    }

    private func openNoteEditor(for gradeId: String, current: String) {
        noteEditGradeId = gradeId
        noteEditText = current
        showNoteSheet = true
    }

    private func saveNote() async {
        guard let gid = noteEditGradeId else { return }
        do {
            try await store.updateGradeNoteInFirestore(subjectId: subject.name, gradeId: gid, note: noteEditText.isEmpty ? nil : noteEditText)
            showNoteSheet = false
            noteEditGradeId = nil
            noteEditText = ""
        } catch {
            // Optional: Fehler anzeigen
        }
    }

    private func deleteGrade(gradeId: String) async {
        do {
            try await store.deleteGradeFromFirestore(subjectId: subject.name, gradeId: gradeId)
        } catch {
            // Optional: Fehler anzeigen
        }
        deleteConfirmGradeId = nil
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        do {
            store.stopListening()
            try Auth.auth().signOut()
        } catch {
            // optional: Fehlerbehandlung
        }
    }
}
