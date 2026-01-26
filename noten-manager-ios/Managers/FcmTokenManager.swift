import Foundation
import FirebaseAuth
import FirebaseMessaging

enum FcmTokenManager {
    private static let cachedTokenKey = "cached_fcm_token"

    static func cache(token: String) {
        UserDefaults.standard.set(token, forKey: cachedTokenKey)
    }

    static func cachedToken() -> String? {
        UserDefaults.standard.string(forKey: cachedTokenKey)
    }

    static func syncCachedTokenIfPossible() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let token = cachedToken() else { return }
        Task {
            await FirestoreService.shared.updateFcmToken(userId: uid, token: token)
        }
    }

    static func refreshAndSyncCurrentToken() {
        guard Auth.auth().currentUser?.uid != nil else { return }
        Messaging.messaging().token { token, error in
            if let error = error {
                print("Error fetching FCM token: \(error)")
                return
            }
            guard let token else { return }
            cache(token: token)
            syncCachedTokenIfPossible()
        }
    }
}
