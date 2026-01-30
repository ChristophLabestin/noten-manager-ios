import Foundation
import os.log

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
    private static var autoEndTasks: [String: Task<Void, Never>] = [:]
    private static var pushTokenTasks: [String: Task<Void, Never>] = [:]

    @MainActor
    static func syncLiveActivities(for exams: [Exam]) async {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        // Critical: If exams are not yet loaded (empty array), don't sync.
        // Otherwise we might accidentally end activities that were started via push
        // during a background launch or before Firestore has finished re-fetching.
        guard !exams.isEmpty else { 
            os_log("[syncLiveActivities] Exams array is empty, skipping sync to avoid accidental cancellation.",
                   log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                   type: .default)
            return 
        }

        if #available(iOS 17.2, *) {
            startMonitoringPushToStartToken()
        }

        let now = Date()
        let relevant = exams.filter { $0.hasTime && !$0.isCompleted }
        let activities = Activity<ExamCountdownAttributes>.activities
        var activityMap = Dictionary(activities.map { ($0.attributes.examId, $0) }, uniquingKeysWith: { _, latest in latest })

        for activity in activities {
            os_log("[syncLiveActivities] Found activity for examId=%{public}@, examDate=%{public}@, now=%{public}@",
                   log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                   type: .info,
                   activity.attributes.examId,
                   activity.content.state.examDate.description,
                   now.description)
            
            // Check if we have the exam in our local data
            if let exam = relevant.first(where: { $0.id == activity.attributes.examId }) {
                os_log("[syncLiveActivities] Exam found in local data",
                       log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                       type: .info)
                // Exam found - check if it's still valid for Live Activity
                if exam.date <= now || exam.date.timeIntervalSince(now) > leadTime {
                    os_log("[syncLiveActivities] Ending activity: exam.date=%{public}@, timeUntil=%f",
                           log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                           type: .info,
                           exam.date.description,
                           exam.date.timeIntervalSince(now))
                    cancelAutoEnd(for: activity.id)
                    cancelPushTokenTask(for: activity.id)
                    await end(activity)
                    activityMap[activity.attributes.examId] = nil
                    continue
                }
                // Update the activity with latest content
                let (content, _) = activityContent(for: exam, existing: activity.content.state, includeAlert: false)
                await activity.update(content)
            } else {
                os_log("[syncLiveActivities] Exam NOT in local data, checking activityExamDate",
                       log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                       type: .info)
                // Exam not in local data - but activity might be from a push
                // Only end if the activity's exam date has passed
                let activityExamDate = activity.content.state.examDate
                os_log("[syncLiveActivities] activityExamDate=%{public}@, now=%{public}@, isPast=%d",
                       log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                       type: .info,
                       activityExamDate.description,
                       now.description,
                       activityExamDate <= now ? 1 : 0)
                if activityExamDate <= now {
                    // Exam date has passed, safe to end
                    os_log("[syncLiveActivities] Ending activity - exam date passed",
                           log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                           type: .info)
                    cancelAutoEnd(for: activity.id)
                    cancelPushTokenTask(for: activity.id)
                    await end(activity)
                    activityMap[activity.attributes.examId] = nil
                } else {
                    os_log("[syncLiveActivities] Keeping activity running",
                           log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                           type: .info)
                }
                // Otherwise, keep the activity running (it might be a push-started activity
                // for a shared exam that hasn't loaded yet)
            }
        }

        for exam in relevant where exam.date > now && exam.date.timeIntervalSince(now) <= leadTime {
            if activityMap[exam.id] != nil { continue }
            await start(for: exam)
        }
    }

    @available(iOS 16.2, *)
    @MainActor
    static func start(examId: String, title: String, subject: String?, date: Date, showAlert: Bool = true) async {
        // Check if an activity for this examId already exists
        let existingActivities = Activity<ExamCountdownAttributes>.activities
        if existingActivities.contains(where: { $0.attributes.examId == examId }) {
            // Activity already exists, don't start a duplicate
            return
        }
        
        let attributes = ExamCountdownAttributes(
            examId: examId,
            title: title,
            subject: subject,
            accent: currentAccentTheme()
        )
        // Helper to construct "fake" exam for content calculation logic
        // We reuse contentState logic but need to be careful with leadTime check if we want to force start
        let now = Date()
        let timeTilExam = date.timeIntervalSince(now)
        let actualLeadTime = max(leadTime, timeTilExam)
        let startDate = date.addingTimeInterval(-actualLeadTime)
        let duration = actualLeadTime
        
        let state = ExamCountdownAttributes.ContentState(
            examDate: date,
            title: title,
            subject: subject,
            startDate: startDate,
            duration: duration
        )
        
        let content = ActivityContent(state: state, staleDate: date, relevanceScore: 50)
        
        var alert: AlertConfiguration? = nil
        if showAlert {
            let alertTitle: LocalizedStringResource = "Klausur in 90 Minuten"
            let alertBody: LocalizedStringResource
            if let s = subject, !s.isEmpty {
                alertBody = "\(title) in \(s)"
            } else {
                alertBody = "\(title)"
            }
            
            if #available(iOS 17.0, *) {
                alert = AlertConfiguration(title: alertTitle, body: alertBody, sound: .default)
            }
        }

        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: .token)
            if let alert, #available(iOS 17.0, *) {
                await activity.update(content, alertConfiguration: alert)
            }
            // We assume a full Exam object is needed for token registration, 
            // but for remote start, we might skip re-registering the token immediately 
            // or fetch the full exam asynchronously if needed.
            // For now, we skip registerPushToken since the activity is already started remotely.
            
            scheduleAutoEnd(for: activity, at: date)
            // Note: Removed triggerHaptic() here since AlertConfiguration already provides feedback
        } catch {
            os_log(
                "Failed to start Live Activity (remote data): id=%{public}@ error=%{public}@",
                log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"),
                type: .error,
                examId,
                String(describing: error)
            )
        }
    }

    @available(iOS 16.2, *)
    @MainActor
    private static func start(for exam: Exam) async {
        await start(examId: exam.id, title: exam.title, subject: subjectLabel(for: exam), date: exam.date)
    }

    @available(iOS 16.2, *)
    @MainActor
    private static func end(_ activity: Activity<ExamCountdownAttributes>) async {
        cancelAutoEnd(for: activity.id)
        cancelPushTokenTask(for: activity.id)
        await activity.end(activity.content, dismissalPolicy: .immediate)
        await removePushRegistration(for: activity.id)
    }

    @available(iOS 16.2, *)
    private static func contentState(for exam: Exam, existing: ExamCountdownAttributes.ContentState?) -> ExamCountdownAttributes.ContentState {
        let now = Date()
        let timeTilExam = exam.date.timeIntervalSince(now)
        
        // If we are starting earlier than leadTime (e.g. 92 mins), we adjust 
        // the startDate to NOW so the countdown is not "frozen".
        let actualLeadTime = max(leadTime, timeTilExam)
        let startDate = exam.date.addingTimeInterval(-actualLeadTime)
        let duration = actualLeadTime
        
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
        cancelAutoEnd(for: activity.id)
        let activityId = activity.id
        let delay = date.timeIntervalSinceNow
        let task = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let latest = Activity<ExamCountdownAttributes>.activities.first(where: { $0.id == activityId }) else { return }
            await end(latest)
        }
        autoEndTasks[activityId] = task
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
        cancelPushTokenTask(for: activity.id)
        let task = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await savePushRegistration(token: token, uid: uid, activity: activity, exam: exam)
                // one token is enough; break out
                break
            }
        }
        pushTokenTasks[activity.id] = task
    }

    @available(iOS 16.2, *)
    private static func savePushRegistration(token: String, uid: String, activity: Activity<ExamCountdownAttributes>, exam: Exam) async {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        let db = Firestore.firestore()
        let now = Date()
        let timeTilExam = exam.date.timeIntervalSince(now)
        let actualLeadTime = max(leadTime, timeTilExam)
        let startAt = exam.date.addingTimeInterval(-actualLeadTime)
        
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
        if OfflineModeManager.shared.isOfflineModeActive { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid).collection("liveActivities").document(activityId)
        try? await doc.delete()
    }

    private static func cancelAutoEnd(for id: String) {
        autoEndTasks[id]?.cancel()
        autoEndTasks[id] = nil
    }

    private static func cancelPushTokenTask(for id: String) {
        pushTokenTasks[id]?.cancel()
        pushTokenTasks[id] = nil
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

    // MARK: - Push-to-Start (iOS 17.2+)
    
    @available(iOS 17.2, *)
    private static var pushToStartTask: Task<Void, Never>?

    @MainActor
    static func startMonitoringPushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        guard pushToStartTask == nil else { return }

        pushToStartTask = Task {
            for await tokenData in Activity<ExamCountdownAttributes>.pushToStartTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await uploadPushToStartToken(token)
            }
        }
    }

    @available(iOS 17.2, *)
    private static func uploadPushToStartToken(_ token: String) async {
        if OfflineModeManager.shared.isOfflineModeActive { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let doc = db.collection("users").document(uid).collection("liveActivityTokens").document("examCountdown")
        
        let payload: [String: Any] = [
            "token": token,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        do {
            try await doc.setData(payload, merge: true)
            os_log("Uploaded Push-to-Start token", log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"), type: .info)
        } catch {
            os_log("Failed to upload Push-to-Start token: %{public}@", log: OSLog(subsystem: "de.christophlabestin.noten-manager-ios", category: "LiveActivity"), type: .error, String(describing: error))
        }
    }
}
#else
enum ExamLiveActivityManager {
    static let leadTime: TimeInterval = 90 * 60
    static func syncLiveActivities(for exams: [Exam]) async {}
}
#endif
