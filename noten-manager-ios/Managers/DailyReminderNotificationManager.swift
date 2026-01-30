import Foundation
@preconcurrency import UserNotifications

enum DailyReminderNotificationManager {
    static let categoryIdentifier = "DAILY_REMINDER"
    static let categoryWithHomeworkIdentifier = "DAILY_REMINDER_HOMEWORK"
    static let actionMarkHomeworkDoneIdentifier = "DAILY_MARK_HOMEWORK_DONE"
    static let actionSnoozeIdentifier = "DAILY_REMINDER_SNOOZE_1H"
    private static let lastStampDefaultsKey = "dailyReminderLastStamp"

    static func configureCategories() {
        Task {
            let markHomework = UNNotificationAction(
                identifier: actionMarkHomeworkDoneIdentifier,
                title: "Hausaufgabe erledigt",
                options: [.authenticationRequired]
            )
            let snooze = UNNotificationAction(
                identifier: actionSnoozeIdentifier,
                title: "In 1 Stunde erinnern",
                options: []
            )
            let withHomework = UNNotificationCategory(
                identifier: categoryWithHomeworkIdentifier,
                actions: [markHomework, snooze],
                intentIdentifiers: [],
                options: []
            )
            let onlySnooze = UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: [snooze],
                intentIdentifiers: [],
                options: []
            )

            let center = UNUserNotificationCenter.current()
            let existing = await center.notificationCategories()
            var all = existing
            all.insert(withHomework)
            all.insert(onlySnooze)
            center.setNotificationCategories(all)
        }
    }

    static func handleNotificationResponse(_ response: UNNotificationResponse) {
        let actionId = response.actionIdentifier
        guard actionId == actionMarkHomeworkDoneIdentifier || actionId == actionSnoozeIdentifier else { return }

        let request = response.notification.request
        let content = request.content
        let userInfo = content.userInfo

        let homeworkId = userInfo["homeworkId"] as? String
        let groupId = userInfo["groupId"] as? String

        switch actionId {
        case actionMarkHomeworkDoneIdentifier:
            guard let homeworkId else { break }
            HomeworkNotificationManager.markHomeworkCompleted(homeworkId, groupId: groupId)
        case actionSnoozeIdentifier:
            scheduleSnooze(originalContent: content)
        default:
            break
        }
    }

    static func syncDailyReminder(
        homeworks: [Homework],
        exams: [Exam],
        hour: Int,
        minute: Int,
        enabled: Bool = true
    ) {
        // Simple debounce to avoid thrashing when multiple updates arrive rapidly.
        struct State {
            static var lastRun: Date?
        }
        let nowGate = Date()
        if let last = State.lastRun, nowGate.timeIntervalSince(last) < 2 {
            return
        }
        State.lastRun = nowGate
        HomeworkNotificationManager.requestAuthorizationIfNeeded()

        Task {
            let center = UNUserNotificationCenter.current()
            let existing = await center.pendingNotificationRequests()
            let identifiers = existing
                .map(\.identifier)
                .filter { $0.hasPrefix("daily_reminder_") }
            let snoozeIds = identifiers.filter { $0.contains("_snooze_") }
            let baseIds = identifiers.filter { !$0.contains("_snooze_") }
            let defaults = UserDefaults.standard

            if !enabled {
                let toRemove = baseIds + snoozeIds
                if !toRemove.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: toRemove)
                }
                return
            }

            let calendar = Calendar.current
            let now = Date()
            let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd"
            let stamp = formatter.string(from: tomorrow)
            let targetIdentifier = "daily_reminder_\(stamp)"
            let hasCurrentBase = baseIds.contains(targetIdentifier)

            let tomorrowHomeworks = homeworks.filter { hw in
                guard hw.isActive, let due = hw.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: tomorrow)
            }
            let tomorrowExams = exams.filter { exam in
                exam.isActive && calendar.isDate(exam.date, inSameDayAs: tomorrow)
            }
            if tomorrowHomeworks.isEmpty && tomorrowExams.isEmpty {
                let toRemove = baseIds + snoozeIds
                if !toRemove.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: toRemove)
                }
                return
            }

            if !baseIds.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: baseIds)
            }

            let reminderHour = max(0, min(23, hour))
            let reminderMinute = max(0, min(59, minute))

            var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = reminderHour
            comps.minute = reminderMinute
            let reminderDate = calendar.date(from: comps)

            if let last = defaults.string(forKey: lastStampDefaultsKey),
               last == stamp,
               (reminderDate ?? now) <= now,
               !hasCurrentBase {
                // Bereits für diesen Tag ausgelöst – nicht erneut planen
                if !snoozeIds.isEmpty {
                    center.removePendingNotificationRequests(withIdentifiers: snoozeIds)
                }
                return
            }

            let trigger: UNNotificationTrigger
            if let reminderDate = calendar.date(from: comps),
               reminderDate > now {
                let dateComps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
                trigger = UNCalendarNotificationTrigger(dateMatching: dateComps, repeats: false)
            } else {
                // Erinnerungszeit vorbei -> einmalig zeitnah senden
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 300, repeats: false)
            }

            let content = UNMutableNotificationContent()
            content.title = "Morgen anstehend"
            content.body = buildBody(homeworks: tomorrowHomeworks, exams: tomorrowExams)
            content.sound = .default

            var userInfo: [AnyHashable: Any] = [:]
            let examIds = tomorrowExams.map(\.id)
            if !examIds.isEmpty {
                userInfo["examIds"] = examIds
                if examIds.count == 1 {
                    userInfo["examId"] = examIds[0]
                }
            }
            
            let homeworkIds = tomorrowHomeworks.map(\.id)
            if !homeworkIds.isEmpty {
                userInfo["homeworkIds"] = homeworkIds
                if let hw = tomorrowHomeworks.sorted(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }).first {
                    userInfo["homeworkId"] = hw.id
                    if let gid = hw.groupId, !gid.isEmpty {
                        userInfo["groupId"] = gid
                    }
                }
                content.categoryIdentifier = categoryWithHomeworkIdentifier
            } else {
                content.categoryIdentifier = categoryIdentifier
            }
            content.userInfo = userInfo

            let identifier = targetIdentifier

            // Ältere Daily-Reminder entfernen, dann neuen planen
            let oldBases = baseIds.filter { $0 != targetIdentifier }
            if !oldBases.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: oldBases)
            }
            if hasCurrentBase {
                center.removePendingNotificationRequests(withIdentifiers: [targetIdentifier])
            }

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
            defaults.set(stamp, forKey: lastStampDefaultsKey)
        }
    }

    private static func scheduleSnooze(originalContent: UNNotificationContent) {
        let newContent = UNMutableNotificationContent()
        newContent.title = originalContent.title
        newContent.body = originalContent.body
        newContent.sound = originalContent.sound
        newContent.categoryIdentifier = originalContent.categoryIdentifier
        newContent.userInfo = originalContent.userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let requestId = "daily_reminder_snooze_\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: requestId, content: newContent, trigger: trigger)
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private static func buildBody(homeworks: [Homework], exams: [Exam]) -> String {
        // Case 1: Both
        if !homeworks.isEmpty && !exams.isEmpty {
            let examPart = exams.count == 1
                ? (exams[0].subjectName.isEmpty ? "eine Klausur" : "die \(exams[0].subjectName) Klausur")
                : "\(exams.count) Klausuren"
            
            let hwPart = homeworks.count == 1
                ? (homeworks[0].subjectName.isEmpty ? "eine Hausaufgabe" : "Hausaufgabe in \(homeworks[0].subjectName)")
                : "\(homeworks.count) Hausaufgaben"
            
            return "Morgen steht \(examPart) an und du hast noch \(hwPart). Tippe für Details."
        }
        
        // Case 2: Only Exams
        if !exams.isEmpty {
            if exams.count == 1 {
                let e = exams[0]
                let subject = e.subjectName.isEmpty ? "" : " in \(e.subjectName)"
                return "Morgen: \(e.title)\(subject). Viel Erfolg! 🍀"
            } else {
                return "Morgen stehen \(exams.count) Klausuren an. Viel Erfolg! 🍀"
            }
        }
        
        // Case 3: Only Homework
        if !homeworks.isEmpty {
            if homeworks.count == 1 {
                let h = homeworks[0]
                let subject = h.subjectName.isEmpty ? "" : " in \(h.subjectName)"
                return "Nicht vergessen: Hausaufgabe \"\(h.title)\"\(subject) ist für morgen fällig."
            } else {
                return "Du hast für morgen \(homeworks.count) offene Hausaufgaben."
            }
        }
        
        return "Schau dir an, was morgen ansteht."
    }
}
