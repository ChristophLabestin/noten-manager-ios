---
name: UI Development
description: Guidelines for building consistent, high-quality UI in noten-manager-ios.
---

# UI Development

This skill provides guidelines for creating user interfaces in `noten-manager-ios`, ensuring consistency with the app's premium aesthetic and specific design system.

## Core Design Philosophy

*   **Premium & Soft**: Use soft gradients, blurred backgrounds, and "soft tint" styles.
*   **Themed**: Respect the user's theme choice ("default" vs. "feminine") and Color Scheme (Light vs. Dark).
*   **Card-Based Strategy**: Group content into cards (`SettingsCard`, `GradeCardStyle`).

## Key Components

Always prioritize using these shared components over raw SwiftUI views.

### 1. Cards & Containers

#### `SettingsCard`
The primary container for settings, forms, and informational blocks.
*   **Usage**: Wraps content in a styled card with optional title, subtitle, and icon.
*   **Example**:
    ```swift
    SettingsCard(
        title: "Subject Name",
        subtitle: "Optional subtitle",
        systemImage: "book.fill", // Optional
        accent: .blue // Optional, defaults to accentColor
    ) {
        // Content here
        Toggle("Enabled", isOn: $isEnabled)
    }
    ```

#### `SummaryCard`
A variant of `SettingsCard` specifically for summary sections, often wrapping a `SettingsSectionBox`.
*   **Example**:
    ```swift
    SummaryCard(title: "Overview") {
        Text("Content")
    }
    ```

#### `SettingsSectionBox`
A standard background container for grouped items within a card.
*   **Usage**: Use inside a `SettingsCard` to group related rows.

### 2. Buttons & Interactions

#### `SoftTintButtonStyle`
The standard button style for actions that aren't primary floating buttons but need emphasis.
*   **Usage**:
    ```swift
    Button("Save") { ... }
        .buttonStyle(SoftTintButtonStyle(accent: .blue))
    ```

### 3. Visual Effects

#### `ThemedBackground`
The standard background for all screens.
*   **Usage**: Place as the first element in a `ZStack` for the entire screen.
    ```swift
    ZStack {
        ThemedBackground(
            isDark: colorScheme == .dark,
            isFeminine: store.theme == "feminine"
        )
        ScrollView { ... }
    }
    ```

#### `PrivacyBlurModifier`
Automatically blurs sensitive content (grades) when Privacy Mode is active.
*   **Usage**: `.privacyBlur()`
    ```swift
    Text("13.5")
        .privacyBlur()
    ```

### 4. Text & Typography

*   **Numbers/Grades**: Use `.monospacedDigit()` and `.minimumScaleFactor(0.8)` for grade values.
*   **Headers**: `.font(.title3.weight(.bold))`
*   **Subtitles**: `.font(.subheadline).foregroundStyle(.secondary)`

## Color Palette

Do not use raw system colors unless necessary. Use semantic colors defined in `AppStyleComponents` or standard system styles.

*   `Color.formCardBackground`: Background for cards in forms.
*   `Color.formInputBackground`: Background for text fields.
*   `Color.formSectionBackground`: Background for sections.

## Animation

*   **Soft Fade**: Use `.softFadeIn()` for elements appearing on screen.
*   **Drill-Down**: Use standard SwiftUI navigation transitions, but prefer `SettingsCard` expansions for inline details.

## Icons

*   **Symbol**: Use SF Symbols.
*   **Styling**: Often wrapped in a `ZStack` with a rounded rect background matching the accent color opacity.
    ```swift
    ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accent.opacity(0.18))
            .frame(width: 36, height: 36)
        Image(systemName: icon)
            .foregroundStyle(accent)
    }
    ```
