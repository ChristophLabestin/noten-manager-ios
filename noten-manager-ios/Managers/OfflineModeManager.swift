import Foundation
import Network
import Combine
import FirebaseFirestore
import WidgetKit



@MainActor
final class OfflineModeManager: ObservableObject {
    static let shared = OfflineModeManager()

    @Published private(set) var isOfflineModeActive: Bool = false
    @Published private(set) var cachedSnapshot: OfflineSnapshot?
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var networkStatusReady: Bool = false
    @Published private(set) var isManualOfflinePinned: Bool = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "OfflineModeMonitor")
    private let defaults = UserDefaults.standard
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var pendingSaveTask: Task<Void, Never>?
    private var monitorStarted: Bool = false
    private var firestoreNetworkSuppressed: Bool = false

    private let lastLoginKey = "offline_last_login"
    private let lastLoginUidKey = "offline_last_login_uid"
    private let manualOfflineKey = "offline_manual_mode_active"
    private let snapshotFileName = "offline-cache.json"
    private let offlineWindow: TimeInterval = 60 * 60 * 24 * 3 // 3 Tage
    private let appGroupId = "group.de.christophlabestin.noten-manager-ios"

    init() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec

        cachedSnapshot = try? loadSnapshotFromDisk()

        isManualOfflinePinned = defaults.bool(forKey: manualOfflineKey)
        if isManualOfflinePinned {
            isOfflineModeActive = true
            disableFirestoreNetwork()
        }
    }

    func startMonitoring() {
        guard !monitorStarted else { return }
        monitorStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status != .unsatisfied)
                self?.networkStatusReady = true
            }
        }
        monitor.start(queue: monitorQueue)
        isOnline = (monitor.currentPath.status != .unsatisfied)
        networkStatusReady = true
    }

    func recordOnlineLogin(uid: String) {
        defaults.set(Date(), forKey: lastLoginKey)
        defaults.set(uid, forKey: lastLoginUidKey)
        if !isManualOfflinePinned {
            deactivateOfflineMode(resetManualPin: false)
        }
    }

    var lastLoginDate: Date? {
        defaults.object(forKey: lastLoginKey) as? Date
    }

    var lastLoginUserId: String? {
        defaults.string(forKey: lastLoginUidKey)
    }

    func isOfflineLoginAllowed(for uid: String?) -> Bool {
        guard let last = lastLoginDate else { return false }
        guard let snapshot = cachedSnapshot ?? (try? loadSnapshotFromDisk()) else { return false }
        guard Date().timeIntervalSince(last) <= offlineWindow else { return false }
        if let uid, snapshot.userId != uid { return false }
        return true
    }

    func loadSnapshotAsync() async -> OfflineSnapshot? {
        if let snapshot = cachedSnapshot {
            return snapshot
        }
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return nil }
            return try? self.loadSnapshotFromDisk()
        }.value
    }

    func availableSnapshot() -> OfflineSnapshot? {
        if let snapshot = cachedSnapshot {
            return snapshot
        }
        return try? loadSnapshotFromDisk()
    }

    func activateOfflineMode(manual: Bool = false) {
        isOfflineModeActive = true
        if manual { setManualOfflinePinned(true) }
        disableFirestoreNetwork()
    }

    func deactivateOfflineMode(resetManualPin: Bool = true) {
        isOfflineModeActive = false
        if resetManualPin { setManualOfflinePinned(false) }
        enableFirestoreNetworkIfNeeded()
    }

    func clearOfflineData() {
        cachedSnapshot = nil
        isOfflineModeActive = false
        setManualOfflinePinned(false)
        defaults.removeObject(forKey: lastLoginKey)
        defaults.removeObject(forKey: lastLoginUidKey)
        try? FileManager.default.removeItem(at: snapshotURL())
        enableFirestoreNetworkIfNeeded()
    }

    func saveSnapshot(from store: GradesStore, userId: String) async {
        let snapshot = store.makeOfflineSnapshot(userId: userId)
        await persist(snapshot: snapshot)
    }

    func scheduleSnapshotSave(from store: GradesStore, userId: String) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // leicht entkoppeln
            await self?.saveSnapshot(from: store, userId: userId)
        }
    }

    private func persist(snapshot: OfflineSnapshot) async {
        do {
            // Encode on the main actor (sync) but offload file I/O to a background task.
            let data = try encoder.encode(snapshot)
            let targetURL = snapshotURL()
            let sharedURL = sharedSnapshotURL()
            try await Task.detached(priority: .utility) {
                try data.write(to: targetURL, options: .atomic)
                if let sharedURL {
                    try? FileManager.default.createDirectory(at: sharedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: sharedURL, options: .atomic)
                }
            }.value
            cachedSnapshot = snapshot
            refreshWidgets()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional: logging
        }
    }

    nonisolated private func loadSnapshotFromDisk() throws -> OfflineSnapshot {
        if let sharedURL = sharedSnapshotURL(),
           let sharedData = try? Data(contentsOf: sharedURL) {
            return try decoder.decode(OfflineSnapshot.self, from: sharedData)
        }
        let data = try Data(contentsOf: snapshotURL())
        return try decoder.decode(OfflineSnapshot.self, from: data)
    }

    nonisolated private func snapshotURL() -> URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir.appendingPathComponent(snapshotFileName)
        }
        // Extremely defensive: fall back to temporary directory to avoid crashing if documentsDir is unavailable.
        return FileManager.default.temporaryDirectory.appendingPathComponent(snapshotFileName)
    }

    nonisolated private func sharedSnapshotURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId)?
            .appendingPathComponent(snapshotFileName)
    }

    private func persistSnapshotToSharedContainer(_ data: Data) {
        guard let target = sharedSnapshotURL() else { return }
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional: logging
        }
    }

    private func refreshWidgets() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func setManualOfflinePinned(_ active: Bool) {
        isManualOfflinePinned = active
        defaults.set(active, forKey: manualOfflineKey)
    }

    private func disableFirestoreNetwork() {
        guard !firestoreNetworkSuppressed else { return }
        firestoreNetworkSuppressed = true
        Task {
            try? await Firestore.firestore().disableNetwork()
        }
    }

    func enableFirestoreNetworkIfNeeded() {
        guard firestoreNetworkSuppressed else { return }
        firestoreNetworkSuppressed = false
        Task {
            try? await Firestore.firestore().enableNetwork()
        }
    }
}
