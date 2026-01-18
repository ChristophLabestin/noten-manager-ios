# Project Gotchas & Edge Cases

This file documents non-obvious details, workarounds, and "gotchas" in the codebase.
**AI Agents:** Read this before starting complex tasks. Update this when you discover new edge cases.

## Grade Calculation
*   **Rounding**: Grade averages (0-15 scale) are often rounded to 2 decimal places for display, but calculations (e.g., matching the Report Card) may require specific truncation rules specific to Bavarian FOBOSO. Always check `GradeCalculator.swift` logic.
*   **Dropped Half-Years**: A subject might have a `droppedHalfYear` (1 or 2). This means that half-year's average is ignored in the overall average calculation.
*   **Weighting**: "Schulaufgaben" usually weigh 2x, while other exams weigh 1x. However, `GradingMode.withoutSchulaufgaben` changes this logic.

## Firestore & Data
*   **School Year Scope**: Most data is nested under `users/{uid}/schoolYears/{yearId}`. Always ensure you are writing to the *active* school year path.
*   **Encryption**: Some exam points like `examPointsEncrypted` in `SubjectModels` are encrypted strings (`ivB64:ciphertextB64`). Do not attempt to write raw Doubles to these fields.

## UI Components
*   **Theme**: The app supports a "Feminine" theme (Pink) and "Default" (Indigo/Blue). Use `AppStyleComponents` or `store.theme` checks to respect this.
*   **Privacy Mode**: Use `PrivacyBlurModifier` for sensitive data (grades) when `store.privacyMode` is active.

## Navigation
*   **Tab Bar**: The custom tab bar implementation requires careful handling of bottom safe area padding in child views.
*   **Sheets**: Use `.presentationDetents` for modern sheet sizing.

## API & Deprecations
*   **iOS 17 `onChange`**: `onChange(of:perform:)` is deprecated. Use the new iOS 17 signature `onChange(of: ...) { oldValue, newValue in ... }`. 
    *   *Known Location*: `CalendarPageView.swift:285` uses the old syntax.
