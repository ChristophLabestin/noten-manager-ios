import Foundation

struct SupportReply: Identifiable, Codable, Hashable {
    var id: String { createdAt.description }
    let message: String
    let createdAt: Date
    let adminId: String
    let adminEmail: String
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
}
