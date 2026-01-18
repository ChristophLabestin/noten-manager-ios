---
name: Onboarding & Auth
description: Logic for authentication, sign-up, and initial data setup.
---

# Onboarding & Auth

This skill details the authentication and onboarding process, ensuring secure and correct user initialization.

## 1. Authentication (`AuthManager`)
*   **Provider**: Firebase Auth.
*   **Methods**: Anonymous Auth (default), Link with Apple/Google/Email.
*   **Persistence**: Handled by Firebase SDK.
*   **User ID (`uid`)**: Used as the document key in `users/{uid}`.

## 2. Onboarding Logic (`OnboardingFunnelView`)
The `OnboardingFunnelView` is a state machine:
*   **State Enum**: `.legacy` -> `.schoolYear` -> `.classes` -> `.subjects`.
*   **Data Check**:
    *   On start, check `LegacyMigrationSummary`.
    *   If legacy data exists (from Web App), prompt user to *Keep* or *Discard*.

### Step 1: School Year
*   **Input**: Year String ("2025-26") and School Type (FOS/BOS).
*   **Validation**: Regex `^\d{4}-\d{2}$`.
*   **Action**: Creates `schoolYears/{yearId}` doc.

### Step 2: Classes (New)
*   **Input**: Class Code (Alphanumeric).
*   **Action**: Looks up `classes/{code}`.
*   **Branch Selection**: User picks a branch (e.g., "Wirtschaft") -> Filters Courses.

### Step 3: Subjects
*   **Display**: List of subjects implied by the Class/Branch selection.
*   **Action**: "Finish" -> Batch write of all initial `Subject` documents to Firestore.
*   **Finalization**: Sets `onboardingCompleted = true` in User doc.

## 3. Migration Logic
*   **Legacy**: Flat structure (`users/{uid}/subjects/...`)
*   **Modern**: Nested structure (`users/{uid}/schoolYears/...`)
*   **Process**:
    *   `GradesStore.handleLegacyMigrationChoice`: Moves documents into the new sub-collection if "Keep" is selected.

## 4. Anonymous to Permanent
*   The app allows full usage as an Anonymous user.
*   "Sign Up" actually means "Link Credential" to the existing Anonymous user to preserve data.
