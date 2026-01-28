import Foundation
import BackgroundTasks
import UIKit
import os.log

enum BackgroundRefreshManager {
    static let refreshTaskId = "de.christophlabestin.noten-manager-ios.refresh"
    static let liveActivityTaskId = "de.christophlabestin.noten-manager-ios.liveactivity"
    private static let liveActivityLeadTime: TimeInterval = 90 * 60
    private static let snapshotFileName = "offline-cache.json"
    private static let appGroupId = "group.de.christophlabestin.noten-manager-ios"
    private static func makeLog() -> OSLog {
        OSLog(
            subsystem: "de.christophlabestin.noten-manager-ios",
            category: "BackgroundRefresh"
        )
    }

    private enum TaskKind: String {
        case appRefresh = "app_refresh"
        case processing = "processing"
    }

    private struct BackgroundWorkResult: Sendable {
        let success: Bool
        let didSync: Bool
    }

    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isCompleted = false
        private let task: BGTask
        let taskId: String

        init(task: BGTask) {
            self.task = task
            self.taskId = task.identifier
        }

        @discardableResult
        func complete(success: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isCompleted else { return false }
            isCompleted = true
            task.setTaskCompleted(success: success)
            return true
        }
    }

    static func register() {
        guard #available(iOS 13.0, *) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: .main) { task in
            handle(task: task, kind: .appRefresh)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: liveActivityTaskId, using: .main) { task in
            handle(task: task, kind: .processing)
        }
    }

    static func schedule(for exams: [Exam]? = nil) {
        guard #available(iOS 13.0, *) else { return }
        scheduleAppRefresh(for: exams)
        scheduleProcessing(for: exams)
    }

    @available(iOS 13.0, *)
    private static func handle(task: BGTask, kind: TaskKind) {
        task.expirationHandler = {
            os_log(
                "BGTask expired kind=%{public}@ id=%{public}@",
                log: makeLog(),
                type: .info,
                kind.rawValue,
                task.identifier
            )
        }

        switch kind {
        case .appRefresh:
            guard task is BGAppRefreshTask else {
                os_log(
                    "BGTask type mismatch (expected app refresh): %{public}@",
                    log: makeLog(),
                    type: .error,
                    task.identifier
                )
                task.setTaskCompleted(success: false)
                return
            }
        case .processing:
            guard task is BGProcessingTask else {
                os_log(
                    "BGTask type mismatch (expected processing): %{public}@",
                    log: makeLog(),
                    type: .error,
                    task.identifier
                )
                task.setTaskCompleted(success: false)
                return
            }
        }
        // Always reschedule for the future.
        schedule()

        os_log(
            "BGTask handler started kind=%{public}@ id=%{public}@ mainThread=%{public}d",
            log: makeLog(),
            type: .info,
            kind.rawValue,
            task.identifier,
            Thread.isMainThread ? 1 : 0
        )

        if UIApplication.shared.isProtectedDataAvailable == false {
            os_log(
                "BGTask aborted (protected data) kind=%{public}@ id=%{public}@",
                log: makeLog(),
                type: .info,
                kind.rawValue,
                task.identifier
            )
            task.setTaskCompleted(success: false)
            return
        }

        let completion = CompletionGate(task: task)
        let taskId = completion.taskId
        let work = Task.detached(priority: .background) { [kind, taskId] in
            let log = OSLog(
                subsystem: "de.christophlabestin.noten-manager-ios",
                category: "BackgroundRefresh"
            )
            do {
                os_log(
                    "BGTask work started kind=%{public}@ id=%{public}@",
                    log: log,
                    type: .info,
                    kind.rawValue,
                    taskId
                )
                try Task.checkCancellation()
                let didSync = await refreshLiveActivitiesFromSnapshotInBackground()
                try Task.checkCancellation()
                os_log(
                    "BGTask work finished kind=%{public}@ id=%{public}@ didSync=%{public}d",
                    log: log,
                    type: .info,
                    kind.rawValue,
                    taskId,
                    didSync ? 1 : 0
                )
                return BackgroundWorkResult(success: true, didSync: didSync)
            } catch is CancellationError {
                os_log(
                    "BGTask cancelled kind=%{public}@ id=%{public}@",
                    log: log,
                    type: .info,
                    kind.rawValue,
                    taskId
                )
                return BackgroundWorkResult(success: false, didSync: false)
            } catch {
                Task { @MainActor in
                    ErrorLoggingService.logErrorIfEnabled(error)
                }
                os_log(
                    "BGTask failed kind=%{public}@ id=%{public}@ error=%{public}@",
                    log: log,
                    type: .error,
                    kind.rawValue,
                    taskId,
                    String(describing: error)
                )
                return BackgroundWorkResult(success: false, didSync: false)
            }
        }

        Task { @MainActor in
            let result = await work.value
            if completion.complete(success: result.success) {
                os_log(
                    "BGTask completed kind=%{public}@ id=%{public}@ success=%{public}d",
                    log: makeLog(),
                    type: .info,
                    kind.rawValue,
                    taskId,
                    result.success ? 1 : 0
                )
            }
        }
    }

    @MainActor
    @discardableResult
    static func refreshLiveActivitiesFromSnapshot() async -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        guard let snapshot = OfflineModeManager.shared.availableSnapshot() else { return false }
        return await refreshLiveActivities(using: snapshot)
    }

    static func performBackgroundFetch(completion: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            let succeeded = await refreshLiveActivitiesFromSnapshotInBackground()
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
                let start = exam.date.addingTimeInterval(-liveActivityLeadTime)
                return start > now ? start : nil
            }
        return candidates.min()
    }

    @available(iOS 13.0, *)
    private static func scheduleAppRefresh(for exams: [Exam]?) {
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            os_log(
                "Background App Refresh is disabled/restricted. Skipping scheduleAppRefresh.",
                log: makeLog(),
                type: .default
            )
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        if #available(iOS 16.2, *), let next = nextLiveActivityStart(from: exams) {
            request.earliestBeginDate = max(Date(), next.addingTimeInterval(-120))
        } else {
            request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        }

        os_log(
            "Attempting to submit BGAppRefreshTaskRequest: id=%{public}@, earliestBeginDate=%{public}@",
            log: makeLog(),
            type: .info,
            refreshTaskId,
            String(describing: request.earliestBeginDate)
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            os_log(
                "Successfully scheduled app refresh: %{public}@",
                log: makeLog(),
                type: .info,
                refreshTaskId
            )
        } catch {
            let errorCode = (error as NSError).code
            os_log(
                "BGTaskScheduler error while scheduling app refresh: id=%{public}@, code=%ld, description=%{public}@",
                log: makeLog(),
                type: .error,
                refreshTaskId,
                errorCode,
                error.localizedDescription
            )
            Task { @MainActor in
                ErrorLoggingService.logErrorIfEnabled(error)
            }
        } catch {
            os_log(
                "Generic error while scheduling app refresh: id=%{public}@, error=%{public}@",
                log: makeLog(),
                type: .error,
                refreshTaskId,
                error.localizedDescription
            )
            Task { @MainActor in
                ErrorLoggingService.logErrorIfEnabled(error)
            }
        }
    }

    @available(iOS 13.0, *)
    private static func scheduleProcessing(for exams: [Exam]?) {
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            os_log(
                "Background App Refresh is disabled/restricted. Skipping scheduleProcessing.",
                log: makeLog(),
                type: .default
            )
            return
        }

        let request = BGProcessingTaskRequest(identifier: liveActivityTaskId)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        if #available(iOS 16.2, *), let next = nextLiveActivityStart(from: exams) {
            request.earliestBeginDate = max(Date(), next.addingTimeInterval(-120))
        }

        os_log(
            "Attempting to submit BGProcessingTaskRequest: id=%{public}@, earliestBeginDate=%{public}@",
            log: makeLog(),
            type: .info,
            liveActivityTaskId,
            String(describing: request.earliestBeginDate)
        )

        do {
            try BGTaskScheduler.shared.submit(request)
            os_log(
                "Successfully scheduled processing task: %{public}@",
                log: makeLog(),
                type: .info,
                liveActivityTaskId
            )
        } catch {
            let errorCode = (error as NSError).code
            os_log(
                "BGTaskScheduler error while scheduling processing task: id=%{public}@, code=%ld, description=%{public}@",
                log: makeLog(),
                type: .error,
                liveActivityTaskId,
                errorCode,
                error.localizedDescription
            )
            Task { @MainActor in
                ErrorLoggingService.logErrorIfEnabled(error)
            }
        } catch {
            os_log(
                "Generic error while scheduling processing task: id=%{public}@, error=%{public}@",
                log: makeLog(),
                type: .error,
                liveActivityTaskId,
                error.localizedDescription
            )
            Task { @MainActor in
                ErrorLoggingService.logErrorIfEnabled(error)
            }
        }
    }

    @available(iOS 16.2, *)
    @MainActor
    private static func syncLiveActivitiesOnMain(for exams: [Exam]) async {
        await ExamLiveActivityManager.syncLiveActivities(for: exams)
    }

    @discardableResult
    private static func refreshLiveActivitiesFromSnapshotInBackground() async -> Bool {
        guard #available(iOS 16.2, *) else { return false }
        guard !Task.isCancelled else { return false }
        guard let snapshot = loadOfflineSnapshotForBackground() else { return false }
        return await refreshLiveActivities(using: snapshot)
    }

    @available(iOS 16.2, *)
    @discardableResult
    private static func refreshLiveActivities(using snapshot: OfflineSnapshot) async -> Bool {
        guard !Task.isCancelled else { return false }
        // Only consider upcoming exams within the next 90 minutes (lead time) and with a time set.
        let now = Date()
        let allSnapshotExams = snapshot.exams + snapshot.sharedExams
        let upcoming = allSnapshotExams.filter { exam in
            guard exam.hasTime, !exam.isCompleted else { return false }
            let delta = exam.date.timeIntervalSince(now)
            return delta > 0 && delta <= liveActivityLeadTime
        }
        guard !Task.isCancelled else { return false }
        await syncLiveActivitiesOnMain(for: upcoming)
        guard !Task.isCancelled else { return false }
        schedule(for: allSnapshotExams)
        return true
    }

    private static func loadOfflineSnapshotForBackground() -> OfflineSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        func decode(at url: URL) -> OfflineSnapshot? {
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(OfflineSnapshot.self, from: data)
            } catch {
                Task { @MainActor in
                    ErrorLoggingService.logErrorIfEnabled(error)
                }
                os_log(
                    "Failed to decode snapshot at %{public}@ error=%{public}@",
                    log: makeLog(),
                    type: .error,
                    url.path,
                    String(describing: error)
                )
                return nil
            }
        }

        if let sharedURL = sharedSnapshotURL(),
           FileManager.default.isReadableFile(atPath: sharedURL.path),
           let snapshot = decode(at: sharedURL) {
            return snapshot
        }

        if let url = snapshotURL(),
           FileManager.default.isReadableFile(atPath: url.path) {
            return decode(at: url)
        }

        return nil
    }

    private static func snapshotURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(snapshotFileName)
    }

    private static func sharedSnapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(snapshotFileName)
    }
}
