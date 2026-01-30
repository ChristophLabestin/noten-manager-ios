import Foundation

struct SupportReply: Identifiable, Codable, Hashable {
    var id: String { createdAt.description }
    let message: String
    let createdAt: Date
    let adminId: String
    let adminEmail: String
}

struct SupportUserUpdate: Identifiable, Codable, Hashable {
    var id: String { "\(createdAt.timeIntervalSince1970)-\(userId ?? "user")" }
    let message: String
    let createdAt: Date
    let userId: String?
}

struct SupportTicket: Identifiable, Codable, Hashable {
    let id: String
    let userId: String
    let email: String?
    let subject: String
    let message: String
    let createdAt: Date
    var status: String // "open", "resolved", "closed"
    var replies: [SupportReply]?
    var userUpdates: [SupportUserUpdate]?
}

extension SupportTicket {
    var lastActivityAt: Date {
        var dates: [Date] = [createdAt]
        if let replies {
            dates.append(contentsOf: replies.map { $0.createdAt })
        }
        if let userUpdates {
            dates.append(contentsOf: userUpdates.map { $0.createdAt })
        }
        return dates.max() ?? createdAt
    }
    
    var latestPreviewMessage: String {
        var entries: [(Date, String)] = [(createdAt, message)]
        if let replies {
            entries.append(contentsOf: replies.map { ($0.createdAt, $0.message) })
        }
        if let userUpdates {
            entries.append(contentsOf: userUpdates.map { ($0.createdAt, $0.message) })
        }
        return entries.max(by: { $0.0 < $1.0 })?.1 ?? message
    }
}
