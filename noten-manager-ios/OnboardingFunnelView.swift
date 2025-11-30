import SwiftUI

struct OnboardingFunnelView: View {
    enum Step: Int {
        case legacy, schoolYear, groups, subjects
    }

    private struct PendingSubject: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let type: Int
        let isElective: Bool
    }

    private struct GroupSubjectSource: Hashable {
        let groupId: String
        let subjectId: String
        let type: Int?
        let alias: String?
    }

    private struct PendingGroupSubject: Identifiable, Hashable {
        let id = UUID()
        let name: String
        var sources: [GroupSubjectSource]
        var selected: Bool = true
    }

    @EnvironmentObject var store: GradesStore
    @EnvironmentObject private var authManager: AuthManager
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
    @State private var baselineGroupIds: Set<String> = []
    @State private var pendingGroupCodes: Set<String> = []
    @State private var pendingSchoolYearId: String?
    @State private var pendingSchoolType: SchoolType = .bos
    @State private var pendingGradeYear: Int = 0
    @State private var pendingPrevSubjectNames: Set<String> = []
    @State private var pendingManualSubjects: [PendingSubject] = []
    @State private var manualNameInput: String = ""
    @State private var manualType: Int = 1
    @State private var manualIsElective: Bool = false
    @State private var manualError: String?
    @State private var groupSubjectCandidates: [PendingGroupSubject] = []

    @State private var finishError: String?
    @State private var isFinishing: Bool = false
    @State private var showAddSubjectSheet: Bool = false
    @State private var removingSubjectNames: Set<String> = []
    @State private var isHandlingLegacyChoice: Bool = false

    private var accentPrimary: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : .indigo
    }
    private var primaryText: Color {
        store.darkMode ? .white : .primary
    }
    private var secondaryText: Color {
        store.darkMode ? .white.opacity(0.75) : .secondary
    }
    private var tileBackground: Color {
        store.darkMode ? Color.white.opacity(0.08) : Color.white
    }
    private var tileStroke: Color {
        accentPrimary.opacity(store.darkMode ? 0.25 : 0.15)
    }

    private var isManualRestart: Bool {
        !isSchoolYearChange && store.onboardingRequired && (store.activeSchoolYearId != nil || !store.subjects.isEmpty)
    }

    private var showSignOutButton: Bool {
        !isSchoolYearChange && !isManualRestart && store.onboardingRequired
    }

    private var showCloseButton: Bool {
        isSchoolYearChange || isManualRestart
    }

    private var canGoBack: Bool {
        !((!legacyStepRequired && currentStep == .schoolYear) || currentStep == .legacy)
    }

    private var hasSubjects: Bool {
        if isSchoolYearChange {
            return !pendingPrevSubjectNames.isEmpty || !pendingManualSubjects.isEmpty
        }
        if store.legacyImportSelected == true && !store.legacySelectedSubjects.isEmpty {
            return true
        }
        return !store.subjects.isEmpty || stagedGroupSubjectCount > 0 || !pendingManualSubjects.isEmpty
    }

    private var hasJoinedGroups: Bool {
        !visibleGroupIds.isEmpty
    }

    private var visibleGroupIds: [String] {
        if isSchoolYearChange {
            let newGroups = Set(store.groupIds).subtracting(baselineGroupIds)
            return Array(newGroups.union(pendingGroupCodes)).sorted()
        }
        return store.groupIds
    }

    private var uniqueGroupSubjectCount: Int {
        var names: Set<String> = []
        let existing = Set(store.subjects.map { $0.name.lowercased() }).union(legacySubjectLowercased)
        for gid in store.groupIds {
            for subj in store.groupSubjectsByGroup[gid] ?? [] {
                let trimmed = subj.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let lower = trimmed.lowercased()
                guard !existing.contains(lower) else { continue }
                names.insert(lower)
            }
        }
        return names.count
    }

    private var stagedSubjects: [String] {
        Array(pendingPrevSubjectNames).sorted()
    }

    private var stagedGroupSubjectCount: Int {
        selectedGroupSubjectNames.count
    }

    private var selectedGroupSubjectNames: [String] {
        groupSubjectCandidates.filter { $0.selected }.map { $0.name }
    }

    private var legacyAvailableSubjectNames: [String] {
        let summaryNames = store.legacyMigrationSummary?.subjectNames ?? []
        let trimmedSummary = summaryNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let names = Set(trimmedSummary).union(store.legacySelectedSubjects)
        return names.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var stagingMode: Bool {
        store.onboardingRequired && store.activeSchoolYearId == nil && !isSchoolYearChange
    }

    private var legacyStepRequired: Bool {
        store.legacyMigrationSummary != nil
    }

    private var totalSteps: Int {
        legacyStepRequired ? 4 : 3
    }

    private var legacySubjectLowercased: Set<String> {
        guard store.legacyImportSelected == true else { return [] }
        return Set(
            store.legacySelectedSubjects.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
    }

    private var currentStepNumber: Int {
        switch currentStep {
        case .legacy: return 1
        case .schoolYear: return legacyStepRequired ? 2 : 1
        case .groups: return legacyStepRequired ? 3 : 2
        case .subjects: return legacyStepRequired ? 4 : 3
        }
    }

    @ViewBuilder
    private var contentForCurrentStepCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            contentForCurrentStep
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tileBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tileStroke, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var contentForCurrentStepContainer: some View {
        if currentStep == .subjects {
            contentForCurrentStep
        } else {
            contentForCurrentStepCard
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        stepIndicator
                        if store.legacyCheckPending {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Daten werden abgerufen …")
                                    .font(.subheadline)
                                    .foregroundStyle(secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                        } else if legacyStepRequired && currentStep == .legacy, let summary = store.legacyMigrationSummary {
                            legacyDetectedSection(summary: summary)
                        } else {
                            contentForCurrentStepContainer
                        }

                        if showSignOutButton {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    authManager.signOut()
                                    dismiss()
                                } label: {
                                    Text("Abmelden")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .red))

                                Text("Du kannst den Assistenten jederzeit erneut starten.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if canGoBack {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .imageScale(.medium)
                        }
                        .accessibilityLabel("Zurück")
                        .disabled(!canGoBack)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if showCloseButton {
                        Button(action: closeOnboarding) {
                            Image(systemName: "xmark")
                                .imageScale(.medium)
                        }
                        .accessibilityLabel("Schließen")
                    }
                }
            }
            .onAppear {
                bootstrapDefaults()
                baselineGroupIds = Set(store.groupIds)
                currentStep = legacyStepRequired ? .legacy : .schoolYear
            }
            .sheet(isPresented: $showAddSubjectSheet) {
                AddSubjectView()
                    .environmentObject(store)
            }
        }
        .onChange(of: store.legacyMigrationSummary) { _, summary in
            if summary != nil {
                currentStep = .legacy
            }
        }
        .keyboardDismissToolbar()
        .interactiveDismissDisabled(!(isSchoolYearChange || isManualRestart))
        .presentationDetents([.large])
        .presentationDragIndicator(showCloseButton ? .visible : .hidden)
        .onChange(of: store.groupSubjectsByGroup) {
            if currentStep == .subjects && !isSchoolYearChange {
                prepareGroupSubjectCandidates()
            }
        }
        .onChange(of: store.subjects) {
            if currentStep == .subjects && !isSchoolYearChange {
                prepareGroupSubjectCandidates()
            }
        }
        .onChange(of: store.groupIds) {
            if currentStep != .schoolYear && !isSchoolYearChange {
                prepareGroupSubjectCandidates()
            }
        }
    }

    @ViewBuilder
    private func legacyDetectedSection(summary: LegacyMigrationSummary) -> some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accentPrimary.opacity(store.darkMode ? 0.22 : 0.16))
                            .frame(width: 48, height: 48)
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(accentPrimary)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Daten aus der Web-App erkannt")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(primaryText)
                        Text("Wir haben Inhalte aus der Web-Version gefunden. Wie möchtest du fortfahren?")
                            .font(.subheadline)
                            .foregroundStyle(secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .foregroundStyle(accentPrimary)
                    Text("Gefundene Web-Daten")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryText)
                }
                statRow(icon: "text.book.closed", title: formattedCount(summary.subjectCount, singular: "Fach", plural: "Fächer"), subtitle: "aus der Web-App")
                statRow(icon: "number.square", title: formattedCount(summary.gradeCount, singular: "Note", plural: "Noten"), subtitle: "bestehende Bewertungen")
                if let gradeYear = summary.gradeYear {
                    statRow(icon: "graduationcap", title: "Klassenstufe \(gradeYear)", subtitle: "aus Web-Einstellungen")
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tileBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(tileStroke, lineWidth: 1)
                    )
            )

            VStack(spacing: 12) {
                optionButton(
                    icon: "arrow.down.doc.fill",
                    title: "Daten übernehmen",
                    subtitle: "Importiert deine Web-Fächer und Noten in dieses Schuljahr.",
                    accent: accentPrimary
                ) { handleLegacyChoice(keep: true) }
                optionButton(
                    icon: "sparkles",
                    title: "Neu anfangen ohne Web-Daten",
                    subtitle: "Beginnt frisch in der App. Deine Web-Daten bleiben dort erhalten.",
                    accent: Color.orange
                ) { handleLegacyChoice(keep: false) }
            }
            .padding(.top, 4)
        }
    }

    private func optionButton(icon: String, title: String, subtitle: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tileBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accent.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accentPrimary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
            Spacer()
        }
    }

    private func formattedCount(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func sectionCard(title: String, subtitle: String? = nil, icon: String, accent: Color, badge: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.formCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.15), lineWidth: 1)
                )
        )
        .overlay(alignment: .topTrailing) {
            if let badge {
                Tag(text: badge, style: .minor)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
            }
        }
    }

    private func selectionRow(title: String, detail: String? = nil, isSelected: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? accent : Color.secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(primaryText)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func stagedSubjectRow(title: String, icon: String, tint: Color, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(tint)
                    .imageScale(.large)
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .foregroundStyle(primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func handleLegacyChoice(keep: Bool) {
        guard !isHandlingLegacyChoice else { return }
        isHandlingLegacyChoice = true
        Task {
            await store.handleLegacyMigrationChoice(keepWebData: keep)
            await MainActor.run {
                isHandlingLegacyChoice = false
                currentStep = .schoolYear
                if !keep {
                    store.legacySelectedSubjects = []
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isSchoolYearChange ? "Schuljahrs-Setup" : "Account einrichten")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(primaryText)
                    Text(stepSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(secondaryText)
                }
                Spacer()
                Text("Schritt \(currentStepNumber)/\(totalSteps)")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accentPrimary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(0..<totalSteps, id: \.self) { idx in
                let isActive = idx == currentStepNumber - 1
                Circle()
                    .fill(isActive ? accentPrimary : accentPrimary.opacity(0.25))
                    .frame(width: 10, height: 10)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var contentForCurrentStep: some View {
        switch currentStep {
        case .legacy:
            EmptyView()
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
                .foregroundStyle(primaryText)
            Text(isSchoolYearChange
                 ? "Richte dein neues Schuljahr ein. Standard ist das kommende Schuljahr."
                 : "Lege zuerst dein aktives Schuljahr fest und wähle deine Jahrgangsstufe.")
                .font(.footnote)
                .foregroundStyle(secondaryText)

            VStack(spacing: 12) {
                TextField("z. B. 2025-26", text: $schoolYearInput)
                    .textInputAutocapitalization(.none)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)
                    .onSubmit { hideKeyboard() }
                    .padding(14)
                    .background(Color.formInputBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                if !schoolYearInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !isValidSchoolYear(schoolYearInput) {
                    Text("Bitte ein Schuljahr im Format 2024-25 eingeben.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if schoolYearAlreadyExists {
                    Text("Dieses Schuljahr existiert bereits. Bitte wähle ein anderes.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

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
            .buttonStyle(SoftTintButtonStyle(accent: accentPrimary))
            .padding(.top, 4)
            .disabled(
                !isValidSchoolYear(schoolYearInput)
                || schoolYearAlreadyExists
                || !gradeOptionsForSchoolType.contains(gradeSelection)
                || isSavingSchoolYear
            )
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.formCardBackground))
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
                .background(Color.formInputBackground)
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
            .buttonStyle(SoftTintButtonStyle(accent: accentPrimary))
            .disabled(normalizeGroupCode(joinCode).isEmpty || isJoining)
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
                    ForEach(visibleGroupIds, id: \.self) { gid in
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
                .buttonStyle(SoftTintButtonStyle(accent: Color(.secondaryLabel)))
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isJoining)

                Button("Weiter") {
                    continueFromGroups()
                }
                .buttonStyle(SoftTintButtonStyle(accent: accentPrimary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isJoining)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.formCardBackground))
        .onAppear {
            if !didPrefetchGroupNames {
                didPrefetchGroupNames = true
                Task { await preloadGroupNames() }
            }
        }
    }

    private var subjectsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Fächer auswählen")
                .font(.title2.weight(.bold))
            Text("Übernimm Fächer aus Web oder Gruppen, aus dem Vorjahr oder lege eigene an. Mindestens ein Fach ist nötig.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if store.legacyImportSelected != false,
               !legacyAvailableSubjectNames.isEmpty {
                sectionCard(
                    title: "Web-Fächer",
                    subtitle: "Gefunden in deiner Web-App",
                    icon: "shippingbox.fill",
                    accent: accentPrimary,
                    badge: store.legacySelectedSubjects.isEmpty ? nil : "\(store.legacySelectedSubjects.count) gewählt"
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(legacyAvailableSubjectNames, id: \.self) { name in
                            let isOn = store.legacySelectedSubjects.contains(name)
                            selectionRow(title: name, isSelected: isOn, accent: accentPrimary) {
                                toggleLegacySubject(name: name, isOn: !isOn)
                            }
                        }
                    }
                }
            }

            if hasJoinedGroups && !isSchoolYearChange {
                sectionCard(
                    title: "Gruppenfächer",
                    subtitle: "Übernimm Fächer aus deinen beigetretenen Gruppen.",
                    icon: "person.3.fill",
                    accent: .blue,
                    badge: stagedGroupSubjectCount > 0 ? "\(stagedGroupSubjectCount) markiert" : nil
                ) {
                    if groupSubjectCandidates.isEmpty {
                        Text(uniqueGroupSubjectCount > 0 ? "Lade Fächer aus den Gruppen ..." : "Keine Gruppenfächer gefunden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(groupSubjectCandidates) { candidate in
                                selectionRow(
                                    title: candidate.name,
                                    detail: candidate.sources.count > 1 ? "\(candidate.sources.count) Gruppen" : nil,
                                    isSelected: candidate.selected,
                                    accent: .blue
                                ) {
                                    toggleGroupSubjectSelection(id: candidate.id, isOn: !candidate.selected)
                                }
                            }
                        }
                        if !stagingMode {
                            Button {
                                importGroupSubjects()
                            } label: {
                                HStack {
                                    if isImporting {
                                        ProgressView()
                                    } else {
                                        Text("Auswahl übernehmen")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .blue))
                            .disabled(isImporting || stagedGroupSubjectCount == 0)
                        } else {
                            Text("Auswahl wird beim Abschluss übernommen.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                sectionCard(
                    title: "Aus Vorjahr übernehmen",
                    subtitle: "Wähle Fächer aus \(prevYear) ohne Noten.",
                    icon: "clock.arrow.circlepath",
                    accent: .orange,
                    badge: !selectedPrevSubjects.isEmpty ? "\(selectedPrevSubjects.count) gewählt" : nil
                ) {
                    if isLoadingPrevSubjects {
                        ProgressView().padding(.vertical, 4)
                    } else if prevYearSubjects.isEmpty {
                        Text("Keine Fächer im Vorjahr gefunden.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(prevYearSubjects, id: \.name) { subj in
                                let isOn = selectedPrevSubjects.contains(subj.name)
                                selectionRow(title: subj.name, isSelected: isOn, accent: .orange) {
                                    if isOn { selectedPrevSubjects.remove(subj.name) }
                                    else { selectedPrevSubjects.insert(subj.name) }
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
                        .buttonStyle(SoftTintButtonStyle(accent: .orange))
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

            sectionCard(
                title: "Eigene Fächer",
                subtitle: isSchoolYearChange || stagingMode ? "Lege Fächer für das neue Schuljahr an." : "Weitere Fächer direkt anlegen.",
                icon: "pencil.and.outline",
                accent: .green
            ) {
                if isSchoolYearChange || stagingMode {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Fachname", text: $manualNameInput)
                            .submitLabel(.done)
                            .onSubmit { hideKeyboard() }
                            .padding(10)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Picker("Typ", selection: $manualType) {
                            Text("Hauptfach").tag(1)
                            Text("Nebenfach").tag(0)
                        }
                        .pickerStyle(.segmented)
                        .disabled(manualIsElective)

                        Toggle("Wahlfach / nicht einbringbar", isOn: $manualIsElective)
                            .onChange(of: manualIsElective) { _, val in
                                if val { manualType = 0 }
                            }

                        Button("Fach vormerken") {
                            addPendingManualSubject()
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .green))
                        .disabled(manualNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if let manualError {
                            Text(manualError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if !pendingManualSubjects.isEmpty {
                        Divider().padding(.vertical, 6)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(pendingManualSubjects, id: \.id) { subj in
                                selectionRow(
                                    title: "\(subj.name)\(subj.isElective ? " (Wahlfach)" : "")",
                                    isSelected: true,
                                    accent: .green
                                ) {
                                    pendingManualSubjects.removeAll { $0.id == subj.id }
                                }
                            }
                        }
                    }
                } else {
                    Button("Fach hinzufügen") {
                        showAddSubjectSheet = true
                    }
                    .buttonStyle(SoftTintButtonStyle(accent: .green))

                    if store.subjects.isEmpty {
                        Text("Noch keine Fächer angelegt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.sortedSubjectsForDisplay(), id: \.name) { subj in
                                selectionRow(
                                    title: subj.name,
                                    isSelected: !removingSubjectNames.contains(subj.name),
                                    accent: .green
                                ) {
                                    if removingSubjectNames.contains(subj.name) { return }
                                    removeSubject(subj.name)
                                }
                            }
                        }
                    }
                }
            }

            if isSchoolYearChange || stagingMode {
                sectionCard(
                    title: "Vorgemerkte Fächer",
                    subtitle: "Alles, was übernommen oder angelegt wird.",
                    icon: "checkmark.seal.fill",
                    accent: .mint
                ) {
                    let stagedPrev = Array(pendingPrevSubjectNames).sorted()
                    let stagedManual = pendingManualSubjects
                    let stagedLegacy = store.legacyImportSelected == true ? Array(store.legacySelectedSubjects).sorted() : []
                    let stagedGroups = selectedGroupSubjectNames.sorted()
                    if stagedPrev.isEmpty && stagedManual.isEmpty && stagedLegacy.isEmpty && stagedGroups.isEmpty {
                        Text("Noch keine Fächer ausgewählt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(stagedLegacy, id: \.self) { name in
                                stagedSubjectRow(title: name, icon: "shippingbox.fill", tint: accentPrimary) {
                                    toggleLegacySubject(name: name, isOn: false)
                                }
                            }
                            ForEach(stagedGroups, id: \.self) { name in
                                stagedSubjectRow(title: name, icon: "person.3.fill", tint: .blue) {
                                    setGroupSubjectSelection(name: name, isOn: false)
                                }
                            }
                            ForEach(stagedPrev, id: \.self) { name in
                                stagedSubjectRow(title: name, icon: "clock.arrow.circlepath", tint: .orange) {
                                    pendingPrevSubjectNames.remove(name)
                                }
                            }
                            ForEach(stagedManual, id: \.id) { subj in
                                let label = "\(subj.name)\(subj.isElective ? " (Wahlfach)" : "")"
                                stagedSubjectRow(title: label, icon: "pencil.and.outline", tint: .green) {
                                    pendingManualSubjects.removeAll { $0.id == subj.id }
                                }
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
            .buttonStyle(SoftTintButtonStyle(accent: accentPrimary))
            .disabled(isFinishing || !hasSubjects)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accentPrimary.opacity(store.darkMode ? 0.25 : 0.2),
                            tileBackground
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(accentPrimary.opacity(store.darkMode ? 0.35 : 0.25), lineWidth: 1)
                )
        )
    }

    private var stepSubtitle: String {
        switch currentStep {
        case .legacy:
            return "Daten aus der Web-App gefunden. Entscheide, ob du sie übernehmen möchtest."
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

    private func normalizeGroupCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var gradeOptionsForSchoolType: [Int] {
        selectedSchoolType == .fos ? [11, 12, 13] : [12, 13]
    }

    private var schoolYearAlreadyExists: Bool {
        let trimmed = schoolYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return store.schoolYears.contains(trimmed)
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
        if schoolYearAlreadyExists {
            schoolYearError = "Dieses Schuljahr gibt es schon. Bitte ein anderes Jahr wählen."
            return
        }
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
        let code = normalizeGroupCode(joinCode)
        guard !code.isEmpty else { return }
        if visibleGroupIds.contains(code) {
            joinInfo = "Gruppe bereits hinzugefügt."
            joinError = nil
            return
        }

        joinInfo = nil
        joinError = nil
        isJoining = true

        Task {
            do {
                if isSchoolYearChange {
                    let metadata = await store.groupMetadata(for: code)
                    if !metadata.exists {
                        await MainActor.run {
                            joinError = "Diese Gruppe existiert nicht."
                            joinInfo = nil
                            isJoining = false
                        }
                        return
                    }
                    if let targetYear = pendingSchoolYearId,
                       let groupYear = metadata.schoolYearId,
                       !groupYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       groupYear != targetYear {
                        await MainActor.run {
                            joinError = "Diese Gruppe gehört zum Schuljahr \(groupYear)."
                            joinInfo = nil
                            isJoining = false
                        }
                        return
                    }
                    await MainActor.run {
                        pendingGroupCodes.insert(code)
                        joinCode = ""
                        joinInfo = "Gruppe wird im neuen Schuljahr verbunden."
                        joinError = nil
                    }
                    await store.loadGroupName(gid: code)
                    await MainActor.run { isJoining = false }
                    return
                }

                let staging = stagingMode
                try await store.joinExistingSharedGroup(with: code, allowYearCreation: !staging)
                await MainActor.run {
                    joinInfo = staging ? "Gruppe vorgemerkt. Fächer werden beim Abschluss übernommen." : "Gruppe verbunden."
                    joinCode = ""
                    if staging { pendingGroupCodes.insert(code) }
                    prepareGroupSubjectCandidates()
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
        prepareGroupSubjectCandidates()
        if previousSchoolYearId != nil && prevYearSubjects.isEmpty {
            Task { await loadPrevSubjects() }
        }
    }

    private func closeOnboarding() {
        if isSchoolYearChange {
            dismiss()
            onFinished()
        } else if isManualRestart {
            store.onboardingRequired = false
            dismiss()
            onFinished()
        }
    }

    private func goBack() {
        guard currentStep.rawValue > 0 else { return }
        if let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    private func removeSubject(_ name: String) {
        guard !removingSubjectNames.contains(name) else { return }
        removingSubjectNames.insert(name)
        Task {
            await store.deleteSubjectFromFirestore(subjectName: name)
            await MainActor.run {
                removingSubjectNames.remove(name)
                prepareGroupSubjectCandidates()
            }
        }
    }

    private func leaveGroup(_ gid: String) {
        guard !leavingGroupIds.contains(gid) else { return }
        if isSchoolYearChange {
            leavingGroupIds.insert(gid)
            Task { @MainActor in
                pendingGroupCodes.remove(gid)
                leavingGroupIds.remove(gid)
            }
            return
        }
        if stagingMode {
            leavingGroupIds.insert(gid)
            Task { @MainActor in
                store.groupIds.removeAll { $0 == gid }
                store.groupSubjectsByGroup.removeValue(forKey: gid)
                store.groupNames.removeValue(forKey: gid)
                pendingGroupCodes.remove(gid)
                prepareGroupSubjectCandidates()
                leavingGroupIds.remove(gid)
            }
            return
        }
        leavingGroupIds.insert(gid)
        Task {
            await store.leaveSharedGroup(code: gid)
            _ = await MainActor.run {
                leavingGroupIds.remove(gid)
            }
        }
    }

    private func preloadGroupNames() async {
        for gid in visibleGroupIds where store.groupNames[gid] == nil {
            await store.loadGroupName(gid: gid)
        }
    }

    private func prepareGroupSubjectCandidates() {
        guard hasJoinedGroups, !isSchoolYearChange else {
            groupSubjectCandidates = []
            return
        }
        let existingSubjects = Set(store.subjects.map { $0.name.lowercased() })
        let existing = existingSubjects.union(legacySubjectLowercased)
        let previousSelection = groupSubjectCandidates.reduce(into: [String: Bool]()) { dict, item in
            dict[item.name.lowercased()] = item.selected
        }
        var draft: [String: PendingGroupSubject] = [:]

        for gid in store.groupIds {
            let subjects = store.groupSubjectsByGroup[gid] ?? []
            for subj in subjects {
                let trimmed = subj.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let lower = trimmed.lowercased()
                guard !existing.contains(lower) else { continue }

                var entry = draft[lower] ?? PendingGroupSubject(
                    name: trimmed,
                    sources: [],
                    selected: previousSelection[lower] ?? true
                )
                let source = GroupSubjectSource(groupId: gid, subjectId: subj.id, type: subj.type, alias: subj.alias)
                if !entry.sources.contains(source) {
                    entry.sources.append(source)
                }
                draft[lower] = entry
            }
        }

        groupSubjectCandidates = draft.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func toggleGroupSubjectSelection(id: UUID, isOn: Bool) {
        guard let idx = groupSubjectCandidates.firstIndex(where: { $0.id == id }) else { return }
        groupSubjectCandidates[idx].selected = isOn
    }

    private func setGroupSubjectSelection(name: String, isOn: Bool) {
        guard let idx = groupSubjectCandidates.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        groupSubjectCandidates[idx].selected = isOn
    }

    private func toggleLegacySubject(name: String, isOn: Bool) {
        if isOn {
            store.legacySelectedSubjects.insert(name)
        } else {
            store.legacySelectedSubjects.remove(name)
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
        var allowed = Set(selectedGroupSubjectNames.map { $0.lowercased() })
        if !legacySubjectLowercased.isEmpty {
            allowed.subtract(legacySubjectLowercased)
        }
        guard !allowed.isEmpty else {
            importInfo = legacySubjectLowercased.isEmpty ? "Keine Gruppenfächer ausgewählt." : "Ausgewählte Gruppenfächer sind bereits über Web-Daten abgedeckt."
            return
        }
        if stagingMode {
            importInfo = "Auswahl wird beim Abschluss übernommen."
            importError = nil
            return
        }
        importInfo = nil
        importError = nil
        isImporting = true

        Task {
            let count = await store.importSubjectsFromGroups(groupIds: nil, allowedNames: allowed)
            await MainActor.run {
                isImporting = false
                if count > 0 {
                    importInfo = "\(count) Fächer übernommen."
                } else {
                    importInfo = "Keine neuen Fächer gefunden."
                }
                prepareGroupSubjectCandidates()
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

            if !pendingGroupCodes.isEmpty {
                for code in pendingGroupCodes {
                    try? await store.joinExistingSharedGroup(with: code, allowYearCreation: true)
                }
                pendingGroupCodes.removeAll()
            }

            if !isSchoolYearChange && !selectedGroupSubjectNames.isEmpty {
                var allowed = Set(selectedGroupSubjectNames.map { $0.lowercased() })
                if !legacySubjectLowercased.isEmpty {
                    allowed.subtract(legacySubjectLowercased)
                }
                _ = await store.importSubjectsFromGroups(groupIds: nil, allowedNames: allowed)
            }

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

            if store.legacyImportSelected == true {
                await store.importLegacyDataIntoActiveYearIfNeeded()
            }

            await store.markOnboardingCompletedIfPossible()
            await MainActor.run {
                isFinishing = false
                onFinished()
            }
        }
    }
}
