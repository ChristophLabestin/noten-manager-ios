import SwiftUI

struct OnboardingFunnelView: View {
    enum Step: Int {
        case schoolYear, groups, subjects
    }

    private struct PendingSubject: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let type: Int
        let isElective: Bool
    }

    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss

    let onFinished: () -> Void
    let isSchoolYearChange: Bool
    let previousSchoolYearId: String?

    init(isSchoolYearChange: Bool = false, previousSchoolYearId: String? = nil, onFinished: @escaping () -> Void) {
        self.isSchoolYearChange = isSchoolYearChange
        self.previousSchoolYearId = previousSchoolYearId
        self.onFinished = onFinished
    }

    @State private var currentStep: Step = .schoolYear
    @State private var schoolYearInput: String = ""
    @State private var gradeSelection: Int = 0
    @State private var selectedSchoolType: SchoolType = .bos
    @State private var schoolYearError: String?
    @State private var isSavingSchoolYear: Bool = false

    @State private var joinCode: String = ""
    @State private var joinInfo: String?
    @State private var joinError: String?
    @State private var isJoining: Bool = false
    @State private var leavingGroupIds: Set<String> = []
    @State private var didPrefetchGroupNames: Bool = false

    @State private var importInfo: String?
    @State private var importError: String?
    @State private var isImporting: Bool = false
    @State private var prevImportInfo: String?
    @State private var prevImportError: String?
    @State private var isImportingPrev: Bool = false
    @State private var prevYearSubjects: [Subject] = []
    @State private var selectedPrevSubjects: Set<String> = []
    @State private var isLoadingPrevSubjects: Bool = false
    @State private var pendingSchoolYearId: String?
    @State private var pendingSchoolType: SchoolType = .bos
    @State private var pendingGradeYear: Int = 0
    @State private var pendingPrevSubjectNames: Set<String> = []
    @State private var pendingManualSubjects: [PendingSubject] = []
    @State private var manualNameInput: String = ""
    @State private var manualType: Int = 1
    @State private var manualIsElective: Bool = false
    @State private var manualError: String?

    @State private var finishError: String?
    @State private var isFinishing: Bool = false
    @State private var showAddSubjectSheet: Bool = false

    private var hasSubjects: Bool {
        if isSchoolYearChange {
            return !pendingPrevSubjectNames.isEmpty || !pendingManualSubjects.isEmpty
        }
        return !store.subjects.isEmpty
    }

    private var hasJoinedGroups: Bool {
        !store.groupIds.isEmpty
    }

    private var uniqueGroupSubjectCount: Int {
        var names: Set<String> = []
        for gid in store.groupIds {
            for subj in store.groupSubjectsByGroup[gid] ?? [] {
                names.insert(subj.name)
            }
        }
        return names.count
    }

    private var stagedSubjects: [String] {
        Array(pendingPrevSubjectNames).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    stepIndicator
                    contentForCurrentStep
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .navigationBarHidden(true)
            .onAppear { bootstrapDefaults() }
            .sheet(isPresented: $showAddSubjectSheet) {
                AddSubjectView()
                    .environmentObject(store)
            }
        }
        .keyboardDismissToolbar()
        .interactiveDismissDisabled(!isSchoolYearChange)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 10) {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                    .disabled(currentStep == .schoolYear)
                    Button {
                        dismiss()
                        onFinished()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Circle())
                    }
                }
                Spacer()
                Text("Schritt \(currentStep.rawValue + 1)/3")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(isSchoolYearChange ? "Schuljahrs-Setup" : "Account einrichten")
                    .font(.title2.weight(.semibold))
                Text(stepSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(0..<3) { idx in
                let isActive = idx == currentStep.rawValue
                Circle()
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.35))
                    .frame(width: 10, height: 10)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var contentForCurrentStep: some View {
        switch currentStep {
        case .schoolYear:
            schoolYearStep
        case .groups:
            groupsStep
        case .subjects:
            subjectsStep
        }
    }

    private var schoolYearStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schuljahr, Schulart & Jahrgang")
                .font(.headline)
            Text(isSchoolYearChange
                 ? "Richte dein neues Schuljahr ein. Standard ist das kommende Schuljahr."
                 : "Lege zuerst dein aktives Schuljahr fest und wähle deine Jahrgangsstufe.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("z. B. 2025-26", text: $schoolYearInput)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Schulart")
                        .font(.subheadline.weight(.semibold))
                    Picker("", selection: $selectedSchoolType) {
                        Text("FOS").tag(SchoolType.fos)
                        Text("BOS").tag(SchoolType.bos)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Jahrgangsstufe")
                        .font(.subheadline.weight(.semibold))
                    Text("Wähle die passende Jahrgangsstufe für die Schulart.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        ForEach(gradeOptionsForSchoolType, id: \.self) { grade in
                            let selected = gradeSelection == grade
                            Button {
                                gradeSelection = grade
                                pendingGradeYear = grade
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

            if let err = schoolYearError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                handleSchoolYearContinue()
            } label: {
                HStack {
                    if isSavingSchoolYear {
                        ProgressView()
                    } else {
                        Text("Weiter zu Gruppen")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            .disabled(!isValidSchoolYear(schoolYearInput) || !gradeOptionsForSchoolType.contains(gradeSelection) || isSavingSchoolYear)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.tertiarySystemBackground)))
    }

    private var groupsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gruppen beitreten")
                .font(.headline)
            Text("Tritt bestehenden Gruppen mit einem Code bei oder überspringe diesen Schritt.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Gruppencode", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .onSubmit { hideKeyboard() }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                handleJoinGroup()
            } label: {
                HStack {
                    if isJoining {
                        ProgressView()
                    } else {
                        Text("Beitreten")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isJoining)
            .frame(maxWidth: .infinity)

            if let msg = joinInfo {
                Text(msg)
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            if let err = joinError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if hasJoinedGroups {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Beigetretene Gruppen")
                        .font(.subheadline.weight(.semibold))
                    ForEach(store.groupIds, id: \.self) { gid in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(store.groupNames[gid] ?? "Lädt …")
                                        .font(.body.weight(.semibold))
                                    Text(gid)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    leaveGroup(gid)
                                } label: {
                                    if leavingGroupIds.contains(gid) {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(leavingGroupIds.contains(gid))
                                .accessibilityLabel("Gruppe verlassen")
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onAppear {
                            if store.groupNames[gid] == nil {
                                Task { await store.loadGroupName(gid: gid) }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Überspringen") {
                    continueFromGroups()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isJoining)

                Button("Weiter") {
                    continueFromGroups()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isJoining)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.tertiarySystemBackground)))
        .onAppear {
            if !didPrefetchGroupNames {
                didPrefetchGroupNames = true
                Task { await preloadGroupNames() }
            }
        }
    }

    private var subjectsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fächer hinzufügen")
                .font(.headline)
            Text("Am Ende des Setups muss mindestens ein Fach vorhanden sein.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if hasJoinedGroups && !isSchoolYearChange {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fächer aus Gruppen übernehmen")
                                .font(.subheadline.weight(.semibold))
                            Text(uniqueGroupSubjectCount > 0
                                 ? "\(uniqueGroupSubjectCount) hinterlegte Fächer gefunden."
                                 : "Noch keine Fächer in den Gruppen gefunden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Button {
                        importGroupSubjects()
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                            } else {
                                Text("Gruppenfächer kopieren")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isImporting)

                    if let info = importInfo {
                        Text(info)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if let err = importError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let prevYear = previousSchoolYearId {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fächer aus Vorjahr übernehmen")
                        .font(.subheadline.weight(.semibold))
                    Text("Wähle Fächer aus \(prevYear) ohne Noten für das neue Schuljahr.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if isLoadingPrevSubjects {
                        ProgressView().padding(.vertical, 4)
                    } else if prevYearSubjects.isEmpty {
                        Text("Keine Fächer im Vorjahr gefunden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(prevYearSubjects, id: \.name) { subj in
                                Toggle(isOn: Binding(
                                    get: { selectedPrevSubjects.contains(subj.name) },
                                    set: { val in
                                        if val { selectedPrevSubjects.insert(subj.name) }
                                        else { selectedPrevSubjects.remove(subj.name) }
                                    }
                                )) {
                                    Text(subj.name)
                                }
                            }
                        }

                        Button {
                            importFromPreviousYear()
                        } label: {
                            HStack {
                                if isImportingPrev {
                                    ProgressView()
                                } else {
                                    Text("Auswahl kopieren")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isImportingPrev || selectedPrevSubjects.isEmpty)
                    }

                    if let info = prevImportInfo {
                        Text(info)
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                    if let err = prevImportError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Fächer manuell anlegen")
                    .font(.subheadline.weight(.semibold))
                if isSchoolYearChange {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Fachname", text: $manualNameInput)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Picker("Typ", selection: $manualType) {
                            Text("Hauptfach").tag(1)
                            Text("Nebenfach").tag(0)
                        }
                        .pickerStyle(.segmented)
                        .disabled(manualIsElective)

                        Toggle("Wahlfach / nicht einbringbar", isOn: $manualIsElective)
                            .onChange(of: manualIsElective) { val in
                                if val { manualType = 0 }
                            }

                        Text("Wahlfächer fließen nicht in die Abschlussnote ein. Für Sport/Musik bitte als Wahlfach markieren.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Fach vormerken") {
                            addPendingManualSubject()
                        }
                        .buttonStyle(.bordered)
                        .disabled(manualNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let manualError {
                            Text(manualError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Button("Fach hinzufügen") {
                        showAddSubjectSheet = true
                    }
                    .buttonStyle(.bordered)

                    if store.subjects.isEmpty {
                        Text("Noch keine Fächer angelegt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.subjects, id: \.name) { subj in
                                Text(subj.name)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }

            if isSchoolYearChange {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vorgemerkte Fächer")
                        .font(.subheadline.weight(.semibold))
                    let stagedPrev = Array(pendingPrevSubjectNames).sorted()
                    let stagedManual = pendingManualSubjects.map { $0.name }
                    if stagedPrev.isEmpty && stagedManual.isEmpty {
                        Text("Noch keine Fächer ausgewählt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(stagedPrev, id: \.self) { name in
                                Text(name)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            ForEach(stagedManual, id: \.self) { name in
                                Text("\(name) (manuell)")
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }

            if let err = finishError {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                finishSetup()
            } label: {
                HStack {
                    if isFinishing {
                        ProgressView()
                    } else {
                        Text("Setup abschließen")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isFinishing || !hasSubjects)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.tertiarySystemBackground)))
    }

    private var stepSubtitle: String {
        switch currentStep {
        case .schoolYear:
            return isSchoolYearChange ? "Neues Schuljahr anlegen, Schulart und Jahrgang wählen." : "Schuljahr wählen und Jahrgang setzen."
        case .groups:
            return isSchoolYearChange ? "Optional Gruppen für das neue Schuljahr verbinden." : "Optional Gruppen mit Code beitreten."
        case .subjects:
            return isSchoolYearChange ? "Fächer aus Gruppen oder Vorjahr übernehmen – oder neu anlegen." : "Fächer übernehmen oder selbst anlegen."
        }
    }

    private func isValidSchoolYear(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^(\\d{4})-(\\d{2})$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range), match.numberOfRanges == 3 else {
            return false
        }
        guard
            let startRange = Range(match.range(at: 1), in: trimmed),
            let endRange = Range(match.range(at: 2), in: trimmed)
        else { return false }
        guard let start = Int(trimmed[startRange]), let suffix = Int(trimmed[endRange]) else { return false }
        return ((start + 1) % 100) == suffix
    }

    private var gradeOptionsForSchoolType: [Int] {
        selectedSchoolType == .fos ? [11, 12, 13] : [12, 13]
    }

    private func bootstrapDefaults() {
        let baseYear = store.activeSchoolYearId ?? SchoolYearService.currentSchoolYearId()
        selectedSchoolType = store.schoolType
        if isSchoolYearChange {
            schoolYearInput = SchoolYearService.nextSchoolYearId(from: baseYear)
        } else {
            schoolYearInput = baseYear
        }
        let current = store.gradeYear ?? 0
        let bumped = current == 11 ? 12 : (current == 12 ? 13 : current)
        let allowed = gradeOptionsForSchoolType
        if allowed.contains(bumped) {
            gradeSelection = bumped
        } else {
            gradeSelection = allowed.first ?? 0
        }
        pendingSchoolYearId = schoolYearInput
        pendingSchoolType = selectedSchoolType
        pendingGradeYear = gradeSelection
    }

    private func handleSchoolYearContinue() {
        guard !isSavingSchoolYear else { return }
        let targetId = schoolYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSchoolYear(targetId), gradeOptionsForSchoolType.contains(gradeSelection) else {
            schoolYearError = "Bitte Schuljahr und Jahrgang korrekt auswählen."
            return
        }

        schoolYearError = nil
        isSavingSchoolYear = true
        Task {
            await MainActor.run {
                pendingSchoolYearId = targetId
                pendingSchoolType = selectedSchoolType
                pendingGradeYear = gradeSelection
                isSavingSchoolYear = false
                currentStep = .groups
            }
        }
    }

    private func handleJoinGroup() {
        guard !isJoining else { return }
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        joinInfo = nil
        joinError = nil
        isJoining = true

        Task {
            do {
                try await store.joinExistingSharedGroup(with: code)
                await MainActor.run {
                    joinInfo = "Gruppe verbunden."
                    joinCode = ""
                }
            } catch {
                await MainActor.run {
                    joinError = error.localizedDescription
                }
            }
            await MainActor.run {
                isJoining = false
            }
        }
    }

    private func continueFromGroups() {
        currentStep = .subjects
        importInfo = nil
        importError = nil
        prevImportInfo = nil
        prevImportError = nil
        finishError = nil
        if previousSchoolYearId != nil && prevYearSubjects.isEmpty {
            Task { await loadPrevSubjects() }
        }
    }

    private func goBack() {
        guard currentStep.rawValue > 0 else { return }
        if let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    private func leaveGroup(_ gid: String) {
        guard !leavingGroupIds.contains(gid) else { return }
        leavingGroupIds.insert(gid)
        Task {
            await store.leaveSharedGroup(code: gid)
            await MainActor.run {
                leavingGroupIds.remove(gid)
            }
        }
    }

    private func preloadGroupNames() async {
        for gid in store.groupIds where store.groupNames[gid] == nil {
            await store.loadGroupName(gid: gid)
        }
    }

    private func loadPrevSubjects() async {
        guard let prev = previousSchoolYearId else { return }
        await MainActor.run {
            isLoadingPrevSubjects = true
            prevYearSubjects = []
            selectedPrevSubjects = []
            prevImportInfo = nil
            prevImportError = nil
        }
        let subjects = await store.loadSubjectsFromSchoolYear(prev)
        await MainActor.run {
            prevYearSubjects = subjects
            isLoadingPrevSubjects = false
        }
    }

    private func importGroupSubjects() {
        guard !isImporting else { return }
        importInfo = nil
        importError = nil
        isImporting = true

        Task {
            let count = await store.importSubjectsFromGroups(groupIds: nil)
            await MainActor.run {
                isImporting = false
                if count > 0 {
                    importInfo = "\(count) Fächer übernommen."
                } else {
                    importInfo = "Keine neuen Fächer gefunden."
                }
            }
        }
    }

    private func importFromPreviousYear() {
        guard !isImportingPrev else { return }
        prevImportInfo = nil
        prevImportError = nil
        isImportingPrev = true

        Task {
            defer { isImportingPrev = false }
            guard let prev = previousSchoolYearId else { return }
            await MainActor.run {
                pendingPrevSubjectNames = selectedPrevSubjects
                prevImportInfo = pendingPrevSubjectNames.isEmpty ? nil : "\(pendingPrevSubjectNames.count) Fächer aus \(prev) werden beim Abschluss übernommen."
                selectedPrevSubjects = []
            }
        }
    }

    private func addPendingManualSubject() {
        let name = manualNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if pendingManualSubjects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            manualNameInput = ""
            return
        }
        let lower = name.lowercased()
        if ["sport", "musik"].contains(lower) && !manualIsElective {
            manualError = "Bitte markiere Sport oder Musik als Wahlfach."
            return
        } else {
            manualError = nil
        }
        let subj = PendingSubject(name: name, type: manualType, isElective: manualIsElective)
        pendingManualSubjects.append(subj)
        manualNameInput = ""
        manualType = 1
        manualIsElective = false
    }

    private func finishSetup() {
        finishError = nil
        guard hasSubjects else {
            finishError = "Lege mindestens ein Fach an oder kopiere es aus einer Gruppe."
            return
        }
        guard !isFinishing else { return }

        isFinishing = true
        Task {
            let targetId = pendingSchoolYearId ?? schoolYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = await store.createSchoolYear(name: targetId)
            if created == nil {
                await store.setActiveSchoolYear(id: targetId)
            } else {
                await store.setActiveSchoolYear(id: targetId)
            }
            await store.updateSchoolType(pendingSchoolType)
            await store.updateGradeYear(pendingGradeYear)

            if let prev = previousSchoolYearId, !pendingPrevSubjectNames.isEmpty {
                _ = await store.importSubjectsFromSchoolYear(prev, subjectNames: Array(pendingPrevSubjectNames))
                pendingPrevSubjectNames = []
            }

            if !pendingManualSubjects.isEmpty {
                for subj in pendingManualSubjects {
                    try? await store.addSubjectToFirestore(name: subj.name, type: subj.type, date: Date(), isElective: subj.isElective)
                }
                pendingManualSubjects = []
            }

            await store.markOnboardingCompletedIfPossible()
            await MainActor.run {
                isFinishing = false
                onFinished()
            }
        }
    }
}
