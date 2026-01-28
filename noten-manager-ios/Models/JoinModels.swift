import Foundation

struct JoinPreview: Identifiable {
    enum JoinType {
        case schoolClass
        case socialGroup
    }
    
    let id: String
    let name: String
    let type: JoinType
    let branches: [String]?
    let wahlpflichtGroups: [String]?
    let examCount: Int
    let memberCount: Int?
}
