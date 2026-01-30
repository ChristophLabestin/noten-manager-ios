---
name: Feature Development
description: Guidelines for implementing major features like Exams, Homework, and Classes.
---

# Feature Development

This skill provides guidelines for building major functional features in `noten-manager-ios`, covering the View Layer, Data Layer, and Standard Patterns.

## 1. Standard View Patterns

### The "List-Detail-Edit" Triad

Most features (Exams, Homework, Classes) follow this structure:

1.  **List View** (`FeatureListView.swift`):
    *   **Role**: Displays a collection of items.
    *   **State**: Observes `@EnvironmentObject var store: GradesStore`.
    *   **Navigation**: Uses `NavigationLink` to Detail or `.sheet` for Creation.
    *   **UI**: Often uses a `ThemedBackground` and `ScrollView`.
    
2.  **Detail View** (`FeatureDetailView.swift` / `Sheet`):
    *   **Role**: Shows full details of an item.
    *   **Interaction**: Often presented as a `.sheet` with `presentationDetents`.
    
3.  **Edit/Create View** (`EditFeatureView.swift`):
    *   **Role**: Form to create or modify data.
    *   **State**: Uses local `@State` for form fields.
    *   **Action**: Calls an `async` function in `GradesStore` or `FirestoreService`.
    *   **Feedback**: Uses `UINotificationFeedbackGenerator` on success/error.

### Async Action Pattern (in Views)

When a user triggers an action (e.g., "Create Class"):

```swift
@State private var isCreating: Bool = false
@State private var errorMessage: String?
@Environment(\.dismiss) private var dismiss

// ... in body
Button {
    Task { await performAction() }
} label: {
    if isCreating {
        ProgressView()
    } else {
        Text("Save")
    }
}
.disabled(isCreating)

// ... helper
@MainActor
private func performAction() async {
    isCreating = true
    errorMessage = nil
    
    // 1. Validate
    guard isValid else {
        errorMessage = "Invalid input"
        isCreating = false
        return
    }
    
    // 2. Execute
    do {
        try await store.someAsyncAction(...)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    } catch {
        errorMessage = error.localizedDescription
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
    isCreating = false
}
```

## 2. Backend Interaction (`FirestoreService`)

*   **Role**: Handles direct raw Firestore operations (Read/Write).
*   **Singleton**: Accessed via `FirestoreService.shared`.
*   **Best Practice**:
    *   Simple reads/writes can go in `FirestoreService`.
    *   Complex business logic (like creating a Class *and* its sub-courses) should be orchestrated in `GradesStore` or a dedicated Service, which then calls `FirestoreService` or Firestore directly.

## 3. The "Classes" Architecture

The app is migrating from "Groups" to "Classes".
*   **Class**: Represents a school class (e.g., "10b").
*   **Course**: Represents a subject instance (e.g., "Math 10b"). Students subscribe to *Courses*, not just the Class.
*   **Creation**: See `ClassCreationView`. Use `GradesStore.createClassWithCourses` to handle the transactional complexity of creating the Class doc and multiple Course docs simultaneously.

## 4. Notifications

*   **Local**: Handled via `UNUserNotificationCenter` (mostly for reminders).
*   **Remote/Inbox**: `NotificationsInboxView` displays in-app notifications.
*   **Tokens**: `FirestoreService.updateFcmToken` ensures the user is reachable.

## 5. UI Composition

Use `AppStyleComponents` to build forms!
*   **Input Fields**: Wrap `TextField` in a `SettingsCard`.
*   **Lists**: Use `FlowLayout` for tags/chips (like Subjects).
*   **Headers**: Use large system icons with the feature's theme color (e.g., Indigo for Classes).
