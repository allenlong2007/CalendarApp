import Foundation

/// Spoken ways of naming a day that the system's date detector doesn't
/// understand: "next week", "Thursday next week", "this weekend", "in two
/// weeks", "the 25th", "the day after tomorrow". Anything it doesn't recognise
/// is left in the text for NSDataDetector ("tomorrow", "next Friday",
/// "October 25th", "10/25"...).
struct SpokenDateResolver {
    var calendar: Calendar = .current

    private static let weekdayNames = "monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun"
    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "a couple of": 2, "couple": 2,
    ]
    private static let months = "jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec"

    /// Finds a day phrase in `text`, removes it, and returns that day (midnight).
    func extractDay(_ text: inout String, now: Date) -> Date? {
        let today = calendar.startOfDay(for: now)

        // "Thursday next week", "Thursday of this week", "next week on Thursday".
        if let g = extract(#"\b(\#(Self.weekdayNames))\b\s*(?:of |in |on )?(this|next) week\b"#, from: &text) {
            return weekday(g[1], inWeekOffset: g[2].lowercased() == "next" ? 1 : 0, now: today)
        }
        if let g = extract(#"\b(this|next) week\s*(?:on |,)?\s*(\#(Self.weekdayNames))\b"#, from: &text) {
            return weekday(g[2], inWeekOffset: g[1].lowercased() == "next" ? 1 : 0, now: today)
        }
        if extract(#"\b(?:the )?day after tomorrow\b"#, from: &text) != nil { return add(.day, 2, to: today) }

        // "in two weeks", "3 days from now".
        if let g = extract(#"\bin (\d+|a couple of|an?|one|two|three|four|five|six|seven|eight|nine|ten) (day|week|month)s?\b"#, from: &text)
            ?? extract(#"\b(\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten) (day|week|month)s? from (?:now|today)\b"#, from: &text),
           let amount = Int(g[1]) ?? Self.numberWords[g[1].lowercased()] {
            return add(g[2].lowercased() == "day" ? .day : g[2].lowercased() == "week" ? .weekOfYear : .month, amount, to: today)
        }

        // Weekends.
        if extract(#"\bnext weekend\b"#, from: &text) != nil { return saturday(inWeekOffset: 1, now: today) }
        if extract(#"\b(?:this|the) weekend\b"#, from: &text) != nil { return saturday(inWeekOffset: 0, now: today) }

        // Whole-week / month phrases with no weekday: same weekday, shifted.
        if extract(#"\bnext week\b"#, from: &text) != nil { return add(.day, 7, to: today) }
        if extract(#"\bthis week\b"#, from: &text) != nil { return today }
        if extract(#"\bnext month\b"#, from: &text) != nil { return add(.month, 1, to: today) }

        // "the 25th", "on the 3rd" -- and a bare "25th" when no month is named.
        if let g = extract(#"\b(?:on )?the (\d{1,2})(?:st|nd|rd|th)\b"#, from: &text) ?? bareOrdinal(&text),
           let dayOfMonth = Int(g[1]) {
            return nextOccurrence(ofDayOfMonth: dayOfMonth, from: today)
        }
        return nil
    }

    // MARK: - Calendar math

    private func add(_ unit: Calendar.Component, _ amount: Int, to date: Date) -> Date {
        calendar.date(byAdding: unit, value: amount, to: date) ?? date
    }

    private func weekday(_ name: String, inWeekOffset offset: Int, now today: Date) -> Date? {
        guard let target = weekdayNumber(name),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return nil }
        let delta = (target - calendar.firstWeekday + 7) % 7
        return add(.day, delta + 7 * offset, to: weekStart)
    }

    private func saturday(inWeekOffset offset: Int, now today: Date) -> Date? {
        if offset == 0 {
            let weekday = calendar.component(.weekday, from: today)
            if weekday == 7 || weekday == 1 { return today }   // already the weekend
        }
        guard let target = weekdayNumber("saturday"),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return nil }
        let delta = (target - calendar.firstWeekday + 7) % 7
        return add(.day, delta + 7 * offset, to: weekStart)
    }

    private func nextOccurrence(ofDayOfMonth day: Int, from today: Date) -> Date? {
        guard (1...31).contains(day) else { return nil }
        var candidate = today
        for _ in 0..<14 {   // far enough to find a month that has that day
            let c = calendar.dateComponents([.year, .month], from: candidate)
            if let date = calendar.date(from: DateComponents(year: c.year, month: c.month, day: day)),
               calendar.component(.day, from: date) == day, date >= today { return date }
            candidate = add(.month, 1, to: calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1)) ?? candidate)
        }
        return nil
    }

    private func weekdayNumber(_ name: String) -> Int? {
        switch name.lowercased().prefix(3) {
        case "sun": return 1
        case "mon": return 2
        case "tue": return 3
        case "wed": return 4
        case "thu": return 5
        case "fri": return 6
        case "sat": return 7
        default: return nil
        }
    }

    // MARK: - Regex helper

    private func bareOrdinal(_ text: inout String) -> [String]? {
        guard text.range(of: #"(?i)\b(?:\#(Self.months))[a-z]*\b"#, options: .regularExpression) == nil else { return nil }
        return extract(#"\b(?:on )?(\d{1,2})(?:st|nd|rd|th)\b"#, from: &text)
    }

    @discardableResult
    private func extract(_ pattern: String, from text: inout String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) { groups.append(String(text[range])) } else { groups.append("") }
        }
        text.replaceSubrange(whole, with: " ")
        return groups
    }
}
