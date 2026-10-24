import Foundation

/// What a spoken sentence is asking for, decided before any event details are
/// read out of it. Confirming and cancelling are intents too, so the whole flow
/// can be done hands-free ("delete pickleball practice Thursday" ... "yes").
enum VoiceIntent: Equatable {
    case email(VoiceEmailRequest)
    case delete(VoiceDeleteRequest)
    case confirm
    /// "delete it" / "yes delete" -- the only spoken way to confirm a deletion.
    /// A generic "ok" or "sure" (easily said or misheard) never deletes.
    case confirmDelete
    /// "duplicate the speak up meeting every Thursday for the rest of the quarter":
    /// copy an existing event. Carries what was said after the verb.
    case duplicate(String)
    case cancel
    /// "move this event one day forward", "push the dentist 2 months back".
    case move(VoiceMoveRequest)
    /// Anything else: details of an event to add, or a correction to the draft.
    case describeEvent
}

struct VoiceDeleteRequest: Equatable {
    /// Words from the event's title, lowercased ("pickleball", "practice").
    var titleWords: [String]
    var day: Date?
    /// Hour of day (0-23) if a time was spoken.
    var hour: Int?
    /// "Delete all pickleball practice ...": every matching event in the range,
    /// not just the best match. Still requires title words and confirmation.
    var isAll = false
    /// The stretch to delete in (inclusive days). Open-ended defaults to upcoming only.
    var rangeStart: Date?
    var rangeEnd: Date?
    /// "every Thursday": only events on these weekdays (Calendar numbering).
    var weekdays: [Int] = []
    /// A range was spoken but its end isn't known ("the rest of the quarter"
    /// when the app can't tell when that is) -- better to match nothing than guess.
    var rangeUnresolved = false
    /// "delete the dentist and the haircut": one request per event. Used only if
    /// the sentence taken as a single title matches nothing.
    var splitParts: [VoiceDeleteRequest] = []
}

struct VoiceIntentClassifier {
    var calendar: Calendar = .current
    var quarterEnd: Date?

    func classify(_ spoken: String, now: Date = .now) -> VoiceIntent {
        if let request = VoiceEmailRequest.parse(spoken) { return .email(request) }
        let text = spoken.lowercased()
            .replacingOccurrences(of: #"[.!?,]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if matches(#"^(?:yes )?(?:delete|remove) (?:it|that|this|them|all|all of them|all of those|everything)(?: please)?$"#, text) || matches(#"^yes,? (?:please )?(?:delete|remove)$"#, text) { return .confirmDelete }
        if matches(#"^(?:yes|yeah|yep|yup|sure|confirm|do it|go ahead|looks good|that'?s right|correct|add it|save it|ok|okay)(?: please)?$"#, text) { return .confirm }
        if matches(#"^(?:no|nope|cancel|never ?mind|stop|don'?t|do not|forget it|keep it)(?: it| that)?$"#, text) { return .cancel }

        if matches(#"^(?:please\s+)?(?:duplicate|copy|clone|replicate)\s+(?!(?:it|that|this|them)\b)\S"#, text) {
            // Re-read from the original wording (casing matters for the title).
            let original = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"(?i)^(?:please\s+)?(?:duplicate|copy|clone|replicate)\s+(?:the\s+|my\s+)?"#, with: "", options: .regularExpression)
            return .duplicate(original)
        }
        if let move = moveRequest(from: spoken, now: now) { return .move(move) }
        if let rest = capture(#"^(?:please\s+)?(?:delete|remove|cancel|erase|get rid of)\s+(?:the\s+|my\s+|that\s+)?(.+)$"#, in: text) {
            var single = request(from: rest, now: now)
            let clauses = rest.components(separatedBy: #"\s*(?:,|&|\band\b|\bplus\b|\balso\b)\s*"#)
            if clauses.count >= 2 {
                var parts = clauses.map { request(from: $0, now: now) }
                // "... and the haircut on Friday": a day said once, at the end, covers all of them.
                if let last = parts.last, let day = last.day, parts.dropLast().allSatisfy({ $0.day == nil }) {
                    for i in parts.indices { parts[i].day = day; if parts[i].hour == nil { parts[i].hour = last.hour } }
                }
                single.splitParts = parts
            }
            return .delete(single)
        }
        return .describeEvent
    }

    func request(from rest: String, now: Date) -> VoiceDeleteRequest {
        var text = rest
        var isAll = false
        var weekdays: [Int] = []
        var rangeStart: Date?, rangeEnd: Date?
        var rangeUnresolved = false

        // "all", "every Thursday", "Thursdays": a bulk request. These words are
        // removed first so they aren't mistaken for a single day.
        let names = "monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun"
        if let days = take(#"\b(?:(?:every|each)\s+((?:\#(names))s?(?:\s*(?:,|and|&)\s*(?:\#(names))s?)*)|((?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)s))\b"#, from: &text) {
            weekdays = weekdayNumbers(in: days)
            isAll = true
        }
        if take(#"\b(?:all|every|each|everything)(?:\s+of)?(?:\s+(?:the|my))?\b"#, from: &text) != nil { isAll = true }
        if isAll {
            let ranger = SpokenRangeResolver(calendar: calendar, quarterEnd: quarterEnd)
            if let end = ranger.extractEnd(&text, from: now, now: now) {
                rangeStart = end.rangeStart
                rangeEnd = end.until
                rangeUnresolved = end.recognized && end.until == nil && end.count == nil
            }
        }
        var day: Date? = SpokenDateResolver(calendar: calendar).extractDay(&text, now: now)
        var hour: Int?

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let found = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        for match in found.reversed() {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let phrase = String(text[range])
            let hasDay = phrase.range(of: #"(?i)\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\b|\b(?:today|tomorrow|tonight|next|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\b\d{1,2}(?:st|nd|rd|th)\b|\b\d{1,2}/\d{1,2}\b"#, options: .regularExpression) != nil
            let hasTime = phrase.range(of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil
            guard hasDay || hasTime else { continue }
            if hasDay && day == nil { day = calendar.startOfDay(for: date) }
            if hasTime { hour = calendar.component(.hour, from: date) }
            text.replaceSubrange(range, with: " ")
        }

        let stop: Set<String> = ["event", "events", "appointment", "on", "at", "for", "from", "my", "the", "a", "an", "all", "calendar", "of", "to", "in", "and", "it", "that", "this",
                                 "one", "ones", "thing", "things", "stuff", "something", "anything", "everything", "all", "every"]
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0) }
            .filter { !stop.contains($0) && $0.count >= 3 }   // 1-2 letter words match inside too many titles
        return VoiceDeleteRequest(titleWords: words, day: day, hour: hour, isAll: isAll, rangeStart: rangeStart, rangeEnd: rangeEnd, weekdays: weekdays, rangeUnresolved: rangeUnresolved)
    }

    /// Removes the first match from `text`; returns the first non-empty capture.
    private func take(_ pattern: String, from text: inout String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text) else { return nil }
        var capture = ""
        for index in 1..<max(match.numberOfRanges, 1) {
            if let range = Range(match.range(at: index), in: text), capture.isEmpty { capture = String(text[range]) }
        }
        text.replaceSubrange(whole, with: " ")
        return capture
    }

    private func weekdayNumbers(in text: String) -> [Int] {
        let lower = text.lowercased()
        return [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7)]
            .filter { lower.range(of: #"\b"# + $0.0, options: .regularExpression) != nil }.map(\.1)
    }

    private func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

/// Just enough of an event to search -- keeps matching free of EventKit so it
/// can be tested on its own.
struct EventRef: Equatable {
    var id: String
    var title: String
    var start: Date
}

enum VoiceDeleteMatcher {
    /// Events the request could mean, best first: upcoming ones soonest first,
    /// then past ones most recent first. A request with no title words matches
    /// nothing -- "delete Thursday" must never offer a day's worth of events.
    static func matches(_ request: VoiceDeleteRequest, in events: [EventRef], now: Date = .now, calendar: Calendar = .current, fuzzy: Bool = false) -> [EventRef] {
        matchesWithQuality(request, in: events, now: now, calendar: calendar, fuzzy: fuzzy).events
    }

    /// Like `matches`, but says whether the answer is an exact one. With `fuzzy` on and no
    /// exact hit, it falls back to the closest titles for words that were only partly
    /// right or misheard ("dentist" for "Dentist Appointment", "pickle practice" for
    /// "Pickleball Team Practice"). Bulk requests never go fuzzy -- a guess is fine
    /// for picking one event to confirm, not for deleting dozens.
    static func matchesWithQuality(_ request: VoiceDeleteRequest, in events: [EventRef], now: Date = .now, calendar: Calendar = .current, fuzzy: Bool = false) -> (events: [EventRef], exact: Bool) {
        guard !request.titleWords.isEmpty, !request.rangeUnresolved else { return ([], true) }

        // Whole words, and every one of them: "practice" must not match inside
        // another word, and a partial match is never good enough to delete on.
        let startOfToday = calendar.startOfDay(for: now)
        let lower = request.rangeStart.map { calendar.startOfDay(for: $0) } ?? startOfToday
        let upper = request.rangeEnd.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
            ?? calendar.date(byAdding: .day, value: 365, to: lower) ?? lower

        func passesFilters(_ event: EventRef) -> Bool {
            if let day = request.day, !calendar.isDate(event.start, inSameDayAs: day) { return false }
            if let hour = request.hour {
                let eventHour = calendar.component(.hour, from: event.start)
                if abs(eventHour - hour) > 1 { return false }
            }
            if request.isAll {
                guard event.start >= lower, event.start < upper else { return false }
                if !request.weekdays.isEmpty, !request.weekdays.contains(calendar.component(.weekday, from: event.start)) { return false }
            }
            return true
        }

        let hits = events.filter { event in
            let allPresent = request.titleWords.allSatisfy { word in
                event.title.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            }
            return allPresent && passesFilters(event)
        }

        func ordered(_ list: [EventRef]) -> [EventRef] {
            // A bulk request returns everything in order; a single one, the few best.
            if request.isAll { return Array(list.sorted { $0.start < $1.start }.prefix(RepeatRule.maxEvents)) }
            let upcoming = list.filter { $0.start >= startOfToday }.sorted { $0.start < $1.start }
            let past = list.filter { $0.start < startOfToday }.sorted { $0.start > $1.start }
            return Array((upcoming + past).prefix(5))
        }
        if !hits.isEmpty || !fuzzy || request.isAll { return (ordered(hits), true) }

        // Closest titles: score each by how well the spoken words match its words.
        let scored: [(EventRef, Double)] = events.compactMap { event in
            guard passesFilters(event) else { return nil }
            let titleWords = tokens(event.title)
            let sims = request.titleWords.map { word in titleWords.map { similarity(word, $0) }.max() ?? 0 }
            let matched = sims.filter { $0 >= 0.6 }.count
            guard matched >= max(1, (request.titleWords.count + 1) / 2) else { return nil }
            return (event, sims.reduce(0, +) / Double(sims.count))
        }
        guard let best = scored.map(\.1).max() else { return ([], false) }
        // Keep the leaders only, so one good guess isn't buried under weak ones.
        let leaders = scored.filter { $0.1 >= best - 0.2 }.map(\.0)
        return (ordered(leaders), false)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// 1 for the same word, ~0.8 for a prefix or contained stem ("pickle" / "pickleball"),
    /// ~0.6 for one or two letters off (a mishearing), else 0.
    static func similarity(_ spoken: String, _ title: String) -> Double {
        let a = spoken.lowercased(), b = title.lowercased()
        if a == b { return 1 }
        // Simple plurals.
        if a + "s" == b || b + "s" == a { return 0.95 }
        if a.count >= 3, b.count >= 3 {
            if b.hasPrefix(a) || a.hasPrefix(b) { return 0.8 }
            if a.count >= 4, b.contains(a) || (b.count >= 4 && a.contains(b)) { return 0.7 }
        }
        let longest = max(a.count, b.count)
        guard longest >= 4 else { return 0 }
        let distance = editDistance(Array(a), Array(b))
        if distance <= 1 { return 0.65 }
        if distance <= 2, longest >= 7 { return 0.6 }
        return 0
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
