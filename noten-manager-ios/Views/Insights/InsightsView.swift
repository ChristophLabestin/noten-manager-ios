import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var store: GradesStore
    @EnvironmentObject var biometricManager: BiometricAuthManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var showHomeworkSheet: Bool = false
    @State private var showExamSheet: Bool = false
    @State private var showWhatIfMode: Bool = false
    @State private var showNotifications: Bool = false
    @State private var includeDroppedHalfYears: Bool = false
    @AppStorage("launchOfferPurchased") private var launchOfferPurchased = false
    @ObservedObject private var notificationInbox = NotificationInboxStore.shared
    var onOpenCreationMenu: () -> Void = {}

    private var subjectsWithoutFachreferat: [Subject] {
        store.sortedSubjectsForDisplay(store.subjects.filter { $0.name != "Fachreferat" })
    }

    private var overallMSS: Double? { overallAverageValue }

    private var overallAverageValue: Double? {
        GradeCalculationService.calculateOverallAverage(
            subjects: store.subjects,
            halfYearValueProvider: { subject, halfYear in
                store.bestAvailableHalfYearValue(subject: subject, halfYear: halfYear)
            },
            droppedHalfYearProvider: { subject in
                includeDroppedHalfYears ? nil : subject.droppedHalfYear
            },
            halfYearFilter: nil,
            fachreferat: store.fachreferat,
            seminar: store.seminarPerformance,
            practical: store.practicalPerformance,
            examPoints: store.examPoints,
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12
        )
    }

    private func halfYearAverage(_ halfYear: Int) -> Double? {
        guard halfYear == 1 || halfYear == 2 else { return nil }
        return GradeCalculationService.calculateOverallAverage(
            subjects: store.subjects,
            halfYearValueProvider: { subject, hy in
                store.bestAvailableHalfYearValue(subject: subject, halfYear: hy)
            },
            droppedHalfYearProvider: { subject in
                includeDroppedHalfYears ? nil : subject.droppedHalfYear
            },
            halfYearFilter: halfYear,
            schoolType: store.schoolType,
            gradeYear: store.gradeYear ?? 12
        )
    }

    private func subjectAverage(_ subject: Subject) -> Double? {
        let droppedHalf = includeDroppedHalfYears ? nil : subject.droppedHalfYear
        let v1 = droppedHalf == 1 ? nil : store.bestAvailableHalfYearValue(subject: subject, halfYear: 1)
        let v2 = droppedHalf == 2 ? nil : store.bestAvailableHalfYearValue(subject: subject, halfYear: 2)
        switch (v1, v2) {
        case let (a?, b?):
            return (a + b) / 2.0
        case let (a?, nil):
            return a
        case let (nil, b?):
            return b
        default:
            return nil
        }
    }

    private var totalGradesCount: Int {
        subjectsWithoutFachreferat.reduce(0) { partial, subject in
            partial + (store.gradesBySubject[subject.name]?.count ?? 0)
        }
    }

    private var sortedByAverageDesc: [Subject] {
        subjectsWithoutFachreferat.sorted { a, b in
            let avgA = subjectAverage(a)
            let avgB = subjectAverage(b)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (a1?, b1?):
                return a1 > b1
            }
        }
    }

    private var topSubjects: [Subject] {
        sortedByAverageDesc.prefix(3).filter { subjectAverage($0) != nil }
    }

    private var bottomSubjects: [Subject] {
        let sortedAsc = subjectsWithoutFachreferat.sorted { a, b in
            let avgA = subjectAverage(a)
            let avgB = subjectAverage(b)
            switch (avgA, avgB) {
            case (nil, nil):
                return a.name.lowercased().localizedCompare(b.name.lowercased()) == .orderedAscending
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (a1?, b1?):
                return a1 < b1
            }
        }
        return sortedAsc.prefix(3).filter { subjectAverage($0) != nil }
    }

    private func formatAverage(_ value: Double?) -> String {
        guard let v = value else { return "-" }
        return String(format: "%.1f", v)
    }

    private func formatMSS(_ value: Double?) -> String {
        store.formatMSS(value)
    }

    private func gradeColor(_ value: Double?) -> Color {
        if store.isPrivacyModeActive { return .primary }
        guard let v = value else { return .secondary }
        if v >= 7 { return .green }
        if v >= 4 { return .orange }
        return .red
    }

    private var hasOverdueHomeworks: Bool {
        let now = Date()
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted else { return false }
            if let due = hw.dueDate { return due < now }
            if let reminder = hw.reminderAt { return reminder < now }
            return false
        }
    }

    private var hasHomeworkDueTomorrow: Bool {
        let cal = Calendar.current
        return store.allHomeworks.contains { hw in
            guard !hw.isCompleted, let due = hw.dueDate else { return false }
            return cal.isDateInTomorrow(due)
        }
    }

    private var hasOverdueExams: Bool {
        let now = Date()
        return store.allExams.contains { exam in
            !exam.isCompleted && exam.date < now
        }
    }

    private var animationsOn: Bool { store.animationsEnabled }

    private func handlePrivacyToggle() {
        if store.isPrivacyModeActive {
            if biometricManager.isEnabledForActiveUser {
                Task {
                    let success = await biometricManager.authenticate(reason: "Noten anzeigen")
                    if success {
                        store.updatePrivacyMode(active: false)
                    }
                }
            } else {
                store.updatePrivacyMode(active: false)
            }
        } else {
            store.updatePrivacyMode(active: true)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Insights")
                            .font(.title2.weight(.bold))
                        
                        Spacer()
                        
                        let hasDrops = store.subjects.contains { $0.droppedHalfYear != nil }
                        if hasDrops {
                            Button {
                                withAnimation {
                                    includeDroppedHalfYears.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: includeDroppedHalfYears ? "eye.slash" : "eye")
                                    Text(includeDroppedHalfYears ? "Streichungen ignoriert" : "Streichungen aktiv")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(includeDroppedHalfYears ? Color.secondary : Color.indigo)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(includeDroppedHalfYears ? Color.secondary.opacity(0.1) : Color.indigo.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("Schnitt, Fächer & Fortschritt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .softFadeIn(enabled: animationsOn, delay: 0.05, offset: 10)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    StatChip(title: "MSS", value: formatMSS(overallMSS), accent: .indigo)
                    let gradeValue = overallAverageValue.map { GradeCalculationService.pointsToGrade(points: $0) }
                    StatChip(title: "Schnitt", value: formatMSS(gradeValue), accent: .indigo)
                    StatChip(title: "Noten", value: "\(totalGradesCount)", accent: .orange)
                }
                .softFadeIn(enabled: animationsOn, delay: 0.1, offset: 12)

                MSSHistoryChartView(includeDroppedHalfYears: $includeDroppedHalfYears)
                    .environmentObject(store)
                    .softFadeIn(enabled: animationsOn, delay: 0.06, offset: 12)

                SettingsCard(
                    title: "Was-wäre-wenn",
                    subtitle: "Schnitt mit fiktiven Noten testen",
                    systemImage: "wand.and.stars",
                    accent: .pink
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Trage hypothetische Noten ein und sieh sofort, wie sich dein Schnitt verändert. Alles bleibt lokal und wird nicht gespeichert.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            showWhatIfMode = true
                        } label: {
                            Label("Was-wäre-wenn-Modus öffnen", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: .pink))
                    }
                }
                .softFadeIn(enabled: animationsOn, delay: 0.06, offset: 12)

                // Halbjahresvergleich
                let hj1 = halfYearAverage(1)
                let hj2 = halfYearAverage(2)
                if hj1 != nil || hj2 != nil {
                    SettingsCard(
                        title: "Halbjahre im Vergleich",
                        subtitle: "Streichung: \(store.maxDroppableHalfYears) möglich",
                        systemImage: "rectangle.split.2x1",
                        accent: .cyan
                    ) {
                        HStack {
                            halfYearChip(title: "1. Halbjahr", value: hj1)
                            Spacer()
                            halfYearChip(title: "2. Halbjahr", value: hj2)
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.10)
                }

                // Top-Fächer
                if !topSubjects.isEmpty {
                    SettingsCard(
                        title: "Deine Top-Fächer",
                        subtitle: "Beste Durchschnittsnoten",
                        systemImage: "arrow.up.right.circle.fill",
                        accent: .green
                    ) {
                        VStack(spacing: 8) {
                            ForEach(Array(topSubjects.enumerated()), id: \.element.name) { entry in
                                let subject = entry.element
                                let delay = 0.18 + Double(entry.offset) * 0.05
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                        .environmentObject(store)
                                } label: {
                                    subjectInsightRow(subject: subject, accent: .green)
                                }
                                .buttonStyle(.plain)
                                .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                            }
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.14)
                }

                // Fächer mit Potenzial
                if !bottomSubjects.isEmpty {
                    SettingsCard(
                        title: "Fächer mit Potenzial",
                        subtitle: "Hier lohnt sich extra Vorbereitung",
                        systemImage: "arrow.down.forward.and.arrow.up.backward.circle.fill",
                        accent: .orange
                    ) {
                        VStack(spacing: 8) {
                            ForEach(Array(bottomSubjects.enumerated()), id: \.element.name) { entry in
                                let subject = entry.element
                                let delay = 0.22 + Double(entry.offset) * 0.05
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                        .environmentObject(store)
                                } label: {
                                    subjectInsightRow(subject: subject, accent: .orange)
                                }
                                .buttonStyle(.plain)
                                .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                            }
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.18)
                }

                // Alle Fächer
                if !subjectsWithoutFachreferat.isEmpty {
                    SettingsCard(
                        title: "Alle Fächer",
                        subtitle: "Sortiert nach Durchschnitt",
                        systemImage: "list.bullet.rectangle.portrait.fill",
                        accent: .cyan
                    ) {
                        VStack(spacing: 8) {
                            ForEach(Array(sortedByAverageDesc.enumerated()), id: \.element.name) { entry in
                                let subject = entry.element
                                let delay = 0.24 + Double(entry.offset) * 0.03
                                NavigationLink {
                                    SubjectDetailView(subject: subject)
                                        .environmentObject(store)
                                } label: {
                                    subjectOverviewRow(subject: subject)
                                }
                                .buttonStyle(.plain)
                                .softFadeIn(enabled: animationsOn, delay: delay, offset: 12)
                            }
                        }
                    }
                    .softFadeIn(enabled: animationsOn, delay: 0.22)
                } else {
                    Text("Lege zuerst Fächer an, um Insights zu sehen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }

        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 0) {
                    Button {
                        showNotifications = true
                    } label: {
                        ToolbarIcon(
                            symbol: "bell",
                            showDot: notificationInbox.hasUnread || (LaunchOfferNotificationManager.isOfferActive() && !launchOfferPurchased)
                        )
                    }
                    .accessibilityLabel("Benachrichtigungen")

                    Button {
                        handlePrivacyToggle()
                    } label: {
                        ToolbarIcon(
                            symbol: store.isPrivacyModeActive ? "eye.slash.fill" : "eye.fill",
                            showDot: false
                        )
                    }
                    .accessibilityLabel(store.isPrivacyModeActive ? "Privatsphäre-Modus deaktivieren" : "Privatsphäre-Modus aktivieren")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    NavigationLink(destination: CalendarPageView().environmentObject(store)) {
                        ToolbarIcon(symbol: "calendar", showDot: false)
                    }
                    .accessibilityLabel("Kalender öffnen")

                    Button {
                        onOpenCreationMenu()
                    } label: {
                        ToolbarIcon(symbol: "plus", showDot: false)
                    }
                    .accessibilityLabel("Neu hinzufügen")
                }
            }
        }
        .sheet(isPresented: $showWhatIfMode) {
            WhatIfModeView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsInboxView(
                inbox: notificationInbox,
                onSelectNotification: { item in
                    handleNotificationSelection(item)
                },
                onOpenImportant: {
                    NotificationCenter.default.post(name: .openLaunchOffer, object: nil)
                }
            )
            .environmentObject(store)
        }
        .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
    }

    @ViewBuilder
    private func subjectInsightRow(subject: Subject, accent: Color) -> some View {
        let avg = subjectAverage(subject)
        let gradesCount = store.gradesBySubject[subject.name]?.count ?? 0

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatAverage(avg))
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(gradeColor(avg).opacity(0.15))
                .foregroundStyle(gradeColor(avg))
                .clipShape(Capsule())
                .privacyBlur()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.20), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func subjectOverviewRow(subject: Subject) -> some View {
        let avg = subjectAverage(subject)
        let gradesCount = store.gradesBySubject[subject.name]?.count ?? 0

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(gradesCount) \(gradesCount == 1 ? "Note" : "Noten")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatAverage(avg))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(gradeColor(avg).opacity(0.12))
                .foregroundStyle(gradeColor(avg))
                .clipShape(Capsule())
                .privacyBlur()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 1)
        )
    }

    private func halfYearChip(title: String, value: Double?) -> some View {
        let color = gradeColor(value)
        let gradeValue = value.map { GradeCalculationService.pointsToGrade(points: $0) }
        
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(formatMSS(value))
                    .font(.headline.weight(.semibold))
                
                if let gv = gradeValue {
                    Text("Ø \(String(format: "%.2f", gv))")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .privacyBlur()
        }
    }

    private func handleNotificationSelection(_ item: NotificationInboxItem) {
        if let _ = item.homeworkId {
            showHomeworkSheet = true
        } else if let _ = item.examId {
            showExamSheet = true
        } else if item.kind == .daily {
            showHomeworkSheet = true
        }
    }
}
