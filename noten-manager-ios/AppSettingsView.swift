import SwiftUI
import FirebaseAuth
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore

    @State private var newName: String = ""
    @State private var isSavingName: Bool = false
    @State private var nameSavedSuccess: Bool = false

    @State private var navigateToFinal: Bool = false
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false

    // Gruppen
    @State private var groupJoinCode: String = ""
    @State private var groupNameInput: String = ""
    @State private var isCreatingGroup: Bool = false
    @State private var isJoiningGroup: Bool = false
    @State private var groupInfoMessage: String?
    @State private var groupErrorMessage: String?
    @State private var showMappingGroupId: String? = nil
    @State private var selectedSubjectsForNewGroup: Set<String> = []
    @State private var groupPendingLeave: String? = nil
    @State private var copiedGroupId: String? = nil

    // Schuljahr
    @State private var newSchoolYearName: String = ""
    @State private var isCreatingSchoolYearLocal: Bool = false
    @State private var schoolYearMessage: String?
    @State private var schoolYearError: String?
    @State private var schoolYearInputIsValid: Bool = false

    // Reset
    @State private var showResetAccountSheet: Bool = false
    @State private var showResetYearSheet: Bool = false
    @State private var resetAccountPassword: String = ""
    @State private var resetYearPassword: String = ""
    @State private var resetAccountSlideDone: Bool = false
    @State private var resetYearSlideDone: Bool = false
    @State private var isResettingAccount: Bool = false
    @State private var isResettingYear: Bool = false
    @State private var resetError: String?

    // Typografie-Hierarchie
    private let sectionHeaderFont: Font = .headline.weight(.semibold)
    private let helperFont: Font = .footnote

    private var maxExamSubjects: Int { 4 }
    private var currentExamSubjectsCount: Int {
        store.subjects.filter { ($0.examSubject ?? false) }.count
    }

    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }

    private var hasHomeworkDueTomorrow: Bool {
        let cal = Calendar.current
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }
    }

    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }

    private var homeworkReminderDate: Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = store.homeworkReminderHour
        comps.minute = store.homeworkReminderMinute
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func isValidSchoolYear(_ value: String) -> Bool {
        let pattern = "^(\\d{4})-(\\d{2})$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = value as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: value, options: [], range: range), match.numberOfRanges == 3 else {
            return false
        }
        guard
            let startRange = Range(match.range(at: 1), in: value),
            let endRange = Range(match.range(at: 2), in: value)
        else { return false }
        guard let start = Int(value[startRange]), let suffix = Int(value[endRange]) else { return false }
        return ((start + 1) % 100) == suffix
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    generalCard
                    groupsCard
                    schoolYearCard
                    onboardingCard
                    resetCard
                    accountCard
                    infoCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Einstellungen").font(.headline)
                        Text("Profil & App verwalten")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button { showExamSheet = true } label: {
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

                        Button { showHomeworkSheet = true } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "checklist")
                                    .imageScale(.large)
                                if hasOverdueHomeworks || hasHomeworkDueTomorrow {
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
            .sheet(isPresented: $showResetAccountSheet) {
                ResetConfirmSheet(
                    title: "Account zurücksetzen",
                    message: "Wirklich alle Daten löschen? Dies kann nicht rückgängig gemacht werden.",
                    password: $resetAccountPassword,
                    isPresented: $showResetAccountSheet,
                    slideDone: $resetAccountSlideDone,
                    isProcessing: isResettingAccount,
                    errorMessage: resetError,
                    confirmAction: confirmResetAccount
                )
            }
            .sheet(isPresented: $showResetYearSheet) {
                ResetConfirmSheet(
                    title: "Aktives Schuljahr zurücksetzen",
                    message: "Alle Daten des aktiven Schuljahres werden gelöscht.",
                    password: $resetYearPassword,
                    isPresented: $showResetYearSheet,
                    slideDone: $resetYearSlideDone,
                    isProcessing: isResettingYear,
                    errorMessage: resetError,
                    confirmAction: confirmResetYear
                )
            }
            .alert("Gruppe verlassen?", isPresented: Binding(
                get: { groupPendingLeave != nil },
                set: { if !$0 { groupPendingLeave = nil } }
            )) {
                Button("Abbrechen", role: .cancel) { groupPendingLeave = nil }
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

    private var generalCard: some View {
        SettingsCard(
            title: "Allgemein",
            subtitle: "Allgemeine App- und Account-Einstellungen"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anzeigename")
                        .font(sectionHeaderFont)
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Farbschema")
                        .font(sectionHeaderFont)
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
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Dark Mode")
                        .font(sectionHeaderFont)
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
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Weitere Einstellungen")
                        .font(sectionHeaderFont)

                    Toggle(
                        isOn: Binding(
                            get: { store.compactView },
                            set: { val in Task { await store.updatePreferences(compactView: val) } }
                        )
                    ) {
                        Text(store.compactView ? "Kompakte Tabellen-Ansicht aktiviert" : "Kompakte Tabellen-Ansicht deaktiviert")
                    }

                    Toggle(
                        isOn: Binding(
                            get: { store.animationsEnabled },
                            set: { val in Task { await store.updatePreferences(animationsEnabled: val) } }
                        )
                    ) {
                        Text(store.animationsEnabled ? "Animationen aktiviert" : "Animationen deaktiviert")
                    }

                    DatePicker(
                        "Hausaufgaben-Erinnerung (täglich, 1 Tag vor Fälligkeit)",
                        selection: Binding(
                            get: { homeworkReminderDate },
                            set: { newVal in
                                let comps = Calendar.current.dateComponents([.hour, .minute], from: newVal)
                                let h = comps.hour ?? 19
                                let m = comps.minute ?? 0
                                Task { await store.updateHomeworkReminderTime(hour: h, minute: m) }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.compact)
                    Text("Standard ist 19:00 Uhr. Wir erinnern am Vortag, falls die Hausaufgabe dann noch offen ist.")
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sections

    private var schoolYearCard: some View {
        SettingsCard(
            title: "Schuljahr",
            subtitle: "Aktives Schuljahr, Jahrgang und Prüfungsfächer"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aktives Schuljahr")
                        .font(sectionHeaderFont)
                    if store.schoolYears.isEmpty {
                        Text("Noch keine Schuljahre gefunden. Lege eines an oder warte, bis es automatisch erstellt wird.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.schoolYears, id: \.self) { sy in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sy)
                                        .font(.headline)
                                    if store.activeSchoolYearId == sy {
                                        Text("Aktiv")
                                            .font(helperFont)
                                            .foregroundStyle(.green)
                                    }
                                }
                                Spacer()
                                Button {
                                    Task { await store.setActiveSchoolYear(id: sy) }
                                } label: {
                                    Image(systemName: store.activeSchoolYearId == sy ? "largecircle.fill.circle" : "circle")
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Neues Schuljahr anlegen")
                        .font(sectionHeaderFont)
                    TextField("z. B. 2026-27", text: Binding(
                        get: { newSchoolYearName },
                        set: { val in
                            let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                            newSchoolYearName = trimmed
                            schoolYearInputIsValid = isValidSchoolYear(trimmed)
                            schoolYearError = nil
                            schoolYearMessage = nil
                        }
                    ))
                    .textInputAutocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.numbersAndPunctuation)

                    Button {
                        Task { await createSchoolYear() }
                    } label: {
                        if isCreatingSchoolYearLocal {
                            ProgressView()
                        } else {
                            Text("Anlegen & aktivieren")
                                .foregroundColor(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!schoolYearInputIsValid || store.schoolYears.contains(where: { $0 == newSchoolYearName }))

                    if let msg = schoolYearMessage {
                        Text(msg)
                            .font(helperFont)
                            .foregroundStyle(.green)
                    }
                    if let err = schoolYearError {
                        Text(err)
                            .font(helperFont)
                            .foregroundStyle(.red)
                    }
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Jahrgangsstufe")
                        .font(sectionHeaderFont)
                    Text("Wähle deine Jahrgangsstufe für das aktive Schuljahr.")
                        .font(helperFont)
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prüfungsfächer")
                        .font(sectionHeaderFont)
                    Text("Maximal 4 Prüfungsfächer auswählen.")
                        .font(helperFont)
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
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    

    private var groupsCard: some View {
        SettingsCard(
            title: "Gruppen",
            subtitle: "Gemeinsame Gruppen für Klausuren und Hausaufgaben"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if store.groupIds.isEmpty {
                    Text("Lege eine Gruppe an oder tritt mit einem Code bei. Fächer werden gruppenbezogen geteilt.")
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.groupIds, id: \.self) { gid in
                        VStack(alignment: .leading, spacing: 6) {
                            let isCopied = copiedGroupId == gid
                            VStack(alignment: .leading, spacing: 10) {
                                // Top row: Name left, Code + Kopieren rechts
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(store.groupNames[gid] ?? "Ohne Namen")
                                            .font(.headline)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text(gid)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Button {
                                            UIPasteboard.general.string = gid
                                            withAnimation { copiedGroupId = gid }
                                            Task {
                                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                                await MainActor.run {
                                                    if copiedGroupId == gid {
                                                        withAnimation { copiedGroupId = nil }
                                                    }
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                                    .foregroundStyle(isCopied ? .green : .blue)
                                                Text(isCopied ? "Kopiert" : "Kopieren")
                                                    .font(.caption)
                                                    .foregroundStyle(isCopied ? .green : .blue)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Gruppencode kopieren")
                                    }
                                }

                                // Bottom row: Abgleichen links, Verlassen rechts
                                HStack {
                                    Button("Fächer abgleichen") {
                                        showMappingGroupId = gid
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        groupPendingLeave = gid
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                            Text("Verlassen")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Gruppe verlassen")
                                }
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
                        .font(sectionHeaderFont)
                    TextField("Gruppenname (Pflichtfeld)", text: $groupNameInput)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fächer einbringen")
                            .font(helperFont)
                        if store.availableSubjectsForNewGroup().isEmpty {
                            Text("Alle Fächer sind bereits einer Gruppe zugeordnet.")
                                .font(helperFont)
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
                        .font(sectionHeaderFont)
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
                        .font(helperFont)
                        .foregroundStyle(.green)
                }
                if let err = groupErrorMessage {
                    Text(err)
                        .font(helperFont)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var infoCard: some View {
        SettingsCard(title: "Info", subtitle: nil) {
            Text("App Version 1.4")
                .font(helperFont)
                .foregroundStyle(.secondary)
        }
    }

    private var accountCard: some View {
        SettingsCard(title: "Account", subtitle: nil) {
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

    private var resetCard: some View {
        SettingsCard(
            title: "Daten zurücksetzen",
            subtitle: "Account oder aktuelles Schuljahr bereinigen"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button(role: .destructive) {
                    resetAccountPassword = ""
                    resetAccountSlideDone = false
                    resetError = nil
                    showResetAccountSheet = true
                } label: {
                    Text("Account komplett zurücksetzen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button(role: .destructive) {
                    resetYearPassword = ""
                    resetYearSlideDone = false
                    resetError = nil
                    showResetYearSheet = true
                } label: {
                    Text("Aktives Schuljahr zurücksetzen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

                Text("Diese Aktionen löschen Daten unwiderruflich. Bestätige mit Slider und Passwort.")
                    .font(helperFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var onboardingCard: some View {
        SettingsCard(
            title: "Onboarding",
            subtitle: "Setup-Assistent erneut durchlaufen"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Starte den Einrichtungs-Assistenten erneut, um Schuljahr, Gruppen und Fächer neu zu setzen. Bestehende Daten bleiben erhalten.")
                    .font(helperFont)
                    .foregroundStyle(.secondary)
                Button("Onboarding neu starten") {
                    Task { await store.restartOnboarding() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

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

    private func createSchoolYear() async {
        guard !isCreatingSchoolYearLocal else { return }
        isCreatingSchoolYearLocal = true
        defer { isCreatingSchoolYearLocal = false }
        let created = await store.createSchoolYear(name: newSchoolYearName)
        if let id = created {
            schoolYearMessage = "Neues Schuljahr \(id) aktiviert."
            schoolYearError = nil
            newSchoolYearName = ""
            schoolYearInputIsValid = false
        } else {
            schoolYearError = "Schuljahr konnte nicht angelegt werden."
            schoolYearMessage = nil
        }
    }

    private func confirmResetAccount() {
        Task {
            guard !isResettingAccount else { return }
            isResettingAccount = true
            defer { isResettingAccount = false }
            do {
                try await store.resetEntireAccount(password: resetAccountPassword)
                showResetAccountSheet = false
                resetAccountPassword = ""
                resetAccountSlideDone = false
                resetError = nil
            } catch {
                resetError = error.localizedDescription
            }
        }
    }

    private func confirmResetYear() {
        Task {
            guard !isResettingYear else { return }
            isResettingYear = true
            defer { isResettingYear = false }
            do {
                try await store.resetActiveSchoolYear(password: resetYearPassword)
                showResetYearSheet = false
                resetYearPassword = ""
                resetYearSlideDone = false
                resetError = nil
            } catch {
                resetError = error.localizedDescription
            }
        }
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
                    .font(.title3.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
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
                if subject.isElective {
                    Tag(text: "Wahlfach", style: .elective)
                } else {
                    Tag(
                        text: subject.type == 1 ? "Hauptfach" : "Nebenfach",
                        style: subject.type == 1 ? .main : .minor
                    )
                }
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

private struct ResetConfirmSheet: View {
    let title: String
    let message: String
    @Binding var password: String
    @Binding var isPresented: Bool
    @Binding var slideDone: Bool
    let isProcessing: Bool
    let errorMessage: String?
    let confirmAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(title).font(.title3).bold()
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                SlideToConfirmView(isConfirmed: $slideDone)
                    .frame(height: 56)

                SecureField("Passwort eingeben", text: $password)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if let err = errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Button {
                    confirmAction()
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Bestätigen")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!(slideDone && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isProcessing)

                Button("Abbrechen") {
                    isPresented = false
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding()
        }
    }
}

private struct SlideToConfirmView: View {
    @Binding var isConfirmed: Bool
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 52
            let maxOffset = width - height

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(.secondarySystemBackground))
                Text(isConfirmed ? "Bereit" : "Zum Bestätigen schieben")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Circle()
                    .fill(isConfirmed ? Color.green : Color.blue)
                    .frame(width: height - 6, height: height - 6)
                    .offset(x: max(0, min(dragOffset, maxOffset)))
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if isConfirmed { return }
                            dragOffset = max(0, min(value.translation.width, maxOffset))
                        }
                        .onEnded { _ in
                            if dragOffset > maxOffset * 0.8 {
                                isConfirmed = true
                                dragOffset = maxOffset
                            } else {
                                isConfirmed = false
                                dragOffset = 0
                            }
                        }
                    )
                    .padding(.leading, 3)
            }
            .frame(height: height)
        }
    }
}
