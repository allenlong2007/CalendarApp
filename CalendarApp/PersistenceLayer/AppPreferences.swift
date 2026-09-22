import Foundation
import SwiftData

/// Single-row app preferences. Theme is deliberately absent -- dark mode is
/// fixed in code (AppTheme/CalendarAppApp), not a user setting.
@Model
final class AppPreferences {
    var id: UUID = UUID()
    var weekStartDay: Int = 0
    var defaultReminderMinutes: Int?
    var notificationsEnabled: Bool = true
    /// EKCalendar.calendarIdentifier values hidden from the calendar-list
    /// sidebar's visibility toggles. Purely a display preference for this
    /// app -- EventKit has no cross-app "visible" flag to persist to.
    var hiddenCalendarIdentifiers: [String] = []

    init() {}
}

/// EventKit calendars have no icon field. This stores the SF Symbol name
/// chosen for a category/calendar as presentation-only metadata, keyed by
/// EKCalendar.calendarIdentifier.
@Model
final class CalendarIconMap {
    var id: UUID = UUID()
    var calendarIdentifier: String = ""
    var symbolName: String = "tag"

    init(calendarIdentifier: String, symbolName: String) {
        self.calendarIdentifier = calendarIdentifier
        self.symbolName = symbolName
    }
}
