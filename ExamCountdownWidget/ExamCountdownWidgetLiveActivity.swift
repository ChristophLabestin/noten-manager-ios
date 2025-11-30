import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
struct ExamCountdownAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var examDate: Date
        var title: String
        var subject: String?
        var startDate: Date
        var duration: TimeInterval
    }

    var examId: String
    var title: String
    var subject: String?
    var accent: String?
}

@available(iOS 16.2, *)
struct ExamCountdownWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExamCountdownAttributes.self) { context in
            let accent = accentGradient(for: context.attributes)
            let accentColor = accentColorForTheme(context.attributes.accent)
            let countdownRange = countdownRange(for: context.state)
            LiveActivityView(
                attributes: context.attributes,
                state: context.state,
                countdownRange: countdownRange,
                accent: accent,
                accentColor: accentColor
            )
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .activityBackgroundTint(.black)
                .widgetURL(deepLinkURL(for: context.attributes))
        } dynamicIsland: { context in
            let accentColor = accentColorForTheme(context.attributes.accent)
            let countdownRange = countdownRange(for: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            appIcon(color: accentColor)
                            Text(context.attributes.title)
                                .font(.headline)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(spacing: 4) {
                            ProgressCapsule(range: countdownRange, color: accentColor)
                                .frame(height: 8)
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.badge.checkmark")
                                        .foregroundStyle(accentColor)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Noch")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    CountdownView(countdownRange: countdownRange)
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                }
                                Spacer()
                                Text(endTimeString(for: context.state))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            } compactLeading: {
                appIcon(color: accentColor)
                    .font(.system(size: 16, weight: .semibold))
            } compactTrailing: {
                CircularProgress(range: countdownRange, color: accentColor)
                    .frame(width: 24, height: 24)
            } minimal: {
                CircularProgress(range: countdownRange, color: accentColor)
                    .frame(width: 20, height: 20)
            }
            .widgetURL(deepLinkURL(for: context.attributes))
        }
    }
    
    private func appIcon(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 24, height: 24)
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func countdownRange(for state: ExamCountdownAttributes.ContentState) -> ClosedRange<Date> {
        state.startDate...state.examDate
    }

    private func accentColorForTheme(_ theme: String?) -> Color {
        if let theme, theme == "feminine" {
            return Color.pink
        }
        return Color.indigo
    }

    private func accentGradient(for attributes: ExamCountdownAttributes) -> LinearGradient {
        let colors: [Color]
        if let theme = attributes.accent, theme == "feminine" {
            colors = [Color.pink.opacity(0.9), Color.purple.opacity(0.9)]
        } else {
            colors = [Color.indigo, Color.blue.opacity(0.85)]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private func deepLinkURL(for attributes: ExamCountdownAttributes) -> URL? {
        URL(string: "notenmanager://exam/\(attributes.examId)")
    }

    private func endTimeString(for state: ExamCountdownAttributes.ContentState) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: state.examDate)
    }

}

@available(iOS 16.2, *)
private struct ProgressCapsule: View {
    let range: ClosedRange<Date>
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.14))
            ProgressView(timerInterval: range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(color)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

@available(iOS 16.2, *)
private struct CircularProgress: View {
    let range: ClosedRange<Date>
    let color: Color

    var body: some View {
        ProgressView(timerInterval: range, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(color)
        .padding(2)
    }
}

@available(iOS 16.2, *)
private struct LiveActivityView: View {
    let attributes: ExamCountdownAttributes
    let state: ExamCountdownAttributes.ContentState
    let countdownRange: ClosedRange<Date>
    let accent: LinearGradient
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(attributes.title)
                        .font(.headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let subject = attributes.subject, !subject.isEmpty {
                        Text(subject)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                RemainingLabel(countdownRange: countdownRange, accent: accentColor)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            ProgressCapsule(range: countdownRange, color: accentColor)
                .frame(height: 10)

            HStack(spacing: 10) {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundStyle(accentColor)
                    .font(.system(size: 14, weight: .semibold))
                Text("Noch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                CountdownView(countdownRange: countdownRange)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Ende \(targetTimeString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var targetTimeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: state.examDate)
    }
}

@available(iOS 16.2, *)
private struct CountdownView: View {
    let countdownRange: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: countdownRange, countsDown: true)
            .monospacedDigit()
    }
}

@available(iOS 16.2, *)
private struct RemainingLabel: View {
    let countdownRange: ClosedRange<Date>
    let accent: Color

    var body: some View {
        Text(timerInterval: countdownRange, countsDown: true)
            .monospacedDigit()
            .foregroundStyle(accent)
    }
}

@available(iOS 16.2, *)
struct ExamCountdownWidgetLiveActivity_Previews: PreviewProvider {
    static let attributes = ExamCountdownAttributes(
        examId: "preview",
        title: "Klausur",
        subject: "Mathematik",
        accent: "default"
    )
    static let contentState = ExamCountdownAttributes.ContentState(
        examDate: Date().addingTimeInterval(1200),
        title: "Klausur",
        subject: "Mathematik",
        startDate: Date().addingTimeInterval(-1800),
        duration: 1800
    )

    static var previews: some View {
        let accent = LinearGradient(
            colors: [Color.indigo, Color.blue.opacity(0.85)],
            startPoint: .leading,
            endPoint: .trailing
        )
        let countdownRange = contentState.startDate...contentState.examDate
        return Group {
            AnyView(attributes.previewContext(contentState, viewKind: .dynamicIsland(.compact)))
            AnyView(LiveActivityView(
                attributes: attributes,
                state: contentState,
                countdownRange: countdownRange,
                accent: accent,
                accentColor: .indigo
            ))
        }
    }
}
