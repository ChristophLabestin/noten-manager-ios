---
name: Data Schema
description: Validation-ready schema of all data models and Firestore paths for Android porting.
---

# Data Schema

This skill serves as the **Single Source of Truth** for the app's data layer. Use this to ensure the Android port uses the exact same data structures.

## 1. Firestore Paths

*   **User Root**: `users/{uid}`
    *   **Sub-Collection**: `schoolYears/{yearId}` (Scope: One school year)
        *   **Sub-Collection**: `subjects/{subjectId}` (Name as ID)
            *   **Sub-Collection**: `grades/{gradeId}`
    *   **Sub-Collection**: `classes/{classId}` (New Architecture)
        *   **Sub-Collection**: `courses` (New Architecture)

## 2. Core Models

### `SchoolYear` (Firestore Doc)
*   `id`: String (e.g., "2025-26")
*   `gradeYear`: Int? (e.g., 12)
*   `schoolType`: String ("fos" | "bos")
*   `active`: Bool (Implicit via User.activeSchoolYearId)

### `Subject` (`SubjectModels.swift`)
*   `name`: String (Primary Key / Document ID)
*   `type`: Int
*   `gradingMode`: String? ("withSchulaufgaben" | "withoutSchulaufgaben")
*   `droppedHalfYear`: Int? (1 or 2)
*   `examSubject`: Bool?
*   `isElective`: Bool

### `Grade` (`SubjectModels.swift`)
*   `id`: String (UUID)
*   `grade`: Double (Points 0-15)
*   `weight`: Double (1.0 or 2.0 typically)
*   `halfYear`: Int? (1 or 2)
*   `date`: Date (Timestamp)
*   `assessmentType`: String? (enum: "schulaufgabe", "kurzarbeit", "muendlich")

### `Exam` (`ExamModels.swift`)
*   `id`: String (UUID)
*   `title`: String
*   `date`: Date
*   `subjectName`: String
*   `isCompleted`: Bool
*   `hasTime`: Bool (If true, hour/minute matters)

### `UserProfile` (`users/{uid}`)
*   `activeSchoolYearId`: String?
*   `appIcon`: String? ("default", "pink")
*   `theme`: String ("default", "feminine")
*   `darkMode`: Bool

## 3. New Architecture (Classes)

### `Class`
*   `id`: String (e.g., "10b")
*   `classCode`: String (Join Code)
*   `branches`: Array of Objects (`{ name: String, subjects: [String] }`)

### `Course`
*   `id`: String
*   `name`: String
*   `classId`: String
*   `type`: ("mandatory" | "branch" | "elective")

## 4. Legacy Migration
*   **Flag**: `migratedToSchoolYears` (Bool) on User doc.
*   **Logic**: If false, app reads root-level `subjects` collection and moves them to `schoolYears/current`.

## 5. Security & Privacy
*   **Encryption**: Some fields (`examPointsEncrypted`) store `ivB64:ciphertextB64`.
*   **Salt**: `encryptionSalt` stored on User profile.
