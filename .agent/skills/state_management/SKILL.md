---
name: State Management
description: Guidelines for managing app state, data persistence, and Firebase interactions.
---

# State Management

This skill defines how to manage state in `noten-manager-ios`, focusing on the `GradesStore` class and Firestore interactions.

## Core Architecture

### 1. `GradesStore` (The Source of Truth)
*   **Type**: `ObservableObject` (`@EnvironmentObject`).
*   **Role**: Manages all app state, user session, and live data listeners.
*   **Key Properties**:
    *   `subjects`, `gradesBySubject`: Core data.
    *   `schoolType`, `gradeYear`: Global configuration.
    *   `classDetails`, `courses`: New architecture entities.
    *   `isPrivacyModeActive`: UI state.
    *   `activeSchoolYearId`: Critical scope for current data.

### 2. Firestore Structure
*   **Users Collection**: `users/{uid}`
    *   Holds preferences (`appIcon`, `theme`) and global state.
    *   **SchoolYears Subcollection**: `users/{uid}/schoolYears/{yearId}`
        *   Holds data scoped to a specific school year.
        *   **Subjects Subcollection**: `.../subjects/{subjectId}`
            *   **Grades Subcollection**: `.../grades/{gradeId}`
    *   **Courses/Classes**: (New Architecture)
        *   `classes/{classId}`: Class configurations.
        *   `courses/{courseId}`: Course definitions.

### 3. Data Flow

1.  **Auth & Init**: `startListening()` called on app launch. Authenticates user, loads `userDoc`.
2.  **School Year Scope**: Determines `activeSchoolYearId`. Starts listeners for that year's subcollections.
3.  **Live Updates**: Changes in Firestore automatically update `@Published` properties.
4.  **Optimistic UI**: Use local state for immediate feedback, but generally rely on Firestore listeners for the "truth".

## Working with `SchoolYearService`

*   **Id Generation**: `2025-26` format.
*   **Migration**: Handles moving data from legacy flat structure to `schoolYears` subcollections.

## Best Practices

### 1. Modifying Data
*   **DO NOT** modify `@Published` arrays (like `subjects`) directly from Views.
*   **USE** `GradesStore` methods (or Service methods) that perform the Firestore write.
    *   Example: `GradesService.addGrade(...)` -> Firestore Write -> Listener fires -> `GradesStore` updates.

### 2. Reading Data
*   Access properties directly on `store`.
*   Avoid complex filtering in `body`. Use computed properties or helper functions in `GradesStore` if expensive.

### 3. New Architecture (Classes & Courses)
*   **Transition**: The app is moving from "Groups" to "Classes/Courses".
*   **Courses**: `Course` model holds `classId`.
*   **Subscriptions**: `subscribedCourseIds` determines what a student sees.

## Offline Mode
The app has basic offline support via `OfflineModeManager` and local caching.
*   **Pending Data**: Writes made while offline are queued in `offlinePendingGrades`.
*   **Sync**: `overlayPendingData()` merges offline changes into the live view until sync occurs.
