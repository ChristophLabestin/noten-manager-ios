# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-01-08

### Added
- **Global Quick Actions**: The "Plus" (+) button in the top toolbar is now enabled for all iOS versions across all primary tabs (Home, Groups, Insights, Final Grade, Settings).
- **Quick Actions Menu**: Added a "Gruppe" option to the "Schnelle Aktionen" sheet to quickly create new groups.
- **Class Features**:
    - **Class Creation**: Added functionality to `ClassCreationView` to select independent groups during the creation process.
    - **Class Joining**: Integrated QR code scanning into `ClassJoinView` for faster onboarding.
    - **Class Detail View**: Redesigned the groups list into a single, cohesive `SettingsCard` with status-colored icons and badges.
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
