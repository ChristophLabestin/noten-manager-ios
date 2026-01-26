// UserProfile.swift
import Foundation

struct UserProfile: Codable {
    let id: String
    let name: String
    let email: String
    let encryptionSalt: String
    
    // Course-Based Architecture
    // Course-Based Architecture
    var activeClassId: String? = nil
    var subscribedCourseIds: [String]? = nil
    
    // Migration Status
    var hasSeenMigrationInfo: Bool? = false
    // Registration & Purchase Metadata
    var registeredInVersion: String? = nil
    var registrationPlatform: String? = nil
    var purchaseType: String? = nil
    var subscriptionTier: String? = nil
}
