# iOS GradesStore Fix Plan (2026-01-28)

## Decision Needed
- **Canonical course path**: choose one source of truth.
  - Recommendation: `classes/{classId}/courses/{courseId}` with `exams`/`homeworks` subcollections.
  - Confirm whether production data exists in top-level `/courses`.

---

## Phase 1 — Stop the bleeding (highest impact, minimal migration)
1) **Course content listeners start too early**
   - Move `startCourseContentListeners()` to run *after* courses are loaded.
   - Trigger from `rebuildCourses()` when course IDs change.

2) **Listener cleanup + stale maps**
   - `stopCourseContentListeners()` should clear `courseExamsMap` / `courseHomeworksMap` and rebuild shared lists (don’t wipe `sharedExams/sharedHomeworks`).
   - Ensure `stopListening()` + `resetSchoolYearScopedData()` remove:
     - `coursesQueriesListeners`
     - `courseExamsListeners` / `courseHomeworksListeners`
     - `courseMappingsListener`

3) **Legacy homework listener leak**
   - Remove the extra `homeworkGroups/.../subjects` listener in `updateSharedHomeworksListenerIfNeeded` (it overwrites the homeworks listener).
   - Use the dedicated `homeworkGroupSubjectsListener` instead.

4) **Shared-item dedup collisions**
   - Dedup by compound key (`groupId`/`courseId`/`classId` + `docId`) in `rebuildSharedExams()` and `rebuildSharedHomeworks()`.

5) **Group members listener cleanup**
   - Remove `groupMembersListeners` and `groupMemberIds` in `stopListening`, `resetSchoolYearScopedData`, and `leaveSharedGroup`.

---

## Phase 2 — Align schema + write paths
1) **Normalize course writes to class subcollections**
   - Update write paths in:
     - `addLegacyGroupToClass`
     - `addBranchToClass`
     - `addWahlpflichtfachGroupToClass`
     - `addCourseToClass`
     - `migrateGroupToClass` (exam/homework migrations)
     - `deleteClass`, `deleteCourse`

2) **Read-side compatibility**
   - Temporary fallback: read top-level `/courses` if class subcollection missing.

---

## Phase 3 — Data migration
1) **Move top-level `/courses` into `classes/{classId}/courses`**
2) **Backfill `id` fields for course exams/homeworks**
3) **Legacy migration gap**
   - Add `seminar` to migration + deletion
   - Add notes/rescheduled collections to deletion list

---

## Phase 4 — Schema consistency
1) **Class config field**
   - Standardize on `config` (or `courseConfiguration`) and migrate/alias the other.

2) **CourseType encoding**
   - Make branch update/removal accept current encoded schema (`type` + `associatedId`).

---

## Phase 5 — Verification
- Fresh login → course exams/homeworks appear.
- Join group → shared items appear, no dedup collisions.
- Legacy group migration → items visible in courses.
- Reset school year → no orphaned notes/reminders.

---

## Open Questions
- Do you prefer client-side or server-side migration for course path?
- Any production data in top-level `/courses`?
- Canonical field: `config` vs `courseConfiguration`?
