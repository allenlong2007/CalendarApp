import Foundation

/// An event as far as it has been described out loud so far. Everything is
/// optional/overridable because speech arrives in pieces: the first sentence
/// may leave the time or category out, and a later correction fills it in.
struct EventDraft: Equatable {
    var title = ""
    /// Matched against the user's real calendars (categories) by title.
    var calendarTitle: String?
    var start: Date?
    var end: Date?
    var isAllDay = false
    /// False when only a day was heard ("Thursday") and `start` holds a
    /// placeholder time -- the summary asks for the time instead of guessing.
    var timeKnown = false
    var location: String?
    /// Minutes before the event; nil leaves the app's default reminder.
    var reminderMinutes: Int?
    var notes: String?

    enum Gap: String, CaseIterable {
        case title = "a title"
        case day = "a day"
        case time = "a time"
    }

    /// What still has to be said (or typed) before the event can be created.
    var gaps: [Gap] {
        var result: [Gap] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty { result.append(.title) }
        if start == nil { result.append(.day) }
        else if !timeKnown && !isAllDay { result.append(.time) }
        return result
    }

    var isComplete: Bool { gaps.isEmpty }

    var durationMinutes: Int? {
        guard let start, let end, end > start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }
}
