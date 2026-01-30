---
name: Notifications & Widgets
description: Specifications for background interactions, push notifications, and home screen widgets.
---

# Notifications & Widgets

This skill defines the background capabilities of the app.

## 1. Push Notifications (FCM)
*   **Provider**: Firebase Cloud Messaging (FCM).
*   **Handling**: `AppDelegate` / `FirebaseMessaging`.
*   **Payload Types**:
    *   `homework_reminder`: Triggers standard alert.
    *   `exam_reminder`: Triggers standard alert.
    *   `marketing`: (Optional) "Launch Offer" etc.
*   **Token Sync**: App updates FCM token to Firestore on every launch (`FirestoreService.updateFcmToken`).

## 2. Local Notifications (`UNUserNotificationCenter`)
*   **Managers**:
    *   `HomeworkNotificationManager`: Schedules reminders for due homework (e.g., "Math due tomorrow").
    *   `ExamNotificationManager`: Schedules exam reminders (e.g., "Exam in 1 day").
*   **Scheduling**:
    *   Triggered when an item is created/edited.
    *   Uses user preference for time (e.g., 19:00).

## 3. Home Screen Widgets (`ExamCountdownWidget`)
*   **Tech**: `WidgetKit` (SwiftUI).
*   **Data Source**: Shared `App Group` or direct Firestore fetch (if online/auth generic).
*   **Content**: "Next Exam" Countdown.
    *   **Timeline**: Updates every minute or hour.
    *   **Visual**: Circular progress + Days remaining.

## 4. Background Fetch
*   **Manager**: `BackgroundRefreshManager`.
*   **Task**: Periodically fetches new grades/exams to update Widget or Local Notifications without app launch.
*   **Framework**: `BGTaskScheduler`.

## 5. Android Porting Note
*   **Notifications**: Use `WorkManager` for local scheduling and `FirebaseMessagingService` for remote.
*   **Widgets**: Use `AppWidgetProvider`. Replicate the "Countdown" logic.
