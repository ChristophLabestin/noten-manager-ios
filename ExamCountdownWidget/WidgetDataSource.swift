import Foundation

struct WidgetExam: Codable, Identifiable, Hashable {
    let id: String
    let groupId: String?
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

    var isGeneralEvent: Bool {
        subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (requiresGrade == false)
    }

    var isActive: Bool {
        guard !isCompleted else { return false }
        let now = Date()
        if hasTime {
            return date > now
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        return endOfDay > now
    }
}

struct WidgetHomework: Codable, Identifiable, Hashable {
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

    var isActive: Bool {
        guard !isCompleted else { return false }
        if let dueDate {
            return dueDate > Date()
        }
        return true
    }
}

struct WidgetSnapshot: Codable {
    let capturedAt: Date
    let activeSchoolYearId: String?
    let exams: [WidgetExam]
    let sharedExams: [WidgetExam]
    let homeworks: [WidgetHomework]
    let sharedHomeworks: [WidgetHomework]

    var allExams: [WidgetExam] { exams + sharedExams }
    var allHomeworks: [WidgetHomework] { homeworks + sharedHomeworks }
}

enum WidgetDataSource {
    static let appGroupId = "group.de.christophlabestin.noten-manager-ios"
    private static let snapshotFileName = "offline-cache.json"

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func placeholderSnapshot(date: Date = Date()) -> WidgetSnapshot {
        let cal = Calendar.current
        let exam1 = WidgetExam(
            id: "exam-1",
            groupId: nil,
            subjectName: "Mathematik",
            subjectKey: nil,
            title: "Analysis KA",
            notes: nil,
            date: cal.date(byAdding: .day, value: 5, to: date) ?? date,
            hasTime: false,
            weight: 2,
            customWeight: nil,
            reminderAt: nil,
            isCompleted: false,
            createdAt: date,
            isShared: false,
            creatorId: nil,
            requiresGrade: true
        )
        let exam2 = WidgetExam(
            id: "exam-2",
            groupId: nil,
            subjectName: "",
            subjectKey: nil,
            title: "Elternabend",
            notes: nil,
            date: cal.date(byAdding: .day, value: 2, to: date) ?? date,
            hasTime: true,
            weight: nil,
            customWeight: nil,
            reminderAt: nil,
            isCompleted: false,
            createdAt: date,
            isShared: false,
            creatorId: nil,
            requiresGrade: false
        )
        let hw1 = WidgetHomework(
            id: "hw-1",
            groupId: nil,
            subjectName: "Deutsch",
            subjectKey: nil,
            title: "Lektüre Kapitel 3",
            dueDate: cal.date(byAdding: .day, value: 1, to: date),
            reminderAt: nil,
            isCompleted: false,
            createdAt: date,
            isShared: false,
            creatorId: nil,
            isImportedFromShare: false
        )
        let hw2 = WidgetHomework(
            id: "hw-2",
            groupId: nil,
            subjectName: "Physik",
            subjectKey: nil,
            title: "Versuchsprotokoll",
            dueDate: cal.date(byAdding: .day, value: 4, to: date),
            reminderAt: nil,
            isCompleted: false,
            createdAt: date,
            isShared: false,
            creatorId: nil,
            isImportedFromShare: false
        )
        return WidgetSnapshot(
            capturedAt: date,
            activeSchoolYearId: "2024-25",
            exams: [exam1],
            sharedExams: [exam2],
            homeworks: [hw1, hw2],
            sharedHomeworks: []
        )
    }

    private static func snapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(snapshotFileName)
    }
}

extension WidgetSnapshot {
    func upcomingExams(within days: Int, from reference: Date = Date()) -> [WidgetExam] {
        let cal = Calendar.current
        guard let upper = cal.date(byAdding: .day, value: days, to: reference) else { return [] }
        return allExams
            .filter { isWithinWindow($0, from: reference, until: upper, allowGeneral: false) }
            .sorted { $0.date < $1.date }
    }

    func remainingExams(until end: Date, from reference: Date = Date()) -> [WidgetExam] {
        allExams
            .filter { isWithinWindow($0, from: reference, until: end, allowGeneral: false) }
            .sorted { $0.date < $1.date }
    }

    func upcomingGeneralEvents(from reference: Date = Date()) -> [WidgetExam] {
        allExams
            .filter { exam in
                exam.isGeneralEvent && isWithinWindow(exam, from: reference, until: nil, allowGeneral: true)
            }
            .sorted { $0.date < $1.date }
    }

    func openHomeworks(from reference: Date = Date()) -> [WidgetHomework] {
        allHomeworks
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                let lDate = lhs.dueDate ?? lhs.reminderAt ?? lhs.createdAt
                let rDate = rhs.dueDate ?? rhs.reminderAt ?? rhs.createdAt
                return lDate < rDate
            }
    }

    private func isWithinWindow(_ exam: WidgetExam, from reference: Date, until upper: Date?, allowGeneral: Bool) -> Bool {
        guard !exam.isCompleted else { return false }
        if !allowGeneral && exam.isGeneralEvent { return false }
        let cal = Calendar.current
        if exam.hasTime {
            if exam.date < reference { return false }
            if let upper { return exam.date <= upper }
            return true
        }
        let startOfDay = cal.startOfDay(for: exam.date)
        let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? exam.date
        guard endOfDay > reference else { return false }
        if let upper { return startOfDay <= upper }
        return true
    }
}
