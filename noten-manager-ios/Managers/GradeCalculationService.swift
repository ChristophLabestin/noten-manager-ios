// GradeCalculationService.swift
import Foundation

/// Unified service for calculating Abitur and school averages based on BayFOBOSO rules.
enum GradeCalculationService {
    
    struct CalculationResult {
        let examCount: Int
        let halfYearCount: Int
        let examPointsDouble: Double
        let halfYearPoints: Double
        let seminarPointsDouble: Double
        let seminarCount: Int
        let practicalPointsDouble: Double
        let practicalCount: Int
        let fachreferatPointsDouble: Double
        let fachreferatCount: Int
        let totalPoints: Double
        let totalPointsRaw: Double
        let maxPoints: Int
        let grade: Double?
        let gradeRaw: Double?
    }

    struct CalculationBreakdownItem: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let weight: Double
        let category: String
    }

    struct SubjectData: Identifiable {
        let id: String
        let subject: Subject
        let grades: [any GradeProtocol]
        let isEligible: Bool // e.g., not elective, not Fachreferat
        
        static func from(subject: Subject, grades: [any GradeProtocol]) -> SubjectData {
            let isEligible = subject.name != "Fachreferat" && !subject.isElective
            return SubjectData(id: subject.name, subject: subject, grades: grades, isEligible: isEligible)
        }
    }

    /// Calculates the FOBOSO summary (Abitur prognosis).
    static func makeFobosoSummary(
        schoolType: SchoolType,
        gradeYear: Int,
        subjects: [SubjectData],
        examPoints: [String: Double?],
        dropSelections: [String: Int?], // id -> persisted drop value (1 or 2)
        fachreferat: Fachreferat?,
        practicalPerformance: PracticalPerformance?,
        seminarPerformance: SeminarPerformance?,
        effectiveGradeWeight: (Int, Double) -> Double
    ) -> CalculationResult {
        
        let examWeightDouble: Double = (schoolType == .fos && gradeYear < 13) ? 3 : 2
        let hasSeminarRequirement = gradeYear >= 13
        
        // 1. Exam Points
        // 1. Exam Points
        var examPointsDouble = 0.0
        var examPointsRawSum = 0.0
        var actualExamCount = 0
        for s in subjects {
            if let points = examPoints[s.subject.name] {
                if let p = points {
                    let v = p.rounded(.toNearestOrAwayFromZero) // roundedExamPoints logic
                    examPointsDouble += v * examWeightDouble
                    examPointsRawSum += p * examWeightDouble
                    actualExamCount += 1
                }
            }
        }
        
        // 2. Half Year Results (HJE)
        var totalHalfYearPoints = 0.0
        var totalHalfYearPointsRaw = 0.0
        var totalHalfYearCount = 0
        for s in subjects {
            if !s.isEligible { continue }
            
            let dropValue = dropSelections[s.id] ?? nil
            let isHalfYear1Dropped = (dropValue == 1)
            let isHalfYear2Dropped = (dropValue == 2)
            
            if !isHalfYear1Dropped {
                if let raw = calculateHalfYearAverage(grades: s.grades, subject: s.subject, halfYear: 1, effectiveGradeWeight: effectiveGradeWeight) {
                    let rounded = roundHJE(raw)
                    totalHalfYearPoints += Double(rounded)
                    totalHalfYearPointsRaw += raw
                    totalHalfYearCount += 1
                }
            }
            
            if !isHalfYear2Dropped {
                if let raw = calculateHalfYearAverage(grades: s.grades, subject: s.subject, halfYear: 2, effectiveGradeWeight: effectiveGradeWeight) {
                    let rounded = roundHJE(raw)
                    totalHalfYearPoints += Double(rounded)
                    totalHalfYearPointsRaw += raw
                    totalHalfYearCount += 1
                }
            }
        }
        
        // 3. Fachreferat
        let includeFachreferat = gradeYear <= 12
        var fachreferatPoints = 0.0
        var fachreferatCount = 0
        if includeFachreferat, let fr = fachreferat {
            fachreferatPoints = fr.grade
            fachreferatCount = 1
        }
        
        // 4. Practical Performance (FOS 11/12)
        var practicalPoints = 0.0
        var practicalCount = 0
        if schoolType == .fos && gradeYear <= 12, let practical = practicalPerformance {
            // Take first two grades (1. and 2. half year equivalent)
            let limited = practical.grades.sorted(by: { $0.date < $1.date }).prefix(2)
            practicalPoints = limited.reduce(0.0) { $0 + $1.grade }
            practicalCount = limited.count
        }
        
        // 5. Seminar
        var seminarPoints = 0.0
        var seminarCount = 0
        if hasSeminarRequirement, let sem = seminarPerformance {
            if let finalPoints = calculateSeminarFinalPoints(sem) {
                seminarPoints = finalPoints * 2
                seminarCount = 2
            }
        }
        
        // Final Calculation
        let examWeightInt = Int(examWeightDouble.rounded())
        let units = actualExamCount * examWeightInt + totalHalfYearCount + fachreferatCount + practicalCount + seminarCount
        
        if units == 0 {
            return CalculationResult(
                examCount: actualExamCount, halfYearCount: totalHalfYearCount,
                examPointsDouble: 0, halfYearPoints: 0,
                seminarPointsDouble: 0, seminarCount: 0,
                practicalPointsDouble: 0, practicalCount: 0,
                fachreferatPointsDouble: 0, fachreferatCount: 0,
                totalPoints: 0, totalPointsRaw: 0, maxPoints: 0, grade: nil, gradeRaw: nil
            )
        }
        
        let maxPoints = units * 15
        let totalPoints = examPointsDouble + totalHalfYearPoints + fachreferatPoints + practicalPoints + seminarPoints
        let totalPointsRaw = examPointsRawSum + totalHalfYearPointsRaw + fachreferatPoints + practicalPoints + seminarPoints
        
        // Official Grade: calculated from ROUNDED components (totalPoints)
        let averagePointsOfficial = (totalPoints * 15.0) / Double(maxPoints)
        let gradeOfficialRaw = 17.0 / 3.0 - averagePointsOfficial / 3.0
        // Bavarian Abitur grades are truncated to one decimal place, NOT rounded.
        // We add a tiny epsilon to handle floating point precision issues.
        let gradeTruncated = floor((gradeOfficialRaw + 0.00001) * 10.0) / 10.0
        let grade = max(1.0, min(6.0, gradeTruncated))
        
        // Raw Grade: calculated from UNROUNDED components (totalPointsRaw)
        let gradeRaw = 17.0 / 3.0 - (5.0 * totalPointsRaw) / Double(maxPoints)
        
        return CalculationResult(
            examCount: actualExamCount,
            halfYearCount: totalHalfYearCount,
            examPointsDouble: examPointsDouble,
            halfYearPoints: totalHalfYearPoints,
            seminarPointsDouble: seminarPoints,
            seminarCount: seminarCount,
            practicalPointsDouble: practicalPoints,
            practicalCount: practicalCount,
            fachreferatPointsDouble: fachreferatPoints,
            fachreferatCount: fachreferatCount,
            totalPoints: totalPoints,
            totalPointsRaw: totalPointsRaw,
            maxPoints: maxPoints,
            grade: grade,
            gradeRaw: gradeRaw
        )
    }
    
    /// Calculates the average for a single subject, optionally respecting dropped half-years.
    /// Uses FOBOSO block weighting: calculates each half-year's average, then averages them.
    static func calculateSubjectAverage(
        subject: Subject,
        grades: [any GradeProtocol],
        dropValue: Int?, // 1, 2 or nil
        effectiveGradeWeight: (Int, Double) -> Double
    ) -> Double? {
        let isHalfYear1Dropped = (dropValue == 1)
        let isHalfYear2Dropped = (dropValue == 2)
        
        // Calculate each half-year average using FOBOSO block weighting
        let hy1Avg = isHalfYear1Dropped ? nil : calculateHalfYearAverage(
            grades: grades, subject: subject, halfYear: 1, effectiveGradeWeight: effectiveGradeWeight
        )
        let hy2Avg = isHalfYear2Dropped ? nil : calculateHalfYearAverage(
            grades: grades, subject: subject, halfYear: 2, effectiveGradeWeight: effectiveGradeWeight
        )
        
        // Average the half-year values
        switch (hy1Avg, hy2Avg) {
        case let (a?, b?):
            return (a + b) / 2.0
        case let (a?, nil):
            return a
        case let (nil, b?):
            return b
        default:
            return nil
        }
    }
    
    static func roundHJE(_ raw: Double) -> Int {
        guard raw.isFinite else { return 0 }
        let fraction = raw - floor(raw)
        if fraction < 0.5 {
            return Int(floor(raw))
        } else {
            return Int(ceil(raw))
        }
    }
    
    static func calculateHalfYearAverage(
        grades: [any GradeProtocol],
        subject: Subject,
        halfYear: Int,
        effectiveGradeWeight: (Int, Double) -> Double
    ) -> Double? {
        let filtered = grades.filter { $0.halfYear == halfYear }
        guard !filtered.isEmpty else { return nil }
        
        // Handle FOBOSO block weighting if applicable
        // FOBOSO: Blocks = ONLY Schulaufgaben. Sonstige = Kurzarbeiten + mündliche (weighted average as one block)
        let hasSchulaufgabe = filtered.contains(where: { $0.assessmentType == .schulaufgabe })
        let isHauptfach = subject.gradingMode == .withSchulaufgaben || hasSchulaufgabe || (subject.gradingMode == nil && subject.type == 1)
        
        if isHauptfach {
            // Block grades = ONLY Schulaufgaben (each SA is its own block)
            let blockGrades = filtered.filter { $0.assessmentType == .schulaufgabe }
            // Sonstige = everything else (Kurzarbeiten + mündlich) averaged together as ONE block
            let otherGrades = filtered.filter { $0.assessmentType != .schulaufgabe }
            
            var otherTotal = 0.0
            var otherWeightSum = 0.0
            
            for g in otherGrades {
                let w = effectiveGradeWeight(subject.type, g.weight)
                guard w > 0 else { continue }
                otherTotal += g.grade * w
                otherWeightSum += w
            }
            
            let otherAvg = otherWeightSum > 0 ? otherTotal / otherWeightSum : nil
            let blockPoints = blockGrades.map { $0.grade }
            
            if let other = otherAvg, !blockPoints.isEmpty {
                // FOBOSO Formula: (SonstigeAvg + SA1 + SA2 + ...) / (1 + AnzahlSAs)
                let blocks = Double(blockPoints.count) + 1.0
                return (other + blockPoints.reduce(0, +)) / blocks
            } else if let other = otherAvg {
                return other
            } else if !blockPoints.isEmpty {
                return blockPoints.reduce(0, +) / Double(blockPoints.count)
            }
            return nil
        } else {
            // Simple weighted average for subjects without Schulaufgaben
            var total = 0.0
            var totalWeight = 0.0
            for g in filtered {
                let w = effectiveGradeWeight(subject.type, g.weight)
                guard w > 0 else { continue }
                total += g.grade * w
                totalWeight += w
            }
            guard totalWeight > 0 else { return nil }
            let avg = total / totalWeight
            if avg.isNaN || avg.isInfinite { return nil }
            return max(0, min(15, avg))
        }
    }
    
    static func calculateSeminarFinalPoints(_ sem: SeminarPerformance) -> Double? {
        let hasZero = [sem.individualPoints, sem.paperPoints, sem.presentationPoints].contains { $0 == 0 }
        if hasZero { return 0 }
        guard let individual = sem.individualPoints,
              let paper = sem.paperPoints,
              let presentation = sem.presentationPoints else { return nil }
        let raw = (individual + presentation + (2 * paper)) / 4.0
        let rounded = raw.rounded(.toNearestOrAwayFromZero)
        return max(0, min(15, rounded))
    }
    
    // MARK: - Overall Average (MSS-style)
    
    /// Calculates the overall half-year-based average (MSS style) for display purposes.
    /// This averages the half-year values across eligible subjects (excluding electives and Fachreferat).
    /// - Parameters:
    ///   - subjects: All subjects to consider
    ///   - halfYearValueProvider: Closure that returns the half-year value for a subject and half-year (1 or 2)
    ///   - droppedHalfYearProvider: Optional closure that returns the dropped half-year (1 or 2) for a subject, or nil if none dropped
    ///   - halfYearFilter: Optional filter - nil for both half-years, 1 for first only, 2 for second only
    /// - Returns: The overall average or nil if no data available
    static func calculateOverallAverage(
        subjects: [Subject],
        halfYearValueProvider: (Subject, Int) -> Double?,
        droppedHalfYearProvider: ((Subject) -> Int?)? = nil,
        halfYearFilter: Int? = nil,
        fachreferat: Fachreferat? = nil,
        seminar: SeminarPerformance? = nil,
        practical: PracticalPerformance? = nil,
        examPoints: [String: Double?] = [:],
        schoolType: SchoolType? = nil,
        gradeYear: Int? = nil,
        useRawValues: Bool = true
    ) -> Double? {
        let eligibleSubjects = subjects.filter { 
            $0.name != "Fachreferat" && !$0.isElective 
        }
        
        var total = 0.0
        var count = 0.0
        
        let examWeight: Double = (schoolType == .fos) ? (Double(gradeYear ?? 12) >= 13 ? 2 : 2) : 2
        
        for subject in eligibleSubjects {
            let droppedHalf = droppedHalfYearProvider?(subject)
            
            switch halfYearFilter {
            case 1:
                // If requesting half-year 1 but it's dropped, skip
                if droppedHalf != 1, let hv = halfYearValueProvider(subject, 1) {
                    let val = useRawValues ? hv : Double(roundHJE(hv))
                    total += val
                    count += 1
                }
            case 2:
                // If requesting half-year 2 but it's dropped, skip
                if droppedHalf != 2, let hv = halfYearValueProvider(subject, 2) {
                    let val = useRawValues ? hv : Double(roundHJE(hv))
                    total += val
                    count += 1
                }
            default: // nil or any other = both half-years (respecting drops)
                if droppedHalf != 1, let hv1 = halfYearValueProvider(subject, 1) {
                    let val = useRawValues ? hv1 : Double(roundHJE(hv1))
                    total += val
                    count += 1
                }
                if droppedHalf != 2, let hv2 = halfYearValueProvider(subject, 2) {
                    let val = useRawValues ? hv2 : Double(roundHJE(hv2))
                    total += val
                    count += 1
                }
            }
        }
        
        // Add extra components ONLY for overall average (halfYearFilter == nil)
        if halfYearFilter == nil {
            // 1. Fachreferat (Weight: 1 Subject Equivalent)
            if let fr = fachreferat {
                total += fr.grade
                count += 1
            }
            
            // 2. fpA (Praktikum) - Only in FOS 11 (Weight: 1 Subject Equivalent)
            if schoolType == .fos && gradeYear == 11, let practical = practical {
                let limited = practical.grades.sorted(by: { $0.date < $1.date }).prefix(2)
                if !limited.isEmpty {
                    let avg = limited.reduce(0.0) { $0 + $1.grade } / Double(limited.count)
                    total += avg
                    count += 1
                }
            }
            
            // 3. Seminar (Weight: 2 Subject Equivalent in 13th grade)
            if gradeYear == 13, let sem = seminar {
                if let finalPoints = calculateSeminarFinalPoints(sem) {
                    total += finalPoints * 2.0
                    count += 2.0
                }
            }
            
            // 4. Abitur Exams (Weight: examWeight defined above)
            for subject in subjects {
                if let points = examPoints[subject.name], let p = points {
                    let v = useRawValues ? p : p.rounded(.toNearestOrAwayFromZero)
                    total += v * examWeight
                    count += examWeight
                }
            }
        }
        
        guard count > 0 else { return nil }
        return total / count
    }

    static func calculateOverallAverageDetailed(
        subjects: [Subject],
        halfYearValueProvider: (Subject, Int) -> Double?,
        droppedHalfYearProvider: ((Subject) -> Int?)? = nil,
        halfYearFilter: Int? = nil,
        fachreferat: Fachreferat? = nil,
        seminar: SeminarPerformance? = nil,
        practical: PracticalPerformance? = nil,
        examPoints: [String: Double?] = [:],
        schoolType: SchoolType? = nil,
        gradeYear: Int? = nil
    ) -> (items: [CalculationBreakdownItem], total: Double, divisor: Double, average: Double?) {
        var items: [CalculationBreakdownItem] = []
        let eligibleSubjects = subjects.filter { 
            $0.name != "Fachreferat" && !$0.isElective 
        }
        
        var total = 0.0
        var count = 0.0
        
        let examWeight: Double = (schoolType == .fos) ? (Double(gradeYear ?? 12) >= 13 ? 2 : 2) : 2
        
        for subject in eligibleSubjects {
            let droppedHalf = droppedHalfYearProvider?(subject)
            
            switch halfYearFilter {
            case 1:
                if droppedHalf != 1, let v = halfYearValueProvider(subject, 1) {
                    items.append(CalculationBreakdownItem(label: "\(subject.name) (Hj. 1)", value: v, weight: 1.0, category: "Fächer"))
                    total += v
                    count += 1
                }
            case 2:
                if droppedHalf != 2, let v = halfYearValueProvider(subject, 2) {
                    items.append(CalculationBreakdownItem(label: "\(subject.name) (Hj. 2)", value: v, weight: 1.0, category: "Fächer"))
                    total += v
                    count += 1
                }
            default:
                if droppedHalf != 1, let v1 = halfYearValueProvider(subject, 1) {
                    items.append(CalculationBreakdownItem(label: "\(subject.name) (Hj. 1)", value: v1, weight: 1.0, category: "Fächer"))
                    total += v1
                    count += 1
                }
                if droppedHalf != 2, let v2 = halfYearValueProvider(subject, 2) {
                    items.append(CalculationBreakdownItem(label: "\(subject.name) (Hj. 2)", value: v2, weight: 1.0, category: "Fächer"))
                    total += v2
                    count += 1
                }
            }
        }
        
        if halfYearFilter == nil {
            if let fr = fachreferat {
                items.append(CalculationBreakdownItem(label: "Fachreferat", value: fr.grade, weight: 1.0, category: "Zusatzleistung"))
                total += fr.grade
                count += 1
            }
            
            if schoolType == .fos && gradeYear == 11, let practical = practical {
                let limited = practical.grades.sorted(by: { $0.date < $1.date }).prefix(2)
                if !limited.isEmpty {
                    let avg = limited.reduce(0.0) { $0 + $1.grade } / Double(limited.count)
                    items.append(CalculationBreakdownItem(label: "Praktikum (fpA)", value: avg, weight: 1.0, category: "Zusatzleistung"))
                    total += avg
                    count += 1
                }
            }
            
            if gradeYear == 13, let sem = seminar {
                if let finalPoints = calculateSeminarFinalPoints(sem) {
                    let val = finalPoints * 2.0
                    items.append(CalculationBreakdownItem(label: "Seminar", value: val, weight: 2.0, category: "Zusatzleistung"))
                    total += val
                    count += 2.0
                }
            }
            
            for subject in subjects {
                if let points = examPoints[subject.name], let p = points {
                    let v = p.rounded(.toNearestOrAwayFromZero)
                    items.append(CalculationBreakdownItem(label: "Abiprüfung: \(subject.name)", value: v * examWeight, weight: examWeight, category: "Prüfungen"))
                    total += v * examWeight
                    count += examWeight
                }
            }
        }
        
        return (items: items, total: total, divisor: count, average: count > 0 ? total / count : nil)
    }

    static func pointsToGrade(points: Double) -> Double {
        let grade = (17.0 - points) / 3.0
        return max(1.0, min(6.0, grade))
    }
    
    // MARK: - Droppable Half-Years (FOBOSO)
    
    private static func requiredHalfYearResults(schoolType: SchoolType, grade: Int) -> Int {
        if grade >= 13 {
            return 16 // FOS 13 & BOS 13
        } else if schoolType == .bos {
            return 17 // BOS 12
        } else {
            return 25 // FOS 12 (includes 11/2)
        }
    }
    
    static func calculateMaxDroppableHalfYears(
        subjects: [Subject],
        schoolType: SchoolType,
        grade: Int
    ) -> Int {
        // Filter subjects that contribute to the "Einbringung" (Eligible subjects)
        // Fachreferat, Seminar, Praktikum do NOT count towards the HJE total.
        let eligibleSubjects = subjects.filter { 
            $0.name != "Fachreferat" && $0.name != "Praktikum" && !$0.isElective 
        }
        
        // Total potential results = Subject Count * 2 (S1/S2 per subject)
        // Note: For FOS 12, this technically assumes 11/2 results exist or counted. 
        // FOBOSO allows dropping max 1 per subject.
        // We use a simplified model: Total Available - Required.
        // But limited by "Max 1 per subject". 
        // For now, simpler "total - required" is good enough as a global cap.
        
        let totalPotential = eligibleSubjects.count * 2
        let required = requiredHalfYearResults(schoolType: schoolType, grade: grade)
        
        return max(0, totalPotential - required)
    }
}

