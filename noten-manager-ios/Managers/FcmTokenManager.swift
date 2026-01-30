import Foundation
import UIKit
import FirebaseAuth
import FirebaseMessaging

enum FcmTokenManager {
    private static let cachedTokenKey = "cached_fcm_token"
    private static let cachedDeviceIdKey = "cached_device_id"

    private static func deviceId() -> String {
        if let id = UIDevice.current.identifierForVendor?.uuidString, !id.isEmpty {
            return id
        }
        if let cached = UserDefaults.standard.string(forKey: cachedDeviceIdKey), !cached.isEmpty {
            return cached
        }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: cachedDeviceIdKey)
        return generated
    }

    static func cache(token: String) {
        UserDefaults.standard.set(token, forKey: cachedTokenKey)
    }

    static func cachedToken() -> String? {
        UserDefaults.standard.string(forKey: cachedTokenKey)
    }

    static func syncCachedTokenIfPossible() {
        Task { @MainActor in
            if OfflineModeManager.shared.isOfflineModeActive || !OfflineModeManager.shared.isOnline { return }
            guard let uid = Auth.auth().currentUser?.uid else { return }
            guard let token = cachedToken() else { return }
            await FirestoreService.shared.updateFcmToken(userId: uid, deviceId: deviceId(), token: token)
        }
    }

    static func refreshAndSyncCurrentToken() {
        Task { @MainActor in
            if OfflineModeManager.shared.isOfflineModeActive || !OfflineModeManager.shared.isOnline { return }
            guard Auth.auth().currentUser?.uid != nil else { return }
            guard Messaging.messaging().apnsToken != nil else { return }
            do {
                let token = try await Messaging.messaging().token()
                cache(token: token)
                syncCachedTokenIfPossible()
            } catch {
                if !OfflineModeManager.shared.isOfflineModeActive && OfflineModeManager.shared.isOnline {
                    print("Error fetching FCM token: \(error)")
                }
            }
        }
    }
}
