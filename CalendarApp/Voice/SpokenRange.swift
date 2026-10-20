import Foundation

/// "How long" and "which stretch" phrases: "for the rest of the quarter", "the
/// next few weeks", "for 6 weeks", "until December 4th", "this week". Used both
/// to say how far a repeating event goes and to bound a mass delete.
struct SpokenRangeResolver {
    var calendar: Calendar = .current
    /// The last day of the quarter, if the app can tell (see VoiceEventView).
    var quarterEnd: Date?

    struct End: Equatable {
        var until: Date?
        var count: Int?
        /// A phrase like "next week" also moves where the range begins.
        var rangeStart: Date?
        /// A how-long phrase was heard, even if its date isn't known.
        var recognized = false
        /// For "next 3 weeks": the length, so it can be measured from the real
        /// first day once that's known.
        var spanCount: Int?
        var spanUnit: String?
    }

    /// `n` units from `start`, as the last day included.
    func lastDay(forSpan n: Int, unit: String, startingOn start: Date) -> Date? {
        span(n, unit: unit, from: calendar.startOfDay(for: start))
    }

    private static let amount = #"(\d+|a few|a couple of|a couple|couple of|few|several|an?|one|two|three|four|five|six|seven|eight|nine|ten)"#
    private static let numbers: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "couple": 2, "a couple": 2, "couple of": 2, "a couple of": 2,
        "few": 3, "a few": 3, "several": 4,
    ]

    func extractEnd(_ text: inout String, from start: Date, now: Date = .now) -> End? {
        let startDay = calendar.startOfDay(for: max(start, calendar.startOfDay(for: now)) )
        var end = End()

        // "the rest of the quarter", "through the end of the month".
        if let g = extract(#"\b(?:for |through |until |till |to |by )?(?:the )?(?:rest|remainder|end) of (?:the |this )?(quarter|term|semester|school year|year|month|week)\b"#, from: &text) {
            end.recognized = true
            switch g[1].lowercased() {
            case "quarter", "term", "semester": end.until = quarterEnd
            case "month": end.until = lastDay(of: .month, containing: startDay)
            case "week": end.until = lastDay(of: .weekOfYear, containing: startDay)
            case "year": end.until = lastDay(of: .year, containing: startDay)
            default: break
            }
            return end
        }

        // "the next few weeks", "for the next 6 weeks".
        if let g = extract(#"\b(?:for )?(?:the )?next "# + Self.amount + #" (day|week|month)s?\b"#, from: &text)
            ?? extract(#"\bfor "# + Self.amount + #" (day|week|month)s?\b"#, from: &text),
           let n = number(g[1]) {
            end.recognized = true
            end.until = span(n, unit: g[2], from: startDay)
            end.spanCount = n
            end.spanUnit = g[2]
            return end
        }

        if let g = extract(#"\b(?:for )?"# + Self.amount + #" times\b"#, from: &text), let n = number(g[1]) {
            end.recognized = true
            end.count = n
            return end
        }

        // "until December 4th", "through the 20th".
        if let g = extract(#"\b(?:until|through|thru|till)\s+(?:the\s+)?(.+?)(?=\s+(?:at|from|every|skip|except|excluding|starting|remind|location|category|for)\b|[,.;]|$)"#, from: &text) {
            end.recognized = true
            end.until = SpokenDateResolver(calendar: calendar).day(in: g[1], now: now)
            return end
        }

        // A whole week.
        if extract(#"\bnext week\b"#, from: &text) != nil {
            end.recognized = true
            if let thisWeek = calendar.dateInterval(of: .weekOfYear, for: startDay),
               let next = calendar.date(byAdding: .day, value: 7, to: thisWeek.start) {
                end.rangeStart = next
                end.until = calendar.date(byAdding: .day, value: 6, to: next)
            }
            return end
        }
        if extract(#"\bthis week\b"#, from: &text) != nil {
            end.recognized = true
            end.until = lastDay(of: .weekOfYear, containing: startDay)
            return end
        }
        return nil
    }

    // MARK: - Math

    private func number(_ word: String) -> Int? { Int(word) ?? Self.numbers[word.lowercased()] }

    /// `n` units starting on `start`, as the last day included.
    private func span(_ n: Int, unit: String, from start: Date) -> Date? {
        let component: Calendar.Component = unit.lowercased() == "day" ? .day : unit.lowercased() == "week" ? .weekOfYear : .month
        guard let after = calendar.date(byAdding: component, value: n, to: start) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: after)
    }

    private func lastDay(of component: Calendar.Component, containing date: Date) -> Date? {
        guard let interval = calendar.dateInterval(of: component, for: date) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: interval.end)
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
