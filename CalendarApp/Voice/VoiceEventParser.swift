import Foundation

/// Turns a spoken sentence into an `EventDraft`, or -- when a draft already
/// exists -- treats the sentence as a correction to it ("make it 7pm", "category
/// exercise", "location the gym") and changes only what was mentioned.
///
/// Rule-based on purpose: it runs instantly, offline, and is easy to test. It's
/// behind `parse(_:applying:)` so a smarter parser (e.g. an on-device language
/// model) can replace it without touching the speech or UI layers.
struct VoiceEventParser {
    /// Titles of the user's calendars ("Exercise", "Church", ...).
    var calendarTitles: [String]
    var calendar: Calendar = .current

    func parse(_ spoken: String, applying existing: EventDraft? = nil, now: Date = .now) -> EventDraft {
        var draft = existing ?? EventDraft()
        let isCorrection = existing != nil
        var rest = normalize(spoken)

        // Order matters: pull out the pieces with the most distinctive wording
        // first, so what's left is the title (and so "at 6pm" is gone before
        // "at the courts" is read as a location).
        if let explicit = extractExplicitTitle(&rest) { draft.title = capitalized(explicit) }
        if let minutes = extractReminder(&rest) { draft.reminderMinutes = minutes }
        if let category = extractCategory(&rest) { draft.calendarTitle = category }
        if extract(#"\ball[- ]day\b"#, from: &rest) != nil { draft.isAllDay = true }
        let duration = extractDuration(&rest)
        // Dates and times go before the location, or "at 6pm" reads as a place.
        applyDateAndTime(&rest, to: &draft, duration: duration, isCorrection: isCorrection, now: now)
        if let location = extractLocation(&rest) { draft.location = location }

        if draft.calendarTitle == nil, let guess = guessCategory(in: spoken) { draft.calendarTitle = guess }

        // What remains is the title -- but only a *first* sentence names the
        // event; in a correction the leftover words are just chatter.
        if !isCorrection || draft.title.isEmpty {
            let leftover = cleanTitle(rest)
            if !leftover.isEmpty && (draft.title.isEmpty || !isCorrection) {
                if draft.title.isEmpty { draft.title = capitalized(leftover) }
            }
        }
        return draft
    }

    // MARK: - Normalising

    private func normalize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (pattern, replacement) in [
            (#"(?i)\b([ap])\.m\.?"#, "$1m"),
            (#"(?i)\bp\s?m\b"#, "pm"), (#"(?i)\ba\s?m\b"#, "am"),
            (#"(?i)\bnoon\b"#, "12 pm"), (#"(?i)\bmidnight\b"#, "12 am"),
            (#"(?i)\bsix thirty\b"#, "6:30"),
        ] {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    // MARK: - Small extractors (each removes what it consumes from `rest`)

    /// Removes the first match of `pattern` from `text` and returns its capture
    /// groups (index 0 = whole match).
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

    private func extractExplicitTitle(_ text: inout String) -> String? {
        extract(#"\b(?:call it|name it|title it|titled|rename (?:it )?to|the title is|title is|title)\s+(.+?)(?=\s+(?:on|at|from|for|every|category|calendar|location|remind)\b|[,.]|$)"#, from: &text)?[1]
    }

    private func extractReminder(_ text: inout String) -> Int? {
        if extract(#"\bno (?:reminder|alert|notification)s?\b"#, from: &text) != nil { return 0 }
        guard let g = extract(#"\b(?:remind me|reminder|alert me|notify me|alert)\s+(?:me\s+)?(?:for\s+)?(\d+|an?|one|two|three|five|ten|fifteen|thirty|half an)\s*(minutes?|mins?|hours?|hrs?|days?)\s*(?:before|ahead|early|prior)?"#, from: &text) else { return nil }
        guard let amount = number(g[1]) else { return nil }
        return Int(amount * unitMinutes(g[2]))
    }

    private func extractDuration(_ text: inout String) -> Int? {
        if extract(#"\ban hour and a half\b"#, from: &text) != nil { return 90 }
        guard let g = extract(#"\b(?:for|make it|lasting|lasts|it takes|takes)\s+(\d+(?:\.\d+)?|an?|one|two|three|four|half an?)\s*(hours?|hrs?|minutes?|mins?)\b"#, from: &text),
              let amount = number(g[1]) else { return nil }
        return Int(amount * unitMinutes(g[2]))
    }

    private func extractLocation(_ text: inout String) -> String? {
        let stop = #"(?=\s+(?:on|from|for|every|category|calendar|remind|reminder|tomorrow|today|tonight|next|this|at \d)\b|[,.;]|$)"#
        if let g = extract(#"\blocation\s+(?:is\s+|to\s+)?(.+?)"# + stop, from: &text) { return capitalized(trimArticle(g[1])) }
        if let g = extract(#"\b(?:at|in|@)\s+(.+?)"# + stop, from: &text) { return capitalized(trimArticle(g[1])) }
        return nil
    }

    private func extractCategory(_ text: inout String) -> String? {
        for title in calendarTitles.sorted(by: { $0.count > $1.count }) {
            let t = NSRegularExpression.escapedPattern(for: title.lowercased())
            for pattern in [
                #"\b(?:in|under|as|to|for|on)?\s*(?:the\s+)?"# + t + #"\s+(?:category|calendar)\b"#,
                #"\b(?:category|calendar)\s+(?:is\s+|to\s+)?(?:the\s+)?"# + t + #"\b"#,
            ] where extract(pattern, from: &text) != nil { return title }
        }
        return nil
    }

    /// A calendar named in passing ("gym session, exercise") when there was no
    /// "category ..." phrasing. Looser, so it never removes words from the title.
    private func guessCategory(in text: String) -> String? {
        calendarTitles.sorted { $0.count > $1.count }.first { title in
            title.count >= 4 && text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: title) + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - Dates and times

    private static let dayWords = #"(?i)\b(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)[a-z]*\b|\b(?:today|tomorrow|tonight|next|this coming|jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b|\b\d{1,2}(?:st|nd|rd|th)\b|\b\d{1,2}/\d{1,2}\b"#
    private static let timeWords = #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b|\bo'?clock\b"#

    private func applyDateAndTime(_ text: inout String, to draft: inout EventDraft, duration: Int?, isCorrection: Bool, now: Date) {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var foundDay: Date?, foundTime: DateComponents?, foundDuration: TimeInterval = 0
        var consumed: [Range<String.Index>] = []

        for match in matches {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let phrase = String(text[range])
            let hasDay = phrase.range(of: Self.dayWords, options: .regularExpression) != nil
            let hasTime = phrase.range(of: Self.timeWords, options: .regularExpression) != nil
            if hasDay && foundDay == nil { foundDay = date }
            if hasTime && foundTime == nil {
                foundTime = calendar.dateComponents([.hour, .minute], from: date)
                foundDuration = max(foundDuration, match.duration)
            }
            if hasDay || hasTime { consumed.append(range) }
            else if !hasDay && !hasTime { continue }
        }
        for range in consumed.sorted(by: { $0.lowerBound > $1.lowerBound }) { text.replaceSubrange(range, with: " ") }

        guard foundDay != nil || foundTime != nil || duration != nil else { return }

        let oldStart = draft.start
        let oldTimeKnown = draft.timeKnown
        let oldLength = draft.durationMinutes
        let day = foundDay.map { calendar.startOfDay(for: $0) } ?? oldStart.map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: now)

        func at(_ hour: Int, _ minute: Int) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day }

        if let time = foundTime, let h = time.hour, let m = time.minute {
            var start = at(h, m)
            // "6pm" with no day, said at 8pm, means tomorrow.
            if foundDay == nil && oldStart == nil && start < now { start = calendar.date(byAdding: .day, value: 1, to: start) ?? start }
            let length = duration ?? (foundDuration > 0 ? Int(foundDuration / 60) : (oldLength ?? 60))
            draft.start = start
            draft.end = start.addingTimeInterval(Double(length) * 60)
            draft.timeKnown = true
            draft.isAllDay = false
        } else if foundDay != nil {
            let length = duration ?? oldLength ?? 60
            if let oldStart, oldTimeKnown {
                // A new day with no time keeps the time already set.
                let c = calendar.dateComponents([.hour, .minute], from: oldStart)
                let start = at(c.hour ?? 9, c.minute ?? 0)
                draft.start = start
                draft.end = start.addingTimeInterval(Double(length) * 60)
            } else {
                // Only a day so far: a placeholder time, flagged as unknown.
                draft.start = at(9, 0)
                draft.end = draft.start?.addingTimeInterval(Double(length) * 60)
                draft.timeKnown = false
            }
        } else if let duration, let start = draft.start {
            draft.end = start.addingTimeInterval(Double(duration) * 60)
        }

        if draft.isAllDay, let start = draft.start {
            draft.start = calendar.startOfDay(for: start)
            draft.end = calendar.date(byAdding: .day, value: 1, to: draft.start ?? start)
            draft.timeKnown = true
        }
    }

    // MARK: - Title cleanup

    private func cleanTitle(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(
            of: #"(?i)^\s*(?:please\s+|can you\s+|could you\s+|i want to\s+|i need to\s+)?(?:add|create|schedule|put|set up|make|book|new)\s+(?:me\s+)?(?:an?\s+|the\s+)?(?:new\s+)?(?:event|appointment)?\s*(?:called|named|for)?\s*"#,
            with: "", options: .regularExpression)
        // Words stranded by what was cut out ("pickleball on", "to Warren").
        s = s.replacingOccurrences(of: #"(?i)(?:\s+(?:on|at|from|to|for|and|in|every|until|the|a|an|my)\b)+\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)^\s*(?:(?:on|at|from|to|and|every|the)\b\s*)+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[,.;]+"#, with: " ", options: .regularExpression)
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private func capitalized(_ text: String) -> String {
        text.split(separator: " ").map { word in
            let w = String(word)
            return w == w.uppercased() && w.count > 1 ? w : w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }

    private func trimArticle(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)^(?:the)\s+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private func number(_ word: String) -> Double? {
        let w = word.lowercased()
        if let n = Double(w) { return n }
        return ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "ten": 10, "fifteen": 15, "thirty": 30, "half an": 0.5, "half a": 0.5][w]
    }

    private func unitMinutes(_ unit: String) -> Double {
        let u = unit.lowercased()
        if u.hasPrefix("h") { return 60 }
        if u.hasPrefix("d") { return 1440 }
        return 1
    }
}
