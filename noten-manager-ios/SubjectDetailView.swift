import SwiftUI
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct SubjectDetailView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    let subject: Subject

    enum HalfYearFilter: Hashable { case all, one, two }

    // Aktueller Fachzustand (lokal, damit Umbenennen direkt sichtbar ist)
    @State private var currentSubjectName: String
    @State private var currentTeacher: String?
    @State private var currentRoom: String?
    @State private var currentEmail: String?
    @State private var currentAlias: String?

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

    // Fach bearbeiten
    @State private var showEditSubjectSheet: Bool = false
    @State private var editName: String = ""
    @State private var editTeacher: String = ""
    @State private var editRoom: String = ""
    @State private var editEmail: String = ""
    @State private var editAlias: String = ""
    @State private var isSavingSubject: Bool = false

    // BottomNav Navigation
    @State private var navigateToSettings: Bool = false
    @State private var navigateToFinal: Bool = false
    @State private var showAddGradeSheet: Bool = false

    init(subject: Subject) {
        self.subject = subject
        _currentSubjectName = State(initialValue: subject.name)
        _currentTeacher = State(initialValue: subject.teacher)
        _currentRoom = State(initialValue: subject.room)
        _currentEmail = State(initialValue: subject.email)
        _currentAlias = State(initialValue: subject.alias)
    }

    private var allGrades: [GradeWithId] {
        store.gradesBySubject[currentSubjectName] ?? []
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

    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }

    private var chipForegroundColor: Color {
        if isFeminine {
            return Color(hex: isDark ? "#f472b6" : "#ec4899")
        }
        return .blue
    }

    private var chipBackgroundColor: Color {
        if isFeminine {
            return chipForegroundColor.opacity(isDark ? 0.30 : 0.15)
        }
        return Color.blue.opacity(0.1)
    }

    private var themedBackground: some View {
        Group {
            if store.darkMode {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#1f2937"),
                        Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
                    ]),
                    center: .top,
                    startRadius: 0,
                    endRadius: 800
                )
            } else if store.theme == "feminine" {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "#fdf2ff"),
                        Color(hex: "#fdf2f8"),
                        Color(hex: "#fef2f2")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 238 / 255, green: 242 / 255, blue: 255 / 255),
                        Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255),
                        Color(red: 247 / 255, green: 247 / 255, blue: 247 / 255)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            themedBackground

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
                                .background(chipBackgroundColor)
                                .foregroundStyle(chipForegroundColor)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal)

                    // Details
                    if (currentTeacher?.isEmpty == false) ||
                       (currentAlias?.isEmpty == false) ||
                       (currentEmail?.isEmpty == false) ||
                       (currentRoom?.isEmpty == false) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details").font(.title3).bold()
                            VStack(spacing: 8) {
                                if let t = currentTeacher, !t.isEmpty {
                                    detailRow(label: "Lehrkraft", value: t)
                                }
                                if let a = currentAlias, !a.isEmpty {
                                    detailRow(label: "Kürzel", value: a)
                                }
                                if let e = currentEmail, !e.isEmpty {
                                    detailRow(label: "E-Mail", value: e, isEmail: true)
                                }
                                if let r = currentRoom, !r.isEmpty {
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
        }
        .sheet(isPresented: $showEditSubjectSheet) {
            NavigationStack {
                Form {
                    Section("Allgemein") {
                        TextField("Fachname", text: $editName)
                            .textInputAutocapitalization(.words)
                    }
                    Section("Details") {
                        TextField("Lehrkraft", text: $editTeacher)
                        TextField("Raum", text: $editRoom)
                        TextField("Kürzel", text: $editAlias)
                        TextField("E-Mail", text: $editEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                }
                .navigationTitle("Fach bearbeiten")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") {
                            cancelEditSubject()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSavingSubject ? "Speichern…" : "Speichern") {
                            Task { await handleSaveSubject() }
                        }
                        .disabled(isSavingSubject)
                    }
                }
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(currentSubjectName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if subject.type == 0 || subject.type == 1 {
                        Tag(
                            text: subject.type == 1 ? "Hauptfach" : "Nebenfach",
                            style: subject.type == 1 ? .main : .minor
                        )
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
                    Button {
                        startEditSubject()
                    } label: {
                        Image(systemName: "pencil")
                            .font(.title3)
                    }

                    Button {
                        showAddGradeSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddGradeSheet) {
            NavigationStack {
                AddGradeView(preselectedSubjectName: currentSubjectName)
                    .environmentObject(store)
            }
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
            }
        )
        // Nur den aktuellen Fachnamen an den Container melden
        .preference(key: QuickAddSubjectPreferenceKey.self, value: currentSubjectName)
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
                    .buttonStyle(.borderedProminent)
                    .font(.footnote)
                } else {
                    Button("Notiz hinzufügen") {
                        openNoteEditor(for: grade.id, current: "")
                    }
                    .buttonStyle(.borderedProminent)
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
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Button {
                        cancelInlineEdit()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        startInlineEdit(grade)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        deleteConfirmGradeId = grade.id
                    } label: {
                        Image(systemName: "trash")
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
                subjectId: currentSubjectName,
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
            try await store.updateGradeNoteInFirestore(subjectId: currentSubjectName, gradeId: gid, note: noteEditText.isEmpty ? nil : noteEditText)
            showNoteSheet = false
            noteEditGradeId = nil
            noteEditText = ""
        } catch {
            // Optional: Fehler anzeigen
        }
    }

    private func deleteGrade(gradeId: String) async {
        do {
            try await store.deleteGradeFromFirestore(subjectId: currentSubjectName, gradeId: gradeId)
        } catch {
            // Optional: Fehler anzeigen
        }
        deleteConfirmGradeId = nil
    }

    // MARK: - Fach bearbeiten

    private func startEditSubject() {
        editName = currentSubjectName
        editTeacher = currentTeacher ?? ""
        editRoom = currentRoom ?? ""
        editEmail = currentEmail ?? ""
        editAlias = currentAlias ?? ""
        showEditSubjectSheet = true
    }

    private func cancelEditSubject() {
        showEditSubjectSheet = false
        editName = ""
        editTeacher = ""
        editRoom = ""
        editEmail = ""
        editAlias = ""
    }

    private func handleSaveSubject() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !isSavingSubject else { return }

        let originalName = subject.name
        let newName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        if newName.lowercased() != originalName.lowercased(),
           store.subjects.contains(where: { $0.name.lowercased() == newName.lowercased() }) {
            return
        }

        isSavingSubject = true
        defer { isSavingSubject = false }

        let db = Firestore.firestore()
        guard let original = store.subjects.first(where: { $0.name == originalName }) else { return }

        do {
            if newName == originalName {
                let subjectDocRef = db.collection("users").document(uid).collection("subjects").document(originalName)
                try await subjectDocRef.updateData([
                    "teacher": editTeacher.isEmpty ? NSNull() : editTeacher,
                    "room": editRoom.isEmpty ? NSNull() : editRoom,
                    "email": editEmail.isEmpty ? NSNull() : editEmail,
                    "alias": editAlias.isEmpty ? NSNull() : editAlias
                ])
            } else {
                let oldRef = db.collection("users").document(uid).collection("subjects").document(originalName)
                let newRef = db.collection("users").document(uid).collection("subjects").document(newName)

                var payload: [String: Any] = [
                    "type": original.type,
                    "date": original.date,
                    "order": original.order as Any,
                    "teacher": editTeacher.isEmpty ? NSNull() : editTeacher,
                    "room": editRoom.isEmpty ? NSNull() : editRoom,
                    "email": editEmail.isEmpty ? NSNull() : editEmail,
                    "alias": editAlias.isEmpty ? NSNull() : editAlias,
                    "droppedHalfYear": original.droppedHalfYear as Any,
                    "examSubject": original.examSubject as Any,
                    "examType": original.examType?.rawValue as Any,
                    "examPointsEncrypted": original.examPointsEncrypted as Any,
                    "writtenExamPointsEncrypted": original.writtenExamPointsEncrypted as Any,
                    "oralExamPointsEncrypted": original.oralExamPointsEncrypted as Any
                ]
                payload["type"] = original.type
                payload["date"] = original.date

                try await newRef.setData(payload, merge: true)

                let oldGradesRef = oldRef.collection("grades")
                let newGradesRef = newRef.collection("grades")
                let oldGradesSnap = try await oldGradesRef.getDocuments()

                for gdoc in oldGradesSnap.documents {
                    try await newGradesRef.document(gdoc.documentID).setData(gdoc.data())
                }
                for gdoc in oldGradesSnap.documents {
                    try await gdoc.reference.delete()
                }
                try await oldRef.delete()
            }

            currentSubjectName = newName
            currentTeacher = editTeacher.isEmpty ? nil : editTeacher
            currentRoom = editRoom.isEmpty ? nil : editRoom
            currentEmail = editEmail.isEmpty ? nil : editEmail
            currentAlias = editAlias.isEmpty ? nil : editAlias

            cancelEditSubject()
        } catch {
            // Optional: Fehler anzeigen
        }
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
