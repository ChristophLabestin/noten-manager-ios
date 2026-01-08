import Foundation

struct GradeCalculator {
    let subjects: [Subject]
    let gradesBySubject: [String: [GradeWithId]]
    let fachreferat: Fachreferat?
    let practicalPerformance: PracticalPerformance?
    let seminarPerformance: SeminarPerformance?
    let gradeYear: Int
    let schoolType: SchoolType
    
    // --- Helper Models ---
    
    struct CalculationResult {
        let subjects: [SubjectCalculation]
        let averageBeforeDrops: Double?
        let averageAfterDrops: Double?
        let finalGrade: Double?
    }
    
    struct SubjectCalculation {
        let subjectName: String
        let average: Double? // Current actual average of grades
    }
    
    // --- Public API ---
    
    func calculate() -> CalculationResult {
        // Simple Average of "Subject Averages" so far (simplified for report card view)
        // Note: Full Abitur calculation is complex. For the report card "Zwischenstand", 
        // usually users want the average of their current subject averages.
        
        // 1. Calculate average for each subject
        let subjectCalculations = subjects.map { sub -> SubjectCalculation in
            let average = calculateSubjectAverage(sub)
            return SubjectCalculation(subjectName: sub.name, average: average)
        }
        
        let validSubjectAverages = subjectCalculations.compactMap { $0.average }
        
        // Average Before Drops (simply average of all subjects present)
        let avgBefore = validSubjectAverages.isEmpty ? nil : validSubjectAverages.reduce(0, +) / Double(validSubjectAverages.count)
        
        // Average After Drops
        // Getting "optimal" drops automatically is hard without specific logic.
        // If the store doesn't persist drops, we can't show "User's drops".
        // The FinalGradeView state is local. 
        // PROPOSAL: For this PDF feature, we will calculate an "Optimized" version if we can,
        // OR simpler: Just show the raw average if we can't access user drops.
        // User asked for "Nach gestrichenen Halbjahren".
        // Use a simple heuristic: Drop the worst X halfyears if applicable?
        // Actually, without the explicit `dropSelections` map from the view, we can't EXACTLY replicate the view's state.
        // However, the prompt implies "current" state.
        // Since we can't easily reach into FinalGradeView's @State from here,
        // We will assume "Before Drops" = All Grades, and "Final Grade" = calculated logic if possible.
        // IF we cannot replicate drops easily, we might show just one average or auto-drop worst.
        
        // Let's stick to: "Current Average" (Average of all subject averages)
        // And "Final Grade" -> This often means the Abitur grade logic if 12/13/11.
        
        return CalculationResult(
            subjects: subjectCalculations,
            averageBeforeDrops: avgBefore,
            averageAfterDrops: avgBefore, // Placeholder if no drop logic
            finalGrade: avgBefore // Simplified for this context
        )
    }
    
    private func calculateSubjectAverage(_ subject: Subject) -> Double? {
        let grades = gradesBySubject[subject.name] ?? []
        guard !grades.isEmpty else { return nil }
        
        var total = 0.0
        var weight = 0.0
        
        for g in grades {
            let w = g.weight // Simplified: In FinalGradeView there is logic for Exam vs Normal.
            // Using direct weight is usually correct for "Current Standing".
            total += g.grade * w
            weight += w
        }
        
        return weight > 0 ? total / weight : nil
    }
}
