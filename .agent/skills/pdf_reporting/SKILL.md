---
name: PDF Reporting
description: Logic for generating the grade report PDF (Report Card).
---

# PDF Reporting

This skill describes how to generate the visual Report Card PDF (`ReportCardView`).

## 1. Technology
*   **Engine**: SwiftUI `ImageRenderer` (iOS 16+) or legacy PDFKit rendering.
*   **Concept**: Render a specific SwiftUI View (`ReportCardView`) into a PDF context.

## 2. Layout (`ReportCardView`)
*   **Size**: A4 (595 x 842 points).
*   **Header**:
    *   **Student Name**: Large, Bold.
    *   **Circles**: Two prominent circles for "Points" (Total/MSS) and "Schnitt" (Grade).
*   **Columns**: Two distinct columns:
    *   **Left**: Subjects "With Schulaufgaben" (Exams).
    *   **Right**: Subjects "Without Schulaufgaben".
*   **Footer**: Disclaimer "Inoffizieller Auszug".

## 3. Data Injection
*   **MSS Average**: Calculated via `GradeCalculator.calculate()` -> `averageAfterDrops`.
*   **Total Points**: `totalPoints` (Abitur Sum).
*   **Subjects**: Passed as a simple list `[(name, average, mode)]`. Note: `average` is the rounded point value (0-15).

## 4. Specific Behaviors
*   **Rounding**: Display integers (e.g., "13") if `.0`, otherwise 2 decimals.
*   **Red Text**: Grades < 5 points are colored RED to indicate failure danger.
*   **Empty Subjects**: Display "-" if no grades exist.

## 5. Android Porting Note
*   Android typically uses `PdfDocument` or HTML-to-PDF.
*   **Goal**: Replicate the *visual layout* of `ReportCardView.swift` (Header, Two Columns, Circles) using Android's native drawing or an XML layout converted to PDF.
