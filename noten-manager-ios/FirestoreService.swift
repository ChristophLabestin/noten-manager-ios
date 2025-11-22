// FirestoreService.swift
import Foundation
import FirebaseFirestore

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
}
