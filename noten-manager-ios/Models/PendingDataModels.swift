import Foundation

struct PendingGrade: Codable, Identifiable {
    let id: String
    let subjectId: String
    let grade: Double
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int?
    let linkedExamId: String?
    let createdAt: Date
    let assessmentType: AssessmentType?
}

struct PendingFachreferat: Codable {
    let subjectName: String
    let grade: Double
    let date: Date
    let note: String?
    let createdAt: Date
}

struct PendingSeminarPerformance: Codable {
    let topic: String?
    let individualPoints: Double?
    let paperPoints: Double?
    let presentationPoints: Double?
    let submissionDate: Date?
    let presentationDate: Date?
    let note: String?
    let createdAt: Date
}
