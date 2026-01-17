import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

extension GradesStore {
    func mergeLocalExamIntoShared(localExam: Exam, sharedExam: Exam) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // 1. Move Linked Grade
        // Find subject for local exam
        if let subject = subjects.first(where: { $0.name == localExam.subjectName }) {
            let grades = gradesBySubject[subject.name] ?? []
            if let linked = grades.first(where: { $0.linkedExamId == localExam.id }) {
                let gradeRef = try await requireYearRef(uid: uid)
                    .collection("subjects").document(subject.name)
                    .collection("grades").document(linked.id)
                
                // We only need to update the linkage. 
                // Since the grade content itself (grade, weight, etc.) is encrypted and doesn't change, 
                // and the ID is not part of the encryption payload in the STRUCT (though it's good to check),
                // we can just update the metadata field linkedExamId.
                // Checking `EncryptedGrade` struct in `SubjectModels.swift`:
                // linkedExamId IS part of the struct, so it IS stored in the document.
                // However, is it encrypted?
                // The `grade` field IS encrypted string "ivB64...".
                // `linkedExamId` is a top-level field in `EncryptedGrade` struct?
                // Let's check `SubjectModels.swift` again.
                // lines 74-82: linkedExamId is a property of `EncryptedGrade`.
                // When saving, we save `EncryptedGrade`.
                // If we just update that field via merge, it should be fine.
                
                try await gradeRef.updateData([
                    "linkedExamId": sharedExam.id,
                    "updatedAt": Date()
                ])
                
                // Update local cache optimistically? 
                // GradesStore listeners should handle it.
            }
        }
        
        // 2. Transfer User Data (Notes, Reminders, Completion)
        
        // Notes
        if let note = localExam.notes, !note.isEmpty {
             try await setUserNoteForSharedExam(examId: sharedExam.id, note: note, groupId: sharedExam.groupId)
        }
        
        // Reminder
        if let reminder = localExam.reminderAt {
             try await setUserReminderForSharedExam(examId: sharedExam.id, reminderAt: reminder, groupId: sharedExam.groupId)
        }
        
        // Completion
        if localExam.isCompleted {
             await setUserCompletedForSharedExam(examId: sharedExam.id, completed: true, groupId: sharedExam.groupId)
        }
        
        // 3. Delete Local Exam
        await deleteExamFromFirestore(id: localExam.id)
    }
}
