# iOS GradesStore Fix Plan (2026-01-28)

## Decision Needed
- **Canonical course path**: choose one source of truth.
  - Recommendation: `classes/{classId}/courses/{courseId}` with `exams`/`homeworks` subcollections.
  - Confirm whether production data exists in top-level `/courses`.

---

## Phase 1 — Stop the bleeding (highest impact, minimal migration)
1) ✅ **Course content listeners start too early**
   - `startCourseContentListeners()` now runs after courses load via `rebuildCourses()`.
   - Listener startup triggers when course IDs change or listeners are missing.

2) ✅ **Listener cleanup + stale maps**
   - `stopCourseContentListeners()` clears `courseExamsMap` / `courseHomeworksMap` and rebuilds shared lists.
   - `stopListening()` + `resetSchoolYearScopedData()` remove:
     - `coursesQueriesListeners`
     - `courseExamsListeners` / `courseHomeworksListeners`
     - `courseMappingsListener`

3) ✅ **Legacy homework listener leak**
   - Duplicate legacy listener removed; `homeworkGroupSubjectsListener` kept.

4) ✅ **Shared-item dedup collisions**
   - Dedup now uses compound keys.

5) ✅ **Group members listener cleanup**
   - Member listeners + caches cleared in all teardown paths.

6) ✅ **Shared user settings scoped by source**
   - Per-user keys now include course/class context; legacy keys cleaned up on write/delete.

7) ✅ **Wahlpflicht listener refresh on join/leave**
   - `updateWahlpflichtfachExamsObservers()` called after membership changes.

8) ✅ **Preserve shared exam metadata on user-state apply**
   - `classId` and `assessmentType` retained when applying reminders/completion/reschedule.

9) ✅ **Leave class removes legacy course subscriptions**
   - Also removes top-level `/courses` by `classId`.

10) ✅ **Delete class/course removes subcollections**
   - `deleteClass` and `deleteCourse` now delete `exams`/`homeworks` subcollections (plus class `members`/`exams`).

---

## Phase 2 — Align schema + write paths
1) ✅ **Normalize course writes to class subcollections**
   - Updated write paths in:
     - `addLegacyGroupToClass`
     - `addBranchToClass`
     - `addWahlpflichtfachGroupToClass`
     - `addCourseToClass`
     - `migrateGroupToClass` (exam/homework migrations)
     - `deleteClass`, `deleteCourse`

2) ✅ **Read-side compatibility**
   - Added fallback for legacy top-level `/courses` by `documentID` and decode fixes.

---

## Phase 3 — Data migration
1) ◐ **Move top-level `/courses` into `classes/{classId}/courses`**
   - Implemented per-course migration when legacy path detected.
   - Added opt-in helper `cleanupLegacyTopLevelCourses(deleteLegacy:)` for owner-scoped cleanup; not wired to UI.
2) ✅ **Backfill `id` fields for course exams/homeworks**
   - Decode path now writes missing `id` back to Firestore.
   - Course docs also backfill `classId` from path when missing.
3) ✅ **Legacy migration gap**
   - Added `seminar` to migration + deletion.
   - Added notes/rescheduled collections to deletion list.

---

## Phase 4 — Schema consistency
1) ✅ **Class config field**
   - Reads accept `config` or `courseConfiguration`; updates target existing field.

2) ✅ **CourseType encoding**
   - Branch update/removal accepts `type` + `associatedId`.

---

## Phase 5 — Verification
- Fresh login → course exams/homeworks appear.
- Join group → shared items appear, no dedup collisions.
- Legacy group migration (old shared groups) → items visible in courses.
- Reset school year → no orphaned notes/reminders.

---

## Open Questions
- Do you prefer client-side or server-side migration for course path?
- Any production data in top-level `/courses`?
- Canonical field: `config` vs `courseConfiguration`?
