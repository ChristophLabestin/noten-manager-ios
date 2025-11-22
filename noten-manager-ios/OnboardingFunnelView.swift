import SwiftUI

struct OnboardingFunnelView: View {
    enum Step: Int {
        case schoolYear, groups, subjects
    }

    @EnvironmentObject var store: GradesStore

    let onFinished: () -> Void

    @State private var currentStep: Step = .schoolYear
    @State private var schoolYearInput: String = ""
    @State private var gradeSelection: Int = 0
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

    @State private var finishError: String?
    @State private var isFinishing: Bool = false
    @State private var showAddSubjectSheet: Bool = false

    private var hasSubjects: Bool {
        !store.subjects.isEmpty
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
            .navigationBarHidden(true)
            .onAppear { bootstrapDefaults() }
            .sheet(isPresented: $showAddSubjectSheet) {
                AddSubjectView()
                    .environmentObject(store)
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if currentStep != .schoolYear {
                    Button {
                        goBack()
                    } label: {
                        Image(systemName: "chevron.left")
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
                Text("Account einrichten")
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
            Text("Schuljahr & Jahrgang")
                .font(.headline)
            Text("Lege zuerst dein aktives Schuljahr fest und wähle deine Jahrgangsstufe.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("z. B. 2025-26", text: $schoolYearInput)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled(true)
                    .padding(14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Picker("Jahrgang", selection: $gradeSelection) {
                    Text("Bitte auswählen").tag(0)
                    Text("12. Jahrgang").tag(12)
                    Text("13. Jahrgang").tag(13)
                }
                .pickerStyle(.segmented)
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
            .disabled(!isValidSchoolYear(schoolYearInput) || !(gradeSelection == 12 || gradeSelection == 13) || isSavingSchoolYear)
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

            if hasJoinedGroups {
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

            VStack(alignment: .leading, spacing: 10) {
                Text("Fächer manuell anlegen")
                    .font(.subheadline.weight(.semibold))
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
            return "Schuljahr wählen und Jahrgang setzen."
        case .groups:
            return "Optional Gruppen mit Code beitreten."
        case .subjects:
            return "Fächer übernehmen oder selbst anlegen."
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

    private func bootstrapDefaults() {
        schoolYearInput = store.activeSchoolYearId ?? SchoolYearService.currentSchoolYearId()
        gradeSelection = store.gradeYear ?? 0
    }

    private func handleSchoolYearContinue() {
        guard !isSavingSchoolYear else { return }
        let targetId = schoolYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSchoolYear(targetId), gradeSelection == 12 || gradeSelection == 13 else {
            schoolYearError = "Bitte Schuljahr und Jahrgang korrekt auswählen."
            return
        }

        schoolYearError = nil
        isSavingSchoolYear = true
        Task {
            let created = await store.createSchoolYear(name: targetId)
            if created == nil {
                await store.setActiveSchoolYear(id: targetId)
            }
            await store.updateGradeYear(gradeSelection)

            await MainActor.run {
                isSavingSchoolYear = false
                if store.activeSchoolYearId != nil {
                    currentStep = .groups
                } else {
                    schoolYearError = "Schuljahr konnte nicht gesetzt werden."
                }
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
        finishError = nil
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

    private func finishSetup() {
        finishError = nil
        guard hasSubjects else {
            finishError = "Lege mindestens ein Fach an oder kopiere es aus einer Gruppe."
            return
        }
        guard !isFinishing else { return }

        isFinishing = true
        Task {
            await store.markOnboardingCompletedIfPossible()
            await MainActor.run {
                isFinishing = false
                onFinished()
            }
        }
    }
}
