import SwiftUI
import FirebaseAuth

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var newName: String = ""
    @State private var isSavingName: Bool = false
    @State private var nameSavedSuccess: Bool = false

    // BottomNav Navigation
    @State private var navigateToFinal: Bool = false
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false

    // Gemeinsame Gruppe (Klausuren + Hausaufgaben)
    @State private var groupJoinCode: String = ""
    @State private var groupNameInput: String = ""
    @State private var isCreatingGroup: Bool = false
    @State private var isJoiningGroup: Bool = false
    @State private var groupInfoMessage: String?
    @State private var groupErrorMessage: String?
    @State private var showMappingGroupId: String? = nil
    @State private var selectedSubjectsForNewGroup: Set<String> = []
    @State private var groupPendingLeave: String? = nil

    private var maxExamSubjects: Int { 4 }
    private var currentExamSubjectsCount: Int {
        store.subjects.filter { ($0.examSubject ?? false) }.count
    }
    
    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.homeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }

    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Karte: Allgemein + App-Design
                    SettingsCard(
                        title: "Allgemein",
                        subtitle: "Allgemeine App- und Account-Einstellungen"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Anzeigename
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Anzeigename")
                                    .font(.subheadline)
                                HStack {
                                    TextField("Dein Name", text: $newName)
                                        .textContentType(.name)
                                    Button {
                                        Task { await saveName() }
                                    } label: {
                                        if isSavingName { ProgressView() } else { Text("Name speichern") }
                                    }
                                    .disabled(isSavingName || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                if nameSavedSuccess {
                                    Text("✅ Name erfolgreich gespeichert!")
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                }
                            }

                            Divider().padding(.vertical, 4)

                            // Farbschema
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Farbschema")
                                    .font(.subheadline)
                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { store.theme },
                                        set: { val in Task { await store.updatePreferences(theme: val) } }
                                    )
                                ) {
                                    Text("Klassisch").tag("default")
                                    Text("Pink").tag("feminine")
                                }
                                .pickerStyle(.segmented)

                                Text("Wähle, ob die Oberfläche eher klassisch oder mit einem weicheren Farbschema angezeigt wird.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Dark Mode
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Dark Mode")
                                    .font(.subheadline)
                                Picker("", selection: Binding(
                                    get: { store.darkModeMode },
                                    set: { val in Task { await store.updatePreferences(darkModeMode: val) } }
                                )) {
                                    Text("Geräteeinstellung").tag("system")
                                    Text("Light Mode").tag("light")
                                    Text("Dark Mode").tag("dark")
                                }
                                .pickerStyle(.segmented)
                                Text("Geräteeinstellung folgt dem iOS-Modus, Light/Dark sind fest gewählt.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Weitere Einstellungen
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Weitere Einstellungen")
                                    .font(.subheadline)

                                Toggle(
                                    isOn: Binding(
                                        get: { store.compactView },
                                        set: { val in Task { await store.updatePreferences(compactView: val) } }
                                    )
                                ) {
                                    Text(
                                        store.compactView
                                        ? "Kompakte Tabellen-Ansicht aktiviert"
                                        : "Kompakte Tabellen-Ansicht deaktiviert"
                                    )
                                }

                                Toggle(
                                    isOn: Binding(
                                        get: { store.animationsEnabled },
                                        set: { val in Task { await store.updatePreferences(animationsEnabled: val) } }
                                    )
                                ) {
                                    Text(
                                        store.animationsEnabled
                                        ? "Animationen aktiviert"
                                        : "Animationen deaktiviert"
                                    )
                                }
                            }
                        }
                    }

                    // Karte: Gruppen (gemeinsame Gruppe-Logik, kein aktiver State)
                    SettingsCard(
                        title: "Gruppen",
                        subtitle: "Gemeinsame Gruppen für Klausuren und Hausaufgaben"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if store.groupIds.isEmpty {
                                Text("Lege eine Gruppe an oder tritt mit einem Code bei. Fächer werden gruppenbezogen geteilt.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(store.groupIds, id: \.self) { gid in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(store.groupNames[gid] ?? "Ohne Namen")
                                                    .font(.headline)
                                            Text(gid)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(role: .destructive) {
                                            groupPendingLeave = gid
                                        } label: {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                            .accessibilityLabel("Gruppe verlassen")
                                        }
                                        Button("Fächer abgleichen") {
                                            showMappingGroupId = gid
                                        }
                                    }
                                    .padding(12)
                                    .background(.thinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }

                            Divider().padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Neue Gruppe erstellen")
                                    .font(.subheadline)
                                TextField("Gruppenname (Pflichtfeld)", text: $groupNameInput)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Fächer einbringen")
                                        .font(.footnote)
                                    if store.availableSubjectsForNewGroup().isEmpty {
                                        Text("Alle Fächer sind bereits einer Gruppe zugeordnet.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(store.availableSubjectsForNewGroup(), id: \.name) { subj in
                                            Toggle(subj.name, isOn: Binding(
                                                get: { selectedSubjectsForNewGroup.contains(subj.name) },
                                                set: { val in
                                                    if val { selectedSubjectsForNewGroup.insert(subj.name) }
                                                    else { selectedSubjectsForNewGroup.remove(subj.name) }
                                                }
                                            ))
                                        }
                                    }
                                }
                            }
                            Button {
                                Task {
                                    guard !isCreatingGroup else { return }
                                    let trimmedName = groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmedName.isEmpty else {
                                        groupErrorMessage = "Bitte einen Gruppennamen eingeben."
                                        return
                                    }
                                    let subjects = selectedSubjectsForNewGroup.isEmpty ? store.availableSubjectsForNewGroup().map { $0.name } : Array(selectedSubjectsForNewGroup)
                                    guard !subjects.isEmpty else {
                                        groupErrorMessage = "Keine verfügbaren Fächer für diese Gruppe."
                                        return
                                    }
                                    isCreatingGroup = true
                                    groupErrorMessage = nil
                                    groupInfoMessage = nil
                                    defer { isCreatingGroup = false }
                                    do {
                                        let code = try await store.createSharedGroup(name: trimmedName, subjects: subjects)
                                        groupJoinCode = code
                                        groupInfoMessage = "Neue Gruppe erstellt. Teile den Code mit deinen Mitschülern."
                                        groupNameInput = ""
                                        selectedSubjectsForNewGroup = []
                                    } catch {
                                        groupErrorMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                if isCreatingGroup { ProgressView() } else { Text("Gruppe erstellen") }
                            }
                            .disabled(groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Divider().padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Einer Gruppe beitreten")
                                    .font(.subheadline)
                                TextField("Gruppencode", text: $groupJoinCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled(true)
                            }
                            Button {
                                Task {
                                    guard !isJoiningGroup else { return }
                                    isJoiningGroup = true
                                    groupErrorMessage = nil
                                    groupInfoMessage = nil
                                    defer { isJoiningGroup = false }
                                    do {
                                        try await store.joinSharedGroup(with: groupJoinCode)
                                        groupInfoMessage = "Erfolgreich der Gruppe beigetreten."
                                    } catch {
                                        groupErrorMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                if isJoiningGroup { ProgressView() } else { Text("Mit Code beitreten") }
                            }
                            .disabled(groupJoinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if let msg = groupInfoMessage {
                                Text(msg)
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }
                            if let err = groupErrorMessage {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    // Karte: Schuljahr & Prüfungsfächer
                    SettingsCard(
                        title: "Schuljahr",
                        subtitle: "Jahrgangsstufe und Prüfungsfächer festlegen"
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            // Schuljahr
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Jahrgangsstufe")
                                    .font(.subheadline)
                                Text("Wähle deine Jahrgangsstufe. Daraus werden Einbringung und Streichungen abgeleitet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { store.gradeYear ?? 0 },
                                        set: { val in
                                            let year = (val == 12 || val == 13) ? val : 0
                                            if year != 0 {
                                                Task { await store.updateGradeYear(year) }
                                            }
                                        }
                                    )
                                ) {
                                    Text("Bitte auswählen").tag(0)
                                    Text("12. Jahrgang").tag(12)
                                    Text("13. Jahrgang").tag(13)
                                }
                                .pickerStyle(.segmented)
                            }

                            Divider().padding(.vertical, 4)

                            // Prüfungsfächer
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Prüfungsfächer")
                                    .font(.subheadline)
                                Text("Maximal 4 Prüfungsfächer auswählen.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if store.subjects.isEmpty {
                                    Text("Lege zuerst Fächer an, um Prüfungsfächer zu wählen.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(store.subjects, id: \.name) { subject in
                                        ExamSubjectRow(
                                            subject: subject,
                                            isDisabled: !(subject.examSubject ?? false) && currentExamSubjectsCount >= maxExamSubjects,
                                            onToggle: { isOn in
                                                let nextExamType = subject.examType ?? .written
                                                Task {
                                                    await store.updateSubjectExamFlags(
                                                        subjectName: subject.name,
                                                        examSubject: isOn,
                                                        examType: nextExamType
                                                    )
                                                }
                                            }
                                        )
                                    }
                                    if currentExamSubjectsCount >= maxExamSubjects {
                                        Text("Du hast bereits 4 Prüfungsfächer ausgewählt. Entferne eines, um ein anderes Fach als Prüfungsfach zu markieren.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Info-Karte
                    SettingsCard(
                        title: "Info",
                        subtitle: nil
                    ) {
                        Text("App Version 1.4")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Account
                    SettingsCard(
                        title: "Account",
                        subtitle: nil
                    ) {
                        Button(role: .destructive) {
                            Task {
                                store.stopListening()
                                try? Auth.auth().signOut()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Abmelden")
                                    .font(.body)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Einstellungen")
                            .font(.headline)
                        Text("Profil & App verwalten")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showExamSheet = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "calendar.badge.clock")
                                    .imageScale(.large)
                                if hasOverdueExams {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .accessibilityLabel("Klausurtermine anzeigen")

                        Button {
                            showHomeworkSheet = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "checklist")
                                    .imageScale(.large)
                                if hasOverdueHomeworks {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .accessibilityLabel("Aktive Hausaufgaben anzeigen")
                    }
                }
            }
            .onAppear {
                newName = ""
                nameSavedSuccess = false
                selectedSubjectsForNewGroup = []
            }
            .background(
                Group {
                    NavigationLink(
                        destination: AbiturExamView().environmentObject(store),
                        isActive: $navigateToFinal
                    ) { EmptyView() }
                }
            )
            .sheet(isPresented: $showHomeworkSheet) {
                HomeworkListView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showExamSheet) {
                ExamListView()
                    .environmentObject(store)
            }
            .sheet(
                isPresented: Binding(
                    get: { showMappingGroupId != nil },
                    set: { if !$0 { showMappingGroupId = nil } }
                )
            ) {
                if let gid = showMappingGroupId {
                    UnifiedMappingView(groupId: gid)
                        .environmentObject(store)
                }
            }
            .alert("Gruppe verlassen?", isPresented: Binding(
                get: { groupPendingLeave != nil },
                set: { if !$0 { groupPendingLeave = nil } }
            )) {
                Button("Abbrechen", role: .cancel) {
                    groupPendingLeave = nil
                }
                Button("Verlassen", role: .destructive) {
                    if let gid = groupPendingLeave {
                        Task { await store.leaveSharedGroup(code: gid) }
                    }
                    groupPendingLeave = nil
                }
            } message: {
                Text("Möchtest du diese Gruppe wirklich verlassen?")
            }
        }
    }

    private func saveName() async {
        guard !isSavingName else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingName = true
        await store.updateUserDisplayName(name: trimmed)
        isSavingName = false
        nameSavedSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            nameSavedSuccess = false
        }
        newName = ""
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

private struct ExamSubjectRow: View {
    let subject: Subject
    let isDisabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name).font(.body)
                Tag(
                    text: subject.type == 1 ? "Hauptfach" : "Nebenfach",
                    style: subject.type == 1 ? .main : .minor
                )
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { subject.examSubject ?? false },
                set: { val in onToggle(val) }
            ))
            .labelsHidden()
            .disabled(isDisabled)
        }
    }
}
