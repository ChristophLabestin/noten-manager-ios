import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: WidgetDataSource.placeholderSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = WidgetDataSource.loadSnapshot() ?? WidgetDataSource.placeholderSnapshot()
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = WidgetDataSource.loadSnapshot() ?? WidgetDataSource.placeholderSnapshot()
        let entry = SnapshotEntry(date: Date(), snapshot: snapshot)
        let refresh = Calendar.current.date(byAdding: .minute, value: 45, to: Date()) ?? Date().addingTimeInterval(45 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Klausuren (14 Tage)

struct UpcomingExamsWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.upcoming-exams"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            let exams = entry.snapshot.upcomingExams(within: 14, from: entry.date)
            UpcomingExamsView(date: entry.date, upcoming: exams)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Klausuren – 14 Tage")
        .description("Zeigt, wie viele Klausuren in den nächsten zwei Wochen anstehen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct UpcomingExamsView: View {
    let date: Date
    let upcoming: [WidgetExam]

    var body: some View {
        let next = upcoming.first
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Nächste 14 Tage", subtitle: "Klausuren & Prüfungen", symbol: "calendar.badge.clock")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(upcoming.count)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(upcoming.count == 1 ? "Termin" : "Termine")
                    .font(.headline)
            }
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    let subject = next.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !subject.isEmpty {
                        Text(subject)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack {
                        Label(formattedDate(next.date, includeTime: next.hasTime), systemImage: "clock")
                        Spacer()
                        Text(relativeString(until: next.date, from: date))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            } else {
                Text("Keine Klausuren geplant.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.indigo.opacity(0.9), Color.blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Schuljahr Restbestand

struct RemainingYearExamsWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.remaining-year-exams"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            let endDate = schoolYearEndDate(from: entry.snapshot.activeSchoolYearId, reference: entry.date)
            let exams = entry.snapshot.remainingExams(until: endDate, from: entry.date)
            RemainingYearView(endDate: endDate, exams: exams)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Klausuren Schuljahr")
        .description("Alle Klausuren bis zum 31.07. des aktiven Schuljahres.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RemainingYearView: View {
    let endDate: Date
    let exams: [WidgetExam]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Rest-Schuljahr", subtitle: "bis \(formattedDate(endDate, includeTime: false))", symbol: "calendar")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(exams.count)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(exams.count == 1 ? "Termin" : "Termine")
                    .font(.headline)
            }
            if let next = exams.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(formattedDate(next.date, includeTime: next.hasTime))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Alles erledigt – keine Termine mehr.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.teal.opacity(0.9), Color.cyan.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Offene Hausaufgaben

struct OpenHomeworkWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.open-homework"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            let open = entry.snapshot.openHomeworks(from: entry.date)
            OpenHomeworkView(open: open)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Offene Hausaufgaben")
        .description("Anzahl offener Aufgaben und der nächste Fälligkeitstermin.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct OpenHomeworkView: View {
    let open: [WidgetHomework]

    var body: some View {
        let next = open.first
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Hausaufgaben", subtitle: "offen", symbol: "checklist")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(open.count)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(open.count == 1 ? "Aufgabe" : "Aufgaben")
                    .font(.headline)
            }
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(1)
                    let subject = next.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !subject.isEmpty {
                        Text(subject)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let due = next.dueDate ?? next.reminderAt {
                        Text("Fällig \(formattedDate(due, includeTime: false))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Keine offenen Aufgaben.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.orange.opacity(0.95), Color.red.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Andere Termine

struct GeneralEventsWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.general-events"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            let events = entry.snapshot.upcomingGeneralEvents(from: entry.date)
            GeneralEventsView(events: events, date: entry.date)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Andere Termine")
        .description("Zeigt anstehende Termine ohne Klausur-Bezug.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct GeneralEventsView: View {
    let events: [WidgetExam]
    let date: Date

    var body: some View {
        let next = events.first
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Andere Termine", subtitle: nil, symbol: "calendar.badge.exclamationmark")
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(events.count)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(events.count == 1 ? "Termin" : "Termine")
                    .font(.headline)
            }
            if let next {
                VStack(alignment: .leading, spacing: 4) {
                    Text(next.title)
                        .font(.headline)
                        .lineLimit(2)
                    HStack {
                        Text(formattedDate(next.date, includeTime: next.hasTime))
                        Spacer()
                        Text(relativeString(until: next.date, from: date))
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Keine weiteren Termine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Termin auswählen

struct ExamCountdownWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.exam-countdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectedExamIntent.self, provider: SelectedExamProvider()) { entry in
            SelectedExamView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Termin auswählen")
        .description("Countdown zu einer gewählten Klausur oder einem Termin.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SelectedExamEntry: TimelineEntry {
    let date: Date
    let exam: WidgetExam?
    let configuration: SelectedExamIntent
}

struct SelectedExamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SelectedExamEntry {
        let sample = WidgetDataSource.placeholderSnapshot().allExams.first
        return SelectedExamEntry(date: Date(), exam: sample, configuration: SelectedExamIntent())
    }

    func snapshot(for configuration: SelectedExamIntent, in context: Context) async -> SelectedExamEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: SelectedExamIntent, in context: Context) async -> Timeline<SelectedExamEntry> {
        let entry = await entry(for: configuration)
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func entry(for configuration: SelectedExamIntent) async -> SelectedExamEntry {
        let snapshot = WidgetDataSource.loadSnapshot() ?? WidgetDataSource.placeholderSnapshot()
        let all = snapshot.allExams
            .filter { !$0.isCompleted && $0.date >= Date() }
            .sorted { $0.date < $1.date }
        let selected: WidgetExam?
        if let id = configuration.exam?.id {
            selected = all.first(where: { $0.id == id }) ?? all.first
        } else {
            selected = all.first
        }
        return SelectedExamEntry(date: Date(), exam: selected, configuration: configuration)
    }
}

private struct SelectedExamView: View {
    let entry: SelectedExamEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(title: "Dein Termin", subtitle: entry.exam?.subjectName, symbol: "timer")
            if let exam = entry.exam {
                Text(exam.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack {
                    Text(formattedDate(exam.date, includeTime: exam.hasTime))
                    Spacer()
                    Text(relativeString(until: exam.date, from: entry.date))
                }
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Text("Kein Termin gefunden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.green.opacity(0.9), Color.blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .foregroundStyle(.white)
    }
}

// MARK: - Helpers

@ViewBuilder
private func header(title: String, subtitle: String?, symbol: String) -> some View {
    HStack(alignment: .center, spacing: 8) {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 28, height: 28)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 0)
    }
}

private func formattedDate(_ date: Date, includeTime: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.dateStyle = .medium
    formatter.timeStyle = includeTime ? .short : .none
    return formatter.string(from: date)
}

private func relativeString(until date: Date, from reference: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: reference)
}

private func schoolYearEndDate(from id: String?, reference: Date) -> Date {
    let calendar = Calendar(identifier: .gregorian)
    let startYear: Int = {
        if let id, let parsed = Int(id.prefix(4)) {
            return parsed
        }
        let year = calendar.component(.year, from: reference)
        let month = calendar.component(.month, from: reference)
        return month >= 8 ? year : year - 1
    }()
    let endYear = startYear + 1
    var comps = DateComponents()
    comps.year = endYear
    comps.month = 7
    comps.day = 31
    comps.hour = 23
    comps.minute = 59
    comps.second = 0
    return calendar.date(from: comps) ?? reference
}
