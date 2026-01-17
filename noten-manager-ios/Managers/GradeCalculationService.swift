// GradeCalculationService.swift
import Foundation
import SwiftUI

/// Unified service for calculating Abitur and school averages based on BayFOBOSO rules.
enum GradeCalculationService {
    
    struct CalculationResult {
        let examCount: Int
        let halfYearCount: Int
        let examPointsDouble: Double
        let halfYearPoints: Double
        let seminarPointsDouble: Double
        let practicalPointsDouble: Double
        let fachreferatPointsDouble: Double
        let totalPoints: Double
        let maxPoints: Int
        let grade: Double?
        let gradeRaw: Double?
    }

    struct SubjectData: Identifiable {
        let id: String
        let subject: Subject
        let grades: [GradeWithId]
        let isEligible: Bool // e.g., not elective, not Fachreferat
        
        static func from(subject: Subject, grades: [GradeWithId]) -> SubjectData {
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
        
        let examWeightDouble: Double = (schoolType == .fos) ? (gradeYear >= 13 ? 2 : 3) : 2
        let hasSeminarRequirement = gradeYear >= 13
        
        // 1. Exam Points
        var examPointsDouble = 0.0
        var actualExamCount = 0
        for s in subjects {
            if let points = examPoints[s.subject.name] {
                if let p = points {
                    let v = p.rounded(.toNearestOrAwayFromZero) // roundedExamPoints logic
                    examPointsDouble += v * examWeightDouble
                    actualExamCount += 1
                }
            }
        }
        
        // 2. Half Year Results (HJE)
        var totalHalfYearPoints = 0.0
        var totalHalfYearCount = 0
        for s in subjects {
            if !s.isEligible { continue }
            
            let dropValue = dropSelections[s.id] ?? nil
            let isHalfYear1Dropped = (dropValue == 1)
            let isHalfYear2Dropped = (dropValue == 2)
            
            if !isHalfYear1Dropped {
                if let avg = calculateHalfYearAverage(grades: s.grades, subjectType: s.subject.type, halfYear: 1, effectiveGradeWeight: effectiveGradeWeight) {
                    totalHalfYearPoints += avg
                    totalHalfYearCount += 1
                }
            }
            
            if !isHalfYear2Dropped {
                if let avg = calculateHalfYearAverage(grades: s.grades, subjectType: s.subject.type, halfYear: 2, effectiveGradeWeight: effectiveGradeWeight) {
                    totalHalfYearPoints += avg
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
                examPointsDouble: 0, halfYearPoints: 0, seminarPointsDouble: 0,
                practicalPointsDouble: 0, fachreferatPointsDouble: 0,
                totalPoints: 0, maxPoints: 0, grade: nil, gradeRaw: nil
            )
        }
        
        let maxPoints = units * 15
        let totalPoints = examPointsDouble + totalHalfYearPoints + fachreferatPoints + practicalPoints + seminarPoints
        let gradeRaw = 17.0 / 3.0 - (5.0 * totalPoints) / Double(maxPoints)
        let gradeRounded = (gradeRaw * 10.0).rounded(.toNearestOrAwayFromZero) / 10.0
        let grade = max(1, min(6, gradeRounded))
        
        return CalculationResult(
            examCount: actualExamCount,
            halfYearCount: totalHalfYearCount,
            examPointsDouble: examPointsDouble,
            halfYearPoints: totalHalfYearPoints,
            seminarPointsDouble: seminarPoints,
            practicalPointsDouble: practicalPoints,
            fachreferatPointsDouble: fachreferatPoints,
            totalPoints: totalPoints,
            maxPoints: maxPoints,
            grade: grade,
            gradeRaw: gradeRaw
        )
    }
    
    /// Calculates the average for a single subject, optionally respecting dropped half-years.
    static func calculateSubjectAverage<T: GradeProtocol>(
        subject: Subject,
        grades: [T],
        dropValue: Int?, // 1, 2 or nil
        effectiveGradeWeight: (Int, Double) -> Double
    ) -> Double? {
        let isHalfYear1Dropped = (dropValue == 1)
        let isHalfYear2Dropped = (dropValue == 2)
        
        var total = 0.0
        var totalWeight = 0.0
        
        for g in grades {
            if g.halfYear == 1 && isHalfYear1Dropped { continue }
            if g.halfYear == 2 && isHalfYear2Dropped { continue }
            
            let w = effectiveGradeWeight(subject.type, g.weight)
            total += g.grade * w
            totalWeight += w
        }
        
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }
    
    static func calculateHalfYearAverage<T: GradeProtocol>(
        grades: [T],
        subjectType: Int,
        halfYear: Int,
        effectiveGradeWeight: (Int, Double) -> Double
    ) -> Double? {
        let filtered = grades.filter { $0.halfYear == halfYear }
        guard !filtered.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in filtered {
            let w = effectiveGradeWeight(subjectType, g.weight)
            guard w > 0 else { continue }
            total += g.grade * w
            totalWeight += w
        }
        guard totalWeight > 0 else { return nil }
        let avg = total / totalWeight
        if avg.isNaN || avg.isInfinite { return nil }
        return max(0, min(15, avg))
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
        halfYearFilter: Int? = nil
    ) -> Double? {
        let eligibleSubjects = subjects.filter { 
            $0.name != "Fachreferat" && !$0.isElective 
        }
        
        var total = 0.0
        var count = 0.0
        
        for subject in eligibleSubjects {
            let droppedHalf = droppedHalfYearProvider?(subject)
            let value: Double?
            
            switch halfYearFilter {
            case 1:
                // If requesting half-year 1 but it's dropped, skip
                if droppedHalf == 1 {
                    value = nil
                } else {
                    value = halfYearValueProvider(subject, 1)
                }
            case 2:
                // If requesting half-year 2 but it's dropped, skip
                if droppedHalf == 2 {
                    value = nil
                } else {
                    value = halfYearValueProvider(subject, 2)
                }
            default: // nil or any other = both half-years (respecting drops)
                let v1 = droppedHalf == 1 ? nil : halfYearValueProvider(subject, 1)
                let v2 = droppedHalf == 2 ? nil : halfYearValueProvider(subject, 2)
                switch (v1, v2) {
                case let (a?, b?):
                    value = (a + b) / 2.0
                case let (a?, nil):
                    value = a
                case let (nil, b?):
                    value = b
                default:
                    value = nil
                }
            }
            
            if let v = value {
                total += v
                count += 1
            }
        }
        
        guard count > 0 else { return nil }
        return total / count
    }
}

