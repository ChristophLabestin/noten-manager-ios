import Foundation

struct Homework: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let groupId: String?
    let subjectName: String
    let subjectKey: String?
    let title: String
    let dueDate: Date?
    let reminderAt: Date?
    let isCompleted: Bool
    let createdAt: Date
    let isShared: Bool
    let creatorId: String?

    var isActive: Bool {
        if isCompleted { return false }
        if let dueDate {
            return dueDate > Date()
        }
        return true
    }
}
