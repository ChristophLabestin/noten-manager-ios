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

### 2. Assessment Types (`AssessmentType`)
Each grade must have an explicit `assessmentType`:
*   **`.schulaufgabe`**: Written exam (Schulaufgabe). Weight typically 2.0 in Hauptfach.
*   **`.kurzarbeit`**: Short written test. Part of "Sonstige" block in Hauptfach.
*   **`.muendlich`**: Oral grade, Stegreifaufgabe, or other participation. Part of "Sonstige" block.

### 3. Grading Modes (`GradingMode`)
Subjects can be graded in two modes:
*   **`withSchulaufgaben`** (Hauptfach):
    *   Uses FOBOSO block weighting formula.
    *   Each Schulaufgabe = 1 block.
    *   All other grades (Kurzarbeit + mündlich) = 1 combined "Sonstige" block.
*   **`withoutSchulaufgaben`** (Nebenfach):
    *   Simple weighted average of all grades.

### 4. FOBOSO Block Weighting Formula

**For Hauptfächer (subjects with Schulaufgaben):**

```
HJE = (SonstigeAvg + SA₁ + SA₂ + ...) / (1 + AnzahlSAs)
```

Where:
- `SonstigeAvg` = Weighted average of all non-Schulaufgabe grades (Kurzarbeiten + mündlich)
- `SA₁, SA₂, ...` = Individual Schulaufgabe points
- `AnzahlSAs` = Number of Schulaufgaben

**Example:** SA=10, KA=8, MÜ=12
- SonstigeAvg = (8 + 12) / 2 = 10
- HJE = (10 + 10) / 2 = 10.0

**For Nebenfächer (subjects without Schulaufgaben):**
```
HJE = Sum(Grade × Weight) / Sum(Weights)
```

### 5. Half-Year Results (HJE)
*   **Rounding**: HJE values are rounded to integers (0-15) using `roundHJE()` before being used in overall average calculations.
*   **Rounding rule**: Values ≥0.5 round up, <0.5 round down.
*   **Final vs Interim**: A final HJE requires all blocks (SA + Sonstige). Otherwise, show interim/range.

### 6. Overall Average (Schnitt)

**Home/Insights View:**
Uses `GradeCalculationService.calculateOverallAverage`:
```swift
Avg = Sum(roundedHJE for each subject) / Count(subjects)
```
- Dropped half-years (`subject.droppedHalfYear`) are EXCLUDED.
- Uses rounded HJE values by default (unless `useRawValues = true`).

**Abitur Prognosis (Report Card):**
Uses `GradeCalculator.calculate()`:
- Includes Fachreferat, Seminararbeit, fpA in strict weighting buckets.
- Calculates total points (max 900) and average.

## Critical Files

| File | Description |
|------|-------------|
| `Managers/GradeEngine.swift` | Core FOBOSO block weighting logic |
| `Managers/GradeCalculationService.swift` | Pure math functions: `calculateHalfYearAverage`, `calculateOverallAverage`, `roundHJE` |
| `Managers/GradeCalculator.swift` | High-level orchestrator for Report Card view |
| `Stores/GradesStore.swift` | `bestAvailableHalfYearValue` - bridge to GradeEngine |

## Common Pitfalls

1.  **Kurzarbeit is NOT a block grade**: Only Schulaufgabe counts as a block. Kurzarbeit must be averaged with mündlich grades in the "Sonstige" block.
2.  **AssessmentType must be explicit**: When creating grades from exams, ensure `assessmentType` is correctly set (not just inferred from weight).
3.  **Rounding Errors**: Use `roundHJE()` only at final HJE stage, not for intermediate calculations.
4.  **Dropped Grades**: Always check `subject.droppedHalfYear` before including in average.

## How to Modify Calculations

1.  **Modify `GradeEngine.computeHalfYear`** for block weighting changes.
2.  **Modify `GradeCalculationService.calculateHalfYearAverage`** for alternative calculation paths.
3.  **Modify `GradeCalculator`** for Abitur aggregation strategy.
4.  **Validate** against `GradesStore.bestAvailableHalfYearValue` to ensure UI updates correctly.
