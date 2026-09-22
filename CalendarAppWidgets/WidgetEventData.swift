import EventKit
import SwiftUI
import UIKit

/// A plain-data snapshot of an EKEvent, safe to carry inside a TimelineEntry
/// (widget timelines are built synchronously per refresh -- there's no need
/// to keep the EKEvent/EKCalendar objects themselves around).
struct EventSummary {
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let colorComponents: (red: Double, green: Double, blue: Double)

    var color: Color { Color(red: colorComponents.red, green: colorComponents.green, blue: colorComponents.blue) }

    init(event: EKEvent) {
        title = event.title ?? "Untitled"
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
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

    static func upcomingEvents(hoursAhead: Int) -> [EventSummary] {
        let store = EKEventStore()
        let now = Date.now
        guard let end = Calendar.current.date(byAdding: .hour, value: hoursAhead, to: now) else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map(EventSummary.init)
    }

    static func todaysEvents() -> [EventSummary] {
        let store = EKEventStore()
        let start = DateMath.startOfDay(.now)
        let end = DateMath.endOfDay(.now)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map(EventSummary.init)
    }
}
