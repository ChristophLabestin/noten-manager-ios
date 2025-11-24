//
//  noten_manager_iosApp.swift
//  noten-manager-ios
//
//  Created by Christoph Labestin on 18.11.25.
//

import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self
        HomeworkNotificationManager.configureCategories()
        ExamNotificationManager.configureCategories()
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        HomeworkNotificationManager.handleNotificationResponse(response)
        ExamNotificationManager.handleNotificationResponse(response)
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
