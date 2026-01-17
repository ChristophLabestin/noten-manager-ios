//
//  noten_manager_iosApp.swift
//  noten-manager-ios
//
//  Created by Christoph Labestin on 18.11.25.
//

import SwiftUI
import UIKit
@preconcurrency import UserNotifications
import FirebaseCore
import FirebaseMessaging
import FirebaseAuth
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        Messaging.messaging().delegate = self
        
        UNUserNotificationCenter.current().delegate = self
        
        application.registerForRemoteNotifications()
        HomeworkNotificationManager.configureCategories()
        ExamNotificationManager.configureCategories()
        DailyReminderNotificationManager.configureCategories()
        LaunchOfferNotificationManager.configureCategory()
        BackgroundRefreshManager.register()
        BackgroundRefreshManager.schedule()
        if #unavailable(iOS 13.0) {
            UIApplication.shared.setMinimumBackgroundFetchInterval(15 * 60)
        }
        return true
    }


    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        BackgroundRefreshManager.performBackgroundFetch(completion: completionHandler)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Messaging.messaging().appDidReceiveMessage(userInfo)
        completionHandler(.noData)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("FCM registration token: \(String(describing: fcmToken))")
        // Note: This callback is fired at each app startup and whenever a new token is generated.
        
        if let token = fcmToken, let uid = Auth.auth().currentUser?.uid {
            Task {
                await FirestoreService.shared.updateFcmToken(userId: uid, token: token)
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let item = NotificationInboxItem.from(notification) {
            Task { @MainActor in
                NotificationInboxStore.shared.record(item: item)
            }
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let item = NotificationInboxItem.from(response.notification, markRead: true) {
            Task { @MainActor in
                NotificationInboxStore.shared.record(item: item)
            }
        }
        HomeworkNotificationManager.handleNotificationResponse(response)
        ExamNotificationManager.handleNotificationResponse(response)
        DailyReminderNotificationManager.handleNotificationResponse(response)
        LaunchOfferNotificationManager.handleNotificationResponse(response)
        DynamicCloudNotificationManager.handleNotificationResponse(response)
        completionHandler()
    }
}

@main
struct noten_manager_iosApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var offlineManager = OfflineModeManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(offlineManager)
        }
    }
}
