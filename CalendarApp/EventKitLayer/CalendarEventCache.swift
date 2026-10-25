import EventKit
import Foundation

/// Reuses EventKit results across SwiftUI redraws. Every store revision drops
/// the old results; calendar filters and date ranges are distinct cache keys.
@MainActor
final class CalendarEventCache {
    struct Key: Hashable {
        let start: Date
        let end: Date
        let calendarIdentifiers: [String]?

        init(start: Date, end: Date, calendarIdentifiers: [String]?) {
            self.start = start
            self.end = end
            self.calendarIdentifiers = calendarIdentifiers.map { Array(Set($0)).sorted() }
        }
    }

    private let capacity: Int
    private var revision: Int?
    private struct Entry {
        let events: [EKEvent]
        var days: [Date: [EKEvent]]?
    }

    private var results: [Key: Entry] = [:]
    private var recent: [Key] = []

    init(capacity: Int = 64) { self.capacity = max(1, capacity) }

    func events(for key: Key, revision: Int, load: () -> [EKEvent]) -> [EKEvent] {
        if self.revision != revision {
            results.removeAll(keepingCapacity: true)
            recent.removeAll(keepingCapacity: true)
            self.revision = revision
        }
        if let cached = results[key] {
            recent.removeAll { $0 == key }
            recent.append(key)
            return cached.events
        }
        let events = load()
        if recent.count >= capacity { results.removeValue(forKey: recent.removeFirst()) }
        results[key] = Entry(events: events)
        recent.append(key)
        return events
    }
    /// Group once per fetched range, rather than redoing the date arithmetic
    /// as SwiftUI lays out and selects rows during scrolling.
    func eventsByDay(
        for key: Key, revision: Int, load: () -> [EKEvent],
        group: ([EKEvent]) -> [Date: [EKEvent]] = { EventDayGrouping.group($0) }
    ) -> [Date: [EKEvent]] {
        let events = events(for: key, revision: revision, load: load)
        if let days = results[key]?.days { return days }
        let days = group(events)
        results[key]?.days = days
        return days
    }
}
