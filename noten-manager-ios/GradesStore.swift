import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import CryptoKit
import SwiftUI

@MainActor
final class GradesStore: ObservableObject {
    @Published var subjects: [Subject] = []
    @Published var gradesBySubject: [String: [GradeWithId]] = [:] // Key = subjectId (name)
    @Published var fachreferat: Fachreferat?
    @Published var homeworks: [Homework] = []
    @Published var exams: [Exam] = []            // Eigene Prüfungen
    @Published var sharedExams: [Exam] = []      // Prüfungen aus gemeinsamer Gruppe
    @Published var sharedHomeworks: [Homework] = []      // Hausaufgaben aus gemeinsamer Gruppe
    @Published var examGroupId: String? = nil    // Aktuelle Prüfungsgruppe
    @Published var homeworkGroupId: String? = nil

    // Neue gemeinsame Gruppen-Verwaltung
    @Published var groupIds: [String] = []
    @Published var groupNames: [String: String] = [:] // gid -> name
    @Published var groupSubjectsByGroup: [String: [GroupSubject]] = [:] // gid -> subjects
    @Published var groupSubjectMappings: [String: [String: String]] = [:] // gid -> subjectKey -> local name
    @Published var groupExamsByGroup: [String: [Exam]] = [:]
    @Published var groupHomeworksByGroup: [String: [Homework]] = [:]

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
    @Published var compactView: Bool = false
    @Published var animationsEnabled: Bool = true

    // Settings-Erweiterungen (aus React)
    @Published var theme: String = "default" // "default" | "feminine"
    @Published var darkMode: Bool = false
    @Published var darkModeMode: String = "system" // "system" | "light" | "dark"

    var preferredColorScheme: ColorScheme? {
        switch darkModeMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
    @Published var gradeYear: Int? = nil // 12 oder 13

    // New published properties for group subjects and mappings
    @Published var examGroupSubjects: [GroupSubject] = []
    @Published var homeworkGroupSubjects: [GroupSubject] = []
    @Published var examSubjectMapping: [String: String] = [:] // subjectKey -> local subject name
    @Published var homeworkSubjectMapping: [String: String] = [:]

    private let db = Firestore.firestore()

    // Live-Listener
    private var userDocListener: ListenerRegistration?
    private var subjectsListener: ListenerRegistration?
    private var fachreferatListener: ListenerRegistration?
    private var homeworksListener: ListenerRegistration?
    private var examsListener: ListenerRegistration?
    private var sharedExamsListener: ListenerRegistration?
    private var sharedHomeworksListener: ListenerRegistration?
    private var sharedExamUserSettingsListener: ListenerRegistration?
    private var sharedHomeworkUserSettingsListener: ListenerRegistration?
    private var gradesListeners: [String: ListenerRegistration] = [:] // subjectId -> listener
    private var sharedExamsGroupId: String?
    private var sharedHomeworksGroupId: String?
    private var sharedExamUserReminders: [String: Date] = [:] // examId -> user-spezifische Erinnerung
    private var sharedHomeworkUserReminders: [String: Date] = [:] // homeworkId -> user-spezifische Erinnerung

    private var sharedHomeworkUserCompletedListener: ListenerRegistration?
    private var sharedHomeworkUserCompleted: Set<String> = []
    private var sharedExamUserCompletedListener: ListenerRegistration?
    private var sharedExamUserCompleted: Set<String> = []

    // Neue Listener für gemeinsame Gruppen
    private var groupSubjectsListeners: [String: ListenerRegistration] = [:]
    private var groupMappingsListeners: [String: ListenerRegistration] = [:]
    private var groupNameListeners: [String: ListenerRegistration] = [:]
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

    init() {
        loadLocalPreferences()
    }

    // MARK: - Live Updates

    func startListening() async {
        guard !isListening else { return }
        guard let uid = Auth.auth().currentUser?.uid else {
            resetState()
            return
        }
        isListening = true
        isLoading = true
        loadingLabel = "Verbinde …"
        progress = 0

        // 1) User-Dokument live beobachten (Einstellungen + encryptionSalt)
        userDocListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self else { return }
                if let data = snapshot?.data() {
                    self.applyUserSettings(from: data)
                    await self.deriveKeyIfNeeded(from: data, uid: uid)
                    // Nach dem Key-Setup ggf. weitere Listener starten
                    await self.ensureSecondaryListeners(uid: uid)
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
        subjectsListener?.remove()
        subjectsListener = nil
        fachreferatListener?.remove()
        fachreferatListener = nil
        homeworksListener?.remove()
        homeworksListener = nil
        examsListener?.remove()
        examsListener = nil
        sharedExamsListener?.remove()
        sharedExamsListener = nil
        sharedExamsGroupId = nil
        sharedExamUserSettingsListener?.remove()
        sharedExamUserSettingsListener = nil
        sharedExamUserReminders = [:]
        sharedExamUserCompletedListener?.remove()
        sharedExamUserCompletedListener = nil
        sharedExamUserCompleted = []
        sharedHomeworksListener?.remove()
        sharedHomeworksListener = nil
        sharedHomeworksGroupId = nil
        sharedHomeworkUserSettingsListener?.remove()
        sharedHomeworkUserSettingsListener = nil
        sharedHomeworkUserReminders = [:]
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
        subjects = []
        gradesBySubject = [:]
        fachreferat = nil
        encryptionKey = nil
        homeworks = []
        exams = []
        sharedExams = []
        sharedHomeworks = []
        examGroupId = nil
        homeworkGroupId = nil
        examGroupIds = []
        homeworkGroupIds = []
        examGroupName = nil
        homeworkGroupName = nil
        sharedExamUserReminders = [:]
        sharedHomeworkUserReminders = [:]
        sharedHomeworkUserCompleted = []
        sharedExamUserCompleted = []
        subjectSortMode = .name
        subjectSortOrder = []
        gradeYear = nil
        isLoading = false
        loadingLabel = ""
        progress = 0

        // Reset group subjects and mappings
        examGroupSubjects = []
        homeworkGroupSubjects = []
        examSubjectMapping = [:]
        homeworkSubjectMapping = [:]
        examGroupSubjectsGid = nil
        homeworkGroupSubjectsGid = nil
        examSubjectMappingGid = nil
        homeworkSubjectMappingGid = nil

        groupIds = []
        groupNames = [:]
        groupSubjectsByGroup = [:]
        groupSubjectMappings = [:]
        groupExamsByGroup = [:]
        groupHomeworksByGroup = [:]
    }

    // MARK: - Setup der weiteren Listener (Subjects, Grades, Fachreferat)

    private func ensureSecondaryListeners(uid: String) async {
        // Verhindere gleichzeitiges Setup
        if isSettingUp { return }
        isSettingUp = true
        defer { isSettingUp = false }

        // Subjects-Listener
        if subjectsListener == nil {
            progress = 20
            loadingLabel = "Fächer verbinden …"
            subjectsListener = db.collection("users").document(uid).collection("subjects")
                .addSnapshotListener { [weak self] snapshot, error in
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
                                           oralExamPointsEncrypted: oralExamPointsEncrypted)
                        }
                        self.subjects = subjectsData

                        // Sicherstellen, dass für alle Subjects ein Grades-Listener existiert
                        self.setupGradesListenersIfNeeded(uid: uid, subjects: subjectsData)

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
                    }
                }
        }

        // Fachreferat-Listener
        if fachreferatListener == nil {
            progress = 40
            loadingLabel = "Fachreferat verbinden …"
            fachreferatListener = db.collection("users").document(uid).collection("fachreferat").document("current")
                .addSnapshotListener { [weak self] snapshot, error in
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
                                self.fachreferat = nil
                            }
                        } else {
                            // Ohne Key können wir nicht entschlüsseln; als „nicht vorhanden“ behandeln
                            self.fachreferat = nil
                        }
                        self.finishInitialLoadingIfNeeded()
                    }
                }
        }

        // Hausaufgaben-Listener
        if homeworksListener == nil {
            homeworksListener = db.collection("users")
                .document(uid)
                .collection("homeworks")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snapshot, error in
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
                                creatorId: creatorId
                            )
                        }
                        self.homeworks = list
                        HomeworkNotificationManager.syncNotifications(for: self.allHomeworks)
                    }
                }
        }

        // Prüfungs-Listener
        if examsListener == nil {
            examsListener = db.collection("users")
                .document(uid)
                .collection("exams")
                .order(by: "createdAt", descending: false)
                .addSnapshotListener { [weak self] snapshot, error in
                    Task { @MainActor in
                        guard let self else { return }
                        let docs = snapshot?.documents ?? []
                        let list: [Exam] = docs.compactMap { doc in
                            let data = doc.data()
                            let subjectName = data["subjectName"] as? String ?? ""
                            let title = data["title"] as? String ?? ""
                            let isCompleted = data["isCompleted"] as? Bool ?? false
                            let createdTs = data["createdAt"] as? Timestamp
                            let createdAt = createdTs?.dateValue() ?? Date()
                            guard let dateTs = data["date"] as? Timestamp else { return nil }
                            let date = dateTs.dateValue()
                            let weight = data["weight"] as? Int
                            let reminderTs = data["reminderAt"] as? Timestamp
                            let reminderAt = reminderTs?.dateValue()
                            let creatorId = data["creatorId"] as? String ?? uid
                            let requiresGrade = data["requiresGrade"] as? Bool
                            return Exam(
                                id: doc.documentID,
                                groupId: nil,
                                subjectName: subjectName,
                                subjectKey: nil,
                                title: title,
                                date: date,
                                weight: weight,
                                reminderAt: reminderAt,
                                isCompleted: isCompleted,
                                createdAt: createdAt,
                                isShared: false,
                                creatorId: creatorId,
                                requiresGrade: requiresGrade
                            )
                        }
                        self.exams = list
                        ExamNotificationManager.syncNotifications(for: self.allExams)
                    }
                }
        }

        // Gemeinsame Prüfungs-Listener (legacy) – werden von den neuen Gruppen-Listenern ersetzt
        // updateSharedExamsListenerIfNeeded()
        // updateSharedHomeworksListenerIfNeeded()

        // New: Gruppen-Listener (/groups)
        updateGroupObservers(uid: uid)

        // User-spezifische Einstellungen für geteilte Prüfungen
        if sharedExamUserSettingsListener == nil {
            sharedExamUserSettingsListener = db.collection("users")
                .document(uid)
                .collection("examGroupReminders")
                .addSnapshotListener { [weak self] snapshot, error in
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
                        ExamNotificationManager.syncNotifications(for: self.allExams)
                    }
                }
        }

        if sharedExamUserCompletedListener == nil {
            sharedExamUserCompletedListener = db.collection("users").document(uid).collection("examGroupCompleted").addSnapshotListener { [weak self] snapshot, error in
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
                    ExamNotificationManager.syncNotifications(for: self.allExams)
                }
            }
        }

        if sharedHomeworkUserSettingsListener == nil {
            sharedHomeworkUserSettingsListener = db.collection("users").document(uid).collection("homeworkGroupReminders").addSnapshotListener { [weak self] snapshot, error in
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
                    HomeworkNotificationManager.syncNotifications(for: self.allHomeworks)
                }
            }
        }
        
        if sharedHomeworkUserCompletedListener == nil {
            sharedHomeworkUserCompletedListener = db.collection("users").document(uid).collection("homeworkGroupCompleted").addSnapshotListener { [weak self] snapshot, error in
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
                    HomeworkNotificationManager.syncNotifications(for: self.allHomeworks)
                }
            }
        }
    }

    private func setupGradesListenersIfNeeded(uid: String, subjects: [Subject]) {
        for subject in subjects {
            let sid = subject.name
            if gradesListeners[sid] != nil { continue }
            let listener = db.collection("users").document(uid).collection("subjects").document(sid).collection("grades")
                .addSnapshotListener { [weak self] snapshot, error in
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
                            let eg = EncryptedGrade(grade: gradeStr, weight: weight, date: date, note: note, halfYear: halfYear)
                            return (gdoc.documentID, eg)
                        }
                        self.encryptedGradesCache[sid] = encGrades
                        self.decryptGradesForSubjectIfPossible(subjectId: sid)
                        self.finishInitialLoadingIfNeeded()
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
                decrypted.append(GradeWithId(id: gid, grade: val, weight: enc.weight, date: enc.date, note: enc.note, halfYear: enc.halfYear))
            }
        }
        gradesBySubject[subjectId] = decrypted
    }

    private func decryptAllCachedGradesIfPossible() {
        for sid in encryptedGradesCache.keys {
            decryptGradesForSubjectIfPossible(subjectId: sid)
        }
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
                    date: exam.date,
                    weight: exam.weight,
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
                    date: exam.date,
                    weight: exam.weight,
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
                return Homework(id: hw.id, groupId: hw.groupId, subjectName: hw.subjectName, subjectKey: hw.subjectKey, title: hw.title, dueDate: hw.dueDate, reminderAt: date, isCompleted: hw.isCompleted, createdAt: hw.createdAt, isShared: true, creatorId: hw.creatorId)
            } else {
                return Homework(id: hw.id, groupId: hw.groupId, subjectName: hw.subjectName, subjectKey: hw.subjectKey, title: hw.title, dueDate: hw.dueDate, reminderAt: nil, isCompleted: hw.isCompleted, createdAt: hw.createdAt, isShared: true, creatorId: hw.creatorId)
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
                creatorId: hw.creatorId
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
                date: exam.date,
                weight: exam.weight,
                reminderAt: exam.reminderAt,
                isCompleted: done,
                createdAt: exam.createdAt,
                isShared: exam.isShared,
                creatorId: exam.creatorId,
                requiresGrade: exam.requiresGrade
            )
        }
    }

    // MARK: - User-Settings + Key

    private func applyUserSettings(from data: [String: Any]) {
        compactView = (data["compactView"] as? Bool) ?? compactView
        animationsEnabled = (data["animationsEnabled"] as? Bool) ?? animationsEnabled

        if let themeVal = data["theme"] as? String, ["default","feminine"].contains(themeVal) {
            theme = themeVal
        }
        if let mode = data["darkModeMode"] as? String, ["system","light","dark"].contains(mode) {
            darkModeMode = mode
        } else if let dm = data["darkMode"] as? Bool {
            darkModeMode = dm ? "dark" : "light"
        } else {
            darkModeMode = "system"
        }
        darkMode = effectiveDarkMode(for: darkModeMode)
        if let gy = data["gradeYear"] as? Int, (gy == 12 || gy == 13) {
            gradeYear = gy
        } else {
            gradeYear = nil
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

        if let gids = data["examGroupIds"] as? [String] {
            examGroupIds = gids
        } else {
            examGroupIds = []
        }
        if let gid = data["examGroupId"] as? String, !gid.isEmpty {
            examGroupId = gid
            if !examGroupIds.contains(gid) { examGroupIds.append(gid) }
        } else {
            examGroupId = examGroupIds.first
        }

        if let gids = data["homeworkGroupIds"] as? [String] {
            homeworkGroupIds = gids
        } else {
            homeworkGroupIds = []
        }
        if let gid = data["homeworkGroupId"] as? String, !gid.isEmpty {
            homeworkGroupId = gid
            if !homeworkGroupIds.contains(gid) { homeworkGroupIds.append(gid) }
        } else {
            homeworkGroupId = homeworkGroupIds.first
        }

        // Ab hier: keine Trennung mehr zwischen Klausur- und Hausaufgabengruppen.
        // Es gibt konzeptionell nur noch eine gemeinsame Gruppe, daher IDs vereinheitlichen.
        if let common = examGroupId ?? homeworkGroupId {
            examGroupId = common
            homeworkGroupId = common
            if !examGroupIds.contains(common) { examGroupIds.append(common) }
            if !homeworkGroupIds.contains(common) { homeworkGroupIds.append(common) }
        }

        let unionIds = Array(Set(examGroupIds + homeworkGroupIds))
        examGroupIds = unionIds
        homeworkGroupIds = unionIds

        // Neue Gruppe-Felder (falls vorhanden)
        if let gids = data["groupIds"] as? [String] {
            groupIds = gids
        } else {
            groupIds = unionIds
        }
    }

    private func deriveKeyIfNeeded(from data: [String: Any], uid: String) async {
        // Leite Key aus encryptionSalt ab, wenn vorhanden
        if let salt = data["encryptionSalt"] as? String {
            do {
                let key = try CryptoService.deriveKeyFromPassword(password: uid, saltBase64: salt, iterations: 150_000)
                let keyChanged = (self.encryptionKey == nil) // oder man könnte Keyvergleich machen
                self.encryptionKey = key
                if keyChanged {
                    // Sobald Key gesetzt, alle Caches entschlüsseln
                    self.decryptAllCachedGradesIfPossible()
                }
            } catch {
                self.encryptionKey = nil
                // Ohne Key bleiben Noten leer
                self.decryptAllCachedGradesIfPossible()
            }
        } else {
            // Kein Salt -> kein Key
            self.encryptionKey = nil
            self.decryptAllCachedGradesIfPossible()
        }
    }

    private func loadLocalPreferences() {
        let defaults = UserDefaults.standard

        if let storedTheme = defaults.string(forKey: "grades_theme"),
           ["default", "feminine"].contains(storedTheme) {
            theme = storedTheme
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
        if defaults.object(forKey: "grades_compactView") != nil {
            compactView = defaults.bool(forKey: "grades_compactView")
        }
        if defaults.object(forKey: "grades_animationsEnabled") != nil {
            animationsEnabled = defaults.bool(forKey: "grades_animationsEnabled")
        }
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
                Task { @MainActor in
                    guard let self else { return }
                    let docs = snapshot?.documents ?? []
                    let list: [Exam] = docs.compactMap { doc in
                        let data = doc.data()
                        let subjectName = data["subjectName"] as? String ?? ""
                        let subjectKey = data["subjectKey"] as? String
                        let title = data["title"] as? String ?? ""
                        let createdTs = data["createdAt"] as? Timestamp
                        let createdAt = createdTs?.dateValue() ?? Date()
                        guard let dateTs = data["date"] as? Timestamp else { return nil }
                        let date = dateTs.dateValue()
                        let weight = data["weight"] as? Int
                        let creatorId = data["creatorId"] as? String
                        let requiresGrade = data["requiresGrade"] as? Bool
                        return Exam(
                            id: doc.documentID,
                            groupId: gid,
                            subjectName: subjectName,
                            subjectKey: subjectKey,
                            title: title,
                            date: date,
                            weight: weight,
                            reminderAt: nil,
                            isCompleted: false,
                            createdAt: createdAt,
                            isShared: true,
                            creatorId: creatorId,
                            requiresGrade: requiresGrade
                        )
                    }
                    self.sharedExams = list
                    self.applySharedExamUserReminders()
                    self.applySharedExamUserCompletion()
                    ExamNotificationManager.syncNotifications(for: self.allExams)
                    await self.loadExamGroupName()
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
        sharedHomeworksListener = db.collection("homeworkGroups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, _ in
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
        sharedHomeworksListener = db.collection("homeworkGroups").document(gid).collection("homeworks").order(by: "createdAt", descending: false).addSnapshotListener { [weak self] snapshot, error in
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
                    return Homework(id: doc.documentID, groupId: gid, subjectName: subjectName, subjectKey: subjectKey, title: title, dueDate: dueDate, reminderAt: nil, isCompleted: false, createdAt: createdAt, isShared: true, creatorId: creatorId)
                }
                self.sharedHomeworks = list
                self.applySharedHomeworkUserCompletion()
                self.applySharedHomeworkUserReminders()
                HomeworkNotificationManager.syncNotifications(for: self.allHomeworks)
            }
        }
    }

    func createExamGroupIfNeeded(name: String? = nil) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        // Standard: alle aktuell verfügbaren Fächer, die noch nicht in anderen Gruppen gemappt sind
        let selectable = availableSubjectsForNewGroup().map { $0.name }
        return try await createSharedGroup(name: name ?? "Gruppe", subjects: selectable)
    }

    // Neue zentrale Gruppenerstellung (/groups)
    func createSharedGroup(name: String, subjects: [String]) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let code = generateExamGroupCode()

        // Gruppe anlegen
        let groupRef = db.collection("groups").document(code)
        try await groupRef.setData([
            "ownerId": uid,
            "createdAt": Date(),
            "name": name as Any
        ], merge: true)

        try await db.collection("users").document(uid).updateData([
            "groupIds": FieldValue.arrayUnion([code]),
            "examGroupIds": FieldValue.arrayUnion([code]),      // Kompatibilität
            "homeworkGroupIds": FieldValue.arrayUnion([code]),  // Kompatibilität
            "examGroupId": code,
            "homeworkGroupId": code
        ])

        let union = Array(Set(groupIds + [code]))
        groupIds = union
        examGroupIds = union
        homeworkGroupIds = union
        groupNames[code] = name
        examGroupId = code
        homeworkGroupId = code

        // Seed group subjects from ausgewählten Subjects
        var seededSubjects: [GroupSubject] = []
        var mapping: [String: String] = [:]
        for name in subjects where !name.isEmpty {
            guard let subj = self.subjects.first(where: { $0.name == name }) else { continue }
            let sid = slugifySubjectName(subj.name)
            let payload: [String: Any] = [
                "name": subj.name,
                "type": subj.type,
                "alias": subj.alias as Any
            ]
            try await db.collection("groups").document(code).collection("subjects").document(sid).setData(payload, merge: true)
            seededSubjects.append(GroupSubject(id: sid, name: subj.name, type: subj.type, alias: subj.alias))
            mapping[sid] = subj.name
        }
        groupSubjectsByGroup[code] = seededSubjects
        groupSubjectMappings[code] = mapping
        try await db.collection("users").document(uid).collection("groupMappings").document(code).setData(["map": mapping], merge: true)

        updateGroupObservers(uid: uid)

        return code
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

        let code = normalizedExamGroupCode(rawCode)
        guard !code.isEmpty else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Gruppencode"])
        }

        // Sicherstellen, dass die Gruppe existiert
        let groupRef = db.collection("groups").document(code)
        let snap = try await groupRef.getDocument()
        if !snap.exists {
            try await groupRef.setData([
                "ownerId": uid,
                "createdAt": Date()
            ])
        }

        // User-Dokument aktualisieren (beide Arrays + aktive IDs)
        try await db.collection("users").document(uid).updateData([
            "groupIds": FieldValue.arrayUnion([code]),
            "examGroupIds": FieldValue.arrayUnion([code]),
            "homeworkGroupIds": FieldValue.arrayUnion([code]),
            "examGroupId": code,
            "homeworkGroupId": code
        ])

        let union = Array(Set(groupIds + [code]))
        groupIds = union
        examGroupIds = union
        homeworkGroupIds = union
        examGroupId = code
        homeworkGroupId = code

        // Listener aktualisieren
        updateGroupObservers(uid: uid)

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
            examGroupName = nil
        }
    }

    func leaveHomeworkGroup() async {
        await leaveSharedGroup()
    }

    func leaveSharedGroup(code: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let target = code ?? examGroupId ?? homeworkGroupId
        guard let target else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "groupIds": FieldValue.arrayRemove([target]),
                "examGroupIds": FieldValue.arrayRemove([target]),
                "homeworkGroupIds": FieldValue.arrayRemove([target])
            ])
        } catch {
            // optional loggen
        }

        examGroupIds.removeAll { $0 == target }
        homeworkGroupIds.removeAll { $0 == target }
        groupIds.removeAll { $0 == target }

        let remaining = Array(Set(groupIds))
        let newActive = remaining.first

        if let newActive {
            do {
                try await db.collection("users").document(uid).updateData([
                    "examGroupId": newActive,
                    "homeworkGroupId": newActive
                ])
            } catch {
                // optional loggen
            }
            examGroupId = newActive
            homeworkGroupId = newActive
        } else {
            do {
                try await db.collection("users").document(uid).updateData([
                    "examGroupId": FieldValue.delete(),
                    "homeworkGroupId": FieldValue.delete()
                ])
            } catch {
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

        updateGroupObservers(uid: uid)

        ExamNotificationManager.syncNotifications(for: allExams)
        HomeworkNotificationManager.syncNotifications(for: allHomeworks)
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
                try await db.collection("users").document(uid).updateData([
                    "examGroupId": code,
                    "homeworkGroupId": code
                ])
            } catch {
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
            // optional loggen
        }
    }

    // MARK: - Write

    func addSubjectToFirestore(name: String, type: Int, date: Date) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }
        let docRef = db.collection("users").document(uid).collection("subjects").document(name)
        try await docRef.setData([
            "type": type,
            "date": date
        ], merge: true)

        // Lokalen State optional optimistisch aktualisieren (Listener korrigiert ggf.)
        let s = Subject(name: name, type: type, date: date)
        if !subjects.contains(where: { $0.name == name }) {
            subjects.append(s)
        } else {
            subjects = subjects.map { $0.name == name ? s : $0 }
        }
    }

    func addExamToFirestore(subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?, requiresGrade: Bool? = true) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let now = Date()
        let ref = db.collection("users")
            .document(uid)
            .collection("exams")
            .document()

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date,
            "isCompleted": false,
            "createdAt": now,
            "creatorId": uid
        ]
        if let weight {
            payload["weight"] = weight
        }
        if let reminderAt {
            payload["reminderAt"] = reminderAt
        }
        if let requiresGrade {
            payload["requiresGrade"] = requiresGrade
        }

        try await ref.setData(payload)
    }

    // Neue Variante: verteilt automatisch in alle passenden Gruppen (nach Subject-Mapping)
    func addExamToGroups(subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?, requiresGrade: Bool? = true) async throws -> [(groupId: String, docId: String)] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let gids = targetGroupIds(forLocalSubject: subjectName)
        guard !gids.isEmpty else { return [] }

        let now = Date()
        let subjectKey = slugifySubjectName(subjectName)
        var created: [(String, String)] = []
        for gid in gids {
            let ref = db.collection("groups").document(gid).collection("exams").document()
            var payload: [String: Any] = [
                "subjectName": subjectName,
                "subjectKey": subjectKey,
                "title": title,
                "date": date,
                "createdAt": now,
                "creatorId": uid
            ]
            if let weight { payload["weight"] = weight }
            if let requiresGrade { payload["requiresGrade"] = requiresGrade }
            try await ref.setData(payload)
            created.append((gid, ref.documentID))
        }
        return created
    }
    
    func addHomeworkToFirestore(subjectName: String, title: String, dueDate: Date?, reminderAt: Date?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let now = Date()
        let ref = db.collection("users")
            .document(uid)
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

        try await ref.setData(payload)
    }
    
    func addHomeworkToGroups(subjectName: String, title: String, dueDate: Date?, reminderAt: Date?) async throws -> [(groupId: String, docId: String)] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let gids = targetGroupIds(forLocalSubject: subjectName)
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

    func addGradeToFirestore(subjectId: String, grade: Double, weight: Double, date: Date, note: String?, halfYear: Int?, using key: SymmetricKey) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let encrypted = try CryptoService.encryptString(String(grade), key: key)
        let gradesRef = db.collection("users").document(uid).collection("subjects").document(subjectId).collection("grades")
        let newRef = gradesRef.document()
        try await newRef.setData([
            "grade": encrypted,
            "weight": weight,
            "date": date,
            "note": note as Any,
            "halfYear": halfYear as Any
        ])

        // Optimistisch lokal (Listener setzt danach korrekt)
        var list = gradesBySubject[subjectId] ?? []
        list.append(GradeWithId(id: newRef.documentID, grade: grade, weight: weight, date: date, note: note, halfYear: halfYear))
        gradesBySubject[subjectId] = list

        return newRef.documentID
    }

    func updateHomeworkInFirestore(id: String, subjectName: String, title: String, dueDate: Date?, reminderAt: Date?, isCompleted: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let ref = db.collection("users")
            .document(uid)
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

    func updateExamInFirestore(id: String, subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?, isCompleted: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let ref = db.collection("users")
            .document(uid)
            .collection("exams")
            .document(id)

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date,
            "isCompleted": isCompleted
        ]
        if let weight {
            payload["weight"] = weight
        } else {
            payload["weight"] = NSNull()
        }
        if let reminderAt {
            payload["reminderAt"] = reminderAt
        } else {
            payload["reminderAt"] = NSNull()
        }

        try await ref.updateData(payload)
    }

    func updateSharedExamInGroup(groupId: String, id: String, subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?, requiresGrade: Bool? = nil) async throws {
        let ref = db.collection("groups").document(groupId).collection("exams").document(id)

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date
        ]
        if let weight {
            payload["weight"] = weight
        } else {
            payload["weight"] = NSNull()
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
        let gid = groupId ?? sharedExams.first(where: { $0.id == examId })?.groupId
        let ref = db.collection("users")
            .document(uid)
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
    
    func setUserCompletedForSharedExam(examId: String, completed: Bool, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let gid = groupId ?? sharedExams.first(where: { $0.id == examId })?.groupId
        let ref = db.collection("users").document(uid).collection("examGroupCompleted").document(compoundId(gid: gid, docId: examId))
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
            ExamNotificationManager.syncNotifications(for: allExams)
        } catch {
            // optional loggen
        }
    }
    
    func setUserReminderForSharedHomework(homeworkId: String, reminderAt: Date?, groupId: String? = nil) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let gid = groupId ?? sharedHomeworks.first(where: { $0.id == homeworkId })?.groupId
        let ref = db.collection("users").document(uid).collection("homeworkGroupReminders").document(compoundId(gid: gid, docId: homeworkId))
        if let reminderAt {
            try await ref.setData(["reminderAt": reminderAt])
        } else {
            try await ref.delete()
        }
    }

    func setHomeworkCompleted(id: String, completed: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docRef = db.collection("users")
            .document(uid)
            .collection("homeworks")
            .document(id)
        do {
            try await docRef.updateData([
                "isCompleted": completed
            ])
        } catch {
            // optional loggen
        }
    }
    
    func setUserCompletedForSharedHomework(homeworkId: String, completed: Bool, groupId: String? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let gid = groupId ?? sharedHomeworks.first(where: { $0.id == homeworkId })?.groupId
        let ref = db.collection("users").document(uid).collection("homeworkGroupCompleted").document(compoundId(gid: gid, docId: homeworkId))
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
            HomeworkNotificationManager.syncNotifications(for: allHomeworks)
        } catch {
            // optional loggen
        }
    }

    func setExamCompleted(id: String, completed: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docRef = db.collection("users")
            .document(uid)
            .collection("exams")
            .document(id)
        do {
            try await docRef.updateData([
                "isCompleted": completed
            ])
        } catch {
            // optional loggen
        }
    }

    func setFachreferatToFirestore(subjectName: String, grade: Double, date: Date, note: String?, using key: SymmetricKey) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let encrypted = try CryptoService.encryptString(String(grade), key: key)
        let docRef = db.collection("users").document(uid).collection("fachreferat").document("current")
        try await docRef.setData([
            "grade": encrypted,
            "subjectName": subjectName,
            "date": date,
            "note": note as Any
        ], merge: true)

        // Optimistisch lokal (Listener setzt danach korrekt)
        fachreferat = Fachreferat(id: "current", grade: grade, subjectName: subjectName, date: date, note: note)
    }

    // MARK: - Update/Delete Grades

    func updateGradeInFirestore(subjectId: String, gradeId: String, grade: Double, weight: Double, date: Date, note: String?, halfYear: Int?, using key: SymmetricKey) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let encrypted = try CryptoService.encryptString(String(grade), key: key)
        let gradeDocRef = db.collection("users").document(uid).collection("subjects").document(subjectId).collection("grades").document(gradeId)
        try await gradeDocRef.updateData([
            "grade": encrypted,
            "weight": weight,
            "date": date,
            "note": note as Any,
            "halfYear": halfYear as Any
        ])

        // Optimistisch lokal (Listener setzt danach korrekt)
        var list = gradesBySubject[subjectId] ?? []
        if let idx = list.firstIndex(where: { $0.id == gradeId }) {
            list[idx] = GradeWithId(id: gradeId, grade: grade, weight: weight, date: date, note: note, halfYear: halfYear)
            gradesBySubject[subjectId] = list
        }
    }

    func updateGradeNoteInFirestore(subjectId: String, gradeId: String, note: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let gradeDocRef = db.collection("users").document(uid).collection("subjects").document(subjectId).collection("grades").document(gradeId)
        try await gradeDocRef.updateData([
            "note": note as Any
        ])

        // Optimistisch lokal
        var list = gradesBySubject[subjectId] ?? []
        if let idx = list.firstIndex(where: { $0.id == gradeId }) {
            let g = list[idx]
            list[idx] = GradeWithId(id: g.id, grade: g.grade, weight: g.weight, date: g.date, note: note, halfYear: g.halfYear)
            gradesBySubject[subjectId] = list
        }
    }

    func deleteGradeFromFirestore(subjectId: String, gradeId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"]) }

        let gradeDocRef = db.collection("users").document(uid).collection("subjects").document(subjectId).collection("grades").document(gradeId)
        try await gradeDocRef.delete()

        // Optimistisch lokal
        var list = gradesBySubject[subjectId] ?? []
        list.removeAll { $0.id == gradeId }
        gradesBySubject[subjectId] = list
    }
    
    func deleteSharedHomeworkFromGroup(id: String) async {
        guard let gid = homeworkGroupId, !gid.isEmpty else { return }
        let docRef = db.collection("homeworkGroups").document(gid).collection("homeworks").document(id)
        do {
            try await docRef.delete()
        } catch {
            // optional loggen
        }
    }

    // MARK: - Settings

    func updateSubjectSortPreferences(mode: SubjectSortMode, order: [String]) async {
        subjectSortMode = mode
        subjectSortOrder = order
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "subjectSortMode": mode.rawValue,
                "subjectSortOrder": order
            ])
        } catch {
            // optional loggen
        }
    }

    func calculateGradeWeightForOverall(subject: Subject, grade: Grade) -> Double {
        let t = subject.type
        if t == 1 {
            return (grade.weight == 3 ? 2 : (grade.weight == 2 ? 2 : 1))
        }
        if t == 0 {
            return (grade.weight == 3 ? 2 : (grade.weight == 1 ? 2 : 1))
        }
        return 1
    }

    func updateUserDisplayName(name: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "name": name,
                "displayName": name
            ])
        } catch {
            // optional loggen
        }
    }

    func updatePreferences(theme: String? = nil, darkMode: Bool? = nil, darkModeMode: String? = nil, compactView: Bool? = nil, animationsEnabled: Bool? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // lokalen State vorab aktualisieren (optimistic UI)
        if let theme { self.theme = theme }
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

        // lokal speichern, damit Einstellungen direkt beim App-Start verfügbar sind
        let defaults = UserDefaults.standard
        if let theme { defaults.set(theme, forKey: "grades_theme") }
        if let darkMode { defaults.set(darkMode, forKey: "grades_darkMode") }
        if let mode = darkModeMode { defaults.set(mode, forKey: "grades_darkModeMode") }
        if let compactView { defaults.set(compactView, forKey: "grades_compactView") }
        if let animationsEnabled { defaults.set(animationsEnabled, forKey: "grades_animationsEnabled") }

        var payload: [String: Any] = [:]
        if let theme { payload["theme"] = theme }
        if let darkMode { payload["darkMode"] = darkMode }
        if let mode = darkModeMode { payload["darkModeMode"] = mode }
        if let compactView { payload["compactView"] = compactView }
        if let animationsEnabled { payload["animationsEnabled"] = animationsEnabled }

        guard !payload.isEmpty else { return }
        do {
            try await db.collection("users").document(uid).updateData(payload)
        } catch {
            // optional rollback/loggen
        }
    }

    func updateGradeYear(_ year: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        self.gradeYear = year
        do {
            try await db.collection("users").document(uid).updateData([
                "gradeYear": year
            ])
        } catch {
            // optional loggen
        }
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

    func updateSubjectExamFlags(subjectName: String, examSubject: Bool, examType: ExamType) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid)
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
                                   oralExamPointsEncrypted: s.oralExamPointsEncrypted)
                }
                return s
            }
        } catch {
            // optional loggen
        }
    }

    func updateDroppedHalfYear(subjectName: String, value: Int?) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid)
                .collection("subjects")
                .document(subjectName)
                .updateData([
                    "droppedHalfYear": value as Any
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
                                   droppedHalfYear: value,
                                   examSubject: s.examSubject,
                                   examType: s.examType,
                                   examPointsEncrypted: s.examPointsEncrypted,
                                   writtenExamPointsEncrypted: s.writtenExamPointsEncrypted,
                                   oralExamPointsEncrypted: s.oralExamPointsEncrypted)
                }
                return s
            }
        } catch {
            // optional loggen
        }
    }

    func deleteHomeworkFromFirestore(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docRef = db.collection("users")
            .document(uid)
            .collection("homeworks")
            .document(id)
        do {
            try await docRef.delete()
        } catch {
            // optional loggen
        }
    }

    func deleteExamFromFirestore(id: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let docRef = db.collection("users")
            .document(uid)
            .collection("exams")
            .document(id)
        do {
            try await docRef.delete()
        } catch {
            // optional loggen
        }
    }

    func deleteSharedExamFromGroup(groupId: String, id: String) async {
        let docRef = db.collection("groups").document(groupId).collection("exams").document(id)
        do {
            try await docRef.delete()
        } catch {
            // optional loggen
        }
    }

    func deleteSharedHomeworkFromGroup(groupId: String, id: String) async {
        let docRef = db.collection("groups").document(groupId).collection("homeworks").document(id)
        do {
            try await docRef.delete()
        } catch {
            // optional loggen
        }
    }

    func deleteSubjectFromFirestore(subjectName: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let subjectRef = db.collection("users").document(uid).collection("subjects").document(subjectName)
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
            // optional: Fehlerbehandlung oder Logging
        }
    }

    // MARK: - Helpers for group subjects and mappings

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
        examGroupSubjectsListener = db.collection("examGroups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, _ in
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
        homeworkGroupSubjectsListener = db.collection("homeworkGroups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, _ in
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
        guard let gid = examGroupId else {
            examSubjectMappingListener?.remove(); examSubjectMappingListener = nil; examSubjectMappingGid = nil; examSubjectMapping = [:]; return
        }
        if examSubjectMappingListener != nil { return }
        examSubjectMappingGid = gid
        examSubjectMappingListener = db.collection("users").document(uid).collection("subjectMappings").document(gid).addSnapshotListener { [weak self] snap, _ in
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
        guard let gid = homeworkGroupId else {
            homeworkSubjectMappingListener?.remove(); homeworkSubjectMappingListener = nil; homeworkSubjectMappingGid = nil; homeworkSubjectMapping = [:]; return
        }
        if homeworkSubjectMappingListener != nil { return }
        homeworkSubjectMappingGid = gid
        homeworkSubjectMappingListener = db.collection("users").document(uid).collection("subjectMappings").document(gid).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self else { return }
                let data = snap?.data() ?? [:]
                self.homeworkSubjectMapping = data["map"] as? [String: String] ?? [:]
            }
        }
    }

    // MARK: - Neue Gruppen-Listener (/groups)

    private func updateGroupObservers(uid: String) {
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
        }

        // Starte Listener für aktuelle Gruppen
        for gid in current {
            startGroupSubjectsListener(for: gid)
            startGroupMappingsListener(for: gid, uid: uid)
            startGroupNameListener(for: gid)
            startGroupExamsListener(for: gid)
            startGroupHomeworksListener(for: gid)
        }
    }

    private func startGroupSubjectsListener(for gid: String) {
        if groupSubjectsListeners[gid] != nil { return }
        groupSubjectsListeners[gid] = db.collection("groups").document(gid).collection("subjects").addSnapshotListener { [weak self] snap, _ in
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

    private func startGroupMappingsListener(for gid: String, uid: String) {
        if groupMappingsListeners[gid] != nil { return }
        groupMappingsListeners[gid] = db.collection("users").document(uid).collection("groupMappings").document(gid).addSnapshotListener { [weak self] snap, _ in
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
        groupNameListeners[gid] = db.collection("groups").document(gid).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self else { return }
                if let data = snap?.data(), let name = data["name"] as? String {
                    self.groupNames[gid] = name
                } else {
                    self.groupNames.removeValue(forKey: gid)
                }
            }
        }
    }

    private func startGroupExamsListener(for gid: String) {
        if groupExamsListeners[gid] != nil { return }
        groupExamsListeners[gid] = db.collection("groups").document(gid).collection("exams").order(by: "createdAt", descending: false).addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self else { return }
                let docs = snap?.documents ?? []
                let list: [Exam] = docs.compactMap { doc in
                    let data = doc.data()
                    let subjectName = data["subjectName"] as? String ?? ""
                    let subjectKey = data["subjectKey"] as? String
                    let title = data["title"] as? String ?? ""
                    let createdTs = data["createdAt"] as? Timestamp
                    let createdAt = createdTs?.dateValue() ?? Date()
                    guard let dateTs = data["date"] as? Timestamp else { return nil }
                    let date = dateTs.dateValue()
                    let weight = data["weight"] as? Int
                    let creatorId = data["creatorId"] as? String
                    let requiresGrade = data["requiresGrade"] as? Bool
                    return Exam(
                        id: doc.documentID,
                        groupId: gid,
                        subjectName: subjectName,
                        subjectKey: subjectKey,
                        title: title,
                        date: date,
                        weight: weight,
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
        groupHomeworksListeners[gid] = db.collection("groups").document(gid).collection("homeworks").order(by: "createdAt", descending: false).addSnapshotListener { [weak self] snap, _ in
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
                        creatorId: creatorId
                    )
                }
                self.groupHomeworksByGroup[gid] = list
                self.recomputeSharedCollections()
            }
        }
    }

    private func recomputeSharedCollections() {
        sharedExams = groupExamsByGroup.values.flatMap { $0 }
        sharedHomeworks = groupHomeworksByGroup.values.flatMap { $0 }
        HomeworkNotificationManager.syncNotifications(for: allHomeworks)
        ExamNotificationManager.syncNotifications(for: allExams)
    }

    // MARK: - Gruppierung & Targets

    func availableSubjectsForNewGroup() -> [Subject] {
        let usedLocal = Set(groupSubjectMappings.values.flatMap { $0.values })
        return subjects.filter { $0.name != "Fachreferat" && !usedLocal.contains($0.name) }
    }

    private func targetGroupIds(forLocalSubject subjectName: String) -> [String] {
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
            try await db.collection("users").document(uid).collection("groupMappings").document(groupId).setData(["map": map], merge: true)
            await MainActor.run { self.groupSubjectMappings[groupId] = map }
        } catch {
            // optional loggen
        }
    }

}
