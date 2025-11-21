import Foundation
import UserNotifications
import FirebaseAuth
import FirebaseFirestore

enum ExamNotificationManager {
    static let categoryIdentifier = "EXAM_CATEGORY"
    static let sharedCategoryIdentifier = "EXAM_SHARED_CATEGORY"
    static let actionMarkDoneIdentifier = "EXAM_MARK_DONE"
    static let actionSnoozeIdentifier = "EXAM_SNOOZE_1H"

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
                    // Ergebnis wird still ignoriert
                }
            }
        }
    }

    static func syncNotifications(for exams: [Exam]) {
        requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { existing in
            let examIds = existing
                .filter { $0.identifier.hasPrefix("exam_") }
                .map { $0.identifier }
            if !examIds.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: examIds)
            }

            let now = Date()
            for exam in exams where exam.isActive {
                if exam.isShared {
                    // Für geteilte Klausuren nur die benutzerspezifische Erinnerung nutzen
                    if let reminderAt = exam.reminderAt,
                       reminderAt > now {
                        let content = UNMutableNotificationContent()
                        content.title = "Klausurerinnerung"
                        if exam.subjectName.isEmpty {
                            content.body = exam.title
                        } else {
                            content.body = "\(exam.title) in \(exam.subjectName)"
                        }
                        content.sound = .default
                        content.categoryIdentifier = sharedCategoryIdentifier
                        content.userInfo = ["examId": exam.id]

                        let comps = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: reminderAt
                        )
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let identifier = "exam_custom_\(exam.id)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request, withCompletionHandler: nil)
                    }
                } else {
                    // Eigene Klausuren: Standardlogik (Tag vorher + zusätzliche Erinnerung)
                    if let reminder = reminderDate(before: exam.date),
                       reminder > now {
                        let content = UNMutableNotificationContent()
                        content.title = "Klausur morgen"
                        if exam.subjectName.isEmpty {
                            content.body = exam.title
                        } else {
                            content.body = "\(exam.title) in \(exam.subjectName) ist morgen."
                        }
                        content.sound = .default
                        content.categoryIdentifier = categoryIdentifier
                        content.userInfo = ["examId": exam.id]

                        let comps = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: reminder
                        )
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let identifier = "exam_due_\(exam.id)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        center.add(request, withCompletionHandler: nil)
                    }

                    if let reminderAt = exam.reminderAt,
                       reminderAt > now {
                        let content = UNMutableNotificationContent()
                        content.title = "Klausurerinnerung"
                        if exam.subjectName.isEmpty {
                            content.body = exam.title
                        } else {
                            content.body = "\(exam.title) in \(exam.subjectName)"
                        }
                        content.sound = .default
                        content.categoryIdentifier = categoryIdentifier
                        content.userInfo = ["examId": exam.id]

                        let comps = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: reminderAt
                        )
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let identifier = "exam_custom_\(exam.id)"
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
        let examId: String? = (userInfo["examId"] as? String) ?? extractExamId(from: identifier)
        guard let examId else { return }

        switch actionId {
        case actionMarkDoneIdentifier:
            markExamCompleted(examId)
        case actionSnoozeIdentifier:
            scheduleSnooze(for: examId, originalContent: content)
        default:
            break
        }
    }

    private static func extractExamId(from identifier: String) -> String? {
        // erwartet "exam_due_<id>", "exam_custom_<id>", "exam_snooze_<id>"
        guard identifier.hasPrefix("exam_") else { return nil }
        let components = identifier.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: true)
        guard components.count >= 3 else { return nil }
        return String(components[2])
    }

    private static func markExamCompleted(_ id: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docRef = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("exams")
            .document(id)
        docRef.updateData(["isCompleted": true]) { _ in
            let center = UNUserNotificationCenter.current()
            let identifiers = [
                "exam_due_\(id)",
                "exam_custom_\(id)",
                "exam_snooze_\(id)"
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
        info["examId"] = id
        newContent.userInfo = info

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let requestId = "exam_snooze_\(id)"
        let request = UNNotificationRequest(identifier: requestId, content: newContent, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func reminderDate(before date: Date) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) else {
            return nil
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: dayBefore)
        comps.hour = 20
        comps.minute = 0
        return calendar.date(from: comps)
    }
}
