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

struct Subject: Codable, Identifiable, Hashable {
    // In Firestore ist die documentID der Name; wir spiegeln das
    var id: String { name }
    let name: String
    let type: Int
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

    init(name: String,
         type: Int,
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
         isElective: Bool = false) {
        self.name = name
        self.type = type
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
    }
}

struct EncryptedGrade: Codable {
    let grade: String // verschlüsselt: "ivB64:ciphertextB64"
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int? // 1 | 2
}

struct Grade: Codable {
    let grade: Double
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int?
}

struct GradeWithId: Codable, Identifiable {
    let id: String
    let grade: Double
    let weight: Double
    let date: Date
    let note: String?
    let halfYear: Int?
}

struct EncryptedFachreferat: Codable {
    let grade: String
    let subjectName: String
    let date: Date
    let note: String?
}

struct Fachreferat: Codable, Identifiable {
    let id: String
    let grade: Double
    let subjectName: String
    let date: Date
    let note: String?
}

struct PracticalGradeEntry: Codable, Identifiable, Equatable {
    let id: String
    let grade: Double
    let company: String?
    let note: String?
    let halfYear: Int?
    let date: Date
}

struct PracticalPerformance: Codable, Identifiable, Equatable {
    let id: String
    let grades: [PracticalGradeEntry]
}

enum SubjectSortMode: String, Codable, CaseIterable {
    case name
    case name_desc
    case average
    case average_worst
    case custom
}
