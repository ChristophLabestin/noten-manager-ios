# Grading (FOBOSO) Overview

- GradingMode:
  - `withSchulaufgaben`: subject expects Schulaufgaben in a term.
  - `withoutSchulaufgaben`: no Schulaufgaben.
- AssessmentType: `schulaufgabe`, `kurzarbeit`, `stegreifaufgabe`, `muendlich`, `praktisch`, `projekt`.
- HalfYearStatus: `finalResult`, `interim`, `missing`.

Rules:
- Sonstige Leistungsnachweise = all assessments except `.schulaufgabe`.
- otherAvg = sum(points * weight) / sum(weight), no rounding.
- If Schulaufgaben exist (n > 0): raw = (otherAvg + sum(SA)) / (1 + n).
- If no Schulaufgaben: raw = otherAvg.
- Final rounding: `<0.50` down, `>=0.50` up; values <1.0 become 0.

Status:
- `withSchulaufgaben`: FINAL only if at least one Schulaufgabe AND one other assessment exist; else INTERIM with missingReasons.
- `withoutSchulaufgaben`: FINAL only if at least one other assessment exists; else MISSING.

Range:
- Use expectedSchulaufgabenPerTerm (default 1) to compute missing SA count.
- If otherAvg exists: rawMin/rawMax based on 0..15 for missing SA blocks.
- If otherAvg missing: include 0..15 for that block too.
- Round range endpoints with final rounding (no mid-rounding).

Engine:
- `GradeEngine.computeHalfYear(subject:term:assessments:) -> HalfYearComputation`
- Pure Swift, no IO/UI. Filter assessments by subjectId/termId before use or rely on engine filter.

Migration:
- Legacy subject.type main -> `withSchulaufgaben`, minor -> `withoutSchulaufgaben`.
