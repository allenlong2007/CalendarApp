import Foundation

/// An event as far as it has been described out loud so far. Everything is
/// optional/overridable because speech arrives in pieces: the first sentence
/// may leave the time or category out, and a later correction fills it in.
struct EventDraft: Equatable {
    var title = ""
    /// Matched against the user's real calendars (categories) by title.
    var calendarTitle: String?
    /// The exact calendar, when it's known (a copied event) -- preferred over the
    /// title, since two calendars can share a name.
    var calendarIdentifier: String?
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
    /// Set when it should be added on many days ("every Friday until Dec 4").
    var repeatRule: RepeatRule?
    /// Days left out of a repeat ("skip Thanksgiving").
    var skipDates: [Date] = []
    /// More days to add the same event on ("Tuesday and next Friday"), at the same time.
    var extraDays: [Date] = []

    enum Gap: String, CaseIterable {
        case title = "a title"
        case day = "a day"
        case time = "a time"
        case repeatEnd = "how long to repeat (say “for the rest of the quarter” or “for 6 weeks”)"
    }

    /// What still has to be said (or typed) before the event can be created.
    var gaps: [Gap] {
        var result: [Gap] = []
        if title.trimmingCharacters(in: .whitespaces).isEmpty { result.append(.title) }
        if start == nil { result.append(.day) }
        else if !timeKnown && !isAllDay { result.append(.time) }
        if let rule = repeatRule, rule.until == nil, rule.count == nil { result.append(.repeatEnd) }
        return result
    }

    var isComplete: Bool { gaps.isEmpty }

    var durationMinutes: Int? {
        guard let start, let end, end > start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }
}

/// How an event repeats when it's added in bulk. Each day becomes its own
/// ordinary event (like the rest of this calendar), so any single one can be
/// moved, completed or deleted without touching the others.
struct RepeatRule: Equatable {
    /// `Calendar` weekday numbers (1 = Sunday ... 7 = Saturday). Empty with
    /// `everyDay` false means "weekly, on the first event's weekday".
    var weekdays: [Int] = []
    var everyDay = false
    /// Last day to include.
    var until: Date?
    /// Or: stop after this many events.
    var count: Int?
    /// "the next 3 weeks": kept so it can be measured from the first copy.
    var spanCount: Int?
    var spanUnit: String?

    static let maxEvents = 120

    func matches(weekday: Int, firstWeekday: Int) -> Bool {
        if everyDay { return true }
        return weekdays.isEmpty ? weekday == firstWeekday : weekdays.contains(weekday)
    }
}

extension EventDraft {
    /// The start of every event this draft will create (one, when it doesn't repeat).
    func occurrences(calendar: Calendar = .current) -> [Date] {
        guard let start else { return [] }
        guard let rule = repeatRule else {
            let time = calendar.dateComponents([.hour, .minute], from: start)
            let firstDay = calendar.startOfDay(for: start)
            var days: [Date] = [start]
            for extra in extraDays.map({ calendar.startOfDay(for: $0) }).sorted()
            where extra != firstDay && !days.contains(where: { calendar.startOfDay(for: $0) == extra }) {
                days.append(calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: extra) ?? extra)
            }
            return days.sorted()
        }
        let firstDay = calendar.startOfDay(for: start)
        let firstWeekday = calendar.component(.weekday, from: start)
        let time = calendar.dateComponents([.hour, .minute], from: start)
        let skips = Set(skipDates.map { calendar.startOfDay(for: $0) })
        let lastDay = rule.until.map { calendar.startOfDay(for: $0) }
            ?? calendar.date(byAdding: .day, value: 400, to: firstDay) ?? firstDay
        let limit = min(rule.count ?? RepeatRule.maxEvents, RepeatRule.maxEvents)

        var result: [Date] = []
        var day = firstDay
        while day <= lastDay, result.count < limit {
            if rule.matches(weekday: calendar.component(.weekday, from: day), firstWeekday: firstWeekday), !skips.contains(day) {
                result.append(calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day)
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? lastDay.addingTimeInterval(86_400)
        }
        return result
    }
}
