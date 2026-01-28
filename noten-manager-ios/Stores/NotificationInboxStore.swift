import Foundation
import Combine
@preconcurrency import UserNotifications

struct NotificationInboxItem: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable {
        case exam
        case homework
        case daily
        case support
        case unknown
    }

    let id: String
    let title: String
    let body: String
    let date: Date
    let kind: Kind
    let examId: String?
    let examIds: [String]?
    let homeworkId: String?
    let homeworkIds: [String]?
    let ticketId: String?
    let groupId: String?
    let isRead: Bool

    init(
        id: String,
        title: String,
        body: String,
        date: Date,
        kind: Kind,
        examId: String?,
        examIds: [String]? = nil,
        homeworkId: String?,
        homeworkIds: [String]? = nil,
        ticketId: String? = nil,
        groupId: String?,
        isRead: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
        self.kind = kind
        self.examId = examId
        self.examIds = examIds
        self.homeworkId = homeworkId
        self.homeworkIds = homeworkIds
        self.ticketId = ticketId
        self.groupId = groupId
        self.isRead = isRead
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case date
        case kind
        case examId
        case examIds
        case homeworkId
        case homeworkIds
        case ticketId
        case groupId
        case isRead
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(Kind.self, forKey: .kind)
        examId = try container.decodeIfPresent(String.self, forKey: .examId)
        examIds = try container.decodeIfPresent([String].self, forKey: .examIds)
        homeworkId = try container.decodeIfPresent(String.self, forKey: .homeworkId)
        homeworkIds = try container.decodeIfPresent([String].self, forKey: .homeworkIds)
        ticketId = try container.decodeIfPresent(String.self, forKey: .ticketId)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(date, forKey: .date)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(examId, forKey: .examId)
        try container.encodeIfPresent(examIds, forKey: .examIds)
        try container.encodeIfPresent(homeworkId, forKey: .homeworkId)
        try container.encodeIfPresent(homeworkIds, forKey: .homeworkIds)
        try container.encodeIfPresent(ticketId, forKey: .ticketId)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encode(isRead, forKey: .isRead)
    }
}

@MainActor
final class NotificationInboxStore: ObservableObject {
    static let shared = NotificationInboxStore()

    @Published private(set) var items: [NotificationInboxItem] = []
    @Published private(set) var broadcasts: [BroadcastNotification] = []

    private let storageKey = "notification_inbox_items_v1"

    var hasItems: Bool { !items.isEmpty }
    var hasUnread: Bool { items.contains { !$0.isRead } }

    private init() {
        load()
    }

    func refreshFromDelivered() {
        Task { @MainActor in
            let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
            let items = notifications.compactMap { NotificationInboxItem.from($0) }
            mergeDelivered(items)
            await fetchBroadcasts()
        }
    }

    func fetchBroadcasts() async {
        do {
            let fetched = try await FirestoreService.shared.getActiveBroadcastNotifications()
            broadcasts = fetched
            removeBroadcastDuplicates(using: fetched)
        } catch {
            print("Error fetching broadcasts: \(error)")
        }
    }

    func record(item: NotificationInboxItem) {
        if merge(item: item) {
            sortAndPersist()
        }
    }

    func clearAll() {
        items.removeAll()
        persist()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    private func removeBroadcastDuplicates(using broadcasts: [BroadcastNotification]) {
        guard !broadcasts.isEmpty else { return }
        let keys = Set(broadcasts.map { normalizeKey(title: $0.title, body: $0.body) })
        let originalCount = items.count
        items.removeAll { item in
            item.kind == .unknown && keys.contains(normalizeKey(title: item.title, body: item.body))
        }
        if items.count != originalCount {
            persist()
        }
    }

    private func normalizeKey(title: String, body: String) -> String {
        "\(normalizeText(title))|\(normalizeText(body))"
    }

    private func normalizeText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func mergeDelivered(_ delivered: [NotificationInboxItem]) {
        var changed = false
        for item in delivered {
            changed = merge(item: item) || changed
        }
        if changed {
            sortAndPersist()
        } else {
            items.sort { $0.date > $1.date }
        }
    }

    @discardableResult
    private func merge(item: NotificationInboxItem) -> Bool {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let existing = items[index]
            let resolvedRead = existing.isRead || item.isRead
            let merged = item.isRead == resolvedRead ? item : item.withRead(resolvedRead)
            if existing != merged {
                items[index] = merged
                return true
            }
            return false
        }
        items.append(item)
        return true
    }

    private func sortAndPersist() {
        items.sort { $0.date > $1.date }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([NotificationInboxItem].self, from: data) {
            items = decoded.sorted(by: { $0.date > $1.date })
        }
    }

    func markRead(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard !items[index].isRead else { return }
        items[index] = items[index].withRead(true)
        persist()
    }
}

extension NotificationInboxItem {
    static func from(_ notification: UNNotification, markRead: Bool = false) -> NotificationInboxItem? {
        let request = notification.request
        let content = request.content
        let identifier = request.identifier
        let userInfo = content.userInfo

        let kind = Kind.from(identifier: identifier, userInfo: userInfo)
        let explicitExamId = (userInfo["examId"] as? String) ?? extractExamId(from: identifier)
        let examIds = extractExamIds(from: userInfo, fallback: explicitExamId)
        let examId = explicitExamId ?? (examIds.count == 1 ? examIds.first : nil)
        let explicitHomeworkId = (userInfo["homeworkId"] as? String) ?? extractHomeworkId(from: identifier)
        let homeworkIds = extractHomeworkIds(from: userInfo, fallback: explicitHomeworkId)
        let homeworkId = explicitHomeworkId ?? (homeworkIds.count == 1 ? homeworkIds.first : nil)
        let ticketId = userInfo["ticketId"] as? String
        let groupId = userInfo["groupId"] as? String

        let title = content.title.isEmpty ? "Benachrichtigung" : content.title
        let body = content.body

        return NotificationInboxItem(
            id: identifier,
            title: title,
            body: body,
            date: notification.date,
            kind: kind,
            examId: examId,
            examIds: examIds.isEmpty ? nil : examIds,
            homeworkId: homeworkId,
            homeworkIds: homeworkIds.isEmpty ? nil : homeworkIds,
            ticketId: ticketId,
            groupId: groupId,
            isRead: markRead
        )
    }

    func withRead(_ isRead: Bool) -> NotificationInboxItem {
        NotificationInboxItem(
            id: id,
            title: title,
            body: body,
            date: date,
            kind: kind,
            examId: examId,
            examIds: examIds,
            homeworkId: homeworkId,
            homeworkIds: homeworkIds,
            ticketId: ticketId,
            groupId: groupId,
            isRead: isRead
        )
    }

    private static func extractExamIds(from userInfo: [AnyHashable: Any], fallback: String?) -> [String] {
        if let ids = userInfo["examIds"] as? [String] {
            return ids
        }
        if let ids = userInfo["examIds"] as? [Any] {
            let strings = ids.compactMap { $0 as? String }
            if !strings.isEmpty {
                return strings
            }
        }
        if let fallback, !fallback.isEmpty {
            return [fallback]
        }
        return []
    }

    private static func extractHomeworkIds(from userInfo: [AnyHashable: Any], fallback: String?) -> [String] {
        if let ids = userInfo["homeworkIds"] as? [String] {
            return ids
        }
        if let ids = userInfo["homeworkIds"] as? [Any] {
            let strings = ids.compactMap { $0 as? String }
            if !strings.isEmpty {
                return strings
            }
        }
        if let fallback, !fallback.isEmpty {
            return [fallback]
        }
        return []
    }

    private static func extractExamId(from identifier: String) -> String? {
        guard identifier.hasPrefix("exam_") else { return nil }
        let components = identifier.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: true)
        guard components.count >= 3 else { return nil }
        return String(components[2])
    }

    private static func extractHomeworkId(from identifier: String) -> String? {
        guard identifier.hasPrefix("homework_") else { return nil }
        let components = identifier.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: true)
        guard components.count >= 3 else { return nil }
        return String(components[2])
    }
}

extension NotificationInboxItem.Kind {
    static func from(identifier: String, userInfo: [AnyHashable: Any]) -> NotificationInboxItem.Kind {
        if identifier.hasPrefix("exam_") { return .exam }
        if identifier.hasPrefix("homework_") { return .homework }
        if identifier.hasPrefix("daily_reminder_") { return .daily }
        if userInfo["examId"] != nil { return .exam }
        if userInfo["homeworkId"] != nil { return .homework }
        if userInfo["ticketId"] != nil { return .support }
        return .unknown
    }
}
