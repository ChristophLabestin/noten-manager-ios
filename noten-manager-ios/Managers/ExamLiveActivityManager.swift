import Foundation

#if canImport(ActivityKit)
@preconcurrency import ActivityKit
import UIKit
import UserNotifications
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@available(iOS 16.2, *)
struct ExamCountdownAttributes: ActivityAttributes, Hashable {
    public struct ContentState: Codable, Hashable {
        var examDate: Date
        var title: String
        var subject: String?
        var startDate: Date
        var duration: TimeInterval
    }

    var examId: String
    var title: String
    var subject: String?
    var accent: String?
}

@MainActor
enum ExamLiveActivityManager {
    static let leadTime: TimeInterval = 90 * 60
    private static let themeKey = "grades_theme"

    @MainActor
    static func syncLiveActivities(for exams: [Exam]) async {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let now = Date()
        let relevant = exams.filter { $0.hasTime && !$0.isCompleted }
        let activities = Activity<ExamCountdownAttributes>.activities
        var activityMap = Dictionary(uniqueKeysWithValues: activities.map { ($0.attributes.examId, $0) })

        for activity in activities {
            guard let exam = relevant.first(where: { $0.id == activity.attributes.examId }) else {
                await end(activity)
                activityMap[activity.attributes.examId] = nil
                continue
            }
            if exam.date <= now || exam.date.timeIntervalSince(now) > leadTime {
                await end(activity)
                activityMap[activity.attributes.examId] = nil
                continue
            }
            let (content, _) = activityContent(for: exam, existing: activity.content.state, includeAlert: false)
            await activity.update(content)
        }

        for exam in relevant where exam.date > now && exam.date.timeIntervalSince(now) <= leadTime {
            if activityMap[exam.id] != nil { continue }
            await start(for: exam)
        }
    }

    @available(iOS 16.2, *)
    @MainActor
    private static func start(for exam: Exam) async {
        let attributes = ExamCountdownAttributes(
            examId: exam.id,
            title: exam.title,
            subject: subjectLabel(for: exam),
            accent: currentAccentTheme()
        )
        let (content, alert) = activityContent(for: exam, existing: nil, includeAlert: true)
        if let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token) {
            if let alert, #available(iOS 17.0, *) {
                await activity.update(content, alertConfiguration: alert)
            }
            await registerPushToken(for: activity, exam: exam)
            scheduleAutoEnd(for: activity, at: exam.date)
            await notifyStartIfNeeded(for: exam)
            await triggerHaptic()
            return
        }

        // Fallback: falls Push-Token-Flow scheitert (kein APNs-Key/Entitlement), trotzdem lokal starten.
        if let activity = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
            if let alert, #available(iOS 17.0, *) {
                await activity.update(content, alertConfiguration: alert)
            }
            scheduleAutoEnd(for: activity, at: exam.date)
            await notifyStartIfNeeded(for: exam)
            await triggerHaptic()
        }
    }

    @available(iOS 16.2, *)
    @MainActor
    private static func end(_ activity: Activity<ExamCountdownAttributes>) async {
        await activity.end(activity.content, dismissalPolicy: .immediate)
        await removePushRegistration(for: activity.id)
    }

    @available(iOS 16.2, *)
    private static func contentState(for exam: Exam, existing: ExamCountdownAttributes.ContentState?) -> ExamCountdownAttributes.ContentState {
        let startDate = exam.date.addingTimeInterval(-leadTime)
        let duration = leadTime
        return ExamCountdownAttributes.ContentState(
            examDate: exam.date,
            title: exam.title,
            subject: subjectLabel(for: exam),
            startDate: startDate,
            duration: duration
        )
    }

    @available(iOS 16.2, *)
    private static func activityContent(
        for exam: Exam,
        existing: ExamCountdownAttributes.ContentState?,
        includeAlert: Bool
    ) -> (ActivityContent<ExamCountdownAttributes.ContentState>, AlertConfiguration?) {
        let state = contentState(for: exam, existing: existing)
        let content = ActivityContent(state: state, staleDate: state.examDate, relevanceScore: 50)

        guard includeAlert else { return (content, nil) }
        if #available(iOS 17.0, *) {
            let title: LocalizedStringResource = "Klausur in 90 Minuten"
            let alertBody: LocalizedStringResource
            if let subject = state.subject, !subject.isEmpty {
                alertBody = "\(state.title) in \(subject)"
            } else {
                alertBody = "\(state.title)"
            }
            let alert = AlertConfiguration(title: title, body: alertBody, sound: .default)
            return (content, alert)
        }

        return (content, nil)
    }

    private static func currentAccentTheme() -> String? {
        UserDefaults.standard.string(forKey: themeKey)
    }

    private static func subjectLabel(for exam: Exam) -> String? {
        let trimmed = exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @available(iOS 16.2, *)
    @MainActor
    private static func scheduleAutoEnd(for activity: Activity<ExamCountdownAttributes>, at date: Date) {
        let activityId = activity.id
        let delay = date.timeIntervalSinceNow
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let latest = Activity<ExamCountdownAttributes>.activities.first(where: { $0.id == activityId }) else { return }
            await end(latest)
        }
    }

    private static func triggerHaptic() async {
        await MainActor.run {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
    }

    @available(iOS 16.2, *)
    private static func registerPushToken(for activity: Activity<ExamCountdownAttributes>, exam: Exam) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await savePushRegistration(token: token, uid: uid, activity: activity, exam: exam)
                // one token is enough; break out
                break
            }
        }
    }

    @available(iOS 16.2, *)
    private static func savePushRegistration(token: String, uid: String, activity: Activity<ExamCountdownAttributes>, exam: Exam) async {
        let db = Firestore.firestore()
        let startAt = exam.date.addingTimeInterval(-leadTime)
        var payload: [String: Any] = [
            "pushToken": token,
            "examId": exam.id,
            "userId": uid,
            "startAt": Timestamp(date: startAt),
            "examDate": Timestamp(date: exam.date),
            "title": exam.title,
            "subject": subjectLabel(for: exam) ?? "",
            "accent": currentAccentTheme() ?? "",
            "createdAt": Timestamp(date: Date())
        ]
        if let groupId = exam.groupId { payload["groupId"] = groupId }
        let doc = db.collection("users").document(uid).collection("liveActivities").document(activity.id)
        try? await doc.setData(payload, merge: true)
    }

    @available(iOS 16.2, *)
    private static func removePushRegistration(for activityId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid).collection("liveActivities").document(activityId)
        try? await doc.delete()
    }

    @available(iOS 16.2, *)
    private static func notifyStartIfNeeded(for exam: Exam) async {
        // iOS 17+ nutzt AlertConfiguration für Banner/Haptik.
        if #available(iOS 17.0, *) { return }
        await MainActor.run {
            guard UIApplication.shared.applicationState != .active else { return }
            let content = UNMutableNotificationContent()
            content.title = "Klausur in 90 Minuten"
            if !exam.subjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content.body = "\(exam.title) in \(exam.subjectName)"
            } else {
                content.body = exam.title
            }
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "exam_live_activity_start_\(exam.id)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
#else
enum ExamLiveActivityManager {
    static let leadTime: TimeInterval = 90 * 60
    static func syncLiveActivities(for exams: [Exam]) async {}
}
#endif
