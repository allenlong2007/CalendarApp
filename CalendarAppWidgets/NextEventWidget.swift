import EventKit
import SwiftUI
import WidgetKit

struct NextEventEntry: TimelineEntry {
    let date: Date
    let event: EventSummary?
    let needsAccess: Bool

    static let placeholder = NextEventEntry(
        date: .now,
        event: EventSummary(event: {
            let store = EKEventStore()
            let event = EKEvent(eventStore: store)
            event.title = "Team Standup"
            event.startDate = .now
            event.endDate = .now.addingTimeInterval(1800)
            return event
        }()),
        needsAccess: false
    )
}

struct NextEventProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEventEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NextEventEntry) -> Void) {
        guard WidgetEventStore.hasAccess else {
            completion(NextEventEntry(date: .now, event: nil, needsAccess: true))
            return
        }
        let events = WidgetEventStore.upcomingEvents(hoursAhead: 24)
        completion(NextEventEntry(date: .now, event: events.first, needsAccess: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextEventEntry>) -> Void) {
        guard WidgetEventStore.hasAccess else {
            let retryAt = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            completion(Timeline(entries: [NextEventEntry(date: .now, event: nil, needsAccess: true)], policy: .after(retryAt)))
            return
        }

        let now = Date.now
        let events = WidgetEventStore.upcomingEvents(hoursAhead: 24)
        var entries: [NextEventEntry] = []

        if events.isEmpty {
            entries.append(NextEventEntry(date: now, event: nil, needsAccess: false))
        } else {
            for (index, event) in events.enumerated() {
                let entryDate = index == 0 ? now : events[index - 1].endDate
                entries.append(NextEventEntry(date: entryDate, event: event, needsAccess: false))
            }
            entries.append(NextEventEntry(date: events.last!.endDate, event: nil, needsAccess: false))
        }

        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 4, to: now) ?? now.addingTimeInterval(14400)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }
}

struct NextEventWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEventEntry

    var body: some View {
        if entry.needsAccess {
            Text("Open CalendarApp to allow calendar access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let event = entry.event {
            switch family {
            case .accessoryInline:
                Text("\(event.title) at \(event.startDate, style: .time)")
            case .accessoryCircular:
                circularView(event)
            case .accessoryRectangular:
                rectangularView(event)
            default:
                homeScreenView(event)
            }
        } else {
            emptyView
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            Text("No More Events")
                .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private func homeScreenView(_ event: EventSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(event.color)
                .frame(width: 24, height: 4)
            Text(event.title)
                .font(.headline)
                .lineLimit(2)
            Text(event.isAllDay ? "All-day" : event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private func circularView(_ event: EventSummary) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "calendar")
                .font(.caption2)
            Text(event.startDate, style: .time)
                .font(.caption2.weight(.semibold))
                .minimumScaleFactor(0.7)
        }
    }

    private func rectangularView(_ event: EventSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.headline)
                .lineLimit(1)
            Text(event.isAllDay ? "All-day" : event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NextEventWidget: Widget {
    let kind = "NextEventWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextEventProvider()) { entry in
            NextEventWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Event")
        .description("Shows your next upcoming event.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
