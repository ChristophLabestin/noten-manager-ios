// SupportAccessRequest.swift
import Foundation

/// Model representing a user's request for admin support access to their data.
struct SupportAccessRequest: Identifiable, Codable, Hashable {
    let id: String
    let message: String           // User's problem description
    let createdAt: Date
    var status: String            // "pending", "resolved"
    var resolvedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, message, createdAt, status, resolvedAt
    }
}
