import SwiftUI
import CryptoKit

private enum HalfYearDropOption: Equatable {
    case none
    case one
    case two

    var persistedValue: Int? {
        switch self {
        case .none: return nil
        case .one: return 1
        case .two: return 2
        }
    }

    static func fromPersisted(_ v: Int?) -> HalfYearDropOption {
        if v == 1 { return .one }
        if v == 2 { return .two }
        return .none
    }
}

struct FinalGradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var store: GradesStore
    @EnvironmentObject var biometricManager: BiometricAuthManager
    
    @State private var dropSelections: [String: HalfYearDropOption] = [:]
    @State private var maxDroppedHalfYears: Int = 3
    // State removed: finalGradeTapState, finalGradeToFixed
    @State private var showWhatIfGradesSheet: Bool = false
    @State private var showWhatIfSimulationMode: Bool = false
    @State private var showWhatIfExamSheet: Bool = false
    @State private var showSeminarSheet: Bool = false
    @State private var showStatusDetails: Bool = false
    @State private var detailHomework: Homework? = nil
    @State private var detailExam: Exam? = nil
    @State private var dailySummaryData: DailySummaryData? = nil
    @State private var previousYearSnapshot: SchoolYearSnapshot?
    @State private var isLoadingPreviousYear: Bool = false
    @State private var showNotifications: Bool = false
    @State private var showPDFSheet: Bool = false // PDF Export Sheet
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false
    @ObservedObject private var notificationInbox = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}
    
    // Interaction State
    @State private var showSwapOptions: Bool = false
    @State private var swapCandidate: SwapCandidate? = nil
    @State private var showManageDrops: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var useMSSInHero: Bool = false
    
    fileprivate struct SubjectHandle: Identifiable, Hashable {
        let id: String
        let schoolYearId: String?
        let gradeYear: Int?
        let isCurrentYear: Bool
        let subject: Subject
        let grades: [GradeWithId]
        
        init(schoolYearId: String?, gradeYear: Int?, isCurrentYear: Bool, subject: Subject, grades: [GradeWithId]) {
            let yearPart = schoolYearId ?? "current"
            self.id = "\(yearPart)::\(subject.name)"
            self.schoolYearId = schoolYearId
            self.gradeYear = gradeYear
            self.isCurrentYear = isCurrentYear
            self.subject = subject
            self.grades = grades
        }
        
        var isEligible: Bool {
            subject.name != "Fachreferat" && !subject.isElective
        }
        
        var yearLabel: String? {
            gradeYear.map { "\($0)." }
        }
        
        static func == (lhs: SubjectHandle, rhs: SubjectHandle) -> Bool {
            lhs.id == rhs.id
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }
    
    private struct SuggestionCandidate: Identifiable {
        let handle: SubjectHandle
        let halfYear: Int
        let average: Double
        
        var id: String { "\(handle.id)-\(halfYear)" }
    }
    
    private var currentSchoolYearId: String? {
        store.activeSchoolYearId
    }
    
    private var previousSchoolYearCandidateId: String? {
        previousSchoolYearId(from: currentSchoolYearId)
    }
    
    private var canUsePreviousYearSnapshot: Bool {
        guard schoolType == .fos else { return false }
        guard store.gradeYear == 12 else { return false }
        guard let candidate = previousSchoolYearCandidateId else { return false }
        guard let snapshot = previousYearSnapshot, snapshot.id == candidate else { return false }
        guard let prevGrade = snapshot.gradeYear, prevGrade == 11 else { return false }
        if let prevType = snapshot.schoolType {
            return prevType == .fos
        }
        return true
    }
    
    private var currentSubjectHandles: [SubjectHandle] {
        store.sortedSubjectsForDisplay().map { subject in
            let grades = store.gradesBySubject[subject.name] ?? []
            return SubjectHandle(
                schoolYearId: currentSchoolYearId,
                gradeYear: store.gradeYear,
                isCurrentYear: true,
                subject: subject,
                grades: grades
            )
        }
    }
    
    private var previousSubjectHandles: [SubjectHandle] {
        guard canUsePreviousYearSnapshot, let snapshot = previousYearSnapshot else { return [] }
        return store.sortedSubjectsForDisplay(snapshot.subjects).map { subject in
            let grades = snapshot.gradesBySubject[subject.name] ?? []
            return SubjectHandle(
                schoolYearId: snapshot.id,
                gradeYear: snapshot.gradeYear,
                isCurrentYear: false,
                subject: subject,
                grades: grades
            )
        }
    }
    
    private var allSubjectHandles: [SubjectHandle] {
        currentSubjectHandles + previousSubjectHandles
    }
    
    private var eligibleSubjectHandles: [SubjectHandle] {
        allSubjectHandles.filter { $0.isEligible }
    }
    
    private var hasFachreferat: Bool {
        store.fachreferat != nil
    }
    
    private var isFeminine: Bool { store.theme == "feminine" }
    private var isDark: Bool { store.darkMode }
    private var schoolType: SchoolType { store.schoolType }
    private var gradeYear: Int { store.gradeYear ?? 12 }
    private var hasExamSimulation: Bool { !store.simulatedExamPointsDict.isEmpty }
    private var hasSimulation: Bool { hasExamSimulation || !store.simulatedGrades.isEmpty || !store.excludedRealGradeIds.isEmpty }
    private var activeExamPointsBySubject: [String: Double?] {
        var merged = store.examPoints
        for (key, value) in store.simulatedExamPointsDict {
            merged[key] = value
        }
        return merged
    }
    
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
    
    private var deltaColor: Color {
        if useMSSInHero {
            guard let base = baselineMSSValue, let sim = simulatedMSSValue else { return .orange }
            // Higher points is better
            if sim > base { return .green }
            if sim < base { return .orange }
            return .secondary
        } else {
            guard let base = baselineFinalGradeValue, let sim = simulatedFinalGradeValue else { return .orange }
            // Lower grade is better (1.0 vs 2.0)
            if sim < base { return .green }
            if sim > base { return .orange }
            return .secondary
        }
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
    
    private var practicalPerformanceForDisplay: PracticalPerformance? {
        if canUsePreviousYearSnapshot, let snapshot = previousYearSnapshot, let practical = snapshot.practicalPerformance {
            return practical
        }
        return store.practicalPerformance
    }
    
    private var seminarPerformanceForDisplay: SeminarPerformance? {
        store.seminarPerformance
    }
    
    private var hasSeminarRequirement: Bool { gradeYear >= 13 }
    
    private var seminarFinalPoints: Double? {
        guard let sem = seminarPerformanceForDisplay else { return nil }
        let hasZero = [sem.individualPoints, sem.paperPoints, sem.presentationPoints].contains { $0 == 0 }
        if hasZero { return 0 }
        guard let individual = sem.individualPoints,
              let paper = sem.paperPoints,
              let presentation = sem.presentationPoints else { return nil }
        let raw = (individual + presentation + (2 * paper)) / 4.0
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        return max(0, min(15, rounded))
    }
    
    private var seminarMissingComponents: [String] {
        guard let sem = seminarPerformanceForDisplay else { return ["Teilnoten fehlen"] }
        var missing: [String] = []
        if sem.individualPoints == nil { missing.append("individuelle Leistung") }
        if sem.paperPoints == nil { missing.append("Seminararbeit") }
        if sem.presentationPoints == nil { missing.append("Präsentation") }
        return missing
    }
    
    private var seminarTopic: String? { seminarPerformanceForDisplay?.topic }
    private var seminarSubmissionDate: Date? { seminarPerformanceForDisplay?.submissionDate }
    private var seminarPresentationDate: Date? { seminarPerformanceForDisplay?.presentationDate }
    
    private var seminarPointsDouble: Double {
        guard let value = seminarFinalPoints, hasSeminarRequirement else { return 0 }
        return value * 2
    }
    
    private var examWeightFactor: Double {
        if schoolType == .fos {
            return gradeYear >= 13 ? 2 : 3
        }
        return 2
    }
    
    private var practicalGrades: [PracticalGradeEntry] {
        practicalPerformanceForDisplay?.grades ?? []
    }
    
    private var sortedPracticalGrades: [PracticalGradeEntry] {
        practicalGrades.sorted { lhs, rhs in
            if let lh = lhs.halfYear, let rh = rhs.halfYear, lh != rh {
                return lh < rh
            }
            if let _ = lhs.halfYear, rhs.halfYear == nil { return true }
            if lhs.halfYear == nil, let _ = rhs.halfYear { return false }
            return lhs.date < rhs.date
        }
    }
    
    private var animationsOn: Bool { store.animationsEnabled }
    
    private func triggerUpdate() {
        // Triggers a view update if needed, though EnvironmentObject usually handles this.
        // If specific logic is needed, add it here.
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .global).minY)
                    }
                    .frame(height: 0)
                    
                    contentStack
                        .padding(.top, 8)
                }
            }
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                self.scrollOffset = value
            }
            
            if scrollOffset < -100 {
                miniHero
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
                .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
                .navigationBarTitleDisplayMode(.inline)
                .modifier(FinalGradeSheets(
                    showNotifications: $showNotifications,
                    showWhatIfGradesSheet: $showWhatIfGradesSheet,
                    showWhatIfExamSheet: $showWhatIfExamSheet,
                    showSeminarSheet: $showSeminarSheet,
                    showStatusDetails: $showStatusDetails,
                    showManageDrops: $showManageDrops,
                    showPDFSheet: $showPDFSheet,
                    showSwapOptions: $showSwapOptions,
                    showWhatIfSimulationMode: $showWhatIfSimulationMode,
                    detailHomework: $detailHomework,
                    detailExam: $detailExam,
                    dailySummaryData: $dailySummaryData,
                    store: store,
                    notificationInbox: notificationInbox,
                    examSubjectHandles: examSubjectHandles,
                    baselineFinalGradeText: baselineFinalGradeText,
                    baselineFinalGradeValue: baselineFinalGradeValue,
                    finalGradeColor: finalGradeColor,
                    statusDetailSheet: statusDetailSheet,
                    manageDropsSheet: manageDropsSheet,
                    droppedHalfYears: droppedHalfYears,
                    swapCandidate: swapCandidate,
                    handleNotificationSelection: handleNotificationSelection,
                    syncDropSelectionsFromData: syncDropSelectionsFromData,
                    recomputeMaxDroppedHalfYears: recomputeMaxDroppedHalfYears,
                    loadPreviousYearSnapshotIfNeeded: loadPreviousYearSnapshotIfNeeded,
                    previousYearSnapshot: previousYearSnapshot,
                    triggerUpdate: triggerUpdate,
                    makeFobosoSummary: { self.makeFobosoSummary(examPoints: $0) },
                    finalGradeText: { self.finalGradeText(for: $0) },
                    mergedExamPoints: { self.mergedExamPoints(base: $0, overrides: $1) }
                ))
                .onChange(of: store.encryptionKey == nil) { _, _ in
                    Task {
                        await loadPreviousYearSnapshotIfNeeded()
                    }
                }
                .onAppear {
                    syncDropSelectionsFromData()
                    recomputeMaxDroppedHalfYears()
                }
                .onChange(of: store.subjects) { _, _ in
                    syncDropSelectionsFromData()
                    recomputeMaxDroppedHalfYears()
                }
                .onChange(of: store.gradeYear) { _, _ in
                    recomputeMaxDroppedHalfYears()
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        HStack(spacing: 0) {
                            Button {
                                showNotifications = true
                            } label: {
                                ToolbarIcon(
                                    symbol: "bell",
                                    showDot: notificationInbox.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !launchOfferPurchased)
                                )
                            }
                            .accessibilityLabel("Benachrichtigungen")
                            
                            Button {
                                handlePrivacyToggle()
                            } label: {
                                ToolbarIcon(
                                    symbol: store.isPrivacyModeActive ? "eye.slash.fill" : "eye.fill",
                                    showDot: false
                                )
                            }
                            .accessibilityLabel(store.isPrivacyModeActive ? "Privatsphäre-Modus deaktivieren" : "Privatsphäre-Modus aktivieren")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            NavigationLink(destination: CalendarPageView().environmentObject(store)) {
                                ToolbarIcon(symbol: "calendar", showDot: false)
                            }
                            .accessibilityLabel("Kalender öffnen")
                            
                            Button {
                                onOpenCreationMenu()
                            } label: {
                                ToolbarIcon(symbol: "plus", showDot: false)
                            }
                            .accessibilityLabel("Neu hinzufügen")
                        }
                    }
                }
        }
        
        // MARK: - UI Pieces
        
        private var miniHero: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(finalGradeText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .privacyBlur()
                    Text("\(formatAverage(fobosoSummary.averageAfterDrops)) MSS • \(selectedDropCount)/\(maxDroppedHalfYears) gestrichen")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .privacyBlur()
                }
                
                Spacer()
                
                GradeProgressBar(value: simulatedFinalGradeValue ?? 4.0)
                    .frame(width: 100, height: 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.top, 8)
            .padding(.horizontal, 16)
        }
        
        @ViewBuilder
        private var contentStack: some View {
            VStack(spacing: 16) {
                loadingSection
                heroHeader
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.03, offset: 12)
                heroChips
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.08, offset: 12)
                statusCard
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 12)
                whatIfCard
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.10, offset: 12)
                HelpCenterLink(
                    title: "Hilfe zur Abschlussnote",
                    subtitle: "Regeln, Gewichtung & Beispiele nach BayFOBOSO",
                    section: .pass,
                    accent: .indigo
                )
                .padding(.horizontal, 16)
                .softFadeIn(enabled: animationsOn, delay: 0.12, offset: 12)
                
                exportButton
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.13, offset: 12)
                
                abiturOverviewCard
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.14, offset: 12)
                if hasSeminarRequirement || seminarPerformanceForDisplay != nil {
                    seminarCard
                        .padding(.horizontal, 16)
                        .softFadeIn(enabled: animationsOn, delay: 0.16, offset: 12)
                }
                if schoolType == .fos && gradeYear <= 12 {
                    practicalPerformanceCard
                        .padding(.horizontal, 16)
                        .softFadeIn(enabled: animationsOn, delay: 0.18, offset: 12)
                }
                if fobosoSummary.maxPoints > 0 {
                    pointsCard
                        .padding(.horizontal, 16)
                        .softFadeIn(enabled: animationsOn, delay: 0.22, offset: 12)
                }
                subjectCountRow
                    .padding(.horizontal)
                    .softFadeIn(enabled: animationsOn, delay: 0.24, offset: 12)
                droppedHalfYearsCard
                    .padding(.horizontal, 16)
                    .softFadeIn(enabled: animationsOn, delay: 0.27, offset: 12)
                if maxDroppedHalfYears > 0 && limitReached {
                    Text("Du hast bereits die maximal erlaubte Anzahl an gestrichenen Halbjahren ausgewählt. Entferne zuerst eine Auswahl, um ein weiteres Halbjahr zu streichen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                Text("Hinweis: Das Streichen von Halbjahren in dieser Ansicht dient nur dir selbst als Orientierung und Merkhilfe. Es werden keine Daten an deine Schule oder andere Dritte übermittelt. Offizielle Entscheidungen über gestrichene Halbjahren musst du gegebenenfalls separat bei deiner Schule beantragen bzw. mitteilen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
        }
        
        @ViewBuilder
        private var loadingSection: some View {
            if store.isLoading {
                VStack(spacing: 8) {
                    ProgressView(value: store.progress, total: 100)
                    Text(store.loadingLabel).font(.footnote)
                }
                .padding(.horizontal)
            } else if isLoadingPreviousYear {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Vorjahr wird geladen …")
                        .font(.footnote)
                }
                .padding(.horizontal)
            }
        }
        
        @ViewBuilder
        private var heroHeader: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Abschlussnote")
                    .font(.title2.weight(.bold))
                HStack(spacing: 6) {
                    if hasSimulation {
                        HStack(spacing: 4) {
                            Text("Simulation aktiv")
                            if !store.excludedRealGradeIds.isEmpty {
                                Text("•")
                                Text("\(store.excludedRealGradeIds.count) ausgeklammert")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.pink)
                        .clipShape(Capsule())
                    } else {
                        Text("Stand heute")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let year = store.activeSchoolYearId {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(year)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        @ViewBuilder
        private var heroChips: some View {
            HStack(spacing: 0) {
                // Left: Valid Grade (Schnitt)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(useMSSInHero ? "Schnitt (Pkt)" : "Schnitt")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Toggle("", isOn: $useMSSInHero)
                                .labelsHidden()
                                .scaleEffect(0.7)
                                .frame(width: 40, height: 20)
                        }
                        
                        ZStack {
                            Text(useMSSInHero ? heroMSSValue : finalGradeText)
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(store.isPrivacyModeActive ? .primary : finalGradeColor(finalGradeValueForColor))
                                .contentTransition(.numericText())
                                .privacyBlur()
                                .monospacedDigit()
                            
                            if hasSimulation {
                                Image(systemName: "wand.and.stars")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.pink)
                                    .offset(x: 40, y: -12)
                            }
                        }
                        
                        if !store.excludedRealGradeIds.isEmpty {
                            Text("\(store.excludedRealGradeIds.count) ausgeklammert")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.1))
                                .clipShape(Capsule())
                                .offset(y: -4)
                        }
                    }
                    .frame(minWidth: 120, alignment: .leading)
                
                Divider()
                    .frame(height: 44)
                    .padding(.horizontal, 20)
                
                // Right: Rating and MSS
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bewertung")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    
                    if let val = finalGradeValueForColor {
                        Text(finalGradeDescriptor(val))
                            .font(.headline) // Make this prominent but smaller than the grade
                            .lineLimit(1)
                            .privacyBlur()
                        
                        // MSS in smaller text below
                        Text("\(heroMSSValue) Notenpunkte")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .privacyBlur()
                    } else {
                        Text("-")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(GradeCardStyle.surface(colorScheme: scheme, theme: store.theme, accent: .indigo))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        hasSimulation ? Color.pink.opacity(0.5) : GradeCardStyle.borderStrokeColor(colorScheme: scheme, accent: Color.indigo),
                        lineWidth: hasSimulation ? 2 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity(scheme == .dark ? 0.45 : 0.08),
                radius: 8,
                x: 0,
                y: 4
            )
            // Add padding to container so the shadow isn't clipped by scrollview if tight
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        
        
        /// MSS value (0-15 points average) for hero display
        private var heroMSSValue: String {
            guard let avg = fobosoSummary.averageAfterDrops else { return "-" }
            return store.formatMSS(avg)
        }
        
        /// MSS text for display under grade
        private var heroMSSText: String {
            guard let avg = fobosoSummary.averageAfterDrops else { return "MSS: -" }
            // Use raw value for precision, let store.formatMSS handle formatting/rounding preference
            return "MSS: \(store.formatMSS(avg))"
        }
        
        
        @ViewBuilder
        private var whatIfCard: some View {
            SettingsCard(
                title: "Was-wäre-wenn",
                subtitle: "Abschlussnote & Abiturnoten simulieren",
                systemImage: "wand.and.stars",
                accent: .pink
            ) {
                if examSubjectHandles.isEmpty {
                    Text("Lege zuerst Abiturfächer an, um Prüfungsnoten simulieren zu können.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            StatChip(title: "Aktuell", value: baselineFinalGradeText, accent: .indigo)
                            StatChip(title: "Simulation", value: finalGradeText, accent: .pink)
                            StatChip(
                                title: "Δ",
                                value: formatFinalGradeDelta(
                                    base: useMSSInHero ? baselineMSSValue : baselineFinalGradeValue,
                                    simulated: useMSSInHero ? simulatedMSSValue : simulatedFinalGradeValue
                                ),
                                accent: deltaColor
                            )
                        }


                        
                        HStack(spacing: 12) {
                            Button {
                                showWhatIfSimulationMode = true
                            } label: {
                                Label("Noten sim.", systemImage: "plus.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .indigo))
                            
                            Button {
                                showWhatIfGradesSheet = true
                            } label: {
                                Label("Abitur sim.", systemImage: "wand.and.stars")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .pink))
                        }
                        
                        if hasSimulation {
                            Button {
                                store.clearGradeSimulations()
                                store.clearExamSimulations()
                            } label: {
                                Label("Simulation zurücksetzen", systemImage: "arrow.counterclockwise")
                                    .font(.caption.weight(.semibold))
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.pink.opacity(0.10))
                            )
                        }
                    }
                }
            }
        }
        
        @ViewBuilder
        private var statusCard: some View {
            let status = statusDisplay
            let statusColor = store.isPrivacyModeActive ? .primary : status.color
            
            SettingsCard(
                title: "Prüfungsstatus",
                subtitle: nil,
                systemImage: "checkmark.seal.fill",
                accent: statusColor
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(status.text)
                            .font(.headline)
                        Spacer()
                        Text(status.text == "Bestanden" ? "✔︎" : status.text == "Nicht bestanden" ? "✖︎" : "…")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(statusColor.opacity(0.18))
                            .foregroundStyle(store.isPrivacyModeActive ? .primary : (status.color == .secondary ? Color.primary : status.color))
                            .clipShape(Capsule())
                    }
                    
                    switch passFailStatus {
                    case .failed:
                        VStack(alignment: .leading, spacing: 6) {
                            if failedByHalfYearTooFew {
                                failureReasonRow("zu wenige Halbjahre eingebracht")
                            }
                            if failedByHalfYearTooMany {
                                failureReasonRow("zu viele Halbjahre eingebracht")
                            }
                            if failedByExamGrade {
                                failureReasonRow("benötigter Schnitt nicht erreicht")
                            }
                            if failedByFinalGrade {
                                failureReasonRow("benötigte Abschlussnote nicht erreicht")
                            }
                            if failedByMissingFachreferat {
                                failureReasonRow("Fachreferat Note nicht eingetragen")
                            }
                            if failedByMissingPracticalPerformance {
                                failureReasonRow("Praktikums-Jahresleistung fehlt")
                            }
                            if failedByMissingSeminar {
                                failureReasonRow("Seminarfach fehlt")
                            }
                            if failedBySeminarZero {
                                failureReasonRow("Seminarfach mit 0 Punkten")
                            }
                            if failedBySubjectPoints {
                                failureReasonRow("benötigte Punktzahl nicht erreicht")
                            }
                        }
                        Button {
                            showStatusDetails = true
                        } label: {
                            Text("Details anzeigen")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    case .open:
                        Text("Noch offene Daten. Trage alle Prüfungsnoten und Halbjahre ein.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .passed:
                        Text("Herzlichen Glückwunsch! 🎉")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        
        @ViewBuilder
        private var exportButton: some View {
            Button {
                showPDFSheet = true
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.blue.opacity(scheme == .dark ? 0.22 : 0.14))
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.blue.opacity(scheme == .dark ? 0.30 : 0.20), lineWidth: 1)
                            )
                        Image(systemName: "doc.text.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zeugnis exportieren")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Dein Notenblatt als PDF speichern oder teilen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(GradeCardStyle.surface(colorScheme: scheme, theme: store.theme, accent: .blue))
                .overlay(GradeCardStyle.border(colorScheme: scheme, accent: .blue))
                .shadow(
                    color: Color.black.opacity(scheme == .dark ? 0.40 : 0.06),
                    radius: 4,
                    x: 0,
                    y: 2
                )
            }
            .buttonStyle(.plain)
        }
        
        @ViewBuilder
        private var abiturOverviewCard: some View {
            SettingsCard(
                title: "Abiturnoten",
                subtitle: nil,
                systemImage: "graduationcap.fill",
                accent: .mint
            ) {
                SettingsSectionBox {
                    if examSubjectFinals.isEmpty {
                        Text("Trage deine Abiturnoten im Abitur-Bereich ein, um hier eine Übersicht zu sehen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(examSubjectFinals, id: \.handle.id) { entry in
                                HStack {
                                    Text(entry.handle.subject.name)
                                    Spacer()
                                    let color = store.isPrivacyModeActive ? .primary : gradeColor(entry.final)
                                    Text(formatAverage(entry.final))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(color.opacity(0.15))
                                        .foregroundStyle(color)
                                        .clipShape(Capsule())
                                        .privacyBlur()
                                }
                            }
                            if let avg = abiturExamAverage {
                                Divider().padding(.vertical, 4)
                                HStack {
                                    Text("Durchschnitt")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    let color = store.isPrivacyModeActive ? .primary : gradeColor(avg)
                                    Text(formatAverage(avg))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(color.opacity(0.15))
                                        .foregroundStyle(color)
                                        .clipShape(Capsule())
                                        .privacyBlur()
                                }
                            }
                        }
                    }
                }
            }
        }
        
        @ViewBuilder
        private var seminarCard: some View {
            SettingsCard(
                title: "Seminarfach",
                subtitle: "Seminararbeit zählt doppelt.",
                systemImage: "doc.text.magnifyingglass",
                accent: .indigo
            ) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Gesamt (2×)")
                                .font(.headline)
                            Spacer()
                            Text(seminarFinalPoints != nil ? formatAverage(seminarFinalPoints) : "-")
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(gradeColor(seminarFinalPoints).opacity(0.15))
                                .foregroundStyle(gradeColor(seminarFinalPoints))
                                .clipShape(Capsule())
                                .privacyBlur()
                        }
                        
                        if let topic = seminarTopic, !topic.isEmpty {
                            Text("Thema: \(topic)")
                                .font(.subheadline)
                        }
                        
                        VStack(spacing: 8) {
                            seminarComponentRow(title: "Individuelle Leistung", value: seminarPerformanceForDisplay?.individualPoints)
                            seminarComponentRow(title: "Seminararbeit (2×)", value: seminarPerformanceForDisplay?.paperPoints)
                            seminarComponentRow(title: "Präsentation & Diskussion", value: seminarPerformanceForDisplay?.presentationPoints)
                        }
                        
                        if let sub = seminarSubmissionDate {
                            Text("Abgabe: \(formatDateShort(sub)) (Dienstag der 2. Unterrichtswoche).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let pres = seminarPresentationDate {
                            Text("Präsentation/Diskussion: \(formatDateShort(pres)).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if hasSeminarRequirement {
                            Text("0 Punkte in einem Teil ⇒ Seminar gesamt 0 Punkte (FOBOSO 3.1) und keine Zulassung zur Abschlussprüfung; zählt in 13. doppelt ins Abitur.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Trage hier schon während der Blockphase deine Teilnoten und Termine ein.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button {
                            showSeminarSheet = true
                        } label: {
                            Text(seminarPerformanceForDisplay == nil ? "Seminarfach pflegen" : "Seminarfach bearbeiten")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        
        @ViewBuilder
        private var pointsCard: some View {
            SettingsCard(
                title: "Erreichte Punkte",
                subtitle: nil,
                systemImage: "chart.bar.fill",
                accent: .orange
            ) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(round(fobosoSummary.totalPoints))) / \(fobosoSummary.maxPoints)")
                            .font(.title3).bold()
                            .privacyBlur()
                        Text("Prüfungen (\(Int(examWeightFactor))× Gewichtung): \(Int(round(fobosoSummary.examPointsDouble))) Punkte")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .privacyBlur()
                        Text("Halbjahresergebnisse: \(Int(round(fobosoSummary.halfYearPoints))) Punkte (\(halfYearSummary.count) HJE).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .privacyBlur()
                        if practicalYearSummary.count > 0 {
                            Text("Praktikum 11.: \(Int(round(practicalYearSummary.totalPoints))) Punkte (\(practicalYearSummary.count) HJL).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .privacyBlur()
                        }
                        if hasSeminarRequirement {
                            let pointsText = seminarFinalPoints != nil ? "\(Int(round(seminarPointsDouble))) Punkte" : "noch offen"
                            Text("Seminarfach (2×): \(pointsText).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .privacyBlur()
                        }
                        if fachreferatHalfYearSummary.count > 0 {
                            Text("Fachreferat: \(Int(round(fachreferatHalfYearSummary.totalPoints))) Punkte (\(fachreferatHalfYearSummary.count) HJE).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .privacyBlur()
                        }
                    }
                }
            }
        }
        
        @ViewBuilder
        private var subjectCountRow: some View {
            SettingsCard(
                title: "Kurzüberblick",
                subtitle: nil,
                systemImage: "info.circle",
                accent: .cyan
            ) {
                HStack(spacing: 10) {
                    StatChip(title: "Fächer", value: "\(eligibleSubjectHandles.count)", accent: .cyan)
                    let halfYearText: String = maxDroppedHalfYears > 0 ? "\(selectedDropCount) / \(maxDroppedHalfYears)" : "\(selectedDropCount)"
                    StatChip(title: "Halbjahre", value: halfYearText, accent: .orange)
                }
            }
        }
        
        @ViewBuilder
        private var droppedHalfYearsCard: some View {
            SettingsCard(
                title: "Streichungen Optimieren",
                subtitle: nil,
                systemImage: "scissors",
                accent: .indigo
            ) {
                VStack(spacing: 16) {
                    // Section: Limit & Status
                    if maxDroppedHalfYears > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Verfügbare Streichungen")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(selectedDropCount) von \(maxDroppedHalfYears) genutzt")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(limitReached ? .orange : .primary)
                            }
                            Spacer()
                            if limitReached {
                                Text("Limit erreicht")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    } else {
                        Text("In dieser Ausbildungsrichtung/Jahrgangsstufe sind keine Streichungen vorgesehen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if maxDroppedHalfYears > 0 {
                        Divider()
                        
                        // Section: Active Drops
                        if !droppedHalfYears.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Aktuell gestrichen")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                
                                ForEach(droppedHalfYears, id: \.handle.id) { entry in
                                    activeDropRow(handle: entry.handle, halfYear: entry.halfYear)
                                }
                            }
                            Divider()
                        }
                        
                        // Section: Recommendations
                        if !limitReached {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Vorschläge")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                    Spacer()
                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                        .foregroundStyle(.indigo)
                                }
                                
                                if smartCandidates.isEmpty {
                                    Text("Keine sinnvollen Streichungen verfügbar.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    // Show top 3 candidates
                                    ForEach(smartCandidates.prefix(3)) { candidate in
                                        recommendationRow(candidate: candidate)
                                    }
                                }
                            }
                            Divider()
                        }
                        
                        // Footer Action
                        Button {
                            showManageDrops = true
                        } label: {
                            HStack {
                                Text("Manuelle Auswahl")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        
        private func activeDropRow(handle: SubjectHandle, halfYear: Int) -> some View {
            HStack {
                Image(systemName: subjectIcon(for: handle.subject.name))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(handle.subject.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(halfYear). Halbjahr")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                let avg = calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: halfYear)
                Text(formatAverage(avg))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .privacyBlur()
                    .strikethrough()
                
                Button {
                    toggleSmartDrop(handle: handle, halfYear: halfYear)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.8))
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        
        private func recommendationRow(candidate: SuggestionCandidate) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.handle.subject.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(candidate.halfYear). Halbjahr")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Impact badge
                if let imp = calculateImpact(for: candidate.handle, halfYear: candidate.halfYear), imp > 0.005 {
                    let badgeColor = store.isPrivacyModeActive ? .primary : Color.green
                    Text("+\(String(format: "%.\(store.mssDecimalPrecision)f", imp))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.1))
                        .clipShape(Capsule())
                        .privacyBlur()
                }
                
                let gradeColorVal = store.isPrivacyModeActive ? .primary : gradeColor(candidate.average)
                Text(formatAverage(candidate.average))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(gradeColorVal)
                    .privacyBlur()
                    .frame(minWidth: 40, alignment: .trailing)
                
                Button {
                    toggleSmartDrop(handle: candidate.handle, halfYear: candidate.halfYear)
                } label: {
                    Image(systemName: "arrow.down.to.line.circle.fill") // Icon for "Drop"
                        .foregroundStyle(.indigo)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(8)
            .background(Color.indigo.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        
        
        
        
        /// Returns an appropriate SF Symbol for a subject name
        private func subjectIcon(for subjectName: String) -> String {
            let name = subjectName.lowercased()
            if name.contains("deutsch") { return "textformat.abc" }
            if name.contains("englisch") || name.contains("english") { return "globe" }
            if name.contains("mathe") || name.contains("math") { return "function" }
            if name.contains("physik") || name.contains("physics") { return "atom" }
            if name.contains("chemie") || name.contains("chemistry") { return "flask" }
            if name.contains("biologie") || name.contains("biology") { return "leaf" }
            if name.contains("informatik") || name.contains("computer") { return "desktopcomputer" }
            if name.contains("geschichte") || name.contains("history") { return "clock.arrow.circlepath" }
            if name.contains("geographie") || name.contains("erdkunde") || name.contains("geography") { return "globe.europe.africa" }
            if name.contains("kunst") || name.contains("art") { return "paintpalette" }
            if name.contains("musik") || name.contains("music") { return "music.note" }
            if name.contains("sport") { return "figure.run" }
            if name.contains("religion") || name.contains("ethik") { return "sparkles" }
            if name.contains("wirtschaft") || name.contains("bwl") || name.contains("vwl") { return "chart.line.uptrend.xyaxis" }
            if name.contains("recht") || name.contains("law") { return "scale.3d" }
            if name.contains("sozialkunde") || name.contains("politik") { return "person.3" }
            if name.contains("französisch") || name.contains("french") { return "globe.europe.africa" }
            if name.contains("spanisch") || name.contains("spanish") { return "globe.americas" }
            if name.contains("latein") || name.contains("latin") { return "scroll" }
            if name.contains("technik") || name.contains("technologie") { return "gearshape.2" }
            if name.contains("gesundheit") || name.contains("health") { return "heart" }
            if name.contains("pädagogik") || name.contains("psychologie") { return "brain.head.profile" }
            return "book.closed"
        }
        
        @ViewBuilder
        private var practicalPerformanceCard: some View {
            let subtitleText: String? = {
                if canUsePreviousYearSnapshot, let snapshot = previousYearSnapshot {
                    return "Daten aus dem Schuljahr \(snapshot.id)."
                }
                return nil
            }()
            
            SettingsCard(
                title: "Fachpraktische Ausbildung",
                subtitle: subtitleText,
                systemImage: "wrench.and.screwdriver.fill",
                accent: .teal
            ) {
                SettingsSectionBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if let avg = practicalAverageDisplay {
                            HStack {
                                Text("Durchschnitt")
                                    .font(.headline)
                                Spacer()
                                let color = store.isPrivacyModeActive ? .primary : gradeColor(avg)
                                Text(formatAverage(avg))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(color.opacity(0.15))
                                    .foregroundStyle(color)
                                    .clipShape(Capsule())
                                    .privacyBlur()
                            }
                        }
                        
                        if sortedPracticalGrades.isEmpty {
                            Text("Erfasste Praktikumsnoten werden hier angezeigt. Nutze den Praktikumsbereich, um sie zu pflegen.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(sortedPracticalGrades) { entry in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(practicalLabel(for: entry))
                                                .font(.subheadline)
                                            if let company = entry.company, !company.isEmpty {
                                                Text(company)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if let note = entry.note, !note.isEmpty {
                                                Text(note)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        let color = store.isPrivacyModeActive ? .primary : gradeColor(entry.grade)
                                        Text(formatAverage(entry.grade))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(color.opacity(0.15))
                                            .foregroundStyle(color)
                                            .clipShape(Capsule())
                                            .privacyBlur()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        @ViewBuilder
        private func failureReasonRow(_ text: String) -> some View {
            let color = store.isPrivacyModeActive ? .primary : Color(hex: "#f87171")
            HStack(alignment: .top, spacing: 6) {
                Text("x")
                    .font(.caption)
                    .foregroundStyle(color)
                    .padding(.top, 1)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(color)
            }
        }
        
        // MARK: - Helpers (Port von React)
        
        private func calculateGradeWeightForSubject(_ subjectType: Int, _ grade: GradeWithId) -> Double {
            store.effectiveGradeWeight(subjectType: subjectType, rawWeight: grade.weight)
        }
        
        private func calculateHalfYearAverageForSubject(_ subject: Subject, grades: [GradeWithId], halfYear: Int) -> Double? {
            store.bestAvailableHalfYearValue(subject: subject, halfYear: halfYear, grades: grades)
        }
        
        private func subjectAverageFor(handle: SubjectHandle) -> Double? {
            let grades = filteredGradesByHandle[handle.id] ?? []
            guard !grades.isEmpty else { return nil }
            var total = 0.0
            var totalWeight = 0.0
            for g in grades {
                let w = calculateGradeWeightForSubject(handle.subject.type, g)
                total += g.grade * w
                totalWeight += w
            }
            guard totalWeight > 0 else { return nil }
            return total / totalWeight
        }
        
        private func formatAverage(_ value: Double?) -> String {
            guard let v = value else { return "-" }
            return String(format: "%.\(store.mssDecimalPrecision)f", v)
        }
        
        private func formatDateShort(_ date: Date?) -> String {
            guard let date else { return "-" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
        
        private func examPoint(for subjectName: String, points: [String: Double?]? = nil) -> Double? {
            let source = points ?? activeExamPointsBySubject
            return source[subjectName] ?? nil
        }
        
        private func mergedExamPoints(base: [String: Double?], overrides: [String: Double]) -> [String: Double?] {
            var merged = base
            for (key, value) in overrides {
                merged[key] = value
            }
            return merged
        }
        
        @ViewBuilder
        private func seminarComponentRow(title: String, value: Double?) -> some View {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                let color = store.isPrivacyModeActive ? .primary : gradeColor(value)
                Text(value != nil ? "\(Int(value!)) Punkte" : "fehlt")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
                    .privacyBlur()
            }
        }
        
        /// Calculates the overall average MSS (0-15 points) using the same calculation as HomeView
        /// This uses raw half-year values without rounding for consistency
        private func overallAverageMSS(examPoints: [String: Double?], isBaseline: Bool = false) -> Double? {
            // Filter out excluded real grades when not baseline
            let subjects = store.subjects
            
            return GradeCalculationService.calculateOverallAverage(
                subjects: subjects,
                halfYearValueProvider: { [self] subject, hy in
                    // Use half year values from grades, respecting exclusions when not baseline
                    if isBaseline {
                        return store.bestAvailableHalfYearValue(subject: subject, halfYear: hy)
                    } else {
                        // Get grades excluding simulated exclusions
                        let allGrades = store.gradesBySubject[subject.name] ?? []
                        let filtered = allGrades.filter { !store.excludedRealGradeIds.contains($0.id) }
                        let ghosts = store.simulatedGrades.filter { $0.subjectName == subject.name }
                        
                        let combined: [any GradeProtocol] = filtered + ghosts
                        return GradeCalculationService.calculateHalfYearAverage(
                            grades: combined,
                            subject: subject,
                            halfYear: hy,
                            effectiveGradeWeight: { [store] in store.effectiveGradeWeight(subjectType: $0, rawWeight: $1) }
                        )
                    }
                },
                droppedHalfYearProvider: { subject in
                    subject.droppedHalfYear
                },
                halfYearFilter: nil,
                fachreferat: store.fachreferat,
                seminar: store.seminarPerformance,
                practical: store.practicalPerformance,
                examPoints: examPoints,
                schoolType: store.schoolType,
                gradeYear: store.gradeYear ?? 12,
                useRawValues: true
            )
        }
        
        /// Converts MSS (0-15) to grade (1-6) using the standard formula: Grade = (17 - Points) / 3
        private func mssToGrade(_ mss: Double?) -> Double? {
            guard let p = mss else { return nil }
            return (17.0 - p) / 3.0
        }
        
        private var baselineMSSValue: Double? {
            baselineFobosoSummary.averageAfterDrops
        }

        private var simulatedMSSValue: Double? {
            fobosoSummary.averageAfterDrops
        }

        private var finalGradeText: String {
            finalGradeText(for: activeExamPointsBySubject, isBaseline: false)
        }
        
        private var baselineFinalGradeText: String {
            finalGradeText(for: store.examPoints, isBaseline: true)
        }
        
        private var baselineFinalGradeValue: Double? {
            baselineFobosoSummary.gradeRaw
        }
        
        private var simulatedFinalGradeValue: Double? {
            fobosoSummary.gradeRaw
        }
        
        private var finalGradeValueForColor: Double? {
            simulatedFinalGradeValue
        }
        
        private func finalGradeRawValue(using points: [String: Double?]) -> Double? {
            mssToGrade(overallAverageMSS(examPoints: points, isBaseline: false))
        }
        
        private func formatFinalGradeDelta(base: Double?, simulated: Double?) -> String {
            guard let base, let simulated else { return "-" }
            let delta = simulated - base
            if abs(delta) < 0.005 { return "0.00" }
            // For grades, negative delta is improvement.
            // But mathematically: New - Old. 1.8 - 2.0 = -0.2.
            // Display standard numeric delta.
            let prefix = delta > 0 ? "+" : ""
            return "\(prefix)\(String(format: "%.\(store.mssDecimalPrecision)f", delta))"
        }
        
        private func gradeColor(_ value: Double?) -> Color {
            guard let v = value else { return .secondary }
            if v >= 7 { return .green }
            if v >= 4 { return .orange }
            return .red
        }
        
        private func finalGradeColor(_ value: Double?) -> Color {
            guard let v = value else { return .secondary }
            if v <= 3.4 { return .green }
            if v <= 4.4 { return .orange }
            return .red
        }
        
        /// Converts 0-15 points average to 1-6 grade using the same formula as HomeView
        /// Formula: Grade = (17 - Points) / 3
        private func pointsToGrade(_ points: Double?) -> Double? {
            guard let p = points else { return nil }
            let grade = (17.0 - p) / 3.0
            return max(1.0, min(6.0, grade))
        }
        
        private func pointsToGradeText(_ points: Double?, decimals: Int) -> String {
            guard let g = pointsToGrade(points) else { return "-" }
            return String(format: "%.\(decimals)f", g)
        }
        
        private func finalGradeDescriptor(_ value: Double?) -> String {
            guard let v = value else { return "Noch keine Note berechnet" }
            if v == 1 { return "Exzellenter Schnitt" }
            if v <= 1.4 { return "Sehr starker Schnitt" }
            if v <= 2.4 { return "Guter Schnitt" }
            if v <= 3.4 { return "Befriedigender Schnitt" }
            if v <= 4.0 { return "Bestanden" }
            return "Nicht bestanden"
        }

        private func finalGradeValue(using points: [String: Double?]) -> Double? {
            let summary = makeFobosoSummary(examPoints: points)
            if summary.maxPoints > 0 {
                // Priority: use raw grade for precision
                if let gRaw = summary.gradeRaw { return gRaw }
                
                // Fallback to official rounded grade
                if let g = summary.grade { return g }
                
                // Last fallback: calculate average grade from total weighted points
                let averagePoints = (summary.totalPoints * 15.0) / Double(summary.maxPoints)
                return pointsToGrade(averagePoints)
            }
            // Last resort fallback
            return abiturFinalAverage(points: points) ?? gradesOnlyFinalAverage
        }
            
        private func finalGradeText(for points: [String: Double?], isBaseline: Bool = false) -> String {
            let summary = makeFobosoSummary(examPoints: points, isBaseline: isBaseline)
            let decimals = 2
            
            if useMSSInHero {
                if let avg = summary.averageAfterDrops {
                    return String(format: "%.\(decimals)f", avg)
                }
            } else {
                if let grade = summary.gradeRaw {
                    return String(format: "%.\(decimals)f", grade)
                }
            }
            return "--"
        }
            
        private func roundedExamPoints(_ value: Double?) -> Double? {
                guard let v = value else { return nil }
                return v.rounded(.toNearestOrAwayFromZero)
            }
            
            // MARK: - State Berechnungen (entspricht useMemo in React)
            
        private var selectedDropCount: Int {
                eligibleSubjectHandles.reduce(0) { sum, handle in
                    let value = dropSelections[handle.id] ?? .none
                    return sum + ((value == .one || value == .two) ? 1 : 0)
                }
            }
            
        private var filteredGradesByHandle: [String: [GradeWithId]] {
                var result: [String: [GradeWithId]] = [:]
                for handle in allSubjectHandles {
                    let dropOption = dropSelections[handle.id] ?? .none
                    let filtered = handle.grades.filter { g in
                        if dropOption == .one, g.halfYear == 1 { return false }
                        if dropOption == .two, g.halfYear == 2 { return false }
                        return true
                    }
                    result[handle.id] = filtered
                }
                return result
            }
            
        private var droppedHalfYears: [(handle: SubjectHandle, halfYear: Int)] {
                eligibleSubjectHandles.compactMap { handle in
                    let opt = dropSelections[handle.id] ?? .none
                    switch opt {
                    case .one: return (handle, 1)
                    case .two: return (handle, 2)
                    default: return nil
                    }
                }
            }
            
        private var examSubjectHandles: [SubjectHandle] {
                eligibleSubjectHandles.filter { $0.isCurrentYear && ($0.subject.examSubject == true) }
            }
            
        private var sortedSubjectHandles: [SubjectHandle] {
                if eligibleSubjectHandles.isEmpty { return [] }
                
                // Use base average (unfiltered by drops) for stable sorting
                func getSubjectBaseAverageForSort(_ handle: SubjectHandle) -> Double? {
                    let grades = handle.grades
                    guard !grades.isEmpty else { return nil }
                    var total = 0.0, totalWeight = 0.0
                    for g in grades {
                        let w = calculateGradeWeightForSubject(handle.subject.type, g)
                        total += g.grade * w
                        totalWeight += w
                    }
                    guard totalWeight > 0 else { return nil }
                    return total / totalWeight
                }
                
                switch store.subjectSortMode {
                case .name:
                    return eligibleSubjectHandles.sorted {
                        if $0.subject.name.caseInsensitiveCompare($1.subject.name) == .orderedSame {
                            return ($0.gradeYear ?? 0) < ($1.gradeYear ?? 0)
                        }
                        return $0.subject.name.lowercased().localizedCompare($1.subject.name.lowercased()) == .orderedAscending
                    }
                case .name_desc:
                    return eligibleSubjectHandles.sorted {
                        if $0.subject.name.caseInsensitiveCompare($1.subject.name) == .orderedSame {
                            return ($0.gradeYear ?? 0) > ($1.gradeYear ?? 0)
                        }
                        return $0.subject.name.lowercased().localizedCompare($1.subject.name.lowercased()) == .orderedDescending
                    }
                case .average:
                    return eligibleSubjectHandles.sorted { a, b in
                        let a1 = getSubjectBaseAverageForSort(a)
                        let b1 = getSubjectBaseAverageForSort(b)
                        switch (a1, b1) {
                        case (nil, nil):
                            if a.subject.name.caseInsensitiveCompare(b.subject.name) == .orderedSame {
                                return (a.gradeYear ?? 0) < (b.gradeYear ?? 0)
                            }
                            return a.subject.name.lowercased().localizedCompare(b.subject.name.lowercased()) == .orderedAscending
                        case (nil, _):
                            return false
                        case (_, nil):
                            return true
                        case let (aa?, bb?):
                            if aa == bb {
                                if a.subject.name.caseInsensitiveCompare(b.subject.name) == .orderedSame {
                                    return (a.gradeYear ?? 0) < (b.gradeYear ?? 0)
                                }
                                return a.subject.name.lowercased().localizedCompare(b.subject.name.lowercased()) == .orderedAscending
                            }
                            return aa > bb
                        }
                    }
                case .average_worst:
                    return eligibleSubjectHandles.sorted { a, b in
                        let a1 = getSubjectBaseAverageForSort(a)
                        let b1 = getSubjectBaseAverageForSort(b)
                        switch (a1, b1) {
                        case (nil, nil):
                            if a.subject.name.caseInsensitiveCompare(b.subject.name) == .orderedSame {
                                return (a.gradeYear ?? 0) < (b.gradeYear ?? 0)
                            }
                            return a.subject.name.lowercased().localizedCompare(b.subject.name.lowercased()) == .orderedAscending
                        case (nil, _):
                            return true
                        case (_, nil):
                            return false
                        case let (aa?, bb?):
                            if aa == bb {
                                if a.subject.name.caseInsensitiveCompare(b.subject.name) == .orderedSame {
                                    return (a.gradeYear ?? 0) < (b.gradeYear ?? 0)
                                }
                                return a.subject.name.lowercased().localizedCompare(b.subject.name.lowercased()) == .orderedAscending
                            }
                            return aa < bb
                        }
                    }
                case .custom:
                    if store.subjectSortOrder.isEmpty {
                        return eligibleSubjectHandles.sorted {
                            if $0.subject.name.caseInsensitiveCompare($1.subject.name) == .orderedSame {
                                return ($0.gradeYear ?? 0) < ($1.gradeYear ?? 0)
                            }
                            return $0.subject.name.lowercased().localizedCompare($1.subject.name.lowercased()) == .orderedAscending
                        }
                    }
                    let orderMap = Dictionary(uniqueKeysWithValues: store.subjectSortOrder.enumerated().map { ($1, $0) })
                    return eligibleSubjectHandles.sorted { a, b in
                        let ia = orderMap[a.subject.name]
                        let ib = orderMap[b.subject.name]
                        switch (ia, ib) {
                        case (nil, nil):
                            if a.subject.name.caseInsensitiveCompare(b.subject.name) == .orderedSame {
                                return (a.gradeYear ?? 0) < (b.gradeYear ?? 0)
                            }
                            return a.subject.name.lowercased().localizedCompare(b.subject.name.lowercased()) == .orderedAscending
                        case (nil, _):
                            return false
                        case (_, nil):
                            return true
                        default:
                            if ia == ib {
                                return (a.gradeYear ?? 0) < (b.gradeYear ?? 0)
                            }
                            return ia! < ib!
                        }
                    }
                }
            }
            
        private var gradesOnlyFinalAverage: Double? {
                guard !eligibleSubjectHandles.isEmpty else { return nil }
                var total = 0.0, totalWeight = 0.0
                for handle in eligibleSubjectHandles {
                    let grades = filteredGradesByHandle[handle.id] ?? []
                    for g in grades {
                        let w = calculateGradeWeightForSubject(handle.subject.type, g)
                        total += g.grade * w
                        totalWeight += w
                    }
                }
                guard totalWeight > 0 else { return nil }
                return total / totalWeight
            }
            
        private func abiturFinalAverage(points: [String: Double?]? = nil) -> Double? {
                let es = examSubjectHandles
                guard !es.isEmpty else { return nil }
                var subjectFinals: [Double] = []
                let examWeight = examWeightFactor
                for handle in es {
                    let examPoints = examPoint(for: handle.subject.name, points: points)
                    guard let rawExam = examPoints else { continue }
                    let ep = roundedExamPoints(rawExam) ?? rawExam
                    
                    let dropOption = dropSelections[handle.id] ?? .none
                    let isHalfYear1Dropped = (dropOption == .one)
                    let isHalfYear2Dropped = (dropOption == .two)
                    
                    let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: 1)
                    let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: 2)
                    
                    var components: [(value: Double, weight: Double)] = []
                    if let f = first { components.append((f, 1)) }
                    if let sec = second { components.append((sec, 1)) }
                    components.append((ep, examWeight))
                    
                    let totalWeight = components.reduce(0) { $0 + $1.weight }
                    guard totalWeight > 0 else { continue }
                    let totalValue = components.reduce(0) { $0 + $1.value * $1.weight }
                    subjectFinals.append(totalValue / totalWeight)
                }
                
                guard !subjectFinals.isEmpty else { return nil }
                let sum = subjectFinals.reduce(0, +)
                return sum / Double(subjectFinals.count)
            }
            
        private var abiturFinalAverageValue: Double? {
                abiturFinalAverage(points: nil)
            }
            
        private var finalAverage: Double? {
                abiturFinalAverageValue ?? gradesOnlyFinalAverage
            }
            
        private var statusDetailReasons: [String] {
                var reasons: [String] = []
                if failedByHalfYearTooFew {
                    let missing = requiredHalfYearCount - halfYearSummary.count
                    reasons.append("Es fehlen noch \(missing) von \(requiredHalfYearCount) erforderlichen HJE.")
                }
                if failedByHalfYearTooMany {
                    let extra = halfYearSummary.count - requiredHalfYearCount
                    reasons.append("Du hast \(extra) HJE zu viel eingebracht (maximal \(requiredHalfYearCount) erlaubt).")
                }
                if failedByMissingFachreferat {
                    reasons.append("Die Fachreferat-Note fehlt.")
                }
                if failedByMissingPracticalPerformance {
                    reasons.append("Die beiden Praktikumsnoten (11.) fehlen für die FOS.")
                }
                if failedByMissingSeminar {
                    reasons.append("Seminarfach-Teilnoten fehlen.")
                }
                if failedBySeminarZero {
                    reasons.append("Seminarfach aktuell 0 Punkte (0 Punkte in einer Teilleistung).")
                }
                if failedBySubjectPoints {
                    let weak = weakExamCounts
                    if weak.weighted > 2 {
                        reasons.append("Zu viele Prüfungen unter 4 Punkten (0 zählt doppelt, maximal zwei erlaubt).")
                    } else {
                        let threshold = weak.weighted == 1 ? pointsThresholds.oneWeak : pointsThresholds.twoWeak
                        let missing = max(0, threshold - fobosoSummary.totalPoints)
                        reasons.append("Gesamtpunktzahl zu niedrig (\(Int(fobosoSummary.totalPoints))/\(Int(threshold)); es fehlen ca. \(Int(ceil(missing))) Punkte).")
                    }
                }
                if failedByForbiddenZeroExam {
                    reasons.append("0-Punkte-Prüfung ist in der 13. Jahrgangsstufe nicht zulässig.")
                }
                if failedByExamGrade, let avg = examAveragePoints {
                    reasons.append("Prüfungsdurchschnitt zu niedrig (aktuell \(formatAverage(avg)) statt mindestens 4,0).")
                }
                if failedByFinalGrade, let g = fobosoSummary.grade {
                    reasons.append("Abschlussnote zu schlecht (aktuell \(String(format: "%.1f", g)), benötigt höchstens 4,0).")
                }
                return reasons
            }
            
        private var statusDetailNextSteps: [String] {
                var tips: [String] = []
                if failedByHalfYearTooFew {
                    tips.append("Weitere Halbjahre einbringen, bis \(requiredHalfYearCount) erreicht sind.")
                }
                if failedByHalfYearTooMany {
                    tips.append("Halbjahre streichen, bis nur \(requiredHalfYearCount) HJE übrig bleiben.")
                }
                if failedByMissingFachreferat {
                    tips.append("Fachreferat-Note eintragen.")
                }
                if failedByMissingPracticalPerformance {
                    tips.append("Beide Praktikumsnoten (11.) eintragen.")
                }
                if failedByMissingSeminar {
                    tips.append("Seminarfach eintragen (individuelle Leistung, Seminararbeit, Präsentation).")
                }
                if failedBySeminarZero {
                    tips.append("0 Punkte im Seminar vermeiden – Teilleistungen nachbessern.")
                }
                if failedBySubjectPoints {
                    if weakExamCounts.weighted > 2 {
                        tips.append("Maximal zwei Prüfungen dürfen unter 4 Punkten liegen (0 zählt doppelt) – schwächste Prüfungen verbessern.")
                    } else {
                        tips.append("Punkte erhöhen: bessere Halbjahresnoten oder Prüfungen helfen, den Schwellenwert zu erreichen.")
                    }
                }
                if failedByForbiddenZeroExam {
                    tips.append("Keine Prüfung mit 0 Punkten zulässig – prüfe deine eingetragenen Prüfungsnoten.")
                }
                if failedByExamGrade {
                    tips.append("Prüfungsnoten auf mindestens 4,0 im Schnitt bringen.")
                }
                if failedByFinalGrade {
                    tips.append("Gesamt-Notenschnitt auf 4,0 oder besser senken.")
                }
                return tips
            }
            
        private var halfYearSummary: (totalPoints: Double, count: Int) {
                var totalPoints = 0.0
                var count = 0
                for handle in eligibleSubjectHandles {
                    let dropOption = dropSelections[handle.id] ?? .none
                    let isHalfYear1Dropped = (dropOption == .one)
                    let isHalfYear2Dropped = (dropOption == .two)
                    let first = isHalfYear1Dropped ? nil : calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: 1)
                    let second = isHalfYear2Dropped ? nil : calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: 2)
                    if let f = first { totalPoints += f; count += 1 }
                    if let s = second { totalPoints += s; count += 1 }
                }
                return (totalPoints, count)
            }
            
        private var fachreferatHalfYearSummary: (totalPoints: Double, count: Int) {
                guard let fr = store.fachreferat else { return (0, 0) }
                return (fr.grade, 1)
            }
            
        private var practicalYearSummary: (totalPoints: Double, count: Int) {
                let gy = store.gradeYear ?? 12
                guard schoolType == .fos, gy <= 12 else { return (0, 0) }
                let grades = sortedPracticalGrades
                guard !grades.isEmpty else { return (0, 0) }
                let limited = grades.prefix(2)
                let total = limited.reduce(0.0) { $0 + $1.grade }
                return (total, limited.count)
            }
            
        private var practicalAverageDisplay: Double? {
                guard !sortedPracticalGrades.isEmpty else { return nil }
                let total = sortedPracticalGrades.reduce(0.0) { $0 + $1.grade }
                return total / Double(sortedPracticalGrades.count)
            }
            
            private func makeFobosoSummary(examPoints: [String: Double?]? = nil, isBaseline: Bool = false) -> (examCount: Int,
                                                                                     halfYearCount: Int,
                                                                                     examPointsDouble: Double,
                                                                                     halfYearPoints: Double,
                                                                                     seminarPointsDouble: Double,
                                                                                     totalPoints: Double,
                                                                                     totalPointsRaw: Double,
                                                                                     maxPoints: Int,
                                                                                     grade: Double?,
                                                                                     gradeRaw: Double?,
                                                                                     averageAfterDrops: Double?) {
                let subjects = eligibleSubjectHandles.map { handle in
                    let real = handle.grades
                    let filteredReal = isBaseline ? real : real.filter { !store.excludedRealGradeIds.contains($0.id) }
                    let ghosts = isBaseline ? [] : store.simulatedGrades.filter { $0.subjectName == handle.subject.name }
                    let combined: [GradeProtocol] = filteredReal + ghosts
                    
                    return GradeCalculationService.SubjectData(id: handle.id, subject: handle.subject, grades: combined, isEligible: handle.isEligible)
                }
                
                var dropMap: [String: Int?] = [:]
                for h in allSubjectHandles {
                    dropMap[h.id] = dropSelections[h.id]?.persistedValue
                }
                
                let res = GradeCalculationService.makeFobosoSummary(
                    schoolType: schoolType,
                    gradeYear: gradeYear,
                    subjects: subjects,
                    examPoints: examPoints ?? activeExamPointsBySubject,
                    dropSelections: dropMap,
                    fachreferat: store.fachreferat,
                    practicalPerformance: practicalPerformanceForDisplay,
                    seminarPerformance: seminarPerformanceForDisplay,
                    effectiveGradeWeight: { type, weight in store.effectiveGradeWeight(subjectType: type, rawWeight: weight) }
                )
                
                let avgAfterDrops = res.maxPoints > 0 ? (res.totalPointsRaw * 15.0) / Double(res.maxPoints) : nil
                return (res.examCount, res.halfYearCount, res.examPointsDouble, res.halfYearPoints, res.seminarPointsDouble, res.totalPoints, res.totalPointsRaw, res.maxPoints, res.grade, res.gradeRaw, avgAfterDrops)
            }
            
            
            private var fobosoSummary: (examCount: Int,
                                        halfYearCount: Int,
                                        examPointsDouble: Double,
                                        halfYearPoints: Double,
                                        seminarPointsDouble: Double,
                                        totalPoints: Double,
                                        totalPointsRaw: Double,
                                        maxPoints: Int,
                                        grade: Double?,
                                        gradeRaw: Double?,
                                        averageAfterDrops: Double?) {
                makeFobosoSummary(examPoints: nil)
            }
            
            private var baselineFobosoSummary: (examCount: Int,
                                                halfYearCount: Int,
                                                examPointsDouble: Double,
                                                halfYearPoints: Double,
                                                seminarPointsDouble: Double,
                                                totalPoints: Double,
                                                totalPointsRaw: Double,
                                                maxPoints: Int,
                                                grade: Double?,
                                                gradeRaw: Double?,
                                                averageAfterDrops: Double?) {
                makeFobosoSummary(examPoints: store.examPoints, isBaseline: true)
            }
            
            private func calculateImpact(for handle: SubjectHandle, halfYear: Int) -> Double? {
                let key = handle.id
                let currentDrop = dropSelections[key] ?? .none
                
                // If already dropped, we simulate UNDROPPING it
                if (currentDrop == .one && halfYear == 1) || (currentDrop == .two && halfYear == 2) {
                    // Logic for un-dropping
                    var simulatedDrops = dropSelections
                    simulatedDrops[key] = nil // or .none, but dictionary removal is cleaner
                    
                    // Recalculate average
                    let simulatedAvg = calculateSimulatedAverage(with: simulatedDrops)
                    guard let sim = simulatedAvg, let base = fobosoSummary.averageAfterDrops else { return nil }
                    return sim - base
                }
                
                // If NOT dropped, we simulate DROPPING it
                var simulatedDrops = dropSelections
                let baselineAvg = fobosoSummary.averageAfterDrops ?? 0
                
                if maxDroppedHalfYears > 0 && selectedDropCount >= maxDroppedHalfYears {
                    // Limit reached: We must simulate a SWAP.
                    // Find the active drop with the HIGHEST points (the "weakest" drop to keep).
                    var bestDropToRemove: (handle: SubjectHandle, halfYear: Int, points: Double)? = nil
                    
                    for drop in droppedHalfYears {
                        let points = calculateHalfYearAverageForSubject(drop.handle.subject, grades: drop.handle.grades, halfYear: drop.halfYear) ?? 15.0
                        if bestDropToRemove == nil || points > bestDropToRemove!.points {
                            bestDropToRemove = (drop.handle, drop.halfYear, points)
                        }
                    }
                    
                    if let toRemove = bestDropToRemove {
                        // remove the old one
                        simulatedDrops[toRemove.handle.id] = nil
                        // add the new one
                        simulatedDrops[key] = (halfYear == 1 ? .one : .two)
                    } else {
                        // Should not happen if count >= max > 0, but fallback: just add high
                        simulatedDrops[key] = (halfYear == 1 ? .one : .two)
                    }
                } else {
                    // Limit not reached, just add
                    simulatedDrops[key] = (halfYear == 1 ? .one : .two)
                }
                
                let simulatedAvg = calculateSimulatedAverage(with: simulatedDrops)
                guard let sim = simulatedAvg else { return nil }
                return sim - baselineAvg
            }
            
            private func calculateSimulatedAverage(with drops: [String: HalfYearDropOption]) -> Double? {
                // 1. Prepare subjects
                let subjects = eligibleSubjectHandles.map {
                    GradeCalculationService.SubjectData(id: $0.id, subject: $0.subject, grades: $0.grades, isEligible: $0.isEligible)
                }
                
                // 2. Prepare drop map from the SIMULATED drops
                var dropMap: [String: Int?] = [:]
                for h in allSubjectHandles {
                    dropMap[h.id] = drops[h.id]?.persistedValue
                }
                
                // 3. Run full calculation
                let res = GradeCalculationService.makeFobosoSummary(
                    schoolType: schoolType,
                    gradeYear: gradeYear,
                    subjects: subjects,
                    examPoints: store.examPoints, // Assume exam points stay constant for drop impact
                    dropSelections: dropMap,
                    fachreferat: store.fachreferat,
                    practicalPerformance: practicalPerformanceForDisplay,
                    seminarPerformance: seminarPerformanceForDisplay,
                    effectiveGradeWeight: { type, weight in store.effectiveGradeWeight(subjectType: type, rawWeight: weight) }
                )
                
                // 4. Extract Average
                guard res.maxPoints > 0 else { return nil }
                return (res.totalPoints * 15.0) / Double(res.maxPoints)
            }
            
            private func hasAllExamPoints(using points: [String: Double?]? = nil) -> Bool {
                let es = examSubjectHandles
                guard es.count >= requiredExamCount else { return false }
                return es.allSatisfy { examPoint(for: $0.subject.name, points: points) != nil }
            }
            
            private var hasAllExamPointsActive: Bool { hasAllExamPoints(using: nil) }
            private var hasAllExamPoints: Bool { hasAllExamPointsActive }
            
            private func examAveragePoints(using points: [String: Double?]? = nil) -> Double? {
                guard hasAllExamPoints(using: points) else { return nil }
                let es = examSubjectHandles
                guard !es.isEmpty else { return nil }
                var total = 0.0
                var count = 0
                for handle in es {
                    if let v = examPoint(for: handle.subject.name, points: points) {
                        total += v
                        count += 1
                    }
                }
                guard count > 0 else { return nil }
                return total / Double(count)
            }
            
            private var examAveragePoints: Double? {
                examAveragePoints(using: nil)
            }
            
            private var weakExamCounts: (weighted: Int, raw: Int, zeros: Int) {
                guard hasAllExamPointsActive else { return (0, 0, 0) }
                var weighted = 0
                var raw = 0
                var zeros = 0
                for entry in examSubjectFinals {
                    guard let v = entry.final else { continue }
                    if v < 4 {
                        raw += 1
                        if v <= 0 {
                            weighted += 2
                            zeros += 1
                        } else {
                            weighted += 1
                        }
                    }
                }
                return (weighted, raw, zeros)
            }
            
            private var examResultAtLeastFour: Bool? {
                guard let avg = examAveragePoints else { return nil }
                return avg >= 4
            }
            
            private var finalGradeAtLeastFour: Bool? {
                guard hasAllExamPoints, fobosoSummary.maxPoints > 0, let g = fobosoSummary.grade else { return nil }
                return g <= 4
            }
            
            private var pointsThresholds: (oneWeak: Double, twoWeak: Double) {
                if schoolType == .fos && gradeYear <= 12 {
                    return (200, 240)
                }
                return (130, 156)
            }
            
            private var requiredExamCount: Int { 4 }
            
            private var requiredHalfYearCount: Int {
                let gy = store.gradeYear ?? 12
                if schoolType == .fos {
                    return gy >= 13 ? 16 : 25
                }
                // BOS
                return gy >= 13 ? 16 : 17
            }
            
            private var failedByHalfYearTooFew: Bool {
                halfYearSummary.count < requiredHalfYearCount
            }
            private var failedByHalfYearTooMany: Bool {
                halfYearSummary.count > requiredHalfYearCount
            }
            private var failedByHalfYearCount: Bool {
                failedByHalfYearTooFew || failedByHalfYearTooMany
            }
            private var failedByMissingFachreferat: Bool {
                gradeYear == 12 && !hasFachreferat
            }
            private var failedByMissingPracticalPerformance: Bool {
                schoolType == .fos && gradeYear <= 12 && practicalYearSummary.count < 2
            }
            private var failedByMissingSeminar: Bool {
                hasSeminarRequirement && seminarFinalPoints == nil
            }
            private var failedBySeminarZero: Bool {
                hasSeminarRequirement && seminarFinalPoints == 0
            }
            private var failedBySubjectPoints: Bool {
                guard hasAllExamPoints else { return false }
                let weak = weakExamCounts
                if weak.weighted > 2 { return true }
                if weak.weighted == 0 { return false }
                let threshold = weak.weighted == 1 ? pointsThresholds.oneWeak : pointsThresholds.twoWeak
                return fobosoSummary.totalPoints < threshold
            }
            private var failedByForbiddenZeroExam: Bool {
                gradeYear >= 13 && weakExamCounts.zeros > 0
            }
            private var failedByExamGrade: Bool {
                hasAllExamPoints && (examResultAtLeastFour == false)
            }
            private var failedByFinalGrade: Bool {
                hasAllExamPoints && (finalGradeAtLeastFour == false)
            }
            
            private enum PassFailStatus { case open, passed, failed }
            private var passFailStatus: PassFailStatus {
                let isFailed = failedByHalfYearCount || failedByMissingFachreferat || failedByMissingPracticalPerformance || failedByMissingSeminar || failedBySeminarZero || failedBySubjectPoints || failedByExamGrade || failedByFinalGrade || failedByForbiddenZeroExam
                let isPassed = !isFailed && hasAllExamPoints && halfYearSummary.count == requiredHalfYearCount && examResultAtLeastFour == true && finalGradeAtLeastFour == true && !failedByMissingPracticalPerformance && !failedByMissingSeminar && !failedBySeminarZero
                if isFailed { return .failed }
                if isPassed { return .passed }
                return .open
            }
            
            private var statusDisplay: (text: String, color: Color) {
                switch passFailStatus {
                case .passed:
                    return ("Bestanden", .green)
                case .failed:
                    return ("Nicht bestanden", .red)
                case .open:
                    return ("Offen", .secondary)
                }
            }
            
            private func examSubjectsWithPoints(using points: [String: Double?]? = nil) -> [SubjectHandle] {
                examSubjectHandles.filter { examPoint(for: $0.subject.name, points: points) != nil }
            }
            
            private var examSubjectsWithPoints: [SubjectHandle] {
                examSubjectsWithPoints(using: nil)
            }
            
            private func examSubjectFinals(using points: [String: Double?]? = nil) -> [(handle: SubjectHandle, final: Double?)] {
                examSubjectsWithPoints(using: points).map { handle in
                    let ep = examPoint(for: handle.subject.name, points: points)
                    return (handle, ep)
                }
            }
            
            private var examSubjectFinals: [(handle: SubjectHandle, final: Double?)] {
                examSubjectFinals(using: nil)
            }
            
            private var abiturExamAverage: Double? {
                let finals = examSubjectFinals.compactMap { $0.final }
                guard !finals.isEmpty else { return nil }
                let sum = finals.reduce(0, +)
                return sum / Double(finals.count)
            }
            
            private var limitReached: Bool {
                maxDroppedHalfYears > 0 && selectedDropCount >= maxDroppedHalfYears
            }
            
            private var availableHalfYearCount: Int {
                eligibleSubjectHandles.count * 2
            }
            
            private func syncDropSelectionsFromData() {
                var next: [String: HalfYearDropOption] = [:]
                for handle in allSubjectHandles {
                    next[handle.id] = HalfYearDropOption.fromPersisted(handle.subject.droppedHalfYear)
                }
                dropSelections = next
            }
            
            private func previousSchoolYearId(from id: String?) -> String? {
                guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), id.count >= 7 else { return nil }
                guard let startYear = Int(id.prefix(4)) else { return nil }
                let previousStart = startYear - 1
                let previousEnd = startYear
                let endSuffix = String(format: "%02d", previousEnd % 100)
                return "\(previousStart)-\(endSuffix)"
            }
            
            private func loadPreviousYearSnapshotIfNeeded() async {
                guard schoolType == .fos else {
                    await MainActor.run {
                        previousYearSnapshot = nil
                        isLoadingPreviousYear = false
                        recomputeMaxDroppedHalfYears()
                    }
                    return
                }
                guard store.gradeYear == 12 else {
                    await MainActor.run {
                        previousYearSnapshot = nil
                        isLoadingPreviousYear = false
                        recomputeMaxDroppedHalfYears()
                    }
                    return
                }
                guard let candidate = previousSchoolYearCandidateId, store.schoolYears.contains(candidate) else {
                    await MainActor.run {
                        previousYearSnapshot = nil
                        isLoadingPreviousYear = false
                        recomputeMaxDroppedHalfYears()
                    }
                    return
                }
                if let snapshot = previousYearSnapshot, snapshot.id == candidate, snapshot.gradeYear == 11 {
                    return
                }
                if let cached = store.cachedSchoolYearSnapshot(for: candidate), let grade = cached.gradeYear, grade == 11 {
                    await MainActor.run {
                        previousYearSnapshot = cached
                        isLoadingPreviousYear = false
                        syncDropSelectionsFromData()
                        recomputeMaxDroppedHalfYears()
                    }
                    return
                }
                await MainActor.run { isLoadingPreviousYear = true }
                let snapshot = await store.loadSchoolYearSnapshot(schoolYearId: candidate)
                await MainActor.run {
                    if let snapshot, let grade = snapshot.gradeYear, grade == 11 {
                        previousYearSnapshot = snapshot
                    } else {
                        previousYearSnapshot = nil
                    }
                    isLoadingPreviousYear = false
                    syncDropSelectionsFromData()
                    recomputeMaxDroppedHalfYears()
                }
            }
            
            // toggleFinalGradeToFixed removed
            
            // MARK: - Actions
            
            private func toggleSmartDrop(handle: SubjectHandle, halfYear: Int) {
                let key = handle.id
                let currentOption = dropSelections[key] ?? .none
                
                // Is this specific half-year currently dropped?
                let isCurrentlyDropped = (currentOption == .one && halfYear == 1) || (currentOption == .two && halfYear == 2)
                
                if isCurrentlyDropped {
                    // Un-drop it
                    Task {
                        await store.updateDroppedHalfYear(
                            subjectName: handle.subject.name,
                            value: nil,
                            inSchoolYear: handle.isCurrentYear ? nil : handle.schoolYearId
                        )
                        syncDropSelectionsFromData()
                        recomputeMaxDroppedHalfYears()
                    }
                } else {
                    // Try to drop it
                    if maxDroppedHalfYears > 0 && selectedDropCount >= maxDroppedHalfYears {
                        // Limit reached: We need to swap!
                        // We want to remove the currently dropped half-year that has the HIGHEST points (since dropping high points is inefficient).
                        // Or more simply: replace the "weakest" drop.
                        // A "weak" drop is one where we are dropping a high grade (e.g. 10 points), instead of a low grade (0 points).
                        // So we find the drop with the MAX points and un-drop it.
                        
                        var bestDropToRemove: (handle: SubjectHandle, halfYear: Int, points: Double)? = nil
                        
                        for drop in droppedHalfYears {
                            let points = calculateHalfYearAverageForSubject(drop.handle.subject, grades: drop.handle.grades, halfYear: drop.halfYear) ?? 15.0
                            if bestDropToRemove == nil || points > bestDropToRemove!.points {
                                bestDropToRemove = (drop.handle, drop.halfYear, points)
                            }
                        }
                        
                        if let toRemove = bestDropToRemove {
                            Task {
                                // 1. Un-drop the inefficient one
                                await store.updateDroppedHalfYear(
                                    subjectName: toRemove.handle.subject.name,
                                    value: nil,
                                    inSchoolYear: toRemove.handle.isCurrentYear ? nil : toRemove.handle.schoolYearId
                                )
                                // 2. Drop the new target
                                await store.updateDroppedHalfYear(
                                    subjectName: handle.subject.name,
                                    value: halfYear,
                                    inSchoolYear: handle.isCurrentYear ? nil : handle.schoolYearId
                                )
                                syncDropSelectionsFromData()
                                recomputeMaxDroppedHalfYears()
                            }
                        }
                    } else {
                        // Limit not reached, just add it
                        Task {
                            await store.updateDroppedHalfYear(
                                subjectName: handle.subject.name,
                                value: halfYear, // We assume if it wasn't dropped, we drop just this half-year. Logic needs to respect existing .one/.two state if we supported dropping BOTH, but here we can only drop max 1 per subject usually?
                                // Wait, dropSelections stores .one OR .two. Can a subject have BOTH dropped?
                                // The enum is `case one, two, none`. So a subject can only have ONE half-year dropped at a time in this data model?
                                // If so, `value: halfYear` works perfectly.
                                inSchoolYear: handle.isCurrentYear ? nil : handle.schoolYearId
                            )
                            syncDropSelectionsFromData()
                            recomputeMaxDroppedHalfYears()
                        }
                    }
                }
            }
            
            private func recomputeMaxDroppedHalfYears() {
                let computed = max(0, availableHalfYearCount - requiredHalfYearCount)
                maxDroppedHalfYears = computed
            }
            
            private func practicalLabel(for entry: PracticalGradeEntry) -> String {
                if let hy = entry.halfYear {
                    return hy == 1 ? "1. Praktikum" : "2. Praktikum"
                }
                return "Praktikum"
            }
            
            private var statusDetailSheet: some View {
                NavigationStack {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            SettingsCard(
                                title: "Status-Details",
                                subtitle: "Prüfungsstatus verstehen",
                                systemImage: "exclamationmark.triangle.fill",
                                accent: .orange
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Warum nicht bestanden?")
                                        .font(.headline)
                                    if statusDetailReasons.isEmpty {
                                        Text("Keine Details verfügbar.")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            ForEach(statusDetailReasons, id: \.self) { reason in
                                                HStack(alignment: .top, spacing: 8) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(store.isPrivacyModeActive ? Color.primary : Color.red)
                                                    Text(reason)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .privacyBlur()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if !statusDetailNextSteps.isEmpty {
                                SettingsCard(
                                    title: "Nächste Schritte",
                                    subtitle: "So kannst du nachbessern",
                                    systemImage: "lightbulb.max.fill",
                                    accent: .mint
                                ) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(statusDetailNextSteps, id: \.self) { tip in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "arrow.forward.circle.fill")
                                                    .foregroundStyle(.mint)
                                                Text(tip)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .background(
                        ThemedBackground(
                            isDark: store.darkMode,
                            isFeminine: store.theme == "feminine",
                            intensity: store.themeBackgroundIntensity
                        )
                    )
                    .sheetNavigationTitle("Status-Details")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showStatusDetails = false
                            } label: {
                                Image(systemName: "chevron.down")
                                    .imageScale(.medium)
                                    .foregroundStyle(Color.primary)
                            }
                            .accessibilityLabel("Schließen")
                        }
                    }
                }
            }
            
            private var manageDropsSheet: some View {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Active Drops Section
                            if !droppedHalfYears.isEmpty {
                                SettingsCard(
                                    title: "Aktuell gestrichen",
                                    subtitle: "\(selectedDropCount) von \(maxDroppedHalfYears) ausgewählt",
                                    systemImage: "scissors",
                                    accent: .indigo
                                ) {
                                    enableDropLimitWarningIfNeeded
                                    
                                    VStack(spacing: 12) {
                                        ForEach(droppedHalfYears, id: \.handle.id) { entry in
                                            dropCandidateRow(handle: entry.handle, halfYear: entry.halfYear, isSelected: true)
                                        }
                                    }
                                }
                            } else {
                                SettingsCard(
                                    title: "Aktuell gestrichen",
                                    subtitle: "0 von \(maxDroppedHalfYears) ausgewählt",
                                    systemImage: "scissors",
                                    accent: .indigo
                                ) {
                                    Text("Du hast noch keine Halbjahre gestrichen.")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            
                            // Available Section
                            SettingsCard(
                                title: "Verfügbare Halbjahre",
                                subtitle: "Tippe zum Streichen",
                                systemImage: "list.bullet.clipboard",
                                accent: .secondary
                            ) {
                                if smartCandidates.isEmpty {
                                    Text("Keine streichbaren Halbjahre gefunden.")
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                        .padding(.vertical, 8)
                                } else {
                                    VStack(spacing: 12) {
                                        ForEach(smartCandidates) { candidate in
                                            dropCandidateRow(handle: candidate.handle, halfYear: candidate.halfYear, isSelected: false)
                                        }
                                    }
                                }
                            }
                            
                            Text("Es werden nur Halbjahre mit eingetragenen Noten angezeigt.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                        }
                        .padding(16)
                    }
                    .background(
                        ThemedBackground(
                            isDark: store.darkMode,
                            isFeminine: store.theme == "feminine",
                            intensity: store.themeBackgroundIntensity
                        )
                    )
                    .navigationTitle("Halbjahre streichen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showManageDrops = false
                            } label: {
                                Image(systemName: "xmark")
                                    .imageScale(.medium)
                                    .foregroundStyle(Color.primary)
                            }
                            .accessibilityLabel("Schließen")
                        }
                    }
                }
            }
            
            @ViewBuilder
            private var enableDropLimitWarningIfNeeded: some View {
                if selectedDropCount >= maxDroppedHalfYears {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Limit erreicht. Wenn du ein weiteres Halbjahr wählst, wird automatisch der schlechteste Drop ersetzt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 8)
                }
            }
            
            @ViewBuilder
            private func dropCandidateRow(handle: SubjectHandle, halfYear: Int, isSelected: Bool) -> some View {
                let average = calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: halfYear) ?? 0
                Button {
                    toggleSmartDrop(handle: handle, halfYear: halfYear)
                } label: {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(gradeColor(average).opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: subjectIcon(for: handle.subject.name))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(gradeColor(average))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(handle.subject.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(halfYear). Halbjahr")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if !isSelected {
                            if let imp = calculateImpact(for: handle, halfYear: halfYear), abs(imp) > 0.005 {
                                let isPositive = imp > 0
                                Text((isPositive ? "+" : "") + String(format: "%.\(store.mssDecimalPrecision)f", imp))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(isPositive ? .green : .red)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((isPositive ? Color.green : Color.red).opacity(0.1))
                                    .clipShape(Capsule())
                                    .privacyBlur()
                            }
                        }
                        
                        Text(formatAverage(average))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(gradeColor(average))
                            .privacyBlur()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.title3)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                                .font(.title3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            private var smartCandidates: [SuggestionCandidate] {
                let all = eligibleSubjectHandles.flatMap { handle -> [SuggestionCandidate] in
                    var candidates: [SuggestionCandidate] = []
                    if let h1 = calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: 1) {
                        candidates.append(SuggestionCandidate(handle: handle, halfYear: 1, average: h1))
                    }
                    if let h2 = calculateHalfYearAverageForSubject(handle.subject, grades: handle.grades, halfYear: 2) {
                        candidates.append(SuggestionCandidate(handle: handle, halfYear: 2, average: h2))
                    }
                    return candidates
                }
                
                let filtered = all.filter { candidate in
                    let key = candidate.handle.id
                    let drop = dropSelections[key] ?? .none
                    // Exclude already dropped ones from "Available" list
                    return !(drop == .one && candidate.halfYear == 1) && !(drop == .two && candidate.halfYear == 2)
                }
                
                // Sort by points ascending (worst grades first) to help user find what to drop
                return Array(filtered.sorted { $0.average < $1.average })
            }
            
        private func handlePrivacyToggle() {
            if store.isPrivacyModeActive {
                if biometricManager.isEnabledForActiveUser {
                    Task {
                        let success = await biometricManager.authenticate(reason: "Noten anzeigen")
                        if success {
                            store.updatePrivacyMode(active: false)
                        }
                    }
                } else {
                    store.updatePrivacyMode(active: false)
                }
            } else {
                store.updatePrivacyMode(active: true)
            }
        }
        
        private func handleNotificationSelection(_ item: NotificationInboxItem) {
            if let hwId = item.homeworkId, let hw = store.allHomeworks.first(where: { $0.id == hwId }) {
                detailHomework = hw
            } else if let examId = item.examId, let exam = store.allExams.first(where: { $0.id == examId }) {
                detailExam = exam
            } else if item.kind == .daily {
                let examIds = item.examIds ?? (item.examId.map { [$0] } ?? [])
                let homeworkIds = item.homeworkIds ?? (item.homeworkId.map { [$0] } ?? [])
                let exams = store.allExams.filter { examIds.contains($0.id) }
                let hws = store.allHomeworks.filter { homeworkIds.contains($0.id) }
                dailySummaryData = DailySummaryData(exams: exams, homeworks: hws, date: Date().addingTimeInterval(86400))
            }
        }
    struct ScrollOffsetKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

// MARK: - Extensions & Helper Structs

extension FinalGradeView {
    
    fileprivate struct SwapCandidate: Identifiable {
        let id = UUID()
        let subject: Subject
        let halfYear: Int
    }

    fileprivate struct FinalGradeSheets<StatusSheet: View, DropSheet: View>: ViewModifier {
        @Binding var showNotifications: Bool
        @Binding var showWhatIfGradesSheet: Bool
        @Binding var showWhatIfExamSheet: Bool
        @Binding var showSeminarSheet: Bool
        @Binding var showStatusDetails: Bool
        @Binding var showManageDrops: Bool
        @Binding var showPDFSheet: Bool
        @Binding var showSwapOptions: Bool
        @Binding var showWhatIfSimulationMode: Bool
        @Binding var detailHomework: Homework?
        @Binding var detailExam: Exam?
        @Binding var dailySummaryData: DailySummaryData?
        
        var store: GradesStore
        var notificationInbox: NotificationInboxStore
        private var examSubjectHandles: [SubjectHandle]
        
        let baselineFinalGradeText: String
        let baselineFinalGradeValue: Double?
        let finalGradeColor: (Double?) -> Color
        
        let statusDetailSheet: StatusSheet
        let manageDropsSheet: DropSheet
        
        private let droppedHalfYears: [(handle: SubjectHandle, halfYear: Int)]
        let swapCandidate: SwapCandidate?
        
        let handleNotificationSelection: (NotificationInboxItem) -> Void
        let syncDropSelectionsFromData: () -> Void
        let recomputeMaxDroppedHalfYears: () -> Void
        let loadPreviousYearSnapshotIfNeeded: () async -> Void
        let previousYearSnapshot: Any?
        let triggerUpdate: () -> Void
        let makeFobosoSummary: ([String: Double?]?) -> (examCount: Int, halfYearCount: Int, examPointsDouble: Double, halfYearPoints: Double, seminarPointsDouble: Double, totalPoints: Double, totalPointsRaw: Double, maxPoints: Int, grade: Double?, gradeRaw: Double?, averageAfterDrops: Double?)
        let finalGradeText: ([String: Double?]) -> String
        let mergedExamPoints: ([String: Double?], [String: Double]) -> [String: Double?]
        
        fileprivate init(
            showNotifications: Binding<Bool>,
            showWhatIfGradesSheet: Binding<Bool>,
            showWhatIfExamSheet: Binding<Bool>,
            showSeminarSheet: Binding<Bool>,
            showStatusDetails: Binding<Bool>,
            showManageDrops: Binding<Bool>,
            showPDFSheet: Binding<Bool>,
            showSwapOptions: Binding<Bool>,
            showWhatIfSimulationMode: Binding<Bool>,
            detailHomework: Binding<Homework?>,
            detailExam: Binding<Exam?>,
            dailySummaryData: Binding<DailySummaryData?>,
            store: GradesStore,
            notificationInbox: NotificationInboxStore,
            examSubjectHandles: [SubjectHandle],
            baselineFinalGradeText: String,
            baselineFinalGradeValue: Double?,
            finalGradeColor: @escaping (Double?) -> Color,
            statusDetailSheet: StatusSheet,
            manageDropsSheet: DropSheet,
            droppedHalfYears: [(handle: SubjectHandle, halfYear: Int)],
            swapCandidate: SwapCandidate?,
            handleNotificationSelection: @escaping (NotificationInboxItem) -> Void,
            syncDropSelectionsFromData: @escaping () -> Void,
            recomputeMaxDroppedHalfYears: @escaping () -> Void,
            loadPreviousYearSnapshotIfNeeded: @escaping () async -> Void,
            previousYearSnapshot: Any?,
            triggerUpdate: @escaping () -> Void,
            makeFobosoSummary: @escaping ([String: Double?]?) -> (examCount: Int, halfYearCount: Int, examPointsDouble: Double, halfYearPoints: Double, seminarPointsDouble: Double, totalPoints: Double, totalPointsRaw: Double, maxPoints: Int, grade: Double?, gradeRaw: Double?, averageAfterDrops: Double?),
            finalGradeText: @escaping ([String: Double?]) -> String,
            mergedExamPoints: @escaping ([String: Double?], [String: Double]) -> [String: Double?]
        ) {
            self._showNotifications = showNotifications
            self._showWhatIfGradesSheet = showWhatIfGradesSheet
            self._showWhatIfExamSheet = showWhatIfExamSheet
            self._showSeminarSheet = showSeminarSheet
            self._showStatusDetails = showStatusDetails
            self._showManageDrops = showManageDrops
            self._showPDFSheet = showPDFSheet
            self._showSwapOptions = showSwapOptions
            self._showWhatIfSimulationMode = showWhatIfSimulationMode
            self._detailHomework = detailHomework
            self._detailExam = detailExam
            self._dailySummaryData = dailySummaryData
            self.store = store
            self.notificationInbox = notificationInbox
            self.examSubjectHandles = examSubjectHandles
            self.baselineFinalGradeText = baselineFinalGradeText
            self.baselineFinalGradeValue = baselineFinalGradeValue
            self.finalGradeColor = finalGradeColor
            self.statusDetailSheet = statusDetailSheet
            self.manageDropsSheet = manageDropsSheet
            self.droppedHalfYears = droppedHalfYears
            self.swapCandidate = swapCandidate
            self.handleNotificationSelection = handleNotificationSelection
            self.syncDropSelectionsFromData = syncDropSelectionsFromData
            self.recomputeMaxDroppedHalfYears = recomputeMaxDroppedHalfYears
            self.loadPreviousYearSnapshotIfNeeded = loadPreviousYearSnapshotIfNeeded
            self.previousYearSnapshot = previousYearSnapshot
            self.triggerUpdate = triggerUpdate
            self.makeFobosoSummary = makeFobosoSummary
            self.finalGradeText = finalGradeText
            self.mergedExamPoints = mergedExamPoints
        }
        
        func body(content: Content) -> some View {
            content
                .sheet(isPresented: $showNotifications) {
                    NotificationsInboxView(
                        inbox: notificationInbox,
                        onSelectNotification: { item in
                            handleNotificationSelection(item)
                            showNotifications = false
                        },
                        onOpenImportant: {
                            showNotifications = false
                        }
                    )
                    .environmentObject(store)
                }
                .sheet(isPresented: $showWhatIfGradesSheet) {
                    makeWhatIfView()
                        .presentationBackground {
                            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                        }
                }
                .sheet(isPresented: $showWhatIfSimulationMode) {
                    WhatIfModeView()
                        .environmentObject(store)
                        .presentationBackground {
                            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                        }
                }
                .sheet(isPresented: $showWhatIfExamSheet) {
                    AbiturExamView()
                        .environmentObject(store)
                        .presentationBackground {
                            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                        }
                }
                .sheet(isPresented: $showSeminarSheet) {
                    SeminarPerformanceView()
                        .environmentObject(store)
                        .presentationBackground {
                            ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity)
                        }
                }
                .sheet(isPresented: $showStatusDetails) {
                    statusDetailSheet
                }
                .sheet(isPresented: $showManageDrops) {
                    manageDropsSheet
                        .onDisappear {
                            syncDropSelectionsFromData()
                            recomputeMaxDroppedHalfYears()
                        }
                }
                .sheet(isPresented: $showPDFSheet) {
                    ReportCardSheet()
                        .environmentObject(store)
                }
                .confirmationDialog(
                    "Halbjahr tauschen",
                    isPresented: $showSwapOptions,
                    presenting: swapCandidate
                ) { candidate in
                    Button("Tauschen") {
                        Task {
                            await store.swapHalfYear(subject: candidate.subject, from: candidate.halfYear)
                            triggerUpdate()
                        }
                    }
                    Button("Abbrechen", role: .cancel) { }
                } message: { candidate in
                    Text("Das \(candidate.halfYear). Halbjahr von \(candidate.subject.name) wird gegen das gestrichene Halbjahr getauscht.")
                }
                .sheet(item: $detailHomework) { hw in
                    HomeworkDetailSheet(homework: hw, onEdit: { _ in })
                        .environmentObject(store)
                }
                .sheet(item: $detailExam) { ex in
                    ExamDetailSheet(exam: ex, onEdit: { _ in })
                        .environmentObject(store)
                }
                .sheet(item: $dailySummaryData) { data in
                    DailySummarySheet(data: data)
                        .environmentObject(store)
                }
        }
        
        private func makeWhatIfView() -> some View {
            let examSubjects = store.subjects.filter { $0.examSubject == true }
            
            let existingPoints = Dictionary(uniqueKeysWithValues: examSubjects.map { subject in
                 (subject.name, store.examPoints[subject.name] ?? nil)
            })
            
            let existingSimulation = store.simulatedExamPointsDict
            
            return FinalGradeWhatIfView(
                subjects: examSubjects,
                existingPoints: existingPoints,
                existingSimulation: existingSimulation,
                baselineGradeText: baselineFinalGradeText,
                baselineGradeValue: baselineFinalGradeValue,
                computePreview: { overrides in
                    let merged = mergedExamPoints(store.examPoints, overrides)
                    let summary = makeFobosoSummary(merged)
                    return (finalGradeText(merged), summary.gradeRaw)
                },
                gradeColor: finalGradeColor,
                onApply: { overrides in
                    store.simulatedExamPointsDict = overrides
                },
                onReset: {
                    store.clearExamSimulations()
                }
            )
            .environmentObject(store)
        }
    }
}

