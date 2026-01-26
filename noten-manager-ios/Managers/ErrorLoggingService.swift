import Foundation
import UIKit

enum ErrorLoggingService {
    private static let preferenceKey = "allowAnonymousErrorLogging"
    private static let maxStackFrames = 40

    static func logError(
        _ error: Error,
        context: [String: String] = [:],
        includeCallStack: Bool = true,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) async {
        #if DEBUG
        // Don't log to Firestore in debug builds to keep the logs clean.
        // We can still print to console if needed.
        print("DEBUG Error Logging: \(error.localizedDescription) at \(file):\(line)")
        return
        #endif

        guard !(error is CancellationError) else { return }
        guard UserDefaults.standard.bool(forKey: preferenceKey) else { return }

        let nsError = error as NSError
        let userInfo = sanitizeUserInfo(nsError.userInfo)
        let callStack = includeCallStack
            ? Array(Thread.callStackSymbols.prefix(maxStackFrames))
            : []

        let appInfo = await loadAppInfo()
        let deviceState = await loadDeviceState()
        
        let payload = AnonymousErrorLogPayload(
            createdAt: Date(),
            errorType: String(reflecting: type(of: error)),
            errorDescription: error.localizedDescription,
            source: ErrorLogSource(file: file, function: function, line: line),
            context: context,
            errorDomain: nsError.domain,
            errorCode: nsError.code,
            userInfo: userInfo,
            callStack: callStack,
            appInfo: appInfo,
            deviceState: deviceState
        )

        FirestoreService.shared.createAnonymousErrorLog(payload: payload)
    }

    static func logErrorIfEnabled(
        _ error: Error,
        context: [String: String] = [:],
        includeCallStack: Bool = true,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        Task {
            await logError(
                error,
                context: context,
                includeCallStack: includeCallStack,
                file: file,
                function: function,
                line: line
            )
        }
    }

    static func logErrorIfEnabled(
        _ error: Error?,
        context: [String: String] = [:],
        includeCallStack: Bool = true,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard let error else { return }
        logErrorIfEnabled(
            error,
            context: context,
            includeCallStack: includeCallStack,
            file: file,
            function: function,
            line: line
        )
    }

    private static func loadDeviceState() async -> [String: ErrorLogValue] {
        await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            
            // Disk Space
            let freeSpace = (try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64) ?? 0
            
            // Memory Usage (Resident Size)
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
            let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            let memoryMB = kerr == KERN_SUCCESS ? Double(info.resident_size) / 1024.0 / 1024.0 : 0.0
            
            let data: [String: Any] = [
                "batteryLevel": device.batteryLevel,
                "batteryState": String(describing: device.batteryState),
                "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
                "thermalState": String(describing: ProcessInfo.processInfo.thermalState),
                "freeDiskSpaceGB": Double(freeSpace) / 1_000_000_000.0,
                "memoryUsageMB": memoryMB,
                "userInterfaceStyle": UIScreen.main.traitCollection.userInterfaceStyle == .dark ? "dark" : "light",
                "isVoiceOverRunning": UIAccessibility.isVoiceOverRunning,
                "isReduceMotionEnabled": UIAccessibility.isReduceMotionEnabled,
                "topViewController": getTopViewControllerName() ?? "unknown"
            ]
            
            return sanitizeUserInfo(data)
        }
    }

    private static func getTopViewControllerName() -> String? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        
        // Handle NavigationController/TabBarController if needed
        if let nav = topVC as? UINavigationController {
            return String(describing: type(of: nav.visibleViewController ?? nav))
        }
        if let tab = topVC as? UITabBarController {
            return String(describing: type(of: tab.selectedViewController ?? tab))
        }
        
        return String(describing: type(of: topVC))
    }

    private static func loadAppInfo() async -> [String: String] {
        await MainActor.run {
            let bundle = Bundle.main
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            let locale = Locale.current.identifier
            let timeZone = TimeZone.current.identifier
            let systemName = UIDevice.current.systemName
            let systemVersion = UIDevice.current.systemVersion
            let model = UIDevice.current.model
            return [
                "appVersion": version,
                "appBuild": build,
                "locale": locale,
                "timeZone": timeZone,
                "systemName": systemName,
                "systemVersion": systemVersion,
                "deviceModel": model
            ]
        }
    }

    private static func sanitizeUserInfo(_ info: [String: Any]) -> [String: ErrorLogValue] {
        var sanitized: [String: ErrorLogValue] = [:]
        for (key, value) in info {
            if let cleaned = sanitizeValue(value) {
                sanitized[key] = cleaned
            }
        }
        return sanitized
    }

    private static func sanitizeValue(_ value: Any) -> ErrorLogValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let doubleValue = number.doubleValue
            if doubleValue.rounded() == doubleValue {
                return .int(number.intValue)
            }
            return .double(doubleValue)
        case let bool as Bool:
            return .bool(bool)
        case let date as Date:
            return .date(date)
        case let dict as [String: Any]:
            return .object(sanitizeUserInfo(dict))
        case let array as [Any]:
            return .array(array.compactMap { sanitizeValue($0) })
        default:
            return .string(String(describing: value))
        }
    }
}

struct ErrorLogSource: Sendable {
    let file: String
    let function: String
    let line: Int
}

enum ErrorLogValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case array([ErrorLogValue])
    case object([String: ErrorLogValue])

    func toAny() -> Any {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .date(let value):
            return value
        case .array(let values):
            return values.map { $0.toAny() }
        case .object(let values):
            return values.mapValues { $0.toAny() }
        }
    }
}

struct AnonymousErrorLogPayload: Sendable {
    let createdAt: Date
    let errorType: String
    let errorDescription: String
    let source: ErrorLogSource
    let context: [String: String]
    let errorDomain: String
    let errorCode: Int
    let userInfo: [String: ErrorLogValue]
    let callStack: [String]
    let appInfo: [String: String]
    let deviceState: [String: ErrorLogValue]

    func firestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "createdAt": createdAt,
            "errorType": errorType,
            "errorDescription": errorDescription,
            "source": [
                "file": source.file,
                "function": source.function,
                "line": source.line
            ],
            "context": context,
            "errorDomain": errorDomain,
            "errorCode": errorCode,
            "userInfo": userInfo.mapValues { $0.toAny() },
            "appInfo": appInfo,
            "deviceState": deviceState.mapValues { $0.toAny() }
        ]
        if !callStack.isEmpty {
            data["callStack"] = callStack
        }
        return data
    }
}