import Foundation
@preconcurrency import UserNotifications

enum LaunchOfferNotificationManager {
    static let categoryIdentifier = "LAUNCH_OFFER_CATEGORY"
    static let pendingOpenDefaultsKey = "launch_offer_pending_open"
    static let remindersDisabledKey = "launch_offer_reminders_disabled"

    private static let reminderHour = 12
    private static let reminderMinute = 0
    private static let targetYear = 2026
    private static let targetMonth = 1
    private static let targetDay = 31
    private static let offerUserInfoKey = "launchOffer"

    private static let idSevenDays = "launch_offer_2026_7days"
    private static let idLastDay = "launch_offer_2026_lastday"

    static func configureCategory() {
        Task {
            let category = UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: []
            )
            let center = UNUserNotificationCenter.current()
            let existing = await center.notificationCategories()
            var all = existing
            all.insert(category)
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

    static func scheduleIfNeeded(purchased: Bool, displayPrice: String? = nil) {
        if UserDefaults.standard.bool(forKey: remindersDisabledKey) {
            let center = UNUserNotificationCenter.current()
            let ids = [idSevenDays, idLastDay]
            center.removePendingNotificationRequests(withIdentifiers: ids)
            return
        }
        
        requestAuthorizationIfNeeded()
        configureCategory()

        Task {
            let center = UNUserNotificationCenter.current()
            if purchased || !isOfferActive() {
                let ids = [idSevenDays, idLastDay]
                center.removePendingNotificationRequests(withIdentifiers: ids)
                center.removeDeliveredNotifications(withIdentifiers: ids)
                clearPendingOpenFlag()
                return
            }

            guard let targetDate = makeTargetDate() else { return }
            guard let sevenDaysBefore = Calendar.current.date(byAdding: .day, value: -7, to: targetDate) else { return }

            let now = Date()
            var requests: [UNNotificationRequest] = []
            let priceText = displayPrice?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? displayPrice!
                : "3,99€"

            if sevenDaysBefore > now {
                requests.append(makeRequest(
                    identifier: idSevenDays,
                    title: "Noch 7 Tage: \(priceText) sichern",
                    body: "Nur noch 7 Tage: Einmalig \(priceText) für immer statt 9,99€ / Jahr. Tippen zum Öffnen.",
                    date: sevenDaysBefore
                ))
            }

            if targetDate > now {
                requests.append(makeRequest(
                    identifier: idLastDay,
                    title: "Letzter Tag für \(priceText)",
                    body: "Heute endet der Frühzugang: \(priceText) einmalig statt 9,99€ / Jahr. Jetzt sichern.",
                    date: targetDate
                ))
            }

            guard !requests.isEmpty else { return }

            let ids = [idSevenDays, idLastDay]
            center.removePendingNotificationRequests(withIdentifiers: ids)
            for request in requests {
                try? await center.add(request)
            }
        }
    }

    static func handleNotificationResponse(_ response: UNNotificationResponse) {
        guard isLaunchOfferNotification(response.notification.request) else { return }
        guard isOfferActive() else {
            clearPendingOpenFlag()
            return
        }
        UserDefaults.standard.set(true, forKey: pendingOpenDefaultsKey)
        NotificationCenter.default.post(name: .openLaunchOffer, object: nil)
    }

    static func consumePendingOpen() -> Bool {
        let defaults = UserDefaults.standard
        let shouldOpen = defaults.bool(forKey: pendingOpenDefaultsKey)
        if shouldOpen && isOfferActive() {
            defaults.set(false, forKey: pendingOpenDefaultsKey)
            return true
        }
        if shouldOpen {
            defaults.set(false, forKey: pendingOpenDefaultsKey)
        }
        return false
    }

    static func isOfferActive(on date: Date = Date()) -> Bool {
        let checkingDate = date
        guard let cutoff = makeCutoffDate() else { return true }
        return checkingDate < cutoff
    }

    static func isSubscriptionGateActive(on date: Date = Date()) -> Bool {
        let checkingDate = date
        guard let cutoff = makeCutoffDate() else { return false }
        return checkingDate >= cutoff
    }

    static func isLaunchOfferNotification(_ request: UNNotificationRequest) -> Bool {
        if request.identifier == idSevenDays || request.identifier == idLastDay {
            return true
        }
        if let flag = request.content.userInfo[offerUserInfoKey] as? Bool, flag {
            return true
        }
        return false
    }

    private static func makeTargetDate() -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = targetYear
        components.month = targetMonth
        components.day = targetDay
        components.hour = reminderHour
        components.minute = reminderMinute
        return calendar.date(from: components)
    }

    private static func makeCutoffDate() -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = targetYear
        components.month = 2
        components.day = 1
        components.hour = 0
        components.minute = 0
        return calendar.date(from: components)
    }


    private static func clearPendingOpenFlag() {
        UserDefaults.standard.set(false, forKey: pendingOpenDefaultsKey)
    }

    private static func makeRequest(identifier: String, title: String, body: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [offerUserInfoKey: true]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    static func disableReminders() {
        UserDefaults.standard.set(true, forKey: remindersDisabledKey)
        let center = UNUserNotificationCenter.current()
        let ids = [idSevenDays, idLastDay]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
