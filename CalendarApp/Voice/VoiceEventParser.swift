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
    /// Last day of the quarter, for "for the rest of the quarter".
    var quarterEnd: Date?

    func parse(_ spoken: String, applying existing: EventDraft? = nil, now: Date = .now) -> EventDraft {
        var draft = existing ?? EventDraft()
        let isCorrection = existing != nil
        var rest = normalize(spoken)

        // Order matters: pull out the pieces with the most distinctive wording
        // first, so what's left is the title (and so "at 6pm" is gone before
        // "at the courts" is read as a location).
        if let explicit = extractExplicitTitle(&rest) { draft.title = capitalized(explicit) }
        if let minutes = extractReminder(&rest) { draft.reminderMinutes = minutes }
        // "Remind me in 6 months to ...", "set a reminder for Friday at 3": a reminder
        // *is* an event on that day, so only the lead-in words come out.
        let isReminder = extractReminderLeadIn(&rest)
        if let category = extractCategory(&rest) { draft.calendarTitle = category; draft.calendarIdentifier = nil }
        if extract(#"\ball[- ]day\b"#, from: &rest) != nil { draft.isAllDay = true }
        let duration = extractDuration(&rest)

        // Bulk adds: "every Friday", "every day this week", "weekdays", plus how
        // long ("for the rest of the quarter", "the next few weeks", "until Dec 4")
        // and exceptions ("skip Thanksgiving"). All come out before the date is
        // read, or "Friday" would be taken for a single day.
        let newRule = extractRepeat(&rest)
        rest = rest.replacingOccurrences(of: #"(?i)\bstarting (?!at\b)(?:on |from )?"#, with: "", options: .regularExpression)
        let skips = extractSkips(&rest, now: now)
        let repeating = newRule != nil || draft.repeatRule != nil
        let end = repeating
            ? SpokenRangeResolver(calendar: calendar, quarterEnd: quarterEnd).extractEnd(&rest, from: draft.start ?? now, now: now)
            : nil
        let previousStart = draft.start
        if !repeating { draft.extraDays += extractExtraDays(&rest, now: now) }

        // Dates and times go before the location, or "at 6pm" reads as a place.
        let daySpoken = applyDateAndTime(&rest, to: &draft, duration: duration, isCorrection: isCorrection, now: now)
        if isReminder && !isCorrection && newRule == nil { shapeReminder(&draft, duration: duration) }
        if repeating {
            applyRepeat(newRule, end: end, skips: skips, to: &draft, daySpoken: daySpoken, previousStart: previousStart, now: now)
        } else if !skips.isEmpty {
            draft.skipDates += skips
        }
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

    // MARK: - Several different events

    /// "Add a dentist visit Tuesday at 3 and a haircut Friday at 5": drafts for each,
    /// or nil when the sentence isn't several complete events (so "dinner with Sam
    /// and Alex tomorrow" stays one). Every clause must bring its own title and day.
    func parseMany(_ spoken: String, now: Date = .now) -> [EventDraft]? {
        let clauses = normalize(spoken).components(separatedBy: #"\s*(?:,|&|\band\b|\bplus\b|\bthen\b|\balso\b)\s*"#)
        guard clauses.count >= 2, clauses.count <= 8 else { return nil }
        var drafts: [EventDraft] = []
        for (index, clause) in clauses.enumerated() {
            let cleaned = index == 0 ? clause : clause.replacingOccurrences(
                of: #"(?i)^(?:(?:add|schedule|create|put|book)\s+)?(?:an?\s+|the\s+)?(?:new\s+)?(?:event\s+|appointment\s+)?(?:(?:called|named)\s+)?"#,
                with: "", options: .regularExpression)
            let draft = parse(cleaned, now: now)
            guard !draft.title.isEmpty, draft.start != nil, draft.extraDays.isEmpty || index == 0 else { return nil }
            drafts.append(draft)
        }
        return drafts
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
        // "remind me 10 minutes before" is an alert on the event; "... 10 minutes from now" is not.
        guard let g = extract(#"\b(?:remind me|reminder|alert me|notify me|alert)\s+(?:me\s+)?(?:for\s+)?(\d+|an?|one|two|three|five|ten|fifteen|thirty|half an)\s*(minutes?|mins?|hours?|hrs?|days?)\b(?!\s*(?:from now|later))\s*(?:before|ahead|early|prior)?"#, from: &text) else { return nil }
        guard let amount = number(g[1]) else { return nil }
        return Int(amount * unitMinutes(g[2]))
    }

    /// Removes "remind me (to/about/that)" and "set a reminder (for/to)", leaving the
    /// when and the what. True when the sentence was a reminder request.
    private func extractReminderLeadIn(_ text: inout String) -> Bool {
        extract(#"\b(?:(?:please\s+)?(?:set|make|add|create|put|schedule)(?:\s+up)?\s+(?:me\s+)?(?:an?\s+|the\s+)?(?:new\s+)?reminders?|remind me|reminder)\b(?:\s+(?:for|to|that|about|on|at))?(?![a-z])"#, from: &text) != nil
    }

    /// A reminder with only a day is an all-day item; with a time it's a short block.
    private func shapeReminder(_ draft: inout EventDraft, duration: Int?) {
        guard let start = draft.start else { return }
        if !draft.timeKnown {
            let day = calendar.startOfDay(for: start)
            draft.isAllDay = true
            draft.start = day
            draft.end = calendar.date(byAdding: .day, value: 1, to: day)
            draft.timeKnown = true
        } else if duration == nil {
            draft.end = start.addingTimeInterval(15 * 60)
        }
    }

    private func extractDuration(_ text: inout String) -> Int? {
        if extract(#"\ban hour and a half\b"#, from: &text) != nil { return 90 }
        guard let g = extract(#"\b(?:for|make it|lasting|lasts|it takes|takes)\s+(\d+(?:\.\d+)?|an?|one|two|three|four|half an?)\s*(hours?|hrs?|minutes?|mins?)\b"#, from: &text),
              let amount = number(g[1]) else { return nil }
        return Int(amount * unitMinutes(g[2]))
    }

    private func extractLocation(_ text: inout String) -> String? {
        // Prepositions stranded by an extracted time ("... at") aren't places.
        text = text.replacingOccurrences(of: #"(?i)(?:\s+(?:at|on|from|in|by|for|to))+\s*$"#, with: "", options: .regularExpression)
        let stop = #"(?=\s+(?:on|from|for|every|category|calendar|remind|reminder|tomorrow|today|tonight|next|this|at \d)\b|[,.;]|$)"#
        if let g = extract(#"\blocation\s+(?:is\s+|to\s+)?(.+?)"# + stop, from: &text) {
            let place = trimArticle(g[1])
            return place.contains(where: \.isLetter) ? capitalized(place) : nil
        }
        if let g = extract(#"\b(?:at|in|@)\s+(.+?)"# + stop, from: &text) {
            let place = trimArticle(g[1])
            return place.contains(where: \.isLetter) ? capitalized(place) : nil
        }
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

    // MARK: - Several days

    /// "... Tuesday and next Friday": a clause made only of date words, right after
    /// another date, is one more day for the same event. It comes out of `text`; any
    /// time said with it ("at 3 pm") stays, since the whole event shares one time.
    private func extractExtraDays(_ text: inout String, now: Date) -> [Date] {
        let separator = #"\s*(?:,|&|\band\b|\bplus\b)\s*"#
        guard let regex = try? NSRegularExpression(pattern: separator, options: [.caseInsensitive]) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return [] }

        // Clause i runs from the end of separator i-1 to the start of separator i.
        var bounds: [(Range<String.Index>, Range<String.Index>?)] = []   // (clause, separator before it)
        var last = text.startIndex
        var sepBefore: Range<String.Index>?
        for m in matches {
            guard let sep = Range(m.range, in: text) else { continue }
            bounds.append((last..<sep.lowerBound, sepBefore))
            last = sep.upperBound; sepBefore = sep
        }
        bounds.append((last..<text.endIndex, sepBefore))

        let resolver = SpokenDateResolver(calendar: calendar)
        var days: [Date] = []
        var removals: [Range<String.Index>] = []
        var carriedTime = ""
        for index in 1..<bounds.count {
            let clauseRange = bounds[index].0
            let clause = String(text[clauseRange])
            let before = String(text[bounds[index - 1].0]).split(separator: " ").last.map(String.init) ?? ""
            // The leading run of date words is the day (and time); what follows stays.
            var consumed = 0
            let tokens = clause.split(separator: " ", omittingEmptySubsequences: true)
            for token in tokens { if isDateWord(String(token)) { consumed += 1 } else { break } }
            guard consumed > 0, isDateWord(before), let sep = bounds[index].1 else { continue }
            let phrase = tokens.prefix(consumed).joined(separator: " ")
            guard let day = resolver.day(in: phrase, now: now) else { continue }
            days.append(day)
            // Cut from the separator through the end of the day phrase.
            guard let phraseEnd = clause.range(of: phrase) else { continue }
            let offset = clause.distance(from: clause.startIndex, to: phraseEnd.upperBound)
            let end = text.index(clauseRange.lowerBound, offsetBy: offset)
            removals.append(sep.lowerBound..<end)
            if let t = phrase.range(of: #"(?i)\b(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)\b"#, options: .regularExpression) { carriedTime = " " + String(phrase[t]) }
        }
        for range in removals.reversed() { text.replaceSubrange(range, with: " ") }
        text += carriedTime
        return days
    }

    // MARK: - Repeats

    private static let weekdayNames = "monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun"

    private func extractRepeat(_ text: inout String) -> RepeatRule? {
        if extract(#"\b(?:every|each) (?:weekday|work ?day|school day)s?\b|\bweekdays\b"#, from: &text) != nil {
            return RepeatRule(weekdays: [2, 3, 4, 5, 6])
        }
        if extract(#"\b(?:every ?day|every single day|each day|daily)\b"#, from: &text) != nil {
            return RepeatRule(everyDay: true)
        }
        let plural = #"(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)s"#
        let names = Self.weekdayNames
        let list = extract(#"\b(?:every|each)\s+((?:\#(names))s?(?:\s*(?:,|and|&)\s*(?:\#(names))s?)*)\b"#, from: &text)
            ?? extract(#"\b(?:on\s+)?(\#(plural)(?:\s*(?:,|and|&)\s*\#(plural))*)\b"#, from: &text)
        if let list {
            let days = weekdayNumbers(in: list[1])
            if !days.isEmpty { return RepeatRule(weekdays: days) }
        }
        if extract(#"\b(?:weekly|every week|each week|once a week)\b"#, from: &text) != nil { return RepeatRule() }
        return nil
    }

    private func weekdayNumbers(in text: String) -> [Int] {
        var result: [Int] = []
        let lower = text.lowercased()
        for (prefix, number) in [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]
        where lower.range(of: #"\b"# + prefix, options: .regularExpression) != nil {
            result.append(number)
        }
        return result
    }

    /// "skip Thanksgiving", "except November 26th and December 3rd".
    private func extractSkips(_ text: inout String, now: Date) -> [Date] {
        guard let g = extract(#"\b(?:skip|except(?: for)?|excluding|but not|not on|other than)\s+(.+?)(?=\s+(?:but|until|through|starting|every|remind|location|category)\b|[;.]|$)"#, from: &text) else { return [] }
        let resolver = SpokenDateResolver(calendar: calendar)
        return g[1].components(separatedBy: CharacterSet(charactersIn: ",&"))
            .flatMap { $0.components(separatedBy: " and ") }
            .compactMap { resolver.day(in: $0.trimmingCharacters(in: .whitespaces), now: now) }
    }

    private func applyRepeat(_ newRule: RepeatRule?, end: SpokenRangeResolver.End?, skips: [Date], to draft: inout EventDraft,
                             daySpoken: Bool, previousStart: Date?, now: Date) {
        var rule = newRule ?? draft.repeatRule ?? RepeatRule()
        if let newRule, let old = draft.repeatRule {   // "make it every Wednesday": keep how long
            rule.until = old.until
            rule.count = old.count
            _ = newRule
        }
        let today = calendar.startOfDay(for: now)
        let ranger = SpokenRangeResolver(calendar: calendar, quarterEnd: quarterEnd)

        // Where the first one falls.
        let reposition = newRule != nil || daySpoken || end?.rangeStart != nil || draft.start == nil || previousStart == nil
        if reposition {
            let baseDay: Date
            if daySpoken, let start = draft.start { baseDay = calendar.startOfDay(for: start) }
            else if let rangeStart = end?.rangeStart { baseDay = rangeStart }
            else if let previousStart { baseDay = calendar.startOfDay(for: previousStart) }
            else { baseDay = today }

            let time = (draft.timeKnown ? draft.start : nil).map { calendar.dateComponents([.hour, .minute], from: $0) }
            let hour = time?.hour ?? 9, minute = time?.minute ?? 0
            let length = draft.durationMinutes ?? 60

            var chosen = baseDay
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: baseDay) else { break }
                let weekday = calendar.component(.weekday, from: day)
                let anchorWeekday = calendar.component(.weekday, from: baseDay)
                guard rule.matches(weekday: weekday, firstWeekday: anchorWeekday) else { continue }
                let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                let stillAhead = day > today || candidate > now || !draft.timeKnown
                if stillAhead || daySpoken && day >= today { chosen = day; break }
            }
            let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: chosen) ?? chosen
            draft.start = start
            draft.end = start.addingTimeInterval(Double(length) * 60)
        }

        if let end {
            if let count = end.count { rule.count = count; rule.until = nil }
            else if let n = end.spanCount, let unit = end.spanUnit, let start = draft.start {
                rule.until = ranger.lastDay(forSpan: n, unit: unit, startingOn: start); rule.count = nil
                rule.spanCount = n; rule.spanUnit = unit
            } else if let until = end.until { rule.until = until; rule.count = nil }
        }
        draft.repeatRule = rule
        draft.skipDates += skips
    }

    // MARK: - Dates and times

    private static let dayWords = #"(?i)\b(?:mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)[a-z]*\b|\b(?:today|tomorrow|tonight|next|this coming|jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b|\b\d{1,2}(?:st|nd|rd|th)\b|\b\d{1,2}/\d{1,2}\b"#
    private static let timeWords = #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b|\bo'?clock\b"#

    @discardableResult
    private func applyDateAndTime(_ text: inout String, to draft: inout EventDraft, duration: Int?, isCorrection: Bool, now: Date) -> Bool {
        // Phrases the system detector can't read ("next week", "the 25th") first.
        var foundDay: Date? = SpokenDateResolver(calendar: calendar).extractDay(&text, now: now)
        var foundTime: DateComponents?, foundDuration: TimeInterval = 0
        var consumed: [Range<String.Index>] = []

        // "in 20 minutes", "in half an hour", "2 hours from now": a moment relative to now.
        let amount = #"(\d+(?:\.\d+)?|an?|one|two|three|four|five|six|seven|eight|nine|ten|fifteen|twenty|thirty|forty[ -]?five|half an?)"#
        if let g = extract(#"\b(?:in|after)\s+\#(amount)\s*(minutes?|mins?|hours?|hrs?)(?:'s)?(?:\s+time)?\b"#, from: &text)
            ?? extract(#"\b\#(amount)\s*(minutes?|mins?|hours?|hrs?)\s+(?:from now|later)\b"#, from: &text),
           let count = number(g[1]) {
            let target = now.addingTimeInterval(count * unitMinutes(g[2]) * 60)
            foundDay = calendar.startOfDay(for: target)
            foundTime = calendar.dateComponents([.hour, .minute], from: target)
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
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
        // The detector sometimes swallows ordinary words ("lunch" reads as a time of
        // day); put back whatever in a matched phrase isn't date or time vocabulary.
        for range in consumed.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            let kept = text[range].split(separator: " ").map(String.init).filter { !isDateWord($0) }.joined(separator: " ")
            text.replaceSubrange(range, with: " \(kept) ")
        }

        guard foundDay != nil || foundTime != nil || duration != nil else { return false }

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
        return foundDay != nil
    }

    private static let dateVocabulary = #"(?i)^(?:\d{1,2}(?::\d{2})?(?:am|pm)?|am|pm|at|on|from|to|until|till|through|the|of|and|in|by|-|noon|midnight|morning|afternoon|evening|night|tonight|today|tomorrow|next|this|last|week|weekend|month|year|day|days|o'clock|(?:mon|tues?|wed(?:nes)?|thu(?:rs?)?|fri|sat(?:ur)?|sun)(?:day)?|\d{1,2}(?:st|nd|rd|th)|\d{1,2}/\d{1,2}(?:/\d{2,4})?|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)$"#

    private func isDateWord(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ",.;"))
        return trimmed.isEmpty || trimmed.range(of: Self.dateVocabulary, options: .regularExpression) != nil
    }

    // MARK: - Title cleanup

    private func cleanTitle(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(
            of: #"(?i)^\s*(?:please\s+|can you\s+|could you\s+|i want to\s+|i need to\s+)?(?:add|create|schedule|put|set up|make|book|new)\s+(?:me\s+)?(?:an?\s+|the\s+)?(?:new\s+)?(?:event|appointment)?\s*(?:(?:called|named|titled|for)\s+)*"#,
            with: "", options: .regularExpression)
        // Words stranded by what was cut out ("pickleball on", "to Warren").
        s = s.replacingOccurrences(of: #"(?i)(?:\s+(?:on|at|from|to|for|and|in|every|until|the|a|an|my)\b)+\s*$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)^\s*(?:(?:on|at|from|to|and|every|the|that|about|for)\b\s*)+"#, with: "", options: .regularExpression)
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
        return ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30,
                "forty five": 45, "forty-five": 45, "fortyfive": 45, "half an": 0.5, "half a": 0.5][w]
    }

    private func unitMinutes(_ unit: String) -> Double {
        let u = unit.lowercased()
        if u.hasPrefix("h") { return 60 }
        if u.hasPrefix("d") { return 1440 }
        return 1
    }
}

/// An existing event, as much as is needed to copy it.
struct DuplicateSource: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String?
    var calendarIdentifier: String?
    var location: String?
    var notes: String?
}

extension VoiceEventParser {
    /// The words in a "duplicate ..." request that name the event -- what's left
    /// once repeats, ranges and filler like "same time" are taken out.
    func duplicateTitleWords(from rest: String, now: Date = .now) -> [String] {
        let words = parseDuplicateRequest(rest, now: now).title
        let stop: Set<String> = ["event", "events", "appointment", "the", "my", "a", "an", "to", "of", "and", "for", "on", "at"]
        return words.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { !stop.contains($0) && $0.count >= 2 }
    }

    /// "same time, same everything else" says nothing new; it must not end up in a title.
    static func withoutFiller(_ text: String) -> String {
        var s = text
        for pattern in [
            #"(?i)\b(?:and |with |at )?(?:the )?same (?:time|place|location|category|calendar|details|settings|length|duration|everything(?: else)?|as (?:before|that|it|the original))\b"#,
            #"(?i)\b(?:and )?everything else\b"#,
        ] {
            while s.range(of: pattern, options: .regularExpression) != nil {
                s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
        }
        return s
    }

    /// The draft for copying `source` as described in `rest` ("every Thursday for
    /// the rest of the quarter"). Everything about the event comes from the source;
    /// only the days come from what was said. The first copy lands on the first
    /// matching day AFTER the original, so the original isn't duplicated onto itself.
    func duplicate(_ source: DuplicateSource, saying rest: String, now: Date = .now) -> EventDraft {
        var draft = parseDuplicateRequest(rest, now: now)
        var rule = draft.repeatRule ?? RepeatRule()   // "duplicate ... for the rest of the quarter" = weekly

        draft.title = source.title
        draft.calendarTitle = source.calendarTitle
        draft.calendarIdentifier = source.calendarIdentifier
        draft.location = source.location
        draft.notes = source.notes
        draft.isAllDay = source.isAllDay
        draft.timeKnown = true
        let length = source.end.timeIntervalSince(source.start)
        let time = calendar.dateComponents([.hour, .minute], from: source.start)
        let sourceWeekday = calendar.component(.weekday, from: source.start)

        let today = calendar.startOfDay(for: now)
        let dayAfterSource = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: source.start)) ?? today
        let base = max(today, dayAfterSource)
        var first = base
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: base) else { break }
            if rule.matches(weekday: calendar.component(.weekday, from: day), firstWeekday: sourceWeekday) { first = day; break }
        }
        let start = source.isAllDay ? first : (calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: first) ?? first)
        draft.start = start
        draft.end = start.addingTimeInterval(length)

        // "for the next 3 weeks" counts from the first copy, not from when it was said.
        if let n = rule.spanCount, let unit = rule.spanUnit {
            rule.until = SpokenRangeResolver(calendar: calendar, quarterEnd: quarterEnd).lastDay(forSpan: n, unit: unit, startingOn: first)
        }
        draft.repeatRule = rule
        return draft
    }

    /// Reads the repeat/range part of a duplicate request. Without a weekday
    /// ("... for the rest of the quarter") it's read as weekly, so the range
    /// phrase is still understood and kept out of the title.
    private func parseDuplicateRequest(_ rest: String, now: Date) -> EventDraft {
        let text = Self.withoutFiller(rest)
        let draft = parse(text, now: now)
        return draft.repeatRule == nil ? parse(text + " weekly", now: now) : draft
    }
}
