# NotenManager iOS Release Checklist

This checklist covers all views and features of the iOS application. Use this to verify functionality before a release.

## 📱 Onboarding & Auth
- [x] **Launch Screen**: Visuals and animation.
- [x] **Sign In / Sign Up**: Email/Password flow.
- [x] **Apple Sign-In**: Authentication success.
- [x] **Onboarding Funnel**: Step-by-step school/grade year selection.
- [x] **Email Verification**: Banner visibility and refresh logic.
- [x] **Biometric Auth**: FaceID/TouchID toggle and prompt.

## 🏠 Home & Core UI
- [x] **Home View**: Subject list, average display, and speedometer.
- [x] **Creation Menu (Quick Add)**:
    - [x] Add Subject
    - [x] Add Grade
    - [x] Add Homework
    - [x] Add Exam
    - [x] Add Fachreferat/Seminar/Practical
- [x] **Sync Status**: Sync progress indicator and success/fail states.
- [x] **Offline Banner**: Correct display when offline.
- [x] **Fancy Speedometer Cover**: Interactive launch cover.

## 📚 Subjects & Grades
- [x] **Subject Detail**: Grade list, weightings, and stats.
- [x] **Grade Entry**: 0-15 point scale, date selection, weighting (1x, 2x).
- [x] **Weighting Logic**: "Schulaufgaben" vs "Sonstige Leistung" handling.
- [x] **Subject Editing**: Rename, delete, or change color.

## 📝 Exams
- [x] **Exam List**: Filtering (Next, Past, Waiting for Grade).
- [x] **Exam Detail**: Notes, date, time selection.
- [x] **Abitur Exams**: Specific Abitur exam entry (Written/Oral).
- [x] **Exam Edit**: Edit exam details.
- [x] **Exam Delete**: Delete exam.

## ✍️ Homework
- [x] **Homework List**: Status (Done/Pending), due dates.
- [x] **Share Link**: Generating and importing homework share links.
- [x] **Reminders**: Local notifications for upcoming homework.

## 📊 Insights & Final Grade
- [x] **Insights View**: Half-year comparisons and grade trajectories.
- [x] **Final Grade Screen**: Bavarian FOBOSO calculation (rounded/truncated).
- [x] **Report Card (PDF)**: PDF generation and export functionality.
- [x] **Abitur Projection**: Point calculation for Abitur graduation.

## 👥 Classes & Groups
- [x] **Class List**: Joined classes and legacy groups.
- [x] **Join Class**: QR code scan or manual code entry.
- [x] **Create Class**: Teacher/Admin flow for class creation.
- [x] **Group Detail**: Member list and shared class stats.

## ⚙️ Settings & System
- [x] **Account Management**: Profile editing and logout.
- [x] **Privacy Mode**: Grade blurring in UI.
- [x] **Themes**: Default (Blue) vs Feminine (Pink).
- [x] **MSS Precision**: MSS/Abitur calculation accuracy settings.
- [x] **Support History**: Ticket status and help link.
- [x] **Purchases / Subscription**: Full version unlock and active status.
- [x] **Holiday Logic**: Automated holiday detection for Bavarian schools.
- [x] **Firestore Sync**: Data persistence and encryption.
