import EventKit
import SwiftData

/// Fetch-then-upsert helpers for EventCompletionStatus, keyed primarily by
/// calendarItemExternalIdentifier (falling back to eventIdentifier) since
/// EventCompletionStatus has no schema-level uniqueness constraint.
enum EventCompletionAccess {
    static func isCompleted(_ event: EKEvent, in rows: [EventCompletionStatus]) -> Bool {
        row(for: event, in: rows)?.completed ?? false
    }

    static func toggle(_ event: EKEvent, in rows: [EventCompletionStatus], context: ModelContext) {
        if let existing = row(for: event, in: rows) {
            existing.completed.toggle()
            existing.lastKnownStartDate = event.startDate
            existing.lastKnownTitle = event.title
        } else {
            let status = EventCompletionStatus(
                eventIdentifier: event.eventIdentifier ?? "",
                calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
                completed: true,
                lastKnownStartDate: event.startDate,
                lastKnownTitle: event.title
            )
            context.insert(status)
        }
    }

    private static func row(for event: EKEvent, in rows: [EventCompletionStatus]) -> EventCompletionStatus? {
        if let external = event.calendarItemExternalIdentifier {
            if let match = rows.first(where: { $0.calendarItemExternalIdentifier == external }) {
                return match
            }
        }
        guard let eventIdentifier = event.eventIdentifier else { return nil }
        return rows.first { $0.eventIdentifier == eventIdentifier }
    }
}
