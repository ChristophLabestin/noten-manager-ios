import Foundation
import UserNotifications
import SwiftUI

enum DynamicCloudNotificationManager {
    static let actionKey = "action"
    static let payloadIdKey = "id"
    static let sheetTypeKey = "sheetType"

    enum ActionType: String {
        case openExam = "OPEN_EXAM"
        case openSheet = "OPEN_SHEET"
        case openSupportTicket = "openSupportTicket"
    }

    static func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        
        guard let actionString = userInfo[actionKey] as? String,
              let action = ActionType(rawValue: actionString) else {
            return
        }

        switch action {
        case .openExam:
            if let examId = userInfo[payloadIdKey] as? String {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .openExamDetail, object: examId)
                }
            }
        case .openSheet:
            if let sheetType = userInfo[sheetTypeKey] as? String {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .openSheet, object: sheetType)
                }
            }
        case .openSupportTicket:
            if let ticketId = userInfo["ticketId"] as? String {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(name: .openSupportTicket, object: ticketId)
                }
            }
        }
    }
}

extension Notification.Name {
    static let openSheet = Notification.Name("openSheet")
    static let openSupportTicket = Notification.Name("openSupportTicket")
}
