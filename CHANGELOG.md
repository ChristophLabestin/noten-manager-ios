# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased] - 2026-01-08

### Added
- **Global Quick Actions**: The "Plus" (+) button in the top toolbar is now enabled for all iOS versions across all primary tabs (Home, Groups, Insights, Final Grade, Settings).
- **Quick Actions Menu**: Added a "Gruppe" option to the "Schnelle Aktionen" sheet to quickly create new groups.

### Changed
- **Group UI Redesign**:
    - **GroupCreationView**: Redesigned with "Liquid Glass" aesthetic, using `ThemedBackground`, `SettingsCard`, and `SoftTintButtonStyle`.
    - **GroupJoinView**: Redesigned to match the new aesthetic with a compact header, `SettingsCard` input, and `SoftTintButtonStyle`.
    - **GroupsListView**: Updated the "Neue Gruppe erstellen" button to use `SoftTintButtonStyle` for consistency.
- **Navigation & Toolbars**:
    - **GroupSubjectManagementView**: Removed custom "Abbrechen" and "Fertig" buttons from the toolbar, restoring the standard native back button for better navigation flow.
    - **Sheet Dismissal**: Standardized sheet dismissal icons to `chevron.down` which adapts dynamically (White in Dark Mode, Black in Light Mode).
- **Refactoring**:
    - Moved `GroupCreationView` to its own file (`Views/Groups/GroupCreationView.swift`) for better modularity.

### Fixed
- Ensured high contrast for dismissal icons in sheets by implementing adaptive coloring.
