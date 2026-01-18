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
    @State private var includeDroppedHalfYears: Bool = false

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
        .onChange(of: includeDroppedHalfYears) {
            calculateHistory()
        }
        .onChange(of: store.isPrivacyModeActive) { active in
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
            
            var currentGradesBySubject: [String: [Grade]] = [:]
            var history: [MSSHistoryChartDataPoint] = []
            
            for event in events {
                let newGrade = Grade(
                    grade: event.grade,
                    weight: event.weight,
                    date: event.date,
                    note: nil,
                    halfYear: event.halfYear,
                    linkedExamId: nil,
                    assessmentType: event.assessmentType
                )
                
                var subjectGrades = currentGradesBySubject[event.subjectName] ?? []
                subjectGrades.append(newGrade)
                currentGradesBySubject[event.subjectName] = subjectGrades
                
                let avg = GradeCalculationService.calculateOverallAverage(
                    subjects: subjects,
                    halfYearValueProvider: { subject, halfYear in
                        guard let gradesForSubject = currentGradesBySubject[subject.name] else { return nil }
                        return GradeCalculationService.calculateHalfYearAverage(
                            grades: gradesForSubject,
                            subject: subject,
                            halfYear: halfYear,
                            effectiveGradeWeight: { _, w in w }
                        )
                    },
                    droppedHalfYearProvider: { subject in
                        // If includeDropped logic is ON, we return nil (none dropped). 
                        // Otherwise, we respect the subject's droppedHalfYear.
                        if includeDropped {
                            return nil 
                        }
                        return subject.droppedHalfYear
                    },
                    halfYearFilter: nil,
                    fachreferat: fr,
                    seminar: sem,
                    practical: prac,
                    examPoints: ep,
                    schoolType: st,
                    gradeYear: gy ?? 12
                )
                
                let subject = subjects.first(where: { $0.name == event.subjectName })
                // If dropped, skip adding this point to history ENTIRELY
                let pointIsDropped = !includeDropped && (subject?.droppedHalfYear == event.halfYear)
                
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
                    if let date = value.as(Date.self) {
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
            
            // Toggle to include/exclude dropped half-years
            // Toggle to include/exclude dropped half-years
            if hasDroppedHalfYears {
                Button(action: {
                    withAnimation {
                        includeDroppedHalfYears.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: includeDroppedHalfYears ? "eye.slash" : "eye")
                        Text(includeDroppedHalfYears ? "Streichungen ignoriert" : "Streichungen aktiv")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(includeDroppedHalfYears ? Color.secondary : Color.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(includeDroppedHalfYears ? Color.secondary.opacity(0.1) : Color.indigo.opacity(0.1))
                    )
                }
            }
        }
    }
}
