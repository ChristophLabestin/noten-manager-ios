import Foundation

struct GroupSubject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: Int?
    let alias: String?

    init(id: String, name: String, type: Int? = nil, alias: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.alias = alias
    }
}
