import Foundation

/// Calendars the app uses for its own bookkeeping. User-facing entry points
/// (Shivan bridge, Shortcuts) must never read or write them.
enum ReservedCalendars {
    static let syncTitle = "CalendarApp Sync"
    static let titles: Set<String> = [syncTitle, "CalendarApp App Data"]
}
