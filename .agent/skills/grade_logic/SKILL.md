---
name: Grade Logic
description: Guidelines for calculating grades, averages, and Abitur projections (FOBOSO).
---

# Grade Logic

This skill defines how to handle grade calculations in `noten-manager-ios`, ensuring compliance with Bavarian FOBOSO (Fachober- und Berufsoberschulordnung) rules.

## Core Concepts

### 1. Grading Scale
*   **Points**: 0 to 15 points (standard upper secondary level).
*   **Grades**: 1 to 6 (standard German grades), derived from points.
    *   `GradeCalculationService.pointsToGrade(points: Double)`

### 2. Grading Modes (`GradingMode`)
Subjects can be graded in two main modes, affecting weighting:
*   **`withSchulaufgaben`**:
    *   **Schulaufgabe** (Exam): Weight 2.0 (usually).
    *   **Kurzarbeit/Stegreifaufgabe**: Weight 1.0.
    *   **Mündlich**: Weight 1.0.
    *   *Note*: Sometimes simplified to 2:1 ratio for "Written" vs "Oral".
*   **`withoutSchulaufgaben`**:
    *   All grades are typically equal weight or follow specific small-scale weighting.

### 3. Half-Year Calculations
*   **Formula**: `(Sum of (Grade * Weight)) / (Sum of Weights)`.
*   **Rounding**: Calculations are generally exact internally, but formatted to 0-2 decimal places for display. **HJE (Halbjahresergebnisse)** are integers (0-15).

### 4. Overall Average (Schnitt)
The "Schnitt" (Average) shown in the app works differently depending on the view:

*   **Home/Insights ("Status" View)**:
    *   Uses `GradeCalculationService.calculateOverallAverage`.
    *   Logic: Average of the *valid half-year values* of all subjects.
    *   **Logic**:
        ```swift
        Avg = Sum(SubjectAverage) / Count(Subjects)
        ```
    *   *SubjectAverage*: `(H1 + H2) / 2` (if both exist), or just the existing one.
    *   **Crucial**: Dropped half-years (`subject.droppedHalfYear`) are EXCLUDED.

*   **Abitur Prognosis (Report Card)**:
    *   Uses `GradeCalculator.calculate()`.
    *   Includes "Fachreferat", "Seminararbeit", and "Fachpraktische Ausbildung" in strict weighting buckets.
    *   Calculates "Total Points" (max 900) vs. simple "Average".

## Critical Files

### `Managers/GradeCalculator.swift`
The high-level orchestrator for the "Report Card" view. It creates a `CalculationResult` containing:
*   `averageAfterDrops`: The MSS average (0-15) aligned with the Home view.
*   `totalPoints`: The strict Abitur point sum.

### `Managers/GradeCalculationService.swift` (Implicit)
Contains the pure math functions:
*   `calculateHalfYearAverage(...)`
*   `calculateOverallAverage(...)`
*   `pointsToGrade(...)`

## Common Pitfalls

1.  **Rounding Errors**: Never manually round intermediate steps unless FOBOSO explicitly says to (e.g., HJE are integers). Use `Double` for averages.
2.  **Dropped Grades**: Always check `subject.droppedHalfYear` before including a subject's HJE in the average.
3.  **Weighting**: Always check `grade.weight`. Do not assume default weighting (1.0).
4.  **Assessment Types**: Use `derivedAssessmentType` to handle legacy grades that might miss explicit types.

## How to Modify Calculations

1.  **Modify `GradeCalculationService`** for low-level math changes.
2.  **Modify `GradeCalculator`** for high-level aggregation strategy (e.g. how Abitur buckets are formed).
3.  **Validate** against `GradesStore` computed properties to ensure UI updates.
