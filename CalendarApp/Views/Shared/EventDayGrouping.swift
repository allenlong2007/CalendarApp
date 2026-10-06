import EventKit

/// Groups events under *every* day they cover, not just their start day.
/// Grouping by start day alone made multi-day events (a trip, a conference)
/// and overnight events show up only on their first day -- on any other day
/// they covered, they looked like they'd never been added.
enum EventDayGrouping {
    /// Caps runaway spans (e.g. a mis-entered multi-year event) so a single
    /// bad event can't balloon a Month/Week render.
    private static let maxSpanDays = 62

    static func daysCovered(by event: EKEvent) -> [Date] {
        let eventStart: Date = event.startDate
        let eventEnd: Date = event.endDate
        let firstDay = DateMath.startOfDay(eventStart)
        // An event ending exactly at midnight (including all-day events, which
        // EventKit ends at next midnight) doesn't actually reach into that day.
        let lastInstant: Date = eventEnd > eventStart ? eventEnd.addingTimeInterval(-1) : eventStart
        let lastDay = DateMath.startOfDay(lastInstant)
        var days: [Date] = []
        var day = firstDay
        while day <= lastDay, days.count < maxSpanDays {
            days.append(day)
            day = DateMath.addingDays(1, to: day)
        }
        return days
    }

    static func group(_ events: [EKEvent], within range: ClosedRange<Date>? = nil) -> [Date: [EKEvent]] {
        var result: [Date: [EKEvent]] = [:]
        for event in events {
            for day in daysCovered(by: event) {
                if let range, !range.contains(day) { continue }
                result[day, default: []].append(event)
            }
        }
        return result
    }

    /// The part of `event` that falls on `day`, as minutes since that day's
    /// midnight -- clamped so an event that began yesterday starts at the top
    /// of today's column, and one that continues tomorrow ends at the bottom.
    static func minuteRange(of event: EKEvent, on day: Date) -> (start: Double, end: Double) {
        let dayStart = DateMath.startOfDay(day)
        let dayEnd = DateMath.addingDays(1, to: dayStart)
        let eventStart: Date = event.startDate
        let eventEnd: Date = event.endDate
        let clampedStart = max(eventStart, dayStart)
        let clampedEnd = min(eventEnd, dayEnd)
        let start = clampedStart.timeIntervalSince(dayStart) / 60
        let end = clampedEnd.timeIntervalSince(dayStart) / 60
        return (start, max(start + 20, end))
    }
}
