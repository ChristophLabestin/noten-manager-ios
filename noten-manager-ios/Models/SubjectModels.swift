// SubjectModels.swift
import Foundation

enum ExamType: String, Codable {
    case written
    case oral
    case presentation
}

enum SchoolType: String, Codable, CaseIterable {
    case fos
    case bos

    var displayName: String {
        switch self {
        case .fos: return "FOS (Fachabitur 11/12)"
        case .bos: return "BOS (Abitur 12/13)"
        }
    }
}

struct SimulatedGradeEntry: Codable, Identifiable, Equatable, GradeProtocol {
    let id: UUID
    let subjectName: String
    let grade: Double
    let weight: Double
    let assessmentType: AssessmentType?
    let isCustomWeight: Bool
    let halfYear: Int?
    let createdAt: Date

    init(id: UUID = UUID(),
         subjectName: String,
         grade: Double,
         weight: Double,
         assessmentType: AssessmentType?,
         isCustomWeight: Bool,
         halfYear: Int?,
         createdAt: Date = Date()) {
        self.id = id
        self.subjectName = subjectName
        self.grade = grade
        self.weight = weight
        self.assessmentType = assessmentType
        self.isCustomWeight = isCustomWeight
        self.halfYear = halfYear
        self.createdAt = createdAt
    }
}

struct Subject: Codable, Identifiable, Hashable {
    // In Firestore ist die documentID der Name; wir spiegeln das
    var id: String { name }
    let name: String
    let type: Int
    // New grading mode (FOBOSO)
    let gradingMode: GradingMode?
    let expectedSchulaufgabenPerTerm: Int?
    let date: Date
    let order: Int?
    let teacher: String?
    let room: String?
    let email: String?
    let alias: String?
    let droppedHalfYear: Int? // 1 | 2
    let examSubject: Bool?
    let examType: ExamType?
    let examPointsEncrypted: String?
    let writtenExamPointsEncrypted: String?
    let oralExamPointsEncrypted: String?
    let isElective: Bool
    
    // Fixed Averages (Overrides)
    let fixedAverageHalfYear1: Double?
    let fixedAverageHalfYear2: Double?
    let fixedAverageYearly: Double?

    init(name: String,
         type: Int,
         gradingMode: GradingMode? = nil,
         expectedSchulaufgabenPerTerm: Int? = nil,
         date: Date,
         order: Int? = nil,
         teacher: String? = nil,
         room: String? = nil,
         email: String? = nil,
         alias: String? = nil,
         droppedHalfYear: Int? = nil,
         examSubject: Bool? = nil,
         examType: ExamType? = nil,
         examPointsEncrypted: String? = nil,
         writtenExamPointsEncrypted: String? = nil,
         oralExamPointsEncrypted: String? = nil,
         isElective: Bool = false,
         fixedAverageHalfYear1: Double? = nil,
         fixedAverageHalfYear2: Double? = nil,
         fixedAverageYearly: Double? = nil) {
        self.name = name
        self.type = type
        self.gradingMode = gradingMode
        self.expectedSchulaufgabenPerTerm = expectedSchulaufgabenPerTerm
        self.date = date
        self.order = order
        self.teacher = teacher
        self.room = room
        self.email = email
        self.alias = alias
        self.droppedHalfYear = droppedHalfYear
        self.examSubject = examSubject
        self.examType = examType
        self.examPointsEncrypted = examPointsEncrypted
        self.writtenExamPointsEncrypted = writtenExamPointsEncrypted
        self.oralExamPointsEncrypted = oralExamPointsEncrypted
        self.isElective = isElective
        self.fixedAverageHalfYear1 = fixedAverageHalfYear1
        self.fixedAverageHalfYear2 = fixedAverageHalfYear2
        self.fixedAverageYearly = fixedAverageYearly
    }
}

struct EncryptedGrade: Codable {
    let grade: String // verschlüsselt: "ivB64:ciphertextB64"
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int? // 1 | 2
    let linkedExamId: String?
    let updatedAt: Date?
    let assessmentType: AssessmentType?
}

protocol GradeProtocol {
    var grade: Double { get }
    var weight: Double { get }
    var halfYear: Int? { get }
    var assessmentType: AssessmentType? { get }
}

struct Grade: Codable, GradeProtocol {
    let grade: Double
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int?
    let linkedExamId: String?
    let assessmentType: AssessmentType?

    init(
        grade: Double,
        weight: Double,
        date: Date,
        note: String?,
        halfYear: Int?,
        linkedExamId: String?,
        assessmentType: AssessmentType? = nil
    ) {
        self.grade = grade
        self.weight = weight
        self.date = date
        self.note = note
        self.halfYear = halfYear
        self.linkedExamId = linkedExamId
        self.assessmentType = assessmentType
    }
}

struct GradeWithId: Codable, Identifiable, GradeProtocol {
    let id: String
    let grade: Double
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int?
    let linkedExamId: String?
    let assessmentType: AssessmentType?

    init(
        id: String,
        grade: Double,
        weight: Double,
        date: Date,
        note: String?,
        halfYear: Int?,
        linkedExamId: String?,
        assessmentType: AssessmentType? = nil
    ) {
        self.id = id
        self.grade = grade
        self.weight = weight
        self.date = date
        self.note = note
        self.halfYear = halfYear
        self.linkedExamId = linkedExamId
        self.assessmentType = assessmentType
    }
}

struct EncryptedFachreferat: Codable {
    let grade: String
    let subjectName: String
    let date: Date
    let note: String?
    let presentationGrade: String?
    let paperGrade: String?
    let presentationWeight: Double?
    let fixedGrade: String?  // Override for calculated grade
}

struct Fachreferat: Codable, Identifiable {
    let id: String
    let grade: Double
    let subjectName: String
    let date: Date
    let note: String?
    let presentationGrade: Double?
    let paperGrade: Double?
    let presentationWeight: Double?
    let fixedGrade: Double?  // Override for calculated grade
}

struct SeminarPerformance: Codable, Identifiable, Equatable {
    let id: String
    let topic: String?
    let individualPoints: Double?
    let paperPoints: Double?
    let presentationPoints: Double?
    let submissionDate: Date?
    let presentationDate: Date?
    let note: String?
    let updatedAt: Date?
}

struct PracticalGradeEntry: Codable, Identifiable, Equatable {
    let id: String
    let grade: Double
    let company: String?
    let note: String?
    let halfYear: Int?
    let date: Date
    // FOS 11 FOBOSO Components
    let guidanceGrade: Double?    // Praktische Anleitung (1x)
    let deepeningGrade: Double?   // Praktische Vertiefung (1x)
    let activityGrade: Double?    // Praktische Tätigkeit (2x)
}

struct PracticalPerformance: Codable, Identifiable, Equatable {
    let id: String
    let grades: [PracticalGradeEntry]
    let fixedAverage: Double?  // Override for calculated average
}

enum SubjectSortMode: String, Codable, CaseIterable {
    case name
    case name_desc
    case average
    case average_worst
    case custom

    var displayName: String {
        switch self {
        case .name: return "Alphabetisch (A-Z)"
        case .name_desc: return "Alphabetisch (Z-A)"
        case .average: return "Beste zuerst"
        case .average_worst: return "Schlechteste zuerst"
        case .custom: return "Eigene Reihenfolge"
        }
    }
}
