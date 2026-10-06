import Foundation
import SwiftData

/// This app's own reminder setting for an event, replacing EventKit's
/// EKAlarm -- alarms fire as system Calendar notifications shared with
/// Apple's own Calendar app, which is exactly what the user asked to move
/// away from (events still live in EventKit/iCloud for cross-device sync,
/// but reminders now come from CalendarApp itself via ReminderScheduler).
/// Mirrors EventCompletionStatus's identifier strategy exactly: keyed
/// primarily by calendarItemExternalIdentifier (stable across a recurring
/// series and across devices), with eventIdentifier as a fast-path cache
/// and lastKnownStartDate/lastKnownTitle as a last-resort fuzzy match.
@Model
final class EventReminderPreference {
    var id: UUID = UUID()
    var eventIdentifier: String = ""
    var calendarItemExternalIdentifier: String?
    /// Minutes before the event to notify; nil means no reminder.
    var reminderMinutesBefore: Int?
    var lastKnownStartDate: Date?
    var lastKnownTitle: String?

    init(
        eventIdentifier: String,
        calendarItemExternalIdentifier: String? = nil,
        reminderMinutesBefore: Int? = nil,
        lastKnownStartDate: Date? = nil,
        lastKnownTitle: String? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarItemExternalIdentifier = calendarItemExternalIdentifier
        self.reminderMinutesBefore = reminderMinutesBefore
        self.lastKnownStartDate = lastKnownStartDate
        self.lastKnownTitle = lastKnownTitle
    }
}
