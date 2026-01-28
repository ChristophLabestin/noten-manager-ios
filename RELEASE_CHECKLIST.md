# NotenManager iOS Release Checklist

This checklist covers all views and features of the iOS application. Use this to verify functionality before a release.

## 📱 Onboarding & Auth
- [ ] **Launch Screen**: Visuals and animation.
- [ ] **Sign In / Sign Up**: Email/Password flow.
- [ ] **Apple Sign-In**: Authentication success.
- [ ] **Onboarding Funnel**: Step-by-step school/grade year selection.
- [ ] **Email Verification**: Banner visibility and refresh logic.
- [ ] **Biometric Auth**: FaceID/TouchID toggle and prompt.

## 🏠 Home & Core UI
- [ ] **Home View**: Subject list, average display, and speedometer.
- [ ] **Creation Menu (Quick Add)**:
    - [ ] Add Subject
    - [ ] Add Grade
    - [ ] Add Homework
    - [ ] Add Exam
    - [ ] Add Fachreferat/Seminar/Practical
- [ ] **Sync Status**: Sync progress indicator and success/fail states.
- [ ] **Offline Banner**: Correct display when offline.
- [ ] **Fancy Speedometer Cover**: Interactive launch cover.

## 📚 Subjects & Grades
- [ ] **Subject Detail**: Grade list, weightings, and stats.
- [ ] **Grade Entry**: 0-15 point scale, date selection, weighting (1x, 2x).
- [ ] **Weighting Logic**: "Schulaufgaben" vs "Sonstige Leistung" handling.
- [ ] **Subject Editing**: Rename, delete, or change color.

## 📝 Exams
- [x] **Exam List**: Filtering (Next, Past, Waiting for Grade).
- [ ] **Exam Detail**: Notes, date, time selection.
- [ ] **Abitur Exams**: Specific Abitur exam entry (Written/Oral).
- [ ] **Live Activities**: "Countdown to Exam" on lock screen.
- [ ] **Exam Edit**: Edit exam details.
- [ ] **Exam Delete**: Delete exam.

## ✍️ Homework
- [ ] **Homework List**: Status (Done/Pending), due dates.
- [ ] **Share Link**: Generating and importing homework share links.
- [ ] **Reminders**: Local notifications for upcoming homework.

## 📊 Insights & Final Grade
- [ ] **Insights View**: Half-year comparisons and grade trajectories.
- [ ] **Final Grade Screen**: Bavarian FOBOSO calculation (rounded/truncated).
- [ ] **Report Card (PDF)**: PDF generation and export functionality.
- [ ] **Abitur Projection**: Point calculation for Abitur graduation.

## 👥 Classes & Groups
- [ ] **Class List**: Joined classes and legacy groups.
- [ ] **Join Class**: QR code scan or manual code entry.
- [ ] **Create Class**: Teacher/Admin flow for class creation.
- [ ] **Group Detail**: Member list and shared class stats.

## ⚙️ Settings & System
- [ ] **Account Management**: Profile editing and logout.
- [ ] **Privacy Mode**: Grade blurring in UI.
- [ ] **Themes**: Default (Blue) vs Feminine (Pink).
- [ ] **MSS Precision**: MSS/Abitur calculation accuracy settings.
- [ ] **Support History**: Ticket status and help link.
- [ ] **Purchases / Subscription**: Full version unlock and active status.
- [ ] **Holiday Logic**: Automated holiday detection for Bavarian schools.
- [ ] **Firestore Sync**: Data persistence and encryption.
