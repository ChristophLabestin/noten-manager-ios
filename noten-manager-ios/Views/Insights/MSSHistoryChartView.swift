import SwiftUI
import Charts
import Combine

struct MSSHistoryChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let mss: Double
    let subjectName: String
    let gradeValue: Double
    let assessmentType: AssessmentType?
}

struct MSSHistoryChartView: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var dataPoints: [MSSHistoryChartDataPoint] = []
    @State private var isLoading: Bool = true
    @Binding var includeDroppedHalfYears: Bool

    @State private var selectedDate: Date?
    @State private var selectedPoint: MSSHistoryChartDataPoint?
    
    // Dynamic Y-Axis scale props
    private var yDomain: ClosedRange<Double> {
        guard !dataPoints.isEmpty else { return 0...15 }
        let values = dataPoints.map { $0.mss }
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 15
        
        // Add some breathing room (e.g. +/- 1 point), clamped to 0-15
        let lower = max(0, minVal - 1.5)
        let upper = min(15, maxVal + 1.5)
        
        // If range is too small, default to a reasonable spread
        if upper - lower < 2 {
            return max(0, lower - 1)...min(15, upper + 1)
        }
        return lower...upper
    }
    
    // Computed property to check if any subject has dropped half-years
    private var hasDroppedHalfYears: Bool {
        store.subjects.contains { $0.droppedHalfYear != nil }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
                .padding(.horizontal, 4)

            content
        }
        .padding(.bottom, 24) // Added spacing for card below
        .onAppear {
            calculateHistory()
        }
        .onReceive(store.$gradesBySubject) { _ in
            calculateHistory()
        }
        .onChange(of: includeDroppedHalfYears) { _, _ in
            calculateHistory()
        }
        .onChange(of: store.isPrivacyModeActive) { _, active in
            if active {
                withAnimation {
                    selectedPoint = nil
                }
            }
        }
    }
    
    private func findClosestPoint(at location: CGPoint, proxy: ChartProxy) {
        guard let date: Date = proxy.value(atX: location.x) else { return }
        
        if let closest = dataPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
            if selectedPoint?.id != closest.id {
                let generator = UISelectionFeedbackGenerator()
                generator.selectionChanged()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedPoint = closest
                }
            }
        }
    }

    private func inferHalfYear(from date: Date) -> Int {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        // H2 is typically March (3) to July (7)
        if month >= 3 && month <= 7 {
            return 2
        }
        // All other months (Aug-Feb) are H1
        return 1
    }

    private func calculateHistory() {
        isLoading = true
        let includeDropped = includeDroppedHalfYears
        
        Task { @MainActor in
            let gradesMap = store.gradesBySubject
            let subjects = store.subjects
            let fr = store.fachreferat
            let sem = store.seminarPerformance
            let prac = store.practicalPerformance
            let ep = store.examPoints
            let st = store.schoolType
            let gy = store.gradeYear

            // Helper wrapper for calculation
            struct GradeEvent {
                let date: Date
                let grade: Double
                let weight: Double
                let halfYear: Int?
                let subjectName: String
                let assessmentType: AssessmentType?
                let id: String
            }
            
            var events: [GradeEvent] = []
            
            for (subjectName, grades) in gradesMap {
                for g in grades {
                    events.append(GradeEvent(
                        date: g.date,
                        grade: g.grade,
                        weight: g.weight,
                        halfYear: g.halfYear,
                        subjectName: subjectName,
                        assessmentType: g.assessmentType,
                        id: g.id
                    ))
                }
            }
            
            events.sort { $0.date < $1.date }
            
            guard !events.isEmpty else {
                self.dataPoints = []
                self.isLoading = false
                return
            }
            
            // Pre-calculate effective GradingMode for each subject
            // This mirrors GradesStore.gradingMode(for:) logic to ensuring consistent weighing
            var subjectGradingModes: [String: GradingMode] = [:]
            for subject in subjects {
                if let explicit = subject.gradingMode {
                    subjectGradingModes[subject.name] = explicit
                } else {
                    let sGrades = gradesMap[subject.name] ?? []
                    // Only Schulaufgabe triggers withSchulaufgaben mode (not Kurzarbeit)
                    let hasSchulaufgabe = sGrades.contains { $0.assessmentType == .schulaufgabe }
                    // Also check for weighted exams in history if needed, but grade-check is usually sufficient for migrated data
                    if hasSchulaufgabe {
                        subjectGradingModes[subject.name] = .withSchulaufgaben
                    } else {
                        subjectGradingModes[subject.name] = (subject.type == 1) ? .withSchulaufgaben : .withoutSchulaufgaben
                    }
                }
            }
            
            var currentGradesBySubject: [String: [Grade]] = [:]
            var history: [MSSHistoryChartDataPoint] = []
            
            for event in events {
                // If halfYear is nil, infer it from date so it's not excluded from calc
                let effectiveHalfYear = event.halfYear ?? inferHalfYear(from: event.date)

                // Resolve the correct subject with the effective GradingMode
                guard var subject = subjects.first(where: { $0.name == event.subjectName }) else { continue }
                if let mode = subjectGradingModes[subject.name] {
                    // Create a copy with the resolved grading mode to ensure CalculationService uses correct logic
                    subject = Subject(
                        name: subject.name,
                        type: subject.type,
                        gradingMode: mode, // FORCE effective mode
                        expectedSchulaufgabenPerTerm: subject.expectedSchulaufgabenPerTerm,
                        date: subject.date,
                        order: subject.order,
                        teacher: subject.teacher,
                        room: subject.room,
                        email: subject.email,
                        alias: subject.alias,
                        droppedHalfYear: subject.droppedHalfYear,
                        examSubject: subject.examSubject,
                        examType: subject.examType,
                        examPointsEncrypted: subject.examPointsEncrypted,
                        writtenExamPointsEncrypted: subject.writtenExamPointsEncrypted,
                        oralExamPointsEncrypted: subject.oralExamPointsEncrypted,
                        isElective: subject.isElective
                    )
                }

                // 2. Pure Type-Based Logic (Ignore Legacy Weight)
                let gradingMode = subject.gradingMode ?? .withoutSchulaufgaben
                
                // A) Determine Type: Trust migrated type, default to .muendlich if missing/nil
                // (User confirmed data is migrated, so types should be correct)
                var effectiveType: AssessmentType = event.assessmentType ?? .muendlich
                
                // B) Override Type based on Mode
                if gradingMode == .withoutSchulaufgaben {
                    effectiveType = .muendlich
                }
                
                // C) Assign Standard Weight based on Type
                // For FOBOSO block calculation, only Schulaufgabe has weight 2.
                // Kurzarbeit and muendlich are part of "Sonstige" block with weight 1.
                let normalizedWeight: Double
                switch effectiveType {
                case .schulaufgabe:
                    normalizedWeight = 2.0
                case .kurzarbeit:
                    normalizedWeight = 1.0  // Part of Sonstige, not a block grade
                default:
                    normalizedWeight = 1.0
                }

                let newGrade = Grade(
                    grade: event.grade,
                    weight: normalizedWeight, 
                    date: event.date,
                    note: nil,
                    halfYear: effectiveHalfYear,
                    linkedExamId: nil,
                    assessmentType: effectiveType
                )
                
                var subjectGrades = currentGradesBySubject[event.subjectName] ?? []
                subjectGrades.append(newGrade)
                currentGradesBySubject[event.subjectName] = subjectGrades
                
                let avg = GradeCalculationService.calculateOverallAverage(
                    subjects: subjects.map { $0.name == subject.name ? subject : $0 }, // Inject our modified subject
                    halfYearValueProvider: { subj, halfYear in
                        // Use the modified subject if it matches, to get correct grading mode
                        let effectiveSubject = (subj.name == subject.name) ? subject : subj
                        
                        guard let gradesForSubject = currentGradesBySubject[effectiveSubject.name] else { return nil }
                        return GradeCalculationService.calculateHalfYearAverage(
                            grades: gradesForSubject,
                            subject: effectiveSubject,
                            halfYear: halfYear,
                            effectiveGradeWeight: { type, w in store.effectiveGradeWeight(subjectType: type, rawWeight: w) } 
                        )
                    },
                    droppedHalfYearProvider: { subj in
                        if includeDropped { return nil }
                        return subj.droppedHalfYear
                    },
                    halfYearFilter: nil,
                    fachreferat: fr,
                    seminar: sem,
                    practical: prac,
                    examPoints: ep,
                    schoolType: st,
                    gradeYear: gy ?? 12,
                    useRawValues: true // Use raw averages for history progression display
                )
                

                // If dropped, skip adding this point to history ENTIRELY
                // Fix: explicit check for droppedHalfYear != nil to avoid nil == nil matching
                // Also check against effectiveHalfYear
                let pointIsDropped = !includeDropped && (subject.droppedHalfYear != nil && subject.droppedHalfYear == effectiveHalfYear)
                
                if pointIsDropped { continue }
                
                if let avg = avg {
                     history.append(MSSHistoryChartDataPoint(
                        date: event.date,
                        mss: avg,
                        subjectName: event.subjectName,
                        gradeValue: event.grade,
                        assessmentType: event.assessmentType
                     ))
                }
            }
            
            self.dataPoints = history
            self.isLoading = false
        }
    }
    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if dataPoints.isEmpty {
            Text("Keine Noten vorhanden")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            Chart {
                chartMarks
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    if value.as(Date.self) != nil {
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                            .foregroundStyle(Color.secondary)
                            .font(.caption2)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                    AxisGridLine()
                        .foregroundStyle(Color.secondary.opacity(0.1))
                    AxisValueLabel()
                        .foregroundStyle(Color.secondary)
                        .font(.caption2)
                }
            }
            .chartOverlay { proxy in
                chartGestureOverlay(proxy: proxy)
            }
            .frame(height: 220)
            .privacyBlur()
            .overlay {
                if store.isPrivacyModeActive {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.5))
                        
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                            Text("Privatsphäre aktiv")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    @ChartContentBuilder
    private var chartMarks: some ChartContent {
        ForEach(dataPoints) { point in
            // Gradient Fill - clamped to bottom of domain
            AreaMark(
                x: .value("Datum", point.date),
                yStart: .value("Base", yDomain.lowerBound),
                yEnd: .value("MSS", point.mss)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.15),
                        Color.indigo.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Clean Line
            LineMark(
                x: .value("Datum", point.date),
                y: .value("MSS", point.mss)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(Color.indigo)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            
            // Visible Node for every point
            PointMark(
                x: .value("Datum", point.date),
                y: .value("MSS", point.mss)
            )
            .foregroundStyle(Color.indigo)
            .symbol {
                Circle()
                    .fill(Color.indigo)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 1)
            }
        }
        
        if let selectedPoint {
            // Vertical Guide
            RuleMark(x: .value("Datum", selectedPoint.date))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1))
                
            // Selected Point Highlight & Tooltip
            PointMark(
                x: .value("Datum", selectedPoint.date),
                y: .value("MSS", selectedPoint.mss)
            )
            .foregroundStyle(Color.indigo)
            .symbol {
                Circle()
                    .fill(Color.indigo)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 3)
            }
            .annotation(position: .top, alignment: .center, spacing: 12) {
                VStack(spacing: 4) {
                    Text("\(selectedPoint.subjectName)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    VStack(spacing: 0) {
                        // Display raw Points for MSS, otherwise converted grade
                        Text("\(selectedPoint.gradeValue, specifier: "%.0f") NP")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        if let type = selectedPoint.assessmentType {
                            Text(type.prettyName)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Ø \(String(format: "%.2f", selectedPoint.mss))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.indigo)
                            .monospacedDigit()
                    }
                    
                    Text(selectedPoint.date.formatted(.dateTime.day().month()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.tertiarySystemBackground))
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                )
            }
        }
    }

    private func chartGestureOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .allowsHitTesting(!store.isPrivacyModeActive)
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geometry[plotFrame].origin
                            let location = CGPoint(
                                x: value.location.x - origin.x,
                                y: value.location.y - origin.y
                            )
                            findClosestPoint(at: location, proxy: proxy)
                        }
                        .simultaneously(with: DragGesture()
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let location = CGPoint(
                                    x: value.location.x - origin.x,
                                    y: value.location.y - origin.y
                                )
                                findClosestPoint(at: location, proxy: proxy)
                            }
                            .onEnded { _ in
                                // Optional: Keep tooltips persistent or auto-dismiss?
                                // Auto-dismiss is cleaner for "viewing".
                                withAnimation(.easeInOut) {
                                    selectedPoint = nil
                                }
                            }
                        )
                )
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Verlauf")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text("MSS-Entwicklung über die Zeit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
