import Foundation

struct GradeCalculator {
    let subjects: [Subject]
    let gradesBySubject: [String: [GradeWithId]]
    let fachreferat: Fachreferat?
    let practicalPerformance: PracticalPerformance?
    let seminarPerformance: SeminarPerformance?
    let examPoints: [String: Double?]
    let gradeYear: Int
    let schoolType: SchoolType
    
    // --- Helper Models ---
    
    struct CalculationResult {
        let subjects: [SubjectCalculation]
        let averageBeforeDrops: Double? // Average Points 0-15
        let averageAfterDrops: Double?  // Average Points 0-15
        let finalGrade: Double?         // Schnitt 1-6
        let totalPoints: Double?
        let maxPoints: Int?
        let abiturResults: [AbiturResult]
        let fachreferatGrade: Double?
        let practicalGrade: Double?
        let seminarGrade: Double?
    }
    
    struct SubjectCalculation {
        let subjectName: String
        let average: Double? // Current actual average of grades
        let gradingMode: GradingMode?
    }

    struct AbiturResult {
        let subjectName: String
        let points: Double?
    }
    
    // --- Public API ---
    
    func calculate() -> CalculationResult {
        // 1. Prepare SubjectData for makeFobosoSummary (still needed for Abitur Prognosis parts if we want to keep them,
        // or effectively we might strictly pivot to "App Mode" display?
        // The user asked to "align it that all grades and the overall averages for the MSS value and the schnitt shows the same values as the rest of the app".
        // The "rest of the app" (Home/Insights) primarily uses the "Status" view (raw averages).
        // However, the "Report Card" often implies a "Projected Abitur" view.
        // Given the request "calculations are slightly off from what the rest of the app is showing", I will prioritize the "Status" view alignment.
        
        // 1. Prepare SubjectData for makeFobosoSummary (Strict Abitur view)
        // For Foboso Summary, we still need basic mapping but maybe we should use the same normalized grades?
        // Actually, makeFobosoSummary does its own processing? 
        // No, it takes `SubjectData` which has `grades: [GradeProtocol]`.
        // To be consistent, let's feed it the "best guess" normalized grades for both half-years.
        
        let subjectData = subjects.map { sub -> GradeCalculationService.SubjectData in
            let h1 = getGradesForHalfYear(sub, halfYear: 1)
            let h2 = getGradesForHalfYear(sub, halfYear: 2)
            return GradeCalculationService.SubjectData.from(subject: sub, grades: h1 + h2)
        }
        
        // Note: We use { _, w in w } because we already normalized weights in getGradesForHalfYear
        let weightLogic: (Int, Double) -> Double = { _, w in w }
        
        // --- 1. Subject Averages (Match HomeView) ---
        
        let subjectCalculations = subjects.map { sub -> SubjectCalculation in
            // Use GradeCalculationService.calculateHalfYearAverage to get raw values
            let v1 = GradeCalculationService.calculateHalfYearAverage(
                grades: getGradesForHalfYear(sub, halfYear: 1),
                subject: sub,
                halfYear: 1,
                effectiveGradeWeight: weightLogic
            )
            let v2 = GradeCalculationService.calculateHalfYearAverage(
                grades: getGradesForHalfYear(sub, halfYear: 2),
                subject: sub,
                halfYear: 2,
                effectiveGradeWeight: weightLogic
            )
            
            let droppedHJ = sub.droppedHalfYear
            let val1 = (droppedHJ == 1) ? nil : v1
            let val2 = (droppedHJ == 2) ? nil : v2
            
            var avg: Double?
            if let a = val1, let b = val2 {
                avg = (a + b) / 2.0
            } else if let a = val1 {
                avg = a
            } else if let b = val2 {
                avg = b
            } else {
                avg = nil
            }
            
            return SubjectCalculation(subjectName: sub.name, average: avg, gradingMode: sub.gradingMode)
        }
        
        // --- 2. Overall Average (MSS) (Match InsightsView) ---
        let avgAfter = GradeCalculationService.calculateOverallAverage(
            subjects: subjects,
            halfYearValueProvider: { subject, hy in
                GradeCalculationService.calculateHalfYearAverage(
                    grades: getGradesForHalfYear(subject, halfYear: hy),
                    subject: subject,
                    halfYear: hy,
                    effectiveGradeWeight: weightLogic
                )
            },
            droppedHalfYearProvider: { $0.droppedHalfYear },
            halfYearFilter: nil, // All half years
            fachreferat: fachreferat,
            seminar: seminarPerformance,
            practical: practicalPerformance,
            examPoints: examPoints,
            schoolType: schoolType,
            gradeYear: gradeYear
        )
        
        // --- 3. Average Before Drops ---
        let avgBefore = GradeCalculationService.calculateOverallAverage(
            subjects: subjects,
            halfYearValueProvider: { subject, hy in
                GradeCalculationService.calculateHalfYearAverage(
                    grades: getGradesForHalfYear(subject, halfYear: hy),
                    subject: subject,
                    halfYear: hy,
                    effectiveGradeWeight: weightLogic
                )
            },
            droppedHalfYearProvider: { _ in nil }, // No drops
            halfYearFilter: nil,
            fachreferat: fachreferat,
            seminar: seminarPerformance,
            practical: practicalPerformance,
            examPoints: examPoints,
            schoolType: schoolType,
            gradeYear: gradeYear
        )
        
        // --- 4. Final Grade (Schnitt) ---
        // HomeView uses: pointsToGrade(average)
        let finalGrade = avgAfter != nil ? GradeCalculationService.pointsToGrade(points: avgAfter!) : nil
        
        // --- 5. Validating "Total Points" & "Max Points" ---
        // These are tricky. "Total Points" usually implies the Abitur Sum (300-900).
        // But the "MSS" (points 0-15) is what we just calculated as avgAfter.
        // If the user wants the "Overall Average for the MSS value" to look like the app, they probably mean the 0-15 value.
        // The ReportCardView shows: "Gesamtpunkte: X / Y". This implies the Sum.
        // However, if we simply sum up the raw averages, it won't be a valid Abitur Sum.
        // Let's keep the "Foboso Summary" purely for the "Total Points / Max Points" display if available,
        // BUT make sure the main "MSS" circle uses the avgAfter we just calculated.
        
        // Recalculate strict Foboso for Total/Max stats (purely informational)
        let fSummary = GradeCalculationService.makeFobosoSummary(
            schoolType: schoolType,
            gradeYear: gradeYear,
            subjects: subjectData,
            examPoints: examPoints,
            dropSelections: Dictionary(uniqueKeysWithValues: subjects.map { ($0.name, $0.droppedHalfYear) }),
            fachreferat: fachreferat,
            practicalPerformance: practicalPerformance,
            seminarPerformance: seminarPerformance,
            effectiveGradeWeight: weightLogic
        )

        // Abitur results display
        let abiturResults = subjects.filter { $0.examSubject == true }.map { sub in
            AbiturResult(subjectName: sub.name, points: examPoints[sub.name] ?? nil)
        }
        
        // Extract practical/seminar grades for display
        // We can just use the raw values from the structs directly if available, or calculate them.
        let pracGrade: Double? = {
            if let p = practicalPerformance, !p.grades.isEmpty {
                 let limited = p.grades.sorted(by: { $0.date < $1.date }).prefix(2)
                 if !limited.isEmpty {
                     return limited.reduce(0.0) { $0 + $1.grade } / Double(limited.count)
                 }
            }
            return nil
        }()
        
        let semGrade: Double? = {
            if let s = seminarPerformance {
                return GradeCalculationService.calculateSeminarFinalPoints(s)
            }
            return nil
        }()

        return CalculationResult(
            subjects: subjectCalculations,
            averageBeforeDrops: avgBefore,
            averageAfterDrops: avgAfter, // Use the aligned MSS value
            finalGrade: finalGrade,      // Use the aligned Grade value
            totalPoints: fSummary.totalPoints, // Keep strict sum for "Gesamtpunkte" info
            maxPoints: fSummary.maxPoints,
            abiturResults: abiturResults,
            fachreferatGrade: fachreferat?.grade,
            practicalGrade: pracGrade,
            seminarGrade: semGrade
        )
    }
    // --- Private Helpers ---
    
    private struct CalculatedGrade: GradeProtocol {
        let grade: Double
        let weight: Double
        let halfYear: Int?
        let assessmentType: AssessmentType?
    }
    
    private func derivedAssessmentType(for grade: GradeWithId, gradingMode: GradingMode) -> AssessmentType {
        if let type = grade.assessmentType { return type }
        switch gradingMode {
        case .withSchulaufgaben:
            if grade.weight >= 2 { return .schulaufgabe }
            if grade.weight >= 1 { return .kurzarbeit }
            return .muendlich
        case .withoutSchulaufgaben:
            if grade.weight >= 1 { return .kurzarbeit }
            return .muendlich
        }
    }
    
    /// Replicates GradesStore.mapAssessments logic:
    /// 1. Filters by halfYear (handling legacy nil cases)
    /// 2. Rounds points to Integer
    /// 3. Normalizes weights
    /// 4. Derives assessment type
    private func getGradesForHalfYear(_ subject: Subject, halfYear: Int) -> [CalculatedGrade] {
        let rawGrades = gradesBySubject[subject.name] ?? []
        
        // 1. Filtering Logic (Legacy Fallback)
        let hasExplicitHalf = rawGrades.contains { $0.halfYear == halfYear }
        var filtered = rawGrades.filter { g in
            if hasExplicitHalf {
                return g.halfYear == halfYear
            } else {
                return g.halfYear == nil || g.halfYear == halfYear
            }
        }
        if filtered.isEmpty {
             // If nothing matched, check for nil-halfYear entries (extreme legacy fallback)
             let nilOnly = rawGrades.filter { $0.halfYear == nil }
             if !nilOnly.isEmpty {
                 filtered = nilOnly
             }
        }
        
        let mode = subject.gradingMode ?? .withoutSchulaufgaben
        
        return filtered.map { g in
            let type = derivedAssessmentType(for: g, gradingMode: mode)
            
            // 2. Rounding Logic (GradesStore does Int(g.grade.rounded()))
            let roundedGrade = g.grade.rounded()
            
            // 3. Weight Normalization
            // GradesStore: if type == .schulaufgabe { return g.weight } else { return g.weight <= 0 ? 1 : g.weight }
            let normalizedWeight: Double = {
                if type == .schulaufgabe { return g.weight }
                return g.weight <= 0 ? 1 : g.weight
            }()
            
            return CalculatedGrade(
                grade: roundedGrade,
                weight: normalizedWeight,
                halfYear: halfYear, // Force to requested halfYear so calculateHalfYearAverage accepts it
                assessmentType: type
            )
        }
    }
}
