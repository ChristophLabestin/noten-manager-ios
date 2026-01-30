import Foundation

enum GradingMode: String, Codable {
    case withSchulaufgaben
    case withoutSchulaufgaben
}

enum AssessmentType: String, Codable {
    case schulaufgabe
    case kurzarbeit
    case stegreifaufgabe
    case muendlich
    case praktisch
    case projekt
    
    var prettyName: String {
        switch self {
        case .schulaufgabe: return "Schulaufgabe"
        case .kurzarbeit: return "Kurzarbeit"
        case .stegreifaufgabe: return "Stegreifaufgabe"
        case .muendlich: return "Mündlich"
        case .praktisch: return "Praktisch"
        case .projekt: return "Projekt"
        }
    }
}

enum HalfYearStatus: String, Codable {
    case finalResult
    case interim
    case missing
}

struct SubjectV2: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var gradingMode: GradingMode
    var expectedSchulaufgabenPerTerm: Int?
}

struct TermV2: Codable, Identifiable, Hashable {
    let id: UUID
    var label: String
}

struct Assessment: Codable, Identifiable, Hashable {
    let id: UUID
    let subjectId: UUID
    let termId: UUID
    let type: AssessmentType
    let points: Int // 0...15
    let weight: Double
    let date: Date
    let title: String?

    init(
        id: UUID = UUID(),
        subjectId: UUID,
        termId: UUID,
        type: AssessmentType,
        points: Int,
        weight: Double = 1.0,
        date: Date = Date(),
        title: String? = nil
    ) {
        self.id = id
        self.subjectId = subjectId
        self.termId = termId
        self.type = type
        self.points = points
        self.weight = weight
        self.date = date
        self.title = title
    }
}
