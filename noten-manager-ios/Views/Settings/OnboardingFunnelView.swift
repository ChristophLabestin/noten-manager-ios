import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct OnboardingFunnelView: View {
    enum Step: String, CaseIterable {
        case welcome, legacy, schoolYear, prevYearPrompt, joinClass, subjects, finish
    }

    struct PendingSubject: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let type: Int
        let isElective: Bool
        var gradingMode: GradingMode
    }
    
    enum BranchStream: String, CaseIterable, Identifiable {
        case manual = "Manuell"
        case technik = "Technik"
        case wirtschaft = "Wirtschaft"
        case sozial = "Sozial"
        case gesundheit = "Gesundheit"
        case gestaltung = "Gestaltung"
        case agrar = "Agrar"
        
        var id: String { rawValue }
        
        var defaultSubjects: [PendingSubject] {
            let common = [
                PendingSubject(name: "Deutsch", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                PendingSubject(name: "Mathematik", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                PendingSubject(name: "Englisch", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                PendingSubject(name: "Religion/Ethik", type: 2, isElective: false, gradingMode: .withoutSchulaufgaben),
                PendingSubject(name: "Geschichte", type: 2, isElective: false, gradingMode: .withoutSchulaufgaben),
                PendingSubject(name: "Sozialkunde", type: 2, isElective: false, gradingMode: .withoutSchulaufgaben)
            ]
            
            switch self {
            case .manual: return []
            case .technik:
                return common + [
                    PendingSubject(name: "Physik", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Chemie", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Informatik", type: 1, isElective: false, gradingMode: .withSchulaufgaben)
                ]
            case .wirtschaft:
                return common + [
                    PendingSubject(name: "BWR", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "VWL", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Informatik", type: 1, isElective: false, gradingMode: .withSchulaufgaben)
                ]
            case .sozial:
                return common + [
                    PendingSubject(name: "Pädagogik/Psychologie", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Biologie", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Soziologie", type: 1, isElective: false, gradingMode: .withSchulaufgaben)
                ]
            case .gesundheit:
                return common + [
                    PendingSubject(name: "Gesundheit", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Biologie", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Chemie", type: 1, isElective: false, gradingMode: .withSchulaufgaben)
                ]
            case .gestaltung:
                return common + [
                    PendingSubject(name: "Gestaltung", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Kunst", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Medien", type: 1, isElective: false, gradingMode: .withSchulaufgaben)
                ]
            case .agrar:
                return common + [
                    PendingSubject(name: "Agrarwirtschaft", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Biologie", type: 1, isElective: false, gradingMode: .withSchulaufgaben),
                    PendingSubject(name: "Chemie", type: 1, isElective: false, gradingMode: .withSchulaufgaben)
                ]
            }
        }
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

    @State private var currentStep: Step = .welcome
    @State private var schoolYearInput: String = ""
    @State private var gradeSelection: Int = 0
    @State private var selectedSchoolType: SchoolType = .bos
    @State private var schoolYearError: String?
    @State private var isSavingSchoolYear: Bool = false


    @State private var pendingSchoolYearId: String?
    @State private var pendingSchoolType: SchoolType = .bos
    @State private var pendingGradeYear: Int = 0
    @State private var pendingPrevSubjectNames: Set<String> = []
    @State private var pendingManualSubjects: [PendingSubject] = []
    @State private var manualNameInput: String = ""

    @State private var manualIsElective: Bool = false
    @State private var manualError: String?
    // @State private var groupSubjectCandidates: [PendingGroupSubject] = [] // Removed

    @State private var finishError: String?
    @State private var isFinishing: Bool = false
    @State private var showAddSubjectSheet: Bool = false
    @State private var removingSubjectNames: Set<String> = []
    @State private var selectedStream: BranchStream = .manual
    @State private var isHandlingLegacyChoice: Bool = false
    
    @State private var prevYearSubjects: [String] = []
    @State private var isLoadingPrevYear: Bool = false
    @State private var showPrevYearSubjects: Bool = false

    // New: Class Join & Mapping
    @State private var onboardingClassCode: String = ""
    @State private var isJoiningClass: Bool = false
    @State private var classJoinError: String?
    @State private var showCourseJoinSheet: Bool = false
    @State private var joinContextForSheet: ClassJoinContext?
    @State private var showSubjectMappingSheet: Bool = false
    @State private var joinedCoursesForMapping: [Course] = []
    @State private var mappedClassId: String?
    @State private var showScanner: Bool = false
    @State private var showHelpSheet: Bool = false
    @State private var showFeatureBriefing: Bool = false

    @State private var wasAlreadyConfigured: Bool = false
    @State private var shouldPromptPrevYear: Bool = false
    
    // New: Previous Year Prompt
    @State private var wantsPrevYear: Bool = false
    
    // School-year scoped class state for onboarding
    @State private var onboardingClassIds: [String] = []
    @State private var onboardingClassNames: [String: String] = [:]
    @State private var joinedClassSubjectCount: Int = 0


    struct ClassJoinContext: Identifiable {
        let id: String
        let name: String
        let config: ClassConfiguration?
        let linkedClassIds: [String]
    }

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
        !isSchoolYearChange && store.onboardingAlreadyCompleted
    }


    private var showSignOutButton: Bool {
        !isSchoolYearChange && !isManualRestart && store.onboardingRequired
    }

    private var showCloseButton: Bool {
        isSchoolYearChange || isManualRestart
    }

    private var primaryActionTitle: String {
        switch currentStep {
        case .welcome: return "Jetzt einrichten"
        case .legacy: return "Daten übernehmen"
        case .schoolYear: return "Weiter"
        case .prevYearPrompt: return "Weiter"
        case .joinClass: 
             if hasJoinedClasses { return "Weiter" }
             return onboardingClassCode.isEmpty ? "Weiter" : "Beitreten"
        case .subjects: return "Weiter"
        case .finish: return "Setup abschließen"
        }
    }
    
    private var isPrimaryActionDisabled: Bool {
        switch currentStep {
        case .schoolYear: return false
        case .joinClass: return isJoiningClass
        case .subjects: return false // Allow proceeding without subjects
        case .finish: return isFinishing
        default: return false
        }
    }
    
    private func handlePrimaryAction() {
        switch currentStep {
        case .welcome: withAnimation { currentStep = .schoolYear }
        case .legacy: handleLegacyChoice(keep: true)
        case .schoolYear: handleSchoolYearContinue()
        case .prevYearPrompt: withAnimation { currentStep = .joinClass }
        case .joinClass: handleJoinClassAction()
        case .subjects: withAnimation { currentStep = .finish }
        case .finish: finishSetup()
        }
    }

    private var canGoBack: Bool {
        currentStep != .welcome
    }

    private var hasSubjects: Bool {
        if isSchoolYearChange {
            return !pendingPrevSubjectNames.isEmpty || !pendingManualSubjects.isEmpty
        }
        if store.legacyImportSelected == true && !store.legacySelectedSubjects.isEmpty {
            return true
        }
        return !store.subjects.isEmpty || !pendingManualSubjects.isEmpty
    }

    private var hasJoinedClasses: Bool {
        !currentJoinClassIds.isEmpty
    }

    private var pendingYearId: String {
        let pending = pendingSchoolYearId ?? schoolYearInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return pending.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private var usesPendingClassContext: Bool {
        guard !pendingYearId.isEmpty else { return false }
        guard let activeId = store.activeSchoolYearId else { return true }
        return pendingYearId != activeId
    }

    private var currentJoinClassIds: [String] {
        usesPendingClassContext ? onboardingClassIds : store.classIds
    }

    private var currentJoinClassNames: [String: String] {
        usesPendingClassContext ? onboardingClassNames : store.classNames
    }
    
    // Helper to extract code from URL
    private func extractCode(from raw: String) -> String {
        if raw.contains("://") || raw.contains("http"), let url = URL(string: raw) {
            return url.lastPathComponent
        }
        return raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /* Legacy Group Properties Removed
    private var uniqueGroupSubjectCount: Int { ... }
    private var stagedGroupSubjectCount: Int { ... }
    private var selectedGroupSubjectNames: [String] { ... }
    */

    private var legacyAvailableSubjectNames: [String] {
        let summaryNames = store.legacyMigrationSummary?.subjectNames ?? []
        let trimmedSummary = summaryNames
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
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

    private var visibleSteps: [Step] {
        Step.allCases.filter { step in
            if step == .legacy && !legacyStepRequired { return false }
            if step == .prevYearPrompt && !shouldPromptPrevYear { return false }
            return true
        }
    }
    
    private func computePrevYearPrompt(schoolType: SchoolType, grade: Int) -> Bool {
        schoolType == .fos && (grade == 12 || grade == 13)
    }


    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                
                VStack(spacing: 0) {
                    // Progress Indicator
                    HStack(spacing: 4) {
                        let steps = visibleSteps
                        let currentIdx = steps.firstIndex(of: currentStep) ?? 0
                        ForEach(0..<steps.count, id: \.self) { idx in
                            let step = steps[idx]
                            let isActive = currentStep == step
                            let isPast = currentIdx > idx
                            
                            Capsule()
                                .fill(isActive ? accentPrimary : (isPast ? accentPrimary.opacity(0.6) : accentPrimary.opacity(0.2)))
                                .frame(height: 4)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    
                    TabView(selection: $currentStep) {
                        WelcomePage()
                            .tag(Step.welcome)
                        
                        if legacyStepRequired {
                            if let summary = store.legacyMigrationSummary {
                                LegacyPage(summary: summary)
                                    .tag(Step.legacy)
                            }
                        }
                        
                        SchoolYearPage()
                            .tag(Step.schoolYear)
                        
                        if shouldPromptPrevYear {
                            PrevYearPage()
                                .tag(Step.prevYearPrompt)
                        }
                        
                        JoinClassPage()
                            .tag(Step.joinClass)
                        
                        SubjectsPage()
                            .tag(Step.subjects)
                        
                        FinishPage()
                            .tag(Step.finish)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
                
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer()
                        VStack(spacing: 8) {
                            Button {
                                handlePrimaryAction()
                            } label: {
                                HStack {
                                    if isSavingSchoolYear || isFinishing || isHandlingLegacyChoice || isJoiningClass {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(primaryActionTitle)
                                    }
                                }
                            }
                            .buttonStyle(PremiumOnboardingButtonStyle(accent: accentPrimary))
                            .disabled(isPrimaryActionDisabled)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 8 : 16)
                        .background(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .ignoresSafeArea(.keyboard)
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if canGoBack {
                            Button(action: goBack) {
                                ToolbarIcon(symbol: "chevron.left", showDot: false)
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 0) {
                            Button {
                                showHelpSheet = true
                            } label: {
                                ToolbarIcon(symbol: "questionmark.circle", showDot: false)
                            }
                            
                            if showCloseButton {
                                Button(action: closeOnboarding) {
                                    ToolbarIcon(symbol: "xmark", showDot: false)
                                }
                            } else if showSignOutButton || currentStep == .welcome {
                                Button {
                                    authManager.signOut()
                                    dismiss()
                                } label: {
                                    ToolbarIcon(symbol: "rectangle.portrait.and.arrow.right", showDot: false, color: .red)
                                }

                            }
                        }
                    }
                }
                .sheet(isPresented: $showHelpSheet) {
                    NavigationStack {
                        HelpCenterView()
                            .environmentObject(store)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {
                                        showHelpSheet = false
                                    } label: {
                                        ToolbarIcon(symbol: "xmark", showDot: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                    }
                }
                .onAppear {
                    bootstrapDefaults()
                    currentStep = .welcome
                }
                .onChange(of: selectedSchoolType) { _, newType in
                    let allowed = gradeOptionsForSchoolType
                    if !allowed.contains(gradeSelection) {
                        gradeSelection = allowed.first ?? 0
                    }
                    if currentStep == .schoolYear {
                        shouldPromptPrevYear = computePrevYearPrompt(schoolType: newType, grade: gradeSelection)
                    }
                }
                .onChange(of: gradeSelection) { _, newGrade in
                    if currentStep == .schoolYear {
                        shouldPromptPrevYear = computePrevYearPrompt(schoolType: selectedSchoolType, grade: newGrade)
                    }
                }
                .onChange(of: currentStep) { _, newStep in
                    if newStep == .joinClass && usesPendingClassContext {
                        Task { await loadOnboardingClasses() }
                    }
                }
                .onChange(of: shouldPromptPrevYear) { _, newValue in
                    if currentStep == .prevYearPrompt && !newValue {
                        currentStep = .joinClass
                    }
                }
                .sheet(isPresented: $showAddSubjectSheet) {
                    AddSubjectView()
                        .environmentObject(store)
                }
                .sheet(isPresented: $showCourseJoinSheet) {
                    if let ctx = joinContextForSheet {
                        CourseJoinView(
                            classId: ctx.id,
                            className: ctx.name,
                            config: ctx.config,
                            linkedClassIds: ctx.linkedClassIds,
                            targetSchoolYearId: usesPendingClassContext ? pendingYearId : nil,
                            updateLocalState: !usesPendingClassContext,
                            onJoinSuccess: {
                                showCourseJoinSheet = false
                                self.mappedClassId = ctx.id
                                if usesPendingClassContext {
                                    if !self.onboardingClassIds.contains(ctx.id) {
                                        self.onboardingClassIds.append(ctx.id)
                                    }
                                    self.onboardingClassNames[ctx.id] = ctx.name
                                    withAnimation { currentStep = .subjects }
                                } else {
                                    // Check for mapping
                                    let missing = store.missingSubjects(for: ctx.id)
                                    if !missing.isEmpty {
                                        self.joinedCoursesForMapping = missing
                                        self.showSubjectMappingSheet = true
                                    } else {
                                        withAnimation { currentStep = .subjects }
                                    }
                                }
                            }
                        )
                        .environmentObject(store)
                    }
                }
                .sheet(isPresented: $showSubjectMappingSheet) {
                    if let activeClassId = mappedClassId {
                        SubjectMappingView(classId: activeClassId, courses: joinedCoursesForMapping)
                            .environmentObject(store)
                            .onDisappear {
                                withAnimation { currentStep = .subjects }
                            }
                    }
                }
                .sheet(isPresented: $showScanner) {
                    QRScannerView { scannedCode in
                        onboardingClassCode = extractCode(from: scannedCode)
                    }
                }
                .sheet(isPresented: $showFeatureBriefing) {
                    FeatureBriefingSheet()
                }
                .onChange(of: store.legacyMigrationSummary) { _, summary in
                    if summary != nil {
                        currentStep = .legacy
                    }
                }
                .keyboardDismissToolbar()
            }
        }
    }


    private func handleLegacyChoice(keep: Bool) {
        guard !isHandlingLegacyChoice else { return }
        isHandlingLegacyChoice = true
        Task {
            await store.handleLegacyMigrationChoice(keepWebData: keep)
            await MainActor.run {
                isHandlingLegacyChoice = false
                withAnimation {
                    currentStep = .schoolYear
                }
                if !keep {
                    store.legacySelectedSubjects = []
                }
            }
        }
    }


    private func isValidSchoolYear(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).uppercased()
    }

    private var gradeOptionsForSchoolType: [Int] {
        selectedSchoolType == .fos ? [11, 12, 13] : [12, 13]
    }

    private var schoolYearAlreadyExists: Bool {
        if store.onboardingRequired && !isSchoolYearChange {
            return false
        }
        let trimmed = schoolYearInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return store.schoolYears.contains(trimmed)
    }

    private func bootstrapDefaults() {
        wasAlreadyConfigured = (store.activeSchoolYearId != nil || !store.subjects.isEmpty)
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
        shouldPromptPrevYear = computePrevYearPrompt(schoolType: selectedSchoolType, grade: gradeSelection)
        pendingSchoolYearId = schoolYearInput
        pendingSchoolType = selectedSchoolType
        pendingGradeYear = gradeSelection
        
        // Optimization: Skip loading previous year subjects for manual restarts
        // unless explicitly needed. Manual restarts usually imply just re-doing the current year.
        if isSchoolYearChange || !store.onboardingAlreadyCompleted {
            Task { await loadPrevYearSubjects() }
        }
    }
    
    private var availableSchoolYears: [String] {
        let currentId = SchoolYearService.currentSchoolYearId()
        guard let startYear = Int(currentId.prefix(4)) else { return [currentId] }
        var years = (-5...2).map { offset in
            let start = startYear + offset
            let end = start + 1
            let endSuffix = String(format: "%02d", end % 100)
            return "\(start)-\(endSuffix)"
        }
        let trimmed = schoolYearInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !trimmed.isEmpty && !years.contains(trimmed) {
            years.append(trimmed)
            years.sort { (lhs, rhs) in
                let left = Int(lhs.prefix(4)) ?? 0
                let right = Int(rhs.prefix(4)) ?? 0
                return left < right
            }
        }
        return years
    }
    
    private func loadPrevYearSubjects() async {
        guard let uid = authManager.currentUser?.uid else { return }
        // Try to find the "logical" previous year if not already set
        let targetPrevId: String
        if let pId = previousSchoolYearId {
            targetPrevId = pId
        } else {
            // Predict based on current year input
            let current = schoolYearInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pred = previousSchoolYearId(from: current) else { return }
            targetPrevId = pred
        }
        
        _ = await MainActor.run { isLoadingPrevYear = true }
        
        do {
            let yearRef = Firestore.firestore().collection("users").document(uid).collection("schoolYears").document(targetPrevId)
            let subjectsSnap = try await yearRef.collection("subjects").getDocuments()
            let names = subjectsSnap.documents.compactMap { $0.data()["name"] as? String }
            
            _ = await MainActor.run {
                self.prevYearSubjects = names.sorted()
                self.isLoadingPrevYear = false
            }
        } catch {
            _ = await MainActor.run { self.isLoadingPrevYear = false }
        }
    }
    
    private func previousSchoolYearId(from id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 7, let startYear = Int(trimmed.prefix(4)) else { return nil }
        let prevStart = startYear - 1
        let prevEnd = startYear
        let endSuffix = String(format: "%02d", prevEnd % 100)
        return "\(prevStart)-\(endSuffix)"
    }

    private func handleSchoolYearContinue() {
        guard !isSavingSchoolYear else { return }
        let targetId = schoolYearInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
                shouldPromptPrevYear = computePrevYearPrompt(schoolType: selectedSchoolType, grade: gradeSelection)
                onboardingClassIds = []
                onboardingClassNames = [:]
                isSavingSchoolYear = false
                withAnimation {
                    if shouldPromptPrevYear {
                        currentStep = .prevYearPrompt
                    } else {
                        currentStep = .joinClass
                    }
                }
            }
        }
    }

    private func handleJoinClassAction() {
        if hasJoinedClasses {
            withAnimation { currentStep = .subjects }
            return
        }
        
        let code = onboardingClassCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty {
            withAnimation { currentStep = .subjects }
            return
        }
        
        isJoiningClass = true
        classJoinError = nil
        let targetYearId = usesPendingClassContext ? pendingYearId : nil
        let shouldUpdateLocal = !usesPendingClassContext
        
        Task {
            do {
                let info = try await store.fetchClassInfo(with: code)
                if let config = info.config {
                    // Has branches -> Always show sheet
                    await MainActor.run {
                        self.joinContextForSheet = ClassJoinContext(
                            id: info.id,
                            name: info.name,
                            config: config,
                            linkedClassIds: info.linkedClassIds ?? []
                        )
                        self.isJoiningClass = false
                        self.showCourseJoinSheet = true
                    }
                } else if let linked = info.linkedClassIds, !linked.isEmpty {
                    // No branches, but has linked classes -> Show sheet to opt-in
                    await MainActor.run {
                        self.joinContextForSheet = ClassJoinContext(
                            id: info.id,
                            name: info.name,
                            config: nil,
                            linkedClassIds: linked
                        )
                        self.isJoiningClass = false
                        self.showCourseJoinSheet = true
                    }
                } else {
                    _ = try await store.joinClass(with: code, targetSchoolYearId: targetYearId, updateLocalState: shouldUpdateLocal)
                    await MainActor.run {
                        self.isJoiningClass = false
                        self.mappedClassId = info.id
                        
                        if usesPendingClassContext {
                            if !self.onboardingClassIds.contains(info.id) {
                                self.onboardingClassIds.append(info.id)
                            }
                            self.onboardingClassNames[info.id] = info.name
                            withAnimation { currentStep = .subjects }
                        } else {
                            let missing = store.missingSubjects(for: info.id)
                            if !missing.isEmpty {
                                self.joinedCoursesForMapping = missing
                                self.showSubjectMappingSheet = true
                            } else {
                                withAnimation { currentStep = .subjects }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.classJoinError = error.localizedDescription
                    self.isJoiningClass = false
                }
            }
        }
    }

    private func loadOnboardingClasses() async {
        guard let uid = authManager.currentUser?.uid else { return }
        let targetId = pendingYearId
        guard !targetId.isEmpty else { return }
        do {
            let yearRef = Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("schoolYears")
                .document(targetId)
            let snap = try await yearRef.getDocument()
            let ids = snap.data()?["classIds"] as? [String] ?? []
            var names: [String: String] = [:]
            for classId in ids {
                if let info = try? await store.fetchClassInfo(with: classId) {
                    names[classId] = info.name
                }
            }
            await MainActor.run {
                onboardingClassIds = ids
                onboardingClassNames = names
            }
        } catch {
            await MainActor.run {
                onboardingClassIds = []
                onboardingClassNames = [:]
            }
        }
    }

    
    private func closeOnboarding() {
        if isSchoolYearChange {
            dismiss()
            onFinished()
            // If it was a manual restart, we MUST reset the flag to false
            // to allow the user to trigger it again later from settings.
            store.onboardingRequired = false
            
            // Fix: Confirm online session
            if let uid = authManager.currentUser?.uid {
                OfflineModeManager.shared.recordOnlineLogin(uid: uid)
                OfflineModeManager.shared.deactivateOfflineMode()
            }
            
            dismiss()
            onFinished()
        } else {
            // Initial onboarding: we don't set it to false if they just close it?
            // User feedback says closing it makes it unselectable.
            // If they close initial onboarding, it should probably STAY required
            // but the sheet needs to be dismissed.
            // However, the SHEET follows store.onboardingRequired.
            // So we MUST set it to false to close, but the bug is it becomes "unselectable".
            // The fix in GradesStore handles the "unselectable" part by toggling.
            store.onboardingRequired = false
            dismiss()
            onFinished()
        }
    }

    private func goBack() {
        let steps = visibleSteps
        if let idx = steps.firstIndex(of: currentStep), idx > 0 {
            withAnimation { currentStep = steps[idx - 1] }
        }
    }

    private func removeSubject(_ name: String) {
        guard !removingSubjectNames.contains(name) else { return }
        removingSubjectNames.insert(name)
        Task {
            await store.deleteSubjectFromFirestore(subjectName: name)
            _ = await MainActor.run {
                removingSubjectNames.remove(name)
            }
        }
    }

    // removed preloadGroupNames


    // Removed toggleGroupSubjectSelection & setGroupSubjectSelection

    private func toggleLegacySubject(name: String, isOn: Bool) {
        if isOn {
            store.legacySelectedSubjects.insert(name)
        } else {
            store.legacySelectedSubjects.remove(name)
        }
    }

    private func addPendingManualSubject() {
        let name = manualNameInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if pendingManualSubjects.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            manualNameInput = ""
            return
        }
        // Default to withSchulaufgaben (type 1)
        let type = 1
        let subj = PendingSubject(name: name, type: type, isElective: manualIsElective, gradingMode: .withSchulaufgaben)
        withAnimation {
            pendingManualSubjects.append(subj)
            manualNameInput = ""
        }
    }
}

// MARK: - Components
extension OnboardingFunnelView {
    func HeaderSection(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 20)
    }
}

// MARK: - Pages
extension OnboardingFunnelView {
    @ViewBuilder
    func LegacyPage(summary: LegacyMigrationSummary) -> some View {
        VStack(spacing: 24) {
            HeaderSection(
                icon: "shippingbox.fill",
                title: "Web-Daten gefunden",
                subtitle: "Wir haben Inhalte aus der Web-Version erkannt. Möchtest du diese übernehmen?"
            )
            
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(accentPrimary)
                    Text("Zusammenfassung")
                        .font(.headline)
                }
                
                VStack(spacing: 10) {
                    summaryStatRow(icon: "text.book.closed.fill", title: "\(summary.subjectCount) Fächer", subtitle: "inkl. Einstellungen")
                    summaryStatRow(icon: "number.square.fill", title: "\(summary.gradeCount) Noten", subtitle: "bestehende Bewertungen")
                    if let year = summary.gradeYear {
                        summaryStatRow(icon: "graduationcap.fill", title: "Klassenstufe \(year)", subtitle: "aus Web-Einstellungen")
                    }
                }
            }
            .padding(20)
            .glassCard()
            .padding(.horizontal, 24)
            
            Spacer()
            
            VStack(spacing: 16) {
                Button("Neu anfangen (Web-Daten ignorieren)") {
                    handleLegacyChoice(keep: false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 120) // Accounting for fixed button
            }
        }
    }
    
    private func summaryStatRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accentPrimary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    func JoinClassPage() -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                HeaderSection(
                    icon: "person.badge.plus.fill",
                    title: "Klasse beitreten",
                    subtitle: "Überspringe diesen Schritt, wenn du deine Fächer manuell verwalten möchtest."
                )
                
                if let classId = currentJoinClassIds.first {
                    // JOINED STATE
                    SettingsCard(
                        title: "Beigetreten",
                        subtitle: currentJoinClassNames[classId] ?? "Deine Klasse",
                        systemImage: "checkmark.circle.fill",
                        accent: .green
                    ) {
                        VStack(spacing: 16) {
                            Text("Du bist der Klasse **\(currentJoinClassNames[classId] ?? classId)** erfolgreich beigetreten.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                Task {
                                    await store.leaveClass(code: classId, targetSchoolYearId: usesPendingClassContext ? pendingYearId : nil, updateLocalState: !usesPendingClassContext)
                                    await MainActor.run {
                                        mappedClassId = nil
                                        onboardingClassIds.removeAll { $0 == classId }
                                        onboardingClassNames.removeValue(forKey: classId)
                                    }
                                }
                            } label: {
                                Label("Klasse verlassen", systemImage: "rectangle.portrait.and.arrow.right")
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 20)
                } else {
                    // INPUT STATE
                    SettingsCard(
                        title: "Klassencode",
                        subtitle: "Optional",
                        systemImage: "qrcode",
                        accent: .indigo
                    ) {
                        VStack(spacing: 12) {
                            TextField("Code eingeben", text: $onboardingClassCode)
                                .font(.title3.monospaced())
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.characters)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.formInputBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                                )
                            
                            Button {
                                showScanner = true
                            } label: {
                                Label("QR-Code scannen", systemImage: "viewfinder")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(.indigo)
                            
                            if let err = classJoinError {
                                Text(err)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)
                            }
                            
                            Text("Tipp: Du kannst deine Klasse auch später im Klassen-Tab hinzufügen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer(minLength: 120)
            }
        }
    }

    @ViewBuilder
    func SchoolYearPage() -> some View {
        SchoolYearSetupView(
            schoolYearInput: $schoolYearInput,
            selectedSchoolType: $selectedSchoolType,
            gradeSelection: $gradeSelection,
            availableSchoolYears: availableSchoolYears,
            gradeOptions: gradeOptionsForSchoolType,
            accentColor: accentPrimary,
            currentSchoolYearId: SchoolYearService.currentSchoolYearId(),
            error: schoolYearError
        ) {
            HeaderSection(
                icon: "calendar.badge.clock",
                title: "Schuljahr wählen",
                subtitle: "Wann und wo startest du durch?"
            )
        }
    }

    @ViewBuilder
    func WelcomePage() -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accentPrimary.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(accentPrimary)
                    }
                    
                    VStack(spacing: 8) {
                        Text("NotenManager")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        Text("Dein Begleiter zum Abschluss")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    WelcomeFeatureCard(
                        icon: "chart.bar.fill",
                        title: "Schnitt-Analyse",
                        subtitle: "Automatische MSS-Berechnung für Bayern.",
                        accent: .blue
                    )
                    
                    WelcomeFeatureCard(
                        icon: "person.2.fill",
                        title: "Klassen-Sync",
                        subtitle: "Fächer und Termine mit anderen teilen.",
                        accent: .green
                    )
                    
                    WelcomeFeatureCard(
                        icon: "cloud.fill",
                        title: "Multi-Plattform",
                        subtitle: "Deine Noten auf iOS und Android.",
                        accent: .orange
                    )
                    
                    WelcomeFeatureCard(
                        icon: "graduationcap.fill",
                        title: "Abitur-Rechner",
                        subtitle: "Smarte Prognosen für deinen Abschluss.",
                        accent: .purple
                    )

                    WelcomeFeatureCard(
                        icon: "wifi.slash",
                        title: "Offline-Backup",
                        subtitle: "Lerne überall – auch ohne Internet.",
                        accent: .gray
                    )
                }
                .padding(.horizontal, 20)
                
                Button {
                    showFeatureBriefing = true
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Alle Features entdecken")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(accentPrimary.opacity(0.1))
                    .clipShape(Capsule())
                }

                if legacyStepRequired, let summary = store.legacyMigrationSummary {
                    SettingsCard(
                        title: "Web-Daten gefunden",
                        subtitle: "\(summary.subjectCount) Fächer & \(summary.gradeCount) Noten",
                        systemImage: "shippingbox.fill",
                        accent: accentPrimary
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Möchtest du deine bestehenden Daten aus der Web-Version übernehmen?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                Button("Übernehmen") {
                                    handleLegacyChoice(keep: true)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: accentPrimary))
                                
                                Button("Neu beginnen") {
                                    handleLegacyChoice(keep: false)
                                }
                                .buttonStyle(SoftTintButtonStyle(accent: .red))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .softFadeIn(enabled: true, delay: 0.2)
                }

                Spacer(minLength: 120)
            }
        }
    }
    
    private func WelcomeFeatureCard(icon: String, title: String, subtitle: String, accent: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .font(.title3.weight(.bold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.formCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.1), lineWidth: 1)
        )
    }


    @ViewBuilder
    func SubjectsPage() -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                HeaderSection(
                    icon: "text.book.closed.fill",
                    title: "Deine Fächer",
                    subtitle: "Wähle eine Fachrichtung oder füge Fächer manuell hinzu."
                )
                
                // Branch Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("SCHNELL-SETUP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(BranchStream.allCases) { stream in
                                let isSelected = selectedStream == stream
                                Button {
                                    selectedStream = stream
                                    DispatchQueue.main.async {
                                        pendingManualSubjects = stream.defaultSubjects
                                    }
                                } label: {
                                    Text(stream.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(isSelected ? accentPrimary : Color.formInputBackground)
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(isSelected ? .clear : .primary.opacity(0.1), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                
                // Manual Add
                VStack(alignment: .leading, spacing: 12) {
                    Text("FACH HINZUFÜGEN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                    
                    HStack(spacing: 12) {
                        TextField("Fachname eingeben...", text: $manualNameInput)
                            .padding(14)
                            .background(Color.formInputBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onSubmit { addPendingManualSubject() }
                            .submitLabel(.done)
                        
                        Button {
                            addPendingManualSubject()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .foregroundStyle(manualNameInput.isEmpty ? .secondary : accentPrimary)
                        }
                        .disabled(manualNameInput.isEmpty)
                    }
                    .padding(.horizontal, 24)
                }
                
                // Unified Subject List
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("DEINE FÄCHER")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Text("\(pendingManualSubjects.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentPrimary)
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 28)
                    
                    if pendingManualSubjects.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("Noch keine Fächer")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(Color.formInputBackground.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($pendingManualSubjects) { $subj in
                                UnifiedSubjectRow(
                                    name: subj.name,
                                    isFromPrevYear: prevYearSubjects.contains(subj.name),
                                    hasSA: Binding(
                                        get: { subj.gradingMode == .withSchulaufgaben },
                                        set: { subj.gradingMode = $0 ? .withSchulaufgaben : .withoutSchulaufgaben }
                                    ),
                                    accent: accentPrimary,
                                    onDelete: {
                                        withAnimation(.spring(response: 0.3)) {
                                            pendingManualSubjects.removeAll { $0.id == subj.id }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                Spacer(minLength: 120)
            }
        }
    }

    @ViewBuilder
    func PrevYearPage() -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                HeaderSection(
                    icon: "clock.arrow.circlepath",
                    title: "11. Klasse hinzufügen?",
                    subtitle: "Für dein Fachabitur zählen die Noten der 11. Klasse."
                )
                
                SettingsCard(
                    title: "Rückwirkend anlegen",
                    subtitle: "Optional",
                    systemImage: "calendar.badge.plus",
                    accent: .orange
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Möchtest du das vorherige Schuljahr direkt mit anlegen?")
                            .font(.headline)
                        
                        Text("Wir erstellen ein leeres Schuljahr für dich. Du kannst deine Fächer und Noten aus der 11. später jederzeit nachtragen.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            Button {
                                wantsPrevYear = true
                            } label: {
                                HStack {
                                    Text("Ja, anlegen")
                                    if wantsPrevYear {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(wantsPrevYear ? Color.orange : prevYearOptionBackground)
                                .foregroundStyle(wantsPrevYear ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(wantsPrevYear ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                wantsPrevYear = false
                            } label: {
                                HStack {
                                    Text("Nein")
                                    if !wantsPrevYear {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(!wantsPrevYear ? Color.secondary.opacity(0.2) : prevYearOptionBackground)
                                .foregroundStyle(!wantsPrevYear ? .primary : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(!wantsPrevYear ? Color.clear : Color.primary.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 120)
            }
        }
    }

    @ViewBuilder
    func FinishPage() -> some View {
        VStack(spacing: 32) {
            HeaderSection(
                icon: "checkmark.seal.fill",
                title: "Fast geschafft!",
                subtitle: "Dein Profil ist bereit zum Start."
            )
            
            VStack(spacing: 16) {
                SummaryStatCard(icon: "calendar", title: "Schuljahr", value: schoolYearInput, accent: accentPrimary)
                SummaryStatCard(icon: "graduationcap", title: "Klasse", value: "\(gradeSelection). Klasse", accent: .orange)
                
                let totalSubjects = usesPendingClassContext 
                    ? joinedClassSubjectCount + pendingManualSubjects.count 
                    : store.subjects.count + pendingManualSubjects.count
                
                SummaryStatCard(icon: "text.book.closed", title: "Fächer", value: "\(totalSubjects) Fächer", accent: .green)
            }
            .padding(.horizontal, 24)
            .task {
                if usesPendingClassContext {
                    await calculateJoinedSubjectCount()
                }
            }
            
            Spacer(minLength: 120)
        }
    }
    
    private func SummaryStatCard(icon: String, title: String, value: String, accent: Color) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .font(.title3.weight(.bold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.formCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.1), lineWidth: 1)
        )
    }

    private func finishSetup() {
        guard !isFinishing else { return }

        isFinishing = true
        Task {
            // Correctly derive parameters based on whether we are in "School Year Change" mode (using pending vars) 
            // OR initial onboarding setup (using state vars directly if pending not yet set? actually pending IS set in handleSchoolYearContinue)
            // safer to use pending variables as they are the "commit" buffer.
            
            let currentId = pendingSchoolYearId ?? schoolYearInput.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let currentGrade = pendingGradeYear > 0 ? pendingGradeYear : gradeSelection
            let currentType = pendingSchoolType // this is reliable
            
            // 1. Create PREVIOUS year if requested
            if wantsPrevYear {
                if let prevId = previousSchoolYearId(from: currentId) {
                    let prevGrade = currentGrade - 1
                    // Create empty year (passed nil for subjects/copying)
                    _ = await store.createSchoolYear(name: prevId, gradeYear: prevGrade, schoolType: currentType)
                }
            }
            
            // 2. Create/Activate CURRENT year
            let created = await store.createSchoolYear(name: currentId, gradeYear: currentGrade, schoolType: currentType)
            if created == nil {
                await store.setActiveSchoolYear(id: currentId)
            }
            
            // Apply Mandatory Subjects to CURRENT year
            for subj in pendingManualSubjects {
                try? await store.addSubjectToFirestore(
                    name: subj.name, 
                    type: subj.type, 
                    date: Date(), 
                    isElective: subj.isElective,
                    gradingMode: subj.gradingMode,
                    targetSchoolYearId: currentId 
                )
            }
            
            await store.markOnboardingCompletedIfPossible()
            
            // Fix: Explicitly confirm online session to prevent fallback to offline mode
            if let uid = authManager.currentUser?.uid {
                await MainActor.run {
                    OfflineModeManager.shared.recordOnlineLogin(uid: uid)
                    OfflineModeManager.shared.deactivateOfflineMode()
                }
            }
            
            await MainActor.run {
                isFinishing = false
                dismiss()
            }
        }
    }

    private func calculateJoinedSubjectCount() async {
        guard !onboardingClassIds.isEmpty else {
            joinedClassSubjectCount = 0
            return
        }
        var total = 0
        for classId in onboardingClassIds {
            do {
                let snapshot = try await Firestore.firestore()
                    .collection("classes")
                    .document(classId)
                    .collection("courses")
                    .count
                    .getAggregation(source: .server)
                total += Int(truncating: snapshot.count)
            } catch {
                print("Error counting courses for class \(classId): \(error)")
            }
        }
        await MainActor.run {
            self.joinedClassSubjectCount = total
        }
    }

    private var prevYearOptionBackground: Color {
        if store.darkMode {
            return Color(red: 0.16, green: 0.16, blue: 0.18)
        }
        return Color(uiColor: .systemGray6)
    }
}

// MARK: - Premium Button Style
struct PremiumOnboardingButtonStyle: ButtonStyle {
    var accent: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var shimmerOffset: CGFloat = -1

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Base Gradient
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.85), accent.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Shimmer Layer
                    GeometryReader { geo in
                        Color.white.opacity(0.15)
                            .mask(
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.5), .clear],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .rotationEffect(.degrees(30))
                                    .offset(x: shimmerOffset * geo.size.width * 2)
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .shadow(color: accent.opacity(0.4), radius: 12, x: 0, y: 6)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .onAppear {
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1
                }
            }
    }
}

// MARK: - Feature Briefing Sheet
struct FeatureBriefingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    @State private var showHelpCenter = false
    
    private var accentPrimary: Color {
        store.theme == "feminine" ? Color(hex: "#ec4899") : .indigo
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text("Deine Features")
                            .font(.title.weight(.bold))
                        Text("Alles, was du für deinen Abschluss brauchst.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 16) {
                        featureRow(icon: "chart.bar.fill", title: "Schnitt-Analyse", text: "Automatisches MSS-System für Bayern mit Block-Gewichtung und Rundung.", accent: .blue)
                        featureRow(icon: "graduationcap.fill", title: "Abitur-Rechner", text: "Vorschau auf dein Abitur/Fachabitur basierend auf aktuellen Noten.", accent: .purple)
                        featureRow(icon: "person.2.fill", title: "Klassen-Sync", text: "Tritt deiner Klasse bei, um Fächer, Hausaufgaben und Termine automatisch zu laden.", accent: .green)
                        featureRow(icon: "bell.badge.fill", title: "Prüfungs-Timer & Hausaufgaben", text: "Verpasse nie wieder eine Abgabe oder Klausur durch intelligente Benachrichtigungen.", accent: .red)
                        featureRow(icon: "cloud.fill", title: "Multi-Plattform Sync", text: "Deine Daten sind sicher in der Cloud und auf all deinen Geräten verfügbar.", accent: .orange)
                        featureRow(icon: "wifi.slash", title: "Offline-Modus", text: "Alle Funktionen klappen auch ohne Internet. Sync erfolgt automatisch.", accent: .secondary)
                        featureRow(icon: "lock.fill", title: "Privacy & Datenschutz", text: "Deine Noten gehören dir. Ende-zu-Ende Verschlüsselung für maximale Sicherheit.", accent: .indigo)
                    }
                    .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        Text("Noch Fragen?")
                            .font(.headline)
                        
                        Button {
                            showHelpCenter = true
                        } label: {
                            HStack {
                                Image(systemName: "questionmark.circle.fill")
                                Text("Zum Help Center")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(24)
                    .background(accentPrimary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showHelpCenter) {
                NavigationStack {
                    HelpCenterView()
                        .environmentObject(store)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showHelpCenter = false
                                } label: {
                                    ToolbarIcon(symbol: "xmark", showDot: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                }
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        }
    }
    

    private func featureRow(icon: String, title: String, text: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .font(.headline)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
}

// MARK: - Helper Views
struct SubjectCandidateRow: View {
    let name: String
    let onAdd: () -> Void
    var color: Color = .indigo
    
    var body: some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SubjectToggleRow: View {
    let name: String
    let isSelected: Bool
    var color: Color = .indigo
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isSelected ? color : Color.secondary.opacity(0.3))
                        .frame(width: 50, height: 30)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        .offset(x: isSelected ? 10 : -10)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .padding(12)
            .background(Color.formInputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.3) : color.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct UnifiedSubjectRow: View {
    let name: String
    let isFromPrevYear: Bool
    @Binding var hasSA: Bool
    var accent: Color = .indigo
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                
                if isFromPrevYear {
                    Text("Vom Vorjahr")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            // SA Toggle
            Button {
                hasSA.toggle()
            } label: {
                Text(hasSA ? "SA" : "Keine SA")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hasSA ? accent.opacity(0.15) : Color.secondary.opacity(0.1))
                    .foregroundStyle(hasSA ? accent : .secondary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            
            // Delete
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.formInputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.1), lineWidth: 1)
        )
    }
}
