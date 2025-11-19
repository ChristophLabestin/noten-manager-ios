import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SubjectsManageView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    // Editing state
    @State private var editingSubjectName: String? = nil
    @State private var editName: String = ""
    @State private var editTeacher: String = ""
    @State private var editRoom: String = ""
    @State private var editEmail: String = ""
    @State private var editAlias: String = ""
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false

    // Delete confirmation
    @State private var deleteConfirmName: String? = nil

    private var subjectsWithoutFachreferat: [Subject] {
        store.subjects.filter { $0.name != "Fachreferat" }
    }

    private var sortedSubjects: [Subject] {
        subjectsWithoutFachreferat.sorted { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
        }
    }

    private var mainSubjectsCount: Int {
        subjectsWithoutFachreferat.filter { $0.type == 1 }.count
    }

    private var minorSubjectsCount: Int {
        subjectsWithoutFachreferat.filter { $0.type == 0 }.count
    }

    private func formatSubjectType(_ type: Int) -> String {
        type == 1 ? "Hauptfach" : "Nebenfach"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // BurgerMenu Header
                BurgerMenuView(isSmall: true, title: "Fächerübersicht", subjectType: nil, subtitle: "Verwalte deine Fächer")
                    .environmentObject(store)

                if store.isLoading {
                    VStack(spacing: 8) {
                        ProgressView(value: store.progress, total: 100)
                        Text(store.loadingLabel).font(.footnote)
                    }
                    .padding(.horizontal)
                }

                // Summary cards
                HStack(spacing: 12) {
                    SummaryCard(title: "Fächer") {
                        Text("\(subjectsWithoutFachreferat.count)")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    SummaryCard(title: "Hauptfächer") {
                        Text("\(mainSubjectsCount)")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    SummaryCard(title: "Nebenfächer") {
                        Text("\(minorSubjectsCount)")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)

                if subjectsWithoutFachreferat.isEmpty {
                    Text("Du hast noch keine Fächer angelegt. Nutze unten die Schnellaktionen, um dein erstes Fach zu erstellen.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alle Fächer").font(.headline)
                        VStack(spacing: 12) {
                            ForEach(sortedSubjects, id: \.name) { subject in
                                subjectCard(subject)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { }
        .confirmationDialog("Fach löschen?", isPresented: .constant(deleteConfirmName != nil), presenting: deleteConfirmName) { name in
            Button("Löschen", role: .destructive) {
                Task { await handleDeleteSubject(subjectName: name) }
            }
            Button("Abbrechen", role: .cancel) {
                deleteConfirmName = nil
            }
        } message: { _ in
            Text("Möchtest du dieses Fach wirklich löschen? Alle zugehörigen Noten werden ebenfalls gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.")
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func subjectCard(_ subject: Subject) -> some View {
        let gradesCount = (store.gradesBySubject[subject.name] ?? []).count
        let isEditing = (editingSubjectName == subject.name)
        let hasDetails = (subject.teacher?.isEmpty == false) ||
                         (subject.room?.isEmpty == false) ||
                         (subject.email?.isEmpty == false) ||
                         (subject.alias?.isEmpty == false)

        VStack(spacing: 8) {
            // Header
            HStack {
                if isEditing {
                    TextField("Fachname", text: $editName)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                } else {
                    Text(subject.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                Text(formatSubjectType(subject.type))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(subject.type == 1 ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                    .foregroundStyle(subject.type == 1 ? .blue : .gray)
                    .clipShape(Capsule())
            }

            HStack {
                Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Details grid
            if isEditing || hasDetails {
                VStack(spacing: 8) {
                    if isEditing || (subject.teacher?.isEmpty == false) {
                        detailField(label: "Lehrkraft", isEditing: isEditing, text: $editTeacher, value: subject.teacher)
                    }
                    if isEditing || (subject.room?.isEmpty == false) {
                        detailField(label: "Raum", isEditing: isEditing, text: $editRoom, value: subject.room)
                    }
                    if isEditing || (subject.alias?.isEmpty == false) {
                        detailField(label: "Kürzel", isEditing: isEditing, text: $editAlias, value: subject.alias)
                    }
                    if isEditing || (subject.email?.isEmpty == false) {
                        detailField(label: "E-Mail", isEditing: isEditing, text: $editEmail, value: subject.email, keyboard: .emailAddress)
                    }
                }
                .padding(.top, 4)
            } else {
                Text("Keine Details hinzugefügt")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Footer actions
            HStack {
                if isEditing {
                    Button {
                        Task { await handleSaveSubject(originalName: subject.name) }
                    } label: {
                        Label(isSaving ? "Speichern..." : "Speichern", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Button {
                        cancelEditSubject()
                    } label: {
                        Label("Abbrechen", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                } else {
                    Button {
                        startEditSubject(subject)
                    } label: {
                        Label("Bearbeiten", systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDeleting)

                    NavigationLink {
                        SubjectDetailView(subject: subject).environmentObject(store)
                    } label: {
                        Text("Fach öffnen")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDeleting)

                    Button(role: .destructive) {
                        deleteConfirmName = subject.name
                    } label: {
                        Label(isDeleting ? "Lösche..." : "Löschen", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDeleting)
                }
                Spacer()
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func detailField(label: String, isEditing: Bool, text: Binding<String>, value: String?, keyboard: UIKeyboardType = .default) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if isEditing {
                TextField(label, text: text)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(keyboard)
                    .frame(maxWidth: 260)
            } else {
                Text(value ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Editing helpers

    private func startEditSubject(_ subject: Subject) {
        editingSubjectName = subject.name
        editName = subject.name
        editTeacher = subject.teacher ?? ""
        editRoom = subject.room ?? ""
        editEmail = subject.email ?? ""
        editAlias = subject.alias ?? ""
    }

    private func cancelEditSubject() {
        editingSubjectName = nil
        editName = ""
        editTeacher = ""
        editRoom = ""
        editEmail = ""
        editAlias = ""
    }

    // MARK: - Firestore actions

    private func handleSaveSubject(originalName: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !isSaving else { return }

        let newName = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }

        if newName.lowercased() != originalName.lowercased(),
           store.subjects.contains(where: { $0.name.lowercased() == newName.lowercased() }) {
            return
        }

        isSaving = true
        defer { isSaving = false }

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

            cancelEditSubject()
        } catch {
            // Optional: Fehler anzeigen
        }
    }

    private func handleDeleteSubject(subjectName: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !isDeleting else { return }
        isDeleting = true
        defer {
            isDeleting = false
            deleteConfirmName = nil
        }

        let db = Firestore.firestore()
        let subjectDocRef = db.collection("users").document(uid).collection("subjects").document(subjectName)
        let gradesRef = subjectDocRef.collection("grades")

        do {
            let gradesSnap = try await gradesRef.getDocuments()
            for gdoc in gradesSnap.documents {
                try await gdoc.reference.delete()
            }
            try await subjectDocRef.delete()

            if editingSubjectName == subjectName {
                cancelEditSubject()
            }
        } catch {
            // Optional: Fehler anzeigen
        }
    }
}
