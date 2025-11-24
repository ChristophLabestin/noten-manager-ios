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
    @State private var showSchoolYearWizard: Bool = false

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

    private var reminderTimeText: String {
        String(format: "%02d:%02d", store.homeworkReminderHour, store.homeworkReminderMinute)
    }

    private var overdueHomeworksCount: Int {
        let now = Date()
        return store.allHomeworks.filter { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }.count
    }

    private var homeworkDueTomorrowCount: Int {
        let cal = Calendar.current
        return store.allHomeworks.filter { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }.count
    }

    private var overdueExamsCount: Int {
        let now = Date()
        return store.allExams.filter { exam in
            !exam.isCompleted && exam.date < now
        }.count
    }

    private var gradeOptions: [Int] {
        store.schoolType == .fos ? [11, 12, 13] : [12, 13]
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

    private var headerCard: some View {
        SettingsCard(
            title: "Einstellungen",
            subtitle: "Status, Thema und Erinnerungen",
            systemImage: "slider.horizontal.3",
            accent: .indigo,
            trailing: {
                PillBadge(
                    text: store.schoolType == .fos ? "FOS" : "BOS",
                    systemImage: "seal.fill",
                    foreground: Color.indigo,
                    background: Color.indigo.opacity(0.14)
                )
            }
        ) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HeaderTile(
                        title: "Schuljahr",
                        value: store.activeSchoolYearId ?? "—",
                        icon: "calendar",
                        accent: .cyan
                    )
                    HeaderTile(
                        title: "Jahrgang",
                        value: store.gradeYear.map { "\($0)." } ?? "—",
                        icon: "graduationcap.fill",
                        accent: .mint
                    )
                }
                HStack(spacing: 12) {
                    HeaderTile(
                        title: "Erinnerung",
                        value: reminderTimeText,
                        icon: "bell.fill",
                        accent: .orange
                    )
                    HeaderTile(
                        title: "Prüfungsfächer",
                        value: "\(currentExamSubjectsCount)/\(maxExamSubjects)",
                        icon: "checkmark.seal.fill",
                        accent: .indigo
                    )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        PillBadge(
                            text: store.theme == "feminine" ? "Soft/Pink" : "Klassisch",
                            systemImage: "paintpalette.fill",
                            foreground: Color.orange,
                            background: Color.orange.opacity(0.15)
                        )
                        if overdueHomeworksCount > 0 {
                            PillBadge(
                                text: "HW fällig: \(overdueHomeworksCount)",
                                systemImage: "exclamationmark.triangle.fill",
                                foreground: .orange,
                                background: Color.orange.opacity(0.16)
                            )
                        }
                        if homeworkDueTomorrowCount > 0 {
                            PillBadge(
                                text: "HW morgen: \(homeworkDueTomorrowCount)",
                                systemImage: "clock.badge.exclamationmark",
                                foreground: .yellow,
                                background: Color.yellow.opacity(0.16)
                            )
                        }
                        if overdueExamsCount > 0 {
                            PillBadge(
                                text: "Prüfungen fällig: \(overdueExamsCount)",
                                systemImage: "calendar.badge.exclamationmark",
                                foreground: .red,
                                background: Color.red.opacity(0.16)
                            )
                        }
                        if overdueHomeworksCount == 0 && homeworkDueTomorrowCount == 0 && overdueExamsCount == 0 {
                            PillBadge(
                                text: "Alles im Plan",
                                systemImage: "checkmark.circle.fill",
                                foreground: .green,
                                background: Color.green.opacity(0.15)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.leading, 2)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    headerCard
                    generalCard
                    schoolYearCard
                    groupsCard
                    onboardingCard
                    resetCard
                    accountCard
                    infoCard

                    NavigationLink(
                        destination: AbiturExamView().environmentObject(store),
                        isActive: $navigateToFinal
                    ) { EmptyView() }
                    .frame(width: 0, height: 0)
                    .hidden()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine")
            )
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
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
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 0) {
                        Button { showExamSheet = true } label: {
                            ToolbarIcon(symbol: "calendar.badge.clock", showDot: hasOverdueExams)
                        }
                        .accessibilityLabel("Klausurtermine anzeigen")

                        Button { showHomeworkSheet = true } label: {
                            ToolbarIcon(symbol: "checklist", showDot: hasOverdueHomeworks || hasHomeworkDueTomorrow)
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
            .sheet(isPresented: $showHomeworkSheet) {
                HomeworkListView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSchoolYearWizard) {
                OnboardingFunnelView(
                    isSchoolYearChange: true,
                    previousSchoolYearId: store.activeSchoolYearId
                ) {
                    showSchoolYearWizard = false
                }
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
        .keyboardDismissToolbar()
    }

    private var generalCard: some View {
        SettingsCard(
            title: "Profil & Oberfläche",
            subtitle: "Name, Farben und Interaktionen",
            systemImage: "slider.horizontal.3",
            accent: .cyan
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anzeigename")
                            .font(sectionHeaderFont)
                        Text("Wird in Dashboard und Übersichten angezeigt.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                        VStack(spacing: 10) {
                            TextField("Dein Name", text: $newName)
                                .textContentType(.name)
                                .submitLabel(.done)
                                .onSubmit { hideKeyboard() }
                                .padding(12)
                                .background(Color.formInputBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Button {
                                Task { await saveName() }
                            } label: {
                                if isSavingName { ProgressView() } else { Text("Name speichern") }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(isSavingName || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if nameSavedSuccess {
                            Text("✅ Name erfolgreich gespeichert!")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                    }
                }

                SettingsSectionBox {
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
                            Text("Soft / Pink").tag("feminine")
                        }
                        .pickerStyle(.segmented)

                        Text("Wähle, ob die Oberfläche eher klassisch oder mit einem weicheren Farbschema angezeigt wird.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Darstellung & Animationen")
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
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hausaufgaben-Erinnerung")
                            .font(sectionHeaderFont)

                        DatePicker(
                            "1 Tag vor Fälligkeit erinnern",
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
    }

    // MARK: - Sections

    private var schoolYearCard: some View {
        SettingsCard(
            title: "Schuljahr",
            subtitle: "Aktives Schuljahr, Jahrgang und Prüfungsfächer",
            systemImage: "graduationcap.fill",
            accent: .mint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aktives Schuljahr")
                            .font(sectionHeaderFont)
                        if store.schoolYears.isEmpty {
                            Text("Noch keine Schuljahre gefunden. Lege eines an oder warte, bis es automatisch erstellt wird.")
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.schoolYears, id: \.self) { sy in
                                    let isActive = store.activeSchoolYearId == sy
                                    Button {
                                        Task { await store.setActiveSchoolYear(id: sy) }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(sy)
                                                    .font(.headline)
                                                if isActive {
                                                    Text("Aktiv")
                                                        .font(helperFont)
                                                        .foregroundStyle(.green)
                                                }
                                            }
                                            Spacer()
                                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .foregroundStyle(isActive ? .green : .secondary)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color(.secondarySystemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(isActive ? Color.green : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Neues Schuljahr anlegen")
                            .font(sectionHeaderFont)
                        Text("Starte den Schuljahrs-Setup (wie im Onboarding), um Jahr, Schulart, Jahrgang und Gruppen festzulegen.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)

                        Button {
                            showSchoolYearWizard = true
                        } label: {
                            Text("Schuljahrs-Setup starten")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Schulart")
                            .font(sectionHeaderFont)
                        Text("Bestimmt die Berechnung der Abschlussnote (FOS: 11./12. + Praktikum, BOS: 12./13.).")
                            .font(helperFont)
                            .foregroundStyle(.secondary)

                        Picker(
                            "",
                            selection: Binding(
                                get: { store.schoolType },
                                set: { val in
                                    Task {
                                        await store.updateSchoolType(val)
                                        if val == .bos, store.gradeYear == 11 {
                                            await store.updateGradeYear(12)
                                        }
                                    }
                                }
                            )
                        ) {
                            Text("FOS").tag(SchoolType.fos)
                            Text("BOS").tag(SchoolType.bos)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Jahrgangsstufe")
                            .font(sectionHeaderFont)
                        Text("Wähle deine Jahrgangsstufe für das aktive Schuljahr.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 10) {
                            ForEach(gradeOptions, id: \.self) { grade in
                                let selected = store.gradeYear == grade
                                Button {
                                    Task { await store.updateGradeYear(grade) }
                                } label: {
                                    HStack {
                                        Text("\(grade). Jahrgang")
                                            .font(.body)
                                        Spacer()
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                SettingsSectionBox {
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
                            VStack(spacing: 8) {
                                ForEach(store.sortedSubjectsForDisplay(), id: \.name) { subject in
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
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                }
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
    }

    

    private var groupsCard: some View {
        SettingsCard(
            title: "Gruppen & Sync",
            subtitle: "Gemeinsame Gruppen für Klausurentermine und Hausaufgaben",
            systemImage: "person.3.sequence.fill",
            accent: .indigo
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deine Gruppen")
                            .font(sectionHeaderFont)

                        if store.groupIds.isEmpty {
                            Text("Lege eine Gruppe an oder tritt mit einem Code bei. Fächer werden gruppenbezogen geteilt.")
                                .font(helperFont)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(store.groupIds, id: \.self) { gid in
                                    let isCopied = copiedGroupId == gid
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(store.groupNames[gid] ?? "Ohne Namen")
                                                    .font(.headline)
                                                Text("Code: \(gid)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
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
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(Color(.secondarySystemBackground))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Gruppencode kopieren")
                                        }

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
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.indigo.opacity(0.12), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Neue Gruppe erstellen")
                            .font(sectionHeaderFont)
                        TextField("Gruppenname (Pflichtfeld)", text: $groupNameInput)
                            .padding(12)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(groupNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Einer Gruppe beitreten")
                            .font(sectionHeaderFont)
                        TextField("Gruppencode", text: $groupJoinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .padding(12)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
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
        }
    }

    private var infoCard: some View {
        SettingsCard(
            title: "Info",
            subtitle: "Version & Hinweise",
            systemImage: "info.circle",
            accent: .gray
        ) {
            SettingsSectionBox {
                Text("App Version 1.4")
                    .font(helperFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountCard: some View {
        SettingsCard(
            title: "Account",
            subtitle: "Sitzung verwalten",
            systemImage: "person.crop.circle.badge.xmark",
            accent: .gray
        ) {
            SettingsSectionBox {
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
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }

    private var resetCard: some View {
        SettingsCard(
            title: "Daten zurücksetzen",
            subtitle: "Account oder aktuelles Schuljahr bereinigen",
            systemImage: "exclamationmark.triangle.fill",
            accent: .red
        ) {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Account komplett zurücksetzen")
                            .font(sectionHeaderFont)
                        Text("Alle Daten werden gelöscht. Bestätige im nächsten Schritt mit Slider und Passwort.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            resetAccountPassword = ""
                            resetAccountSlideDone = false
                            resetError = nil
                            showResetAccountSheet = true
                        } label: {
                            Text("Account löschen")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }

                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aktives Schuljahr zurücksetzen")
                            .font(sectionHeaderFont)
                        Text("Bereinigt alle Daten des aktuellen Schuljahres. Optimal, wenn du neu starten möchtest.")
                            .font(helperFont)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            resetYearPassword = ""
                            resetYearSlideDone = false
                            resetError = nil
                            showResetYearSheet = true
                        } label: {
                            Text("Schuljahr zurücksetzen")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
            }
        }
    }

    private var onboardingCard: some View {
        SettingsCard(
            title: "Onboarding",
            subtitle: "Setup-Assistent erneut durchlaufen",
            systemImage: "sparkles",
            accent: .teal
        ) {
            SettingsSectionBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Starte den Einrichtungs-Assistenten erneut, um Schuljahr, Gruppen und Fächer neu zu setzen. Bestehende Daten bleiben erhalten.")
                        .font(helperFont)
                        .foregroundStyle(.secondary)
                    Button("Onboarding neu starten") {
                        Task { await store.restartOnboarding() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                }
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.red.opacity(colorScheme == .dark ? 0.28 : 0.18),
                                            Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.12)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 56, height: 56)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.title3.weight(.semibold))
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(colorScheme == .dark ? 0.22 : 0.16),
                                    Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )

                SlideToConfirmView(isConfirmed: $slideDone)
                    .frame(height: 68)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mit Passwort bestätigen")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        SecureField("Passwort eingeben", text: $password)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(12)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                Button {
                    confirmAction()
                } label: {
                    HStack {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Bestätigen")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!(slideDone && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || isProcessing)

                Button {
                    isPresented = false
                } label: {
                    Label("Abbrechen", systemImage: "xmark")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(18)
            .background(Color(.systemGroupedBackground))
        }
    }
}

private struct SlideToConfirmView: View {
    @Binding var isConfirmed: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var hintPhase: Bool = false
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 64
            let knobSize = height - 12
            let maxOffset = max(0, width - knobSize - 8)
            let progress: CGFloat = maxOffset == 0
                ? 1
                : max(0, min(dragOffset / maxOffset, 1))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.red.opacity(isDragging ? 0.55 : 0.35),
                                Color.orange.opacity(isDragging ? 0.50 : 0.30)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(knobSize + 6, (knobSize + 6) + maxOffset * progress))
                    .opacity(0.35)
                    .overlay(
                        RoundedRectangle(cornerRadius: height / 2)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.0),
                                        Color.white.opacity(isDragging ? 0.30 : 0.16),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: isDragging ? 2 : 1
                            )
                            .opacity(isDragging ? 0.7 : 0.25)
                    )

                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Text(isConfirmed ? "Loslassen zum Löschen" : "Zum Bestätigen nach rechts schieben")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary.opacity(isConfirmed ? 0.9 : 0.7))
                        Text("Sicherheits-Swipe verhindert versehentliches Löschen.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, knobSize * 0.35)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: isConfirmed
                                ? [Color.green, Color.green.opacity(0.8)]
                                : [Color.red, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: (isConfirmed ? Color.green : Color.orange).opacity(0.25), radius: 8, x: 0, y: 4)
                    .overlay(
                        ZStack {
                            if isDragging {
                                TimelineView(.animation) { timeline in
                                    let t = timeline.date.timeIntervalSinceReferenceDate
                                    let pulse = 1 + 0.08 * sin(t * 6)
                                    Circle()
                                        .stroke(Color.white.opacity(0.35), lineWidth: 3)
                                        .scaleEffect(pulse)
                                        .opacity(0.6 - 0.3 * abs(sin(t * 3)))
                                }
                            }

                            HStack(spacing: 2) {
                                Image(systemName: isConfirmed ? "checkmark" : "chevron.forward")
                                    .font(.headline.weight(.bold))
                                if !isConfirmed {
                                    Image(systemName: "chevron.forward")
                                        .font(.headline.weight(.bold))
                                        .opacity(hintPhase ? 1 : 0.4)
                                        .offset(x: hintPhase ? 2 : -2)
                                }
                            }
                            .foregroundStyle(.white)
                        }
                    )
                    .scaleEffect(isDragging ? 1.05 : 1)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isDragging)
                    .offset(x: max(4, min(dragOffset + 4, maxOffset + 4)))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard !isConfirmed else { return }
                                if !isDragging {
                                    isDragging = true
                                }
                                dragOffset = max(0, min(value.translation.width, maxOffset))
                            }
                            .onEnded { _ in
                                guard !isConfirmed else { return }
                                if dragOffset > maxOffset * 0.82 {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                                        isConfirmed = true
                                        dragOffset = maxOffset
                                    }
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isConfirmed = false
                                        dragOffset = 0
                                    }
                                }
                                isDragging = false
                            }
                    )
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: hintPhase)
            }
            .frame(height: height)
            .onAppear {
                hintPhase = true
            }
            .onChange(of: isConfirmed) { newValue in
                if !newValue {
                    dragOffset = 0
                    isDragging = false
                } else {
                    dragOffset = maxOffset
                }
            }
        }
    }
}
