import Foundation

struct Homework: Codable, Identifiable, Hashable {
    let id: String
    let subjectName: String
    let title: String
    let dueDate: Date?
    let reminderAt: Date?
    let isCompleted: Bool
    let createdAt: Date

    var isActive: Bool {
        if isCompleted { return false }
        if let dueDate {
            return dueDate > Date()
        }
        return true
    }
}
