# iOS GradesStore Audit (2026-01-28)

## Scope
- Primary focus: `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift`
- Supporting context: `noten-manager-ios/noten-manager-ios/Stores/GradesStore+Merge.swift`,
  `noten-manager-ios/noten-manager-ios/Models/CourseModels.swift`,
  `noten-manager-ios/noten-manager-ios/Models/ExamModels.swift`,
  `noten-manager-ios/noten-manager-ios/Models/HomeworkModels.swift`

## Summary of Key Risk Areas
- **Course/class Firestore path drift**: multiple code paths still write to top-level `/courses` while newer logic reads from `/classes/{classId}/courses`.
- **Listener lifecycle issues**: missing removals, duplicate listeners, and setup order problems likely cause stale data, extra reads, and UI inconsistencies.
- **Migration/deletion gaps**: some legacy collections are not migrated or deleted, leaving data behind.
- **Aggregation/dedup collisions**: shared exams/homeworks are de-duplicated only by `id`, risking collisions across sources.
- **Schema field drift**: `config` vs `courseConfiguration` and `type` vs `case` encoding for `CourseType`.

---

## Findings (Detailed)

### 1) Courses stored in multiple Firestore paths (high impact)
**Issue**
- New logic assumes courses live under `classes/{classId}/courses`, but multiple functions still create, update, or delete courses in a top-level `courses` collection.
- Exam/homework migration also writes to `/courses/{courseId}/exams` and `/courses/{courseId}/homeworks` rather than the class subcollection.

**Evidence**
- Listener assumes subcollection: `startCourseContentListeners` uses `classes/{classId}/courses/{courseId}`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2670-2694`
- Comments state “courses now in classes/{cid}/courses”. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2590-2594`
- Top-level course creation:
  - `addLegacyGroupToClass` creates courses in `/courses`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5916-5929`
  - `addBranchToClass` creates courses in `/courses`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6141-6156`
  - `addWahlpflichtfachGroupToClass` creates courses in `/courses`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6218-6234`
  - `addCourseToClass` creates courses in `/courses`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6379-6392`
- Top-level course deletion/query:
  - `deleteCourse` deletes from `/courses`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6400-6406`
  - `deleteClass` queries `/courses` to delete class courses. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5240-5246`
- Migration writes exam/homework to `/courses/{courseId}`:
  - `migrateGroupToClass` writes to `/courses/{courseId}/exams` and `/homeworks`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5401-5417, 5435-5448`
  - `addLegacyGroupToClass` migration also writes to `/courses/{courseId}/exams` and `/homeworks`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5948-5994`

**Impact / likely symptoms**
- Course exams/homeworks created via older paths are not visible because listeners read only `classes/{classId}/courses/{courseId}`.
- Deleting a class might not delete any subcollection courses (if they were stored under classes).
- Migrated group exams/homeworks can appear to “disappear” because they are stored in a path not read by the UI.

**Recommendation**
- Pick a single canonical path (prefer `classes/{classId}/courses`) and update all write/read/delete/migration code to use it.
- Consider a one-time migration script to move top-level `/courses` into the class subcollection.

---

### 2) Course listeners start before course list is populated (high impact)
**Issue**
- `startCoursesListener` calls `startCourseContentListeners()` immediately, before `courses` has been populated by the Firestore snapshot.
- `rebuildCourses()` never calls `startCourseContentListeners()` after `courses` changes.

**Evidence**
- `startCoursesListener` calls `startCourseContentListeners` before queries run. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2572-2586`
- `startCourseContentListeners` iterates current `courses` array. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2670-2679`
- `rebuildCourses` only updates `self.courses` and does not start listeners. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2619-2652`

**Impact / likely symptoms**
- Course-based exams/homeworks never load on fresh app start (unless `courses` were already cached in memory).

**Recommendation**
- Start course content listeners after `courses` is populated (e.g., call `startCourseContentListeners()` inside `rebuildCourses()` or after the first snapshot loads).

---

### 3) Course listener cleanup wipes non-course shared data (high impact)
**Issue**
- `stopCourseContentListeners()` clears `sharedExams` and `sharedHomeworks`, even though those arrays also include group/class/wahlpflicht items.
- It also does not clear `courseExamsMap`/`courseHomeworksMap`, so stale course data can reappear later.

**Evidence**
- `stopCourseContentListeners` clears shared arrays. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2659-2667`
- `courseExamsMap`/`courseHomeworksMap` are never cleared. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2700-2701`

**Impact / likely symptoms**
- Toggling subscriptions or reloading courses can temporarily wipe shared items from groups/classes.
- Stale course exams/homeworks can “come back” after unrelated recomputation.

**Recommendation**
- Only remove course-derived items (clear `courseExamsMap`/`courseHomeworksMap`) and rebuild shared lists, rather than clearing `sharedExams`/`sharedHomeworks` directly.

---

### 4) Shared exams/homeworks deduping ignores source (high impact)
**Issue**
- `rebuildSharedExams` and `rebuildSharedHomeworks` de-duplicate by `id` only, ignoring `groupId/courseId/classId`.
- There are helper functions that use compound IDs, but they are not used.

**Evidence**
- `rebuildSharedExams` unique by `id` only. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2747-2755`
- `rebuildSharedHomeworks` unique by `id` only. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2796-2813`
- Unused helpers using compound IDs. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:10170-10192`

**Impact / likely symptoms**
- Exams/homeworks from different sources can collide and one disappears if their document IDs match.

**Recommendation**
- Use `compoundId(gid: docId)` or include `courseId/classId` in the key when de-duplicating.

---

### 5) Legacy migration misses `seminar` data (high impact)
**Issue**
- Legacy data migration does not copy the `seminar` collection, even though the new schema expects it.

**Evidence**
- `migrateLegacyDataIfNeeded` copies `fachreferat`, `practicalPerformance`, `homeworks`, etc., but not `seminar`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:166-177`
- `deleteSchoolYearData` explicitly deletes `seminar`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:1141-1149`

**Impact / likely symptoms**
- Seminar performance data may be lost on migration to school years.

**Recommendation**
- Include `seminar` in legacy migration or add a one-off migration for it.

---

### 6) School-year deletion leaves user-specific data behind (medium)
**Issue**
- `deleteSchoolYearData` omits several collections that are used elsewhere (`examGroupNotes`, `homeworkGroupNotes`, `examGroupRescheduled`, `courseMappings`).

**Evidence**
- Delete list includes reminders/completed/mappings, but not notes or rescheduled. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:1141-1155`
- Notes/rescheduled collections are used by listeners and setters. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:1661-1726` (notes) and `1702-1732` (rescheduled)

**Impact / likely symptoms**
- Orphaned documents persist after school year reset; potential reappearance of stale data.

**Recommendation**
- Add all user-specific collections to delete list.

---

### 7) Duplicate listener for legacy homework groups + leaked listener (medium)
**Issue**
- `updateSharedHomeworksListenerIfNeeded()` assigns `sharedHomeworksListener` twice (subjects then homeworks), overwriting the first listener reference and making it impossible to remove.
- It also duplicates the dedicated `homeworkGroupSubjectsListener` (same data source).

**Evidence**
- Overwrites `sharedHomeworksListener` with subject listener, then overwrites it with homeworks listener. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:4153-4168`
- Separate legacy listener already exists: `homeworkGroupSubjectsListener`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:801-803` and `9697-9720`

**Impact / likely symptoms**
- Extra Firestore listeners and unexpected updates; possible memory/CPU cost.

**Recommendation**
- Use two separate listener variables (subjects + homeworks) or reuse the existing `homeworkGroupSubjectsListener` and only keep a single `sharedHomeworksListener` for homeworks.

---

### 8) Group member listeners are not cleaned up (medium)
**Issue**
- `groupMembersListeners` are not removed in `stopListening` or `resetSchoolYearScopedData`.
- `leaveSharedGroup` also does not remove the member listener or `groupMemberIds` cache.

**Evidence**
- `stopListening` removes subjects/mappings/names but not members. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:650-655`
- `resetSchoolYearScopedData` removes mappings but not member listeners. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:813-818`
- `leaveSharedGroup` removes other listeners but not member listeners or `groupMemberIds`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6727-6739`

**Impact / likely symptoms**
- Background listeners stay active after logout or group leave; stale member data.

**Recommendation**
- Remove `groupMembersListeners` wherever other group listeners are removed, and clear `groupMemberIds` for the group.

---

### 9) Class config field drift: `config` vs `courseConfiguration` (medium)
**Issue**
- New class creation stores configuration under `config`, but other readers/updaters expect `courseConfiguration`.

**Evidence**
- `createClassWithCourses` writes `config`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:4752-4757`
- `fetchClassDetails` reads only `courseConfiguration` (ignores `config`). `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6511-6514`
- `addBranchToClass` / `updateBranch` / `removeBranch` update `courseConfiguration`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6160-6174, 6264-6278, 6305-6316`

**Impact / likely symptoms**
- Class details view may show empty or outdated configuration.
- Branch updates can diverge from the authoritative `config` field.

**Recommendation**
- Standardize on a single field and migrate/alias the other.

---

### 10) CourseType encoding mismatch (`type` vs `case`) (medium)
**Issue**
- `CourseType.encode` writes `{ "type": "branch", "associatedId": "..." }`, but branch update/removal code expects `{ "case": "branch", "associatedId": "..." }`.

**Evidence**
- Encoding uses `type` key. `noten-manager-ios/noten-manager-ios/Models/CourseModels.swift:114-127`
- Update/remove branch check uses `typeMap["case"]`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6287-6295, 6325-6333`

**Impact / likely symptoms**
- Branch updates/deletes may fail for newly encoded courses.

**Recommendation**
- Update branch logic to accept the new encoded schema (or normalize in migration).

---

### 11) Unused / stale course listener cleanup (medium)
**Issue**
- `applySchoolYearSettings` clears a `coursesListener` that is never used, while actual listeners live in `coursesQueriesListeners`.

**Evidence**
- `coursesListener` is only declared and removed, never set. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:482, 3200-3202`
- Actual listeners are `coursesQueriesListeners`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2569-2616`

**Impact / likely symptoms**
- When subscriptions are cleared, query listeners may keep running.

**Recommendation**
- Remove `coursesListener` and explicitly tear down `coursesQueriesListeners` + course content listeners when subscriptions become empty.

---

### 12) Course exam/homework decode requires `id` field (medium)
**Issue**
- `startCourseContentListeners` uses `data(as: Exam.self)` and `data(as: Homework.self)`. The decoders require `id` in document data. Legacy docs without `id` will not decode.

**Evidence**
- Course listeners decode using `data(as:)`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2682-2693`
- `Exam` requires `id` in decoder. `noten-manager-ios/noten-manager-ios/Models/ExamModels.swift:59-66`
- `Homework` requires `id` in decoder. `noten-manager-ios/noten-manager-ios/Models/HomeworkModels.swift:3-23`

**Impact / likely symptoms**
- Course items created before the “id field fix” appear to vanish.

**Recommendation**
- Backfill `id` fields or decode using `documentID` as fallback.

---

### 12b) Course subscription query skips docs missing `id` (medium)
**Issue**
- `startCoursesListener` uses a collectionGroup query filtered by `id`. Legacy course docs without an `id` field are never returned and may be pruned as “stale.”

**Evidence**
- Query uses `.whereField("id", in: chunk)` on `collectionGroup("courses")`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2628-2635`

**Impact / likely symptoms**
- Courses created before the `id` field was introduced can disappear from the UI and be removed from `subscribedCourseIds`.

**Recommendation**
- Add a legacy fallback query on top-level `/courses` by `documentID`, and/or backfill `id` on those documents.

---

### 13) School year list ordering likely incorrect (low/medium)
**Issue**
- `startSchoolYearsListener` orders by `id` field, but school year docs only set `name` + `createdAt`.

**Evidence**
- Query uses `.order(by: "id")`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:1016-1021`
- `createSchoolYear` writes `name` + `createdAt`, not `id`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:1078-1086`

**Impact / likely symptoms**
- Firestore ordering may be undefined or require extra index; potential listener errors.

**Recommendation**
- Order by `createdAt` or use `documentID` ordering.

---

### 14) Group name lookup ignores legacy collections (low/medium)
**Issue**
- Group name lookup reads from `/groups` only, even for legacy `examGroups`/`homeworkGroups`.

**Evidence**
- `loadExamGroupName` queries `/groups/{gid}`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6661-6666`
- `loadHomeworkGroupName` queries `/groups/{gid}`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6786-6790`

**Impact / likely symptoms**
- Legacy group names show as empty or `nil`.

**Recommendation**
- Fallback to legacy collections if `groups/{gid}` is missing.

---

### 15) Redundant calls in `joinSharedGroup` (low)
**Issue**
- `joinSharedGroup` calls `updateGroupObservers` and `loadGroupName` twice.

**Evidence**
- Duplicate calls near end of method. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:4402-4407`

**Impact / likely symptoms**
- Redundant reads and extra UI refreshes.

**Recommendation**
- Remove the duplicate calls.

---

### 16) Subject deletion tries to remove subscriptions by subject name (low)
**Issue**
- `deleteSubjectFromFirestore` removes `subjectName` from `subscribedCourseIds`, but that list stores course IDs (not subject names).

**Evidence**
- `deleteSubjectFromFirestore` checks `subscribedCourseIds.contains(subjectName)`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:9611-9616`

**Impact / likely symptoms**
- Subscription cleanup does not happen; stale course subscriptions remain.

**Recommendation**
- Remove course IDs that actually map to the deleted subject (via `courseMappings` or `course.name`).

---

### 17) Group/Class/Wahlpflicht removal doesn’t fully clear shared listeners (medium)
**Issue**
- `updateGroupObservers`, `updateClassExamsObservers`, and `updateWahlpflichtfachExamsObservers` remove metadata listeners, but do not consistently remove exam/homework listeners or recompute shared lists when an ID is removed.

**Evidence**
- `updateGroupObservers` removes subject/mapping/name/member listeners only; exam/homework listeners are not removed there. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:10144-10210`
- `updateClassExamsObservers` removes `classExamsByClass` entries but does not recompute. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:10369-10379`
- `updateWahlpflichtfachExamsObservers` removes entries but does not recompute. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:10437-10447`

**Impact / likely symptoms**
- When a user is removed from a group/class (or leaves a Wahlpflicht group), stale shared exams/homeworks can remain visible until another unrelated listener fires.
- Orphaned listeners can remain active for groups removed outside `leaveSharedGroup`.

**Recommendation**
- Ensure group/class/wahlpflicht observer cleanup removes all relevant listeners + data maps and triggers `recomputeSharedCollections()` when removals occur.

---

### 18) Course docs missing `classId` break course content listeners (medium)
**Issue**
- `startCourseContentListeners` relies on `course.classId` to build the course path. If a course document lacks `classId`, the listener skips the course entirely even if the doc lives under `classes/{classId}/courses`.

**Evidence**
- Listener requires `classId` to build `classes/{classId}/courses/{courseId}`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2917-2936`
- Course decoding uses document fields, not path, so missing `classId` yields `nil`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2608-2624`

**Impact / likely symptoms**
- Course exams/homeworks never load for affected courses.

**Recommendation**
- Derive `classId` from the document path when missing and backfill it to Firestore.

---

### 19) Shared user settings collide across sources (medium)
**Issue**
- Per-user reminders/notes/completion for shared items are keyed by `groupId|docId` or just `docId`. For class/course shared exams and homeworks, `groupId` is `nil`, so different sources can collide if document IDs match.

**Evidence**
- `compoundId` uses `groupId` only, and fallbacks use just `exam.id` / `homework.id`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2452-2578`

**Impact / likely symptoms**
- A reminder or completion flag from a course exam could mistakenly apply to a class/group exam with the same document ID.

**Recommendation**
- Scope per-user keys by source (e.g., `course:{courseId}|{docId}`, `class:{classId}|{docId}`) and keep a fallback for existing data.

---

### 20) Shared exam user‑state drops `classId` + `assessmentType` (low/medium)
**Issue**
- When applying user reminders/completion/reschedule to shared exams, the code rebuilds `Exam` objects without preserving `classId` or `assessmentType`.

**Evidence**
- In `applySharedExamUserReminders`, `applySharedExamUserCompletion`, and `applySharedExamUserRescheduledDates`, new `Exam` instances are created without `classId` or `assessmentType`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2466-2588`

**Impact / likely symptoms**
- Class exams can lose `classId`, causing dedup/labeling issues.
- `assessmentType` can disappear from UI after applying user state.

**Recommendation**
- Preserve `classId` and `assessmentType` when rebuilding shared exam entries.

---

### 21) Legacy course migration flag is global across users (low/medium)
**Issue**
- The “legacy course migration completed” list is stored in `UserDefaults` without scoping to the current user, so switching accounts can skip necessary migrations.

**Evidence**
- `legacyCourseMigrationKey` is a global key and is used without UID scoping. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2745-2790`

**Impact / likely symptoms**
- A different user account on the same device might never migrate legacy course content.

**Recommendation**
- Scope migration keys by `uid` (e.g., `legacyCourseMigration_v1_<uid>`).

---

### 22) Wahlpflicht exams listeners not refreshed on join/leave (low/medium)
**Issue**
- Joining or leaving a Wahlpflichtfach group updates local IDs but does not restart the exam listeners, so shared exams may not appear or may keep listening after leave.

**Evidence**
- `joinWahlpflichtfachGroup`/`leaveWahlpflichtfachGroup` update `wahlpflichtfachGroupIds` without calling `updateWahlpflichtfachExamsObservers`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:4777-4904`

**Impact / likely symptoms**
- Missing Wahlpflicht exams after join; lingering listeners after leave.

**Recommendation**
- Call `updateWahlpflichtfachExamsObservers()` after changes to `wahlpflichtfachGroupIds`.

---

### 23) Leaving class ignores legacy top‑level courses (low/medium)
**Issue**
- `leaveClass` unsubscribes from `classes/{classId}/courses` only, but legacy top‑level `/courses` with `classId` can remain subscribed.

**Evidence**
- Unsubscribe uses only the class subcollection; no query against top‑level `courses`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5428-5468`

**Impact / likely symptoms**
- Stale `subscribedCourseIds` linger after leaving a class with legacy courses.

**Recommendation**
- Also remove top‑level courses where `classId == classId` from subscriptions.

---

### 24) Legacy shared-user docs linger after rekeying (low/medium)
**Issue**
- If shared user settings start using a new key format, legacy documents keyed by raw `examId` / `homeworkId` can remain and keep applying via fallback logic.

**Evidence**
- User settings fall back to `exam.id`/`homework.id` when a keyed entry is missing. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2466-2578`

**Impact / likely symptoms**
- Users can’t fully clear old reminders/notes/completion after rekeying.

**Recommendation**
- When writing/removing a new scoped key, also delete the legacy doc ID to prevent fallback collisions.

---

### 25) Course subscription query chunk size may exceed Firestore `in` limits (low/medium)
**Issue**
- The subscription query chunks `subscribedCourseIds` into batches of 30 for a Firestore `in` query; Firestore `in` has a strict maximum (historically 10).

**Evidence**
- `subscribedCourseIds.chunked(into: 30)` followed by `.whereField("id", in: chunk)`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:2689-2694`

**Impact / likely symptoms**
- If the limit is lower than 30, the listener will error for larger chunks and courses will not load.

**Recommendation**
- Confirm the current Firestore `in` limit and adjust chunk size accordingly.

**Status**
- Chunk size reduced to 10 to stay within older Firestore limits.

---

### 26) Course/class deletions leave subcollections orphaned (low)
**Issue**
- `deleteClass` and `deleteCourse` delete parent documents but do not delete subcollections (`exams`, `homeworks`), leaving orphaned documents and potential storage growth.

**Evidence**
- `deleteClass` batches only course docs and class doc; subcollection deletion is explicitly skipped. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5518-5534`
- `deleteCourse` deletes only the course document. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:6616-6640`

**Impact / likely symptoms**
- Hidden orphaned data accumulates; storage grows; potential privacy risk if data is assumed deleted.

**Recommendation**
- Add recursive delete via Cloud Function or client-side cleanup of subcollections.

**Status**
- Client-side subcollection cleanup added in `deleteClass` and `deleteCourse`.

---

### 27) Class course fetch ignores legacy top‑level courses (low/medium)
**Issue**
- `fetchCoursesForClass` queries only `classes/{classId}/courses`, so legacy top‑level `/courses` with `classId` are skipped.

**Evidence**
- Fetch uses only class subcollection; no fallback query. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:5438-5445`

**Impact / likely symptoms**
- Join/leave flows that depend on `fetchCoursesForClass` won’t subscribe/unsubscribe to legacy courses.

**Recommendation**
- Merge in top‑level `/courses` where `classId == classId`.

**Status**
- `fetchCoursesForClass` now merges legacy top‑level courses and dedupes by ID.

---

## Additional Observations
- `stopListening` does not stop course query listeners (`coursesQueriesListeners`) or course content listeners. Combined with missing cleanup of `courseExamsMap`, this can leave stale course data in memory. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:587-664, 2659-2701`
- There are two different mapping stores: `groupMappings` (new) and `subjectMappings` (legacy). Only legacy migration copies `subjectMappings`. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:166-177, 9759-9794`
- The helper functions `mergeSharedExams`/`mergeSharedHomeworks` (compound-ID based) are currently unused, suggesting previous logic was replaced but not fully integrated. `noten-manager-ios/noten-manager-ios/Stores/GradesStore.swift:10170-10192`

---

## Suggested Next Steps (if you want follow-up)
- I can draft a single-source-of-truth schema for courses/classes/groups and provide a migration plan.
- I can also prepare targeted fixes for the listener lifecycle issues and the course content listener startup order.
