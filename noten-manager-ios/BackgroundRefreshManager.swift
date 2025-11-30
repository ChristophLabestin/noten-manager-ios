import Foundation
import BackgroundTasks
import UIKit

enum BackgroundRefreshManager {
    static let refreshTaskId = "de.christophlabestin.noten-manager-ios.refresh"
    static let liveActivityTaskId = "de.christophlabestin.noten-manager-ios.liveactivity"

    static func register() {
        guard #available(iOS 13.0, *) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            handle(task: task as? BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: liveActivityTaskId, using: nil) { task in
            handle(processingTask: task as? BGProcessingTask)
        }
    }

    static func schedule(for exams: [Exam]? = nil) {
        guard #available(iOS 13.0, *) else { return }
        scheduleAppRefresh(for: exams)
        scheduleProcessing(for: exams)
    }

    @available(iOS 13.0, *)
    private static func handle(task: BGAppRefreshTask?) {
        guard let task else { return }
        // Always reschedule for the future.
        schedule()

        let work = Task {
            _ = await refreshLiveActivitiesFromSnapshot()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }

    @available(iOS 13.0, *)
    private static func handle(processingTask task: BGProcessingTask?) {
        guard let task else { return }
        schedule()

        let work = Task {
            _ = await refreshLiveActivitiesFromSnapshot()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
        }
    }

    @discardableResult
    static func refreshLiveActivitiesFromSnapshot() async -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        guard let snapshot = OfflineModeManager.shared.availableSnapshot() else { return false }
        // Only consider upcoming exams within the next 90 minutes (lead time) and with a time set.
        let now = Date()
        let allSnapshotExams = snapshot.exams + snapshot.sharedExams
        let upcoming = allSnapshotExams.filter { exam in
            guard exam.hasTime, !exam.isCompleted else { return false }
            let delta = exam.date.timeIntervalSince(now)
            return delta > 0 && delta <= ExamLiveActivityManager.leadTime
        }
        await ExamLiveActivityManager.syncLiveActivities(for: upcoming)
        schedule(for: allSnapshotExams)
        return true
    }

    static func performBackgroundFetch(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            let succeeded = await refreshLiveActivitiesFromSnapshot()
            completion(succeeded ? UIBackgroundFetchResult.newData : UIBackgroundFetchResult.noData)
        }
    }

    @available(iOS 16.2, *)
    private static func nextLiveActivityStart(from exams: [Exam]?) -> Date? {
        guard let exams else { return nil }
        let now = Date()
        let candidates = exams
            .filter { $0.hasTime && !$0.isCompleted }
            .compactMap { exam -> Date? in
                let start = exam.date.addingTimeInterval(-ExamLiveActivityManager.leadTime)
                return start > now ? start : nil
            }
        return candidates.min()
    }

    @available(iOS 13.0, *)
    private static func scheduleAppRefresh(for exams: [Exam]?) {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        if #available(iOS 16.2, *), let next = nextLiveActivityStart(from: exams) {
            request.earliestBeginDate = max(Date(), next.addingTimeInterval(-120))
        } else {
            request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        }
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // optional logging
        }
    }

    @available(iOS 13.0, *)
    private static func scheduleProcessing(for exams: [Exam]?) {
        let request = BGProcessingTaskRequest(identifier: liveActivityTaskId)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        if #available(iOS 16.2, *), let next = nextLiveActivityStart(from: exams) {
            request.earliestBeginDate = max(Date(), next.addingTimeInterval(-120))
        }
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // optional logging
        }
    }
}
