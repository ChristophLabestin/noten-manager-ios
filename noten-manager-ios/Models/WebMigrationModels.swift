import Foundation

enum ResolutionStrategy: String, Codable {
    case keepLocal
    case useWeb
    case keepBoth
}

struct WebDataConflict: Identifiable, Codable {
    var id: String { "\(subjectName)_\(gradeId)" }
    let subjectName: String
    let gradeId: String
    let localGrade: Double?
    let webGrade: Double
    let localDate: Date?
    let webDate: Date
    let localNote: String?
    let webNote: String?
    var resolution: ResolutionStrategy = .keepLocal
}

struct WebImportResult {
    let newSubjects: [String]
    let conflicts: [WebDataConflict]
    let totalWebGrades: Int
}
