import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import CryptoKit

@MainActor
final class GradesStore: ObservableObject {
    @Published var subjects: [Subject] = []
    @Published var gradesBySubject: [String: [GradeWithId]] = [:] // Key = subjectId (name)
    @Published var fachreferat: Fachreferat?
    @Published var homeworks: [Homework] = []
    @Published var exams: [Exam] = []            // Eigene Prüfungen
    @Published var sharedExams: [Exam] = []      // Prüfungen aus gemeinsamer Gruppe
    @Published var examGroupId: String? = nil    // Aktuelle Prüfungsgruppe
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
    @Published var gradeYear: Int? = nil // 12 oder 13

    private let db = Firestore.firestore()

    // Live-Listener
    private var userDocListener: ListenerRegistration?
    private var subjectsListener: ListenerRegistration?
    private var fachreferatListener: ListenerRegistration?
    private var homeworksListener: ListenerRegistration?
    private var examsListener: ListenerRegistration?
    private var sharedExamsListener: ListenerRegistration?
    private var sharedExamUserSettingsListener: ListenerRegistration?
    private var gradesListeners: [String: ListenerRegistration] = [:] // subjectId -> listener

    // Cache verschlüsselter Noten, damit wir bei Key-Verfügbarkeit sofort entschlüsseln können
    private var encryptedGradesCache: [String: [(id: String, data: EncryptedGrade)]] = [:]

    private var isListening: Bool = false
    private var isSettingUp: Bool = false
    private var sharedExamsGroupId: String?
    private var sharedExamUserReminders: [String: Date] = [:] // examId -> user-spezifische Erinnerung

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
        for (_, l) in gradesListeners {
            l.remove()
        }
        gradesListeners = [:]
        encryptedGradesCache = [:]
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
        examGroupId = nil
        sharedExamUserReminders = [:]
        subjectSortMode = .name
        subjectSortOrder = []
        gradeYear = nil
        isLoading = false
        loadingLabel = ""
        progress = 0
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
                            return Homework(
                                id: doc.documentID,
                                subjectName: subjectName,
                                title: title,
                                dueDate: dueDate,
                                reminderAt: reminderAt,
                                isCompleted: isCompleted,
                                createdAt: createdAt
                            )
                        }
                        self.homeworks = list
                        HomeworkNotificationManager.syncNotifications(for: list)
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
                            return Exam(
                                id: doc.documentID,
                                subjectName: subjectName,
                                title: title,
                                date: date,
                                weight: weight,
                                reminderAt: reminderAt,
                                isCompleted: isCompleted,
                                createdAt: createdAt,
                                isShared: false,
                                creatorId: creatorId
                            )
                        }
                        self.exams = list
                        ExamNotificationManager.syncNotifications(for: self.allExams)
                    }
                }
        }

        // Gemeinsame Prüfungs-Listener (Group)
        updateSharedExamsListenerIfNeeded()

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

    private func applySharedExamUserReminders() {
        guard !sharedExams.isEmpty else { return }
        sharedExams = sharedExams.map { exam in
            if let date = sharedExamUserReminders[exam.id] {
                return Exam(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    title: exam.title,
                    date: exam.date,
                    weight: exam.weight,
                    reminderAt: date,
                    isCompleted: exam.isCompleted,
                    createdAt: exam.createdAt,
                    isShared: exam.isShared,
                    creatorId: exam.creatorId
                )
            } else {
                return Exam(
                    id: exam.id,
                    subjectName: exam.subjectName,
                    title: exam.title,
                    date: exam.date,
                    weight: exam.weight,
                    reminderAt: nil,
                    isCompleted: exam.isCompleted,
                    createdAt: exam.createdAt,
                    isShared: exam.isShared,
                    creatorId: exam.creatorId
                )
            }
        }
    }

    // MARK: - User-Settings + Key

    private func applyUserSettings(from data: [String: Any]) {
        compactView = (data["compactView"] as? Bool) ?? compactView
        animationsEnabled = (data["animationsEnabled"] as? Bool) ?? animationsEnabled

        if let themeVal = data["theme"] as? String, ["default","feminine"].contains(themeVal) {
            theme = themeVal
        }
        if let dm = data["darkMode"] as? Bool {
            darkMode = dm
        }
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

        if let gid = data["examGroupId"] as? String, !gid.isEmpty {
            examGroupId = gid
        } else {
            examGroupId = nil
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
        if defaults.object(forKey: "grades_darkMode") != nil {
            darkMode = defaults.bool(forKey: "grades_darkMode")
        }
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
                        let title = data["title"] as? String ?? ""
                        let createdTs = data["createdAt"] as? Timestamp
                        let createdAt = createdTs?.dateValue() ?? Date()
                        guard let dateTs = data["date"] as? Timestamp else { return nil }
                        let date = dateTs.dateValue()
                        let weight = data["weight"] as? Int
                        let creatorId = data["creatorId"] as? String
                        return Exam(
                            id: doc.documentID,
                            subjectName: subjectName,
                            title: title,
                            date: date,
                            weight: weight,
                            reminderAt: nil,
                            isCompleted: false,
                            createdAt: createdAt,
                            isShared: true,
                            creatorId: creatorId
                        )
                    }
                    self.sharedExams = list
                    self.applySharedExamUserReminders()
                    ExamNotificationManager.syncNotifications(for: self.allExams)
                }
            }
    }

    func createExamGroupIfNeeded() async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        if let existing = examGroupId, !existing.isEmpty {
            return existing
        }

        let code = generateExamGroupCode()
        let groupRef = db.collection("examGroups").document(code)
        try await groupRef.setData([
            "ownerId": uid,
            "createdAt": Date()
        ], merge: true)

        try await db.collection("users").document(uid).updateData([
            "examGroupId": code
        ])

        examGroupId = code
        updateSharedExamsListenerIfNeeded()
        return code
    }

    func joinExamGroup(with rawCode: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }

        let code = normalizedExamGroupCode(rawCode)
        guard !code.isEmpty else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ungültiger Gruppencode"])
        }

        let groupRef = db.collection("examGroups").document(code)
        let snap = try await groupRef.getDocument()
        if !snap.exists {
            try await groupRef.setData([
                "ownerId": uid,
                "createdAt": Date()
            ])
        }

        try await db.collection("users").document(uid).updateData([
            "examGroupId": code
        ])

        examGroupId = code
        updateSharedExamsListenerIfNeeded()
    }

    func leaveExamGroup() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "examGroupId": FieldValue.delete()
            ])
        } catch {
            // optional loggen
        }

        examGroupId = nil
        sharedExamsListener?.remove()
        sharedExamsListener = nil
        sharedExamsGroupId = nil
        sharedExams = []
        sharedExamUserReminders = [:]
        ExamNotificationManager.syncNotifications(for: allExams)
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

    func addExamToFirestore(subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?) async throws {
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

        try await ref.setData(payload)
    }

    func addExamToSharedGroup(subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?) async throws -> String {
        guard let gid = examGroupId, !gid.isEmpty else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Keine Klausurgruppe ausgewählt"])
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let now = Date()
        let ref = db.collection("examGroups")
            .document(gid)
            .collection("exams")
            .document()

        var payload: [String: Any] = [
            "subjectName": subjectName,
            "title": title,
            "date": date,
            "createdAt": now,
            "creatorId": uid
        ]
        if let weight {
            payload["weight"] = weight
        }
        // reminderAt wird pro Benutzer separat gespeichert

        try await ref.setData(payload)
        return ref.documentID
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

    func updateSharedExamInGroup(id: String, subjectName: String, title: String, date: Date, weight: Int?, reminderAt: Date?) async throws {
        guard let gid = examGroupId, !gid.isEmpty else {
            throw NSError(domain: "GradesStore", code: -2, userInfo: [NSLocalizedDescriptionKey: "Keine Klausurgruppe ausgewählt"])
        }
        let ref = db.collection("examGroups")
            .document(gid)
            .collection("exams")
            .document(id)

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
        try await ref.updateData(payload)
    }

    func setUserReminderForSharedExam(examId: String, reminderAt: Date?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GradesStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Kein Nutzer"])
        }
        let ref = db.collection("users")
            .document(uid)
            .collection("examGroupReminders")
            .document(examId)

        if let reminderAt {
            try await ref.setData([
                "reminderAt": reminderAt
            ])
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

    func updatePreferences(theme: String? = nil, darkMode: Bool? = nil, compactView: Bool? = nil, animationsEnabled: Bool? = nil) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // lokalen State vorab aktualisieren (optimistic UI)
        if let theme { self.theme = theme }
        if let darkMode { self.darkMode = darkMode }
        if let compactView { self.compactView = compactView }
        if let animationsEnabled { self.animationsEnabled = animationsEnabled }

        // lokal speichern, damit Einstellungen direkt beim App-Start verfügbar sind
        let defaults = UserDefaults.standard
        if let theme { defaults.set(theme, forKey: "grades_theme") }
        if let darkMode { defaults.set(darkMode, forKey: "grades_darkMode") }
        if let compactView { defaults.set(compactView, forKey: "grades_compactView") }
        if let animationsEnabled { defaults.set(animationsEnabled, forKey: "grades_animationsEnabled") }

        var payload: [String: Any] = [:]
        if let theme { payload["theme"] = theme }
        if let darkMode { payload["darkMode"] = darkMode }
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

    func deleteSharedExamFromGroup(id: String) async {
        guard let gid = examGroupId, !gid.isEmpty else { return }
        let docRef = db.collection("examGroups")
            .document(gid)
            .collection("exams")
            .document(id)
        do {
            try await docRef.delete()
        } catch {
            // optional loggen
        }
    }
}
