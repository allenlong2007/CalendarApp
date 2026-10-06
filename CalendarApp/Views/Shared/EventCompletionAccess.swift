import EventKit
import SwiftData

/// Fetch-then-upsert helpers for EventCompletionStatus, keyed by identifier
/// *and* occurrence start date -- see the matching note on `row` below.
///
/// Also reachable from the widget extension via raw-identifier overloads
/// (an AppIntent's parameters must be Codable primitives, so a widget
/// button can't hand this an EKEvent directly).
enum EventCompletionAccess {
    static func isCompleted(_ event: EKEvent, in rows: [EventCompletionStatus]) -> Bool {
        row(for: event, in: rows)?.completed ?? false
    }

    static func toggle(_ event: EKEvent, in rows: [EventCompletionStatus], context: ModelContext) {
        toggle(
            eventIdentifier: event.eventIdentifier ?? "",
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            occurrenceStartDate: event.startDate,
            title: event.title,
            in: rows,
            context: context
        )
    }

    static func toggle(
        eventIdentifier: String,
        calendarItemExternalIdentifier: String?,
        occurrenceStartDate: Date,
        title: String?,
        in rows: [EventCompletionStatus],
        context: ModelContext
    ) {
        if let existing = row(
            eventIdentifier: eventIdentifier,
            calendarItemExternalIdentifier: calendarItemExternalIdentifier,
            occurrenceStartDate: occurrenceStartDate,
            in: rows
        ) {
            existing.completed.toggle()
            existing.lastKnownTitle = title
        } else {
            let status = EventCompletionStatus(
                eventIdentifier: eventIdentifier,
                calendarItemExternalIdentifier: calendarItemExternalIdentifier,
                completed: true,
                lastKnownStartDate: occurrenceStartDate,
                lastKnownTitle: title
            )
            context.insert(status)
        }
    }

    /// Recurring events share one `eventIdentifier`/`calendarItemExternalIdentifier`
    /// across every occurrence in the series, so matching by identifier
    /// alone (the old behavior) made completing a single lecture complete
    /// every past and future occurrence of it too. The occurrence's own
    /// start date disambiguates which specific instance a row belongs to.
    private static func row(for event: EKEvent, in rows: [EventCompletionStatus]) -> EventCompletionStatus? {
        row(
            eventIdentifier: event.eventIdentifier ?? "",
            calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
            occurrenceStartDate: event.startDate,
            in: rows
        )
    }

    private static func row(
        eventIdentifier: String,
        calendarItemExternalIdentifier: String?,
        occurrenceStartDate: Date,
        in rows: [EventCompletionStatus]
    ) -> EventCompletionStatus? {
        rows.first { candidate in
            matchesIdentifier(candidate, eventIdentifier: eventIdentifier, calendarItemExternalIdentifier: calendarItemExternalIdentifier)
                && isSameOccurrence(candidate.lastKnownStartDate, occurrenceStartDate)
        }
    }

    private static func matchesIdentifier(
        _ candidate: EventCompletionStatus,
        eventIdentifier: String,
        calendarItemExternalIdentifier: String?
    ) -> Bool {
        if let external = calendarItemExternalIdentifier, let candidateExternal = candidate.calendarItemExternalIdentifier {
            return external == candidateExternal
        }
        return !eventIdentifier.isEmpty && candidate.eventIdentifier == eventIdentifier
    }

    private static func isSameOccurrence(_ stored: Date?, _ actual: Date) -> Bool {
        guard let stored else { return false }
        return abs(stored.timeIntervalSince(actual)) < 60
    }
}
