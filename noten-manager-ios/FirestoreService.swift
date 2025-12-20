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
}
