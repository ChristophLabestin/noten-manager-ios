// UserProfile.swift
import Foundation

struct UserProfile: Codable {
    let id: String
    let name: String
    let email: String
    let encryptionSalt: String
    
    // Course-Based Architecture
    let activeClassId: String?
    let subscribedCourseIds: [String]?
    
    // Migration Status
    var hasSeenMigrationInfo: Bool?
}
