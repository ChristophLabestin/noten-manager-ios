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
    let presentationGrade: Double?
    let paperGrade: Double?
    let presentationWeight: Double?
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

enum PendingChangeAction: String, Codable {
    case add
    case update
    case delete
}

struct PendingGradeChange: Codable, Identifiable {
    let id: String
    let subjectId: String
    let action: PendingChangeAction
    let grade: Double?
    let weight: Double?
    let date: Date?
    let note: String?
    let halfYear: Int?
    let linkedExamId: String?
    let assessmentType: AssessmentType?
    let updatedAt: Date
}

struct PendingSubjectChange: Codable, Identifiable {
    let id: String
    let action: PendingChangeAction
    let subjectName: String
    let type: Int?
    let date: Date?
    let isElective: Bool?
    let gradingModeRaw: String?
    let expectedSchulaufgabenPerTerm: Int?
    let teacher: String?
    let room: String?
    let email: String?
    let alias: String?
    let order: Int?
    let examSubject: Bool?
    let examTypeRaw: String?
    let droppedHalfYear: Int?
    let clearDroppedHalfYear: Bool
    let fixedAverageHalfYear1: Double?
    let clearFixedAverageHalfYear1: Bool
    let fixedAverageHalfYear2: Double?
    let clearFixedAverageHalfYear2: Bool
    let fixedAverageYearly: Double?
    let clearFixedAverageYearly: Bool
    let updatedAt: Date
}

struct PendingExamChange: Codable, Identifiable {
    let id: String
    let action: PendingChangeAction
    let subjectName: String?
    let subjectKey: String?
    let title: String?
    let notes: String?
    let date: Date?
    let hasTime: Bool?
    let weight: Int?
    let customWeight: Double?
    let reminderAt: Date?
    let isCompleted: Bool?
    let createdAt: Date?
    let requiresGrade: Bool?
    let assessmentType: AssessmentType?
    let updatedAt: Date
}

struct PendingHomeworkChange: Codable, Identifiable {
    let id: String
    let action: PendingChangeAction
    let subjectName: String?
    let subjectKey: String?
    let title: String?
    let dueDate: Date?
    let reminderAt: Date?
    let isCompleted: Bool?
    let createdAt: Date?
    let updatedAt: Date
}

enum PendingSharedUserAction: String, Codable {
    case reminder
    case note
    case completed
    case rescheduled
}

struct PendingSharedExamUserChange: Codable, Identifiable {
    let id: String
    let action: PendingSharedUserAction
    let examId: String
    let groupId: String?
    let reminderAt: Date?
    let note: String?
    let isCompleted: Bool?
    let rescheduledDate: Date?
    let updatedAt: Date
}

struct PendingSharedHomeworkUserChange: Codable, Identifiable {
    let id: String
    let action: PendingSharedUserAction
    let homeworkId: String
    let groupId: String?
    let reminderAt: Date?
    let note: String?
    let isCompleted: Bool?
    let updatedAt: Date
}
