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
    private var results: [Key: [EKEvent]] = [:]
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
            return cached
        }
        let events = load()
        if recent.count >= capacity { results.removeValue(forKey: recent.removeFirst()) }
        results[key] = events
        recent.append(key)
        return events
    }
}
