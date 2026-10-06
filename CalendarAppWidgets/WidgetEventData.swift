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

    /// Stable identity for SwiftUI lists and for collapsing repeats.
    var id: String { "\(title)|\(startDate.timeIntervalSince1970)|\(endDate.timeIntervalSince1970)|\(isAllDay)" }

    var color: Color { Color(red: colorComponents.red, green: colorComponents.green, blue: colorComponents.blue) }

    init(event: EKEvent, completed: Bool = false) {
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
    private static func events(from start: Date, to end: Date) -> [EKEvent] {
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let sorted = store.events(matching: predicate)
            .filter { $0.calendar?.title != syncCalendarTitle }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
                return (lhs.title ?? "") < (rhs.title ?? "")
            }
        var seen = Set<String>()
        return sorted.filter { event in
            let key = "\(event.title ?? "")|\(event.startDate.timeIntervalSince1970)|\(event.endDate.timeIntervalSince1970)|\(event.isAllDay)"
            return seen.insert(key).inserted
        }
    }

    static func upcomingEvents(hoursAhead: Int) -> [EventSummary] {
        let now = Date.now
        guard let end = Calendar.current.date(byAdding: .hour, value: hoursAhead, to: now) else { return [] }
        let rows = completionRows()
        return events(from: now, to: end)
            .filter { !$0.isAllDay && $0.endDate > now }
            .map { EventSummary(event: $0, completed: EventCompletionAccess.isCompleted($0, in: rows)) }
    }

    static func todaysEvents() -> [EventSummary] {
        let rows = completionRows()
        return events(from: DateMath.startOfDay(.now), to: DateMath.endOfDay(.now))
            .map { EventSummary(event: $0, completed: EventCompletionAccess.isCompleted($0, in: rows)) }
    }
}
