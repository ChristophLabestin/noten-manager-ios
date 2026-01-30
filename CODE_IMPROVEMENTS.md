# Code Improvement & Crash Risk Log

# Code Improvement & Crash Risk Log

## Crash- or Freeze-Prone Spots
- Managers/AuthManager.swift:332-341 – `randomNonceString` `fatalError`/`precondition` on SecRandomCopyBytes failure; prefer throwing or fallback generation to avoid app-kill paths during low-entropy or keychain issues.
- Managers/CryptoService.swift:16-37 – `generateSalt`/`encryptString` also crash via preconditions if SecRandomCopyBytes fails; return errors and surface them to auth/onboarding UI instead of aborting.
- Managers/OfflineModeManager.swift:195-198 – force unwrap of the documents directory can crash in rare app-extension/sandbox states; guard/throw and surface failure when persisting offline snapshots.
- Managers/DailyReminderNotificationManager.swift:127-145 – reminder time is built from `now` rather than `tomorrow`, so “tomorrow” reminders fire the same day or fall back to 5‑minute timer; use `tomorrow` components to prevent wrong-day notifications.
- Stores/GradesStore.swift:552-595 – duplicated removal of `sharedHomeworkUserNotesListener` hints at missed cleanup for some listeners; lingering listeners can crash on callbacks after logout or account switch. Audit listener lifecycle and add tests.

## Logic / Correctness Issues
- Core/MainView.swift:125-130 – `LaunchOfferNotificationManager.consumePendingOpen()` is called twice in a row; the first call clears the flag so the second is a no-op and risks missing future events if state changes mid-block.
- Managers/HolidaysService.swift:48-58 – `try? await fetchHolidays` is used even though `fetchHolidays` is non-throwing; likely leftover from an API change. Either make the fetch throwing with proper error handling or remove `try?` to simplify the flow and logging.
- GradeCalculationService.swift (overall) – final grade computation is a simplified heuristic without guardrails for invalid weights/half-year counts. Add validation and unit tests to prevent incorrect report card output.

## Robustness & Performance
- Managers/ExamLiveActivityManager.swift:102-143 – `scheduleAutoEnd` spawns long-lived `Task.sleep` jobs with no cancellation token; tasks continue even after exams are deleted, risking activity churn and late termination. Track tasks per activity and cancel when exams change.
- Managers/ExamLiveActivityManager.swift:151-174 – `registerPushToken` launches an untracked task over `pushTokenUpdates`; if the user logs out or activities are disabled the task keeps running. Store/cancel these tasks and gate on `areActivitiesEnabled`.
- BackgroundRefreshManager.swift:33-118 & 185-240 – background work reads snapshot files with `Data(contentsOf:)` during BG tasks without handling data-protection errors; in protected state this can throw and end the task. Add explicit error handling, backoff, and ensure BG tasks respect `task.expirationHandler`.
- OfflineModeManager.swift:160-180 – snapshot encoding/writing runs on the main actor, blocking UI during large datasets. Move disk I/O to a background actor/queue and surface errors via logging.
- Notification scheduling (Daily/Exam/Homework managers) – scheduling is re-run on every update without debouncing, causing repeated fetch/removal cycles. Introduce simple coalescing to reduce battery impact and race windows.

## Maintainability / Testing
- Stores/GradesStore.swift (4000+ lines) – monolithic store mixes persistence, encryption, notifications, and UI flags. Split into smaller services (subjects, exams/homeworks, settings) with protocols to enable unit tests and safer listener management.
- Add regression tests for GradeCalculationService, HomeworkShareLinkBuilder, and Subject sorting/filtering to catch weighting or parsing errors early.
- Extend ErrorLoggingService to capture unhandled promise rejections/Task failures in notification managers and ActivityKit flows; current `try?` usage hides errors that could explain App Store crashes.

## Crash- or Freeze-Prone Spots
- [x] Managers/AuthManager.swift:332-341 – `randomNonceString` `fatalError`/`precondition` on SecRandomCopyBytes failure; now falls back instead of crashing.
- [x] Managers/CryptoService.swift:16-37 – `generateSalt`/`encryptString` preconditions could crash; now fall back on failure.
- [x] Managers/OfflineModeManager.swift:195-198 – force unwrap of the documents directory; now guarded with a safe fallback.
- [x] Managers/DailyReminderNotificationManager.swift:127-145 – reminder time built from `now` instead of `tomorrow`, causing wrong-day notifications; fixed to use tomorrow’s components.
- [x] Stores/GradesStore.swift:552-595 – duplicated removal of `sharedHomeworkUserNotesListener` indicating missed cleanup; deduplicated and safer.

## Logic / Correctness Issues
- [x] Core/MainView.swift:125-130 – duplicate `consumePendingOpen()` call cleared state twice; removed duplicate.
- [x] Managers/HolidaysService.swift:48-58 – unnecessary `try? await fetchHolidays` despite non-throwing API; simplified flow.
- [x] GradeCalculationService.swift – added basic validation (ignore non-positive weights, clamp/NaN guard); still add unit tests for full coverage.

## Robustness & Performance
- [x] Managers/ExamLiveActivityManager.swift:102-174 – `Task.sleep` auto-end and push-token flows were untracked; now tasks are tracked and cancelled to avoid runaway work and stale activities.
- [x] BackgroundRefreshManager.swift:33-118 & 185-240 – BG tasks lacked data-protection checks and expiration logging; now gate on protected data availability, log expirations, and add safer snapshot reads.
- [x] OfflineModeManager.swift:160-180 – snapshot encoding/writing on main actor can block UI for large datasets; moved encoding/writing off the main actor, still surface errors.
- [x] Notification scheduling (Daily/Exam/Homework managers) – added lightweight debounce to reduce rapid re-scheduling; consider more robust coalescing if needed.

## Maintainability / Testing
- [ ] Stores/GradesStore.swift (4000+ lines) – monolithic store mixes persistence, encryption, notifications, and UI flags; split into smaller services with protocols and tests.
- [ ] Add regression tests for GradeCalculationService, HomeworkShareLinkBuilder, and subject sorting/filtering to catch weighting/parsing errors early.
- [ ] Extend ErrorLoggingService to capture notification/ActivityKit task failures; add unit tests for notification flows and utilities.
