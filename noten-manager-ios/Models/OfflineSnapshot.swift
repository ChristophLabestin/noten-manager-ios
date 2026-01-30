import Foundation


struct OfflineSnapshot: Sendable {
    let userId: String
    let capturedAt: Date
    let activeSchoolYearId: String?
    let encryptionSalt: String?
    let subjects: [Subject]
    let gradesBySubject: [String: [GradeWithId]]
    let fachreferat: Fachreferat?
    let seminarPerformance: SeminarPerformance?
    let practicalPerformance: PracticalPerformance?
    let homeworks: [Homework]
    let exams: [Exam]
    let sharedExams: [Exam]
    let sharedHomeworks: [Homework]
    let examGroupId: String?
    let homeworkGroupId: String?
    let groupIds: [String]
    let groupNames: [String: String]
    // Nested dictionary decoding can sometimes be tricky with Sendable/Isolation inference
    let groupSubjectMappings: [String: [String: String]]
    let groupExamsByGroup: [String: [Exam]]
    let groupHomeworksByGroup: [String: [Homework]]
    let schoolYears: [String]
    let gradeYear: Int?
    let schoolType: SchoolType
    let subjectSortMode: SubjectSortMode
    let subjectSortOrder: [String]
    let compactView: Bool
    let animationsEnabled: Bool
    let showHolidayHints: Bool?
    let theme: String
    let themeIntensity: Double?
    let appIcon: String?
    let darkMode: Bool
    let darkModeMode: String
    let homeworkReminderHour: Int
    let homeworkReminderMinute: Int
    let standardRemindersEnabled: Bool?
    let supportNotificationUpdates: Bool?
    let supportNotificationAccess: Bool?
    let customNotificationsEnabled: Bool?
    let broadcastNotificationsEnabled: Bool?
    let pendingGrades: [PendingGrade]
    let pendingFachreferat: PendingFachreferat?
    let pendingSeminar: PendingSeminarPerformance?
    let pendingGradeChanges: [PendingGradeChange]
    let pendingSubjectChanges: [PendingSubjectChange]
    let pendingExamChanges: [PendingExamChange]
    let pendingHomeworkChanges: [PendingHomeworkChange]
    let pendingSharedExamUserChanges: [PendingSharedExamUserChange]
    let pendingSharedHomeworkUserChanges: [PendingSharedHomeworkUserChange]
    
    private enum CodingKeys: String, CodingKey {
        case userId, capturedAt, activeSchoolYearId, encryptionSalt
        case subjects, gradesBySubject, fachreferat, seminarPerformance, practicalPerformance
        case homeworks, exams, sharedExams, sharedHomeworks
        case examGroupId, homeworkGroupId, groupIds, groupNames, groupSubjectMappings
        case groupExamsByGroup, groupHomeworksByGroup
        case schoolYears, gradeYear, schoolType
        case subjectSortMode, subjectSortOrder
        case compactView, animationsEnabled, showHolidayHints
    case theme, themeIntensity, appIcon
        case darkMode, darkModeMode
        case homeworkReminderHour, homeworkReminderMinute, standardRemindersEnabled
        case supportNotificationUpdates, supportNotificationAccess
        case customNotificationsEnabled, broadcastNotificationsEnabled
        case pendingGrades, pendingFachreferat, pendingSeminar
        case pendingGradeChanges, pendingSubjectChanges, pendingExamChanges, pendingHomeworkChanges
        case pendingSharedExamUserChanges, pendingSharedHomeworkUserChanges
        case subscribedCourseIds, courses, classIds, classNames, classOwners, classDetails
        case migratedGroupIds, activeClassId, courseExamsMap, courseHomeworksMap, courseMappings
        case wahlpflichtfachGroupIds, wahlpflichtfachGroupNames, wahlpflichtfachGroupOwners
        case examPoints, isPrivacyModeActive, alwaysEnablePrivacyOnStart, userName
        case mssDecimalPrecision, showSubjectsAsGrid, showNextExamCard, subjectCustomOrder
        case hasSeenMigrationInfo, hasSeenClassesOnboarding, lastSeenVersion
        case simulatedGrades, excludedRealGradeIds, includeDroppedGrades, simulatedExamPointsDict
        case groupOwners, groupTypes, groupMemberIds, groupsHidden, schoolYearNames
        case examSubjectMapping, homeworkSubjectMapping, examGroupSubjects, homeworkGroupSubjects
        case sharedExamUserReminders, sharedHomeworkUserReminders, sharedExamUserNotes, sharedHomeworkUserNotes
        case sharedExamUserCompleted, sharedHomeworkUserCompleted, sharedExamUserRescheduled
        case holidaysCache, feiertageCache, pfingstferienCache, summerEndCache
    }

    let subscribedCourseIds: [String]
    let courses: [Course]
    let classIds: [String]
    let classNames: [String: String]
    let classOwners: [String: String]
    let classDetails: [String: SchoolClass]
    let migratedGroupIds: [String]
    let activeClassId: String?
    let courseExamsMap: [String: [Exam]]
    let courseHomeworksMap: [String: [Homework]]
    let courseMappings: [String: String]
    let wahlpflichtfachGroupIds: [String]
    let wahlpflichtfachGroupNames: [String: String]
    let wahlpflichtfachGroupOwners: [String: String]

    let examPoints: [String: Double?]
    let isPrivacyModeActive: Bool
    let alwaysEnablePrivacyOnStart: Bool
    let userName: String?
    let mssDecimalPrecision: Int
    let showSubjectsAsGrid: Bool
    let showNextExamCard: Bool
    let subjectCustomOrder: [String]
    let hasSeenMigrationInfo: Bool
    let hasSeenClassesOnboarding: Bool
    let lastSeenVersion: String?
    let simulatedGrades: [SimulatedGradeEntry]
    let excludedRealGradeIds: [String]
    let includeDroppedGrades: Bool
    let simulatedExamPointsDict: [String: Double]
    let groupOwners: [String: String]
    let groupTypes: [String: String]
    let groupMemberIds: [String: [String]]
    let groupsHidden: Bool
    let schoolYearNames: [String: String]
    let examSubjectMapping: [String: String]
    let homeworkSubjectMapping: [String: String]
    let examGroupSubjects: [GroupSubject]
    let homeworkGroupSubjects: [GroupSubject]
    let sharedExamUserReminders: [String: Date]
    let sharedHomeworkUserReminders: [String: Date]
    let sharedExamUserNotes: [String: String]
    let sharedHomeworkUserNotes: [String: String]
    let sharedExamUserCompleted: [String]
    let sharedHomeworkUserCompleted: [String]
    let sharedExamUserRescheduled: [String: Date]

    let holidaysCache: [String: [HolidayPeriod]]
    let feiertageCache: [String: [HolidayPeriod]]
    let pfingstferienCache: [String: Date]
    let summerEndCache: [String: Date]
}

extension OfflineSnapshot: Decodable {
    // Explicit nonisolated init to satisfy strict concurrency checking
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        activeSchoolYearId = try container.decodeIfPresent(String.self, forKey: .activeSchoolYearId)
        encryptionSalt = try container.decodeIfPresent(String.self, forKey: .encryptionSalt)
        subjects = try container.decode([Subject].self, forKey: .subjects)
        gradesBySubject = try container.decode([String: [GradeWithId]].self, forKey: .gradesBySubject)
        fachreferat = try container.decodeIfPresent(Fachreferat.self, forKey: .fachreferat)
        seminarPerformance = try container.decodeIfPresent(SeminarPerformance.self, forKey: .seminarPerformance)
        practicalPerformance = try container.decodeIfPresent(PracticalPerformance.self, forKey: .practicalPerformance)
        homeworks = try container.decode([Homework].self, forKey: .homeworks)
        exams = try container.decode([Exam].self, forKey: .exams)
        sharedExams = try container.decode([Exam].self, forKey: .sharedExams)
        sharedHomeworks = try container.decode([Homework].self, forKey: .sharedHomeworks)
        examGroupId = try container.decodeIfPresent(String.self, forKey: .examGroupId)
        homeworkGroupId = try container.decodeIfPresent(String.self, forKey: .homeworkGroupId)
        groupIds = try container.decode([String].self, forKey: .groupIds)
        groupNames = try container.decode([String: String].self, forKey: .groupNames)
        groupSubjectMappings = try container.decode([String: [String: String]].self, forKey: .groupSubjectMappings)
        groupExamsByGroup = try container.decode([String: [Exam]].self, forKey: .groupExamsByGroup)
        groupHomeworksByGroup = try container.decode([String: [Homework]].self, forKey: .groupHomeworksByGroup)
        schoolYears = try container.decode([String].self, forKey: .schoolYears)
        gradeYear = try container.decodeIfPresent(Int.self, forKey: .gradeYear)
        schoolType = try container.decode(SchoolType.self, forKey: .schoolType)
        subjectSortMode = try container.decode(SubjectSortMode.self, forKey: .subjectSortMode)
        subjectSortOrder = try container.decode([String].self, forKey: .subjectSortOrder)
        compactView = try container.decode(Bool.self, forKey: .compactView)
        animationsEnabled = try container.decode(Bool.self, forKey: .animationsEnabled)
        showHolidayHints = try container.decodeIfPresent(Bool.self, forKey: .showHolidayHints)
        theme = try container.decode(String.self, forKey: .theme)
        themeIntensity = try container.decodeIfPresent(Double.self, forKey: .themeIntensity)
        appIcon = try container.decodeIfPresent(String.self, forKey: .appIcon)
        darkMode = try container.decode(Bool.self, forKey: .darkMode)
        darkModeMode = try container.decode(String.self, forKey: .darkModeMode)
        homeworkReminderHour = try container.decode(Int.self, forKey: .homeworkReminderHour)
        homeworkReminderMinute = try container.decode(Int.self, forKey: .homeworkReminderMinute)
        standardRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .standardRemindersEnabled)
        supportNotificationUpdates = try container.decodeIfPresent(Bool.self, forKey: .supportNotificationUpdates)
        supportNotificationAccess = try container.decodeIfPresent(Bool.self, forKey: .supportNotificationAccess)
        customNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .customNotificationsEnabled)
        broadcastNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .broadcastNotificationsEnabled)
        pendingGrades = try container.decode([PendingGrade].self, forKey: .pendingGrades)
        pendingFachreferat = try container.decodeIfPresent(PendingFachreferat.self, forKey: .pendingFachreferat)
        pendingSeminar = try container.decodeIfPresent(PendingSeminarPerformance.self, forKey: .pendingSeminar)
        pendingGradeChanges = try container.decodeIfPresent([PendingGradeChange].self, forKey: .pendingGradeChanges) ?? []
        pendingSubjectChanges = try container.decodeIfPresent([PendingSubjectChange].self, forKey: .pendingSubjectChanges) ?? []
        pendingExamChanges = try container.decodeIfPresent([PendingExamChange].self, forKey: .pendingExamChanges) ?? []
        pendingHomeworkChanges = try container.decodeIfPresent([PendingHomeworkChange].self, forKey: .pendingHomeworkChanges) ?? []
        pendingSharedExamUserChanges = try container.decodeIfPresent([PendingSharedExamUserChange].self, forKey: .pendingSharedExamUserChanges) ?? []
        pendingSharedHomeworkUserChanges = try container.decodeIfPresent([PendingSharedHomeworkUserChange].self, forKey: .pendingSharedHomeworkUserChanges) ?? []
        
        subscribedCourseIds = try container.decode([String].self, forKey: .subscribedCourseIds)
        courses = try container.decode([Course].self, forKey: .courses)
        classIds = try container.decode([String].self, forKey: .classIds)
        classNames = try container.decode([String: String].self, forKey: .classNames)
        classOwners = try container.decode([String: String].self, forKey: .classOwners)
        classDetails = try container.decode([String: SchoolClass].self, forKey: .classDetails)
        migratedGroupIds = try container.decode([String].self, forKey: .migratedGroupIds)
        activeClassId = try container.decodeIfPresent(String.self, forKey: .activeClassId)
        courseExamsMap = try container.decode([String: [Exam]].self, forKey: .courseExamsMap)
        courseHomeworksMap = try container.decode([String: [Homework]].self, forKey: .courseHomeworksMap)
        courseMappings = try container.decode([String: String].self, forKey: .courseMappings)
        wahlpflichtfachGroupIds = try container.decode([String].self, forKey: .wahlpflichtfachGroupIds)
        wahlpflichtfachGroupNames = try container.decode([String: String].self, forKey: .wahlpflichtfachGroupNames)
        wahlpflichtfachGroupOwners = try container.decode([String: String].self, forKey: .wahlpflichtfachGroupOwners)

        examPoints = try container.decode([String: Double?].self, forKey: .examPoints)
        isPrivacyModeActive = try container.decode(Bool.self, forKey: .isPrivacyModeActive)
        alwaysEnablePrivacyOnStart = try container.decode(Bool.self, forKey: .alwaysEnablePrivacyOnStart)
        userName = try container.decodeIfPresent(String.self, forKey: .userName)
        mssDecimalPrecision = try container.decode(Int.self, forKey: .mssDecimalPrecision)
        showSubjectsAsGrid = try container.decode(Bool.self, forKey: .showSubjectsAsGrid)
        showNextExamCard = try container.decode(Bool.self, forKey: .showNextExamCard)
        subjectCustomOrder = try container.decode([String].self, forKey: .subjectCustomOrder)
        hasSeenMigrationInfo = try container.decode(Bool.self, forKey: .hasSeenMigrationInfo)
        hasSeenClassesOnboarding = try container.decode(Bool.self, forKey: .hasSeenClassesOnboarding)
        lastSeenVersion = try container.decodeIfPresent(String.self, forKey: .lastSeenVersion)
        simulatedGrades = try container.decode([SimulatedGradeEntry].self, forKey: .simulatedGrades)
        excludedRealGradeIds = try container.decode([String].self, forKey: .excludedRealGradeIds)
        includeDroppedGrades = try container.decode(Bool.self, forKey: .includeDroppedGrades)
        simulatedExamPointsDict = try container.decode([String: Double].self, forKey: .simulatedExamPointsDict)
        groupOwners = try container.decode([String: String].self, forKey: .groupOwners)
        groupTypes = try container.decode([String: String].self, forKey: .groupTypes)
        groupMemberIds = try container.decode([String: [String]].self, forKey: .groupMemberIds)
        groupsHidden = try container.decode(Bool.self, forKey: .groupsHidden)
        schoolYearNames = try container.decode([String: String].self, forKey: .schoolYearNames)
        examSubjectMapping = try container.decode([String: String].self, forKey: .examSubjectMapping)
        homeworkSubjectMapping = try container.decode([String: String].self, forKey: .homeworkSubjectMapping)
        examGroupSubjects = try container.decode([GroupSubject].self, forKey: .examGroupSubjects)
        homeworkGroupSubjects = try container.decode([GroupSubject].self, forKey: .homeworkGroupSubjects)
        sharedExamUserReminders = try container.decode([String: Date].self, forKey: .sharedExamUserReminders)
        sharedHomeworkUserReminders = try container.decode([String: Date].self, forKey: .sharedHomeworkUserReminders)
        sharedExamUserNotes = try container.decode([String: String].self, forKey: .sharedExamUserNotes)
        sharedHomeworkUserNotes = try container.decode([String: String].self, forKey: .sharedHomeworkUserNotes)
        sharedExamUserCompleted = try container.decode([String].self, forKey: .sharedExamUserCompleted)
        sharedHomeworkUserCompleted = try container.decode([String].self, forKey: .sharedHomeworkUserCompleted)
        sharedExamUserRescheduled = try container.decode([String: Date].self, forKey: .sharedExamUserRescheduled)

        holidaysCache = try container.decode([String: [HolidayPeriod]].self, forKey: .holidaysCache)
        feiertageCache = try container.decode([String: [HolidayPeriod]].self, forKey: .feiertageCache)
        pfingstferienCache = try container.decode([String: Date].self, forKey: .pfingstferienCache)
        summerEndCache = try container.decode([String: Date].self, forKey: .summerEndCache)
    }
}

extension OfflineSnapshot: Encodable {
    // Explicit encode to match
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encodeIfPresent(activeSchoolYearId, forKey: .activeSchoolYearId)
        try container.encodeIfPresent(encryptionSalt, forKey: .encryptionSalt)
        try container.encode(subjects, forKey: .subjects)
        try container.encode(gradesBySubject, forKey: .gradesBySubject)
        try container.encodeIfPresent(fachreferat, forKey: .fachreferat)
        try container.encodeIfPresent(seminarPerformance, forKey: .seminarPerformance)
        try container.encodeIfPresent(practicalPerformance, forKey: .practicalPerformance)
        try container.encode(homeworks, forKey: .homeworks)
        try container.encode(exams, forKey: .exams)
        try container.encode(sharedExams, forKey: .sharedExams)
        try container.encode(sharedHomeworks, forKey: .sharedHomeworks)
        try container.encodeIfPresent(examGroupId, forKey: .examGroupId)
        try container.encodeIfPresent(homeworkGroupId, forKey: .homeworkGroupId)
        try container.encode(groupIds, forKey: .groupIds)
        try container.encode(groupNames, forKey: .groupNames)
        try container.encode(groupSubjectMappings, forKey: .groupSubjectMappings)
        try container.encode(groupExamsByGroup, forKey: .groupExamsByGroup)
        try container.encode(groupHomeworksByGroup, forKey: .groupHomeworksByGroup)
        try container.encode(schoolYears, forKey: .schoolYears)
        try container.encodeIfPresent(gradeYear, forKey: .gradeYear)
        try container.encode(schoolType, forKey: .schoolType)
        try container.encode(subjectSortMode, forKey: .subjectSortMode)
        try container.encode(subjectSortOrder, forKey: .subjectSortOrder)
        try container.encode(compactView, forKey: .compactView)
        try container.encode(animationsEnabled, forKey: .animationsEnabled)
        try container.encodeIfPresent(showHolidayHints, forKey: .showHolidayHints)
        try container.encode(theme, forKey: .theme)
        try container.encodeIfPresent(themeIntensity, forKey: .themeIntensity)
        try container.encodeIfPresent(appIcon, forKey: .appIcon)
        try container.encode(darkMode, forKey: .darkMode)
        try container.encode(darkModeMode, forKey: .darkModeMode)
        try container.encode(homeworkReminderHour, forKey: .homeworkReminderHour)
        try container.encode(homeworkReminderMinute, forKey: .homeworkReminderMinute)
        try container.encodeIfPresent(standardRemindersEnabled, forKey: .standardRemindersEnabled)
        try container.encodeIfPresent(supportNotificationUpdates, forKey: .supportNotificationUpdates)
        try container.encodeIfPresent(supportNotificationAccess, forKey: .supportNotificationAccess)
        try container.encodeIfPresent(customNotificationsEnabled, forKey: .customNotificationsEnabled)
        try container.encodeIfPresent(broadcastNotificationsEnabled, forKey: .broadcastNotificationsEnabled)
        try container.encode(pendingGrades, forKey: .pendingGrades)
        try container.encodeIfPresent(pendingFachreferat, forKey: .pendingFachreferat)
        try container.encodeIfPresent(pendingSeminar, forKey: .pendingSeminar)
        try container.encode(pendingGradeChanges, forKey: .pendingGradeChanges)
        try container.encode(pendingSubjectChanges, forKey: .pendingSubjectChanges)
        try container.encode(pendingExamChanges, forKey: .pendingExamChanges)
        try container.encode(pendingHomeworkChanges, forKey: .pendingHomeworkChanges)
        try container.encode(pendingSharedExamUserChanges, forKey: .pendingSharedExamUserChanges)
        try container.encode(pendingSharedHomeworkUserChanges, forKey: .pendingSharedHomeworkUserChanges)
        
        try container.encode(subscribedCourseIds, forKey: .subscribedCourseIds)
        try container.encode(courses, forKey: .courses)
        try container.encode(classIds, forKey: .classIds)
        try container.encode(classNames, forKey: .classNames)
        try container.encode(classOwners, forKey: .classOwners)
        try container.encode(classDetails, forKey: .classDetails)
        try container.encode(migratedGroupIds, forKey: .migratedGroupIds)
        try container.encodeIfPresent(activeClassId, forKey: .activeClassId)
        try container.encode(courseExamsMap, forKey: .courseExamsMap)
        try container.encode(courseHomeworksMap, forKey: .courseHomeworksMap)
        try container.encode(courseMappings, forKey: .courseMappings)
        try container.encode(wahlpflichtfachGroupIds, forKey: .wahlpflichtfachGroupIds)
        try container.encode(wahlpflichtfachGroupNames, forKey: .wahlpflichtfachGroupNames)
        try container.encode(wahlpflichtfachGroupOwners, forKey: .wahlpflichtfachGroupOwners)
        
        try container.encode(examPoints, forKey: .examPoints)
        try container.encode(isPrivacyModeActive, forKey: .isPrivacyModeActive)
        try container.encode(alwaysEnablePrivacyOnStart, forKey: .alwaysEnablePrivacyOnStart)
        try container.encodeIfPresent(userName, forKey: .userName)
        try container.encode(mssDecimalPrecision, forKey: .mssDecimalPrecision)
        try container.encode(showSubjectsAsGrid, forKey: .showSubjectsAsGrid)
        try container.encode(showNextExamCard, forKey: .showNextExamCard)
        try container.encode(subjectCustomOrder, forKey: .subjectCustomOrder)
        try container.encode(hasSeenMigrationInfo, forKey: .hasSeenMigrationInfo)
        try container.encode(hasSeenClassesOnboarding, forKey: .hasSeenClassesOnboarding)
        try container.encodeIfPresent(lastSeenVersion, forKey: .lastSeenVersion)
        try container.encode(simulatedGrades, forKey: .simulatedGrades)
        try container.encode(excludedRealGradeIds, forKey: .excludedRealGradeIds)
        try container.encode(includeDroppedGrades, forKey: .includeDroppedGrades)
        try container.encode(simulatedExamPointsDict, forKey: .simulatedExamPointsDict)
        try container.encode(groupOwners, forKey: .groupOwners)
        try container.encode(groupTypes, forKey: .groupTypes)
        try container.encode(groupMemberIds, forKey: .groupMemberIds)
        try container.encode(groupsHidden, forKey: .groupsHidden)
        try container.encode(schoolYearNames, forKey: .schoolYearNames)
        try container.encode(examSubjectMapping, forKey: .examSubjectMapping)
        try container.encode(homeworkSubjectMapping, forKey: .homeworkSubjectMapping)
        try container.encode(examGroupSubjects, forKey: .examGroupSubjects)
        try container.encode(homeworkGroupSubjects, forKey: .homeworkGroupSubjects)
        try container.encode(sharedExamUserReminders, forKey: .sharedExamUserReminders)
        try container.encode(sharedHomeworkUserReminders, forKey: .sharedHomeworkUserReminders)
        try container.encode(sharedExamUserNotes, forKey: .sharedExamUserNotes)
        try container.encode(sharedHomeworkUserNotes, forKey: .sharedHomeworkUserNotes)
        try container.encode(sharedExamUserCompleted, forKey: .sharedExamUserCompleted)
        try container.encode(sharedHomeworkUserCompleted, forKey: .sharedHomeworkUserCompleted)
        try container.encode(sharedExamUserRescheduled, forKey: .sharedExamUserRescheduled)

        try container.encode(holidaysCache, forKey: .holidaysCache)
        try container.encode(feiertageCache, forKey: .feiertageCache)
        try container.encode(pfingstferienCache, forKey: .pfingstferienCache)
        try container.encode(summerEndCache, forKey: .summerEndCache)
    }
}
