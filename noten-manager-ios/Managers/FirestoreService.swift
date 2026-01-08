// FirestoreService.swift
import Foundation
@preconcurrency import FirebaseFirestore

final class FirestoreService {
    static let shared = FirestoreService()
    private init() {}

    private let db = Firestore.firestore()

    func setUserProfile(profile: UserProfile, onboardingCompleted: Bool = true) async throws {
        try await db.collection("users").document(profile.id).setData([
            "id": profile.id,
            "name": profile.name,
            "email": profile.email,
            "encryptionSalt": profile.encryptionSalt,
            "onboardingCompleted": onboardingCompleted
        ], merge: true)
    }

    func getUserProfile(uid: String) async throws -> UserProfile? {
        let snap = try await db.collection("users").document(uid).getDocument()
        guard let data = snap.data(),
              let id = data["id"] as? String,
              let name = data["name"] as? String,
              let email = data["email"] as? String,
              let encryptionSalt = data["encryptionSalt"] as? String
        else {
            return nil
        }
        return UserProfile(id: id, name: name, email: email, encryptionSalt: encryptionSalt)
    }

    func createSupportTicket(userId: String, email: String?, subject: String, message: String) async throws {
        var data: [String: Any] = [
            "userId": userId,
            "subject": subject,
            "message": message,
            "createdAt": Timestamp(date: Date()),
            "status": "open"
        ]
        if let email, !email.isEmpty {
            data["email"] = email
        }
        try await db.collection("supportTickets").addDocument(data: data)
    }

    func createAnonymousErrorLog(payload: AnonymousErrorLogPayload) {
        let data = payload.firestoreData()
        _ = db.collection("anonymousErrorLogs").addDocument(data: data)
    }

    // MARK: - Support Access

    /// Grants admin access for 24 hours and creates a support access request
    func grantAdminAccess(userId: String, message: String, notifyByPush: Bool, notifyByEmail: Bool, email: String?, allowGradeDecryption: Bool) async throws -> String {
        let expiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
        let requestId = UUID().uuidString
        
        // Update user document with access flags
        try await db.collection("users").document(userId).setData([
            "adminAccessGranted": true,
            "adminAccessExpiresAt": Timestamp(date: expiresAt)
        ], merge: true)
        
        // Create support access request document with notification preferences
        var requestData: [String: Any] = [
            "id": requestId,
            "message": message,
            "createdAt": Timestamp(date: Date()),
            "status": "pending",
            "notifyByPush": notifyByPush,
            "notifyByEmail": notifyByEmail,
            "allowGradeDecryption": allowGradeDecryption
        ]
        if let email, !email.isEmpty {
            requestData["notificationEmail"] = email
        }
        try await db.collection("users").document(userId)
            .collection("supportAccessRequests").document(requestId).setData(requestData)
        
        return requestId
    }

    /// Revokes admin access immediately
    func revokeAdminAccess(userId: String) async throws {
        try await db.collection("users").document(userId).setData([
            "adminAccessGranted": false,
            "adminAccessExpiresAt": FieldValue.delete()
        ], merge: true)
    }

    /// Marks a support access request as resolved (called by admin)
    func markSupportAccessResolved(userId: String, requestId: String) async throws {
        try await db.collection("users").document(userId)
            .collection("supportAccessRequests").document(requestId).setData([
                "status": "resolved",
                "resolvedAt": Timestamp(date: Date())
            ], merge: true)
    }

    // MARK: - Notification Tokens

    func updateFcmToken(userId: String, token: String) async {
        do {
            try await db.collection("users").document(userId).updateData([
                "fcmTokens": FieldValue.arrayUnion([token]),
                "lastTokenUpdate": Timestamp(date: Date())
            ])
        } catch {
            print("Error updating FCM token: \(error)")
            // If document doesn't exist, create it (partially)
            try? await db.collection("users").document(userId).setData([
                "fcmTokens": [token],
                "lastTokenUpdate": Timestamp(date: Date())
            ], merge: true)
        }
    }
}
