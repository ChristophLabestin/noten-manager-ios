import Foundation

struct Exam: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String?
    let subjectName: String
    let subjectKey: String?
    let title: String
    let date: Date
    let weight: Int?
    let reminderAt: Date?
    let isCompleted: Bool
    let createdAt: Date
    let isShared: Bool
    let creatorId: String?
    let requiresGrade: Bool?

    var isActive: Bool {
        if isCompleted { return false }
        return date > Date()
    }
}
