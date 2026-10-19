import Foundation

/// What a spoken sentence is asking for, decided before any event details are
/// read out of it. Confirming and cancelling are intents too, so the whole flow
/// can be done hands-free ("delete pickleball practice Thursday" ... "yes").
enum VoiceIntent: Equatable {
    case delete(VoiceDeleteRequest)
    case confirm
    case cancel
    /// Anything else: details of an event to add, or a correction to the draft.
    case describeEvent
}

struct VoiceDeleteRequest: Equatable {
    /// Words from the event's title, lowercased ("pickleball", "practice").
    var titleWords: [String]
    var day: Date?
    /// Hour of day (0-23) if a time was spoken.
    var hour: Int?
}

struct VoiceIntentClassifier {
    var calendar: Calendar = .current

    func classify(_ spoken: String) -> VoiceIntent {
        let text = spoken.lowercased()
            .replacingOccurrences(of: #"[.!?,]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if matches(#"^(?:yes|yeah|yep|yup|sure|confirm|do it|go ahead|looks good|that'?s right|correct|add it|save it|delete it|delete that|remove it|remove that|ok|okay)(?: please)?$"#, text) { return .confirm }
        if matches(#"^(?:no|nope|cancel|never ?mind|stop|don'?t|do not|forget it|keep it)(?: it| that)?$"#, text) { return .cancel }

        if let rest = capture(#"^(?:please\s+)?(?:delete|remove|cancel|erase|get rid of)\s+(?:the\s+|my\s+|that\s+)?(.+)$"#, in: text) {
            return .delete(request(from: rest))
        }
        return .describeEvent
    }

    private func request(from rest: String) -> VoiceDeleteRequest {
        var text = rest
        var day: Date?
        var hour: Int?

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let found = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        for match in found.reversed() {
            guard let date = match.date, let range = Range(match.range, in: text) else { continue }
            let phrase = String(text[range])
            let hasDay = phrase.range(of: #"(?i)\b(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\b|\b(?:today|tomorrow|tonight|next|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\b\d{1,2}(?:st|nd|rd|th)\b|\b\d{1,2}/\d{1,2}\b"#, options: .regularExpression) != nil
            let hasTime = phrase.range(of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil
            guard hasDay || hasTime else { continue }
            if hasDay { day = calendar.startOfDay(for: date) }
            if hasTime { hour = calendar.component(.hour, from: date) }
            text.replaceSubrange(range, with: " ")
        }

        let stop: Set<String> = ["event", "events", "appointment", "on", "at", "for", "from", "my", "the", "a", "an", "all", "calendar", "of", "to", "in", "and", "it", "that", "this"]
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0) }
            .filter { !stop.contains($0) }
        return VoiceDeleteRequest(titleWords: words, day: day, hour: hour)
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
    static func matches(_ request: VoiceDeleteRequest, in events: [EventRef], now: Date = .now, calendar: Calendar = .current) -> [EventRef] {
        guard !request.titleWords.isEmpty else { return [] }

        let hits = events.filter { event in
            let title = event.title.lowercased()
            let present = request.titleWords.filter { title.contains($0) }.count
            let enough = present == request.titleWords.count
                || (request.titleWords.count >= 3 && Double(present) / Double(request.titleWords.count) >= 0.67)
            guard enough else { return false }
            if let day = request.day, !calendar.isDate(event.start, inSameDayAs: day) { return false }
            if let hour = request.hour {
                let eventHour = calendar.component(.hour, from: event.start)
                if abs(eventHour - hour) > 1 { return false }
            }
            return true
        }

        let startOfToday = calendar.startOfDay(for: now)
        let upcoming = hits.filter { $0.start >= startOfToday }.sorted { $0.start < $1.start }
        let past = hits.filter { $0.start < startOfToday }.sorted { $0.start > $1.start }
        return Array((upcoming + past).prefix(5))
    }
}
