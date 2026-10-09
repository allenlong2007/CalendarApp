import AppIntents
import EventKit
import SwiftUI
import WidgetKit

struct TodayAgendaEntry: TimelineEntry {
    let date: Date
    let events: [EventSummary]
    let needsAccess: Bool

    static let placeholder = TodayAgendaEntry(
        date: .now,
        events: [0, 1, 2].map { offset in
            let store = EKEventStore()
            let event = EKEvent(eventStore: store)
            event.title = "Sample Event \(offset + 1)"
            event.startDate = Calendar.current.date(byAdding: .hour, value: offset * 2, to: .now) ?? .now
            event.endDate = event.startDate.addingTimeInterval(3600)
            return EventSummary(event: event)
        },
        needsAccess: false
    )
}

struct TodayAgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayAgendaEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TodayAgendaEntry) -> Void) {
        guard WidgetEventStore.hasAccess else {
            completion(TodayAgendaEntry(date: .now, events: [], needsAccess: true))
            return
        }
        completion(TodayAgendaEntry(date: .now, events: WidgetEventStore.todaysEvents(), needsAccess: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayAgendaEntry>) -> Void) {
        guard WidgetEventStore.hasAccess else {
            let retryAt = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
            completion(Timeline(entries: [TodayAgendaEntry(date: .now, events: [], needsAccess: true)], policy: .after(retryAt)))
            return
        }

        let events = WidgetEventStore.todaysEvents()
        let entry = TodayAgendaEntry(date: .now, events: events, needsAccess: false)
        // Refresh soon so checkmarks made on the Mac show up without the app
        // having to run (see CompletionMirror), and at the latest at midnight.
        let midnight = DateMath.addingDays(1, to: DateMath.startOfDay(.now))
        completion(Timeline(entries: [entry], policy: .after(min(midnight, .now.addingTimeInterval(15 * 60)))))
    }
}

struct TodayAgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayAgendaEntry

    private var maxRows: Int { family == .systemLarge ? 8 : 4 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)

            if entry.needsAccess {
                Text("Open CalendarApp to allow calendar access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if entry.events.isEmpty {
                Text("No events today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.events.prefix(maxRows)), id: \.id) { event in
                    HStack(spacing: 6) {
                        completeButton(for: event)
                        Capsule()
                            .fill(event.color)
                            .frame(width: 3)
                        Text(event.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .strikethrough(event.completed)
                        Spacer(minLength: 4)
                        Text(event.isAllDay ? "All-day" : event.startDate.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if entry.events.count > maxRows {
                    Text("+\(entry.events.count - maxRows) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    /// One-tap complete toggle right on the widget -- no need to open the
    /// app. Button(intent:) runs ToggleEventCompletionIntent in-process and
    /// WidgetKit re-renders this widget once it calls reloadAllTimelines().
    private func completeButton(for event: EventSummary) -> some View {
        Button(intent: ToggleEventCompletionIntent(
            eventIdentifier: event.eventIdentifier ?? "",
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            occurrenceStartDate: event.startDate,
            eventTitle: event.title
        )) {
            Image(systemName: event.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(event.completed ? AppTheme.completed : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

struct TodayAgendaWidget: Widget {
    let kind = "TodayAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayAgendaProvider()) { entry in
            TodayAgendaWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Agenda")
        .description("Shows all of today's events at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
