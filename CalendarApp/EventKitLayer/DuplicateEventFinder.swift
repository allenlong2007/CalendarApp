import EventKit
import Foundation

/// Finds events saved twice -- same calendar, title, start and end -- which is
/// what a double-fired tap (Quick Add, Save as Template) leaves behind.
/// Repeating events are never touched: removing one occurrence of a series
/// detaches it rather than deleting a copy.
enum DuplicateEventFinder {
    struct Duplicates {
        /// Events to delete, with the one copy of each that stays.
        var extras: [EKEvent] = []
        var groupCount = 0
        var sampleTitles: [String] = []
    }

    @MainActor
    static func scan(_ eventStore: EventStoreManager) -> Duplicates {
        let now = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        let end = Calendar.current.date(byAdding: .day, value: 365, to: now)!

        let candidates = eventStore.events(from: start, to: end).filter {
            $0.calendar?.allowsContentModifications == true && !$0.hasRecurrenceRules && !$0.isDetached
        }
        let groups = Dictionary(grouping: candidates) { event -> String in
            let s: Date = event.startDate, e: Date = event.endDate
            return "\(event.calendar?.calendarIdentifier ?? "")|\(event.title ?? "")|\(s.timeIntervalSince1970)|\(e.timeIntervalSince1970)|\(event.isAllDay)"
        }

        var result = Duplicates()
        for group in groups.values where group.count > 1 {
            // Keep the copy carrying the most detail, then the oldest.
            let ranked = group.sorted { lhs, rhs in
                let l = detail(lhs), r = detail(rhs)
                if l != r { return l > r }
                return (lhs.creationDate ?? .distantFuture) < (rhs.creationDate ?? .distantFuture)
            }
            result.extras.append(contentsOf: ranked.dropFirst())
            result.groupCount += 1
            if let title = ranked.first?.title, !result.sampleTitles.contains(title), result.sampleTitles.count < 3 {
                result.sampleTitles.append(title)
            }
        }
        return result
    }

    private static func detail(_ event: EKEvent) -> Int {
        (event.location?.isEmpty == false ? 1 : 0) + (event.notes?.isEmpty == false ? 1 : 0)
    }
}
