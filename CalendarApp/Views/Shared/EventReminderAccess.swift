import EventKit
import SwiftData

/// Fetch-then-upsert helpers for EventReminderPreference -- same shape as
/// EventCompletionAccess, since EventReminderPreference has no schema-level
/// uniqueness constraint either.
enum EventReminderAccess {
    /// What an event gets when this device has no reminder row for it.
    /// Reminder rows are stored per device (no iCloud sync for app data on a
    /// free developer account), so an event created on the Mac -- or in Apple
    /// Calendar -- has no row on the phone. Without a default it would never
    /// remind there at all.
    static let defaultMinutes = 15

    static func reminderMinutes(for event: EKEvent, in rows: [EventReminderPreference]) -> Int? {
        row(for: event, in: rows)?.reminderMinutesBefore
    }

    /// The reminder that will actually fire: an explicit row wins (including
    /// an explicit "None"); otherwise timed events on writable calendars get
    /// the default. All-day events and read-only subscribed calendars
    /// (Holidays, Birthdays) are excluded from the default -- a 15-minute
    /// warning on Christmas Day would fire at 11:45 PM the night before.
    static func effectiveMinutes(for event: EKEvent, in rows: [EventReminderPreference]) -> Int? {
        if let existing = row(for: event, in: rows) { return existing.reminderMinutesBefore }
        guard !event.isAllDay, event.calendar?.allowsContentModifications == true else { return nil }
        return defaultMinutes
    }

    static func setReminder(_ minutes: Int?, for event: EKEvent, in rows: [EventReminderPreference], context: ModelContext) {
        if let existing = row(for: event, in: rows) {
            existing.reminderMinutesBefore = minutes
            existing.lastKnownStartDate = event.startDate
            existing.lastKnownTitle = event.title
        } else {
            let pref = EventReminderPreference(
                eventIdentifier: event.eventIdentifier ?? "",
                calendarItemExternalIdentifier: event.calendarItemExternalIdentifier,
                reminderMinutesBefore: minutes,
                lastKnownStartDate: event.startDate,
                lastKnownTitle: event.title
            )
            context.insert(pref)
        }
    }

    private static func row(for event: EKEvent, in rows: [EventReminderPreference]) -> EventReminderPreference? {
        if let external = event.calendarItemExternalIdentifier {
            if let match = rows.first(where: { $0.calendarItemExternalIdentifier == external }) {
                return match
            }
        }
        guard let eventIdentifier = event.eventIdentifier else { return nil }
        return rows.first { $0.eventIdentifier == eventIdentifier }
    }
}
