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
            actions: [done, snooze],
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

    static func syncNotifications(
        for homeworks: [Homework],
        reminderHour: Int = 19,
        reminderMinute: Int = 0,
        standardReminderEnabled: Bool = true
    ) {
        // Ensure categories (actions) are registered before scheduling
        configureCategories()
        requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { existing in
            let homeworkIds = existing
                .map(\.identifier)
                .filter { $0.hasPrefix("homework_") && !$0.contains("_snooze_") }
            if !homeworkIds.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: homeworkIds)
            }

            let inactiveSnoozes = homeworks
                .filter { !$0.isActive }
                .map { "homework_snooze_\($0.id)" }
            if !inactiveSnoozes.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: inactiveSnoozes)
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
                        var info: [AnyHashable: Any] = ["homeworkId": hw.id]
                        if let gid = hw.groupId, !gid.isEmpty {
                            info["groupId"] = gid
                        }
                        content.userInfo = info

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

                    if standardReminderEnabled,
                       let dueDate = hw.dueDate,
                       let reminder = reminderDate(before: dueDate, hour: reminderHour, minute: reminderMinute),
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
                        var info: [AnyHashable: Any] = ["homeworkId": hw.id]
                        if let gid = hw.groupId, !gid.isEmpty {
                            info["groupId"] = gid
                        }
                        content.userInfo = info

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
                        var info: [AnyHashable: Any] = ["homeworkId": hw.id]
                        if let gid = hw.groupId, !gid.isEmpty {
                            info["groupId"] = gid
                        }
                        content.userInfo = info

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
        let groupId: String? = userInfo["groupId"] as? String
        guard let homeworkId else { return }

        switch actionId {
        case actionMarkDoneIdentifier:
            markHomeworkCompleted(homeworkId, groupId: groupId)
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

    static func markHomeworkCompleted(_ id: String, groupId: String? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            let db = Firestore.firestore()
            do {
                let schoolYearId = try await SchoolYearService.ensureActiveSchoolYear(uid: uid, db: db)
                let yearRef = db
                    .collection("users")
                    .document(uid)
                    .collection("schoolYears")
                    .document(schoolYearId)

                if let gid = groupId, !gid.isEmpty {
                    let key = compoundId(gid: gid, docId: id)
                    let docRef = yearRef
                        .collection("homeworkGroupCompleted")
                        .document(key)
                    try await docRef.setData(["isCompleted": true])
                } else {
                    let docRef = yearRef
                        .collection("homeworks")
                        .document(id)
                    try await docRef.updateData(["isCompleted": true])
                }
            } catch {
                // optional: Fehler ignorieren, Notification trotzdem entfernen
            }

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
        newContent.categoryIdentifier = originalContent.categoryIdentifier

        var info = originalContent.userInfo
        info["homeworkId"] = id
        newContent.userInfo = info

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let requestId = "homework_snooze_\(id)"
        let request = UNNotificationRequest(identifier: requestId, content: newContent, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func reminderDate(before dueDate: Date, hour: Int, minute: Int) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDate) else {
            return nil
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        comps.hour = max(0, min(23, hour))
        comps.minute = max(0, min(59, minute))
        return calendar.date(from: comps)
    }

    private static func compoundId(gid: String?, docId: String) -> String {
        guard let gid, !gid.isEmpty else { return docId }
        return "\(gid)|\(docId)"
    }
}
