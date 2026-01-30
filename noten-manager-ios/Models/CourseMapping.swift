import Foundation

struct CourseMapping: Codable, Hashable {
    let courseId: String
    let localSubjectId: String
    // We might add more metadata later if needed, e.g. timestamp
}
