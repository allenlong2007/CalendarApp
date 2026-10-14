import EventKit
import SwiftData
import SwiftUI
import UIKit

/// A plain-data snapshot of an EKEvent, safe to carry inside a TimelineEntry
/// (widget timelines are built synchronously per refresh -- there's no need
/// to keep the EKEvent/EKCalendar objects themselves around). Also carries
/// the identifying fields ToggleEventCompletionIntent needs, since an
/// AppIntent parameter can't be an EKEvent itself.
struct EventSummary {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let colorComponents: (red: Double, green: Double, blue: Double)
    let eventIdentifier: String?
    let calendarItemExternalIdentifier: String?
    let completed: Bool
    /// Other events with exactly this title and time (see WidgetEventStore.events).
    /// Shown as one row, so a tap has to check them all off together -- otherwise
    /// the widget marks one copy and the row looks unchanged or flips back.
    let peerEventIdentifiers: [String]
    let peerExternalIdentifiers: [String]

    /// Stable identity for SwiftUI lists and for collapsing repeats.
    var id: String { "\(title)|\(startDate.timeIntervalSince1970)|\(endDate.timeIntervalSince1970)|\(isAllDay)" }

    var color: Color { Color(red: colorComponents.red, green: colorComponents.green, blue: colorComponents.blue) }

    init(event: EKEvent, completed: Bool = false, peers: [EKEvent] = []) {
        peerEventIdentifiers = peers.map { $0.eventIdentifier ?? "" }
        peerExternalIdentifiers = peers.map { $0.calendarItemExternalIdentifier ?? "" }
        title = event.title ?? "Untitled"
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        eventIdentifier = event.eventIdentifier
        calendarItemExternalIdentifier = event.calendarItemExternalIdentifier
        self.completed = completed
        let uiColor = UIColor(AppTheme.calendarColor(for: event.calendar))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        colorComponents = (Double(r), Double(g), Double(b))
    }
}

enum WidgetEventStore {
    /// Widgets can't independently prompt for calendar access -- they share
    /// the host app's authorization once it's been granted there.
    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Reads from the same App Group-shared SwiftData container the main
    /// app uses, so a widget shows completion state set in the app (and
    /// vice versa after ToggleEventCompletionIntent writes to it).
    private static func completionRows() -> [EventCompletionStatus] {
        let container = ModelContainerFactory.make()
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<EventCompletionStatus>())) ?? []
    }

    /// Matches EventStoreManager.syncCalendarTitle in the main app -- the hidden
    /// calendar the app uses to sync its own data, never a real calendar.
    private static let syncCalendarTitle = "CalendarApp Sync"

    /// Everything in range, in a stable order, with the app's sync calendar
    /// removed and exact repeats collapsed. A widget has room for a handful of
    /// rows, so one event listed twice (the same title and time saved twice, or
    /// present in two calendars) is the first thing that looks like a glitch.
    /// The collapsed copies ride along as `peers` so completion treats the row
    /// as one thing.
    private static func events(from start: Date, to end: Date) -> [(event: EKEvent, peers: [EKEvent])] {
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let sorted = store.events(matching: predicate)
            .filter { $0.calendar?.title != syncCalendarTitle }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
        var order: [String] = []
        var groups: [String: [EKEvent]] = [:]
        for event in sorted {
            let key = "\(event.title ?? "")|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)|\(event.isAllDay)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(event)
        }
        return order.compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            return (event: first, peers: Array(group.dropFirst()))
        }
    }

    private static func summary(_ group: (event: EKEvent, peers: [EKEvent]), rows: [EventCompletionStatus], queued: [PendingCompletion]) -> EventSummary {
        // Done if any copy is done: the app lists the copies separately, and
        // whichever one was ticked there is the one the user meant.
        let done = ([group.event] + group.peers).contains { isCompleted($0, rows: rows, queued: queued) }
        return EventSummary(event: group.event, completed: done, peers: group.peers)
    }

    /// Checkmarks not in the stored rows yet: other devices' newer ones the app
    /// hasn't merged (see CompletionMirror), then this widget's own queued taps.
    /// Newest wins, so a tap made after a Mac change still shows.
    private static func pendingChanges() -> [PendingCompletion] {
        CompletionMirror.unmergedRemoteChanges(store: EKEventStore()) + CompletionOutbox.pending().map(\.item)
    }

    /// Stored state, overlaid with taps the app hasn't applied yet (see
    /// CompletionOutbox) so a tap shows up on the widget immediately.
    private static func isCompleted(_ event: EKEvent, rows: [EventCompletionStatus], queued: [PendingCompletion]) -> Bool {
        let startMs = Int64((event.startDate.timeIntervalSince1970 * 1000).rounded())
        if let pending = CompletionOutbox.latestValue(
            eventIdentifier: event.eventIdentifier ?? "",
            external: event.calendarItemExternalIdentifier,
            startMs: startMs,
            in: queued
        ) { return pending }
        return EventCompletionAccess.isCompleted(event, in: rows)
    }

    static func upcomingEvents(hoursAhead: Int) -> [EventSummary] {
        let now = Date.now
        guard let end = Calendar.current.date(byAdding: .hour, value: hoursAhead, to: now) else { return [] }
        let rows = completionRows()
        let queued = pendingChanges()
        return events(from: now, to: end)
            .filter { !$0.event.isAllDay && $0.event.endDate > now }
            .map { summary($0, rows: rows, queued: queued) }
    }

    static func todaysEvents() -> [EventSummary] {
        let rows = completionRows()
        let queued = pendingChanges()
        return events(from: DateMath.startOfDay(.now), to: DateMath.endOfDay(.now))
            .map { summary($0, rows: rows, queued: queued) }
    }
}
