import Foundation
@preconcurrency import UserNotifications
import FirebaseAuth
import FirebaseFirestore

enum ExamNotificationManager {
    static let categoryIdentifier = "EXAM_CATEGORY"
    static let sharedCategoryIdentifier = "EXAM_SHARED_CATEGORY"
    static let actionMarkDoneIdentifier = "EXAM_MARK_DONE"
    static let actionSnoozeIdentifier = "EXAM_SNOOZE_1H"

    static func configureCategories() {
        Task {
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
            let existing = await center.notificationCategories()
            var all = existing
            all.insert(category)
            all.insert(sharedCategory)
            center.setNotificationCategories(all)
        }
    }

    static func requestAuthorizationIfNeeded() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    static func syncNotifications(
        for exams: [Exam],
        standardReminderEnabled: Bool = true
    ) {
        // Ensure categories are available before scheduling notifications
        configureCategories()
        requestAuthorizationIfNeeded()

        Task {
            let center = UNUserNotificationCenter.current()
            let existing = await center.pendingNotificationRequests()
            let examIds = existing
                .map(\.identifier)
                .filter { $0.hasPrefix("exam_") && !$0.contains("_snooze_") }
            if !examIds.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: examIds)
            }

            let inactiveSnoozes = exams
                .filter { !$0.isActive }
                .map { "exam_snooze_\($0.id)" }
            if !inactiveSnoozes.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: inactiveSnoozes)
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
                        try? await center.add(request)
                    }
                } else {
                    // Eigene Klausuren: Standardlogik (Tag vorher + zusätzliche Erinnerung)
                    if standardReminderEnabled,
                       let reminder = reminderDate(before: exam.date),
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
                        try? await center.add(request)
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
                        try? await center.add(request)
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
        Task {
            let db = Firestore.firestore()
            do {
                let schoolYearId = try await SchoolYearService.ensureActiveSchoolYear(uid: uid, db: db)
                let docRef = db
                    .collection("users")
                    .document(uid)
                    .collection("schoolYears")
                    .document(schoolYearId)
                    .collection("exams")
                    .document(id)
                try await docRef.updateData(["isCompleted": true])
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional: Fehler ignorieren, Notification trotzdem entfernen
            }

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
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
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
