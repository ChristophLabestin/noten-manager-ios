import Foundation

struct Exam: Codable, Identifiable, Hashable {
    let id: String
    let subjectName: String
    let title: String
    let date: Date
    let weight: Int?
    let reminderAt: Date?
    let isCompleted: Bool
    let createdAt: Date
    let isShared: Bool
    let creatorId: String?

    var isActive: Bool {
        if isCompleted { return false }
        return date > Date()
    }
}
