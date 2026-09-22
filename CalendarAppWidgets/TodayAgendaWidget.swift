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
        // Midnight rollover is the only thing that changes "today" -- refresh then.
        let midnight = DateMath.addingDays(1, to: DateMath.startOfDay(.now))
        completion(Timeline(entries: [entry], policy: .after(midnight)))
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
                ForEach(Array(entry.events.prefix(maxRows).enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(event.color)
                            .frame(width: 3)
                        Text(event.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
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
