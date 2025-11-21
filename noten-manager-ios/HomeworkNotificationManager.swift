import Foundation
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

enum HomeworkNotificationManager {
    static let categoryIdentifier = "HOMEWORK_CATEGORY"
    static let sharedCategoryIdentifier = "HOMEWORK_SHARED_CATEGORY"
    static let actionMarkDoneIdentifier = "HOMEWORK_MARK_DONE"
    static let actionSnoozeIdentifier = "HOMEWORK_SNOOZE_1H"

    static func configureCategories() {
        let done = UNNotificationAction(
            identifier: actionMarkDoneIdentifier,
            title: "Als erledigt markieren",
            options: [.authenticationRequired]
        )
        let snooze = UNNotificationAction(
            identifier: actionSnoozeIdentifier,
            title: "In 1 Stunde erinnern",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        let sharedCategory = UNNotificationCategory(
            identifier: sharedCategoryIdentifier,
            actions: [snooze],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            var all = existing
            all.insert(category)
            all.insert(sharedCategory)
            center.setNotificationCategories(all)
        }
    }

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    // Ignoriere Ergebnis still – Nutzer kann später in Einstellungen ändern
                }
            }
        }
    }

    static func syncNotifications(for homeworks: [Homework]) {
        requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { existing in
            let homeworkIds = existing
                .filter { $0.identifier.hasPrefix("homework_") }
                .map { $0.identifier }
            if !homeworkIds.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: homeworkIds)
            }

            let now = Date()

            for hw in homeworks where hw.isActive {
                if hw.isShared {
                    // Only schedule user-specific reminderAt with shared category
                    if let reminderAt = hw.reminderAt,
                       reminderAt > now {
                        let content = UNMutableNotificationContent()
                        content.title = "Erinnerung an Hausaufgabe"
                        if hw.subjectName.isEmpty {
                            content.body = hw.title
                        } else {
                            content.body = "\(hw.title) in \(hw.subjectName)"
                        }
                        content.sound = .default
                        content.categoryIdentifier = sharedCategoryIdentifier
                        content.userInfo = ["homeworkId": hw.id]

                        let comps = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: reminderAt
                        )
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let identifier = "homework_custom_\(hw.id)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request, withCompletionHandler: nil)
                    }
                } else {
                    // Original logic for non-shared homeworks

                    if let dueDate = hw.dueDate,
                       let reminder = reminderDate(before: dueDate),
                       reminder > now {
                        let content = UNMutableNotificationContent()
                        content.title = "Hausaufgabe morgen fällig"
                        if hw.subjectName.isEmpty {
                            content.body = hw.title
                        } else {
                            content.body = "\(hw.title) in \(hw.subjectName) ist morgen fällig."
                        }
                        content.sound = .default
                        content.categoryIdentifier = categoryIdentifier
                        content.userInfo = ["homeworkId": hw.id]

                        let comps = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: reminder
                        )
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let identifier = "homework_due_\(hw.id)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request, withCompletionHandler: nil)
                    }

                    if let reminderAt = hw.reminderAt,
                       reminderAt > now {
                        let content = UNMutableNotificationContent()
                        content.title = "Erinnerung an Hausaufgabe"
                        if hw.subjectName.isEmpty {
                            content.body = hw.title
                        } else {
                            content.body = "\(hw.title) in \(hw.subjectName)"
                        }
                        content.sound = .default
                        content.categoryIdentifier = categoryIdentifier
                        content.userInfo = ["homeworkId": hw.id]

                        let comps = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: reminderAt
                        )
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let identifier = "homework_custom_\(hw.id)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request, withCompletionHandler: nil)
                    }
                }
            }
        }
    }

    static func handleNotificationResponse(_ response: UNNotificationResponse) {
        let actionId = response.actionIdentifier
        guard actionId == actionMarkDoneIdentifier || actionId == actionSnoozeIdentifier else {
            return
        }

        let request = response.notification.request
        let content = request.content
        let identifier = request.identifier

        let userInfo = content.userInfo
        let homeworkId: String? = (userInfo["homeworkId"] as? String) ?? extractHomeworkId(from: identifier)
        guard let homeworkId else { return }

        switch actionId {
        case actionMarkDoneIdentifier:
            markHomeworkCompleted(homeworkId)
        case actionSnoozeIdentifier:
            scheduleSnooze(for: homeworkId, originalContent: content)
        default:
            break
        }
    }

    private static func extractHomeworkId(from identifier: String) -> String? {
        // erwartet Muster wie "homework_due_<id>", "homework_custom_<id>", "homework_snooze_<id>"
        guard identifier.hasPrefix("homework_") else { return nil }
        let components = identifier.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: true)
        guard components.count >= 3 else { return nil }
        return String(components[2])
    }

    private static func markHomeworkCompleted(_ id: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docRef = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("homeworks")
            .document(id)
        docRef.updateData(["isCompleted": true]) { _ in
            let center = UNUserNotificationCenter.current()
            let identifiers = [
                "homework_due_\(id)",
                "homework_custom_\(id)",
                "homework_snooze_\(id)"
            ]
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    private static func scheduleSnooze(for id: String, originalContent: UNNotificationContent) {
        let newContent = UNMutableNotificationContent()
        newContent.title = originalContent.title
        newContent.body = originalContent.body
        newContent.sound = originalContent.sound
        newContent.categoryIdentifier = categoryIdentifier

        var info = originalContent.userInfo
        info["homeworkId"] = id
        newContent.userInfo = info

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let requestId = "homework_snooze_\(id)"
        let request = UNNotificationRequest(identifier: requestId, content: newContent, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func reminderDate(before dueDate: Date) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDate) else {
            return nil
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        comps.hour = 20
        comps.minute = 0
        return calendar.date(from: comps)
    }
}
