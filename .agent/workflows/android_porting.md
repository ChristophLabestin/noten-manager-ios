---
description: Complete guide to porting the app to Android, from empty project to full release.
---

# Android Porting Workflow

This workflow guides an agent through the process of porting `noten-manager-ios` to a native Android application using Kotlin and Jetpack Compose. Use this list to track your progress.

**Prerequisites:**
- [ ] Read `GOTCHAS.md` for edge cases.
- [ ] Consult the relevant `SKILL.md` before each major section.

## Phase 1: Project Setup & Infrastructure

- [ ] **1. Initialize Project**
    - [ ] Create a new Android project: `NotenManagerAndroid`.
    - [ ] Stack: Kotlin, Jetpack Compose, Material 3.
    - [ ] Min SDK: 26 (Android 8.0).

- [ ] **2. Dependencies**
    - [ ] Add Firebase (BoM, Auth, Firestore, Messaging, Crashlytics).
    - [ ] Add Hilt (Dependency Injection).
    - [ ] Add Navigation Compose.
    - [ ] Add Gson or Kotlin Serialization.

- [ ] **3. Skill Check**
    - [ ] Read `.agent/skills/data_schema/SKILL.md`.
    - [ ] Objective: Understand the exact field names required for backend compatibility.

## Phase 2: Design System (The "UI Skill" Port)

- [ ] **4. Theme Setup**
    - [ ] Read `.agent/skills/ui_development/SKILL.md`.
    - [ ] Create `Theme.kt`: Define `Feminine` (Pink) and `Default` (Indigo) color schemes.
    - [ ] Implement `Dark Mode` support matching `AppStyleComponents`.

- [ ] **5. Core Components**
    - [ ] Port `SoftTintButtonStyle` -> `Composable Fun SoftTintButton(...)`
    - [ ] Port `SettingsCard` -> `Composable Fun SettingsCard(...)`
    - [ ] Port `PrivacyBlurModifier` -> Custom Modifier in Compose.

## Phase 3: Data Layer (The "Data Schema" Port)

- [ ] **6. Models**
    - [ ] Create Data Classes matching `.agent/skills/data_schema/SKILL.md`.
    - [ ] `SchoolYear.kt`, `Subject.kt`, `Grade.kt`, `Exam.kt`, `UserProfile.kt`.
    - [ ] **Crucial**: Ensure `@PropertyName` annotations match Firestore fields exactly (e.g., camelCase).

- [ ] **7. Repositories**
    - [ ] Create `FirestoreService` (Singleton/SingletonComponent).
    - [ ] Implement user profile fetching, school year switching logic.

## Phase 4: Core Logic (The "Grade Logic" Port)

- [ ] **8. Calculation Service**
    - [ ] Read `.agent/skills/grade_logic/SKILL.md`.
    - [ ] Port `GradeCalculator.swift` -> `GradeCalculationService.kt`.
    - [ ] Implement `calculateSubjectAverage` (Handling 0-15 scale, rounding).
    - [ ] Implement `calculateOverallAverage` (Handling dropped half-years).

## Phase 5: Feature Implementation

- [ ] **9. Onboarding & Auth**
    - [ ] Read `.agent/skills/onboarding_auth/SKILL.md`.
    - [ ] Implement `OnboardingScreen`:
        - [ ] Step 1: School Year / Type (FOS/BOS).
        - [ ] Step 2: Class Join (QR Code / Text).
        - [ ] Step 3: Subject Confirmation.

- [ ] **10. Navigation Structure**
    - [ ] Read `.agent/skills/app_navigation/SKILL.md`.
    - [ ] Implement `AppNavigation` host.
    - [ ] Create Bottom Navigation Bar (Home, Calendar, Insights, Settings).

- [ ] **11. Home Tab**
    - [ ] Implement `HomeScreen`: List of subjects.
    - [ ] Implement `SubjectDetailScreen`: Grades list, Edit Sheet.

- [ ] **12. Calendar Tab**
    - [ ] Implement `CalendarScreen`: Agenda view.
    - [ ] Integrate logic to show Exams and Homework.

- [ ] **13. Insights Tab**
    - [ ] Implement `InsightsScreen`: MSS Graph (use a library like MPAndroidChart or custom Canvas).
    - [ ] Implement `ReportCardPreview`: Visual circles for Points/Grade.

## Phase 6: Advanced Capabilities

- [ ] **14. PDF Reporting**
    - [ ] Read `.agent/skills/pdf_reporting/SKILL.md`.
    - [ ] Implement `PdfGenerator`: Convert `ReportCardState` to a PDF file using Android's `PdfDocument`.

- [ ] **15. Notifications**
    - [ ] Read `.agent/skills/notifications_widgets/SKILL.md`.
    - [ ] Implement `FirebaseMessagingService`.
    - [ ] Implement `WorkManager` for local exam/homework reminders.

- [ ] **16. Widgets**
    - [ ] Read `.agent/skills/notifications_widgets/SKILL.md`.
    - [ ] Implement `Glance` App Widget for "Next Exam".

## Phase 7: Verification

- [ ] **17. Manual QA**
    - [ ] Verify calculations match the iOS app exactly (using `grade_logic` skill as reference).
    - [ ] Verify Firestore paths match `data_schema`.
