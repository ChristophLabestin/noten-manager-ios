import Foundation

struct Exam: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let groupId: String?
    let courseId: String?
    let subjectName: String
    let subjectKey: String?
    let title: String
    let notes: String?
    let date: Date
    let hasTime: Bool
    let weight: Int?
    let customWeight: Double?
    let reminderAt: Date?
    let isCompleted: Bool
    let createdAt: Date
    let isShared: Bool
    let creatorId: String?
    let requiresGrade: Bool?

    init(
        id: String,
        groupId: String?,
        courseId: String? = nil,
        subjectName: String,
        subjectKey: String?,
        title: String,
        notes: String?,
        date: Date,
        hasTime: Bool = false,
        weight: Int?,
        customWeight: Double?,
        reminderAt: Date?,
        isCompleted: Bool,
        createdAt: Date,
        isShared: Bool,
        creatorId: String?,
        requiresGrade: Bool?
    ) {
        self.id = id
        self.groupId = groupId
        self.courseId = courseId
        self.subjectName = subjectName
        self.subjectKey = subjectKey
        self.title = title
        self.notes = notes
        self.date = date
        self.hasTime = hasTime
        self.weight = weight
        self.customWeight = customWeight
        self.reminderAt = reminderAt
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.isShared = isShared
        self.creatorId = creatorId
        self.requiresGrade = requiresGrade
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case groupId
        case courseId
        case subjectName
        case subjectKey
        case title
        case notes
        case date
        case hasTime
        case weight
        case customWeight
        case reminderAt
        case isCompleted
        case createdAt
        case isShared
        case creatorId
        case requiresGrade
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        courseId = try container.decodeIfPresent(String.self, forKey: .courseId)
        subjectName = try container.decode(String.self, forKey: .subjectName)
        subjectKey = try container.decodeIfPresent(String.self, forKey: .subjectKey)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        date = try container.decode(Date.self, forKey: .date)
        let decodedHasTime = try container.decodeIfPresent(Bool.self, forKey: .hasTime)
        if let decodedHasTime {
            hasTime = decodedHasTime
        } else {
            let calendar = Calendar.current
            hasTime = !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
        }
        weight = try container.decodeIfPresent(Int.self, forKey: .weight)
        customWeight = try container.decodeIfPresent(Double.self, forKey: .customWeight)
        reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        creatorId = try container.decodeIfPresent(String.self, forKey: .creatorId)
        requiresGrade = try container.decodeIfPresent(Bool.self, forKey: .requiresGrade)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encodeIfPresent(courseId, forKey: .courseId)
        try container.encode(subjectName, forKey: .subjectName)
        try container.encodeIfPresent(subjectKey, forKey: .subjectKey)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(date, forKey: .date)
        try container.encode(hasTime, forKey: .hasTime)
        try container.encodeIfPresent(weight, forKey: .weight)
        try container.encodeIfPresent(customWeight, forKey: .customWeight)
        try container.encodeIfPresent(reminderAt, forKey: .reminderAt)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(isShared, forKey: .isShared)
        try container.encodeIfPresent(creatorId, forKey: .creatorId)
        try container.encodeIfPresent(requiresGrade, forKey: .requiresGrade)
    }

    var isActive: Bool {
        if isCompleted { return false }
        let now = Date()
        if hasTime {
            return date > now
        }
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return endOfDay > now
    }
}
