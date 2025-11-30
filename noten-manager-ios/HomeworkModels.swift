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
    let isImportedFromShare: Bool

    init(
        id: String,
        groupId: String?,
        subjectName: String,
        subjectKey: String?,
        title: String,
        dueDate: Date?,
        reminderAt: Date?,
        isCompleted: Bool,
        createdAt: Date,
        isShared: Bool,
        creatorId: String?,
        isImportedFromShare: Bool = false
    ) {
        self.id = id
        self.groupId = groupId
        self.subjectName = subjectName
        self.subjectKey = subjectKey
        self.title = title
        self.dueDate = dueDate
        self.reminderAt = reminderAt
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.isShared = isShared
        self.creatorId = creatorId
        self.isImportedFromShare = isImportedFromShare
    }

    var isActive: Bool {
        if isCompleted { return false }
        if let dueDate {
            return dueDate > Date()
        }
        return true
    }
}
