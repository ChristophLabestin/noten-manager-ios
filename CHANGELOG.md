# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-01-19

### Added
- **Social Groups**: Introduced subject-independent groups for sharing homework and appointments without fixed course lists.
- **Social Group Management**: Added `SocialGroupCreationView` and `SocialGroupDetailView` for seamless group handling.
- **Smart Half-Year Drops**: Implemented intelligent suggestion logic in `FinalGradeView` to help users identify the best half-years to drop according to FOBOSO rules.
- **What's New Sheet**: Added a new sheet that highlights key features (`Social Groups`, `Final Grade What-If`) on first launch after an update.

### Changed
- **Help Center UX**: Implemented collapsible sections in `HelpCenterView` to reduce visual clutter and improved navigation with automated scrolling.
- **Report Card Upgrade**: Added multi-page support with intelligent content overflow handling (subjects, special items, abitur exams).
- **Report Card Filtering**: Added option to exclude grades from dropped half-years ("Gestrichene Halbjahre").
- **Report Card Layout**: Fixed persistent layout issues including preview overlap and scaling offsets.
- **What If Entry**: Optimized `WhatIfModeView` with a high-density point grid (0-15) for faster grade simulation.
- **Target Selection**: Categorized sharing targets into "Soziale Gruppen" and "Themengruppen" for better organization.
- **Compact UI**: Redesigned `HelpCenterLink` for a more minimal, space-efficient appearance.
- **Final Grade Hero**: polished the hero section in `FinalGradeView` to ensure two decimal places for the average and prevent text truncation.
- **Onboarding UI**: Refined the Classes Feature Onboarding Sheet layout for better responsiveness.

### Fixed
- **Privacy Mode Polish**: Extended grade obscuration to `SubjectDetailView` and refined color handling when privacy mode is active.
- **Toolbar Consistency**: Restored standard toolbar colors and icons in `SubjectDetailView` edit sheets.
- **Documentation**: Updated `GOTCHAS.md` with layout tips and iOS 17 transition notes.
- **Report Card**: Resolved compilation errors and layout issues in `ReportCardSheet` and `ReportCardView`.

## [Unreleased] - 2026-01-18

### Added
- **MSS Detailed Calculation**: Introduced a new transparent view for MSS calculation breakdown.
- **MSS History Charting**: Added interactive progress tracking with historical MSS data points.
- **FOBOSO Components**: Integrated "Fachreferat", "Fachpraktische Ausbildung" (fpA), and "Seminararbeit" into grade calculations and report cards.
- **Exam Type Intelligence**: The `Exam` model now stores the `assessmentType`, enabling intelligent pre-selection when adding new grades.
- **UI Enhancements**: Added `FancyCoverView` and a refined `SpeedometerView` for a more premium visual experience.

### Changed
- **Final Grade Redesign**: Upgraded the subject assessment in `FinalGradeView` with a modern 3-option selector and high-density information chips.
- **Onboarding 2.0**: Migrated the onboarding funnel to the new "Classes" system, replacing legacy "Groups" with a streamlined joining flow.
- **Settings UX Refinement**: Redesigned theme and notification settings with rich interactive cards and detailed descriptions.
- **Smart Grade Coloring**: Subject grades are now only highlighted in red if the MSS value falls below 4 (insufficient).
- **Standardized Actions**: All primary view buttons now utilize `SoftTintButtonStyle` and are strategically placed in `safeAreaInset` for better reachability.

### Fixed
- **Calculation Precision**: Corrected "What If" mode to align with FOBOSO block weighting requirements.
- **Holiday Awareness**: Fixed holiday hints to proactively show upcoming breaks beyond the 7-day window.
- **Sorting Logic**: Resolved issues where dropped half-years incorrectly influenced subject sorting in `HomeView`.
- **Report Card Polish**: Removed redundant metrics and refined decimal formatting for a cleaner export.

## [Unreleased] - 2026-01-17

### Added
- **Privacy Mode core functionality**: 
    - Introduced a global `@Published var isPrivacyModeActive: Bool` in `GradesStore` with `UserDefaults` persistence.
    - Added a `privacyBlur()` view modifier using `ultraThinMaterial` and radius blur for elegant grade obscuration.
    - Integrated a biometric authentication requirement (Face ID/Touch ID) to disable Privacy Mode when active.
    - Added a prominent toggle icon to the toolbar across `HomeView`, `InsightsView`, and `FinalGradeView`.
- **Privacy Mode Configuration**: New section in `AppSettingsView` to manage global privacy and biometric settings.
- **Unified Grade Calculation**: Introduced `GradeCalculationService.swift` to centralize calculation logic (Abitur prognosis, subject averages, half-year results) following BayFOBOSO rules.
- **Course Mapping Models**: Added `CourseMapping` and associated models for shared group course synchronization.
- **Calendar Integration**: Added initial `CalendarPageView` for exam and homework scheduling.

### Changed
- **Insights Calculations**: Refactored `InsightsView` to use the unified `GradeCalculationService`, ensuring consistent grade reporting across the app.
- **Biometric Management**: Streamlined `BiometricAuthManager` for more reliable authentication flows.
- **Privacy Mode Coloring**: Updated the global grade coloring logic to hide the "traffic light" colors (red/orange/green) when Privacy Mode is active. Grades now appear in a neutral primary color to prevent visual guessing of grade quality.

### Fixed
- **Settings View stability**: Resolved structural issues and compilation errors in `AppSettingsView.swift`, including method scope and brace balance fixes.
- **Background Sync**: Improved reliability of background refresh and notification scheduling.

## [Unreleased] - 2026-01-08

### Added
- **Global Quick Actions**: The "Plus" (+) button in the top toolbar is now enabled for all iOS versions across all primary tabs (Home, Groups, Insights, Final Grade, Settings).
- **Quick Actions Menu**: Added a "Gruppe" option to the "Schnelle Aktionen" sheet to quickly create new groups.
- **Class Features**:
    - **Class Creation**: Added functionality to `ClassCreationView` to select independent groups during the creation process.
    - **Class Joining**: Integrated QR code scanning into `ClassJoinView` for faster onboarding.
    - **Class Detail View**: Redesigned the groups list into a single, cohesive `SettingsCard` with status-colored icons and badges.
    - **Branch Management**: Owners can now manually add new branches to existing classes. Users can subscribe to specific branches or individual courses.
    - **Robust Migration**: Converting a Group to a Class now ensures all members (including legacy users) are correctly migrated and subscribed.
- **Report Card PDF Export**:
    - **Elegant Design**: Completely redesigned the PDF Report Card to match the app's aesthetic, featuring rounded fonts, clean typography, and a "floating paper" preview.
    - **Customization**: Users can now select custom document titles (e.g., "Zwischenzeugnis", "Jahresübersicht") from the preview sheet.
    - **Smart Features**: Auto-generates descriptive filenames (e.g., `Noten_Jahresuebersicht_Name_Date.pdf`) and robustly fetches the user's real name from the database.
    - **App Theme Integration**: The preview sheet adapts to the user's selected theme (Dark/Light/Feminine).

### Changed
- **Class UI Redesign**:
    - **ClassesListView**: Redesigned `ClassCardView` for a more modern, premium look and applied `ThemedBackground`.
    - **ClassDetailView**: Redesigned the "Available Groups" and "Warning Hint" sections for better visual consistency.
- **Group UI Redesign**:
    - **GroupCreationView**: Redesigned with "Liquid Glass" aesthetic, using `ThemedBackground`, `SettingsCard`, and `SoftTintButtonStyle`.
    - **GroupJoinView**: Redesigned to match the new aesthetic with a compact header, `SettingsCard` input, and `SoftTintButtonStyle`.
    - **GroupsListView**: Updated the "Neue Gruppe erstellen" button to use `SoftTintButtonStyle` for consistency.
- **Navigation & Toolbars**:
    - **GroupSubjectManagementView**: Removed custom "Abbrechen" and "Fertig" buttons from the toolbar, restoring the standard native back button for better navigation flow.
    - **Sheet Dismissal**: Standardized sheet dismissal icons to `chevron.down` which adapts dynamically (White in Dark Mode, Black in Light Mode).
- **UI Standardization**:
    - **Button Styles**: Removed the legacy `AccentFilledButtonStyle` globally. All primary buttons now use the modern `SoftTintButtonStyle`.
    - **Report Card Sheet**: Updated the close button to a standardized chevron and streamlined the toolbar.
- **Refactoring**:
    - Moved `GroupCreationView` to its own file (`Views/Groups/GroupCreationView.swift`) for better modularity.

### Fixed
- **Sheet Icons**: Ensured high contrast for dismissal icons in sheets by implementing adaptive coloring.
- **Padding & Spacing**: Refined padding in `ClassDetailView` and `GroupsListView` for better balance.
