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
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
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
            NavigationStack {
                ContentView()
            }
            .environmentObject(offlineManager)
        }
    }
}
