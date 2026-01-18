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
    @EnvironmentObject var store: GradesStore
    @EnvironmentObject var biometricManager: BiometricAuthManager

    @State private var dropSelections: [String: HalfYearDropOption] = [:]
    @State private var maxDroppedHalfYears: Int = 3
    @State private var finalGradeToFixed: Int = 1
    @State private var finalGradeTapState: Int = 0 // 0 -> 1 Nachkommastelle, 1 -> 2, 2 -> 3
    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false
    @State private var showWhatIfGradesSheet: Bool = false
    @State private var showWhatIfExamSheet: Bool = false
    @State private var showSeminarSheet: Bool = false
    @State private var showStatusDetails: Bool = false
    @State private var previousYearSnapshot: SchoolYearSnapshot?
    @State private var isLoadingPreviousYear: Bool = false
    @State private var simulatedExamPoints: [String: Double] = [:]
    @State private var showNotifications: Bool = false
    @State private var showPDFSheet: Bool = false // PDF Export Sheet
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false
    @ObservedObject private var notificationInbox = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}

    private struct SubjectHandle: Identifiable, Hashable {
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
    private var hasExamSimulation: Bool { !simulatedExamPoints.isEmpty }
    private var activeExamPointsBySubject: [String: Double?] {
        var merged = store.examPoints
        for (key, value) in simulatedExamPoints {
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

    var body: some View {
        ScrollView {
            contentStack
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNotifications) {
            NotificationsInboxView(
                inbox: notificationInbox,
                onSelectNotification: { item in
                    handleNotificationSelection(item)
                },
                onOpenImportant: {
                    NotificationCenter.default.post(name: .openLaunchOffer, object: nil)
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showWhatIfGradesSheet) {
            WhatIfModeView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showWhatIfExamSheet) {
            FinalGradeWhatIfView(
                subjectNames: examSubjectHandles.map { $0.subject.name }.sorted(),
                existingPoints: store.examPoints,
                existingSimulation: simulatedExamPoints,
                baselineGradeText: baselineFinalGradeText,
                baselineGradeValue: baselineFinalGradeValue,
                computePreview: { overrides in
                    let merged = mergedExamPoints(base: store.examPoints, overrides: overrides)
                    let text = finalGradeText(for: merged)
                    let value = finalGradeValue(using: merged)
                    return (text, value)
                },
                gradeColor: finalGradeColor(_:),
                onApply: { overrides in
                    simulatedExamPoints = overrides
                },
                onReset: {
                    simulatedExamPoints = [:]
                }
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showSeminarSheet) {
            SeminarPerformanceView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showStatusDetails) {
            statusDetailSheet
        }
        .sheet(isPresented: $showPDFSheet) {
            ReportCardSheet()
                .environmentObject(store)
        }
        .onAppear {
            syncDropSelectionsFromData()
            recomputeMaxDroppedHalfYears()
            Task { await loadPreviousYearSnapshotIfNeeded() }
        }
        .onChange(of: store.subjects) { _, _ in
            syncDropSelectionsFromData()
            recomputeMaxDroppedHalfYears()
        }
        .onChange(of: store.gradeYear) { _, _ in
            recomputeMaxDroppedHalfYears()
            Task { await loadPreviousYearSnapshotIfNeeded() }
        }
        .onChange(of: store.schoolType) { _, _ in
            recomputeMaxDroppedHalfYears()
            Task { await loadPreviousYearSnapshotIfNeeded() }
        }
        .onChange(of: store.schoolYears) { _, _ in
            Task { await loadPreviousYearSnapshotIfNeeded() }
        }
        .onChange(of: store.activeSchoolYearId) { _, _ in
            syncDropSelectionsFromData()
            recomputeMaxDroppedHalfYears()
            simulatedExamPoints = [:]
            Task { await loadPreviousYearSnapshotIfNeeded() }
        }
        .onChange(of: previousYearSnapshot?.id) { _, _ in
            syncDropSelectionsFromData()
            recomputeMaxDroppedHalfYears()
        }
        .onChange(of: store.encryptionKey == nil) { _, _ in
            Task {
                await loadPreviousYearSnapshotIfNeeded()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 8) {
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
                    
                    Button {
                        showPDFSheet = true
                    } label: {
                        ToolbarIcon(symbol: "doc.text", showDot: false)
                    }
                    .accessibilityLabel("Zeugnis als PDF exportieren")
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
            subjectListSection
                .padding(.horizontal)
                .softFadeIn(enabled: animationsOn, delay: 0.30, offset: 12)
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
        .padding(.vertical, 8)
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
                Text("Stand heute")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
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
        VStack(spacing: 16) {
            // Prominent centered grade display
            VStack(spacing: 6) {
                Text(finalGradeText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(finalGradeColor(finalGradeValueForColor))
                    .privacyBlur()
                    .contentTransition(.numericText())
                    .onTapGesture { toggleFinalGradeToFixed() }
                
                if let gradeValue = finalGradeValueForColor {
                    Text(finalGradeDescriptor(gradeValue))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if hasExamSimulation {
                    PillBadge(
                        text: "Simulation aktiv",
                        systemImage: "wand.and.stars",
                        foreground: .pink,
                        background: Color.pink.opacity(0.16)
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            
            // Simple stat chips row matching InsightsView
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatChip(
                    title: "MSS",
                    value: heroMSSValue,
                    accent: .indigo
                )
                
                StatChip(
                    title: "Punkte",
                    value: "\(Int(round(fobosoSummary.totalPoints)))/\(fobosoSummary.maxPoints)",
                    accent: .orange
                )
                
                StatChip(
                    title: "Fächer",
                    value: "\(store.subjects.count)",
                    accent: .cyan
                )
            }
        }
    }


    /// MSS value (0-15 points average) for hero display
    private var heroMSSValue: String {
        guard fobosoSummary.maxPoints > 0 else { return "-" }
        let avgPoints = (fobosoSummary.totalPoints * 15.0) / Double(fobosoSummary.maxPoints)
        return String(format: "%.2f", avgPoints)
    }
    
    /// MSS text for display under grade
    private var heroMSSText: String {
        guard fobosoSummary.maxPoints > 0 else { return "MSS: -" }
        let avgPoints = (fobosoSummary.totalPoints * 15.0) / Double(fobosoSummary.maxPoints)
        return "MSS: \(String(format: "%.2f", avgPoints))"
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
                    HStack(spacing: 10) {
                        StatChip(title: "Aktuell", value: baselineFinalGradeText, accent: .indigo)
                        StatChip(title: "Simulation", value: finalGradeText, accent: .pink)
                        StatChip(title: "Δ", value: formatFinalGradeDelta(base: baselineFinalGradeValue, simulated: simulatedFinalGradeValue), accent: .orange)
                    }
                    Text(hasExamSimulation ? "Simulation aktiv: Eingaben werden nicht gespeichert und gelten nur hier." : "Füge fiktive Prüfungsnoten hinzu oder teste zusätzliche Noten – alles bleibt lokal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            showWhatIfGradesSheet = true
                        } label: {
                            Label("Noten simulieren", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .indigo))

                        Button {
                            showWhatIfExamSheet = true
                        } label: {
                            Label("Abitur simulieren", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .pink))
                    }

                    if hasExamSimulation {
                        Button {
                            simulatedExamPoints = [:]
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
        SettingsCard(
            title: "Prüfungsstatus",
            subtitle: nil,
            systemImage: "checkmark.seal.fill",
            accent: status.color
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(status.text)
                        .font(.headline)
                    Spacer()
                    Text(status.text == "Bestanden" ? "✔︎" : status.text == "Nicht bestanden" ? "✖︎" : "…")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(status.color.opacity(0.18))
                        .foregroundStyle(status.color == .secondary ? Color.primary : status.color)
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
                                Text(formatAverage(entry.final))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(gradeColor(entry.final).opacity(0.15))
                                    .foregroundStyle(gradeColor(entry.final))
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
                                Text(formatAverage(avg))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(gradeColor(avg).opacity(0.15))
                                    .foregroundStyle(gradeColor(avg))
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
                    Text("Prüfungen (\(Int(examWeightFactor))× Gewichtung): \(Int(round(fobosoSummary.examPointsDouble))) Punkte")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Halbjahresergebnisse: \(Int(round(fobosoSummary.halfYearPoints))) Punkte (\(halfYearSummary.count) HJE).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if practicalYearSummary.count > 0 {
                        Text("Praktikum 11.: \(Int(round(practicalYearSummary.totalPoints))) Punkte (\(practicalYearSummary.count) HJL).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if hasSeminarRequirement {
                        let pointsText = seminarFinalPoints != nil ? "\(Int(round(seminarPointsDouble))) Punkte" : "noch offen"
                        Text("Seminarfach (2×): \(pointsText).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if fachreferatHalfYearSummary.count > 0 {
                        Text("Fachreferat: \(Int(round(fachreferatHalfYearSummary.totalPoints))) Punkte (\(fachreferatHalfYearSummary.count) HJE).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            title: "Gestrichene Halbjahre",
            subtitle: nil,
            systemImage: "scissors",
            accent: .indigo
        ) {
            SettingsSectionBox {
                Text(
                    maxDroppedHalfYears > 0
                    ? "Du kannst insgesamt bis zu \(maxDroppedHalfYears) Halbjahre streichen."
                    : "Das Streichen von Halbjahren ist derzeit deaktiviert."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if droppedHalfYears.isEmpty {
                    Text("Du hast noch kein Halbjahr gestrichen.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(droppedHalfYears, id: \.handle.id) { entry in
                            let droppedAverage = calculateHalfYearAverageForSubject(entry.handle.subject, grades: entry.handle.grades, halfYear: entry.halfYear)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(entry.handle.subject.name)
                                    HStack(spacing: 6) {
                                        Text(entry.halfYear == 1 ? "1. Halbjahr" : "2. Halbjahr")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if let yearLabel = entry.handle.yearLabel {
                                            Text("\(yearLabel) Jahrgang")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Text(formatAverage(droppedAverage))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(gradeColor(droppedAverage).opacity(0.15))
                                    .foregroundStyle(gradeColor(droppedAverage))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var subjectListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fächer").font(.headline)
            Text("Streiche die Noten des gewählten Halbjahres.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if canUsePreviousYearSnapshot {
                Text("Halbjahre aus dem 11. und 12. Jahrgang werden gemeinsam angezeigt und können gemeinsam gestrichen werden.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if eligibleSubjectHandles.isEmpty {
                Text("Lege zuerst Fächer und Noten an, um deine Abschlussnote zu berechnen.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(sortedSubjectHandles.enumerated()), id: \.element.id) { entry in
                        let handle = entry.element
                        let delay = 0.30 + Double(entry.offset) * 0.05
                        subjectCard(handle)
                            .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func subjectCard(_ handle: SubjectHandle) -> some View {
        let dropOption = dropSelections[handle.id] ?? .none
        let isHalfYear1Dropped = dropOption == .one
        let isHalfYear2Dropped = dropOption == .two
        let canSelectHalfYear1 = !((limitReached || maxDroppedHalfYears <= 0) && !isHalfYear1Dropped)
        let canSelectHalfYear2 = !((limitReached || maxDroppedHalfYears <= 0) && !isHalfYear2Dropped)

        let subjectGrades = handle.grades
        let firstHalfYearAverage = calculateHalfYearAverageForSubject(handle.subject, grades: subjectGrades, halfYear: 1)
        let secondHalfYearAverage = calculateHalfYearAverageForSubject(handle.subject, grades: subjectGrades, halfYear: 2)
        let subjectAverage = subjectAverageFor(handle: handle)

        // Create binding for segmented picker
        let dropBinding = Binding<Int>(
            get: {
                switch dropOption {
                case .none: return 0
                case .one: return 1
                case .two: return 2
                }
            },
            set: { newValue in
                switch newValue {
                case 1:
                    if canSelectHalfYear1 || isHalfYear1Dropped {
                        handleToggleHalfYear(handle: handle, halfYear: 1)
                    }
                case 2:
                    if canSelectHalfYear2 || isHalfYear2Dropped {
                        handleToggleHalfYear(handle: handle, halfYear: 2)
                    }
                default:
                    // Selecting "Keines" - deselect current
                    if isHalfYear1Dropped {
                        handleToggleHalfYear(handle: handle, halfYear: 1)
                    } else if isHalfYear2Dropped {
                        handleToggleHalfYear(handle: handle, halfYear: 2)
                    }
                }
            }
        )

        SettingsCard(
            title: handle.subject.name,
            subtitle: handle.yearLabel.map { "\($0) Jahrgang" },
            systemImage: subjectIcon(for: handle.subject.name),
            accent: .indigo
        ) {
            // Subject average badge
            Text(formatAverage(subjectAverage))
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(gradeColor(subjectAverage).opacity(0.15))
                .foregroundStyle(gradeColor(subjectAverage))
                .clipShape(Capsule())
                .privacyBlur()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                // Segmented picker for drop selection
                SegmentedPicker(
                    selection: dropBinding,
                    options: [
                        SegmentedPickerOption(title: "Keines", value: 0),
                        SegmentedPickerOption(title: "1. HJ", value: 1),
                        SegmentedPickerOption(title: "2. HJ", value: 2)
                    ],
                    accent: .indigo
                )

                // Side-by-side half-year grades
                HStack(spacing: 10) {
                    StatChip(
                        title: "1. Halbjahr",
                        value: formatAverage(firstHalfYearAverage),
                        accent: gradeColor(firstHalfYearAverage),
                        isGreyedOut: isHalfYear1Dropped
                    )

                    StatChip(
                        title: "2. Halbjahr",
                        value: formatAverage(secondHalfYearAverage),
                        accent: gradeColor(secondHalfYearAverage),
                        isGreyedOut: isHalfYear2Dropped
                    )
                }
            }
        }
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
                            Text(formatAverage(avg))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(gradeColor(avg).opacity(0.15))
                                .foregroundStyle(gradeColor(avg))
                                .clipShape(Capsule())
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
                                    Text(formatAverage(entry.grade))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(gradeColor(entry.grade).opacity(0.15))
                                        .foregroundStyle(gradeColor(entry.grade))
                                        .clipShape(Capsule())
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
        HStack(alignment: .top, spacing: 6) {
            Text("x")
                .font(.caption)
                .foregroundStyle(Color(hex: "#f87171"))
                .padding(.top, 1)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color(hex: "#f87171"))
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
        return String(format: "%.2f", v)
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
            Text(value != nil ? "\(Int(value!)) Punkte" : "fehlt")
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(gradeColor(value).opacity(0.15))
                .foregroundStyle(gradeColor(value))
                .clipShape(Capsule())
        }
    }

    private var finalGradeValueForColor: Double? {
        finalGradeValue(using: activeExamPointsBySubject)
    }

    private var finalGradeText: String {
        finalGradeText(for: activeExamPointsBySubject)
    }

    private var baselineFinalGradeText: String {
        finalGradeText(for: store.examPoints)
    }

    private var baselineFinalGradeValue: Double? {
        finalGradeValue(using: store.examPoints)
    }

    private var simulatedFinalGradeValue: Double? {
        finalGradeValue(using: activeExamPointsBySubject)
    }

    private func formatFinalGradeDelta(base: Double?, simulated: Double?) -> String {
        guard let base, let simulated else { return "-" }
        let delta = simulated - base
        if abs(delta) < 0.005 { return "0.00" }
        let prefix = delta > 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.2f", delta))"
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
        if v <= 3.4 { return "Stabiler Schnitt" }
        if v <= 4.4 { return "Ausreichender Schnitt - Dran bleiben!"}
        return "Achtung: Schnitt im roten Bereich"
    }

    private func finalGradeValue(using points: [String: Double?]) -> Double? {
        let summary = makeFobosoSummary(examPoints: points)
        if summary.maxPoints > 0 {
            // Priority: full grade from formula
            if let g = summary.grade { return g }
            
            // Fallback: calculate average grade from total weighted points
            let averagePoints = (summary.totalPoints * 15.0) / Double(summary.maxPoints)
            return pointsToGrade(averagePoints)
        }
        // Last resort fallback
        return abiturFinalAverage(points: points) ?? gradesOnlyFinalAverage
    }

    private func finalGradeText(for points: [String: Double?]) -> String {
        let decimals = max(1, min(3, finalGradeToFixed))
        let summary = makeFobosoSummary(examPoints: points)
        if summary.maxPoints > 0 {
            if let g = summary.grade {
                return String(format: "%.\(decimals)f", g)
            }
            let averagePoints = (summary.totalPoints * 15.0) / Double(summary.maxPoints)
            return pointsToGradeText(averagePoints, decimals: decimals)
        }
        // Fallback
        return formatAverage(abiturFinalAverage(points: points) ?? gradesOnlyFinalAverage)
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

        func getSubjectAverageForSort(_ handle: SubjectHandle) -> Double? {
            let grades = filteredGradesByHandle[handle.id] ?? []
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
                let a1 = getSubjectAverageForSort(a)
                let b1 = getSubjectAverageForSort(b)
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
                let a1 = getSubjectAverageForSort(a)
                let b1 = getSubjectAverageForSort(b)
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

    private func makeFobosoSummary(examPoints: [String: Double?]? = nil) -> (examCount: Int,
                                                                              halfYearCount: Int,
                                                                              examPointsDouble: Double,
                                                                              halfYearPoints: Double,
                                                                              seminarPointsDouble: Double,
                                                                              totalPoints: Double,
                                                                              maxPoints: Int,
                                                                              grade: Double?,
                                                                              gradeRaw: Double?) {
        let subjects = eligibleSubjectHandles.map {
            GradeCalculationService.SubjectData(id: $0.id, subject: $0.subject, grades: $0.grades, isEligible: $0.isEligible)
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
        
        return (res.examCount, res.halfYearCount, res.examPointsDouble, res.halfYearPoints, res.seminarPointsDouble, res.totalPoints, res.maxPoints, res.grade, res.gradeRaw)
    }


    private var fobosoSummary: (examCount: Int,
                                halfYearCount: Int,
                                examPointsDouble: Double,
                                halfYearPoints: Double,
                                seminarPointsDouble: Double,
                                totalPoints: Double,
                                maxPoints: Int,
                                grade: Double?,
                                gradeRaw: Double?) {
        makeFobosoSummary(examPoints: nil)
    }

    private var baselineFobosoSummary: (examCount: Int,
                                        halfYearCount: Int,
                                        examPointsDouble: Double,
                                        halfYearPoints: Double,
                                        seminarPointsDouble: Double,
                                        totalPoints: Double,
                                        maxPoints: Int,
                                        grade: Double?,
                                        gradeRaw: Double?) {
        makeFobosoSummary(examPoints: store.examPoints)
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

    private func toggleFinalGradeToFixed() {
        // Cycle 1 -> 2 -> 3 -> 1
        switch finalGradeTapState {
        case 0:
            finalGradeToFixed = 2
            finalGradeTapState = 1
        case 1:
            finalGradeToFixed = 3
            finalGradeTapState = 2
        default:
            finalGradeToFixed = 1
            finalGradeTapState = 0
        }
    }

    // MARK: - Actions

    private func handleToggleHalfYear(handle: SubjectHandle, halfYear: Int) {
        let key = handle.id
        let current = dropSelections[key] ?? .none
        var next: HalfYearDropOption = current

        if (current == .one && halfYear == 1) || (current == .two && halfYear == 2) {
            next = .none
        } else {
            let currentSelectedCount = dropSelections.values.filter { $0 == .one || $0 == .two }.count
            let currentlyHasDrop = (current == .one || current == .two)
            let willAddNewDrop = !currentlyHasDrop

            if willAddNewDrop && maxDroppedHalfYears > 0 && currentSelectedCount >= maxDroppedHalfYears {
                return
            }
            next = (halfYear == 1 ? .one : .two)
        }

        dropSelections[key] = next
        Task {
            await store.updateDroppedHalfYear(
                subjectName: handle.subject.name,
                value: next.persistedValue,
                inSchoolYear: handle.isCurrentYear ? nil : handle.schoolYearId
            )
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
                                                .foregroundStyle(.red)
                                            Text(reason)
                                                .frame(maxWidth: .infinity, alignment: .leading)
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
        if let _ = item.homeworkId {
            showHomeworkSheet = true
        } else if let _ = item.examId {
            showExamSheet = true
        } else if item.kind == .daily {
            showHomeworkSheet = true
        }
    }
}
