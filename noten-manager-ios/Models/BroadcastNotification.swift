import Foundation
import FirebaseFirestore

struct BroadcastNotification: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let createdAt: Date
    let platforms: String // "all", "ios", "android"
    let isActive: Bool
    let priority: Int
    let type: String // "announcement", "maintenance", "update", "important"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case createdAt
        case platforms
        case isActive
        case priority
        case type
    }
}
