import Foundation

/// Represents a Course (Fach/Kurs) in the new architecture.
/// This is the central entity that holds Exams and Homework.
struct Course: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let subjectKey: String?
    let classId: String?
    let type: CourseType?
    var gradingMode: GradingMode? = nil
    let ownerId: String?
    let joinCode: String?
    let createdAt: Date?
    
    // UI Helpers
    var icon: String {
        // Logic to return icon based on subjectKey -> can be implemented via a helper
        return "book.fill"
    }
}

/// Represents a standalone elective subject group that can be integrated into classes.
struct WahlpflichtfachGroup: Codable, Identifiable, Hashable {
    let id: String // Document ID (also the join code)
    let name: String // e.g. "Spanisch Wahlpflicht"
    let subjects: [String] // Subject names in this group
    let ownerId: String
    let createdAt: Date
}

/// Defines the enrollment type for a course.
enum CourseType: Codable, Hashable {
    case mandatory
    case branch(String)
    case elective
    case wahlpflicht(String)
    
    enum CodingKeys: String, CodingKey {
        case type, associatedId
    }
    
    // Helper keys for default synthesis
    enum AutoKeys: String, CodingKey {
        case branch, wahlpflicht, mandatory, elective
    }
    enum AssociatedKeys: String, CodingKey {
        case _0
    }
    
    init(from decoder: Decoder) throws {
        // 1. Try single value container (legacy string format)
        if let container = try? decoder.singleValueContainer(),
           let s = try? container.decode(String.self) {
            let lowered = s.lowercased()
            if lowered == "mandatory" { self = .mandatory }
            else if lowered == "elective" { self = .elective }
            else { self = .branch(s) }
            return
        }
        
        // 2. Try default synthesized enum format (nested structure)
        // Format: { "branch": { "_0": "Name" } }
        if let container = try? decoder.container(keyedBy: AutoKeys.self) {
            if let branchContainer = try? container.nestedContainer(keyedBy: AssociatedKeys.self, forKey: .branch),
               let val = try? branchContainer.decode(String.self, forKey: ._0) {
                self = .branch(val)
                return
            }
            if let wpContainer = try? container.nestedContainer(keyedBy: AssociatedKeys.self, forKey: .wahlpflicht),
               let val = try? wpContainer.decode(String.self, forKey: ._0) {
                self = .wahlpflicht(val)
                return
            }
            if container.contains(.mandatory) {
                self = .mandatory
                return
            }
            if container.contains(.elective) {
                self = .elective
                return
            }
        }
        
        // 3. Try custom keyed container (explicit structure)
        do {
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            let typeString = try keyedContainer.decode(String.self, forKey: .type)
            switch typeString {
            case "mandatory": self = .mandatory
            case "elective": self = .elective
            case "branch":
                if let id = try? keyedContainer.decode(String.self, forKey: .associatedId) {
                    self = .branch(id)
                } else if let id = try? keyedContainer.decodeIfPresent(String.self, forKey: .init(stringValue: "branch")!) ??
                                   keyedContainer.decodeIfPresent(String.self, forKey: .init(stringValue: "branchName")!) {
                    // Legacy fallback
                    self = .branch(id)
                } else {
                    self = .mandatory
                }
            case "wahlpflicht":
                let id = try keyedContainer.decode(String.self, forKey: .associatedId)
                self = .wahlpflicht(id)
            default:
                self = .mandatory
            }
        } catch {
            print("❌ CourseType Decoding Error: \(error)")
            self = .elective
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mandatory:
            try container.encode("mandatory", forKey: .type)
        case .elective:
            try container.encode("elective", forKey: .type)
        case .branch(let id):
            try container.encode("branch", forKey: .type)
            try container.encode(id, forKey: .associatedId)
        case .wahlpflicht(let id):
            try container.encode("wahlpflicht", forKey: .type)
            try container.encode(id, forKey: .associatedId)
        }
    }
    
    var associatedId: String? {
        switch self {
        case .branch(let id): return id
        case .wahlpflicht(let id): return id
        default: return nil
        }
    }
}

/// Represents the Blueprint of a Class.
/// Stored in the `classes` collection to describe its structure.
struct ClassConfiguration: Codable {
    struct Branch: Codable, Hashable, Identifiable {
        var id: String { name }
        let name: String // "Sozialzweig", "Wirtschaftszweig"
    }
    
    struct WahlpflichtfachConfig: Codable, Hashable, Identifiable {
        var id: String { name }
        let name: String
        let subjects: [String]
    }
    
    let branches: [Branch]?
    var wahlpflichtfaecher: [WahlpflichtfachConfig]?
    
    enum CodingKeys: String, CodingKey {
        case branches, wahlpflichtfaecher
    }
    
    init(branches: [Branch]?, wahlpflichtfaecher: [WahlpflichtfachConfig]? = nil) {
        self.branches = branches
        self.wahlpflichtfaecher = wahlpflichtfaecher
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.branches = try container.decodeIfPresent([Branch].self, forKey: .branches)
        self.wahlpflichtfaecher = try container.decodeIfPresent([WahlpflichtfachConfig].self, forKey: .wahlpflichtfaecher)
    }
}

/// Represents the User's link to a Class/Platform.
/// This would be part of the User Profile.
struct UserCourseProfile: Codable {
    /// The Class the user is primarily part of (e.g. "12B")
    let primaryClassId: String?
    
    /// The Branch the user selected (if any)
    let selectedBranch: String?
    
    /// The list of Course IDs the user is subscribed to.
    /// This is the "Single Source of Truth" for what content they see.
    let subscribedCourseIds: [String]
}
