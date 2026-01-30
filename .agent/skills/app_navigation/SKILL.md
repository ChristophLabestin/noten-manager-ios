---
name: App Navigation
description: Map of the application flow, tabs, and navigation hierarchies.
---

# App Navigation

This skill outlines the navigation structure of `noten-manager-ios`, crucial for replicating the user flow on Android.

## 1. Root Structure
*   **Entry**: `noten_manager_iosApp.swift` -> `ContentView`.
*   **Logic**:
    *   If `!onboardingCompleted`: Show `OnboardingFunnelView`.
    *   If `onboardingCompleted`: Show `MainTabView`.

## 2. Main Tab View (`ContentView`)
The app uses a strict 4-tab layout:

1.  **Home (`HomeView`)**
    *   **Icon**: `house.fill`
    *   **Content**: Dashboard, Current Grades List, "Next Exam" Card.
    *   **Nav**: Drill-down to `SubjectDetailView`.
    
2.  **Calendar (`CalendarPageView`)**
    *   **Icon**: `calendar`
    *   **Content**: Agenda view of Exams and Homework.
    *   **Nav**: Sheet to `AddExamView` / `AddHomeworkView`.

3.  **Insights (`InsightsView`)**
    *   **Icon**: `chart.bar.fill` (or similar)
    *   **Content**: MSS History Graph, Analysis, Report Card Preview.
    *   **Nav**: Sheet to `ReportCardView` (PDF generation).

4.  **Settings (`AppSettingsView`)**
    *   **Icon**: `gearshape.fill`
    *   **Content**: User Profile, Theme, Notifications, School Year Management.

## 3. Onboarding Flow (`OnboardingFunnelView`)
A multi-step wizard:
1.  **Welcome / Migration Check**: Checks for existing web data.
2.  **School Year Setup**: Input Year ID ("2025-26") and Grade Level (11, 12, 13).
3.  **Class Join**: Enter Code OR Scan QR -> Select Branch.
4.  **Subject Selection**: Final review of subjects.

## 4. Modal Patterns
*   **Creation**: Always `.sheet` (e.g., `AddGradeView`).
*   **Editing**: Often `.sheet` or `NavigationLink` depending on context, but `EditSubjectView` is a sheet.
*   **Alerts**: Simple system alerts for destructive actions.

## 5. Deep Links
*   **Scheme**: `notenmanager://` (Concept)
*   **Join Code**: `https://.../join?code=XYZ` -> Parsed in `OnboardingFunnelView`.
