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
        }
        .configurationDisplayName("Klausuren – 14 Tage")
        .description("Zeigt, wie viele Klausuren in den nächsten zwei Wochen anstehen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct UpcomingExamsView: View {
    let date: Date
    let upcoming: [WidgetExam]
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = upcoming.first
        WidgetCard(gradient: LinearGradient(
            colors: [Color.indigo.opacity(0.9), Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )) {
            let spacing = family == .systemSmall ? 8.0 : 10.0
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: spacing) {
                    HeaderView(title: "Nächste 14 Tage", subtitle: "Klausuren & Prüfungen", symbol: "calendar.badge.clock")
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(upcoming.count)")
                            .font(family.countFont)
                        Text(upcoming.count == 1 ? "Termin" : "Termine")
                            .font(.headline)
                    }
                    if let next {
                        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
                            Text(next.title)
                                .font(family.eventTitleFont)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            let subject = next.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !subject.isEmpty, family != .systemSmall {
                                // Subject rendered in corner for medium
                            } else if !subject.isEmpty {
                                Text(subject)
                                    .font(family.subjectFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            if family == .systemSmall {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label(formattedDate(next.date, includeTime: next.hasTime), systemImage: "clock")
                                }
                                .font(family.metadataFont)
                                .foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    Label(formattedDate(next.date, includeTime: next.hasTime), systemImage: "clock")
                                    Spacer()
                                    Text(relativeString(until: next.date, from: date))
                                        .font(family.metadataFont)
                                        .foregroundStyle(.secondary)
                                }
                                .font(family.metadataFont)
                            }
                        }
                    } else {
                        Text("Keine Klausuren geplant.")
                            .font(family.emptyStateFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if family == .systemMedium, let subject = upcoming.first?.subjectName.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
                    Text(subject)
                        .font(family.subjectFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 2)
                }
            }
        }
        .widgetURL(URL(string: "notenmanager://exams"))
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
        }
        .configurationDisplayName("Klausuren Schuljahr")
        .description("Alle Klausuren bis zum 31.07. des aktiven Schuljahres.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RemainingYearView: View {
    let endDate: Date
    let exams: [WidgetExam]
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetCard(gradient: LinearGradient(
            colors: [Color.teal.opacity(0.9), Color.cyan.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )) {
            let spacing = family == .systemSmall ? 8.0 : 10.0
            VStack(alignment: .leading, spacing: spacing) {
                HeaderView(title: "Rest-Schuljahr", subtitle: "bis \(formattedDate(endDate, includeTime: false))", symbol: "calendar")
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(exams.count)")
                        .font(family.countFont)
                    Text(exams.count == 1 ? "Termin" : "Termine")
                        .font(.headline)
                }
                if let next = exams.first {
                    VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
                        Text(next.title)
                            .font(family.eventTitleFont)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(formattedDate(next.date, includeTime: next.hasTime))
                            .font(family.metadataFont)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Alles erledigt – keine Termine mehr.")
                        .font(family.emptyStateFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Offene Hausaufgaben

struct OpenHomeworkWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.open-homework"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            let open = entry.snapshot.openHomeworks(from: entry.date)
            OpenHomeworkView(open: open)
        }
        .configurationDisplayName("Offene Hausaufgaben")
        .description("Anzahl offener Aufgaben und der nächste Fälligkeitstermin.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct OpenHomeworkView: View {
    let open: [WidgetHomework]
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = open.first
        WidgetCard(gradient: LinearGradient(
            colors: [Color.orange.opacity(0.95), Color.red.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )) {
            let spacing = family == .systemSmall ? 8.0 : 10.0
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: spacing) {
                    HeaderView(title: "Hausaufgaben", subtitle: "offen", symbol: "checklist")
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(open.count)")
                            .font(family.countFont)
                        Text(open.count == 1 ? "Aufgabe" : "Aufgaben")
                            .font(.headline)
                    }
                    if let next {
                        VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
                            Text(next.title)
                                .font(family.eventTitleFont)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            let subject = next.subjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !subject.isEmpty, family != .systemSmall {
                                // Subject rendered in corner for medium
                            } else if !subject.isEmpty {
                                Text(subject)
                                    .font(family.subjectFont)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            if let due = next.dueDate ?? next.reminderAt {
                                Text("Fällig \(formattedDate(due, includeTime: false))")
                                    .font(family.metadataFont)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Keine offenen Aufgaben.")
                            .font(family.emptyStateFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if family == .systemMedium, let subject = open.first?.subjectName.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
                    Text(subject)
                        .font(family.subjectFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 2)
                }
            }
        }
        .widgetURL(URL(string: "notenmanager://homework"))
    }
}

// MARK: - Andere Termine

struct GeneralEventsWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.general-events"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotProvider()) { entry in
            let events = entry.snapshot.upcomingGeneralEvents(from: entry.date)
            GeneralEventsView(events: events, date: entry.date)
        }
        .configurationDisplayName("Andere Termine")
        .description("Zeigt anstehende Termine ohne Klausur-Bezug.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct GeneralEventsView: View {
    let events: [WidgetExam]
    let date: Date
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let next = events.first
        WidgetCard(gradient: LinearGradient(
            colors: [Color.purple.opacity(0.9), Color.indigo.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )) {
            let spacing = family == .systemSmall ? 8.0 : 10.0
            VStack(alignment: .leading, spacing: spacing) {
                HeaderView(title: "Andere Termine", subtitle: nil, symbol: "calendar.badge.exclamationmark")
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(events.count)")
                        .font(family.countFont)
                    Text(events.count == 1 ? "Termin" : "Termine")
                        .font(.headline)
                }
                if let next {
                    VStack(alignment: .leading, spacing: family == .systemSmall ? 3 : 4) {
                        Text(next.title)
                            .font(family.eventTitleFont)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if family == .systemSmall {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formattedDate(next.date, includeTime: next.hasTime))
                            }
                            .font(family.metadataFont)
                            .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Text(formattedDate(next.date, includeTime: next.hasTime))
                                Spacer()
                                Text(relativeString(until: next.date, from: date))
                            }
                            .font(family.metadataFont)
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Keine weiteren Termine.")
                        .font(family.emptyStateFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Termin auswählen

@available(iOS 17.0, *)
struct ExamCountdownWidget: Widget {
    let kind: String = "de.christophlabestin.noten-manager-ios.exam-countdown"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectedExamIntent.self, provider: SelectedExamProvider()) { entry in
            SelectedExamView(entry: entry)
        }
        .configurationDisplayName("Termin auswählen")
        .description("Countdown zu einer gewählten Klausur oder einem Termin.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@available(iOS 17.0, *)
struct SelectedExamEntry: TimelineEntry {
    let date: Date
    let exam: WidgetExam?
    let configuration: SelectedExamIntent
}

@available(iOS 17.0, *)
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

@available(iOS 17.0, *)
private struct SelectedExamView: View {
    let entry: SelectedExamEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let widgetURL: URL? = {
            if let id = entry.exam?.id {
                return URL(string: "notenmanager://exam/\(id)")
            }
            return URL(string: "notenmanager://exams")
        }()

        return WidgetCard(gradient: LinearGradient(
            colors: [Color.green.opacity(0.9), Color.blue.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )) {
            let spacing = family == .systemSmall ? 8.0 : 10.0
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: spacing) {
                    HeaderView(title: "Gewählter Termin", subtitle: entry.exam?.subjectName, symbol: "timer")
                    if let exam = entry.exam {
                        Text(exam.title)
                            .font(family.eventTitleFont)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if family == .systemSmall {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(formattedDate(exam.date, includeTime: exam.hasTime))
                            }
                            .font(family.metadataFont)
                            .foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Text(formattedDate(exam.date, includeTime: exam.hasTime))
                                Spacer()
                                Text(relativeString(until: exam.date, from: entry.date))
                            }
                            .font(family.metadataFont)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Kein Termin gefunden.")
                            .font(family.emptyStateFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if family == .systemMedium, let subject = entry.exam?.subjectName.trimmingCharacters(in: .whitespacesAndNewlines), !subject.isEmpty {
                    Text(subject)
                        .font(family.subjectFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 2)
                }
            }
        }
        .widgetURL(widgetURL)
    }
}

// MARK: - Layout

private struct WidgetCard<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let gradient: LinearGradient
    let content: () -> Content

    init(gradient: LinearGradient, @ViewBuilder content: @escaping () -> Content) {
        self.gradient = gradient
        self.content = content
    }

    var body: some View {
        let base = content()
            .padding(.vertical, family == .systemSmall ? 10 : 12)
            .padding(.horizontal, family == .systemSmall ? 4 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white)

        if #available(iOS 17.0, *) {
            base.containerBackground(for: .widget) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(gradient)
            }
        } else {
            base.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(gradient)
            )
        }
    }

    private var cornerRadius: CGFloat {
        family == .systemSmall ? 14 : 16
    }
}

private extension WidgetFamily {
    var eventTitleFont: Font {
        self == .systemSmall ? .footnote.weight(.semibold) : .headline
    }

    var subjectFont: Font {
        self == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold)
    }

    var countFont: Font {
        self == .systemSmall ? .system(size: 32, weight: .bold, design: .rounded) : .system(size: 38, weight: .bold, design: .rounded)
    }

    var metadataFont: Font {
        self == .systemSmall ? .caption2.monospacedDigit() : .footnote.monospacedDigit()
    }

    var emptyStateFont: Font {
        self == .systemSmall ? .caption : .subheadline
    }
}

// MARK: - Helpers

// MARK: - Header

private struct HeaderView: View {
    @Environment(\.widgetFamily) private var family
    let title: String
    let subtitle: String?
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: family == .systemSmall ? 24 : 28, height: family == .systemSmall ? 24 : 28)
                Image(systemName: symbol)
                    .font(.system(size: family == .systemSmall ? 12 : 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(family.headerTitleFont)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(family.headerSubtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private extension WidgetFamily {
    var headerTitleFont: Font {
        self == .systemSmall ? .footnote.weight(.semibold) : .subheadline.weight(.semibold)
    }

    var headerSubtitleFont: Font {
        self == .systemSmall ? .caption2 : .caption
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
