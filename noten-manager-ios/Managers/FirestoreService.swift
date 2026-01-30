import Foundation
@preconcurrency import FirebaseFirestore
import FirebaseAuth

final class FirestoreService {
    static let shared = FirestoreService()
    private init() {}

    private let db = Firestore.firestore()

    func setUserProfile(profile: UserProfile, onboardingCompleted: Bool = true) async throws {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        var data: [String: Any] = [
            "id": profile.id,
            "name": profile.name,
            "email": profile.email,
            "encryptionSalt": profile.encryptionSalt,
            "onboardingCompleted": onboardingCompleted
        ]
        if let registeredInVersion = profile.registeredInVersion {
            data["registeredInVersion"] = registeredInVersion
        }
        if let registrationPlatform = profile.registrationPlatform {
            data["registrationPlatform"] = registrationPlatform
        }
        if let purchaseType = profile.purchaseType {
            data["purchaseType"] = purchaseType
        }
        if let subscriptionTier = profile.subscriptionTier {
            data["subscriptionTier"] = subscriptionTier
        }
        try await db.collection("users").document(profile.id).setData(data, merge: true)
    }
    
    func updateUserProfileField(userId: String, field: String, value: Any) async throws {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        try await db.collection("users").document(userId).updateData([
            field: value
        ])
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
        return UserProfile(
            id: id,
            name: name,
            email: email,
            encryptionSalt: encryptionSalt,
            activeClassId: data["activeClassId"] as? String,
            subscribedCourseIds: data["subscribedCourseIds"] as? [String],
            hasSeenMigrationInfo: data["hasSeenMigrationInfo"] as? Bool,
            registeredInVersion: data["registeredInVersion"] as? String,
            registrationPlatform: data["registrationPlatform"] as? String,
            purchaseType: data["purchaseType"] as? String,
            subscriptionTier: data["subscriptionTier"] as? String
        )
    }

    func createSupportTicket(userId: String, email: String?, subject: String, message: String) async throws {
        if OfflineModeManager.shared.isOfflineModeActive { return }
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

    func getUserSupportTickets(userId: String) async throws -> [SupportTicket] {
        let baseQuery = db.collection("supportTickets").whereField("userId", isEqualTo: userId)
        do {
            let snap = try await baseQuery
                .order(by: "createdAt", descending: true)
                .getDocuments()
            var tickets = snap.documents.compactMap { parseSupportTicket(from: $0) }
            if tickets.isEmpty {
                let legacySnap = try await db.collection("users").document(userId)
                    .collection("supportTickets")
                    .order(by: "createdAt", descending: true)
                    .getDocuments()
                let legacy = legacySnap.documents.compactMap { parseSupportTicket(from: $0) }
                if !legacy.isEmpty {
                    tickets = legacy
                }
            }
            return tickets
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.failedPrecondition.rawValue {
                let snap = try await baseQuery.getDocuments()
                var tickets = snap.documents.compactMap { parseSupportTicket(from: $0) }
                if tickets.isEmpty {
                    let legacySnap = try await db.collection("users").document(userId)
                        .collection("supportTickets")
                        .getDocuments()
                    let legacy = legacySnap.documents.compactMap { parseSupportTicket(from: $0) }
                    if !legacy.isEmpty {
                        tickets = legacy
                    }
                }
                return tickets.sorted { $0.createdAt > $1.createdAt }
            }
            throw error
        }
    }

    func getSupportTicket(ticketId: String, userId: String? = nil) async throws -> SupportTicket? {
        let doc = try await db.collection("supportTickets").document(ticketId).getDocument()
        guard let ticket = parseSupportTicket(from: doc) else { return nil }
        if let userId, ticket.userId != userId { return nil }
        return ticket
    }

    func addSupportTicketUpdate(ticketId: String, userId: String, message: String) async throws {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        let now = Timestamp(date: Date())
        let update: [String: Any] = [
            "message": message,
            "createdAt": now,
            "userId": userId
        ]
        try await db.collection("supportTickets").document(ticketId).setData([
            "userUpdates": FieldValue.arrayUnion([update]),
            "status": "open",
            "updatedAt": now,
            "lastUserUpdateAt": now,
            "lastUserUpdateUserId": userId
        ], merge: true)
    }

    func createAnonymousErrorLog(payload: AnonymousErrorLogPayload) {
        let data = payload.firestoreData()
        _ = db.collection("anonymousErrorLogs").addDocument(data: data)
    }

    private func parseSupportTicket(from doc: DocumentSnapshot) -> SupportTicket? {
        let data = doc.data() ?? [:]
        guard let userId = data["userId"] as? String,
              let subject = data["subject"] as? String,
              let message = data["message"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let status = data["status"] as? String else {
            return nil
        }
        
        let rawReplies = data["replies"] as? [[String: Any]] ?? []
        let replies: [SupportReply] = rawReplies.compactMap { r in
            guard let rMsg = r["message"] as? String,
                  let rDate = (r["createdAt"] as? Timestamp)?.dateValue(),
                  let rAdminId = r["adminId"] as? String,
                  let rAdminEmail = r["adminEmail"] as? String else {
                return nil
            }
            return SupportReply(message: rMsg, createdAt: rDate, adminId: rAdminId, adminEmail: rAdminEmail)
        }
        
        let rawUserUpdates = data["userUpdates"] as? [[String: Any]] ?? []
        let userUpdates: [SupportUserUpdate] = rawUserUpdates.compactMap { u in
            guard let uMsg = u["message"] as? String,
                  let uDate = (u["createdAt"] as? Timestamp)?.dateValue() else {
                return nil
            }
            return SupportUserUpdate(message: uMsg, createdAt: uDate, userId: u["userId"] as? String)
        }
        
        return SupportTicket(
            id: doc.documentID,
            userId: userId,
            email: data["email"] as? String,
            subject: subject,
            message: message,
            createdAt: createdAt,
            status: status,
            replies: replies.isEmpty ? nil : replies,
            userUpdates: userUpdates.isEmpty ? nil : userUpdates
        )
    }

    // MARK: - Support Access

    /// Grants admin access for 24 hours and creates a support access request
    func grantAdminAccess(userId: String, message: String, notifyByPush: Bool, notifyByEmail: Bool, email: String?, allowGradeDecryption: Bool) async throws -> String {
        if OfflineModeManager.shared.isOfflineModeActive { return "" }
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
        if OfflineModeManager.shared.isOfflineModeActive { return }
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

    /// Fetches all support access requests for a user
    func getUserSupportAccessRequests(userId: String) async throws -> [SupportAccessRequest] {
        let snap = try await db.collection("users").document(userId)
            .collection("supportAccessRequests")
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snap.documents.compactMap { doc in
            let data = doc.data()
            guard let message = data["message"] as? String,
                  let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
                  let status = data["status"] as? String else {
                return nil
            }
            
            return SupportAccessRequest(
                id: doc.documentID,
                message: message,
                createdAt: createdAt,
                status: status,
                resolvedAt: (data["resolvedAt"] as? Timestamp)?.dateValue()
            )
        }
    }

    // MARK: - Notification Tokens

    func updateFcmToken(userId: String, deviceId: String, token: String) async {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        do {
            let userRef = db.collection("users").document(userId)
            let tokenRef = userRef.collection("fcmTokens").document(deviceId)

            try await tokenRef.setData([
                "token": token,
                "deviceId": deviceId,
                "platform": "ios",
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)

            try await userRef.updateData([
                "lastTokenUpdate": Timestamp(date: Date()),
                "lastPlatform": "ios"
            ])
        } catch {
            print("Error updating FCM token: \(error)")
            // If document doesn't exist, create it (partially)
            let userRef = db.collection("users").document(userId)
            let tokenRef = userRef.collection("fcmTokens").document(deviceId)
            try? await tokenRef.setData([
                "token": token,
                "deviceId": deviceId,
                "platform": "ios",
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            try? await userRef.setData([
                "lastTokenUpdate": Timestamp(date: Date()),
                "lastPlatform": "ios"
            ], merge: true)
        }
    }

    // MARK: - Broadcast Notifications

    func getActiveBroadcastNotifications() async throws -> [BroadcastNotification] {
        let snap = try await db.collection("broadcastNotifications")
            .whereField("isActive", isEqualTo: true)
            .order(by: "priority", descending: true)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        return snap.documents.compactMap { doc in
            let data = doc.data()
            guard let title = data["title"] as? String,
                  let body = data["body"] as? String,
                  let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
                  let platforms = data["platforms"] as? String,
                  let isActive = data["isActive"] as? Bool else {
                return nil
            }
            
            return BroadcastNotification(
                id: doc.documentID,
                title: title,
                body: body,
                createdAt: createdAt,
                platforms: platforms,
                isActive: isActive,
                priority: data["priority"] as? Int ?? 0,
                type: data["type"] as? String ?? "important"
            )
        }.filter { broadcast in
            broadcast.platforms == "all" || broadcast.platforms == "ios"
        }
    }

    // MARK: - Feature Tracking
    
    /// Logs that a user has seen a specific feature onboarding/info sheet
    func logFeatureOnboardingSeen(featureId: String) async {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let logData: [String: Any] = [
            "userId": uid,
            "featureId": featureId,
            "seenAt": Timestamp(date: Date()),
            "platform": "ios"
        ]
        
        // Preparation: In the future, this could go into a dedicated analytics collection
        // For now, we log it to a debug collection as requested
        _ = try? await db.collection("featureOnboardingLogs").addDocument(data: logData)
    }
    
    // MARK: - Purchase Tracking
    
    func updateUserPurchaseMetadata(uid: String, type: String, tier: String?) async {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        var data: [String: Any] = ["purchaseType": type]
        if let tier {
            data["subscriptionTier"] = tier
        }
        try? await db.collection("users").document(uid).setData(data, merge: true)
    }
}
