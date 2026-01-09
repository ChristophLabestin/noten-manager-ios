import Foundation

/// Represents a Course (Fach/Kurs) in the new architecture.
/// This is the central entity that holds Exams and Homework.
struct Course: Codable, Identifiable, Hashable {
    let id: String
    let name: String // e.g. "Mathematik", "Sozialkunde"
    
    /// The standard subject key (e.g. "mathematics", "english") for icon/color mapping.
    let subjectKey: String?
    
    /// The ID of the Class this course belongs to.
    /// If nil, it is a standalone course (e.g. a cross-class language course).
    let classId: String?
    
    /// The logic for who attends this course.
    let type: CourseType
    
    /// The user ID of the creator/admin (Teacher).
    let ownerId: String
    
    /// A join code for students to join this specific course directly (optional).
    let joinCode: String?
    
    let createdAt: Date
    
    // UI Helpers
    var icon: String {
        // Logic to return icon based on subjectKey -> can be implemented via a helper
        return "book.fill"
    }
}

/// Defines the enrollment type for a course.
enum CourseType: Codable, Hashable {
    /// Everyone in the class must take this course.
    case mandatory
    
    /// Only students in a specific branch (Zweig) take this.
    /// Associated value is the branch name/ID (e.g. "sozial", "wirtschaft")
    case branch(String)
    
    /// Users must explicitly choose to join this (Wahlfach).
    case elective
}

/// Represents the Blueprint of a Class.
/// Stored in the `classes` collection to describe its structure.
struct ClassConfiguration: Codable {
    struct Branch: Codable, Hashable, Identifiable {
        var id: String { name }
        let name: String // "Sozialzweig", "Wirtschaftszweig"
    }
    
    let branches: [Branch]
    // We don't necessarily need to list all courses here if we query courses by `classId`.
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
