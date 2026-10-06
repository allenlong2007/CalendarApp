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

    static func upcomingEvents(hoursAhead: Int) -> [EventSummary] {
        let store = EKEventStore()
        let now = Date.now
        guard let end = Calendar.current.date(byAdding: .hour, value: hoursAhead, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let rows = completionRows()
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { EventSummary(event: $0, completed: EventCompletionAccess.isCompleted($0, in: rows)) }
    }

    static func todaysEvents() -> [EventSummary] {
        let store = EKEventStore()
        let start = DateMath.startOfDay(.now)
        let end = DateMath.endOfDay(.now)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let rows = completionRows()
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { EventSummary(event: $0, completed: EventCompletionAccess.isCompleted($0, in: rows)) }
    }
}
