import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import SwiftUI
import UIKit

enum SchoolYearError: Error {
    case creationBlocked
}

enum SchoolYearService {
    static func currentSchoolYearId(from date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let startYear = month >= 8 ? year : year - 1
        let endYear = startYear + 1
        let endSuffix = String(format: "%02d", endYear % 100)
        return "\(startYear)-\(endSuffix)"
    }

    static func nextSchoolYearId(from currentId: String?) -> String {
        guard
            let id = currentId?.trimmingCharacters(in: .whitespacesAndNewlines),
            id.count >= 7,
            let start = Int(id.prefix(4))
        else {
            let current = currentSchoolYearId()
            return nextSchoolYearId(from: current)
        }
        let nextStart = start + 1
        let endYear = nextStart + 1
        let endSuffix = String(format: "%02d", endYear % 100)
        return "\(nextStart)-\(endSuffix)"
    }

    static func ensureActiveSchoolYear(
        uid: String,
        userData: [String: Any]? = nil,
        preferredId: String? = nil,
        db: Firestore = Firestore.firestore(),
        skipLegacyMigration: Bool = false,
        allowCreation: Bool = true,
        gateOnOnboarding: Bool = true,
        allowLegacyMigration: Bool = false,
        allowedLegacySubjects: Set<String>? = nil,
        setMigratedFlag: Bool = true
    ) async throws -> String {
        let userRef = db.collection("users").document(uid)
        let existingData: [String: Any]
        if let userData {
            existingData = userData
        } else {
            let snap = try await userRef.getDocument()
            existingData = snap.data() ?? [:]
        }
        let onboardingCompleted = (existingData["onboardingCompleted"] as? Bool) ?? false
        let migrated = (existingData["migratedToSchoolYears"] as? Bool) ?? false
        let existingActive = (existingData["activeSchoolYearId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyDecisionPending = (existingData["legacyDecisionPending"] as? Bool) ?? false
        let hasLegacyFields = existingData["gradeYear"] != nil
            || existingData["groupIds"] != nil
            || existingData["examGroupId"] != nil
            || existingData["homeworkGroupId"] != nil
            || existingData["examGroupIds"] != nil
            || existingData["homeworkGroupIds"] != nil
        let onboardingReady = onboardingCompleted && migrated && !legacyDecisionPending && !hasLegacyFields

        if gateOnOnboarding && !onboardingReady {
            if let existingActive, !existingActive.isEmpty {
                return existingActive
            } else {
                throw SchoolYearError.creationBlocked
            }
        }

        let preferredTrimmed = preferredId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeId = existingActive
        let targetId = (preferredTrimmed?.isEmpty == false ? preferredTrimmed : nil)
            ?? (activeId?.isEmpty == false ? activeId : nil)
            ?? currentSchoolYearId()

        let yearRef = userRef.collection("schoolYears").document(targetId)
        let yearSnap = try await yearRef.getDocument()
        let currentYearData = yearSnap.data() ?? [:]
        var yearPayload: [String: Any] = [
            "name": targetId,
            "createdAt": Date()
        ]
        let effectiveLegacyMigration = allowLegacyMigration && !skipLegacyMigration && hasLegacyFields

        if effectiveLegacyMigration {
            if let g = existingData["groupIds"] { yearPayload["groupIds"] = g }
            if let g = existingData["examGroupIds"] { yearPayload["examGroupIds"] = g }
            if let g = existingData["homeworkGroupIds"] { yearPayload["homeworkGroupIds"] = g }
            if let g = existingData["examGroupId"] { yearPayload["examGroupId"] = g }
            if let g = existingData["homeworkGroupId"] { yearPayload["homeworkGroupId"] = g }
            if let gy = existingData["gradeYear"] { yearPayload["gradeYear"] = gy }
        }
        if !yearSnap.exists {
            guard allowCreation else { throw SchoolYearError.creationBlocked }
            try await yearRef.setData(yearPayload, merge: true)
        } else if yearSnap.data()?.isEmpty == true {
            guard allowCreation else { throw SchoolYearError.creationBlocked }
            try await yearRef.setData(yearPayload, merge: true)
        } else {
            var missingPayload: [String: Any] = [:]
            let emptyOrMissingArray: (Any?) -> Bool = { value in
                guard let arr = value as? [Any] else { return true }
                return arr.isEmpty
            }
            if effectiveLegacyMigration && (currentYearData["groupIds"] == nil || emptyOrMissingArray(currentYearData["groupIds"])) {
                if let g = existingData["groupIds"] { missingPayload["groupIds"] = g }
            }
            if effectiveLegacyMigration && (currentYearData["examGroupIds"] == nil || emptyOrMissingArray(currentYearData["examGroupIds"])) {
                if let g = existingData["examGroupIds"] { missingPayload["examGroupIds"] = g }
            }
            if effectiveLegacyMigration && (currentYearData["homeworkGroupIds"] == nil || emptyOrMissingArray(currentYearData["homeworkGroupIds"])) {
                if let g = existingData["homeworkGroupIds"] { missingPayload["homeworkGroupIds"] = g }
            }
            if effectiveLegacyMigration && currentYearData["examGroupId"] == nil, let g = existingData["examGroupId"] { missingPayload["examGroupId"] = g }
            if effectiveLegacyMigration && currentYearData["homeworkGroupId"] == nil, let g = existingData["homeworkGroupId"] { missingPayload["homeworkGroupId"] = g }
            if effectiveLegacyMigration && currentYearData["gradeYear"] == nil, let gy = existingData["gradeYear"] { missingPayload["gradeYear"] = gy }
            if !missingPayload.isEmpty {
                try await yearRef.setData(missingPayload, merge: true)
            }
        }

        if effectiveLegacyMigration {
            try await migrateLegacyDataIfNeeded(userRef: userRef, yearRef: yearRef, allowedSubjects: allowedLegacySubjects)
        }

        var userUpdate: [String: Any] = [
            "activeSchoolYearId": targetId,
            "legacyDecisionPending": false
        ]
        if setMigratedFlag {
            userUpdate["migratedToSchoolYears"] = true
        }

        try await userRef.setData(userUpdate, merge: true)

        return targetId
    }

    static func migrateLegacyDataIfNeeded(userRef: DocumentReference, yearRef: DocumentReference, allowedSubjects: Set<String>? = nil) async throws {
        let snap = try await userRef.getDocument()
        if (snap.data()?["migratedToSchoolYears"] as? Bool) == true { return }
        let legacyData = snap.data() ?? [:]

        let legacySubjects = try await userRef.collection("subjects").getDocuments()
        for subject in legacySubjects.documents {
            if let allowed = allowedSubjects, !allowed.contains(subject.documentID) { continue }
            let dest = yearRef.collection("subjects").document(subject.documentID)
            try await dest.setData(subject.data(), merge: true)

            let gradesSnap = try await subject.reference.collection("grades").getDocuments()
            for grade in gradesSnap.documents {
                try await dest.collection("grades").document(grade.documentID).setData(grade.data(), merge: true)
            }
        }

        let simpleCollections = [
            "fachreferat",
            "practicalPerformance",
            "homeworks",
            "exams",
            "examGroupReminders",
            "homeworkGroupReminders",
            "examGroupCompleted",
            "homeworkGroupCompleted",
            "subjectMappings",
            "groupMappings"
        ]
        for name in simpleCollections {
            try await copyCollectionIfExists(from: userRef.collection(name), to: yearRef.collection(name))
        }

        var groupPayload: [String: Any] = [:]
        if let g = legacyData["groupIds"] { groupPayload["groupIds"] = g }
        if let g = legacyData["examGroupIds"] { groupPayload["examGroupIds"] = g }
        if let g = legacyData["homeworkGroupIds"] { groupPayload["homeworkGroupIds"] = g }
        if let g = legacyData["examGroupId"] { groupPayload["examGroupId"] = g }
        if let g = legacyData["homeworkGroupId"] { groupPayload["homeworkGroupId"] = g }
        if let gy = legacyData["gradeYear"] { groupPayload["gradeYear"] = gy }
        if !groupPayload.isEmpty {
            try await yearRef.setData(groupPayload, merge: true)
        }

        try await userRef.setData([
            "migratedToSchoolYears": true,
            "legacyDecisionPending": false
        ], merge: true)
    }

    private static func copyCollectionIfExists(from source: CollectionReference, to target: CollectionReference) async throws {
        let snap = try await source.getDocuments()
        guard !snap.isEmpty else { return }
        for doc in snap.documents {
            try await target.document(doc.documentID).setData(doc.data(), merge: true)
        }
    }
}

struct SchoolYearSnapshot {
    let id: String
    let gradeYear: Int?
    let schoolType: SchoolType?
    let subjects: [Subject]
    let gradesBySubject: [String: [GradeWithId]]
    let seminarPerformance: SeminarPerformance?
    let practicalPerformance: PracticalPerformance?
}

struct PendingGrade: Codable, Identifiable {
    let id: String
    let subjectId: String
    let grade: Double
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int?
    let linkedExamId: String?
    let createdAt: Date
}

struct PendingFachreferat: Codable {
    let subjectName: String
    let grade: Double
    let date: Date
    let note: String?
    let createdAt: Date
}

struct PendingSeminarPerformance: Codable {
    let topic: String?
    let individualPoints: Double?
    let paperPoints: Double?
    let presentationPoints: Double?
    let submissionDate: Date?
    let presentationDate: Date?
    let note: String?
    let createdAt: Date
}

struct LegacyMigrationSummary: Equatable {
    let subjectCount: Int
    let gradeCount: Int
    let homeworkCount: Int
    let examCount: Int
    let gradeYear: Int?
    let subjectNames: [String]
}

struct SchoolClass: Identifiable, Codable {
    let id: String // Code
    let name: String
    let ownerId: String
    let groupIds: [String]
    let createdAt: Date
    var config: ClassConfiguration?
    // Display helper
    var fetchedGroups: [GroupDetails]?
    var memberCount: Int?
}

struct GroupDetails: Identifiable, Codable {
    let id: String
    let name: String
    let memberCount: Int
    let subjectCount: Int
}

@MainActor
final class GradesStore: ObservableObject {
    @Published var subjects: [Subject] = []
    @Published var gradesBySubject: [String: [GradeWithId]] = [:] // Key = subjectId (name)
    @Published var fachreferat: Fachreferat?
    @Published var seminarPerformance: SeminarPerformance?
    @Published var practicalPerformance: PracticalPerformance?
    @Published var examPoints: [String: Double?] = [:] // Key = subjectName
    @Published var homeworks: [Homework] = []
    @Published var exams: [Exam] = []            // Eigene Prüfungen
    @Published var sharedExams: [Exam] = []      // Prüfungen aus gemeinsamer Gruppe
    @Published var sharedHomeworks: [Homework] = []      // Hausaufgaben aus gemeinsamer Gruppe
    @Published var examGroupId: String? = nil    // Aktuelle Prüfungsgruppe
    @Published var homeworkGroupId: String? = nil

    // Neue gemeinsame Gruppen-Verwaltung
    @Published var groupIds: [String] = []
    @Published var groupNames: [String: String] = [:] // gid -> name
    @Published var groupBranchNames: [String: String] = [:] // gid -> migratedBranchName
    @Published var groupMigratedToClassIds: [String: String] = [:] // gid -> classId
    @Published var groupOwners: [String: String] = [:] // gid -> ownerId
    @Published var groupMemberIds: [String: Set<String>] = [:] // gid -> userIds
    @Published var groupSubjectsByGroup: [String: [GroupSubject]] = [:] // gid -> subjects
    @Published var groupSubjectMappings: [String: [String: String]] = [:] // gid -> subjectKey -> local name
    @Published var groupExamsByGroup: [String: [Exam]] = [:]
    @Published var groupHomeworksByGroup: [String: [Homework]] = [:]
    private var schoolYearSnapshotCache: [String: SchoolYearSnapshot] = [:]

    @Published var schoolYears: [String] = []
    @Published var schoolYearNames: [String: String] = [:]

    // Classes (Klassen)
    @Published var classIds: [String] = []
    @Published var classNames: [String: String] = [:]
    @Published var classOwners: [String: String] = [:]
    @Published var classDetails: [String: SchoolClass] = [:]

    // Gemeinsame Gruppen-ID (Konzept: eine Gruppe für Klausuren & Hausaufgaben)
    var sharedGroupId: String? {
        get { examGroupId ?? homeworkGroupId }
        set {
            examGroupId = newValue
            homeworkGroupId = newValue
        }
    }

    @Published var examGroupIds: [String] = []
    @Published var homeworkGroupIds: [String] = []
    @Published var examGroupName: String? = nil
    @Published var homeworkGroupName: String? = nil

    @Published var encryptionKey: SymmetricKey?
    @Published var isLoading: Bool = false
    @Published var loadingLabel: String = ""
    @Published var progress: Double = 0.0
    @Published var subjectSortMode: SubjectSortMode = .name
    @Published var subjectSortOrder: [String] = []
    @Published var subjectCustomOrder: [String] = []
    @Published var compactView: Bool = false
    @Published var animationsEnabled: Bool = true

    // Settings-Erweiterungen (aus React)
    @Published var appIcon: String = "default" // "default" | "pink"
    @Published var theme: String = "default" // "default" | "feminine"
    @Published var themeBackgroundIntensity: Double = 1.0 // 0...1
    @Published var darkMode: Bool = false
    @Published var darkModeMode: String = "system" // "system" | "light" | "dark"
    @Published var homeworkReminderHour: Int = 19
    @Published var homeworkReminderMinute: Int = 0
    @Published var standardRemindersEnabled: Bool = true
    @Published var encryptionSalt: String? = nil
    @Published var showHolidayHints: Bool = true
    @Published var userName: String? = nil
    @Published var isPrivacyModeActive: Bool = false

    var preferredColorScheme: ColorScheme? {
        switch darkModeMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
    @Published var gradeYear: Int? = nil // 11, 12 oder 13
    @Published var schoolType: SchoolType = .bos
    @Published var activeSchoolYearId: String? = nil // z. B. "2025-26"
    @Published var onboardingRequired: Bool = false
    @Published var isOfflineMode: Bool = false
    @Published var legacyMigrationSummary: LegacyMigrationSummary? = nil
    @Published var legacySelectedSubjects: Set<String> = []
    @Published var legacyCheckPending: Bool = true

    // New published properties for group subjects and mappings
    @Published var examGroupSubjects: [GroupSubject] = []
    @Published var homeworkGroupSubjects: [GroupSubject] = []
    @Published var examSubjectMapping: [String: String] = [:] // subjectKey -> local subject name
    @Published var homeworkSubjectMapping: [String: String] = [:]

    // Admin support access
    @Published var adminAccessGranted: Bool = false
    @Published var adminAccessExpiresAt: Date? = nil
    @Published var supportAccessRequests: [SupportAccessRequest] = []

    // Course-Based Architecture
    @Published var subscribedCourseIds: [String] = []
    @Published var courses: [Course] = []
    @Published var migratedGroupIds: Set<String> = [] // Groups that have been upgraded to Classes



    private let db = Firestore.firestore()
    private let pfingstferienPromptedKey = "grades_pfingst_prompted_year_ids"
    private let appIconDefaultsKey = "grades_appIcon"
    private let supportedAppIcons: Set<String> = ["default", "pink"]

    // Live-Listener
    private var userDocListener: ListenerRegistration?
    private var schoolYearListener: ListenerRegistration?
    private var schoolYearListenerId: String?
    private var subjectsListener: ListenerRegistration?
    private var fachreferatListener: ListenerRegistration?
    private var seminarPerformanceListener: ListenerRegistration?
    private var practicalPerformanceListener: ListenerRegistration?
    private var homeworksListener: ListenerRegistration?
    private var examsListener: ListenerRegistration?
    private var sharedExamsListener: ListenerRegistration?
    private var sharedHomeworksListener: ListenerRegistration?
    private var sharedExamUserSettingsListener: ListenerRegistration?
    private var sharedExamUserNotesListener: ListenerRegistration?
    private var sharedHomeworkUserSettingsListener: ListenerRegistration?
    private var sharedHomeworkUserNotesListener: ListenerRegistration?
    private var gradesListeners: [String: ListenerRegistration] = [:] // subjectId -> listener
    private var sharedExamsGroupId: String?
    private var sharedHomeworksGroupId: String?
    private var sharedExamUserReminders: [String: Date] = [:] // examId -> user-spezifische Erinnerung
    private var sharedHomeworkUserReminders: [String: Date] = [:] // homeworkId -> user-spezifische Erinnerung
    @Published private var sharedExamUserNotes: [String: String] = [:] // compoundId -> user note
    @Published private var sharedHomeworkUserNotes: [String: String] = [:] // compoundId -> user note

    private var sharedHomeworkUserCompletedListener: ListenerRegistration?
    private var sharedHomeworkUserCompleted: Set<String> = []
    private var sharedExamUserCompletedListener: ListenerRegistration?
    private var sharedExamUserCompleted: Set<String> = []
    private var sharedExamUserRescheduledListener: ListenerRegistration?
    @Published private var sharedExamUserRescheduled: [String: Date] = [:] // compoundId -> rescheduled date
    private var legacySharedExams: [Exam] = []
    private var legacySharedHomeworks: [Homework] = []

    // Neue Listener für gemeinsame Gruppen
    private var groupSubjectsListeners: [String: ListenerRegistration] = [:]
    private var groupMappingsListeners: [String: ListenerRegistration] = [:]
    private var groupNameListeners: [String: ListenerRegistration] = [:]
    private var groupMembersListeners: [String: ListenerRegistration] = [:]
    private var groupExamsListeners: [String: ListenerRegistration] = [:]
    private var groupHomeworksListeners: [String: ListenerRegistration] = [:]

    // New private listeners for group subjects and mappings
    private var examGroupSubjectsListener: ListenerRegistration?
    private var homeworkGroupSubjectsListener: ListenerRegistration?
    private var examSubjectMappingListener: ListenerRegistration?
    private var homeworkSubjectMappingListener: ListenerRegistration?
    private var examGroupSubjectsGid: String?
    private var homeworkGroupSubjectsGid: String?
    private var examSubjectMappingGid: String?
    private var homeworkSubjectMappingGid: String?

    // Cache verschlüsselter Noten, damit wir bei Key-Verfügbarkeit sofort entschlüsseln können
    private var encryptedGradesCache: [String: [(id: String, data: EncryptedGrade)]] = [:]

    private var isListening: Bool = false
    private var isSettingUp: Bool = false
    private var hasBootstrappedYearData: Bool = false
    private var legacyMigrationCheckDone: Bool = false
    private var pendingLegacyUserData: [String: Any]? = nil
    private var waitingForLegacyDecision: Bool = false
    private var forceSkipLegacyMigration: Bool = false
    @Published var legacyImportSelected: Bool? = nil

    private var schoolYearsCollectionListener: ListenerRegistration?
    private var coursesListener: ListenerRegistration?

    private var offlinePendingGrades: [PendingGrade] = []
    private var offlinePendingFachreferat: PendingFachreferat? = nil
    private var offlinePendingSeminar: PendingSeminarPerformance? = nil
    private var pfingstferienPromptedYearIds: Set<String> = []

    private func overlayPendingData() {
        guard !offlinePendingGrades.isEmpty || offlinePendingFachreferat != nil || offlinePendingSeminar != nil else { return }

        for pending in offlinePendingGrades {
            var list = gradesBySubject[pending.subjectId] ?? []
            if !list.contains(where: { $0.id == pending.id }) {
                list.append(
                    GradeWithId(
                        id: pending.id,
                        grade: pending.grade,
                        weight: pending.weight,
                        date: pending.date,
                        note: pending.note,
                        halfYear: pending.halfYear,
                        linkedExamId: pending.linkedExamId
                    )
                )
                gradesBySubject[pending.subjectId] = list
            }
        }

        if let pendingFr = offlinePendingFachreferat {
            fachreferat = Fachreferat(
                id: "current",
                grade: pendingFr.grade,
                subjectName: pendingFr.subjectName,
                date: pendingFr.date,
                note: pendingFr.note
            )
        }

        if let pendingSem = offlinePendingSeminar {
            seminarPerformance = SeminarPerformance(
                id: "current",
                topic: pendingSem.topic,
                individualPoints: pendingSem.individualPoints,
                paperPoints: pendingSem.paperPoints,
                presentationPoints: pendingSem.presentationPoints,
                submissionDate: pendingSem.submissionDate,
                presentationDate: pendingSem.presentationDate,
                note: pendingSem.note,
                updatedAt: pendingSem.createdAt
            )
        }
    }

    init() {
        loadLocalPreferences()
    }

    // MARK: - Live Updates

    func startListening() async {
        guard !isListening else { return }
        guard !isOfflineMode else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            resetState()
            return
        }
        if OfflineModeManager.shared.isOnline {
            OfflineModeManager.shared.recordOnlineLogin(uid: uid)
        }
        isListening = true
        isLoading = true
        loadingLabel = "Verbinde …"
        progress = 0

        // 1) User-Dokument live beobachten (Einstellungen + encryptionSalt)
        userDocListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                if let data = snapshot?.data() {
                    self.applyUserSettings(from: data)
                    await self.deriveKeyIfNeeded(from: data, uid: uid)
                    self.startSchoolYearsListener(uid: uid)
                    if await self.prepareLegacyMigrationIfNeeded(uid: uid, userData: data) {
                        return
                    }
                    // Nach dem Key-Setup ggf. weitere Listener starten
                    await self.ensureSecondaryListeners(uid: uid, userData: data)
                    await self.loadUserClasses()
                } else {
                    // Kein User-Dokument -> minimaler Reset
                    self.applyUserSettings(from: [:])
                    self.encryptionKey = nil
                }
            }
        }
    }

    func stopListening() {
        userDocListener?.remove()
        userDocListener = nil
        schoolYearsCollectionListener?.remove()
        schoolYearsCollectionListener = nil
        schoolYearListener?.remove()
        schoolYearListener = nil
        schoolYearListenerId = nil
        subjectsListener?.remove()
        subjectsListener = nil
        fachreferatListener?.remove()
        fachreferatListener = nil
        seminarPerformanceListener?.remove()
        seminarPerformanceListener = nil
        practicalPerformanceListener?.remove()
        practicalPerformanceListener = nil
        homeworksListener?.remove()
        homeworksListener = nil
        examsListener?.remove()
        examsListener = nil
        sharedExamsListener?.remove()
        sharedExamsListener = nil
        sharedExamsGroupId = nil
        sharedExamUserSettingsListener?.remove()
        sharedExamUserSettingsListener = nil
        sharedExamUserNotesListener?.remove()
        sharedExamUserNotesListener = nil
        sharedExamUserReminders = [:]
        sharedExamUserNotes = [:]
        sharedExamUserCompletedListener?.remove()
        sharedExamUserCompletedListener = nil
        sharedExamUserCompleted = []
        sharedExamUserRescheduledListener?.remove()
        sharedExamUserRescheduledListener = nil
        sharedExamUserRescheduled = [:]
        sharedHomeworksListener?.remove()
        sharedHomeworksListener = nil
        sharedHomeworksGroupId = nil
        sharedHomeworkUserSettingsListener?.remove()
        sharedHomeworkUserSettingsListener = nil
        sharedHomeworkUserNotesListener?.remove()
        sharedHomeworkUserNotesListener = nil
        sharedHomeworkUserReminders = [:]
        sharedHomeworkUserNotes = [:]
        sharedHomeworkUserCompletedListener?.remove()
        sharedHomeworkUserCompletedListener = nil
        sharedHomeworkUserCompleted = []
        for (_, l) in gradesListeners {
            l.remove()
        }
        gradesListeners = [:]
        encryptedGradesCache = [:]

        // Remove listeners for group subjects and mappings
        examGroupSubjectsListener?.remove()
        examGroupSubjectsListener = nil
        homeworkGroupSubjectsListener?.remove()
        homeworkGroupSubjectsListener = nil
        examSubjectMappingListener?.remove()
        examSubjectMappingListener = nil
        homeworkSubjectMappingListener?.remove()
        homeworkSubjectMappingListener = nil

        // Neue Gruppen-Listener entfernen
        for (_, l) in groupSubjectsListeners { l.remove() }
        for (_, l) in groupMappingsListeners { l.remove() }
        for (_, l) in groupNameListeners { l.remove() }
        groupSubjectsListeners = [:]
        groupMappingsListeners = [:]
        groupNameListeners = [:]
        for (_, l) in groupExamsListeners { l.remove() }
        for (_, l) in groupHomeworksListeners { l.remove() }
        groupExamsListeners = [:]
        groupHomeworksListeners = [:]

        examGroupName = nil
        homeworkGroupName = nil
        examGroupIds = []
        homeworkGroupIds = []

        isListening = false
        isSettingUp = false
        resetState()
    }

    private func resetState() {
        legacyCheckPending = true
        resetSchoolYearScopedData()
        encryptionKey = nil
        encryptionSalt = nil
        subjectSortMode = .name
        subjectSortOrder = []
        gradeYear = nil
        schoolType = .bos
        onboardingRequired = false
        isOfflineMode = false
        homeworkReminderHour = 19
        homeworkReminderMinute = 0
        standardRemindersEnabled = true
        isLoading = false
        loadingLabel = ""
        progress = 0
        groupIds = []
        groupNames = [:]
        groupOwners = [:]
        groupSubjectsByGroup = [:]
        groupSubjectMappings = [:]
        groupExamsByGroup = [:]
        groupHomeworksByGroup = [:]
        sharedExamUserNotes = [:]
        sharedHomeworkUserNotes = [:]
        practicalPerformance = nil
        seminarPerformance = nil
        activeSchoolYearId = nil
        schoolYears = []
        isPrivacyModeActive = false
        schoolYearNames = [:]
        subjectCustomOrder = []

        examGroupId = nil
        homeworkGroupId = nil
        examGroupIds = []
        homeworkGroupIds = []
        examGroupName = nil
        homeworkGroupName = nil
        hasBootstrappedYearData = false

        offlinePendingGrades = []
        offlinePendingFachreferat = nil
        offlinePendingSeminar = nil
        legacyMigrationSummary = nil
        legacyMigrationCheckDone = false
        pendingLegacyUserData = nil
        waitingForLegacyDecision = false
        forceSkipLegacyMigration = false

        // Admin support access
        adminAccessGranted = false
        adminAccessExpiresAt = nil
        supportAccessRequests = []
    }

    private func resetSchoolYearScopedData() {
        schoolYearListener?.remove()
        schoolYearListener = nil
        schoolYearListenerId = nil
        gradeYear = nil
        subjectsListener?.remove()
        subjectsListener = nil
        fachreferatListener?.remove()
        fachreferatListener = nil
        practicalPerformanceListener?.remove()
        practicalPerformanceListener = nil
        homeworksListener?.remove()
        homeworksListener = nil
        examsListener?.remove()
        examsListener = nil
        sharedExamsListener?.remove()
        sharedExamsListener = nil
        sharedExamsGroupId = nil
        sharedHomeworksListener?.remove()
        sharedHomeworksListener = nil
        sharedHomeworksGroupId = nil
        sharedExamUserSettingsListener?.remove()
        sharedExamUserSettingsListener = nil
        sharedHomeworkUserSettingsListener?.remove()
        sharedHomeworkUserSettingsListener = nil
        sharedExamUserCompletedListener?.remove()
        sharedExamUserCompletedListener = nil
        sharedHomeworkUserCompletedListener?.remove()
        sharedHomeworkUserCompletedListener = nil
        legacySharedExams = []
        legacySharedHomeworks = []

        for (_, l) in gradesListeners { l.remove() }
        gradesListeners = [:]
        encryptedGradesCache = [:]

        subjects = []
        gradesBySubject = [:]
        fachreferat = nil
        seminarPerformance = nil
        practicalPerformance = nil
        homeworks = []
        exams = []
        sharedExams = []
        sharedHomeworks = []
        sharedExamUserReminders = [:]
        sharedHomeworkUserReminders = [:]
        sharedHomeworkUserCompleted = []
        sharedExamUserCompleted = []
        sharedExamUserRescheduled = [:]
        legacySharedExams = []
        legacySharedHomeworks = []
        hasBootstrappedYearData = false
        schoolType = .bos

        // Reset group subjects and mappings
        examGroupSubjectsListener?.remove()
        examGroupSubjectsListener = nil
        examGroupSubjects = []
        homeworkGroupSubjectsListener?.remove()
        homeworkGroupSubjectsListener = nil
        homeworkGroupSubjects = []
        examSubjectMappingListener?.remove()
        examSubjectMappingListener = nil
        homeworkSubjectMappingListener?.remove()
        homeworkSubjectMappingListener = nil
        examGroupSubjectsGid = nil
        homeworkGroupSubjectsGid = nil
        examSubjectMappingGid = nil
        homeworkSubjectMappingGid = nil

        for (_, l) in groupMappingsListeners { l.remove() }
        groupMappingsListeners = [:]
        groupSubjectMappings = [:]
        groupExamsByGroup = [:]
        groupHomeworksByGroup = [:]
        groupSubjectsByGroup = [:]
        groupIds = []
        groupNames = [:]
        groupOwners = [:]
        examGroupId = nil
        homeworkGroupId = nil
        examGroupIds = []
        homeworkGroupIds = []
        examGroupName = nil
        homeworkGroupName = nil
        schoolYearSnapshotCache = [:]
    }

    // MARK: - Legacy Web Migration Approval

    private func prepareLegacyMigrationIfNeeded(uid: String, userData: [String: Any]) async -> Bool {
        if waitingForLegacyDecision || legacyMigrationSummary != nil {
            legacyCheckPending = false
            return true
        }
        if legacyMigrationCheckDone {
            legacyCheckPending = false
            return false
        }
        if legacyImportSelected != nil {
            legacyMigrationCheckDone = true
            legacyCheckPending = false
            return false
        }
        let alreadyMigrated = (userData["migratedToSchoolYears"] as? Bool) ?? false
        if alreadyMigrated {
            legacyMigrationCheckDone = true
            legacyCheckPending = false
            return false
        }
        guard let summary = await fetchLegacyMigrationSummary(uid: uid, userData: userData) else {
            legacyMigrationCheckDone = true
            legacyCheckPending = false
            return false
        }
        pendingLegacyUserData = userData
        waitingForLegacyDecision = true
        forceSkipLegacyMigration = false
        legacyMigrationSummary = summary
        legacySelectedSubjects = Set(summary.subjectNames)
        try? await db.collection("users").document(uid).setData([
            "legacyDecisionPending": true
        ], merge: true)
        isLoading = false
        loadingLabel = ""
        progress = 0
        legacyCheckPending = false
        return true
    }

    private func fetchLegacyMigrationSummary(uid: String, userData: [String: Any]) async -> LegacyMigrationSummary? {
        let userRef = db.collection("users").document(uid)
        let hasLegacyFields = userData["gradeYear"] != nil
            || userData["groupIds"] != nil
            || userData["examGroupId"] != nil
            || userData["homeworkGroupId"] != nil
            || userData["examGroupIds"] != nil
            || userData["homeworkGroupIds"] != nil
        do {
            let subjectsSnap = try await userRef.collection("subjects").getDocuments()
            let homeworksSnap = try await userRef.collection("homeworks").getDocuments()
            let examsSnap = try await userRef.collection("exams").getDocuments()
            let subjectNames = subjectsSnap.documents.map { $0.documentID }.sorted()
            var gradeCount = 0
            for subject in subjectsSnap.documents {
                let gradesSnap = try await subject.reference.collection("grades").getDocuments()
                gradeCount += gradesSnap.documents.count
            }

            if subjectsSnap.isEmpty && homeworksSnap.isEmpty && examsSnap.isEmpty && !hasLegacyFields {
                return nil
            }

            return LegacyMigrationSummary(
                subjectCount: subjectsSnap.documents.count,
                gradeCount: gradeCount,
                homeworkCount: homeworksSnap.documents.count,
                examCount: examsSnap.documents.count,
                gradeYear: userData["gradeYear"] as? Int,
                subjectNames: subjectNames
            )
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            if hasLegacyFields {
                return LegacyMigrationSummary(
                    subjectCount: 0,
                    gradeCount: 0,
                    homeworkCount: 0,
                    examCount: 0,
                    gradeYear: userData["gradeYear"] as? Int,
                    subjectNames: []
                )
            }
            return nil
        }
    }

    func handleLegacyMigrationChoice(keepWebData: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let userRef = db.collection("users").document(uid)
        let cachedUserData: [String: Any]?
        if let pending = pendingLegacyUserData {
            cachedUserData = pending
        } else {
            cachedUserData = try? await userRef.getDocument().data()
        }
        let currentSummary = legacyMigrationSummary

        pendingLegacyUserData = cachedUserData
        waitingForLegacyDecision = false
        legacyMigrationCheckDone = true
        // Bewahre Summary, damit Onboarding sie anzeigen kann
        legacyMigrationSummary = currentSummary
        legacyImportSelected = keepWebData
        if keepWebData, let summary = currentSummary {
            legacySelectedSubjects = Set(summary.subjectNames)
        } else {
            legacySelectedSubjects = []
        }
        forceSkipLegacyMigration = !keepWebData
        try? await userRef.setData([
            "legacyDecisionPending": false
        ], merge: true)
        isLoading = false
        loadingLabel = ""
        progress = 0
        legacyCheckPending = false
        // Jetzt Setup normal fortsetzen (ohne sofortige Migration)
        await ensureSecondaryListeners(uid: uid, userData: cachedUserData, skipLegacyMigration: !keepWebData)
    }

    private func schoolYearRef(uid: String, id: String) -> DocumentReference {
        db.collection("users").document(uid).collection("schoolYears").document(id)
    }

    private func ensureYearContext(uid: String,
                                   userData: [String: Any]? = nil,
                                   skipLegacyMigration: Bool = false,
                                   allowCreation: Bool = true,
                                   gateOnOnboarding: Bool = true,
                                   allowLegacyMigration: Bool = false,
                                   allowedLegacySubjects: Set<String>? = nil,
                                   setMigratedFlag: Bool = true) async throws -> (id: String, ref: DocumentReference) {
        let id = try await SchoolYearService.ensureActiveSchoolYear(
            uid: uid,
            userData: userData,
            preferredId: activeSchoolYearId,
            db: db,
            skipLegacyMigration: skipLegacyMigration,
            allowCreation: allowCreation,
            gateOnOnboarding: gateOnOnboarding,
            allowLegacyMigration: allowLegacyMigration,
            allowedLegacySubjects: allowedLegacySubjects,
            setMigratedFlag: setMigratedFlag
        )
        if id != activeSchoolYearId {
            resetSchoolYearScopedData()
        }
        activeSchoolYearId = id
        return (id, schoolYearRef(uid: uid, id: id))
    }

    func requireYearRef(uid: String, allowCreation: Bool = true, gateOnOnboarding: Bool = true, allowLegacyMigration: Bool = false, allowedLegacySubjects: Set<String>? = nil, setMigratedFlag: Bool = true) async throws -> DocumentReference {
        if let id = activeSchoolYearId {
            return schoolYearRef(uid: uid, id: id)
        }
        let context = try await ensureYearContext(uid: uid, allowCreation: allowCreation, gateOnOnboarding: gateOnOnboarding, allowLegacyMigration: allowLegacyMigration, allowedLegacySubjects: allowedLegacySubjects, setMigratedFlag: setMigratedFlag)
        return context.ref
    }

    private func previousSchoolYearId(from id: String?) -> String? {
        guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines), id.count >= 7 else { return nil }
        guard let startYear = Int(id.prefix(4)) else { return nil }
        let previousStart = startYear - 1
        let previousEnd = startYear
        let endSuffix = String(format: "%02d", previousEnd % 100)
        return "\(previousStart)-\(endSuffix)"
    }

    private func pickNextActiveSchoolYear(after deletedId: String, availableIds: [String]) -> String? {
        let cleaned = availableIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        let predictedNext = SchoolYearService.nextSchoolYearId(from: deletedId)
        if cleaned.contains(predictedNext) {
            return predictedNext
        }
        return cleaned.sorted(by: >).first
    }

    private func startSchoolYearsListener(uid: String) {
        if schoolYearsCollectionListener != nil { return }
        schoolYearsCollectionListener = db.collection("users").document(uid).collection("schoolYears")
            .addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    let ids = docs.map { $0.documentID }.sorted(by: >)
                    var names: [String: String] = [:]
                    for doc in docs {
                        if let name = (doc.data()["name"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !name.isEmpty {
                            names[doc.documentID] = name
                        }
                    }
                    self.schoolYears = ids
                    self.schoolYearNames = names
                    self.persistOfflineSnapshotIfPossible()
                }
            }
    }

    func setActiveSchoolYear(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userRef = db.collection("users").document(uid)
        let latestUserData = try? await userRef.getDocument().data()
        do {
            await MainActor.run {
                isLoading = true
                loadingLabel = "Schuljahr wechseln …"
                progress = 15
            }
            try await userRef.setData([
                "activeSchoolYearId": id
            ], merge: true)
            // lokale Umschaltung
            resetSchoolYearScopedData()
            activeSchoolYearId = id
            isSettingUp = false
            await ensureSecondaryListeners(uid: uid, userData: latestUserData)
            await MainActor.run {
                finishInitialLoadingIfNeeded()
                isLoading = false
                progress = 100
                loadingLabel = "Fertig"
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func createSchoolYear(name: String?) async -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = trimmed.isEmpty ? SchoolYearService.currentSchoolYearId() : trimmed
        do {
            let yearRef = schoolYearRef(uid: uid, id: id)
            let existing = try await yearRef.getDocument()
            if existing.exists {
                return nil
            }
            try await yearRef.setData([
                "name": id,
                "createdAt": Date(),
                "schoolType": schoolType.rawValue
            ], merge: true)
            try await db.collection("users").document(uid).setData([
                "activeSchoolYearId": id
            ], merge: true)
            resetSchoolYearScopedData()
            activeSchoolYearId = id
            schoolYearNames[id] = id
            isSettingUp = false
            await ensureSecondaryListeners(uid: uid, userData: [:])
            return id
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return nil
        }
    }

    private func reauthenticateIfNeeded(password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw NSError(domain: "GradesStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Kein Login mit Email/Passwort vorhanden."])
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await user.reauthenticate(with: credential)
    }

    private func deleteCollection(_ ref: CollectionReference) async throws {
        let snap = try await ref.getDocuments()
        for doc in snap.documents {
            try await doc.reference.delete()
        }
    }

    private func deleteSubjectsWithGrades(yearRef: DocumentReference) async throws {
        let subjectsSnap = try await yearRef.collection("subjects").getDocuments()
        for subjectDoc in subjectsSnap.documents {
            let gradesSnap = try await subjectDoc.reference.collection("grades").getDocuments()
            for gradeDoc in gradesSnap.documents {
                try await gradeDoc.reference.delete()
            }
            try await subjectDoc.reference.delete()
        }
    }

    private func deleteSchoolYearData(yearRef: DocumentReference) async throws {
        try await deleteSubjectsWithGrades(yearRef: yearRef)
        let simpleCollections = [
            "homeworks",
            "exams",
            "fachreferat",
            "practicalPerformance",
            "seminar",
            "examGroupReminders",
            "homeworkGroupReminders",
            "examGroupCompleted",
            "homeworkGroupCompleted",
            "subjectMappings",
            "groupMappings"
        ]
        for name in simpleCollections {
            try await deleteCollection(yearRef.collection(name))
        }
    }

    func resetActiveSchoolYear(password: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        try await reauthenticateIfNeeded(password: password)
        guard let sid = activeSchoolYearId else { throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Kein aktives Schuljahr"]) }
        let yearRef = schoolYearRef(uid: uid, id: sid)
        try await deleteSchoolYearData(yearRef: yearRef)
        try await yearRef.delete()

        let userRef = db.collection("users").document(uid)
        try await userRef.setData([
            "activeSchoolYearId": FieldValue.delete(),
            "onboardingCompleted": false
        ], merge: true)

        resetSchoolYearScopedData()
        schoolYearNames.removeValue(forKey: sid)
        schoolYears.removeAll { $0 == sid }
        activeSchoolYearId = nil
        onboardingRequired = true
    }

    func deleteActiveSchoolYearCompletely(password: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        try await reauthenticateIfNeeded(password: password)
        guard let sid = activeSchoolYearId else { throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Kein aktives Schuljahr"]) }

        let userRef = db.collection("users").document(uid)
        let yearRef = schoolYearRef(uid: uid, id: sid)
        try await deleteSchoolYearData(yearRef: yearRef)
        try await yearRef.delete()

        let remainingSnap = try await userRef.collection("schoolYears").getDocuments()
        let remainingIds = remainingSnap.documents
            .map { $0.documentID }
            .filter { $0 != sid }
            .sorted(by: >)
        var names: [String: String] = [:]
        for doc in remainingSnap.documents where doc.documentID != sid {
            if let name = (doc.data()["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                names[doc.documentID] = name
            }
        }

        let nextId = pickNextActiveSchoolYear(after: sid, availableIds: remainingIds)
        var userUpdate: [String: Any] = [:]
        if let nextId {
            userUpdate["activeSchoolYearId"] = nextId
        } else {
            userUpdate["activeSchoolYearId"] = FieldValue.delete()
            userUpdate["onboardingCompleted"] = false
        }
        try await userRef.setData(userUpdate, merge: true)

        resetSchoolYearScopedData()
        schoolYearNames = names
        schoolYears = remainingIds

        if let nextId {
            activeSchoolYearId = nextId
            onboardingRequired = false
            let latestUserData = try? await userRef.getDocument().data()
            await ensureSecondaryListeners(uid: uid, userData: latestUserData)
        } else {
            activeSchoolYearId = nil
            onboardingRequired = true
        }
    }

    func resetEntireAccount(password: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        try await reauthenticateIfNeeded(password: password)

        let userRef = db.collection("users").document(uid)
        let schoolYearsSnap = try await userRef.collection("schoolYears").getDocuments()
        for doc in schoolYearsSnap.documents {
            let ref = doc.reference
            try await deleteSchoolYearData(yearRef: ref)
            try await ref.delete()
        }

        try await userRef.setData([
            "activeSchoolYearId": FieldValue.delete(),
            "groupIds": FieldValue.delete(),
            "examGroupIds": FieldValue.delete(),
            "homeworkGroupIds": FieldValue.delete(),
            "examGroupId": FieldValue.delete(),
            "homeworkGroupId": FieldValue.delete(),
            "onboardingCompleted": false,
            "migratedToSchoolYears": false,
            "legacyDecisionPending": FieldValue.delete()
        ], merge: true)

        resetState()
        let freshData = try await userRef.getDocument().data() ?? [:]
        let onboardingDone = resolveOnboardingDone(from: freshData)
        do {
            let context = try await ensureYearContext(uid: uid, userData: freshData, allowCreation: onboardingDone)
            activeSchoolYearId = context.id
            await ensureSecondaryListeners(uid: uid, userData: freshData)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // Account wurde bereinigt; Neuaufbau kann später erfolgen
        }
    }

    func deleteAccountCompletely(password: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        try await reauthenticateIfNeeded(password: password)

        let userRef = db.collection("users").document(user.uid)
        let schoolYearsSnap = try await userRef.collection("schoolYears").getDocuments()
        for doc in schoolYearsSnap.documents {
            let ref = doc.reference
            try await deleteSchoolYearData(yearRef: ref)
            try await ref.delete()
        }

        let legacyCollections = [
            "subjects",
            "homeworks",
            "exams",
            "fachreferat",
            "practicalPerformance",
            "examGroupReminders",
            "homeworkGroupReminders",
            "examGroupCompleted",
            "homeworkGroupCompleted",
            "subjectMappings",
            "groupMappings",
            "liveActivities"
        ]
        for name in legacyCollections {
            try await deleteCollection(userRef.collection(name))
        }

        try? await userRef.delete()
        try await user.delete()

        resetState()
    }

    // MARK: - Setup der weiteren Listener (Subjects, Grades, Fachreferat)

    private func shouldDeferSchoolYearSetup(onboardingDone: Bool, hasAnyActiveYear: Bool, forceYearSetup: Bool) -> Bool {
        if forceYearSetup { return false }
        if waitingForLegacyDecision { return true }
        if onboardingRequired && activeSchoolYearId == nil { return true }
        return !onboardingDone && !hasAnyActiveYear
    }

    private func ensureSecondaryListeners(uid: String, userData: [String: Any]? = nil, skipLegacyMigration: Bool = false, forceYearSetup: Bool = false, allowLegacyMigration: Bool = false) async {
        // Verhindere gleichzeitiges Setup
        if isSettingUp { return }
        isSettingUp = true
        defer { isSettingUp = false }

        let effectiveSkip = skipLegacyMigration || forceSkipLegacyMigration
        let onboardingDone = resolveOnboardingDone(from: userData)
        let incomingActive = (userData?["activeSchoolYearId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnyActiveYear = activeSchoolYearId != nil || (incomingActive?.isEmpty == false)
        let shouldDeferYearSetup = shouldDeferSchoolYearSetup(
            onboardingDone: onboardingDone,
            hasAnyActiveYear: hasAnyActiveYear,
            forceYearSetup: forceYearSetup
        )

        if shouldDeferYearSetup {
            isLoading = false
            loadingLabel = ""
            progress = 0
            return
        }

        let allowCreation = onboardingDone || hasAnyActiveYear || forceYearSetup
        let markMigrated = !(legacyImportSelected == true)
        guard let context = try? await ensureYearContext(
            uid: uid,
            userData: userData,
            skipLegacyMigration: effectiveSkip,
            allowCreation: allowCreation,
            gateOnOnboarding: !forceYearSetup,
            allowLegacyMigration: allowLegacyMigration,
            allowedLegacySubjects: legacySelectedSubjects,
            setMigratedFlag: markMigrated
        ) else {
            return
        }
        if forceSkipLegacyMigration && effectiveSkip {
            forceSkipLegacyMigration = false
        }
        let schoolYearId = context.id
        let yearRef = context.ref

        // Initial Lade der Schuljahres-Einstellungen (z. B. Gruppen)
        do {
            let snap = try await yearRef.getDocument()
            let data = snap.data() ?? [:]
            applySchoolYearSettings(from: data, uid: uid, fallbackUserData: userData)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            applySchoolYearSettings(from: [:], uid: uid, fallbackUserData: userData)
        }
        setupSchoolYearListener(uid: uid, schoolYearId: schoolYearId, ref: yearRef)

        // Subjects-Listener
        if subjectsListener == nil {
            progress = 20
            loadingLabel = "Fächer verbinden …"
            subjectsListener = yearRef.collection("subjects")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        let subjectsData: [Subject] = docs.compactMap { doc in
                            let data = doc.data()
                            let name = doc.documentID
                            let type = data["type"] as? Int ?? 0
                            let ts = data["date"] as? Timestamp
                            let date = ts?.dateValue() ?? Date()
                            let order = data["order"] as? Int
                            let teacher = data["teacher"] as? String
                            let room = data["room"] as? String
                            let email = data["email"] as? String
                            let alias = data["alias"] as? String
                            let dropped = data["droppedHalfYear"] as? Int
                            let examSubject = data["examSubject"] as? Bool
                            let examTypeStr = data["examType"] as? String
                            let examType = examTypeStr.flatMap { ExamType(rawValue: $0) }
                            let examPointsEncrypted = data["examPointsEncrypted"] as? String
                            let writtenExamPointsEncrypted = data["writtenExamPointsEncrypted"] as? String
                            let oralExamPointsEncrypted = data["oralExamPointsEncrypted"] as? String
                            let isElective = data["isElective"] as? Bool ?? false

                            return Subject(name: name,
                                           type: type,
                                           date: date,
                                           order: order,
                                           teacher: teacher,
                                           room: room,
                                           email: email,
                                           alias: alias,
                                           droppedHalfYear: dropped,
                                           examSubject: examSubject,
                                           examType: examType,
                                           examPointsEncrypted: examPointsEncrypted,
                                           writtenExamPointsEncrypted: writtenExamPointsEncrypted,
                                           oralExamPointsEncrypted: oralExamPointsEncrypted,
                                           isElective: isElective)
                        }
                        self.subjects = subjectsData
                        self.decryptExamPoints()

                        // Sicherstellen, dass für alle Subjects ein Grades-Listener existiert
                        self.setupGradesListenersIfNeeded(uid: uid, schoolYearRef: yearRef, subjects: subjectsData)

                        // Entferne Listener für gelöschte Subjects
                        let currentNames = Set(subjectsData.map { $0.name })
                        let toRemove = self.gradesListeners.keys.filter { !currentNames.contains($0) }
                        for name in toRemove {
                            self.gradesListeners[name]?.remove()
                            self.gradesListeners.removeValue(forKey: name)
                            self.encryptedGradesCache.removeValue(forKey: name)
                            self.gradesBySubject.removeValue(forKey: name)
                        }

                        self.progress = 60
                        self.loadingLabel = "Noten verbinden …"
                        self.persistOfflineSnapshotIfPossible()
                    }
                }
        }

        // Fachreferat-Listener
        if fachreferatListener == nil {
            progress = 40
            loadingLabel = "Fachreferat verbinden …"
            fachreferatListener = yearRef.collection("fachreferat").document("current")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        guard let snap = snapshot, snap.exists, let data = snap.data() else {
                            self.fachreferat = nil
                            self.finishInitialLoadingIfNeeded()
                            return
                        }
                       let ts = data["date"] as? Timestamp
                       let date = ts?.dateValue() ?? Date()
                       let note = data["note"] as? String
                        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                        if let gradeStr = data["grade"] as? String,
                           let subjectName = data["subjectName"] as? String,
                           let key = self.encryptionKey {
                            do {
                                let numStr = try CryptoService.decryptString(gradeStr, key: key)
                                if let num = Double(numStr), num.isFinite {
                                    self.fachreferat = Fachreferat(id: "current", grade: num, subjectName: subjectName, date: date, note: note)
                                } else {
                                    self.fachreferat = nil
                                }
                            } catch {
                                ErrorLoggingService.logErrorIfEnabled(error)
                                self.fachreferat = nil
                            }
                        } else {
                            // Ohne Key können wir nicht entschlüsseln; als „nicht vorhanden“ behandeln
                            self.fachreferat = nil
                        }
                        if let pending = self.offlinePendingFachreferat,
                           let serverTs = updatedAt,
                           serverTs >= pending.createdAt {
                            self.offlinePendingFachreferat = nil
                        }
                        self.overlayPendingData()
                        self.finishInitialLoadingIfNeeded()
                    }
                }
        }

        if seminarPerformanceListener == nil {
            seminarPerformanceListener = yearRef.collection("seminar").document("current")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        guard let snap = snapshot, snap.exists, let data = snap.data() else {
                            self.seminarPerformance = nil
                            self.finishInitialLoadingIfNeeded()
                            return
                        }
                        guard let key = self.encryptionKey else {
                            self.seminarPerformance = nil
                            self.finishInitialLoadingIfNeeded()
                            return
                        }
                        self.seminarPerformance = self.decodeSeminarPerformance(data: data, key: key)
                        if let pending = self.offlinePendingSeminar,
                           let ts = data["updatedAt"] as? Timestamp,
                           ts.dateValue() >= pending.createdAt {
                            self.offlinePendingSeminar = nil
                        }
                        self.overlayPendingData()
                        self.finishInitialLoadingIfNeeded()
                    }
                }
        }

        // Praktikums-Jahresleistung (11. Klasse FOS)
        if practicalPerformanceListener == nil {
            practicalPerformanceListener = yearRef.collection("practicalPerformance").document("current")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        guard let snap = snapshot, snap.exists, let data = snap.data() else {
                            self.practicalPerformance = nil
                            self.finishInitialLoadingIfNeeded()
                            return
                        }
                        guard let key = self.encryptionKey else {
                            self.practicalPerformance = nil
                            self.finishInitialLoadingIfNeeded()
                            return
                        }
                        self.practicalPerformance = self.decodePracticalPerformance(data: data, key: key)
                        self.finishInitialLoadingIfNeeded()
                    }
                }
        }

        // Hausaufgaben-Listener
        if homeworksListener == nil {
            homeworksListener = yearRef
                .collection("homeworks")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        let list: [Homework] = docs.compactMap { doc in
                            let data = doc.data()
                            let subjectName = data["subjectName"] as? String ?? ""
                            let title = data["title"] as? String ?? ""
                            let isCompleted = data["isCompleted"] as? Bool ?? false
                            let createdTs = data["createdAt"] as? Timestamp
                            let createdAt = createdTs?.dateValue() ?? Date()
                        let dueTs = data["dueDate"] as? Timestamp
                        let dueDate = dueTs?.dateValue()
                        let reminderTs = data["reminderAt"] as? Timestamp
                        let reminderAt = reminderTs?.dateValue()
                        let creatorId = data["creatorId"] as? String ?? uid
                        let imported = data["importedFromShare"] as? Bool ?? false
                        return Homework(
                            id: doc.documentID,
                            groupId: nil,
                            subjectName: subjectName,
                            subjectKey: nil,
                            title: title,
                            dueDate: dueDate,
                            reminderAt: reminderAt,
                            isCompleted: isCompleted,
                            createdAt: createdAt,
                            isShared: false,
                            creatorId: creatorId,
                            isImportedFromShare: imported
                        )
                    }
                        self.homeworks = list
                        self.rescheduleLocalNotifications()
                        self.persistOfflineSnapshotIfPossible()
                    }
                }
        }

        // Prüfungs-Listener
        if examsListener == nil {
            examsListener = yearRef
                .collection("exams")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        let list: [Exam] = docs.compactMap { doc in
                            let data = doc.data()
                            let subjectName = data["subjectName"] as? String ?? ""
                            let subjectKey = data["subjectKey"] as? String
                            let title = data["title"] as? String ?? ""
                            let notes = data["notes"] as? String
                            let isCompleted = data["isCompleted"] as? Bool ?? false
                            let createdTs = data["createdAt"] as? Timestamp
                            let createdAt = createdTs?.dateValue() ?? Date()
                            guard let dateTs = data["date"] as? Timestamp else { return nil }
                            let date = dateTs.dateValue()
                            let hasTimeFlag = data["hasTime"] as? Bool
                            let calendar = Calendar.current
                            let hasTime = hasTimeFlag ?? !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
                            let weight = data["weight"] as? Int
                            let customWeight = (data["customWeight"] as? NSNumber)?.doubleValue
                            let reminderTs = data["reminderAt"] as? Timestamp
                            let reminderAt = reminderTs?.dateValue()
                            let creatorId = data["creatorId"] as? String ?? uid
                            let requiresGrade = data["requiresGrade"] as? Bool
                            return Exam(
                                id: doc.documentID,
                                groupId: nil,
                                subjectName: subjectName,
                                subjectKey: subjectKey,
                                title: title,
                                notes: notes,
                                date: date,
                                hasTime: hasTime,
                                weight: weight,
                                customWeight: customWeight,
                                reminderAt: reminderAt,
                                isCompleted: isCompleted,
                                createdAt: createdAt,
                                isShared: false,
                                creatorId: creatorId,
                                requiresGrade: requiresGrade
                            )
                        }
                        self.exams = list
                        self.rescheduleLocalNotifications()
                        self.persistOfflineSnapshotIfPossible()
                    }
                }
        }

        // New: Gruppen-Listener (/groups)
        updateGroupObservers(uid: uid, schoolYearId: schoolYearId)
        startCourseMappingsListener()
        // Legacy-Gruppen-Listener sicherheitshalber ebenfalls aktivieren
        updateSharedExamsListenerIfNeeded()
        updateSharedHomeworksListenerIfNeeded()

        // User-spezifische Einstellungen für geteilte Prüfungen
        if sharedExamUserSettingsListener == nil {
            sharedExamUserSettingsListener = yearRef
                .collection("examGroupReminders")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        var map: [String: Date] = [:]
                        for doc in docs {
                            let data = doc.data()
                            if let ts = data["reminderAt"] as? Timestamp {
                                map[doc.documentID] = ts.dateValue()
                            }
                        }
                        self.sharedExamUserReminders = map
                        self.applySharedExamUserReminders()
                        self.rescheduleLocalNotifications()
                    }
                }
        }

        if sharedExamUserNotesListener == nil {
            sharedExamUserNotesListener = yearRef
                .collection("examGroupNotes")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        var map: [String: String] = [:]
                        for doc in docs {
                            if let note = doc.data()["note"] as? String {
                                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    map[doc.documentID] = trimmed
                                }
                            }
                        }
                        self.sharedExamUserNotes = map
                    }
                }
        }

        if sharedExamUserCompletedListener == nil {
            sharedExamUserCompletedListener = yearRef.collection("examGroupCompleted").addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    let set: Set<String> = Set(docs.compactMap { doc in
                        let data = doc.data()
                        if let val = data["isCompleted"] as? Bool {
                            return val ? doc.documentID : nil
                        } else {
                            // If document exists without explicit flag, treat as completed
                            return doc.documentID
                        }
                    })
                    self.sharedExamUserCompleted = set
                    self.applySharedExamUserCompletion()
                    self.rescheduleLocalNotifications()
                }
            }
        }

        if sharedExamUserRescheduledListener == nil {
            sharedExamUserRescheduledListener = yearRef.collection("examGroupRescheduled").addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    var map: [String: Date] = [:]
                    for doc in docs {
                        let data = doc.data()
                        if let ts = data["rescheduledDate"] as? Timestamp {
                            map[doc.documentID] = ts.dateValue()
                        }
                    }
                    self.sharedExamUserRescheduled = map
                    self.applySharedExamUserRescheduledDates()
                    self.rescheduleLocalNotifications()
                }
            }
        }

        if sharedHomeworkUserSettingsListener == nil {
            sharedHomeworkUserSettingsListener = yearRef.collection("homeworkGroupReminders").addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    var map: [String: Date] = [:]
                    for doc in docs {
                        let data = doc.data()
                        if let ts = data["reminderAt"] as? Timestamp {
                            map[doc.documentID] = ts.dateValue()
                        }
                    }
                    self.sharedHomeworkUserReminders = map
                    self.applySharedHomeworkUserReminders()
                        self.rescheduleLocalNotifications()
                    }
                }
        }

        if sharedHomeworkUserNotesListener == nil {
            sharedHomeworkUserNotesListener = yearRef.collection("homeworkGroupNotes").addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    var map: [String: String] = [:]
                    for doc in docs {
                        if let note = doc.data()["note"] as? String {
                            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                map[doc.documentID] = trimmed
                            }
                        }
                    }
                    self.sharedHomeworkUserNotes = map
                }
            }
        }
        
        if sharedHomeworkUserCompletedListener == nil {
            sharedHomeworkUserCompletedListener = yearRef.collection("homeworkGroupCompleted").addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    let set: Set<String> = Set(docs.compactMap { doc in
                        let data = doc.data()
                        if let val = data["isCompleted"] as? Bool {
                            return val ? doc.documentID : nil
                        } else {
                            // If document exists without explicit flag, treat as completed
                            return doc.documentID
                        }
                    })
                    self.sharedHomeworkUserCompleted = set
                    self.applySharedHomeworkUserCompletion()
                    self.rescheduleLocalNotifications()
                }
            }
        }

        // Einmaliger Fallback-Load, falls Firestore-Listener verzögert oder leer starten
        await bootstrapHomeworksAndExamsIfNeeded(yearRef: yearRef, uid: uid)
        // Sicherheitshalber initiale Daten holen, falls Listener mit leerem Snapshot starten
        Task {
            await self.preloadInitialDataIfEmpty(uid: uid, yearRef: yearRef)
        }
    }

    private func bootstrapHomeworksAndExamsIfNeeded(yearRef: DocumentReference, uid: String) async {
        guard !hasBootstrappedYearData else { return }
        hasBootstrappedYearData = true
        var success = true

        do {
            let hwSnap = try await yearRef
                .collection("homeworks")
                .order(by: "createdAt", descending: false)
                .getDocuments()
            let list: [Homework] = hwSnap.documents.compactMap { doc in
                let data = doc.data()
                let subjectName = data["subjectName"] as? String ?? ""
                let title = data["title"] as? String ?? ""
                let isCompleted = data["isCompleted"] as? Bool ?? false
                let createdTs = data["createdAt"] as? Timestamp
                let createdAt = createdTs?.dateValue() ?? Date()
                let dueTs = data["dueDate"] as? Timestamp
                let dueDate = dueTs?.dateValue()
                let reminderTs = data["reminderAt"] as? Timestamp
                let reminderAt = reminderTs?.dateValue()
                let creatorId = data["creatorId"] as? String ?? uid
                let imported = data["importedFromShare"] as? Bool ?? false
                return Homework(
                    id: doc.documentID,
                    groupId: nil,
                    subjectName: subjectName,
                    subjectKey: nil,
                    title: title,
                    dueDate: dueDate,
                    reminderAt: reminderAt,
                    isCompleted: isCompleted,
                    createdAt: createdAt,
                    isShared: false,
                    creatorId: creatorId,
                    isImportedFromShare: imported
                )
            }
            homeworks = list
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            success = false
        }

        do {
            let examSnap = try await yearRef
                .collection("exams")
                .order(by: "createdAt", descending: false)
                .getDocuments()
            let list: [Exam] = examSnap.documents.compactMap { doc in
                let data = doc.data()
                let subjectName = data["subjectName"] as? String ?? ""
                let subjectKey = data["subjectKey"] as? String
                let title = data["title"] as? String ?? ""
                let notes = data["notes"] as? String
                let isCompleted = data["isCompleted"] as? Bool ?? false
                let createdTs = data["createdAt"] as? Timestamp
                let createdAt = createdTs?.dateValue() ?? Date()
                guard let dateTs = data["date"] as? Timestamp else { return nil }
                let date = dateTs.dateValue()
                let hasTimeFlag = data["hasTime"] as? Bool
                let calendar = Calendar.current
                let hasTime = hasTimeFlag ?? !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
                let weight = data["weight"] as? Int
                let customWeight = (data["customWeight"] as? NSNumber)?.doubleValue
                let reminderTs = data["reminderAt"] as? Timestamp
                let reminderAt = reminderTs?.dateValue()
                let creatorId = data["creatorId"] as? String ?? uid
                let requiresGrade = data["requiresGrade"] as? Bool
                return Exam(
                    id: doc.documentID,
                    groupId: nil,
                    subjectName: subjectName,
                    subjectKey: subjectKey,
                    title: title,
                    notes: notes,
                    date: date,
                    hasTime: hasTime,
                    weight: weight,
                    customWeight: customWeight,
                    reminderAt: reminderAt,
                    isCompleted: isCompleted,
                    createdAt: createdAt,
                    isShared: false,
                    creatorId: creatorId,
                    requiresGrade: requiresGrade
                )
            }
            exams = list
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            success = false
        }

        if success {
            rescheduleLocalNotifications()
        } else {
            hasBootstrappedYearData = false
        }
    }

    /// Lädt einmalig Daten, wenn Listener initial leer liefern (z. B. Cold Start mit Latenz)
    private func preloadInitialDataIfEmpty(uid: String, yearRef: DocumentReference) async {
        // Eigene Hausaufgaben
        let homeworksEmpty = await MainActor.run { self.homeworks.isEmpty }
        if homeworksEmpty {
            do {
                let snap = try await yearRef.collection("homeworks")
                    .order(by: "createdAt", descending: false)
                    .getDocuments()
                let list: [Homework] = snap.documents.compactMap { doc in
                    let data = doc.data()
                    let subjectName = data["subjectName"] as? String ?? ""
                    let title = data["title"] as? String ?? ""
                    let isCompleted = data["isCompleted"] as? Bool ?? false
                    let createdTs = data["createdAt"] as? Timestamp
                    let createdAt = createdTs?.dateValue() ?? Date()
                let dueTs = data["dueDate"] as? Timestamp
                let dueDate = dueTs?.dateValue()
                let reminderTs = data["reminderAt"] as? Timestamp
                let reminderAt = reminderTs?.dateValue()
                let creatorId = data["creatorId"] as? String ?? uid
                let imported = data["importedFromShare"] as? Bool ?? false
                return Homework(
                    id: doc.documentID,
                    groupId: nil,
                    subjectName: subjectName,
                    subjectKey: nil,
                    title: title,
                    dueDate: dueDate,
                    reminderAt: reminderAt,
                    isCompleted: isCompleted,
                    createdAt: createdAt,
                    isShared: false,
                    creatorId: creatorId,
                    isImportedFromShare: imported
                )
            }
            await MainActor.run { self.homeworks = list }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
            }
        }

        // Eigene Klausuren
        let examsEmpty = await MainActor.run { self.exams.isEmpty }
        if examsEmpty {
            do {
                let snap = try await yearRef.collection("exams")
                    .order(by: "createdAt", descending: false)
                    .getDocuments()
                let list: [Exam] = snap.documents.compactMap { doc in
                    let data = doc.data()
                    let subjectName = data["subjectName"] as? String ?? ""
                    let subjectKey = data["subjectKey"] as? String
                    let title = data["title"] as? String ?? ""
                    let notes = data["notes"] as? String
                    let isCompleted = data["isCompleted"] as? Bool ?? false
                    let createdTs = data["createdAt"] as? Timestamp
                    let createdAt = createdTs?.dateValue() ?? Date()
                    guard let dateTs = data["date"] as? Timestamp else { return nil }
                    let date = dateTs.dateValue()
                    let hasTimeFlag = data["hasTime"] as? Bool
                    let calendar = Calendar.current
                    let hasTime = hasTimeFlag ?? !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
                    let weight = data["weight"] as? Int
                    let customWeight = (data["customWeight"] as? NSNumber)?.doubleValue
                    let reminderTs = data["reminderAt"] as? Timestamp
                    let reminderAt = reminderTs?.dateValue()
                    let creatorId = data["creatorId"] as? String ?? uid
                    let requiresGrade = data["requiresGrade"] as? Bool
                    return Exam(
                        id: doc.documentID,
                        groupId: nil,
                        subjectName: subjectName,
                        subjectKey: subjectKey,
                        title: title,
                        notes: notes,
                        date: date,
                        hasTime: hasTime,
                        weight: weight,
                        customWeight: customWeight,
                        reminderAt: reminderAt,
                        isCompleted: isCompleted,
                        createdAt: createdAt,
                        isShared: false,
                        creatorId: creatorId,
                        requiresGrade: requiresGrade
                    )
                }
                await MainActor.run { self.exams = list }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
        }

        // Geteilte Gruppen-Daten einmalig nachladen, falls Listener noch nichts geliefert haben
        let gids = await MainActor.run { self.groupIds }
        for gid in gids {
            let groupExamsEmpty = await MainActor.run { self.groupExamsByGroup[gid]?.isEmpty != false }
            if groupExamsEmpty {
                do {
                    let snap = try await db.collection("groups").document(gid)
                        .collection("exams")
                        .order(by: "createdAt", descending: false)
                        .getDocuments()
                    let list: [Exam] = snap.documents.compactMap { doc in
                        let data = doc.data()
                        let subjectName = data["subjectName"] as? String ?? ""
                        let subjectKey = data["subjectKey"] as? String
                        let title = data["title"] as? String ?? ""
                        let notes = data["notes"] as? String
                        let createdTs = data["createdAt"] as? Timestamp
                        let createdAt = createdTs?.dateValue() ?? Date()
                        guard let dateTs = data["date"] as? Timestamp else { return nil }
                        let date = dateTs.dateValue()
                        let hasTimeFlag = data["hasTime"] as? Bool
                        let calendar = Calendar.current
                        let hasTime = hasTimeFlag ?? !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
                        let weight = data["weight"] as? Int
                        let customWeight = (data["customWeight"] as? NSNumber)?.doubleValue
                        let creatorId = data["creatorId"] as? String
                        let requiresGrade = data["requiresGrade"] as? Bool
                        return Exam(
                            id: doc.documentID,
                            groupId: gid,
                            subjectName: subjectName,
                            subjectKey: subjectKey,
                            title: title,
                            notes: notes,
                            date: date,
                            hasTime: hasTime,
                            weight: weight,
                            customWeight: customWeight,
                            reminderAt: nil,
                            isCompleted: false,
                            createdAt: createdAt,
                            isShared: true,
                            creatorId: creatorId,
                            requiresGrade: requiresGrade
                        )
                    }
                    await MainActor.run { self.groupExamsByGroup[gid] = list }
                } catch {
                    ErrorLoggingService.logErrorIfEnabled(error)
                    // optional loggen
                }
            }

            let groupHomeworksEmpty = await MainActor.run { self.groupHomeworksByGroup[gid]?.isEmpty != false }
            if groupHomeworksEmpty {
                do {
                    let snap = try await db.collection("groups").document(gid)
                        .collection("homeworks")
                        .order(by: "createdAt", descending: false)
                        .getDocuments()
                    let list: [Homework] = snap.documents.compactMap { doc in
                        let data = doc.data()
                        let subjectName = data["subjectName"] as? String ?? ""
                        let subjectKey = data["subjectKey"] as? String
                        let title = data["title"] as? String ?? ""
                        let createdTs = data["createdAt"] as? Timestamp
                        let createdAt = createdTs?.dateValue() ?? Date()
                        let dueTs = data["dueDate"] as? Timestamp
                        let dueDate = dueTs?.dateValue()
                        let creatorId = data["creatorId"] as? String
                        return Homework(
                            id: doc.documentID,
                            groupId: gid,
                            subjectName: subjectName,
                            subjectKey: subjectKey,
                            title: title,
                            dueDate: dueDate,
                            reminderAt: nil,
                            isCompleted: false,
                            createdAt: createdAt,
                            isShared: true,
                            creatorId: creatorId,
                            isImportedFromShare: false
                        )
                    }
                    await MainActor.run { self.groupHomeworksByGroup[gid] = list }
                } catch {
                    ErrorLoggingService.logErrorIfEnabled(error)
                    // optional loggen
                }
            }
        }

        await MainActor.run {
            self.recomputeSharedCollections()
        }
    }

    private func setupSchoolYearListener(uid: String, schoolYearId: String, ref: DocumentReference) {
        if schoolYearListenerId == schoolYearId, schoolYearListener != nil { return }
        schoolYearListener?.remove()
        schoolYearListener = ref.addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let data = snap?.data() ?? [:]
                self.applySchoolYearSettings(from: data, uid: uid)
            }
        }
        schoolYearListenerId = schoolYearId
    }

    private func setupGradesListenersIfNeeded(uid: String, schoolYearRef: DocumentReference, subjects: [Subject]) {
        for subject in subjects {
            let sid = subject.name
            if gradesListeners[sid] != nil { continue }
            let listener = schoolYearRef.collection("subjects").document(sid).collection("grades")
                .addSnapshotListener { [weak self] snapshot, error in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        let encGrades: [(String, EncryptedGrade)] = docs.compactMap { gdoc in
                            let gd = gdoc.data()
                            guard let gradeStr = gd["grade"] as? String else { return nil }
                        let weight = (gd["weight"] as? NSNumber)?.doubleValue ?? 1.0
                        let ts = gd["date"] as? Timestamp
                        let date = ts?.dateValue() ?? Date()
                        let note = gd["note"] as? String
                        let halfYear = gd["halfYear"] as? Int
                        let linkedExamId = gd["linkedExamId"] as? String
                        let updatedAt = (gd["updatedAt"] as? Timestamp)?.dateValue()
                        let eg = EncryptedGrade(
                            grade: gradeStr,
                            weight: weight,
                            date: date,
                            note: note,
                            halfYear: halfYear,
                            linkedExamId: linkedExamId,
                            updatedAt: updatedAt
                        )
                        return (gdoc.documentID, eg)
                    }
                        self.encryptedGradesCache[sid] = encGrades
                        self.decryptGradesForSubjectIfPossible(subjectId: sid)
                        self.finishInitialLoadingIfNeeded()
                        self.persistOfflineSnapshotIfPossible()
                    }
                }
            gradesListeners[sid] = listener
        }
    }

    private func decryptGradesForSubjectIfPossible(subjectId: String) {
        guard let key = encryptionKey else {
            gradesBySubject[subjectId] = [] // Ohne Key leeren wir die sichtbaren Noten
            return
        }
        let encList = encryptedGradesCache[subjectId] ?? []
        var decrypted: [GradeWithId] = []
        decrypted.reserveCapacity(encList.count)
        for (gid, enc) in encList {
            if let num = try? CryptoService.decryptString(enc.grade, key: key), let val = Double(num), val.isFinite {
                decrypted.append(
                    GradeWithId(
                        id: gid,
                        grade: val,
                        weight: enc.weight,
                        date: enc.date,
                        note: enc.note,
                        halfYear: enc.halfYear,
                        linkedExamId: enc.linkedExamId
                    )
                )
            }
        }
        gradesBySubject[subjectId] = decrypted
        removeSatisfiedPendingGrades(for: subjectId, decrypted: encList)
        overlayPendingData()
    }

    private func decryptAllCachedGradesIfPossible() {
        for sid in encryptedGradesCache.keys {
            decryptGradesForSubjectIfPossible(subjectId: sid)
        }
        decryptExamPoints()
    }

    private func decryptExamPoints() {
        guard let key = encryptionKey else {
            self.examPoints = [:]
            return
        }
        var next: [String: Double?] = [:]
        for s in subjects {
            var points: Double? = nil
            if let enc = s.examPointsEncrypted {
                do {
                    let decrypted = try CryptoService.decryptString(enc, key: key)
                    if let num = Double(decrypted), num.isFinite {
                        points = num
                    }
                } catch {
                    ErrorLoggingService.logErrorIfEnabled(error)
                }
            }
            next[s.name] = points
        }
        self.examPoints = next
    }

    private func removeSatisfiedPendingGrades(for subjectId: String, decrypted: [(String, EncryptedGrade)]) {
        guard !offlinePendingGrades.isEmpty else { return }
        let map: [String: Date] = decrypted.reduce(into: [:]) { acc, item in
            let updated = item.1.updatedAt ?? item.1.date
            acc[item.0] = updated
        }
        offlinePendingGrades = offlinePendingGrades.filter { pending in
            guard pending.subjectId == subjectId else { return true }
            guard let serverTs = map[pending.id] else { return true }
            return serverTs <= pending.createdAt ? false : true
        }
        if offlinePendingGrades.isEmpty, offlinePendingFachreferat == nil, offlinePendingSeminar == nil {
            persistOfflineSnapshotIfPossible()
        }
    }

    var hasPendingOfflineChanges: Bool {
        !(offlinePendingGrades.isEmpty && offlinePendingFachreferat == nil && offlinePendingSeminar == nil)
    }

    func discardPendingOfflineChanges() {
        offlinePendingGrades = []
        offlinePendingFachreferat = nil
        offlinePendingSeminar = nil
        persistOfflineSnapshotIfPossible()
    }

    private func finishInitialLoadingIfNeeded() {
        // Sobald wir zumindest einmal Subjects und Grades gesehen haben, können wir das Loading beenden.
        // Für einfache Heuristik: Wenn SubjectsListener existiert und wir schon irgendeinen Grades-Cache-Eintrag gesehen haben.
        if isLoading {
            progress = 100
            loadingLabel = "Fertig"
            // leicht verzögert, wie vorher
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.isLoading = false
            }
        }
    }

    // Alle Prüfungen (eigene + geteilte)
    var allExams: [Exam] {
        exams + sharedExams
    }
    var allHomeworks: [Homework] {
        homeworks + sharedHomeworks
    }

    var upcomingExams: [Exam] {
        allExams.filter {
            // Keep exams from today or future, and those not completed? 
            // Usually upcoming includes incomplete past exams too?
            // "Anstehend" usually implies future. "Wartet auf Note" are past but incomplete.
            // Let's match typical "Upcoming" logic: Date >= today, OR (Date < today AND !isCompleted AND !requiresGrade).
            // But usually "Upcoming" just means Date >= today.
            // For now, simple filter: Date >= today (ignoring time component for today comparison so today is included)
            Calendar.current.compare($0.date, to: Date(), toGranularity: .day) != .orderedAscending
        }
        .sorted { $0.date < $1.date }
    }
    
    func userNoteForExam(_ exam: Exam) -> String? {
        let key = compoundId(gid: exam.groupId, docId: exam.id)
        return sharedExamUserNotes[key] ?? sharedExamUserNotes[exam.id]
    }
    
    func userNoteForHomework(_ homework: Homework) -> String? {
        let key = compoundId(gid: homework.groupId, docId: homework.id)
        return sharedHomeworkUserNotes[key] ?? sharedHomeworkUserNotes[homework.id]
    }

    private func applySharedExamUserReminders() {
        guard !sharedExams.isEmpty else { return }
        sharedExams = sharedExams.map { exam in
            let key = compoundId(gid: exam.groupId, docId: exam.id)
            if let date = sharedExamUserReminders[key] ?? sharedExamUserReminders[exam.id] {
                return Exam(
                    id: exam.id,
                    groupId: exam.groupId,
                    subjectName: exam.subjectName,
                    subjectKey: exam.subjectKey,
                    title: exam.title,
                    notes: exam.notes,
                    date: exam.date,
                    hasTime: exam.hasTime,
                    weight: exam.weight,
                    customWeight: exam.customWeight,
                    reminderAt: date,
                    isCompleted: exam.isCompleted,
                    createdAt: exam.createdAt,
                    isShared: exam.isShared,
                    creatorId: exam.creatorId,
                    requiresGrade: exam.requiresGrade
                )
            } else {
                return Exam(
                    id: exam.id,
                    groupId: exam.groupId,
                    subjectName: exam.subjectName,
                    subjectKey: exam.subjectKey,
                    title: exam.title,
                    notes: exam.notes,
                    date: exam.date,
                    hasTime: exam.hasTime,
                    weight: exam.weight,
                    customWeight: exam.customWeight,
                    reminderAt: nil,
                    isCompleted: exam.isCompleted,
                    createdAt: exam.createdAt,
                    isShared: exam.isShared,
                    creatorId: exam.creatorId,
                    requiresGrade: exam.requiresGrade
                )
            }
        }
    }

    private func applySharedHomeworkUserReminders() {
        guard !sharedHomeworks.isEmpty else { return }
        sharedHomeworks = sharedHomeworks.map { hw in
            let key = compoundId(gid: hw.groupId, docId: hw.id)
            if let date = sharedHomeworkUserReminders[key] ?? sharedHomeworkUserReminders[hw.id] {
                return Homework(id: hw.id, groupId: hw.groupId, subjectName: hw.subjectName, subjectKey: hw.subjectKey, title: hw.title, dueDate: hw.dueDate, reminderAt: date, isCompleted: hw.isCompleted, createdAt: hw.createdAt, isShared: true, creatorId: hw.creatorId, isImportedFromShare: hw.isImportedFromShare)
            } else {
                return Homework(id: hw.id, groupId: hw.groupId, subjectName: hw.subjectName, subjectKey: hw.subjectKey, title: hw.title, dueDate: hw.dueDate, reminderAt: nil, isCompleted: hw.isCompleted, createdAt: hw.createdAt, isShared: true, creatorId: hw.creatorId, isImportedFromShare: hw.isImportedFromShare)
            }
        }
    }

    private func applySharedHomeworkUserCompletion() {
        guard !sharedHomeworks.isEmpty else { return }
        sharedHomeworks = sharedHomeworks.map { hw in
            let key = compoundId(gid: hw.groupId, docId: hw.id)
            let done = sharedHomeworkUserCompleted.contains(key) || sharedHomeworkUserCompleted.contains(hw.id)
            return Homework(
                id: hw.id,
                groupId: hw.groupId,
                subjectName: hw.subjectName,
                subjectKey: hw.subjectKey,
                title: hw.title,
                dueDate: hw.dueDate,
                reminderAt: hw.reminderAt,
                isCompleted: done,
                createdAt: hw.createdAt,
                isShared: true,
                creatorId: hw.creatorId,
                isImportedFromShare: hw.isImportedFromShare
            )
        }
    }

    private func applySharedExamUserCompletion() {
        guard !sharedExams.isEmpty else { return }
        sharedExams = sharedExams.map { exam in
            let key = compoundId(gid: exam.groupId, docId: exam.id)
            let done = sharedExamUserCompleted.contains(key) || sharedExamUserCompleted.contains(exam.id)
            return Exam(
                id: exam.id,
                groupId: exam.groupId,
                subjectName: exam.subjectName,
                subjectKey: exam.subjectKey,
                title: exam.title,
                notes: exam.notes,
                date: exam.date,
                hasTime: exam.hasTime,
                weight: exam.weight,
                customWeight: exam.customWeight,
                reminderAt: exam.reminderAt,
                isCompleted: done,
                createdAt: exam.createdAt,
                isShared: exam.isShared,
                creatorId: exam.creatorId,
                requiresGrade: exam.requiresGrade
            )
        }
    }

    private func applySharedExamUserRescheduledDates() {
        guard !sharedExams.isEmpty else { return }
        sharedExams = sharedExams.map { exam in
            let key = compoundId(gid: exam.groupId, docId: exam.id)
            // Check for user-specific rescheduled date
            if let rescheduledDate = sharedExamUserRescheduled[key] ?? sharedExamUserRescheduled[exam.id] {
                return Exam(
                    id: exam.id,
                    groupId: exam.groupId,
                    courseId: exam.courseId,
                    subjectName: exam.subjectName,
                    subjectKey: exam.subjectKey,
                    title: exam.title,
                    notes: exam.notes,
                    date: rescheduledDate, // Apply rescheduled date
                    hasTime: exam.hasTime,
                    weight: exam.weight,
                    customWeight: exam.customWeight,
                    reminderAt: nil, // Reset reminder for rescheduled exams
                    isCompleted: false, // Rescheduled exam is open again
                    createdAt: exam.createdAt,
                    isShared: exam.isShared,
                    creatorId: exam.creatorId,
                    requiresGrade: exam.requiresGrade
                )
            }
            return exam
        }
    }

    private var coursesQueriesListeners: [ListenerRegistration] = []
    private var coursesQueryResults: [Int: [Course]] = [:]

    private func startCoursesListener() {
        // Clear existing listeners
        coursesQueriesListeners.forEach { $0.remove() }
        coursesQueriesListeners.removeAll()
        coursesQueryResults.removeAll()
        
        guard !subscribedCourseIds.isEmpty else {
            courses = []
            stopCourseContentListeners()
            return
        }
        
        // Start listening to content immediately (we have the IDs)
        startCourseContentListeners()
        
        // Chunk IDs for Firestore "in" query limit (max 30)
        let chunks = subscribedCourseIds.chunked(into: 30)
        
        for (index, chunk) in chunks.enumerated() {
            let query = db.collection("courses").whereField(FieldPath.documentID(), in: chunk)
            let listener = query.addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    print("Courses listener error (chunk \(index)): \(error)")
                    return
                }
                guard let docs = snap?.documents else { return }
                let chunkCourses = docs.compactMap { try? $0.data(as: Course.self) }
                self.coursesQueryResults[index] = chunkCourses
                self.rebuildCourses()
            }
            coursesQueriesListeners.append(listener)
        }
    }
    
    private func rebuildCourses() {
        let allCourses = coursesQueryResults.values.flatMap { $0 }
        // Sort by name or whatever default
        self.courses = allCourses.sorted { $0.name < $1.name }
    }

    
    private var courseExamsListeners: [String: ListenerRegistration] = [:]
    private var courseHomeworksListeners: [String: ListenerRegistration] = [:]

    private func stopCourseContentListeners() {
        courseExamsListeners.values.forEach { $0.remove() }
        courseExamsListeners = [:]
        courseHomeworksListeners.values.forEach { $0.remove() }
        courseHomeworksListeners = [:]
        
        // Clear shared data from courses
        sharedExams = []
        sharedHomeworks = []
    }
    
    private func startCourseContentListeners() {
        stopCourseContentListeners() // Clean slate
        
        for courseId in subscribedCourseIds {
            // Listen to Exams
            let examsRef = db.collection("courses").document(courseId).collection("exams")
            courseExamsListeners[courseId] = examsRef.addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                let newExams = docs.compactMap { try? $0.data(as: Exam.self) }
                self.updateSharedExams(from: courseId, exams: newExams)
            }
            
            // Listen to Homework
            let hwRef = db.collection("courses").document(courseId).collection("homeworks")
            courseHomeworksListeners[courseId] = hwRef.addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                let newHw = docs.compactMap { try? $0.data(as: Homework.self) }
                self.updateSharedHomeworks(from: courseId, homeworks: newHw)
            }
        }
    }
    
    // Aggregation Maps
    private var courseExamsMap: [String: [Exam]] = [:]
    private var courseHomeworksMap: [String: [Homework]] = [:]

    private func updateSharedExams(from courseId: String, exams: [Exam]) {
        courseExamsMap[courseId] = exams
        rebuildSharedExams()
    }
    
    private func rebuildSharedExams() {
        let allExams = courseExamsMap.values.flatMap { $0 }
        // Unique by ID + Sort by date
        // Use dictionary to dedup by ID, keeping the latest one if duplicates exist (though usually identical)
        let uniqueMap = Dictionary(grouping: allExams, by: { $0.id })
            .compactMapValues { $0.first }
        
        var unique = Array(uniqueMap.values)
        
        let legacy = legacySharedExams
        // Merge legacy: if ID exists in unique, use unique (newer), else add legacy
        for l in legacy {
            if uniqueMap[l.id] == nil {
                unique.append(l)
            }
        }
        
        let finalExams = unique.sorted(by: { $0.date < $1.date })
        
        DispatchQueue.main.async { [weak self] in
            self?.sharedExams = finalExams
        }
    }

    private func updateSharedHomeworks(from courseId: String, homeworks: [Homework]) {
         courseHomeworksMap[courseId] = homeworks
         rebuildSharedHomeworks()
    }
    
    private func rebuildSharedHomeworks() {
        let allHw = courseHomeworksMap.values.flatMap { $0 }
        let uniqueMap = Dictionary(grouping: allHw, by: { $0.id })
            .compactMapValues { $0.first }
        
        var unique = Array(uniqueMap.values)
        
        let legacy = legacySharedHomeworks
        for l in legacy {
            if uniqueMap[l.id] == nil {
                unique.append(l)
            }
        }
        
        let finalHw = unique.sorted(by: { ($0.dueDate ?? Date.distantFuture) < ($1.dueDate ?? Date.distantFuture) })
        
        DispatchQueue.main.async { [weak self] in
            self?.sharedHomeworks = finalHw
        }
    }

    // MARK: - Subject Mapping Logic

    @Published var courseMappings: [String: String] = [:] // courseId -> localSubjectName (or ID)
    private var courseMappingsListener: ListenerRegistration?

    func subjectName(for course: Course) -> String {
        // 1. Check manual mapping
        if let mappedName = courseMappings[course.id] {
            return mappedName
        }
        // 2. Default to course name
        return course.name
    }

    func saveCourseMapping(courseId: String, subjectName: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let yearRef = try await requireYearRef(uid: uid)
        try await yearRef.collection("courseMappings").document(courseId).setData([
            "courseId": courseId,
            "localSubjectId": subjectName
        ], merge: true)
    }

    func startCourseMappingsListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Task {
            guard let yearRef = try? await requireYearRef(uid: uid) else { return }
            
            await MainActor.run {
                courseMappingsListener?.remove()
                courseMappingsListener = yearRef.collection("courseMappings").addSnapshotListener { [weak self] (snap: QuerySnapshot?, error: Error?) in
                    guard let self, let docs = snap?.documents else { return }
                    var newMap: [String: String] = [:]
                    for doc in docs {
                        if let local = doc.data()["localSubjectId"] as? String {
                            newMap[doc.documentID] = local
                        }
                    }
                    self.courseMappings = newMap
                }
            }
        }
    }


    
    // Check for missing subjects for a class
    func missingSubjects(for classId: String) -> [Course] {
         // Filter courses for this class that:
         // 1. Are in 'courses' list (subscribed)
         // 2. Have NO matching subject in 'subjects' (by name check)
         // 3. AND have NO existing mapping
         
         let classCourses = courses.filter { $0.classId == classId }
         let localSubjectNames = Set(subjects.map { $0.name.lowercased() })
         
         return classCourses.filter { course in
             // If mapped, it's resolved
             if courseMappings[course.id] != nil { return false }
             
             // Check direct name match
             if localSubjectNames.contains(course.name.lowercased()) { return false }
             
             return true
         }
    }

    // MARK: - User-Settings + Key

    private func applyUserSettings(from data: [String: Any]) {
        let previousAppIcon = appIcon
        if let incomingActive = (data["activeSchoolYearId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !incomingActive.isEmpty,
           incomingActive != activeSchoolYearId {
            resetSchoolYearScopedData()
            activeSchoolYearId = incomingActive
        }

        compactView = (data["compactView"] as? Bool) ?? compactView
        animationsEnabled = (data["animationsEnabled"] as? Bool) ?? animationsEnabled
        showHolidayHints = (data["holidayHintsEnabled"] as? Bool) ?? showHolidayHints

        if let themeVal = data["theme"] as? String, ["default","feminine"].contains(themeVal) {
            theme = themeVal
        }
        if let rawIntensity = data["themeIntensity"] as? Double ?? (data["themeIntensity"] as? NSNumber)?.doubleValue {
            let clamped = max(0, min(1, rawIntensity))
            themeBackgroundIntensity = clamped
            UserDefaults.standard.set(clamped, forKey: "grades_themeIntensity")
        }
        if let iconVal = data["appIcon"] as? String, supportedAppIcons.contains(iconVal) {
            appIcon = iconVal
            UserDefaults.standard.set(iconVal, forKey: appIconDefaultsKey)
        }
        if let hr = data["homeworkReminderHour"] as? Int, (0...23).contains(hr) {
            homeworkReminderHour = hr
        } else {
            homeworkReminderHour = 19
        }
        if let mn = data["homeworkReminderMinute"] as? Int, (0...59).contains(mn) {
            homeworkReminderMinute = mn
        } else {
            homeworkReminderMinute = 0
        }
        if let std = data["standardRemindersEnabled"] as? Bool {
            standardRemindersEnabled = std
        } else if UserDefaults.standard.object(forKey: "grades_standardRemindersEnabled") != nil {
            standardRemindersEnabled = UserDefaults.standard.bool(forKey: "grades_standardRemindersEnabled")
        } else {
            standardRemindersEnabled = true
        }
        UserDefaults.standard.set(standardRemindersEnabled, forKey: "grades_standardRemindersEnabled")
        if let mode = data["darkModeMode"] as? String, ["system","light","dark"].contains(mode) {
            darkModeMode = mode
        } else if let dm = data["darkMode"] as? Bool {
            darkModeMode = dm ? "dark" : "light"
        } else {
            darkModeMode = "system"
        }
        darkMode = effectiveDarkMode(for: darkModeMode)
        // gradeYear wird pro Schuljahr verwaltet (siehe applySchoolYearSettings)

        let onboardingDoneFlag = resolveOnboardingDone(from: data)
        onboardingRequired = !onboardingDoneFlag
        rescheduleLocalNotifications()

        // Preload potentielles Vorjahres-Snapshot im Hintergrund (z. B. FOS 11 -> 12)
        Task { [weak self] in
            guard let self, let sid = self.activeSchoolYearId else { return }
            await self.preloadPreviousYearSnapshotIfNeeded(currentYearId: sid)
        }

        if previousAppIcon != appIcon {
            Task { [weak self] in
                await self?.applyAppIconSelectionIfNeeded()
            }
        }
        
        if let subs = data["subscribedCourseIds"] as? [String] {
            let unique = Array(Set(subs)).sorted()
            if unique != subscribedCourseIds {
                subscribedCourseIds = unique
                Task { [weak self] in self?.startCoursesListener() }
            }
        } else {
             if !subscribedCourseIds.isEmpty {
                 subscribedCourseIds = []
                 coursesListener?.remove()
                 coursesListener = nil
                 courses = []
             }
        }

        // Admin support access
        adminAccessGranted = (data["adminAccessGranted"] as? Bool) ?? false
        if let ts = data["adminAccessExpiresAt"] as? Timestamp {
            let expiresDate = ts.dateValue()
            // Auto-expire if past expiration
            if expiresDate > Date() {
                adminAccessExpiresAt = expiresDate
            } else {
                adminAccessExpiresAt = nil
                adminAccessGranted = false
            }
        } else {
            adminAccessExpiresAt = nil
        }

        persistOfflineSnapshotIfPossible()
    }

    private func applySchoolYearSettings(from data: [String: Any], uid: String, fallbackUserData: [String: Any]? = nil) {
        let fallback = fallbackUserData ?? [:]

        let yearExamGroupIds = data["examGroupIds"] as? [String]
        let fbExamGroupIds = fallback["examGroupIds"] as? [String]
        examGroupIds = yearExamGroupIds ?? fbExamGroupIds ?? []

        let yearExamGroupId = (data["examGroupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fbExamGroupId = (fallback["examGroupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let gid = yearExamGroupId, !gid.isEmpty {
            examGroupId = gid
            if !examGroupIds.contains(gid) { examGroupIds.append(gid) }
        } else if let fb = fbExamGroupId, !fb.isEmpty {
            examGroupId = fb
            if !examGroupIds.contains(fb) { examGroupIds.append(fb) }
        } else {
            examGroupId = examGroupIds.first
        }

        let yearHomeworkGroupIds = data["homeworkGroupIds"] as? [String]
        let fbHomeworkGroupIds = fallback["homeworkGroupIds"] as? [String]
        homeworkGroupIds = yearHomeworkGroupIds ?? fbHomeworkGroupIds ?? []

        let yearHomeworkGroupId = (data["homeworkGroupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fbHomeworkGroupId = (fallback["homeworkGroupId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let gid = yearHomeworkGroupId, !gid.isEmpty {
            homeworkGroupId = gid
            if !homeworkGroupIds.contains(gid) { homeworkGroupIds.append(gid) }
        } else if let fb = fbHomeworkGroupId, !fb.isEmpty {
            homeworkGroupId = fb
            if !homeworkGroupIds.contains(fb) { homeworkGroupIds.append(fb) }
        } else {
            homeworkGroupId = homeworkGroupIds.first
        }

        // Ab hier: keine Trennung mehr zwischen Klausur- und Hausaufgabengruppen.
        if let common = examGroupId ?? homeworkGroupId {
            examGroupId = common
            homeworkGroupId = common
            if !examGroupIds.contains(common) { examGroupIds.append(common) }
            if !homeworkGroupIds.contains(common) { homeworkGroupIds.append(common) }
        }

        var unionIds = Array(Set(examGroupIds + homeworkGroupIds))
        examGroupIds = unionIds
        homeworkGroupIds = unionIds

        let yearGroupIds = data["groupIds"] as? [String]
        let fbGroupIds = fallback["groupIds"] as? [String]
        if let gids = yearGroupIds ?? fbGroupIds {
            groupIds = gids
        } else {
            groupIds = unionIds
        }
        unionIds = Array(Set(unionIds + groupIds))
        groupIds = unionIds
        examGroupIds = unionIds
        homeworkGroupIds = unionIds

        if let sid = activeSchoolYearId,
           let name = (data["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            schoolYearNames[sid] = name
        }

        if let gy = data["gradeYear"] as? Int, (11...13).contains(gy) {
            gradeYear = gy
        } else if let gy = fallback["gradeYear"] as? Int, (11...13).contains(gy) {
            gradeYear = gy
        } else {
            gradeYear = nil
        }

        if let stRaw = data["schoolType"] as? String, let st = SchoolType(rawValue: stRaw) {
            schoolType = st
        } else if let stRaw = fallback["schoolType"] as? String, let st = SchoolType(rawValue: stRaw) {
            schoolType = st
        } else {
            schoolType = .bos
        }

        if let modeStr = data["subjectSortMode"] as? String,
           let mode = SubjectSortMode(rawValue: modeStr) {
            subjectSortMode = mode
        } else {
            subjectSortMode = .name
        }
        if let order = data["subjectSortOrder"] as? [String] {
            subjectSortOrder = order
        } else {
            subjectSortOrder = []
        }
        if let customOrder = data["subjectCustomOrder"] as? [String] {
            subjectCustomOrder = customOrder
        } else {
            subjectCustomOrder = subjectSortOrder
        }

        updateGroupObservers(uid: uid, schoolYearId: activeSchoolYearId)
        updateSharedExamsListenerIfNeeded()
        updateSharedHomeworksListenerIfNeeded()
        updateExamGroupSubjectsListenerIfNeeded(forceReload: true)
        updateHomeworkGroupSubjectsListenerIfNeeded(forceReload: true)
        updateExamSubjectMappingListenerIfNeeded(uid: uid, forceReload: true)
        updateHomeworkSubjectMappingListenerIfNeeded(uid: uid, forceReload: true)

        Task {
            await repairGroupMemberships(uid: uid)
        }

        persistOfflineSnapshotIfPossible()
    }
    
    private func repairGroupMemberships(uid: String) async {
        let key = "didRunGroupMembershipRepair_v1"
        if UserDefaults.standard.bool(forKey: key) { return }
        
        for gid in groupIds {
             let ref = db.collection("groups").document(gid).collection("members").document(uid)
             do {
                 let snap = try await ref.getDocument()
                 if !snap.exists {
                     try await ref.setData(["joinedAt": Date()])
                 }
             } catch {
                 // Ignore errors
             }
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    private func deriveKeyIfNeeded(from data: [String: Any], uid: String) async {
        // Leite Key aus encryptionSalt ab, wenn vorhanden
        if let salt = data["encryptionSalt"] as? String {
            do {
                encryptionSalt = salt
                let key = try CryptoService.deriveKeyFromPassword(password: uid, saltBase64: salt, iterations: 150_000)
                let keyChanged = (self.encryptionKey == nil) // oder man könnte Keyvergleich machen
                self.encryptionKey = key
                if keyChanged {
                    // Sobald Key gesetzt, alle Caches entschlüsseln
                    self.decryptAllCachedGradesIfPossible()
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                self.encryptionKey = nil
                encryptionSalt = nil
                // Ohne Key bleiben Noten leer
                self.decryptAllCachedGradesIfPossible()
            }
        } else {
            // Kein Salt -> kein Key
            self.encryptionKey = nil
            encryptionSalt = nil
            self.decryptAllCachedGradesIfPossible()
        }
    }

    func updatePrivacyMode(active: Bool) {
        self.isPrivacyModeActive = active
        UserDefaults.standard.set(active, forKey: "grades_isPrivacyModeActive")
    }

    private func loadLocalPreferences() {
        let defaults = UserDefaults.standard

        if let storedTheme = defaults.string(forKey: "grades_theme"),
           ["default", "feminine"].contains(storedTheme) {
            theme = storedTheme
        }
        if defaults.object(forKey: "grades_themeIntensity") != nil {
            let storedIntensity = defaults.double(forKey: "grades_themeIntensity")
            themeBackgroundIntensity = max(0, min(1, storedIntensity))
        } else {
            themeBackgroundIntensity = 1.0
        }
        if let storedIcon = defaults.string(forKey: appIconDefaultsKey),
           supportedAppIcons.contains(storedIcon) {
            appIcon = storedIcon
        } else {
            appIcon = "default"
        }
        if defaults.object(forKey: "grades_hwReminderHour") != nil,
           defaults.object(forKey: "grades_hwReminderMinute") != nil {
            let hr = defaults.integer(forKey: "grades_hwReminderHour")
            let mn = defaults.integer(forKey: "grades_hwReminderMinute")
            if (0...23).contains(hr) { homeworkReminderHour = hr }
            if (0...59).contains(mn) { homeworkReminderMinute = mn }
        } else {
            homeworkReminderHour = 19
            homeworkReminderMinute = 0
        }
        if let storedMode = defaults.string(forKey: "grades_darkModeMode"),
           ["system", "light", "dark"].contains(storedMode) {
            darkModeMode = storedMode
        } else if defaults.object(forKey: "grades_darkMode") != nil {
            darkModeMode = defaults.bool(forKey: "grades_darkMode") ? "dark" : "light"
        } else {
            darkModeMode = "system"
        }
        darkMode = effectiveDarkMode(for: darkModeMode)
        if defaults.object(forKey: "grades_standardRemindersEnabled") != nil {
            standardRemindersEnabled = defaults.bool(forKey: "grades_standardRemindersEnabled")
        }
        if defaults.object(forKey: "grades_compactView") != nil {
            compactView = defaults.bool(forKey: "grades_compactView")
        }
        if defaults.object(forKey: "grades_animationsEnabled") != nil {
            animationsEnabled = defaults.bool(forKey: "grades_animationsEnabled")
        }
        if let stored = defaults.array(forKey: pfingstferienPromptedKey) as? [String] {
            pfingstferienPromptedYearIds = Set(stored)
        }
        if defaults.object(forKey: "grades_showHolidayHints") != nil {
            showHolidayHints = defaults.bool(forKey: "grades_showHolidayHints")
        } else {
            showHolidayHints = true
        }

        isPrivacyModeActive = defaults.bool(forKey: "grades_isPrivacyModeActive")
        Task { await self.applyAppIconSelectionIfNeeded() }
    }

    @MainActor
    private func applyAppIconSelectionIfNeeded() async {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let targetName = alternateIconName(for: appIcon)
        guard UIApplication.shared.alternateIconName != targetName else { return }

        if let iconsDict = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let alternates = (iconsDict["CFBundleAlternateIcons"] as? [String: Any])?.keys.sorted() {
            print("Available alternate icons in Info.plist: \(alternates)")
        } else {
            print("No alternate icons found in Info.plist")
        }

        if #available(iOS 16.0, *) {
            do {
                try await UIApplication.shared.setAlternateIconName(targetName)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                print("AppIcon switch failed for \(targetName ?? "primary"): \(error)")
                let resolved = selection(forAlternateIconName: UIApplication.shared.alternateIconName)
                appIcon = resolved
                UserDefaults.standard.set(appIcon, forKey: appIconDefaultsKey)
            }
        } else {
            UIApplication.shared.setAlternateIconName(targetName) { error in
                guard let error else { return }
                print("AppIcon switch failed for \(targetName ?? "primary"): \(error)")
                Task { @MainActor in
                    ErrorLoggingService.logErrorIfEnabled(error)
                    let resolved = self.selection(forAlternateIconName: UIApplication.shared.alternateIconName)
                    self.appIcon = resolved
                    UserDefaults.standard.set(resolved, forKey: self.appIconDefaultsKey)
                }
            }
        }
    }

    private func alternateIconName(for selection: String) -> String? {
        switch selection {
        case "pink":
            return "AppIconTwo"
        default:
            return nil
        }
    }

    private func selection(forAlternateIconName name: String?) -> String {
        switch name {
        case "AppIconTwo":
            return "pink"
        default:
            return "default"
        }
    }

    // MARK: - Pfingstferien Prompt

    private func markPfingstferienPromptShown(for yearId: String) {
        pfingstferienPromptedYearIds.insert(yearId)
        UserDefaults.standard.set(Array(pfingstferienPromptedYearIds), forKey: pfingstferienPromptedKey)
    }

    private func hasShownPfingstferienPrompt(for yearId: String) -> Bool {
        pfingstferienPromptedYearIds.contains(yearId)
    }

    func shouldOfferNextSchoolYearAfterPfingstferien(currentDate: Date = Date()) async -> String? {
        guard gradeYear == 12 else { return nil }
        guard let currentYearId = activeSchoolYearId else { return nil }
        if hasShownPfingstferienPrompt(for: currentYearId) { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let currentCalendarYear = calendar.component(.year, from: currentDate)

        let pfingstEnd = await HolidaysService.shared.pfingstferienEndDate(forYear: currentCalendarYear)
        guard let pfingstEnd else { return nil }
        guard currentDate > pfingstEnd else { return nil }

        markPfingstferienPromptShown(for: currentYearId)
        return SchoolYearService.nextSchoolYearId(from: currentYearId)
    }

    // MARK: - Offline Cache

    private func persistOfflineSnapshotIfPossible() {
        let uid = Auth.auth().currentUser?.uid ?? OfflineModeManager.shared.cachedSnapshot?.userId
        guard let uid else { return }
        OfflineModeManager.shared.scheduleSnapshotSave(from: self, userId: uid)
    }

    func makeOfflineSnapshot(userId: String) -> OfflineSnapshot {
        OfflineSnapshot(
            userId: userId,
            capturedAt: Date(),
            activeSchoolYearId: activeSchoolYearId,
            encryptionSalt: encryptionSalt,
            subjects: subjects,
            gradesBySubject: gradesBySubject,
            fachreferat: fachreferat,
            seminarPerformance: seminarPerformance,
            practicalPerformance: practicalPerformance,
            homeworks: homeworks,
            exams: exams,
            sharedExams: sharedExams,
            sharedHomeworks: sharedHomeworks,
            examGroupId: examGroupId,
            homeworkGroupId: homeworkGroupId,
            groupIds: groupIds,
            groupNames: groupNames,
            groupSubjectMappings: groupSubjectMappings,
            groupExamsByGroup: groupExamsByGroup,
            groupHomeworksByGroup: groupHomeworksByGroup,
            schoolYears: schoolYears,
            gradeYear: gradeYear,
            schoolType: schoolType,
            subjectSortMode: subjectSortMode,
            subjectSortOrder: subjectSortOrder,
            compactView: compactView,
            animationsEnabled: animationsEnabled,
            showHolidayHints: showHolidayHints,
            theme: theme,
            themeIntensity: themeBackgroundIntensity,
            appIcon: appIcon,
            darkMode: darkMode,
            darkModeMode: darkModeMode,
            homeworkReminderHour: homeworkReminderHour,
            homeworkReminderMinute: homeworkReminderMinute,
            standardRemindersEnabled: standardRemindersEnabled,
            pendingGrades: offlinePendingGrades,
            pendingFachreferat: offlinePendingFachreferat,
            pendingSeminar: offlinePendingSeminar
        )
    }

    func loadOfflineSnapshot(_ snapshot: OfflineSnapshot) {
        stopListening()
        isOfflineMode = true

        activeSchoolYearId = snapshot.activeSchoolYearId
        subjects = snapshot.subjects
        gradesBySubject = snapshot.gradesBySubject
        fachreferat = snapshot.fachreferat
        seminarPerformance = snapshot.seminarPerformance
        practicalPerformance = snapshot.practicalPerformance
        homeworks = snapshot.homeworks
        exams = snapshot.exams
        sharedExams = snapshot.sharedExams
        sharedHomeworks = snapshot.sharedHomeworks
        examGroupId = snapshot.examGroupId
        homeworkGroupId = snapshot.homeworkGroupId
        groupIds = snapshot.groupIds
        groupNames = snapshot.groupNames
        groupOwners = [:]
        groupSubjectMappings = snapshot.groupSubjectMappings
        groupExamsByGroup = snapshot.groupExamsByGroup
        groupHomeworksByGroup = snapshot.groupHomeworksByGroup
        schoolYears = snapshot.schoolYears
        gradeYear = snapshot.gradeYear
        schoolType = snapshot.schoolType
        subjectSortMode = snapshot.subjectSortMode
        subjectSortOrder = snapshot.subjectSortOrder
        compactView = snapshot.compactView
        animationsEnabled = snapshot.animationsEnabled
        showHolidayHints = snapshot.showHolidayHints ?? true
        theme = snapshot.theme
        themeBackgroundIntensity = max(0, min(1, snapshot.themeIntensity ?? 1.0))
        if let icon = snapshot.appIcon, supportedAppIcons.contains(icon) {
            appIcon = icon
            UserDefaults.standard.set(icon, forKey: appIconDefaultsKey)
        }
        darkMode = snapshot.darkMode
        darkModeMode = snapshot.darkModeMode
        homeworkReminderHour = snapshot.homeworkReminderHour
        homeworkReminderMinute = snapshot.homeworkReminderMinute
        standardRemindersEnabled = snapshot.standardRemindersEnabled ?? true
        encryptionSalt = snapshot.encryptionSalt
        offlinePendingGrades = snapshot.pendingGrades
        offlinePendingFachreferat = snapshot.pendingFachreferat
        offlinePendingSeminar = snapshot.pendingSeminar

        if encryptionKey == nil, let salt = snapshot.encryptionSalt {
            let uid = snapshot.userId
            if let key = try? CryptoService.deriveKeyFromPassword(password: uid, saltBase64: salt, iterations: 150_000) {
                encryptionKey = key
                decryptAllCachedGradesIfPossible()
            }
        }

        isLoading = false
        loadingLabel = ""
        progress = 0

        rescheduleLocalNotifications()

        Task { await self.applyAppIconSelectionIfNeeded() }

        OfflineModeManager.shared.activateOfflineMode()
    }

    func exitOfflineModeIfNeeded() {
        if isOfflineMode {
            isOfflineMode = false
            resetState()
            OfflineModeManager.shared.deactivateOfflineMode()
        }
    }

    func leaveOfflineModePreservingState() {
        if isOfflineMode {
            isOfflineMode = false
            OfflineModeManager.shared.deactivateOfflineMode()
        }
    }

    func importLegacyDataIntoActiveYearIfNeeded() async {
        guard legacyImportSelected == true else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let id = try await SchoolYearService.ensureActiveSchoolYear(
                uid: uid,
                userData: pendingLegacyUserData,
                preferredId: activeSchoolYearId,
                db: db,
                skipLegacyMigration: true,
                allowCreation: true,
                gateOnOnboarding: false,
                allowLegacyMigration: false,
                allowedLegacySubjects: legacySelectedSubjects,
                setMigratedFlag: false
            )
            activeSchoolYearId = id
            let userRef = db.collection("users").document(uid)
            let yearRef = schoolYearRef(uid: uid, id: id)
            try await SchoolYearService.migrateLegacyDataIfNeeded(
                userRef: userRef,
                yearRef: yearRef,
                allowedSubjects: legacySelectedSubjects.isEmpty ? nil : legacySelectedSubjects
            )
            legacyImportSelected = nil
            legacyMigrationSummary = nil
            pendingLegacyUserData = nil
            legacySelectedSubjects = []
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional: Logging
        }
    }

    // MARK: - Offline Sync zurück ins Backend

    func syncOfflinePendingChanges(forceLocalOverride: Bool = false) async {
        var snapshot = OfflineModeManager.shared.cachedSnapshot
        if snapshot == nil {
            snapshot = OfflineModeManager.shared.availableSnapshot()
        }

        if offlinePendingGrades.isEmpty && offlinePendingFachreferat == nil && offlinePendingSeminar == nil, let snap = snapshot {
            offlinePendingGrades = snap.pendingGrades
            offlinePendingFachreferat = snap.pendingFachreferat
            offlinePendingSeminar = snap.pendingSeminar
            if encryptionSalt == nil {
                encryptionSalt = snap.encryptionSalt
            }
            overlayPendingData()
        }

        if waitingForLegacyDecision { return }
        if onboardingRequired && activeSchoolYearId == nil { return }

        guard !offlinePendingGrades.isEmpty || offlinePendingFachreferat != nil || offlinePendingSeminar != nil else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        OfflineModeManager.shared.enableFirestoreNetworkIfNeeded()

        let saltForKey = encryptionSalt ?? snapshot?.encryptionSalt
        if encryptionKey == nil, let salt = saltForKey {
            if let key = try? CryptoService.deriveKeyFromPassword(password: uid, saltBase64: salt, iterations: 150_000) {
                encryptionKey = key
            }
        }
        guard let key = encryptionKey else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }

        var remainingGrades: [PendingGrade] = []
        for pending in offlinePendingGrades {
            do {
                let ref = yearRef.collection("subjects").document(pending.subjectId).collection("grades").document(pending.id)
                let existing = try await ref.getDocument()
                if !forceLocalOverride,
                   let existingData = existing.data(),
                   let ts = existingData["updatedAt"] as? Timestamp,
                   ts.dateValue() >= pending.createdAt {
                    continue // Server ist aktueller oder gleich
                }
                let encrypted = try CryptoService.encryptString(String(pending.grade), key: key)
                var payload: [String: Any] = [
                    "grade": encrypted,
                    "weight": pending.weight,
                    "date": pending.date,
                    "note": pending.note as Any,
                    "halfYear": pending.halfYear as Any,
                    "updatedAt": pending.createdAt
                ]
                if let linked = pending.linkedExamId { payload["linkedExamId"] = linked }
                try await ref.setData(payload, merge: true)
                remainingGrades.append(pending) // bis Listener updatedAt bestätigt
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                remainingGrades.append(pending)
            }
        }
        offlinePendingGrades = remainingGrades

        if let pendingFr = offlinePendingFachreferat {
            do {
                let ref = yearRef.collection("fachreferat").document("current")
                let existing = try await ref.getDocument()
                if !forceLocalOverride,
                   let data = existing.data(),
                   let ts = data["updatedAt"] as? Timestamp,
                   ts.dateValue() >= pendingFr.createdAt {
                    // Server-Version behalten
                } else {
                    let encrypted = try CryptoService.encryptString(String(pendingFr.grade), key: key)
                    try await ref.setData([
                        "grade": encrypted,
                        "subjectName": pendingFr.subjectName,
                        "date": pendingFr.date,
                        "note": pendingFr.note as Any,
                        "updatedAt": pendingFr.createdAt
                    ], merge: true)
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // bleibt pending
            }
        }

        if let pendingSem = offlinePendingSeminar {
            do {
                let ref = yearRef.collection("seminar").document("current")
                let existing = try await ref.getDocument()
                if !forceLocalOverride,
                   let data = existing.data(),
                   let ts = data["updatedAt"] as? Timestamp,
                   ts.dateValue() >= pendingSem.createdAt {
                    // Server-Version ist aktueller
                } else {
                    var payload: [String: Any] = [
                        "topic": pendingSem.topic as Any,
                        "submissionDate": pendingSem.submissionDate as Any,
                        "presentationDate": pendingSem.presentationDate as Any,
                        "note": pendingSem.note as Any,
                        "updatedAt": pendingSem.createdAt
                    ]

                    if let individual = pendingSem.individualPoints {
                        payload["individualPoints"] = try CryptoService.encryptString(String(individual), key: key)
                    }
                    if let paper = pendingSem.paperPoints {
                        payload["paperPoints"] = try CryptoService.encryptString(String(paper), key: key)
                    }
                    if let presentation = pendingSem.presentationPoints {
                        payload["presentationPoints"] = try CryptoService.encryptString(String(presentation), key: key)
                    }

                    if pendingSem.individualPoints == nil { payload["individualPoints"] = FieldValue.delete() }
                    if pendingSem.paperPoints == nil { payload["paperPoints"] = FieldValue.delete() }
                    if pendingSem.presentationPoints == nil { payload["presentationPoints"] = FieldValue.delete() }
                    if pendingSem.topic == nil { payload["topic"] = FieldValue.delete() }
                    if pendingSem.submissionDate == nil { payload["submissionDate"] = FieldValue.delete() }
                    if pendingSem.presentationDate == nil { payload["presentationDate"] = FieldValue.delete() }
                    if pendingSem.note == nil { payload["note"] = FieldValue.delete() }

                    try await ref.setData(payload, merge: true)
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // bleibt pending
            }
        }

        persistOfflineSnapshotIfPossible()
    }

    // MARK: - Gemeinsame Klausurtermine (Gruppen)

    private func normalizedExamGroupCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func generateExamGroupCode(length: Int = 6) -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var result = ""
        for _ in 0..<length {
            if let c = chars.randomElement() {
                result.append(c)
            }
        }
        return result
    }

    private func updateSharedExamsListenerIfNeeded() {
        // Falls keine Gruppe mehr vorhanden ist, Listener entfernen
        if examGroupId == nil {
            sharedExamsListener?.remove()
            sharedExamsListener = nil
            sharedExamsGroupId = nil
            sharedExams = []
            return
        }

        guard let gid = examGroupId else { return }

        // Wenn bereits für dieselbe Gruppe aktiv, nichts tun
        if sharedExamsGroupId == gid, sharedExamsListener != nil {
            return
        }

        // Falls Gruppe gewechselt wurde, alten Listener entfernen
        sharedExamsListener?.remove()
        sharedExamsListener = nil
        sharedExamsGroupId = nil
        sharedExams = []

        sharedExamsGroupId = gid
        sharedExamsListener = db.collection("examGroups")
            .document(gid)
            .collection("exams")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                ErrorLoggingService.logErrorIfEnabled(error)
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    let list: [Exam] = docs.compactMap { doc in
                        let data = doc.data()
                        let subjectName = data["subjectName"] as? String ?? ""
                        let subjectKey = data["subjectKey"] as? String
                        let title = data["title"] as? String ?? ""
                        let notes = data["notes"] as? String
                        let createdTs = data["createdAt"] as? Timestamp
                        let createdAt = createdTs?.dateValue() ?? Date()
                        guard let dateTs = data["date"] as? Timestamp else { return nil }
                        let date = dateTs.dateValue()
                        let hasTimeFlag = data["hasTime"] as? Bool
                        let calendar = Calendar.current
                        let hasTime = hasTimeFlag ?? !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
                        let weight = data["weight"] as? Int
                        let customWeight = (data["customWeight"] as? NSNumber)?.doubleValue
                        let creatorId = data["creatorId"] as? String
                        let requiresGrade = data["requiresGrade"] as? Bool
                        return Exam(
                            id: doc.documentID,
                            groupId: gid,
                            subjectName: subjectName,
                            subjectKey: subjectKey,
                            title: title,
                            notes: notes,
                            date: date,
                            hasTime: hasTime,
                            weight: weight,
                            customWeight: customWeight,
                            reminderAt: nil,
                            isCompleted: false,
                            createdAt: createdAt,
                            isShared: true,
                            creatorId: creatorId,
                            requiresGrade: requiresGrade
                        )
                    }
                    self.legacySharedExams = list
                    self.recomputeSharedCollections()
                    await self.loadExamGroupName()
                    self.persistOfflineSnapshotIfPossible()
                }
            }
    }
    
    private func updateSharedHomeworksListenerIfNeeded() {
        if homeworkGroupId == nil {
            sharedHomeworksListener?.remove()
            sharedHomeworksListener = nil
            sharedHomeworksGroupId = nil
            sharedHomeworks = []
            return
        }
        guard let gid = homeworkGroupId else { return }
        if sharedHomeworksGroupId == gid, sharedHomeworksListener != nil { return }
        sharedHomeworksListener?.remove()
        sharedHomeworksListener = nil
        sharedHomeworksGroupId = nil
        sharedHomeworks = []
        sharedHomeworksGroupId = gid
        sharedHomeworksListener = db.collection("homeworkGroups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                self.homeworkGroupSubjects = docs.map { d in
                    let data = d.data()
                    let name = data["name"] as? String ?? d.documentID
                    let type = data["type"] as? Int
                    let alias = data["alias"] as? String
                    return GroupSubject(id: d.documentID, name: name, type: type, alias: alias)
                }
                self.persistOfflineSnapshotIfPossible()
            }
        }
        sharedHomeworksListener = db.collection("homeworkGroups").document(gid).collection("homeworks").order(by: "createdAt", descending: false).addSnapshotListener { [weak self] snapshot, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snapshot?.documents ?? []
                let list: [Homework] = docs.compactMap { doc in
                    let data = doc.data()
                    let subjectName = data["subjectName"] as? String ?? ""
                    let subjectKey = data["subjectKey"] as? String
                    let title = data["title"] as? String ?? ""
                    let createdTs = data["createdAt"] as? Timestamp
                    let createdAt = createdTs?.dateValue() ?? Date()
                    let dueTs = data["dueDate"] as? Timestamp
                    let dueDate = dueTs?.dateValue()
                    let creatorId = data["creatorId"] as? String
                    return Homework(
                        id: doc.documentID,
                        groupId: gid,
                        subjectName: subjectName,
                        subjectKey: subjectKey,
                        title: title,
                        dueDate: dueDate,
                        reminderAt: nil,
                        isCompleted: false,
                        createdAt: createdAt,
                        isShared: true,
                        creatorId: creatorId,
                        isImportedFromShare: false
                    )
                }
                self.legacySharedHomeworks = list
                self.recomputeSharedCollections()
                self.persistOfflineSnapshotIfPossible()
            }
        }
    }

    func createExamGroupIfNeeded(name: String? = nil) async throws -> String {
        guard Auth.auth().currentUser?.uid != nil else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        // Standard: alle aktuell verfügbaren Fächer, die noch nicht in anderen Gruppen gemappt sind
        let selectable = availableSubjectsForNewGroup().map { $0.name }
        return try await createSharedGroup(name: name ?? "Gruppe", subjects: selectable)
    }

    // Neue zentrale Gruppenerstellung (/groups)
    // Neue zentrale Gruppenerstellung (/groups)
    func createSharedGroup(name: String, subjects: [String]) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let code = generateExamGroupCode()
        let yearRef = try await requireYearRef(uid: uid)
        let activeYearId = activeSchoolYearId

        // Gruppe anlegen
        let groupRef = db.collection("groups").document(code)
        try await groupRef.setData([
            "ownerId": uid,
            "createdAt": Date(),
            "name": name as Any,
            "schoolYearId": activeYearId as Any
        ], merge: true)

        try await groupRef.collection("members").document(uid).setData([
            "joinedAt": Date()
        ])

        try await yearRef.setData([
            "groupIds": FieldValue.arrayUnion([code]),
            "examGroupIds": FieldValue.arrayUnion([code]),      // Kompatibilität
            "homeworkGroupIds": FieldValue.arrayUnion([code]),  // Kompatibilität
            "examGroupId": code,
            "homeworkGroupId": code
        ], merge: true)

        let union = Array(Set(groupIds + [code]))
        groupIds = union
        examGroupIds = union
        homeworkGroupIds = union
        groupNames[code] = name
        groupOwners[code] = uid
        examGroupId = code
        homeworkGroupId = code

        // Seed group subjects from ausgewählten Subjects
        var seededSubjects: [GroupSubject] = []
        var mapping: [String: String] = [:]
        
        for name in subjects where !name.isEmpty {
            // Try to find existing subject to copy type/alias
            let existing = self.subjects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
            
            let sid = slugifySubjectName(name)
            let payload: [String: Any] = [
                "name": name, // Use original casing if it was manual, or we could use existing.name
                "type": existing?.type ?? 0, // Default to 0 if manual
                "alias": existing?.alias as Any
            ]
            
            try await db.collection("groups").document(code).collection("subjects").document(sid).setData(payload, merge: true)
            seededSubjects.append(GroupSubject(id: sid, name: name, type: existing?.type ?? 0, alias: existing?.alias))
            mapping[sid] = name
        }
        
        groupSubjectsByGroup[code] = seededSubjects
        groupSubjectMappings[code] = mapping
        try await yearRef.collection("groupMappings").document(code).setData(["map": mapping], merge: true)

        updateGroupObservers(uid: uid, schoolYearId: yearRef.documentID)

        return code
    }
    
    func deleteSharedGroup(code: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // 1. Verify ownership
        let groupRef = db.collection("groups").document(code)
        let doc = try await groupRef.getDocument()
        guard let owner = doc.data()?["ownerId"] as? String, owner == uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Du bist nicht der Besitzer dieser Gruppe."])
        }
        
        // 2. Delete the group document (this technically leaves subcollections as orphans in standard Firestore,
        // but prevents it from being loaded).
        // A Cloud Function trigger or recursive delete would be cleaner, but for client-side:
        try await groupRef.delete()
        
        // 3. Clean up own reference
        await leaveSharedGroup(code: code)
        
        // Remove locally immediately
        await MainActor.run {
            self.groupNames.removeValue(forKey: code)
            self.groupOwners.removeValue(forKey: code)
        }
    }
    
    func createHomeworkGroupIfNeeded(name: String? = nil) async throws -> String {
        // Für die neue Logik gibt es nur noch eine gemeinsame Gruppe.
        // Delegiere an createExamGroupIfNeeded, damit beide Gruppen dieselbe ID nutzen.
        return try await createExamGroupIfNeeded(name: name)
    }

    func joinSharedGroup(with rawCode: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)

        let code = normalizedExamGroupCode(rawCode)
        guard !code.isEmpty else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Gruppencode"])
        }

        // Sicherstellen, dass die Gruppe existiert
        let groupRef = db.collection("groups").document(code)
        let snap = try await groupRef.getDocument()
        guard snap.exists else {
             throw NSError(domain: "GradesStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Diese Gruppe existiert nicht oder wurde gelöscht."])
        }
        
        if let groupYear = snap.data()?["schoolYearId"] as? String,
                  let currentYear = activeSchoolYearId,
                  !groupYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  groupYear != currentYear {
            throw NSError(domain: "GradesStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Diese Gruppe gehört zum Schuljahr \(groupYear) und kann nicht in \(currentYear) beigetreten werden."])
        }

        // User-Dokument aktualisieren (beide Arrays + aktive IDs)
        try await yearRef.setData([
            "groupIds": FieldValue.arrayUnion([code]),
            "examGroupIds": FieldValue.arrayUnion([code]),
            "homeworkGroupIds": FieldValue.arrayUnion([code]),
            "examGroupId": code,
            "homeworkGroupId": code
        ], merge: true)

        try await groupRef.collection("members").document(uid).setData([
            "joinedAt": Date()
        ])

        let union = Array(Set(groupIds + [code]))
        groupIds = union
        examGroupIds = union
        homeworkGroupIds = union
        examGroupId = code
        homeworkGroupId = code

        // Listener aktualisieren
        updateGroupObservers(uid: uid, schoolYearId: activeSchoolYearId)

        await loadGroupName(gid: code)
        updateGroupObservers(uid: uid, schoolYearId: activeSchoolYearId)
        await loadGroupName(gid: code)
    }

    /// Tries to join multiple groups by code. Returns success codes and errors keyed by code.
    func joinSharedGroups(codes: [String]) async -> (joined: [String], errors: [String: String]) {
        var joinedCodes: [String] = []
        var errorMap: [String: String] = [:]

        for raw in codes {
            do {
                try await joinSharedGroup(with: raw)
                joinedCodes.append(raw)
            } catch {
                errorMap[raw] = error.localizedDescription
            }
        }
        return (joinedCodes, errorMap)
    }

    // MARK: - School Classes (Klassen)

    func createClass(name: String) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        let code = generateExamGroupCode()
        let classRef = db.collection("classes").document(code)
        
        try await classRef.setData([
            "name": name,
            "ownerId": uid,
            "createdAt": Date(),
            "groupIds": []
        ])
        
        try await classRef.collection("members").document(uid).setData([
            "joinedAt": Date()
        ])
        
        let yearRef = try await requireYearRef(uid: uid)
        try await yearRef.setData([
            "classIds": FieldValue.arrayUnion([code])
        ], merge: true)
        
        await MainActor.run {
            if !classIds.contains(code) {
                classIds.append(code)
                classNames[code] = name
                classOwners[code] = uid
            }
        }
        
        return code
    }
    
    // MARK: - New Course-Based Class Creation
    
    struct ClassCreationConfiguration {
        let name: String
        let commonSubjects: [String] // "Mathe", "Deutsch"
        let branches: [BranchConfig]
        
        struct BranchConfig {
            let name: String // "Sozial"
            let subjects: [String] // "Pädagogik"
        }
    }
    
    func createClassWithCourses(config: ClassCreationConfiguration) async throws -> String {
         guard let uid = Auth.auth().currentUser?.uid else {
             throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
         }
         
         let batch = db.batch()
         
         // 1. Create Class
         let code = generateExamGroupCode()
         let classRef = db.collection("classes").document(code)
         
         // Serialize configuration for future reference?
         let branchData = config.branches.map { ["name": $0.name, "id": $0.name] } // Simple ID = name
         
         let classPayload: [String: Any] = [
             "name": config.name,
             "ownerId": uid,
             "createdAt": Date(),
             "courseConfiguration": [
                "branches": branchData
             ],
             "groupIds": [] // Legacy compat
         ]
         batch.setData(classPayload, forDocument: classRef)
         
         // Add creator as member
         let memberRef = classRef.collection("members").document(uid)
         batch.setData(["joinedAt": Date()], forDocument: memberRef)
         
         // Link to user profile
         let yearRef = try await requireYearRef(uid: uid)
         batch.updateData(["classIds": FieldValue.arrayUnion([code])], forDocument: yearRef)
         
         // 2. Create Common Courses
         for subject in config.commonSubjects {
             let courseRef = db.collection("courses").document()
             let course = Course(
                 id: courseRef.documentID,
                 name: subject,
                 subjectKey: slugifySubjectName(subject),
                 classId: code,
                 type: .mandatory,
                 ownerId: uid,
                 joinCode: nil, // Generate if needed
                 createdAt: Date()
             )
             try batch.setData(from: course, forDocument: courseRef)
         }
         
         // 3. Create Branch Courses
         for branch in config.branches {
             for subject in branch.subjects {
                 let courseRef = db.collection("courses").document()
                 let course = Course(
                     id: courseRef.documentID,
                     name: subject,
                     subjectKey: slugifySubjectName(subject),
                     classId: code,
                     type: .branch(branch.name),
                     ownerId: uid,
                     joinCode: nil,
                     createdAt: Date()
                 )
                 try batch.setData(from: course, forDocument: courseRef)
             }
         }
         
         try await batch.commit()
         
         // Local update
         await MainActor.run {
            if !classIds.contains(code) {
                classIds.append(code)
                classNames[code] = config.name
                classOwners[code] = uid
            }
         }
         
         return code
    }
    
    func joinClass(with rawCode: String) async throws {
        // Legacy simple join without branch selection
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let code = normalizedExamGroupCode(rawCode)
        guard !code.isEmpty else { return }
        
        let classRef = db.collection("classes").document(code)
        let doc = try await classRef.getDocument()
        guard doc.exists else {
             throw NSError(domain: "GradesStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Diese Klasse existiert nicht."])
        }
        
        try await classRef.collection("members").document(uid).setData([
            "joinedAt": Date()
        ])
        
        let yearRef = try await requireYearRef(uid: uid)
        try await yearRef.setData([
             "classIds": FieldValue.arrayUnion([code])
         ], merge: true)
        
        await MainActor.run {
             if !classIds.contains(code) {
                 classIds.append(code)
                 classNames[code] = doc.data()?["name"] as? String ?? "Unbenannte Klasse"
             }
         }
    }
    
    func joinClassWithBranch(classId: String, selectedCourses: [Course]) async throws {
         guard let uid = Auth.auth().currentUser?.uid else { return }
         
         let batch = db.batch()
         
         // 1. Add to Class Members
         let classRef = db.collection("classes").document(classId)
         let memberRef = classRef.collection("members").document(uid)
         batch.setData(["joinedAt": Date()], forDocument: memberRef)
         
         // 2. Update User Profile with Class Assignment
         // We store classIds in schoolYear usually, but subscriptions are top-level for now per logic.
         let yearRef = try await requireYearRef(uid: uid)
         batch.updateData(["classIds": FieldValue.arrayUnion([classId])], forDocument: yearRef)
         
         let userRef = db.collection("users").document(uid)
         // Assuming single active class for simplicity, or just update the list.
         // Also update subscriptions
         let courseIds = selectedCourses.map { $0.id }
         if !courseIds.isEmpty {
             batch.updateData([
                "subscribedCourseIds": FieldValue.arrayUnion(courseIds),
                "activeClassId": classId // Set as primary/active
             ], forDocument: userRef)
         } else {
             batch.updateData(["activeClassId": classId], forDocument: userRef)
         }
         
         try await batch.commit()
         
         // Local update handled by listeners
    }
    
    func fetchClassInfo(with rawCode: String) async throws -> (id: String, name: String, config: ClassConfiguration?) {
        guard Auth.auth().currentUser != nil else {
             throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let code = normalizedExamGroupCode(rawCode)
        guard !code.isEmpty else {
             throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Leerer Code"])
        }
        
        let classRef = db.collection("classes").document(code)
        let doc = try await classRef.getDocument()
        guard doc.exists, let data = doc.data() else {
             throw NSError(domain: "GradesStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Diese Klasse existiert nicht."])
        }
        
        let name = data["name"] as? String ?? "Unbenannte Klasse"
        
        var config: ClassConfiguration? = nil
        if let configData = data["courseConfiguration"] as? [String: Any] {
            // Manual decoding or JSON serialization
            if let jsonData = try? JSONSerialization.data(withJSONObject: configData),
               let decoded = try? JSONDecoder().decode(ClassConfiguration.self, from: jsonData) {
                config = decoded
            }
        }
        
        return (code, name, config)
    }
    
    func fetchCoursesForClass(classId: String) async throws -> [Course] {
        let snapshot = try await db.collection("courses")
            .whereField("classId", isEqualTo: classId)
            .getDocuments()
            
        return snapshot.documents.compactMap { try? $0.data(as: Course.self) }
    }
    
    func leaveClass(code: String) async {
         guard let uid = Auth.auth().currentUser?.uid else { return }
         
         // 1. Remove from SchoolYear (Legacy/List tracking)
         if let yearRef = try? await requireYearRef(uid: uid) {
             try? await yearRef.updateData([
                 "classIds": FieldValue.arrayRemove([code])
             ])
         }
         
         // 2. Remove from Class Members
         try? await db.collection("classes").document(code).collection("members").document(uid).delete()
         
         // 3. Cleanup UserProfile (Active Class & Course Subscriptions)
         let userRef = db.collection("users").document(uid)
         
         // Fetch courses of this class to unsubscribe
         if let coursesRequest = try? await db.collection("courses").whereField("classId", isEqualTo: code).getDocuments() {
             let courseIdsToRemove = coursesRequest.documents.map { $0.documentID }
             if !courseIdsToRemove.isEmpty {
                 try? await userRef.updateData([
                     "subscribedCourseIds": FieldValue.arrayRemove(courseIdsToRemove)
                 ])
             }
         }
         
         // Unset activeClassId if it matches
         // Unset activeClassId if it matches (Simulated transaction via optimistic fetch)
         if let userDoc = try? await userRef.getDocument(),
            let currentActive = userDoc.data()?["activeClassId"] as? String,
            currentActive == code {
             try? await userRef.updateData(["activeClassId": FieldValue.delete()])
         }

         await MainActor.run {
             classIds.removeAll { $0 == code }
             classNames.removeValue(forKey: code)
             classDetails.removeValue(forKey: code)
             // Clean up subscribedCourseIds local state implicitly via listener or refresh
             // But strictly speaking we should remove them from `subscribedCourseIds` locally too if not waiting for listener
         }
    }

    func deleteClass(code: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let classRef = db.collection("classes").document(code)
        let doc = try await classRef.getDocument()
        guard let owner = doc.data()?["ownerId"] as? String, owner == uid else {
            throw NSError(domain: "GradesStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Nur der Ersteller kann die Klasse löschen."])
        }
        
        // 1. Find and restore groups that were migrated to this class
        let migratedGroupsSnapshot = try await db.collection("groups")
            .whereField("migratedToClassId", isEqualTo: code)
            .getDocuments()
        
        for groupDoc in migratedGroupsSnapshot.documents {
            // Clear the migration marker so the group shows up again
            try? await groupDoc.reference.updateData([
                "migratedToClassId": FieldValue.delete(),
                "migratedAt": FieldValue.delete()
            ])
            
            // Remove from local migratedGroupIds
            await MainActor.run {
                _ = migratedGroupIds.remove(groupDoc.documentID)
            }
        }
        
        // 2. Delete all Courses associated with this class
        let coursesSnapshot = try await db.collection("courses").whereField("classId", isEqualTo: code).getDocuments()
        let batch = db.batch()
        
        for courseDoc in coursesSnapshot.documents {
            batch.deleteDocument(courseDoc.reference)
            // Note: We are strictly supposed to delete subcollections (exams/homeworks) manually in Firestore!
            // But usually for prototype/small apps we rely on them becoming orphaned or client-side cleanup.
            // For rigorous implementation, we should fetch and delete subcollections of courses too.
            // We'll trust that listeners handle "missing parent" gracefully or we implement cloud function recursive delete later.
        }
        
        // 3. Delete Class Document
        batch.deleteDocument(classRef)
        
        try await batch.commit()
        
        // 4. Local Cleanup
        // Also perform "leave" logic for self to clean up user profile
        await leaveClass(code: code)
    }
    
    func addGroupToClass(classId: String, groupId: String) async throws {
         guard let uid = Auth.auth().currentUser?.uid else { return }
         
         // Allow any member to add
         let memDoc = try? await db.collection("classes").document(classId).collection("members").document(uid).getDocument()
         if memDoc?.exists != true {
             // Fallback: check owner
            let doc = try await db.collection("classes").document(classId).getDocument()
            let owner = doc.data()?["ownerId"] as? String
            if owner != uid {
                throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nur Mitglieder können Gruppen hinzufügen."])
            }
         }
         
         // Prevent adding a group that's already in any class
         let allClassGroupIds = Set(classDetails.values.flatMap { $0.groupIds })
         if allClassGroupIds.contains(groupId) {
             throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Diese Gruppe ist bereits einer Klasse zugeordnet."])
         }
         
         try await db.collection("classes").document(classId).updateData([
             "groupIds": FieldValue.arrayUnion([groupId])
         ])
         
         await fetchClassDetails(classId: classId)
    }
    
    func migrateGroupToClass(groupId: String) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { 
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) 
        }
        
        // 1. Fetch Group Details
        let groupRef = db.collection("groups").document(groupId)
        let groupDoc = try await groupRef.getDocument()
        guard let groupData = groupDoc.data(),
              let groupName = groupData["name"] as? String else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gruppe nicht gefunden"])
        }
        
        // 2. Check Ownership
        if let owner = groupData["ownerId"] as? String, owner != uid {
             throw NSError(domain: "GradesStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Nur der Ersteller kann die Gruppe in eine Klasse umwandeln."])
        }
        
        // 3. Fetch Subjects
        let subjectsSnapshot = try await groupRef.collection("subjects").getDocuments()
        let subjectDocs = subjectsSnapshot.documents
        let subjects = subjectDocs.compactMap { $0.data()["name"] as? String }
        
        guard !subjects.isEmpty else {
             throw NSError(domain: "GradesStore", code: -5, userInfo: [NSLocalizedDescriptionKey: "Die Gruppe hat keine Fächer."])
        }

        // 4. Create Class (this also creates Courses for each subject)
        let config = ClassCreationConfiguration(
            name: groupName,
            commonSubjects: subjects,
            branches: []
        )
        
        let newClassId = try await createClassWithCourses(config: config)
        
        // 5. Get newly created Courses for this class (to map subjects -> courseIds)
        let newCourses = try await fetchCoursesForClass(classId: newClassId)
        var subjectToCourseId: [String: String] = [:]
        for course in newCourses {
            subjectToCourseId[course.name.lowercased()] = course.id
        }
        
        // 6. Migrate Exams from legacy examGroups collection
        let examGroupRef = db.collection("examGroups").document(groupId)
        let examsSnapshot = try? await examGroupRef.collection("exams").getDocuments()
        
        if let exams = examsSnapshot?.documents {
            for examDoc in exams {
                let data = examDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                
                // Find matching course
                if let targetCourseId = subjectToCourseId[subjectName] {
                    // Copy exam to course
                    var newExamData = data
                    newExamData["migratedFromGroup"] = groupId
                    try? await db.collection("courses").document(targetCourseId).collection("exams").document(examDoc.documentID).setData(newExamData)
                }
            }
        }
        
        // 7. Migrate Homeworks from legacy homeworkGroups collection
        let homeworkGroupRef = db.collection("homeworkGroups").document(groupId)
        let homeworksSnapshot = try? await homeworkGroupRef.collection("homeworks").getDocuments()
        
        if let homeworks = homeworksSnapshot?.documents {
            for hwDoc in homeworks {
                let data = hwDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                
                // Find matching course
                if let targetCourseId = subjectToCourseId[subjectName] {
                    // Copy homework to course
                    var newHwData = data
                    newHwData["migratedFromGroup"] = groupId
                    try? await db.collection("courses").document(targetCourseId).collection("homeworks").document(hwDoc.documentID).setData(newHwData)
                }
            }
        }
        
        // 8. Also try groups/{id}/exams and groups/{id}/homeworks as fallback
        let groupExamsSnapshot = try? await groupRef.collection("exams").getDocuments()
        if let exams = groupExamsSnapshot?.documents {
            for examDoc in exams {
                let data = examDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                if let targetCourseId = subjectToCourseId[subjectName] {
                    var newExamData = data
                    newExamData["migratedFromGroup"] = groupId
                    try? await db.collection("courses").document(targetCourseId).collection("exams").document(examDoc.documentID).setData(newExamData, merge: true)
                }
            }
        }
        
        let groupHomeworksSnapshot = try? await groupRef.collection("homeworks").getDocuments()
        if let homeworks = groupHomeworksSnapshot?.documents {
            for hwDoc in homeworks {
                let data = hwDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                if let targetCourseId = subjectToCourseId[subjectName] {
                    var newHwData = data
                    newHwData["migratedFromGroup"] = groupId
                    try? await db.collection("courses").document(targetCourseId).collection("homeworks").document(hwDoc.documentID).setData(newHwData, merge: true)
                }
            }
        }
        
        // 9. Mark Group as Migrated (so it doesn't show in updated app versions)
        try await groupRef.updateData([
            "migratedToClassId": newClassId,
            "migratedToBranchName": "", // Empty string indicates single-group conversion (no branch suffix)
            "migratedAt": Date()
        ])
        
        // 10. Subscribe owner to all migrated courses
        let newCourseIds = newCourses.map { $0.id }
        let userRef = db.collection("users").document(uid)
        try await userRef.updateData([
            "subscribedCourseIds": FieldValue.arrayUnion(newCourseIds)
        ])
        
        // 10b. Migrate other group members (Legacy + Current)
        try await migrateMembersFromGroupToClass(groupId: groupId, toClassId: newClassId, courseIds: newCourseIds)
        
        // 11. Local Cleanup: Mark as migrated immediately
        await MainActor.run {
            // Keep in groupIds so listeners continue (for context resolution)
            migratedGroupIds.insert(groupId)
            subscribedCourseIds.append(contentsOf: newCourseIds)
        }
        
        return newClassId
    }
    
    /// Merges multiple legacy groups into a single new Class, with each group becoming a branch.
    /// - Parameter className: The name of the new class.
    /// - Parameter groups: Array of tuples containing (groupId, branchName).
    /// - Returns: The new Class ID.
    func mergeGroupsIntoClass(className: String, groups: [(groupId: String, branchName: String)]) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        guard !groups.isEmpty else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Keine Gruppen ausgewählt"])
        }
        
        // 1. Create the Class document
        let classCode = generateExamGroupCode()
        let classRef = db.collection("classes").document(classCode)
        
        // Build branches configuration
        var branchConfigs: [ClassConfiguration.Branch] = []
        for group in groups {
            branchConfigs.append(ClassConfiguration.Branch(name: group.branchName))
        }
        
        let config = ClassConfiguration(branches: branchConfigs)
        
        try await classRef.setData([
            "ownerId": uid,
            "createdAt": Date(),
            "name": className,
            "config": try Firestore.Encoder().encode(config)
        ])
        
        // Add owner as member
        try await classRef.collection("members").document(uid).setData([
            "joinedAt": Date(),
            "role": "owner"
        ])
        
        // Add to user's year
        if let yearRef = try? await requireYearRef(uid: uid) {
            try await yearRef.updateData([
                "classIds": FieldValue.arrayUnion([classCode])
            ])
        }
        
        // 2. For each group, create courses and migrate data
        var allCourseIds: [String] = []
        
        for group in groups {
            let groupRef = db.collection("groups").document(group.groupId)
            let groupDoc = try await groupRef.getDocument()
            
            guard groupDoc.exists else { continue }
            
            // Fetch subjects from the group
            let subjectsSnapshot = try await groupRef.collection("subjects").getDocuments()
            let subjects = subjectsSnapshot.documents.compactMap { $0.data()["name"] as? String }
            
            // Create courses for each subject (tagged with branch)
            var subjectToCourseId: [String: String] = [:]
            var branchCourseIds: [String] = []
            
            for subjectName in subjects {
                let courseRef = db.collection("courses").document()
                let course = Course(
                    id: courseRef.documentID,
                    name: subjectName,
                    subjectKey: slugifySubjectName(subjectName),
                    classId: classCode,
                    type: .branch(group.branchName),
                    ownerId: uid,
                    joinCode: nil,
                    createdAt: Date()
                )
                try courseRef.setData(from: course)
                subjectToCourseId[subjectName.lowercased()] = courseRef.documentID
                allCourseIds.append(courseRef.documentID)
                branchCourseIds.append(courseRef.documentID)
            }
            
            // Migrate exams from examGroups
            let examGroupRef = db.collection("examGroups").document(group.groupId)
            if let exams = try? await examGroupRef.collection("exams").getDocuments().documents {
                for examDoc in exams {
                    let data = examDoc.data()
                    let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                    if let targetCourseId = subjectToCourseId[subjectName] {
                        var newData = data
                        newData["migratedFromGroup"] = group.groupId
                        try? await db.collection("courses").document(targetCourseId).collection("exams").document(examDoc.documentID).setData(newData)
                    }
                }
            }
            
            // Migrate homeworks from homeworkGroups
            let homeworkGroupRef = db.collection("homeworkGroups").document(group.groupId)
            if let homeworks = try? await homeworkGroupRef.collection("homeworks").getDocuments().documents {
                for hwDoc in homeworks {
                    let data = hwDoc.data()
                    let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                    if let targetCourseId = subjectToCourseId[subjectName] {
                        var newData = data
                        newData["migratedFromGroup"] = group.groupId
                        try? await db.collection("courses").document(targetCourseId).collection("homeworks").document(hwDoc.documentID).setData(newData)
                    }
                }
            }
            
            // Also try groups/{id}/exams and groups/{id}/homeworks
            if let exams = try? await groupRef.collection("exams").getDocuments().documents {
                for examDoc in exams {
                    let data = examDoc.data()
                    let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                    if let targetCourseId = subjectToCourseId[subjectName] {
                        var newData = data
                        newData["migratedFromGroup"] = group.groupId
                        try? await db.collection("courses").document(targetCourseId).collection("exams").document(examDoc.documentID).setData(newData, merge: true)
                    }
                }
            }
            
            if let homeworks = try? await groupRef.collection("homeworks").getDocuments().documents {
                for hwDoc in homeworks {
                    let data = hwDoc.data()
                    let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                    if let targetCourseId = subjectToCourseId[subjectName] {
                        var newData = data
                        newData["migratedFromGroup"] = group.groupId
                        try? await db.collection("courses").document(targetCourseId).collection("homeworks").document(hwDoc.documentID).setData(newData, merge: true)
                    }
                }
            }
            
            // Migrate Members (Legacy + Current)
            try await migrateMembersFromGroupToClass(groupId: group.groupId, toClassId: classCode, courseIds: branchCourseIds)
            
            // Mark group as migrated
            try await groupRef.updateData([
                "migratedToClassId": classCode,
                "migratedAt": Date()
            ])
        }
        
        // 3. Subscribe owner to all courses
        let userRef = db.collection("users").document(uid)
        try await userRef.updateData([
            "subscribedCourseIds": FieldValue.arrayUnion(allCourseIds),
            "activeClassId": classCode
        ])
        
        // 4. Local cleanup
        await MainActor.run {
            for group in groups {
                // Keep in groupIds and groupNames so listeners continue (needed for context display)
                migratedGroupIds.insert(group.groupId)
            }
            classIds.append(classCode)
            classNames[classCode] = className
            subscribedCourseIds.append(contentsOf: allCourseIds)
        }
        
        return classCode
    }
    
    /// Adds a legacy group to an existing class as a new branch.
    /// - Parameter classId: The ID of the existing class.
    /// - Parameter groupCode: The code/ID of the legacy group.
    /// - Parameter branchName: The name to use for the new branch.
    func addLegacyGroupToClass(classId: String, groupCode: String, branchName: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        let groupRef = db.collection("groups").document(groupCode)
        let groupDoc = try await groupRef.getDocument()
        
        guard groupDoc.exists else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gruppe nicht gefunden"])
        }
        
        // Fetch subjects from the group
        let subjectsSnapshot = try await groupRef.collection("subjects").getDocuments()
        let subjects = subjectsSnapshot.documents.compactMap { $0.data()["name"] as? String }
        
        guard !subjects.isEmpty else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Gruppe hat keine Fächer"])
        }
        
        // Create courses for each subject
        var subjectToCourseId: [String: String] = [:]
        var newCourseIds: [String] = []
        
        for subjectName in subjects {
            let courseRef = db.collection("courses").document()
            let course = Course(
                id: courseRef.documentID,
                name: subjectName,
                subjectKey: slugifySubjectName(subjectName),
                classId: classId,
                type: .branch(branchName),
                ownerId: uid,
                joinCode: nil,
                createdAt: Date()
            )
            try courseRef.setData(from: course)
            subjectToCourseId[subjectName.lowercased()] = courseRef.documentID
            newCourseIds.append(courseRef.documentID)
        }
        
        // Migrate exams from examGroups collection
        let examGroupRef = db.collection("examGroups").document(groupCode)
        if let exams = try? await examGroupRef.collection("exams").getDocuments().documents {
            for examDoc in exams {
                let data = examDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                if let targetCourseId = subjectToCourseId[subjectName] {
                    var newData = data
                    newData["migratedFromGroup"] = groupCode
                    try? await db.collection("courses").document(targetCourseId).collection("exams").document(examDoc.documentID).setData(newData)
                }
            }
        }
        
        // Also migrate exams from groups/{id}/exams subcollection
        if let exams = try? await groupRef.collection("exams").getDocuments().documents {
            for examDoc in exams {
                let data = examDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                if let targetCourseId = subjectToCourseId[subjectName] {
                    var newData = data
                    newData["migratedFromGroup"] = groupCode
                    try? await db.collection("courses").document(targetCourseId).collection("exams").document(examDoc.documentID).setData(newData, merge: true)
                }
            }
        }
        
        // Migrate homeworks from homeworkGroups collection
        let homeworkGroupRef = db.collection("homeworkGroups").document(groupCode)
        if let homeworks = try? await homeworkGroupRef.collection("homeworks").getDocuments().documents {
            for hwDoc in homeworks {
                let data = hwDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                if let targetCourseId = subjectToCourseId[subjectName] {
                    var newData = data
                    newData["migratedFromGroup"] = groupCode
                    try? await db.collection("courses").document(targetCourseId).collection("homeworks").document(hwDoc.documentID).setData(newData)
                }
            }
        }
        
        // Also migrate homeworks from groups/{id}/homeworks subcollection
        if let homeworks = try? await groupRef.collection("homeworks").getDocuments().documents {
            for hwDoc in homeworks {
                let data = hwDoc.data()
                let subjectName = (data["subjectName"] as? String ?? "").lowercased()
                if let targetCourseId = subjectToCourseId[subjectName] {
                    var newData = data
                    newData["migratedFromGroup"] = groupCode
                    try? await db.collection("courses").document(targetCourseId).collection("homeworks").document(hwDoc.documentID).setData(newData, merge: true)
                }
            }
        }
        
        // Migrate Members (Legacy + Current)
        try await migrateMembersFromGroupToClass(groupId: groupCode, toClassId: classId, courseIds: newCourseIds)

        // Mark group as migrated
        // Mark group as migrated
        try await groupRef.updateData([
            "migratedToClassId": classId,
            "migratedToBranchName": branchName,
            "migratedAt": Date()
        ])
        
        // NOTE: We do NOT auto-subscribe the user to these courses.
        // The user adding the group is just making it available for others.
        // Users can choose to subscribe to these courses separately.
        
        // Update class config to include new branch
        let classRef = db.collection("classes").document(classId)
        let classDoc = try await classRef.getDocument()
        if let data = classDoc.data(),
           let configData = data["config"] as? [String: Any],
           var branches = configData["branches"] as? [[String: Any]] {
            branches.append(["name": branchName])
            try await classRef.updateData([
                "config.branches": branches
            ])
        }
        
        // Local cleanup (just mark the group as migrated, no subscription changes)
        await MainActor.run {
            // Keep in groupIds so listeners continue
            _ = migratedGroupIds.insert(groupCode)
        }
    }
    
    /// Adds multiple groups as branches to an existing class.
    /// This is the batch version for adding multiple groups at once.
    func addGroupsAsBranchesToClass(classId: String, groups: [(groupId: String, branchName: String)]) async throws {
        guard !groups.isEmpty else { return }
        
        for group in groups {
            try await addLegacyGroupToClass(classId: classId, groupCode: group.groupId, branchName: group.branchName)
        }
    }
    
    /// Subscribes the user to all courses in a specific branch.
    func subscribeToBranch(branchCourses: [Course]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let courseIds = branchCourses.map { $0.id }
        guard !courseIds.isEmpty else { return }
        
        let userRef = db.collection("users").document(uid)
        try await userRef.updateData([
            "subscribedCourseIds": FieldValue.arrayUnion(courseIds)
        ])
        
        await MainActor.run {
            for id in courseIds {
                if !subscribedCourseIds.contains(id) {
                    subscribedCourseIds.append(id)
                }
            }
        }
    }
    
    /// Unsubscribes the user from all courses in a specific branch.
    func unsubscribeFromBranch(branchCourses: [Course]) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let courseIds = branchCourses.map { $0.id }
        guard !courseIds.isEmpty else { return }
        
        let userRef = db.collection("users").document(uid)
        try await userRef.updateData([
            "subscribedCourseIds": FieldValue.arrayRemove(courseIds)
        ])
        
        await MainActor.run {
            subscribedCourseIds.removeAll { courseIds.contains($0) }
        }
    }
    
    /// Creates a new branch in an existing class with the specified subjects/courses.
    /// - Parameter classId: The ID of the class.
    /// - Parameter branchName: The name of the new branch.
    /// - Parameter subjects: Array of subject names to create as courses for this branch.
    /// - Returns: Array of created Course IDs.
    func addBranchToClass(classId: String, branchName: String, subjects: [String]) async throws -> [String] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        guard !branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Zweig-Name darf nicht leer sein"])
        }
        
        guard !subjects.isEmpty else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mindestens ein Fach erforderlich"])
        }
        
        // Verify class exists
        let classRef = db.collection("classes").document(classId)
        let classDoc = try await classRef.getDocument()
        guard classDoc.exists else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Klasse nicht gefunden"])
        }
        
        var newCourseIds: [String] = []
        
        // Create courses for each subject
        for subject in subjects {
            let courseRef = db.collection("courses").document()
            let course = Course(
                id: courseRef.documentID,
                name: subject,
                subjectKey: slugifySubjectName(subject),
                classId: classId,
                type: .branch(branchName),
                ownerId: uid,
                joinCode: nil,
                createdAt: Date()
            )
            try courseRef.setData(from: course)
            newCourseIds.append(courseRef.documentID)
        }
        
        // Update class config to include new branch
        if let data = classDoc.data(),
           let configData = data["courseConfiguration"] as? [String: Any],
           var branches = configData["branches"] as? [[String: Any]] {
            // Check if branch already exists
            if !branches.contains(where: { ($0["name"] as? String) == branchName }) {
                branches.append(["name": branchName, "id": branchName])
                try await classRef.updateData([
                    "courseConfiguration.branches": branches
                ])
            }
        } else {
            // Initialize branch config if none exists
            try await classRef.updateData([
                "courseConfiguration.branches": [["name": branchName, "id": branchName]]
            ])
        }
        
        return newCourseIds
    }
    
    /// Adds a new Course to an existing Class.
    func addCourseToClass(classId: String, name: String, type: CourseType) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        // Verify user is owner or member of the class
        let classRef = db.collection("classes").document(classId)
        let classDoc = try await classRef.getDocument()
        guard classDoc.exists else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Klasse nicht gefunden"])
        }
        
        let courseRef = db.collection("courses").document()
        let course = Course(
            id: courseRef.documentID,
            name: name,
            subjectKey: slugifySubjectName(name),
            classId: classId,
            type: type,
            ownerId: uid,
            joinCode: nil,
            createdAt: Date()
        )
        try courseRef.setData(from: course)
    }
    
    /// Deletes a Course. Only the owner can delete.
    func deleteCourse(courseId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        let courseRef = db.collection("courses").document(courseId)
        let doc = try await courseRef.getDocument()
        guard let owner = doc.data()?["ownerId"] as? String, owner == uid else {
            throw NSError(domain: "GradesStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Nur der Ersteller kann diesen Kurs löschen."])
        }
        
        try await courseRef.delete()
    }

    func removeGroupFromClass(classId: String, groupId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // Allow any member to remove
        let memDoc = try? await db.collection("classes").document(classId).collection("members").document(uid).getDocument()
        if memDoc?.exists != true {
            // Fallback: check owner
            let doc = try await db.collection("classes").document(classId).getDocument()
            let owner = doc.data()?["ownerId"] as? String
            if owner != uid {
                throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Nur Mitglieder können Gruppen entfernen."])
            }
        }
        
        try await db.collection("classes").document(classId).updateData([
            "groupIds": FieldValue.arrayRemove([groupId])
        ])
        
        await fetchClassDetails(classId: classId)
    }

    /// Creates a group with a manually specified subject (no local subject required).
    func createManualGroup(groupName: String, subjectName: String, type: Int) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        let code = generateExamGroupCode()
        let yearRef = try await requireYearRef(uid: uid)
        
        // Group Doc
        let groupRef = db.collection("groups").document(code)
        try await groupRef.setData([
            "ownerId": uid,
            "createdAt": Date(),
            "name": groupName,
            "schoolYearId": activeSchoolYearId as Any
        ])
        
        // Members
        try await groupRef.collection("members").document(uid).setData([
            "joinedAt": Date()
        ])
        
        // Subject Sub-doc
        let sid = slugifySubjectName(subjectName)
        let payload: [String: Any] = [
            "name": subjectName,
            "type": type
        ]
        try await groupRef.collection("subjects").document(sid).setData(payload)
        
        // Update User
        try await yearRef.setData([
            "groupIds": FieldValue.arrayUnion([code]),
            "examGroupIds": FieldValue.arrayUnion([code]),
            "homeworkGroupIds": FieldValue.arrayUnion([code]),
            "examGroupId": code,
            "homeworkGroupId": code
        ], merge: true)
        
        // Local Updates
        let union = Array(Set(groupIds + [code]))
        groupIds = union
        examGroupIds = union
        homeworkGroupIds = union
        groupNames[code] = groupName
        groupOwners[code] = uid
        examGroupId = code
        homeworkGroupId = code
        
        // Seed local mapping for creator so they see it correctly
        groupSubjectsByGroup[code] = [GroupSubject(id: sid, name: subjectName, type: type, alias: nil)]
        groupSubjectMappings[code] = [sid: subjectName] // Map sid to name
        try await yearRef.collection("groupMappings").document(code).setData(["map": [sid: subjectName]], merge: true)
        
        updateGroupObservers(uid: uid, schoolYearId: yearRef.documentID)
        
        return code
    }
    
    func fetchClassDetails(classId: String) async {
        guard let doc = try? await db.collection("classes").document(classId).getDocument(),
              let data = doc.data() else { return }
        
        let name = data["name"] as? String ?? ""
        let ownerId = data["ownerId"] as? String ?? ""
        let groupIds = data["groupIds"] as? [String] ?? []
        let createdTs = data["createdAt"] as? Timestamp
        let createdAt = createdTs?.dateValue() ?? Date()
        
        var details = SchoolClass(
            id: classId,
            name: name,
            ownerId: ownerId,
            groupIds: groupIds,
            createdAt: createdAt,
            fetchedGroups: nil,
            memberCount: nil
        )
        
        // Count class members
        let classMembersRef = db.collection("classes").document(classId).collection("members")
        if let agg = try? await classMembersRef.count.getAggregation(source: .server) {
             details.memberCount = Int(truncating: agg.count)
        } else if let snaps = try? await classMembersRef.getDocuments() {
             details.memberCount = snaps.count
        }
        
        if !groupIds.isEmpty {
            var groups: [GroupDetails] = []
            for gid in groupIds {
                // Fetch basic group metadata
                if let gDoc = try? await db.collection("groups").document(gid).getDocument() {
                    let gName = gDoc.data()?["name"] as? String ?? gid
                    
                    // Optimize: Use Count Aggregation
                    var memberCount = 0
                    let membersRef = gDoc.reference.collection("members")
                    if let agg = try? await membersRef.count.getAggregation(source: .server) {
                         memberCount = Int(truncating: agg.count)
                    } else if let snaps = try? await membersRef.getDocuments() {
                         memberCount = snaps.count
                    }
                    
                    var subjectCount = 0
                    let subjectsRef = gDoc.reference.collection("subjects")
                    if let agg = try? await subjectsRef.count.getAggregation(source: .server) {
                         subjectCount = Int(truncating: agg.count)
                    } else if let snaps = try? await subjectsRef.getDocuments() {
                         subjectCount = snaps.count
                    }
                    
                    groups.append(GroupDetails(id: gid, name: gName, memberCount: memberCount, subjectCount: subjectCount))
                }
            }
            details.fetchedGroups = groups
        } else {
            details.fetchedGroups = []
        }
        
        let finalDetails = details
        await MainActor.run {
            self.classDetails[classId] = finalDetails
            self.classNames[classId] = name
            self.classOwners[classId] = ownerId
        }
    }

    func loadUserClasses() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        
        do {
            let snap = try await yearRef.getDocument()
            let cIds = snap.data()?["classIds"] as? [String] ?? []
            
            await MainActor.run {
                self.classIds = cIds
            }
            // Fetch details for each
            for cid in cIds {
                await fetchClassDetails(classId: cid)
            }
        } catch {
            // Optional logging
        }
    }

    func joinExistingSharedGroup(with rawCode: String, allowYearCreation: Bool = true) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let code = normalizedExamGroupCode(rawCode)
        guard !code.isEmpty else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Gruppencode"])
        }

        let groupRef = db.collection("groups").document(code)
        let snap = try await groupRef.getDocument()
        guard snap.exists else {
            throw NSError(domain: "GradesStore", code: -3, userInfo: [NSLocalizedDescriptionKey: "Diese Gruppe existiert nicht."])
        }
        if let groupYear = snap.data()?["schoolYearId"] as? String,
           let currentYear = activeSchoolYearId,
           !groupYear.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           groupYear != currentYear {
            throw NSError(domain: "GradesStore", code: -4, userInfo: [NSLocalizedDescriptionKey: "Diese Gruppe gehört zum Schuljahr \(groupYear) und kann nicht in \(currentYear) beigetreten werden."])
        }

        if onboardingRequired && activeSchoolYearId == nil && !allowYearCreation {
            // Onboarding-Staging: Gruppe nur lokal vormerken, nichts in Firestore anlegen.
            let subjects = await loadGroupSubjectsForImport(groupId: code)
            groupSubjectsByGroup[code] = subjects
            let union = Array(Set(groupIds + [code]))
            groupIds = union
            examGroupIds = union
            homeworkGroupIds = union
            await loadGroupName(gid: code)
            return
        }

        let yearRef = try await requireYearRef(uid: uid)
        try await yearRef.setData([
            "groupIds": FieldValue.arrayUnion([code]),
            "examGroupIds": FieldValue.arrayUnion([code]),
            "homeworkGroupIds": FieldValue.arrayUnion([code]),
            "examGroupId": code,
            "homeworkGroupId": code
        ], merge: true)

        try await groupRef.collection("members").document(uid).setData([
            "joinedAt": Date()
        ])

        let union = Array(Set(groupIds + [code]))
        groupIds = union
        examGroupIds = union
        homeworkGroupIds = union
        examGroupId = code
        homeworkGroupId = code

        updateGroupObservers(uid: uid, schoolYearId: activeSchoolYearId)
        await loadGroupName(gid: code)
    }

    func joinExamGroup(with rawCode: String) async throws {
        try await joinSharedGroup(with: rawCode)
    }
    
    func joinHomeworkGroup(with rawCode: String) async throws {
        try await joinSharedGroup(with: rawCode)
    }

    func leaveExamGroup() async {
        await leaveSharedGroup()
    }
    
    func setActiveExamGroup(_ code: String) async {
        await setActiveSharedGroup(code)
    }

    func loadExamGroupName() async {
        guard let gid = examGroupId else { examGroupName = nil; return }
        do {
            let snap = try await db.collection("groups").document(gid).getDocument()
            examGroupName = snap.data()?["name"] as? String
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            examGroupName = nil
        }
    }

    func leaveHomeworkGroup() async {
        await leaveSharedGroup()
    }

    func leaveSharedGroup(code: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let target = code ?? examGroupId ?? homeworkGroupId
        guard let target else { return }
        do {
            try await yearRef.updateData([
                "groupIds": FieldValue.arrayRemove([target]),
                "examGroupIds": FieldValue.arrayRemove([target]),
                "homeworkGroupIds": FieldValue.arrayRemove([target])
            ])
            
            try await db.collection("groups").document(target).collection("members").document(uid).delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }

        examGroupIds.removeAll { $0 == target }
        homeworkGroupIds.removeAll { $0 == target }
        groupIds.removeAll { $0 == target }

        let remaining = Array(Set(groupIds))
        let newActive = remaining.first

        if let newActive {
            do {
                try await yearRef.updateData([
                    "examGroupId": newActive,
                    "homeworkGroupId": newActive
                ])
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
            examGroupId = newActive
            homeworkGroupId = newActive
        } else {
            do {
                try await yearRef.updateData([
                    "examGroupId": FieldValue.delete(),
                    "homeworkGroupId": FieldValue.delete()
                ])
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
            examGroupId = nil
            homeworkGroupId = nil
        }

        // Listener und State zurücksetzen/neu aufbauen
        // Neue Listener bereinigen/erneuern
        if let l = groupExamsListeners[target] { l.remove(); groupExamsListeners.removeValue(forKey: target) }
        if let l = groupHomeworksListeners[target] { l.remove(); groupHomeworksListeners.removeValue(forKey: target) }
        if let l = groupSubjectsListeners[target] { l.remove(); groupSubjectsListeners.removeValue(forKey: target) }
        if let l = groupMappingsListeners[target] { l.remove(); groupMappingsListeners.removeValue(forKey: target) }
        if let l = groupNameListeners[target] { l.remove(); groupNameListeners.removeValue(forKey: target) }
        groupExamsByGroup.removeValue(forKey: target)
        groupHomeworksByGroup.removeValue(forKey: target)
        groupSubjectsByGroup.removeValue(forKey: target)
        groupSubjectMappings.removeValue(forKey: target)
        groupNames.removeValue(forKey: target)
        groupOwners.removeValue(forKey: target)

        updateGroupObservers(uid: uid, schoolYearId: activeSchoolYearId)

        rescheduleLocalNotifications()
    }

    func setActiveHomeworkGroup(_ code: String) async {
        await setActiveSharedGroup(code)
    }

    func setActiveSharedGroup(_ code: String) async {
        guard !code.isEmpty else { return }
        let union = Array(Set(examGroupIds + homeworkGroupIds + [code]))
        examGroupIds = union
        homeworkGroupIds = union
        if let uid = Auth.auth().currentUser?.uid {
            do {
                let yearRef = try await requireYearRef(uid: uid)
                try await yearRef.updateData([
                    "examGroupId": code,
                    "homeworkGroupId": code
                ])
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
            examGroupId = code
            homeworkGroupId = code
            updateSharedExamsListenerIfNeeded()
            updateSharedHomeworksListenerIfNeeded()
            updateExamGroupSubjectsListenerIfNeeded(forceReload: true)
            updateHomeworkGroupSubjectsListenerIfNeeded(forceReload: true)
            updateExamSubjectMappingListenerIfNeeded(uid: uid, forceReload: true)
            updateHomeworkSubjectMappingListenerIfNeeded(uid: uid, forceReload: true)
            await loadExamGroupName()
            await loadHomeworkGroupName()
        } else {
            examGroupId = code
            homeworkGroupId = code
            updateSharedExamsListenerIfNeeded()
            updateSharedHomeworksListenerIfNeeded()
            updateExamGroupSubjectsListenerIfNeeded(forceReload: true)
            updateHomeworkGroupSubjectsListenerIfNeeded(forceReload: true)
        }
    }

    func loadHomeworkGroupName() async {
        guard let gid = homeworkGroupId else { homeworkGroupName = nil; return }
        do {
            let snap = try await db.collection("groups").document(gid).getDocument()
            homeworkGroupName = snap.data()?["name"] as? String
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            homeworkGroupName = nil
        }
    }

    func loadGroupName(gid: String) async {
        do {
            let snap = try await db.collection("groups").document(gid).getDocument()
            if let name = snap.data()?["name"] as? String {
                await MainActor.run { groupNames[gid] = name }
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func groupMetadata(for code: String) async -> (exists: Bool, schoolYearId: String?) {
        do {
            let snap = try await db.collection("groups").document(code).getDocument()
            let year = snap.data()?["schoolYearId"] as? String
            return (snap.exists, year)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return (false, nil)
        }
    }

    // MARK: - Write

    func addSubjectToFirestore(name: String, type: Int, date: Date, isElective: Bool = false) async throws {
        let lower = name.lowercased()
        if ["sport", "musik"].contains(lower) && !isElective {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Bitte markiere Sport oder Musik als nicht einbringbar."])
        }
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        let yearRef = try await requireYearRef(uid: uid)
        let docRef = yearRef.collection("subjects").document(name)
        try await docRef.setData([
            "type": type,
            "date": date,
            "isElective": isElective
        ], merge: true)

        // Lokalen State optional optimistisch aktualisieren (Listener korrigiert ggf.)
        let s = Subject(name: name, type: type, date: date, isElective: isElective)
        if !subjects.contains(where: { $0.name == name }) {
            subjects.append(s)
        } else {
            subjects = subjects.map { $0.name == name ? s : $0 }
        }
    }

    func importSubjectsFromGroups(groupIds: [String]? = nil, allowedNames: Set<String>? = nil) async -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { return 0 }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return 0 }

        let targets = groupIds ?? self.groupIds
        guard !targets.isEmpty else { return 0 }

        let allowedLower: Set<String>? = allowedNames?.reduce(into: Set<String>()) { partialResult, name in
            partialResult.insert(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        var imported = 0
        var existingNames = Set(subjects.map { $0.name })
        let now = Date()
        var pendingMappings: [String: [String: String]] = [:]

        for gid in targets {
            let groupSubjects = await loadGroupSubjectsForImport(groupId: gid)
            for gs in groupSubjects {
                let trimmedName = gs.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else { continue }
                let lower = trimmedName.lowercased()
                if let allowedLower, !allowedLower.contains(lower) { continue }

                // Immer Mapping vorbereiten (auch wenn Fach bereits existiert)
                var map = pendingMappings[gid] ?? groupSubjectMappings[gid] ?? [:]
                map[gs.id] = trimmedName
                pendingMappings[gid] = map

                if existingNames.contains(trimmedName) { continue }

                let elective = ["sport", "musik"].contains(lower)
                let type = gs.type ?? (elective ? 0 : 1)

                var payload: [String: Any] = [
                    "type": type,
                    "date": now,
                    "isElective": elective
                ]
                if let alias = gs.alias, !alias.isEmpty {
                    payload["alias"] = alias
                }

                do {
                    try await yearRef.collection("subjects").document(trimmedName).setData(payload, merge: true)
                    existingNames.insert(trimmedName)
                    imported += 1

                    // Optimistisch lokal (Listener korrigiert)
                    let newSubject = Subject(
                        name: trimmedName,
                        type: type,
                        date: now,
                        teacher: nil,
                        room: nil,
                        email: nil,
                        alias: gs.alias,
                        droppedHalfYear: nil,
                        examSubject: nil,
                        examType: nil,
                        examPointsEncrypted: nil,
                        writtenExamPointsEncrypted: nil,
                        oralExamPointsEncrypted: nil,
                        isElective: elective
                    )
                    if !subjects.contains(where: { $0.name == trimmedName }) {
                        subjects.append(newSubject)
                    } else {
                        subjects = subjects.map { $0.name == trimmedName ? newSubject : $0 }
                    }
                } catch {
                    ErrorLoggingService.logErrorIfEnabled(error)
                    // optional loggen
                    continue
                }
            }
        }

        // Persistiere neue Mappings pro Gruppe
        for (gid, map) in pendingMappings {
            do {
                try await yearRef.collection("groupMappings").document(gid).setData(["map": map], merge: true)
                await MainActor.run {
                    self.groupSubjectMappings[gid] = map
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
        }

        return imported
    }

    func loadSchoolYearSnapshot(schoolYearId: String) async -> SchoolYearSnapshot? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        guard let key = encryptionKey else { return nil }

        if let cached = schoolYearSnapshotCache[schoolYearId] {
            return cached
        }

        let yearRef = schoolYearRef(uid: uid, id: schoolYearId)
        do {
            let yearDoc = try await yearRef.getDocument()
            let yearData = yearDoc.data() ?? [:]
            let gradeYear = yearData["gradeYear"] as? Int
            let schoolTypeRaw = yearData["schoolType"] as? String
            let schoolType = schoolTypeRaw.flatMap { SchoolType(rawValue: $0) }

            let subjectsSnap = try await yearRef.collection("subjects").getDocuments()
            var subjects: [Subject] = []
            var gradesBySubject: [String: [GradeWithId]] = [:]
            subjects.reserveCapacity(subjectsSnap.documents.count)

            for sdoc in subjectsSnap.documents {
                let data = sdoc.data()
                let name = sdoc.documentID
                let type = data["type"] as? Int ?? 0
                let ts = data["date"] as? Timestamp
                let date = ts?.dateValue() ?? Date()
                let order = data["order"] as? Int
                let teacher = data["teacher"] as? String
                let room = data["room"] as? String
                let email = data["email"] as? String
                let alias = data["alias"] as? String
                let dropped = data["droppedHalfYear"] as? Int
                let examSubject = data["examSubject"] as? Bool
                let examTypeStr = data["examType"] as? String
                let examType = examTypeStr.flatMap { ExamType(rawValue: $0) }
                let examPointsEncrypted = data["examPointsEncrypted"] as? String
                let writtenExamPointsEncrypted = data["writtenExamPointsEncrypted"] as? String
                let oralExamPointsEncrypted = data["oralExamPointsEncrypted"] as? String
                let isElective = data["isElective"] as? Bool ?? false

                let subject = Subject(
                    name: name,
                    type: type,
                    date: date,
                    order: order,
                    teacher: teacher,
                    room: room,
                    email: email,
                    alias: alias,
                    droppedHalfYear: dropped,
                    examSubject: examSubject,
                    examType: examType,
                    examPointsEncrypted: examPointsEncrypted,
                    writtenExamPointsEncrypted: writtenExamPointsEncrypted,
                    oralExamPointsEncrypted: oralExamPointsEncrypted,
                    isElective: isElective
                )
                subjects.append(subject)

                let gradesSnap = try await sdoc.reference.collection("grades").getDocuments()
                var grades: [GradeWithId] = []
                grades.reserveCapacity(gradesSnap.documents.count)
                for gdoc in gradesSnap.documents {
                    let gd = gdoc.data()
                    guard let gradeStr = gd["grade"] as? String else { continue }
                    guard let decrypted = try? CryptoService.decryptString(gradeStr, key: key),
                          let value = Double(decrypted),
                          value.isFinite else { continue }
                    let weight = (gd["weight"] as? NSNumber)?.doubleValue ?? 1.0
                    let ts = gd["date"] as? Timestamp
                    let date = ts?.dateValue() ?? Date()
                    let note = gd["note"] as? String
                    let halfYear = gd["halfYear"] as? Int
                    let linkedExamId = gd["linkedExamId"] as? String
                    grades.append(
                        GradeWithId(
                            id: gdoc.documentID,
                            grade: value,
                            weight: weight,
                            date: date,
                            note: note,
                            halfYear: halfYear,
                            linkedExamId: linkedExamId
                        )
                    )
                }
                gradesBySubject[name] = grades
            }

            var practical: PracticalPerformance? = nil
            var seminar: SeminarPerformance? = nil
            do {
                let snap = try await yearRef.collection("practicalPerformance").document("current").getDocument()
                if snap.exists, let data = snap.data() {
                    practical = decodePracticalPerformance(data: data, key: key)
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }

            do {
                let snap = try await yearRef.collection("seminar").document("current").getDocument()
                if snap.exists, let data = snap.data() {
                    seminar = decodeSeminarPerformance(data: data, key: key)
                }
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }

            let snapshot = SchoolYearSnapshot(
                id: schoolYearId,
                gradeYear: gradeYear,
                schoolType: schoolType,
                subjects: subjects,
                gradesBySubject: gradesBySubject,
                seminarPerformance: seminar,
                practicalPerformance: practical
            )
            schoolYearSnapshotCache[schoolYearId] = snapshot
            return snapshot
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return nil
        }
    }

    func cachedSchoolYearSnapshot(for id: String) -> SchoolYearSnapshot? {
        schoolYearSnapshotCache[id]
    }

    private func preloadPreviousYearSnapshotIfNeeded(currentYearId: String) async {
        guard encryptionKey != nil else { return }
        guard let prevId = previousSchoolYearId(from: currentYearId) else { return }
        guard schoolYearSnapshotCache[prevId] == nil else { return }
        // Nur für FOS 12 relevant (kann per Settings später gesetzt werden)
        if schoolType == .fos, gradeYear == 12 {
            _ = await loadSchoolYearSnapshot(schoolYearId: prevId)
        }
    }

    func loadSubjectsFromSchoolYear(_ sourceYearId: String) async -> [Subject] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        let sourceRef = db.collection("users").document(uid).collection("schoolYears").document(sourceYearId)
        do {
            let snap = try await sourceRef.collection("subjects").getDocuments()
            return snap.documents.compactMap { doc in
                let data = doc.data()
                let name = doc.documentID
                let type = data["type"] as? Int ?? 0
                let ts = data["date"] as? Timestamp
                let date = ts?.dateValue() ?? Date()
                let order = data["order"] as? Int
                let teacher = data["teacher"] as? String
                let room = data["room"] as? String
                let email = data["email"] as? String
                let alias = data["alias"] as? String
                let dropped = data["droppedHalfYear"] as? Int
                let examSubject = data["examSubject"] as? Bool
                let examTypeStr = data["examType"] as? String
                let examType = examTypeStr.flatMap { ExamType(rawValue: $0) }
                let isElective = data["isElective"] as? Bool ?? false
                return Subject(
                    name: name,
                    type: type,
                    date: date,
                    order: order,
                    teacher: teacher,
                    room: room,
                    email: email,
                    alias: alias,
                    droppedHalfYear: dropped,
                    examSubject: examSubject,
                    examType: examType,
                    examPointsEncrypted: nil,
                    writtenExamPointsEncrypted: nil,
                    oralExamPointsEncrypted: nil,
                    isElective: isElective
                )
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return []
        }
    }

    func importSubjectsFromSchoolYear(_ sourceYearId: String, subjectNames: [String]) async -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { return 0 }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return 0 }
        guard !subjectNames.isEmpty else { return 0 }

        let sourceSubjects = await loadSubjectsFromSchoolYear(sourceYearId)
        let map = Dictionary(uniqueKeysWithValues: sourceSubjects.map { ($0.name, $0) })
        var imported = 0
        let now = Date()
        var existing = Set(subjects.map { $0.name })

        for name in subjectNames {
            guard let subj = map[name] else { continue }
            if existing.contains(subj.name) { continue }
            var data: [String: Any] = [
                "type": subj.type,
                "date": subj.date,
                "isElective": subj.isElective,
                "teacher": subj.teacher as Any,
                "room": subj.room as Any,
                "email": subj.email as Any,
                "alias": subj.alias as Any,
                "order": subj.order as Any,
                "examSubject": subj.examSubject as Any,
                "examType": subj.examType?.rawValue as Any
            ]
            data["date"] = data["date"] ?? now
            data["droppedHalfYear"] = nil

            do {
                try await yearRef.collection("subjects").document(subj.name).setData(data, merge: true)
                imported += 1
                existing.insert(subj.name)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                continue
            }
        }
        return imported
    }

    func addExamToFirestore(subjectName: String, subjectKey: String? = nil, title: String, notes: String?, date: Date, hasTime: Bool, weight: Int?, customWeight: Double?, reminderAt: Date?, requiresGrade: Bool? = true) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)
        let now = Date()
        let ref = yearRef
            .collection("exams")
            .document()

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date,
            "hasTime": hasTime,
            "isCompleted": false,
            "createdAt": now,
            "creatorId": uid
        ]
        if let notes { payload["notes"] = notes }
        if let subjectKey { payload["subjectKey"] = subjectKey }
        if let weight {
            payload["weight"] = weight
        }
        if let customWeight {
            payload["customWeight"] = customWeight
        }
        if let reminderAt {
            payload["reminderAt"] = reminderAt
        }
        if let requiresGrade {
            payload["requiresGrade"] = requiresGrade
        }

        try await ref.setData(payload)
    }

    // MARK: - Course-Based Add Methods
    
    func addExamToCourse(courseId: String, title: String, notes: String?, date: Date, hasTime: Bool, weight: Int?, customWeight: Double?, reminderAt: Date?, requiresGrade: Bool? = true) async throws -> String {
         guard let uid = Auth.auth().currentUser?.uid else {
             throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
         }
         let ref = db.collection("courses").document(courseId).collection("exams").document()
         
         // Fetch course to get subject info? Or pass it in?
         // Ideally exams should just store data, but current UI assumes subject info is on the exam or joined.
         // Let's assume the View passes enough info or we fetch course.
         // For now, minimal payload.
         // ACTUALLY: The existing UI expects subjectName/subjectKey on the exam object sometimes.
         // Let's look up the course first to be safe.
         // But that's slow. Let's just store what we have. The view likely knows the subject name.
         // Optimization: Read local courses array.
         let course = courses.first(where: { $0.id == courseId })
         let subjectName = course?.name ?? "Unbekannt"
         let subjectKey = course?.subjectKey
         
         var payload: [String: Any] = [
             "courseId": courseId,
             "subjectName": subjectName,
             "subjectKey": subjectKey ?? slugifySubjectName(subjectName),
             "title": title,
             "date": date,
             "hasTime": hasTime,
             "createdAt": Date(),
             "creatorId": uid
         ]
         if let notes { payload["notes"] = notes }
         if let weight { payload["weight"] = weight }
         if let customWeight { payload["customWeight"] = customWeight }
         if let requiresGrade { payload["requiresGrade"] = requiresGrade }
         
         try await ref.setData(payload)
         return ref.documentID
    }

    // Neue Variante: verteilt automatisch in alle passenden Gruppen (nach Subject-Mapping) oder in die explizit angegebenen Gruppen
    func addExamToGroups(subjectName: String, subjectKey: String? = nil, title: String, notes: String?, date: Date, hasTime: Bool, weight: Int?, customWeight: Double?, reminderAt: Date?, requiresGrade: Bool? = true, targetGroupIds explicitGids: [String]? = nil) async throws -> [(groupId: String, docId: String)] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let gids = explicitGids ?? targetGroupIds(forLocalSubject: subjectName)
        guard !gids.isEmpty else { return [] }

        let now = Date()
        let subjectKey = subjectKey ?? slugifySubjectName(subjectName)
        var created: [(String, String)] = []
        for gid in gids {
            let ref = db.collection("groups").document(gid).collection("exams").document()
            var payload: [String: Any] = [
                "subjectName": subjectName,
                "subjectKey": subjectKey,
                "title": title,
                "date": date,
                "hasTime": hasTime,
                "createdAt": now,
                "creatorId": uid
            ]
            if let notes { payload["notes"] = notes }
            if let weight { payload["weight"] = weight }
            if let customWeight { payload["customWeight"] = customWeight }
            if let requiresGrade { payload["requiresGrade"] = requiresGrade }
            try await ref.setData(payload)
            created.append((gid, ref.documentID))
        }
        return created
    }
    
    func shareExamToGroups(examId: String, targetGroupIds: [String]? = nil) async -> Bool {
        guard let exam = exams.first(where: { $0.id == examId }) else { return false }
        do {
            let created = try await addExamToGroups(
                subjectName: exam.subjectName,
                subjectKey: exam.subjectKey,
                title: exam.title,
                notes: exam.notes,
                date: exam.date,
                hasTime: exam.hasTime,
                weight: exam.weight,
                customWeight: exam.customWeight,
                reminderAt: exam.reminderAt,
                requiresGrade: exam.requiresGrade,
                targetGroupIds: targetGroupIds
            )
            guard !created.isEmpty else { return false }
            await deleteExamFromFirestore(id: examId)
            return true
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return false
        }
    }

    func stopSharingExam(groupId: String, examId: String) async -> Bool {
        await deleteSharedExamFromGroup(groupId: groupId, id: examId)
        return true
    }

    func addHomeworkToFirestore(subjectName: String, title: String, dueDate: Date?, reminderAt: Date?, importedFromShare: Bool = false) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)
        let now = Date()
        let ref = yearRef
            .collection("homeworks")
            .document()

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "isCompleted": false,
            "createdAt": now
        ]
        if let dueDate {
            payload["dueDate"] = dueDate
        }
        if let reminderAt {
            payload["reminderAt"] = reminderAt
        }
        if importedFromShare {
            payload["importedFromShare"] = true
        }

        try await ref.setData(payload)
    }
    
    func addHomeworkToCourse(courseId: String, title: String, dueDate: Date?, reminderAt: Date?) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        
        let ref = db.collection("courses").document(courseId).collection("homeworks").document()
        let course = courses.first(where: { $0.id == courseId })
        let subjectName = course?.name ?? "Unbekannt"
        let subjectKey = course?.subjectKey
        
        var payload: [String: Any] = [
            "courseId": courseId,
            "subjectName": subjectName,
            "subjectKey": subjectKey ?? slugifySubjectName(subjectName),
            "title": title,
            "createdAt": Date(),
            "creatorId": uid
        ]
        if let dueDate { payload["dueDate"] = dueDate }
        if let reminderAt { payload["reminderAt"] = reminderAt }
        
        try await ref.setData(payload)
        return ref.documentID
    }

    func addHomeworkToGroups(subjectName: String, title: String, dueDate: Date?, reminderAt: Date?, targetGroupIds explicitGids: [String]? = nil) async throws -> [(groupId: String, docId: String)] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let gids = explicitGids ?? targetGroupIds(forLocalSubject: subjectName)
        guard !gids.isEmpty else { return [] }
        let now = Date()
        let subjectKey = slugifySubjectName(subjectName)
        var created: [(String, String)] = []

        for gid in gids {
            let ref = db.collection("groups").document(gid).collection("homeworks").document()
            var payload: [String: Any] = [
                "subjectName": subjectName,
                "subjectKey": subjectKey,
                "title": title,
                "createdAt": now,
                "creatorId": uid
            ]
            if let dueDate { payload["dueDate"] = dueDate }
            try await ref.setData(payload)
            created.append((gid, ref.documentID))
        }
        return created
    }

    func shareHomeworkToGroups(homeworkId: String, targetGroupIds: [String]? = nil) async -> Bool {
        guard let hw = homeworks.first(where: { $0.id == homeworkId }) else { return false }
        do {
            let created = try await addHomeworkToGroups(
                subjectName: hw.subjectName,
                title: hw.title,
                dueDate: hw.dueDate,
                reminderAt: hw.reminderAt,
                targetGroupIds: targetGroupIds
            )
            guard !created.isEmpty else { return false }
            await deleteHomeworkFromFirestore(id: homeworkId)
            return true
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return false
        }
    }

    func stopSharingHomework(groupId: String, homeworkId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return false }
        let shared = sharedHomeworks.first { $0.id == homeworkId && $0.groupId == groupId }

        // Lege lokale Kopie an, damit der Ersteller sie behält
        if let hw = shared {
            var payload: [String: Any] = [
                "subjectName": hw.subjectName,
                "title": hw.title,
                "isCompleted": hw.isCompleted,
                "createdAt": hw.createdAt
            ]
            if let due = hw.dueDate { payload["dueDate"] = due }
            if let reminder = hw.reminderAt { payload["reminderAt"] = reminder }
            do {
                try await yearRef.collection("homeworks").document().setData(payload)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen, aber trotzdem Unsharing versuchen
            }
        }

        await deleteSharedHomeworkFromGroup(groupId: groupId, id: homeworkId)
        return true
    }

    func addGeneralHomeworkToGroup(groupId: String, title: String, dueDate: Date?, reminderAt: Date?) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let now = Date()
        let ref = db.collection("groups").document(groupId).collection("homeworks").document()
        var payload: [String: Any] = [
            "subjectName": "Allgemein",
            "title": title,
            "createdAt": now,
            "creatorId": uid
        ]
        payload["subjectKey"] = NSNull()
        if let dueDate { payload["dueDate"] = dueDate }
        try await ref.setData(payload)
        return ref.documentID
    }

    func addGradeToFirestore(
        subjectId: String,
        grade: Double,
        weight: Double,
        date: Date,
        note: String?,
        halfYear: Int?,
        linkedExamId: String?,
        using key: SymmetricKey
    ) async throws -> String {
        let offline = OfflineModeManager.shared.isOfflineModeActive
        let uid = Auth.auth().currentUser?.uid ?? ""

        let newId = UUID().uuidString
        if offline || uid.isEmpty {
            // Offline: lokal hinzufügen und Snapshot + Pending speichern
            let pending = PendingGrade(
                id: newId,
                subjectId: subjectId,
                grade: grade,
                weight: weight,
                date: date,
                note: note,
                halfYear: halfYear,
                linkedExamId: linkedExamId,
                createdAt: Date()
            )
            offlinePendingGrades.append(pending)
            var list = gradesBySubject[subjectId] ?? []
            list.append(
                GradeWithId(
                    id: newId,
                    grade: grade,
                    weight: weight,
                    date: date,
                    note: note,
                    halfYear: halfYear,
                    linkedExamId: linkedExamId
                )
            )
            gradesBySubject[subjectId] = list
            persistOfflineSnapshotIfPossible()
            return newId
        }

        let yearRef = try await requireYearRef(uid: uid)
        let encrypted = try CryptoService.encryptString(String(grade), key: key)
        let gradesRef = yearRef.collection("subjects").document(subjectId).collection("grades")
        let newRef = gradesRef.document(newId)
        var payload: [String: Any] = [
            "grade": encrypted,
            "weight": weight,
            "date": date,
            "note": note as Any,
            "halfYear": halfYear as Any,
            "updatedAt": Date()
        ]
        if let linkedExamId {
            payload["linkedExamId"] = linkedExamId
        }
        try await newRef.setData(payload)

        // Optimistisch lokal (Listener setzt danach korrekt)
        var list = gradesBySubject[subjectId] ?? []
        list.append(
            GradeWithId(
                id: newRef.documentID,
                grade: grade,
                weight: weight,
                date: date,
                note: note,
                halfYear: halfYear,
                linkedExamId: linkedExamId
            )
        )
        gradesBySubject[subjectId] = list
        persistOfflineSnapshotIfPossible()

        return newRef.documentID
    }

    func updateHomeworkInFirestore(id: String, subjectName: String, title: String, dueDate: Date?, reminderAt: Date?, isCompleted: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)
        let ref = yearRef
            .collection("homeworks")
            .document(id)

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "isCompleted": isCompleted
        ]
        if let dueDate {
            payload["dueDate"] = dueDate
        } else {
            payload["dueDate"] = NSNull()
        }
        if let reminderAt {
            payload["reminderAt"] = reminderAt
        } else {
            payload["reminderAt"] = NSNull()
        }

        try await ref.updateData(payload)
    }
    
    func updateSharedHomeworkInGroup(groupId: String, id: String, subjectName: String, title: String, dueDate: Date?) async throws {
        let ref = db.collection("groups").document(groupId).collection("homeworks").document(id)
        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title
        ]
        if let dueDate {
            payload["dueDate"] = dueDate
        } else {
            payload["dueDate"] = NSNull()
        }
        try await ref.updateData(payload)
    }

    func updateExamInFirestore(id: String, subjectName: String, subjectKey: String? = nil, title: String, notes: String?, date: Date, hasTime: Bool, weight: Int?, customWeight: Double?, reminderAt: Date?, isCompleted: Bool, requiresGrade: Bool? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)
        let ref = yearRef
            .collection("exams")
            .document(id)

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date,
            "hasTime": hasTime,
            "isCompleted": isCompleted
        ]
        if let subjectKey {
            payload["subjectKey"] = subjectKey
        } else {
            payload["subjectKey"] = FieldValue.delete()
        }
        if let notes {
            payload["notes"] = notes
        } else {
            payload["notes"] = FieldValue.delete()
        }
        if let weight {
            payload["weight"] = weight
        } else {
            payload["weight"] = NSNull()
        }
        if let customWeight {
            payload["customWeight"] = customWeight
        } else {
            payload["customWeight"] = NSNull()
        }
        if let reminderAt {
            payload["reminderAt"] = reminderAt
        } else {
            payload["reminderAt"] = NSNull()
        }
        if let requiresGrade {
            payload["requiresGrade"] = requiresGrade
        }

        try await ref.updateData(payload)
    }

    func updateSharedExamInGroup(groupId: String, id: String, subjectName: String, subjectKey: String? = nil, title: String, notes: String?, date: Date, hasTime: Bool, weight: Int?, customWeight: Double?, reminderAt: Date?, requiresGrade: Bool? = nil) async throws {
        let ref = db.collection("groups").document(groupId).collection("exams").document(id)

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date,
            "hasTime": hasTime
        ]
        if let subjectKey {
            payload["subjectKey"] = subjectKey
        } else {
            payload["subjectKey"] = FieldValue.delete()
        }
        if let notes {
            payload["notes"] = notes
        } else {
            payload["notes"] = FieldValue.delete()
        }
        if let weight {
            payload["weight"] = weight
        } else {
            payload["weight"] = NSNull()
        }
        if let customWeight {
            payload["customWeight"] = customWeight
        } else {
            payload["customWeight"] = NSNull()
        }
        if let requiresGrade {
            payload["requiresGrade"] = requiresGrade
        }
        try await ref.updateData(payload)
    }

    private func compoundId(gid: String?, docId: String) -> String {
        guard let gid, !gid.isEmpty else { return docId }
        return "\(gid)|\(docId)"
    }

    func setUserReminderForSharedExam(examId: String, reminderAt: Date?, groupId: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)
        let gid = groupId ?? sharedExams.first(where: { $0.id == examId })?.groupId
        let ref = yearRef
            .collection("examGroupReminders")
            .document(compoundId(gid: gid, docId: examId))

        if let reminderAt {
            try await ref.setData([
                "reminderAt": reminderAt
            ])
        } else {
            try await ref.delete()
        }
    }
    
    func setUserNoteForSharedExam(examId: String, note: String?, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let gid = groupId ?? sharedExams.first(where: { $0.id == examId })?.groupId
        let ref = yearRef.collection("examGroupNotes").document(compoundId(gid: gid, docId: examId))
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let text = trimmed, !text.isEmpty {
                try await ref.setData(["note": text])
                sharedExamUserNotes[compoundId(gid: gid, docId: examId)] = text
            } else {
                try await ref.delete()
                sharedExamUserNotes.removeValue(forKey: compoundId(gid: gid, docId: examId))
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }
    
    func setUserCompletedForSharedExam(examId: String, completed: Bool, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let gid = groupId ?? sharedExams.first(where: { $0.id == examId })?.groupId
        let ref = yearRef.collection("examGroupCompleted").document(compoundId(gid: gid, docId: examId))
        do {
            if completed {
                try await ref.setData(["isCompleted": true])
                // Optimistisch lokal aktualisieren
                sharedExamUserCompleted.insert(compoundId(gid: gid, docId: examId))
            } else {
                try await ref.delete()
                sharedExamUserCompleted.remove(compoundId(gid: gid, docId: examId))
            }
            applySharedExamUserCompletion()
            rescheduleLocalNotifications()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }
    
    func setUserRescheduledDateForSharedExam(examId: String, rescheduledDate: Date?, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let gid = groupId ?? sharedExams.first(where: { $0.id == examId })?.groupId
        let key = compoundId(gid: gid, docId: examId)
        let ref = yearRef.collection("examGroupRescheduled").document(key)
        do {
            if let newDate = rescheduledDate {
                try await ref.setData(["rescheduledDate": newDate])
                // Optimistic local update
                sharedExamUserRescheduled[key] = newDate
            } else {
                try await ref.delete()
                sharedExamUserRescheduled.removeValue(forKey: key)
            }
            applySharedExamUserRescheduledDates()
            rescheduleLocalNotifications()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
        }
    }
    
    func setUserReminderForSharedHomework(homeworkId: String, reminderAt: Date?, groupId: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let yearRef = try await requireYearRef(uid: uid)
        let gid = groupId ?? sharedHomeworks.first(where: { $0.id == homeworkId })?.groupId
        let ref = yearRef.collection("homeworkGroupReminders").document(compoundId(gid: gid, docId: homeworkId))
        if let reminderAt {
            try await ref.setData(["reminderAt": reminderAt])
        } else {
            try await ref.delete()
        }
    }

    func setHomeworkCompleted(id: String, completed: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let docRef = yearRef
            .collection("homeworks")
            .document(id)
        do {
            try await docRef.updateData([
                "isCompleted": completed
            ])
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func setUserNoteForSharedHomework(homeworkId: String, note: String?, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let gid = groupId ?? sharedHomeworks.first(where: { $0.id == homeworkId })?.groupId
        let ref = yearRef.collection("homeworkGroupNotes").document(compoundId(gid: gid, docId: homeworkId))
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let text = trimmed, !text.isEmpty {
                try await ref.setData(["note": text])
                sharedHomeworkUserNotes[compoundId(gid: gid, docId: homeworkId)] = text
            } else {
                try await ref.delete()
                sharedHomeworkUserNotes.removeValue(forKey: compoundId(gid: gid, docId: homeworkId))
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }
    
    func setUserCompletedForSharedHomework(homeworkId: String, completed: Bool, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let gid = groupId ?? sharedHomeworks.first(where: { $0.id == homeworkId })?.groupId
        let ref = yearRef.collection("homeworkGroupCompleted").document(compoundId(gid: gid, docId: homeworkId))
        do {
            if completed {
                try await ref.setData(["isCompleted": true])
                // Optimistisch lokal aktualisieren
                sharedHomeworkUserCompleted.insert(compoundId(gid: gid, docId: homeworkId))
            } else {
                try await ref.delete()
                sharedHomeworkUserCompleted.remove(compoundId(gid: gid, docId: homeworkId))
            }
            applySharedHomeworkUserCompletion()
            rescheduleLocalNotifications()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func setExamCompleted(id: String, completed: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let docRef = yearRef
            .collection("exams")
            .document(id)
        do {
            try await docRef.updateData([
                "isCompleted": completed
            ])
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func rescheduleExam(exam: Exam, newDate: Date) async throws {
        if exam.isShared {
            // Shared Exam: Set per-user rescheduled date (doesn't affect other users)
            await setUserRescheduledDateForSharedExam(examId: exam.id, rescheduledDate: newDate, groupId: exam.groupId)
        } else {
            // Private Exam: Just update the date and ensure it's open
            try await updateExamInFirestore(
                id: exam.id,
                subjectName: exam.subjectName,
                subjectKey: exam.subjectKey,
                title: exam.title,
                notes: exam.notes,
                date: newDate, // NEW DATE
                hasTime: exam.hasTime,
                weight: exam.weight,
                customWeight: exam.customWeight,
                reminderAt: nil, // Reset reminder
                isCompleted: false, // Ensure it's open
                requiresGrade: exam.requiresGrade
            )
        }
    }

    func setFachreferatToFirestore(subjectName: String, grade: Double, date: Date, note: String?, using key: SymmetricKey) async throws {
        let offline = OfflineModeManager.shared.isOfflineModeActive
        let uid = Auth.auth().currentUser?.uid ?? ""
        if offline || uid.isEmpty {
            let pending = PendingFachreferat(
                subjectName: subjectName,
                grade: grade,
                date: date,
                note: note,
                createdAt: Date()
            )
            offlinePendingFachreferat = pending
            fachreferat = Fachreferat(id: "current", grade: grade, subjectName: subjectName, date: date, note: note)
            persistOfflineSnapshotIfPossible()
            return
        }

        guard let realUid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let yearRef = try await requireYearRef(uid: realUid)
        let encrypted = try CryptoService.encryptString(String(grade), key: key)
        let docRef = yearRef.collection("fachreferat").document("current")
        try await docRef.setData([
            "grade": encrypted,
            "subjectName": subjectName,
            "date": date,
            "note": note as Any,
            "updatedAt": Date()
        ], merge: true)

        // Optimistisch lokal (Listener setzt danach korrekt)
        fachreferat = Fachreferat(id: "current", grade: grade, subjectName: subjectName, date: date, note: note)
        persistOfflineSnapshotIfPossible()
    }

    func setSeminarPerformance(topic: String?,
                               individualPoints: Double?,
                               paperPoints: Double?,
                               presentationPoints: Double?,
                               submissionDate: Date?,
                               presentationDate: Date?,
                               note: String?,
                               using key: SymmetricKey) async throws {
        let normalizedTopic = topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampPoints: (Double?) -> Double? = { value in
            guard let v = value else { return nil }
            return min(max(v, 0), 15)
        }
        let now = Date()
        let performance = SeminarPerformance(
            id: "current",
            topic: (normalizedTopic?.isEmpty == false ? normalizedTopic : nil),
            individualPoints: clampPoints(individualPoints),
            paperPoints: clampPoints(paperPoints),
            presentationPoints: clampPoints(presentationPoints),
            submissionDate: submissionDate,
            presentationDate: presentationDate,
            note: (normalizedNote?.isEmpty == false ? normalizedNote : nil),
            updatedAt: now
        )

        let offline = OfflineModeManager.shared.isOfflineModeActive
        let uid = Auth.auth().currentUser?.uid ?? ""
        if offline || uid.isEmpty {
            offlinePendingSeminar = PendingSeminarPerformance(
                topic: performance.topic,
                individualPoints: performance.individualPoints,
                paperPoints: performance.paperPoints,
                presentationPoints: performance.presentationPoints,
                submissionDate: performance.submissionDate,
                presentationDate: performance.presentationDate,
                note: performance.note,
                createdAt: now
            )
            seminarPerformance = performance
            persistOfflineSnapshotIfPossible()
            return
        }

        guard let realUid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let yearRef = try await requireYearRef(uid: realUid)
        let docRef = yearRef.collection("seminar").document("current")
        var payload: [String: Any] = [
            "topic": performance.topic as Any,
            "submissionDate": performance.submissionDate as Any,
            "presentationDate": performance.presentationDate as Any,
            "note": performance.note as Any,
            "updatedAt": now
        ]

        if let individual = performance.individualPoints {
            payload["individualPoints"] = try CryptoService.encryptString(String(individual), key: key)
        } else {
            payload["individualPoints"] = FieldValue.delete()
        }

        if let paper = performance.paperPoints {
            payload["paperPoints"] = try CryptoService.encryptString(String(paper), key: key)
        } else {
            payload["paperPoints"] = FieldValue.delete()
        }

        if let presentation = performance.presentationPoints {
            payload["presentationPoints"] = try CryptoService.encryptString(String(presentation), key: key)
        } else {
            payload["presentationPoints"] = FieldValue.delete()
        }

        if performance.topic == nil { payload["topic"] = FieldValue.delete() }
        if performance.submissionDate == nil { payload["submissionDate"] = FieldValue.delete() }
        if performance.presentationDate == nil { payload["presentationDate"] = FieldValue.delete() }
        if performance.note == nil { payload["note"] = FieldValue.delete() }

        try await docRef.setData(payload, merge: true)
        seminarPerformance = performance
        offlinePendingSeminar = nil
        persistOfflineSnapshotIfPossible()
    }

    func upsertPracticalGrade(id: String? = nil,
                              grade: Double,
                              halfYear: Int?,
                              note: String?,
                              company: String?,
                              date: Date,
                              using key: SymmetricKey) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        let yearRef = try await requireYearRef(uid: uid)
        let docRef = yearRef.collection("practicalPerformance").document("current")

        var grades = practicalPerformance?.grades ?? []
        let normalizedHalfYear: Int? = {
            guard let hy = halfYear else { return nil }
            if hy == 1 || hy == 2 { return hy }
            return nil
        }()
        let entryId = id ?? UUID().uuidString
        let newEntry = PracticalGradeEntry(
            id: entryId,
            grade: grade,
            company: company,
            note: note,
            halfYear: normalizedHalfYear,
            date: date
        )

        if let idx = grades.firstIndex(where: { $0.id == entryId }) {
            grades[idx] = newEntry
        } else if let h = normalizedHalfYear, let idx = grades.firstIndex(where: { $0.halfYear == h }) {
            grades[idx] = newEntry
        } else {
            grades.append(newEntry)
        }

        grades = practicalGradesLimited(sortedPracticalGrades(grades))
        try await persistPracticalGrades(grades, using: key, docRef: docRef)
    }

    func deletePracticalGrade(id: String, using key: SymmetricKey) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        let yearRef = try await requireYearRef(uid: uid)
        let docRef = yearRef.collection("practicalPerformance").document("current")

        let current = practicalPerformance?.grades ?? []
        let updated = current.filter { $0.id != id }
        if updated.isEmpty {
            try await deletePracticalPerformance()
            return
        }
        try await persistPracticalGrades(updated, using: key, docRef: docRef)
    }

    func deletePracticalPerformance() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        let yearRef = try await requireYearRef(uid: uid)
        let docRef = yearRef.collection("practicalPerformance").document("current")
        try await docRef.delete()
        practicalPerformance = nil
    }

    func deleteFachreferat() async {
        let offline = OfflineModeManager.shared.isOfflineModeActive
        let uid = Auth.auth().currentUser?.uid ?? ""

        if offline || uid.isEmpty {
            offlinePendingFachreferat = nil
            fachreferat = nil
            persistOfflineSnapshotIfPossible()
            return
        }

        guard let realUid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: realUid) else { return }
        do {
            try await yearRef.collection("fachreferat").document("current").delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
        offlinePendingFachreferat = nil
        fachreferat = nil
        persistOfflineSnapshotIfPossible()
    }

    func deleteSeminarPerformance() async {
        let offline = OfflineModeManager.shared.isOfflineModeActive
        let uid = Auth.auth().currentUser?.uid ?? ""

        if offline || uid.isEmpty {
            offlinePendingSeminar = nil
            seminarPerformance = nil
            persistOfflineSnapshotIfPossible()
            return
        }

        guard let realUid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: realUid) else { return }
        do {
            try await yearRef.collection("seminar").document("current").delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
        offlinePendingSeminar = nil
        seminarPerformance = nil
        persistOfflineSnapshotIfPossible()
    }

    private func persistPracticalGrades(_ grades: [PracticalGradeEntry], using key: SymmetricKey, docRef: DocumentReference? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        let yearRef = try await requireYearRef(uid: uid)
        let targetDoc = docRef ?? yearRef.collection("practicalPerformance").document("current")

        let sorted = sortedPracticalGrades(grades)
        let encodedGrades: [[String: Any]] = try sorted.map { entry in
            let encrypted = try CryptoService.encryptString(String(entry.grade), key: key)
            return [
                "id": entry.id,
                "grade": encrypted,
                "company": entry.company as Any,
                "note": entry.note as Any,
                "halfYear": entry.halfYear as Any,
                "date": entry.date
            ]
        }

        var payload: [String: Any] = [
            "grades": encodedGrades
        ]

        if let first = sorted.first {
            payload["gradeOne"] = try CryptoService.encryptString(String(first.grade), key: key)
            payload["noteOne"] = first.note as Any
            payload["companyOne"] = first.company as Any
        } else {
            payload["gradeOne"] = FieldValue.delete()
            payload["noteOne"] = FieldValue.delete()
            payload["companyOne"] = FieldValue.delete()
        }

        if sorted.count > 1 {
            let second = sorted[1]
            payload["gradeTwo"] = try CryptoService.encryptString(String(second.grade), key: key)
            payload["noteTwo"] = second.note as Any
            payload["companyTwo"] = second.company as Any
        } else {
            payload["gradeTwo"] = FieldValue.delete()
            payload["noteTwo"] = FieldValue.delete()
            payload["companyTwo"] = FieldValue.delete()
        }

        try await targetDoc.setData(payload, merge: true)
        practicalPerformance = PracticalPerformance(id: "current", grades: sorted)
    }

    private func sortedPracticalGrades(_ grades: [PracticalGradeEntry]) -> [PracticalGradeEntry] {
        grades.sorted { lhs, rhs in
            if let lh = lhs.halfYear, let rh = rhs.halfYear, lh != rh {
                return lh < rh
            }
            if let _ = lhs.halfYear, rhs.halfYear == nil { return true }
            if lhs.halfYear == nil, let _ = rhs.halfYear { return false }
            return lhs.date < rhs.date
        }
    }

    private func practicalGradesLimited(_ grades: [PracticalGradeEntry]) -> [PracticalGradeEntry] {
        var result: [PracticalGradeEntry] = []
        for entry in grades {
            if let h = entry.halfYear, let idx = result.firstIndex(where: { $0.halfYear == h }) {
                result[idx] = entry
            } else {
                result.append(entry)
            }
        }
        if result.count <= 2 { return result }
        return Array(result.prefix(2))
    }

    private func decodeSeminarPerformance(data: [String: Any], key: SymmetricKey) -> SeminarPerformance? {
        func decryptPoints(_ raw: Any?) -> Double? {
            guard let encrypted = raw as? String else { return nil }
            guard let decrypted = try? CryptoService.decryptString(encrypted, key: key),
                  let value = Double(decrypted),
                  value.isFinite else { return nil }
            return value
        }

        let individual = decryptPoints(data["individualPoints"])
        let paper = decryptPoints(data["paperPoints"])
        let presentation = decryptPoints(data["presentationPoints"])
        let topicRaw = (data["topic"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = (topicRaw?.isEmpty == false) ? topicRaw : nil
        let submissionDate = (data["submissionDate"] as? Timestamp)?.dateValue()
        let presentationDate = (data["presentationDate"] as? Timestamp)?.dateValue()
        let noteRaw = (data["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (noteRaw?.isEmpty == false) ? noteRaw : nil
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        if individual == nil, paper == nil, presentation == nil, topic == nil, submissionDate == nil, presentationDate == nil, note == nil {
            return nil
        }

        return SeminarPerformance(
            id: "current",
            topic: topic,
            individualPoints: individual,
            paperPoints: paper,
            presentationPoints: presentation,
            submissionDate: submissionDate,
            presentationDate: presentationDate,
            note: note,
            updatedAt: updatedAt
        )
    }

    private func decodePracticalPerformance(data: [String: Any], key: SymmetricKey) -> PracticalPerformance? {
        if let gradesPayload = data["grades"] as? [[String: Any]] ?? (data["grades"] as? [Any])?.compactMap({ $0 as? [String: Any] }) {
            var entries: [PracticalGradeEntry] = []
            for raw in gradesPayload {
                guard let encryptedGrade = raw["grade"] as? String else { continue }
                guard let decrypted = try? CryptoService.decryptString(encryptedGrade, key: key),
                      let value = Double(decrypted),
                      value.isFinite else { continue }
                let id = raw["id"] as? String ?? UUID().uuidString
                let note = raw["note"] as? String
                let company = raw["company"] as? String
                let halfYear = raw["halfYear"] as? Int
                let ts = raw["date"] as? Timestamp
                let date = ts?.dateValue() ?? Date()
                entries.append(
                    PracticalGradeEntry(
                        id: id,
                        grade: value,
                        company: company,
                        note: note,
                        halfYear: halfYear,
                        date: date
                    )
                )
            }
            if !entries.isEmpty {
                return PracticalPerformance(id: "current", grades: sortedPracticalGrades(entries))
            }
        }

        let gradeOneStr = data["gradeOne"] as? String ?? data["grade"] as? String
        let gradeTwoStr = data["gradeTwo"] as? String
        do {
            let g1 = try gradeOneStr.flatMap { try CryptoService.decryptString($0, key: key) }.flatMap { Double($0) }
            let g2 = try gradeTwoStr.flatMap { try CryptoService.decryptString($0, key: key) }.flatMap { Double($0) }
            var entries: [PracticalGradeEntry] = []
            if let g1, g1.isFinite {
                entries.append(
                    PracticalGradeEntry(
                        id: "legacy-1",
                        grade: g1,
                        company: data["companyOne"] as? String ?? data["company"] as? String,
                        note: data["noteOne"] as? String ?? data["note"] as? String,
                        halfYear: 1,
                        date: Date()
                    )
                )
            }
            if let g2, g2.isFinite {
                entries.append(
                    PracticalGradeEntry(
                        id: "legacy-2",
                        grade: g2,
                        company: data["companyTwo"] as? String ?? data["companyOne"] as? String ?? data["company"] as? String,
                        note: data["noteTwo"] as? String,
                        halfYear: 2,
                        date: Date()
                    )
                )
            }

            if !entries.isEmpty {
                return PracticalPerformance(id: "current", grades: sortedPracticalGrades(entries))
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return nil
        }

        return nil
    }

    // MARK: - Update/Delete Grades

    func updateGradeInFirestore(
        subjectId: String,
        gradeId: String,
        grade: Double,
        weight: Double,
        date: Date,
        note: String?,
        halfYear: Int?,
        linkedExamId: String?,
        using key: SymmetricKey
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let yearRef = try await requireYearRef(uid: uid)
        let encrypted = try CryptoService.encryptString(String(grade), key: key)
        let gradeDocRef = yearRef.collection("subjects").document(subjectId).collection("grades").document(gradeId)
        let previousLinkedExamId = gradesBySubject[subjectId]?.first(where: { $0.id == gradeId })?.linkedExamId

        var payload: [String: Any] = [
            "grade": encrypted,
            "weight": weight,
            "date": date,
            "note": note as Any,
            "halfYear": halfYear as Any
        ]
        if let linkedExamId {
            payload["linkedExamId"] = linkedExamId
        } else {
            payload["linkedExamId"] = FieldValue.delete()
        }

        try await gradeDocRef.updateData(payload)

        // Optimistisch lokal (Listener setzt danach korrekt)
        var list = gradesBySubject[subjectId] ?? []
        if let idx = list.firstIndex(where: { $0.id == gradeId }) {
            list[idx] = GradeWithId(
                id: gradeId,
                grade: grade,
                weight: weight,
                date: date,
                note: note,
                halfYear: halfYear,
                linkedExamId: linkedExamId
            )
            gradesBySubject[subjectId] = list
        }

        if previousLinkedExamId != linkedExamId, let previousLinkedExamId {
            await resetExamAfterLinkedGradeDeletion(examId: previousLinkedExamId)
        }
        if let linkedExamId {
            if let sharedExam = sharedExams.first(where: { $0.id == linkedExamId }) {
                await setUserCompletedForSharedExam(examId: linkedExamId, completed: true, groupId: sharedExam.groupId)
            } else {
                await setExamCompleted(id: linkedExamId, completed: true)
            }
        }
    }

    func updateGradeNoteInFirestore(subjectId: String, gradeId: String, note: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let yearRef = try await requireYearRef(uid: uid)
        let gradeDocRef = yearRef.collection("subjects").document(subjectId).collection("grades").document(gradeId)
        try await gradeDocRef.updateData([
            "note": note as Any
        ])

        // Optimistisch lokal
        var list = gradesBySubject[subjectId] ?? []
        if let idx = list.firstIndex(where: { $0.id == gradeId }) {
            let g = list[idx]
            list[idx] = GradeWithId(
                id: g.id,
                grade: g.grade,
                weight: g.weight,
                date: g.date,
                note: note,
                halfYear: g.halfYear,
                linkedExamId: g.linkedExamId
            )
            gradesBySubject[subjectId] = list
        }
    }

    func deleteGradeFromFirestore(subjectId: String, gradeId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let yearRef = try await requireYearRef(uid: uid)
        let gradeDocRef = yearRef.collection("subjects").document(subjectId).collection("grades").document(gradeId)
        let linkedExamId = gradesBySubject[subjectId]?.first(where: { $0.id == gradeId })?.linkedExamId
        try await gradeDocRef.delete()

        // Optimistisch lokal
        var list = gradesBySubject[subjectId] ?? []
        list.removeAll { $0.id == gradeId }
        gradesBySubject[subjectId] = list

        if let linkedExamId {
            await resetExamAfterLinkedGradeDeletion(examId: linkedExamId)
        }
    }

    private func resetExamAfterLinkedGradeDeletion(examId: String) async {
        if let sharedExam = sharedExams.first(where: { $0.id == examId }) {
            if sharedExam.isCompleted {
                await setUserCompletedForSharedExam(examId: examId, completed: false, groupId: sharedExam.groupId)
            }
        } else if let exam = exams.first(where: { $0.id == examId }), exam.isCompleted {
            await setExamCompleted(id: examId, completed: false)
        }
    }
    
    func deleteSharedHomeworkFromGroup(id: String) async {
        guard let gid = homeworkGroupId, !gid.isEmpty else { return }
        let docRef = db.collection("homeworkGroups").document(gid).collection("homeworks").document(id)
        do {
            try await docRef.delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    // MARK: - Settings

    func updateSubjectSortPreferences(mode: SubjectSortMode, order: [String]) async {
        subjectSortMode = mode
        subjectSortOrder = order
        if mode == .custom {
            subjectCustomOrder = order
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        do {
            var update: [String: Any] = [
                "subjectSortMode": mode.rawValue,
                "subjectSortOrder": order
            ]
            if mode == .custom {
                update["subjectCustomOrder"] = order
            }
            try await yearRef.updateData(update)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
        }
    }

    func updateSubjectSortMode(mode: SubjectSortMode) async {
        subjectSortMode = mode
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        do {
            try await yearRef.updateData([
                "subjectSortMode": mode.rawValue
            ])
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
        }
    }

    func updateSubjectCustomOrder(order: [String]) async {
        subjectCustomOrder = order
        if subjectSortMode == .custom {
            subjectSortOrder = order
        }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        do {
            var update: [String: Any] = ["subjectCustomOrder": order]
            if subjectSortMode == .custom {
                update["subjectSortOrder"] = order
            }
            try await yearRef.updateData(update)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
        }
    }

    // Einheitliche Sortierung der Fächer – wird in allen Views genutzt.
    func sortedSubjectsForDisplay(_ input: [Subject]? = nil, moveSpecialsToEnd: Bool = true) -> [Subject] {
        let base = input ?? subjects
        guard !base.isEmpty else { return base }

        let comparatorNameAsc: (Subject, Subject) -> Bool = { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
        }
        let comparatorNameDesc: (Subject, Subject) -> Bool = { a, b in
            a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedDescending
        }
        let comparatorAverageBestFirst: (Subject, Subject) -> Bool = { a, b in
            let avgA = self.averageFor(subject: a)
            let avgB = self.averageFor(subject: b)
            switch (avgA, avgB) {
            case (nil, nil):
                return comparatorNameAsc(a, b)
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (a1?, b1?):
                return a1 > b1
            }
        }
        let comparatorAverageWorstFirst: (Subject, Subject) -> Bool = { a, b in
            let avgA = self.averageFor(subject: a)
            let avgB = self.averageFor(subject: b)
            switch (avgA, avgB) {
            case (nil, nil):
                return comparatorNameAsc(a, b)
            case (nil, _):
                return true
            case (_, nil):
                return false
            case let (a1?, b1?):
                return a1 < b1
            }
        }
        let comparatorCustom: (Subject, Subject) -> Bool = { a, b in
            let orderMap: [String: Int] = Dictionary(uniqueKeysWithValues: self.subjectSortOrder.enumerated().map { ($1, $0) })
            let ia = orderMap[a.name]
            let ib = orderMap[b.name]
            switch (ia, ib) {
            case let (ia?, ib?):
                return ia < ib
            case (nil, nil):
                return comparatorNameAsc(a, b)
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }

        func moveSpecials(_ list: [Subject]) -> [Subject] {
            guard moveSpecialsToEnd else { return list }
            var arr = list
            var tail: [Subject] = []

            if let idx = arr.firstIndex(where: { $0.name == "Fachreferat" }) {
                tail.append(arr.remove(at: idx))
            }
            if schoolType == .fos, let idx = arr.firstIndex(where: { $0.name == "Praktikum" }) {
                tail.append(arr.remove(at: idx))
            }
            arr.append(contentsOf: tail)
            return arr
        }

        switch subjectSortMode {
        case .name:
            return moveSpecials(base.sorted(by: comparatorNameAsc))
        case .name_desc:
            return moveSpecials(base.sorted(by: comparatorNameDesc))
        case .average:
            return moveSpecials(base.sorted(by: comparatorAverageBestFirst))
        case .average_worst:
            return moveSpecials(base.sorted(by: comparatorAverageWorstFirst))
        case .custom:
            if subjectSortOrder.isEmpty {
                return moveSpecials(base.sorted(by: comparatorNameAsc))
            }
            return base.sorted(by: comparatorCustom)
        }
    }

    // Durchschnitt zur Sortierung – nutzt vorhandene gewichtete Logik aus Overall-Berechnung.
    private func averageFor(subject: Subject) -> Double? {
        let grades = gradesBySubject[subject.name] ?? []
        guard !grades.isEmpty else { return nil }
        var total = 0.0
        var totalWeight = 0.0
        for g in grades {
            let weight = calculateGradeWeightForOverall(
                subject: subject,
                grade: Grade(
                    grade: g.grade,
                    weight: g.weight,
                    date: g.date,
                    note: g.note,
                    halfYear: g.halfYear,
                    linkedExamId: g.linkedExamId
                )
            )
            total += g.grade * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return total / totalWeight
    }

    func calculateGradeWeightForOverall(subject: Subject, grade: Grade) -> Double {
        effectiveGradeWeight(subjectType: subject.type, rawWeight: grade.weight)
    }

    func effectiveGradeWeight(subjectType: Int, rawWeight: Double) -> Double {
        if rawWeight < 0 {
            let custom = abs(rawWeight)
            return custom > 0 ? custom : 1
        }

        if subjectType == 1 {
            if rawWeight == 3 || rawWeight == 2 { return 2 }
            if rawWeight == 1 { return 1 }
            if rawWeight <= 0 { return 1 }
            return rawWeight
        }

        if subjectType == 0 {
            if rawWeight == 3 || rawWeight == 1 { return 2 }
            if rawWeight <= 0 { return 1 }
            return rawWeight
        }

        return rawWeight > 0 ? rawWeight : 1
    }

    func updateUserDisplayName(name: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "name": name,
                "displayName": name
            ])
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func updatePreferences(theme: String? = nil,
                           themeIntensity: Double? = nil,
                           darkMode: Bool? = nil,
                           darkModeMode: String? = nil,
                           compactView: Bool? = nil,
                           animationsEnabled: Bool? = nil,
                           holidayHintsEnabled: Bool? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let clampedIntensity = themeIntensity.map { max(0, min(1, $0)) }

        // lokalen State vorab aktualisieren (optimistic UI)
        if let theme { self.theme = theme }
        if let clampedIntensity { self.themeBackgroundIntensity = clampedIntensity }
        if let darkMode {
            self.darkMode = darkMode
            self.darkModeMode = darkMode ? "dark" : "light"
        }
        if let mode = darkModeMode, ["system","light","dark"].contains(mode) {
            self.darkModeMode = mode
            self.darkMode = effectiveDarkMode(for: mode)
        }
        if let compactView { self.compactView = compactView }
        if let animationsEnabled { self.animationsEnabled = animationsEnabled }
        if let holidayHintsEnabled { self.showHolidayHints = holidayHintsEnabled }

        // lokal speichern, damit Einstellungen direkt beim App-Start verfügbar sind
        let defaults = UserDefaults.standard
        if let theme { defaults.set(theme, forKey: "grades_theme") }
        if let clampedIntensity { defaults.set(clampedIntensity, forKey: "grades_themeIntensity") }
        if let darkMode { defaults.set(darkMode, forKey: "grades_darkMode") }
        if let mode = darkModeMode { defaults.set(mode, forKey: "grades_darkModeMode") }
        if let compactView { defaults.set(compactView, forKey: "grades_compactView") }
        if let animationsEnabled { defaults.set(animationsEnabled, forKey: "grades_animationsEnabled") }
        if let holidayHintsEnabled { defaults.set(holidayHintsEnabled, forKey: "grades_showHolidayHints") }

        var payload: [String: Any] = [:]
        if let theme { payload["theme"] = theme }
        if let clampedIntensity { payload["themeIntensity"] = clampedIntensity }
        if let darkMode { payload["darkMode"] = darkMode }
        if let mode = darkModeMode { payload["darkModeMode"] = mode }
        if let compactView { payload["compactView"] = compactView }
        if let animationsEnabled { payload["animationsEnabled"] = animationsEnabled }
        if let holidayHintsEnabled { payload["holidayHintsEnabled"] = holidayHintsEnabled }

        guard !payload.isEmpty else { return }
        do {
            try await db.collection("users").document(uid).updateData(payload)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional rollback/loggen
        }

        persistOfflineSnapshotIfPossible()
    }

    // MARK: - Admin Support Access

    /// Grants admin access for 24 hours and creates a support request
    func grantAdminAccess(message: String, notifyByPush: Bool, notifyByEmail: Bool, email: String?, allowGradeDecryption: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        _ = try await FirestoreService.shared.grantAdminAccess(
            userId: uid,
            message: message,
            notifyByPush: notifyByPush,
            notifyByEmail: notifyByEmail,
            email: email,
            allowGradeDecryption: allowGradeDecryption
        )
        // State will be updated via userDocListener
    }

    /// Revokes admin access immediately
    func revokeAdminAccess() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await FirestoreService.shared.revokeAdminAccess(userId: uid)
        // State will be updated via userDocListener
    }

    @MainActor
    func updateAppIcon(to selection: String) async {
        let normalized = supportedAppIcons.contains(selection) ? selection : "default"
        appIcon = normalized
        UserDefaults.standard.set(normalized, forKey: appIconDefaultsKey)

        await applyAppIconSelectionIfNeeded()

        let resolvedIcon = appIcon
        if let uid = Auth.auth().currentUser?.uid {
            do {
                try await db.collection("users").document(uid).setData([
                    "appIcon": resolvedIcon
                ], merge: true)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
        }

        persistOfflineSnapshotIfPossible()
    }

    func updateHomeworkReminderTime(hour: Int, minute: Int) async {
        let hr = max(0, min(23, hour))
        let mn = max(0, min(59, minute))
        homeworkReminderHour = hr
        homeworkReminderMinute = mn

        let defaults = UserDefaults.standard
        defaults.set(hr, forKey: "grades_hwReminderHour")
        defaults.set(mn, forKey: "grades_hwReminderMinute")

        if let uid = Auth.auth().currentUser?.uid {
            do {
                try await db.collection("users").document(uid).setData([
                    "homeworkReminderHour": hr,
                    "homeworkReminderMinute": mn
                ], merge: true)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
        }

        rescheduleLocalNotifications()

        persistOfflineSnapshotIfPossible()
    }

    func updateStandardReminderEnabled(_ enabled: Bool) async {
        standardRemindersEnabled = enabled
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: "grades_standardRemindersEnabled")

        if let uid = Auth.auth().currentUser?.uid {
            do {
                try await db.collection("users").document(uid).setData([
                    "standardRemindersEnabled": enabled
                ], merge: true)
            } catch {
                ErrorLoggingService.logErrorIfEnabled(error)
                // optional loggen
            }
        }

        rescheduleLocalNotifications()
        persistOfflineSnapshotIfPossible()
    }

    private func rescheduleLocalNotifications() {
        HomeworkNotificationManager.syncNotifications(
            for: allHomeworks,
            reminderHour: homeworkReminderHour,
            reminderMinute: homeworkReminderMinute,
            standardReminderEnabled: standardRemindersEnabled
        )
        ExamNotificationManager.syncNotifications(
            for: allExams,
            standardReminderEnabled: standardRemindersEnabled
        )
        DailyReminderNotificationManager.syncDailyReminder(
            homeworks: allHomeworks,
            exams: allExams,
            hour: homeworkReminderHour,
            minute: homeworkReminderMinute,
            enabled: standardRemindersEnabled
        )
        BackgroundRefreshManager.schedule(for: allExams)
        Task {
            await ExamLiveActivityManager.syncLiveActivities(for: allExams)
        }
    }

    /// Wird aufgerufen, wenn die App im System-Modus läuft und sich das ColorScheme des Geräts ändert.
    /// Synchronisiert `darkMode`, damit eigene Gradients/Materialien sofort den Wechsel mitmachen.
    func syncDarkModeWithSystem(colorScheme: ColorScheme) {
        guard darkModeMode == "system" else { return }
        let shouldBeDark = (colorScheme == .dark)
        if darkMode != shouldBeDark {
            darkMode = shouldBeDark
        }
    }

    func updateGradeYear(_ year: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        self.gradeYear = year
        do {
            try await yearRef.updateData([
                "gradeYear": year
            ])
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }

        persistOfflineSnapshotIfPossible()
    }

    func updateSchoolType(_ type: SchoolType) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        self.schoolType = type
        do {
            try await yearRef.updateData([
                "schoolType": type.rawValue
            ])
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }

        persistOfflineSnapshotIfPossible()
    }

    func updateSchoolYearName(_ newName: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let sid = activeSchoolYearId else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let ref = schoolYearRef(uid: uid, id: sid)
            try await ref.setData([
                "name": trimmed
            ], merge: true)
            schoolYearNames[sid] = trimmed
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func markOnboardingCompletedIfPossible() async {
        guard !subjects.isEmpty else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).setData([
                "onboardingCompleted": true,
                "migratedToSchoolYears": true,
                "legacyDecisionPending": false
            ], merge: true)
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
        onboardingRequired = false

        persistOfflineSnapshotIfPossible()
    }

    private func effectiveDarkMode(for mode: String) -> Bool {
        switch mode {
        case "dark": return true
        case "light": return false
        default:
            #if os(iOS)
            return UITraitCollection.current.userInterfaceStyle == .dark
            #else
            return false
            #endif
        }
    }

    func restartOnboarding() async {
        await MainActor.run {
            // Nur lokal erneut anzeigen, ohne den Backend-Status zu überschreiben,
            // damit ein abgebrochenes Onboarding nicht dauerhaft erneut gefordert wird.
            onboardingRequired = true
        }
    }

    private func resolveOnboardingDone(from data: [String: Any]?) -> Bool {
        let onboardingDone = (data?["onboardingCompleted"] as? Bool) ?? false
        let migrated = (data?["migratedToSchoolYears"] as? Bool) ?? false
        let legacyPending = (data?["legacyDecisionPending"] as? Bool) ?? false
        return onboardingDone && migrated && !legacyPending
    }

    func updateSubjectExamFlags(subjectName: String, examSubject: Bool, examType: ExamType) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let yearRef = try await requireYearRef(uid: uid)
            try await yearRef
                .collection("subjects")
                .document(subjectName)
                .updateData([
                    "examSubject": examSubject,
                    "examType": examType.rawValue
                ])

            // Optimistisch lokal (Listener setzt danach korrekt)
            subjects = subjects.map { s in
                if s.name == subjectName {
                    return Subject(name: s.name,
                                   type: s.type,
                                   date: s.date,
                                   order: s.order,
                                   teacher: s.teacher,
                                   room: s.room,
                                   email: s.email,
                                   alias: s.alias,
                                   droppedHalfYear: s.droppedHalfYear,
                                   examSubject: examSubject,
                                   examType: examType,
                                   examPointsEncrypted: s.examPointsEncrypted,
                                   writtenExamPointsEncrypted: s.writtenExamPointsEncrypted,
                                   oralExamPointsEncrypted: s.oralExamPointsEncrypted,
                                   isElective: s.isElective)
                }
                return s
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func updateDroppedHalfYear(subjectName: String, value: Int?, inSchoolYear schoolYearId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let yearRef: DocumentReference
            if let sid = schoolYearId {
                yearRef = schoolYearRef(uid: uid, id: sid)
            } else {
                yearRef = try await requireYearRef(uid: uid)
            }

            try await yearRef
                .collection("subjects")
                .document(subjectName)
                .updateData([
                    "droppedHalfYear": value as Any
                ])

            // Optimistisch lokal nur für das aktive Schuljahr (Listener setzt danach korrekt)
            if schoolYearId == nil {
                subjects = subjects.map { s in
                    if s.name == subjectName {
                        return Subject(name: s.name,
                                       type: s.type,
                                       date: s.date,
                                       order: s.order,
                                       teacher: s.teacher,
                                       room: s.room,
                                       email: s.email,
                                       alias: s.alias,
                                       droppedHalfYear: value,
                                       examSubject: s.examSubject,
                                       examType: s.examType,
                                       examPointsEncrypted: s.examPointsEncrypted,
                                       writtenExamPointsEncrypted: s.writtenExamPointsEncrypted,
                                       oralExamPointsEncrypted: s.oralExamPointsEncrypted,
                                       isElective: s.isElective)
                    }
                    return s
                }
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func deleteHomeworkFromFirestore(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let docRef = yearRef
            .collection("homeworks")
            .document(id)
        do {
            try await docRef.delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func deleteExamFromFirestore(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let docRef = yearRef
            .collection("exams")
            .document(id)
        do {
            try await docRef.delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func deleteSharedExamFromGroup(groupId: String, id: String) async {
        let docRef = db.collection("groups").document(groupId).collection("exams").document(id)
        do {
            try await docRef.delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    func deleteSharedHomeworkFromGroup(groupId: String, id: String) async {
        let docRef = db.collection("groups").document(groupId).collection("homeworks").document(id)
        do {
            try await docRef.delete()
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }

    // Füge weitere lokale Fächer zu einer bestehenden Gruppe hinzu und aktualisiere das Mapping
    @discardableResult
    func addSubjectsToGroup(groupId: String, subjectNames: [String]) async throws -> Int {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        guard let yearRef = try? await requireYearRef(uid: uid) else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Kein aktives Schuljahr"])
        }

        let trimmed = subjectNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return 0 }

        let usedElsewhere = Set(groupSubjectMappings
            .filter { $0.key != groupId }
            .flatMap { $0.value.values })
        let existingKeys = Set(groupSubjectsByGroup[groupId]?.map { $0.id } ?? [])
        var added: [GroupSubject] = []
        var map = groupSubjectMappings[groupId] ?? [:]

        for name in trimmed {
            guard let subj = subjects.first(where: { $0.name == name }) else { continue }
            guard !usedElsewhere.contains(subj.name) else { continue }
            let sid = slugifySubjectName(subj.name)
            guard !existingKeys.contains(sid) else { continue }

            var payload: [String: Any] = [
                "name": subj.name,
                "type": subj.type,
                "alias": subj.alias as Any
            ]
            if let alias = subj.alias, alias.isEmpty { payload["alias"] = FieldValue.delete() }

            try await db.collection("groups").document(groupId)
                .collection("subjects").document(sid)
                .setData(payload, merge: true)

            map[sid] = subj.name
            added.append(GroupSubject(id: sid, name: subj.name, type: subj.type, alias: subj.alias))
        }

        guard !added.isEmpty else { return 0 }

        try await yearRef.collection("groupMappings").document(groupId).setData(["map": map], merge: true)
        await MainActor.run {
            groupSubjectMappings[groupId] = map
            var list = groupSubjectsByGroup[groupId] ?? []
            for entry in added where !list.contains(entry) {
                // Ersetze ggf. bestehendes Fach mit gleicher ID, um doppelte Anzeige zu vermeiden
                list.removeAll { $0.id == entry.id }
                list.append(entry)
            }
            groupSubjectsByGroup[groupId] = list
        }

        return added.count
    }

    func deleteGroupSubject(groupId: String, subjectId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let groupRef = db.collection("groups").document(groupId)
        let snap = try await groupRef.getDocument()
        let ownerId = snap.data()?["ownerId"] as? String
        await MainActor.run {
            if let ownerId { groupOwners[groupId] = ownerId }
        }
        if let ownerId, ownerId != uid {
            throw NSError(domain: "GradesStore", code: -5, userInfo: [NSLocalizedDescriptionKey: "Nur der Ersteller der Gruppe kann Fächer löschen."])
        }

        try await groupRef.collection("subjects").document(subjectId).delete()

        var map = groupSubjectMappings[groupId] ?? [:]
        let removed = map.removeValue(forKey: subjectId)
        if let yearRef = try? await requireYearRef(uid: uid) {
            try? await yearRef.collection("groupMappings").document(groupId).setData(["map": map], merge: true)
        }

        await MainActor.run {
            groupSubjectMappings[groupId] = map
            var list = groupSubjectsByGroup[groupId] ?? []
            list.removeAll { $0.id == subjectId }
            groupSubjectsByGroup[groupId] = list
            if removed != nil {
                recomputeSharedCollections()
            }
        }
    }

    func deleteSubjectFromFirestore(subjectName: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard let yearRef = try? await requireYearRef(uid: uid) else { return }
        let subjectRef = yearRef.collection("subjects").document(subjectName)
        do {
            // Delete all grades in subcollection
            let gradesSnap = try await subjectRef.collection("grades").getDocuments()
            for gdoc in gradesSnap.documents {
                try await gdoc.reference.delete()
            }
            // Delete the subject document itself
            try await subjectRef.delete()

            // Optimistically update local state
            await MainActor.run {
                self.subjects.removeAll { $0.name == subjectName }
                self.gradesBySubject.removeValue(forKey: subjectName)
                // Clean up listeners and caches for this subject
                self.gradesListeners[subjectName]?.remove()
                self.gradesListeners.removeValue(forKey: subjectName)
                self.encryptedGradesCache.removeValue(forKey: subjectName)
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional: Fehlerbehandlung oder Logging
        }
    }

    // MARK: - Helpers for group subjects and mappings

    private func loadGroupSubjectsForImport(groupId: String) async -> [GroupSubject] {
        if let cached = groupSubjectsByGroup[groupId], !cached.isEmpty {
            return cached
        }
        do {
            let snap = try await db.collection("groups").document(groupId).collection("subjects").getDocuments()
            return snap.documents.map { doc in
                let data = doc.data()
                let name = data["name"] as? String ?? doc.documentID
                let type = data["type"] as? Int
                let alias = data["alias"] as? String
                return GroupSubject(id: doc.documentID, name: name, type: type, alias: alias)
            }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            return []
        }
    }

    private func slugifySubjectName(_ name: String) -> String {
        let lower = name.lowercased()
        let map: [String: String] = ["ä":"ae","ö":"oe","ü":"ue","ß":"ss"]
        var s = lower
        for (k,v) in map { s = s.replacingOccurrences(of: k, with: v) }
        let allowed = CharacterSet.alphanumerics
        return s.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined().replacingOccurrences(of: "--", with: "-")
    }

    private func updateExamGroupSubjectsListenerIfNeeded(forceReload: Bool = false) {
        if forceReload || examGroupSubjectsGid != examGroupId {
            examGroupSubjectsListener?.remove()
            examGroupSubjectsListener = nil
            examGroupSubjectsGid = nil
            examGroupSubjects = []
        }
        guard let gid = examGroupId else {
            examGroupSubjectsListener?.remove(); examGroupSubjectsListener = nil; examGroupSubjectsGid = nil; examGroupSubjects = []; return
        }
        if examGroupSubjectsListener != nil { return }
        examGroupSubjectsGid = gid
        examGroupSubjectsListener = db.collection("examGroups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                self.examGroupSubjects = docs.map { d in
                    let data = d.data()
                    let name = data["name"] as? String ?? d.documentID
                    let type = data["type"] as? Int
                    let alias = data["alias"] as? String
                    return GroupSubject(id: d.documentID, name: name, type: type, alias: alias)
                }
            }
        }
    }

    private func updateHomeworkGroupSubjectsListenerIfNeeded(forceReload: Bool = false) {
        if forceReload || homeworkGroupSubjectsGid != homeworkGroupId {
            homeworkGroupSubjectsListener?.remove()
            homeworkGroupSubjectsListener = nil
            homeworkGroupSubjectsGid = nil
            homeworkGroupSubjects = []
        }
        guard let gid = homeworkGroupId else {
            homeworkGroupSubjectsListener?.remove(); homeworkGroupSubjectsListener = nil; homeworkGroupSubjectsGid = nil; homeworkGroupSubjects = []; return
        }
        if homeworkGroupSubjectsListener != nil { return }
        homeworkGroupSubjectsGid = gid
        homeworkGroupSubjectsListener = db.collection("homeworkGroups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                self.homeworkGroupSubjects = docs.map { d in
                    let data = d.data()
                    let name = data["name"] as? String ?? d.documentID
                    let type = data["type"] as? Int
                    let alias = data["alias"] as? String
                    return GroupSubject(id: d.documentID, name: name, type: type, alias: alias)
                }
            }
        }
    }

    private func updateExamSubjectMappingListenerIfNeeded(uid: String, forceReload: Bool = false) {
        if forceReload || examSubjectMappingGid != examGroupId {
            examSubjectMappingListener?.remove(); examSubjectMappingListener = nil; examSubjectMappingGid = nil; examSubjectMapping = [:]
        }
        guard let gid = examGroupId,
              let schoolYearId = activeSchoolYearId else {
            examSubjectMappingListener?.remove(); examSubjectMappingListener = nil; examSubjectMappingGid = nil; examSubjectMapping = [:]; return
        }
        if examSubjectMappingListener != nil { return }
        examSubjectMappingGid = gid
        examSubjectMappingListener = schoolYearRef(uid: uid, id: schoolYearId).collection("subjectMappings").document(gid).addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let data = snap?.data() ?? [:]
                self.examSubjectMapping = data["map"] as? [String: String] ?? [:]
            }
        }
    }

    private func updateHomeworkSubjectMappingListenerIfNeeded(uid: String, forceReload: Bool = false) {
        if forceReload || homeworkSubjectMappingGid != homeworkGroupId {
            homeworkSubjectMappingListener?.remove(); homeworkSubjectMappingListener = nil; homeworkSubjectMappingGid = nil; homeworkSubjectMapping = [:]
        }
        guard let gid = homeworkGroupId,
              let schoolYearId = activeSchoolYearId else {
            homeworkSubjectMappingListener?.remove(); homeworkSubjectMappingListener = nil; homeworkSubjectMappingGid = nil; homeworkSubjectMapping = [:]; return
        }
        if homeworkSubjectMappingListener != nil { return }
        homeworkSubjectMappingGid = gid
        homeworkSubjectMappingListener = schoolYearRef(uid: uid, id: schoolYearId).collection("subjectMappings").document(gid).addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let data = snap?.data() ?? [:]
                self.homeworkSubjectMapping = data["map"] as? [String: String] ?? [:]
            }
        }
    }

    // MARK: - Neue Gruppen-Listener (/groups)

    private func updateGroupObservers(uid: String, schoolYearId: String? = nil) {
        guard let sid = schoolYearId ?? activeSchoolYearId else { return }
        let current = Set(groupIds)

        // Entferne Listener für alte Gruppen
        for (gid, l) in groupSubjectsListeners where !current.contains(gid) {
            l.remove()
            groupSubjectsListeners.removeValue(forKey: gid)
            groupSubjectsByGroup.removeValue(forKey: gid)
        }
        for (gid, l) in groupMappingsListeners where !current.contains(gid) {
            l.remove()
            groupMappingsListeners.removeValue(forKey: gid)
            groupSubjectMappings.removeValue(forKey: gid)
        }
        for (gid, l) in groupNameListeners where !current.contains(gid) {
            l.remove()
            groupNameListeners.removeValue(forKey: gid)
            groupNames.removeValue(forKey: gid)
            groupOwners.removeValue(forKey: gid)
        }
        for (gid, l) in groupMembersListeners where !current.contains(gid) {
            l.remove()
            groupMembersListeners.removeValue(forKey: gid)
            groupMemberIds.removeValue(forKey: gid)
        }

        // Starte Listener für aktuelle Gruppen
        for gid in current {
            startGroupSubjectsListener(for: gid)
            startGroupMappingsListener(for: gid, uid: uid, schoolYearId: sid)
            startGroupNameListener(for: gid)
            startGroupMembersListener(for: gid)
            startGroupExamsListener(for: gid)
            startGroupHomeworksListener(for: gid)
        }
    }

    private func startGroupSubjectsListener(for gid: String) {
        if groupSubjectsListeners[gid] != nil { return }
        groupSubjectsListeners[gid] = db.collection("groups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let subjects = docs.map { d -> GroupSubject in
                    let data = d.data()
                    let name = data["name"] as? String ?? d.documentID
                    let type = data["type"] as? Int
                    let alias = data["alias"] as? String
                    return GroupSubject(id: d.documentID, name: name, type: type, alias: alias)
                }
                self.groupSubjectsByGroup[gid] = subjects
                self.recomputeSharedCollections()
            }
        }
    }

    private func startGroupMappingsListener(for gid: String, uid: String, schoolYearId: String) {
        if groupMappingsListeners[gid] != nil { return }
        groupMappingsListeners[gid] = schoolYearRef(uid: uid, id: schoolYearId).collection("groupMappings").document(gid).addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let data = snap?.data() ?? [:]
                let map = data["map"] as? [String: String] ?? [:]
                self.groupSubjectMappings[gid] = map
                self.recomputeSharedCollections()
            }
        }
    }

    private func startGroupNameListener(for gid: String) {
        if groupNameListeners[gid] != nil { return }
        groupNameListeners[gid] = db.collection("groups").document(gid).addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                if let data = snap?.data() {
                    // Check if group has been migrated
                    if let cid = data["migratedToClassId"] as? String {
                        self.migratedGroupIds.insert(gid)
                        self.groupMigratedToClassIds[gid] = cid
                    } else {
                        self.migratedGroupIds.remove(gid)
                        self.groupMigratedToClassIds.removeValue(forKey: gid)
                    }
                    
                    if let name = data["name"] as? String {
                        self.groupNames[gid] = name
                    } else {
                        self.groupNames.removeValue(forKey: gid)
                    }
                    if let branchName = data["migratedToBranchName"] as? String {
                        self.groupBranchNames[gid] = branchName
                    } else {
                        self.groupBranchNames.removeValue(forKey: gid)
                    }
                    if let owner = data["ownerId"] as? String {
                        self.groupOwners[gid] = owner
                    } else {
                        self.groupOwners.removeValue(forKey: gid)
                    }
                } else {
                    self.groupNames.removeValue(forKey: gid)
                    self.groupOwners.removeValue(forKey: gid)
                }
            }
        }
    }

    private func startGroupMembersListener(for gid: String) {
        if groupMembersListeners[gid] != nil { return }
        groupMembersListeners[gid] = db.collection("groups").document(gid).collection("members").addSnapshotListener { [weak self] snap, error in
            // Error intentionally ignored or lightweight logging
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let ids = docs.map { $0.documentID }
                self.groupMemberIds[gid] = Set(ids)
            }
        }
    }



    private func startGroupExamsListener(for gid: String) {
        if groupExamsListeners[gid] != nil { return }
        groupExamsListeners[gid] = db.collection("groups").document(gid).collection("exams").order(by: "createdAt", descending: false).addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let list: [Exam] = docs.compactMap { doc in
                    let data = doc.data()
                    let subjectName = data["subjectName"] as? String ?? ""
                    let subjectKey = data["subjectKey"] as? String
                    let title = data["title"] as? String ?? ""
                    let notes = data["notes"] as? String
                    let createdTs = data["createdAt"] as? Timestamp
                    let createdAt = createdTs?.dateValue() ?? Date()
                    guard let dateTs = data["date"] as? Timestamp else { return nil }
                    let date = dateTs.dateValue()
                    let hasTimeFlag = data["hasTime"] as? Bool
                    let calendar = Calendar.current
                    let hasTime = hasTimeFlag ?? !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
                    let weight = data["weight"] as? Int
                    let customWeight = (data["customWeight"] as? NSNumber)?.doubleValue
                    let creatorId = data["creatorId"] as? String
                    let requiresGrade = data["requiresGrade"] as? Bool
                    return Exam(
                        id: doc.documentID,
                        groupId: gid,
                        subjectName: subjectName,
                        subjectKey: subjectKey,
                        title: title,
                        notes: notes,
                        date: date,
                        hasTime: hasTime,
                        weight: weight,
                        customWeight: customWeight,
                        reminderAt: nil,
                        isCompleted: false,
                        createdAt: createdAt,
                        isShared: true,
                        creatorId: creatorId,
                        requiresGrade: requiresGrade
                    )
                }
                self.groupExamsByGroup[gid] = list
                self.recomputeSharedCollections()
            }
        }
    }

    private func startGroupHomeworksListener(for gid: String) {
        if groupHomeworksListeners[gid] != nil { return }
        groupHomeworksListeners[gid] = db.collection("groups").document(gid).collection("homeworks").order(by: "createdAt", descending: false).addSnapshotListener { [weak self] snap, error in
            ErrorLoggingService.logErrorIfEnabled(error)
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let list: [Homework] = docs.compactMap { doc in
                    let data = doc.data()
                    let subjectName = data["subjectName"] as? String ?? ""
                    let subjectKey = data["subjectKey"] as? String
                    let title = data["title"] as? String ?? ""
                    let createdTs = data["createdAt"] as? Timestamp
                    let createdAt = createdTs?.dateValue() ?? Date()
                    let dueTs = data["dueDate"] as? Timestamp
                    let dueDate = dueTs?.dateValue()
                    let creatorId = data["creatorId"] as? String
                    return Homework(
                        id: doc.documentID,
                        groupId: gid,
                        subjectName: subjectName,
                        subjectKey: subjectKey,
                        title: title,
                        dueDate: dueDate,
                        reminderAt: nil,
                        isCompleted: false,
                        createdAt: createdAt,
                        isShared: true,
                        creatorId: creatorId,
                        isImportedFromShare: false
                    )
                }
                self.groupHomeworksByGroup[gid] = list
                self.recomputeSharedCollections()
            }
        }
    }

    private func recomputeSharedCollections() {
        let groupedExams = groupExamsByGroup.values.flatMap { $0 }
        let groupedHomeworks = groupHomeworksByGroup.values.flatMap { $0 }

        sharedExams = mergeSharedExams(groupedExams, legacySharedExams)
        sharedHomeworks = mergeSharedHomeworks(groupedHomeworks, legacySharedHomeworks)

        // Anwenderspezifische Erinnerungen/Erledigt-Status anwenden
        applySharedExamUserReminders()
        applySharedExamUserCompletion()
        applySharedExamUserRescheduledDates()
        applySharedHomeworkUserCompletion()
        applySharedHomeworkUserReminders()

        rescheduleLocalNotifications()
        persistOfflineSnapshotIfPossible()
    }

    private func mergeSharedExams(_ grouped: [Exam], _ legacy: [Exam]) -> [Exam] {
        var seen: Set<String> = []
        var merged: [Exam] = []
        merged.reserveCapacity(grouped.count + legacy.count)
        for exam in grouped + legacy {
            let key = compoundId(gid: exam.groupId, docId: exam.id)
            if seen.insert(key).inserted {
                merged.append(exam)
            }
        }
        return merged
    }

    private func mergeSharedHomeworks(_ grouped: [Homework], _ legacy: [Homework]) -> [Homework] {
        var seen: Set<String> = []
        var merged: [Homework] = []
        merged.reserveCapacity(grouped.count + legacy.count)
        for hw in grouped + legacy {
            let key = compoundId(gid: hw.groupId, docId: hw.id)
            if seen.insert(key).inserted {
                merged.append(hw)
            }
        }
        return merged
    }

    // MARK: - Gruppierung & Targets

    func availableSubjectsForNewGroup() -> [Subject] {
        let usedLocal = Set(groupSubjectMappings.values.flatMap { $0.values })
        return subjects.filter { $0.name != "Fachreferat" && !usedLocal.contains($0.name) }
    }

    // Fächer, die noch nicht in der Gruppe liegen und nicht von anderen Gruppen gemappt werden
    func availableSubjectsForGroupAttachment(groupId: String) -> [Subject] {
        let usedElsewhere = Set(groupSubjectMappings
            .filter { $0.key != groupId }
            .flatMap { $0.value.values })
        let existingKeys = Set(groupSubjectsByGroup[groupId]?.map { $0.id } ?? [])
        return subjects.filter { subj in
            subj.name != "Fachreferat"
            && !existingKeys.contains(slugifySubjectName(subj.name))
            && !usedElsewhere.contains(subj.name)
        }
    }

    func isCurrentUserOwner(of groupId: String) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        if let cached = await MainActor.run(body: { groupOwners[groupId] }) {
            return cached == uid
        }
        do {
            let snap = try await db.collection("groups").document(groupId).getDocument()
            let owner = snap.data()?["ownerId"] as? String
            await MainActor.run {
                if let owner { groupOwners[groupId] = owner }
            }
            if let owner { return owner == uid }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
        return false
    }

    func targetGroupIds(forLocalSubject subjectName: String) -> [String] {
        let key = slugifySubjectName(subjectName)
        var result: [String] = []
        for gid in groupIds {
            let subjects = groupSubjectsByGroup[gid] ?? []
            let hasKey = subjects.contains { $0.id == key }
            let mapped = groupSubjectMappings[gid]?[key]
            if hasKey || mapped == subjectName {
                result.append(gid)
            }
        }
        return result
    }
    
    func targetCourseIds(forLocalSubject subjectName: String) -> [String] {
        guard !subjectName.isEmpty else { return [] }
        let key = slugifySubjectName(subjectName)
        return courses.filter { course in
            if course.name.caseInsensitiveCompare(subjectName) == .orderedSame { return true }
            if let ck = course.subjectKey, ck == key { return true }
            return false
        }.map { $0.id }
    }
    
    // Helper to resolve a display name for a legacy group, potentially in a branch
    // Unified helper to resolve display name from either CourseID (Modern) or GroupID (Legacy)
    func resolveContextName(groupId: String?, courseId: String?) -> String {
        // 1. Try resolving via CourseID (New Architecture)
        if let courseId, let course = courses.first(where: { $0.id == courseId }) {
            if let classId = course.classId, let className = classNames[classId] {
                switch course.type {
                case .mandatory: return className
                case .branch(let bName): return "\(className) (\(bName))"
                case .elective: return "\(course.name) (\(className))"
                }
            }
            return course.name
        }
        
        // 2. Fallback to GroupID (Legacy / Migrated)
        if let gid = groupId {
            // Check if explicitly migrated
            if let classId = groupMigratedToClassIds[gid], let className = classNames[classId] {
                // Only show branch name if explicitly set and non-empty
                if let branchName = groupBranchNames[gid], !branchName.isEmpty {
                    return branchName // Just the branch name
                }
                // No branch or empty branch = whole class, show class name only
                return className
            }
            
            // Check if group belongs to a class (Legacy link)
            for (cid, schoolClass) in classDetails {
                if schoolClass.groupIds.contains(gid) {
                    let className = classNames[cid] ?? "Klasse"
                    // Only show branch name if explicitly set and non-empty
                    if let branchName = groupBranchNames[gid], !branchName.isEmpty {
                        return branchName // Just the branch name
                    }
                    // No branch = whole class, show class name only
                    return className
                }
            }
            return groupNames[gid] ?? "Gruppe"
        }
        
        return "Gruppe"
    }

    // MARK: - Public helpers for mappings

    // Neue Mapping-Helper (gruppenbasiert)

    func resolveLocalSubjectNameForExam(_ exam: Exam) -> String? {
        guard let key = exam.subjectKey, let gid = exam.groupId else { return nil }
        return groupSubjectMappings[gid]?[key]
    }

    func resolveLocalSubjectNameForHomework(_ hw: Homework) -> String? {
        guard let key = hw.subjectKey, let gid = hw.groupId else { return nil }
        return groupSubjectMappings[gid]?[key]
    }
    
    func updateGroupSubjectMapping(groupId: String, map: [String: String]) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            guard let yearRef = try? await requireYearRef(uid: uid) else { return }
            try await yearRef.collection("groupMappings").document(groupId).setData(["map": map], merge: true)
            await MainActor.run { self.groupSubjectMappings[groupId] = map }
        } catch {
            ErrorLoggingService.logErrorIfEnabled(error)
            // optional loggen
        }
    }
    
    // Unified helper for migrating group members to a class (handling Legacy + Current)
    private func migrateMembersFromGroupToClass(groupId: String, toClassId: String, courseIds: [String]) async throws {
        var memberIds = Set<String>()
        
        // A. Current Members (subcollection)
        if let currentSnap = try? await db.collection("groups").document(groupId).collection("members").getDocuments() {
            for doc in currentSnap.documents { memberIds.insert(doc.documentID) }
        }
        
        // B. Legacy Members (users.groupIds)
        // Note: Relies on default index for array-contains on collection 'users'
        if let legacySnap = try? await db.collection("users").whereField("groupIds", arrayContains: groupId).getDocuments() {
            for doc in legacySnap.documents {
                let uid = doc.documentID
                if memberIds.contains(uid) { continue }
                
                let data = doc.data()
                let migrated = data["migratedToSchoolYears"] as? Bool ?? false
                
                if !migrated {
                    // Legacy user who hasn't migrated -> Trust the legacy field
                    memberIds.insert(uid)
                } else {
                    // Migrated user. Check active school year.
                    let activeYearId = data["activeSchoolYearId"] as? String
                    if let activeYearId {
                        let yearDoc = try? await db.collection("users").document(uid).collection("schoolYears").document(activeYearId).getDocument()
                        let yearGroupIds = yearDoc?.data()?["groupIds"] as? [String] ?? []
                        if yearGroupIds.contains(groupId) {
                             memberIds.insert(uid)
                        }
                    } else {
                        // Fallback: check latest year
                        if let lastYear = try? await db.collection("users").document(uid).collection("schoolYears").order(by: "id", descending: true).limit(to: 1).getDocuments().documents.first {
                             let yearGroupIds = lastYear.data()["groupIds"] as? [String] ?? []
                             if yearGroupIds.contains(groupId) {
                                 memberIds.insert(uid)
                             }
                        }
                    }
                }
            }
        }
        
        let currentUid = Auth.auth().currentUser?.uid
        
        // C. Perform Migration
        for memberId in memberIds {
            if memberId == currentUid { continue }
            
            // 1. Add to Class Members
            try? await db.collection("classes").document(toClassId).collection("members").document(memberId).setData(["joinedAt": Date()])
            
            // 2. Subscribe & Update Profile
            if let userSnap = try? await db.collection("users").document(memberId).getDocument(),
               let userData = userSnap.data() {
                 
                 try? await db.collection("users").document(memberId).updateData([
                    "subscribedCourseIds": FieldValue.arrayUnion(courseIds)
                 ])
                 
                 var targetYearId = userData["activeSchoolYearId"] as? String
                 if targetYearId == nil {
                     let yearsSnap = try? await db.collection("users").document(memberId).collection("schoolYears")
                        .order(by: "id", descending: true).limit(to: 1).getDocuments()
                     targetYearId = yearsSnap?.documents.first?.documentID
                 }
                 
                 if let yearId = targetYearId {
                     try? await db.collection("users").document(memberId).collection("schoolYears").document(yearId).updateData([
                         "classIds": FieldValue.arrayUnion([toClassId])
                     ])
                 }
            }
        }
    }
}
