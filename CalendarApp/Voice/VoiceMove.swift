import Foundation

/// "Move this event one day forward", "push the dentist 2 months back",
/// "move the team lunch to Friday at 1": shifting an event that already exists.
/// Several at once works too: "move the dentist and the haircut back one day",
/// "move A forward a day and B back two days" -- those come in `parts`.
struct VoiceMoveRequest: Equatable {
    /// Which event: title words (and maybe a day/time). Empty with `useSelected`
    /// means "this event" -- the one open in the calendar.
    var target: VoiceDeleteRequest
    var useSelected: Bool
    /// A relative shift: `amount` of `unit`, forward (+1) or back (-1).
    var amount: Int?
    var unit: Calendar.Component?
    var direction = 1
    /// An absolute move: what was said after "to" ("Friday at 3 pm").
    var destination: String?
    /// "from the 21st to the 20th": the day the event is on now. It's resolved against
    /// the month showing in the calendar, so the month never has to be said.
    var source: String?
    /// When the sentence names several events, one request each. The view uses
    /// these only if the sentence read as a single event matches nothing (so a
    /// title like "Rock and Roll" isn't torn apart).
    var parts: [VoiceMoveRequest] = []

    var isRelative: Bool { amount != nil && unit != nil }

    /// The event's new start, for a relative shift.
    func shifted(_ date: Date, calendar: Calendar = .current) -> Date? {
        guard let amount, let unit else { return nil }
        return calendar.date(byAdding: unit, value: amount * direction, to: date)
    }
}

/// What one clause of a move sentence asks for, before inheriting from its neighbours.
private struct MoveChange {
    var verb: String
    var subject: String
    var amount: Int?
    var unit: Calendar.Component?
    var directionWord: Int?
    var destination: String?
    var source: String?

    var hasChange: Bool { (amount != nil && unit != nil) || destination != nil }
}

extension VoiceIntentClassifier {
    private static let moveVerbs = "move|push|shift|postpone|reschedule|delay|bump|pull|bring|slide|nudge|advance|change"

    /// A move request, or nil if the sentence isn't one (so "move it to Friday" can
    /// still be a correction to a draft, and unrelated sentences fall through).
    func moveRequest(from spoken: String, now: Date = .now) -> VoiceMoveRequest? {
        var text = spoken.lowercased()
            .replacingOccurrences(of: #"[.!?]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Polite lead-ins ("can you move ...", "I want to push ...").
        text = text.replacingOccurrences(of: #"^(?:(?:hey |ok |okay )?(?:can|could|would) you (?:please )?|please |i want to |i need to |i'd like to |let'?s |go ahead and )"#, with: "", options: .regularExpression)
        // Just a direction and an amount ("back one day", "one day forward") means this event.
        if text.range(of: #"^(?:back|forward|forwards|ahead|later|earlier)\b.*\b(?:minute|min|hour|hr|day|week|month|year)s?$|^(?:\d+|an?|one|two|three|four|five|six|seven|eight|nine|ten|a couple of|a few)\s+(?:minute|min|hour|hr|day|week|month|year)s?\s+(?:back|forward|forwards|ahead|later|earlier)$"#, options: .regularExpression) != nil {
            text = "move it " + text
        }
        guard let head = firstMatch(#"^(?:please\s+)?(\#(Self.moveVerbs))\s+(.+)$"#, in: text) else { return nil }
        let verb = head[1]
        let rest = head[2]

        // The whole sentence as one event first ("Rock and Roll" is one title).
        guard let whole = change(verb: verb, clause: rest.replacingOccurrences(of: ",", with: " "), now: now), whole.hasChange else { return nil }
        var request = finish(whole, now: now)

        let clauses = rest.components(separatedBy: #"\s*(?:,|&|\band\b|\bplus\b|\bthen\b|\balso\b)\s*"#)
        if clauses.count >= 2 {
            var changes: [MoveChange] = clauses.compactMap { clause in
                var verb = verb
                var body = clause
                if let g = firstMatch(#"^(\#(Self.moveVerbs))\s+(.+)$"#, in: clause) { verb = g[1]; body = g[2] }
                return change(verb: verb, clause: body, now: now)
            }
            // A clause with no amount ("the dentist" in "the dentist and the haircut back
            // a day") takes the change of the nearest clause that has one.
            for i in changes.indices where !changes[i].hasChange {
                let donor = changes[(i + 1)...].first(where: \.hasChange) ?? changes[..<i].last(where: \.hasChange)
                if let donor {
                    changes[i].amount = donor.amount; changes[i].unit = donor.unit
                    changes[i].directionWord = donor.directionWord; changes[i].destination = donor.destination
                    changes[i].source = changes[i].source ?? donor.source
                }
            }
            if changes.count >= 2, changes.allSatisfy(\.hasChange) { request.parts = changes.map { finish($0, now: now) } }
        }
        return request
    }

    private func finish(_ c: MoveChange, now: Date) -> VoiceMoveRequest {
        var direction = c.directionWord ?? 0
        if direction == 0 { direction = ["pull", "bring"].contains(c.verb) ? -1 : 1 }
        let target = request(from: c.subject, now: now)
        return VoiceMoveRequest(
            target: target, useSelected: target.titleWords.isEmpty && target.day == nil && c.source == nil,
            amount: c.amount, unit: c.unit, direction: direction, destination: c.destination, source: c.source
        )
    }

    /// Reads one clause: the shift ("2 days later"), the direction, a destination
    /// ("to Friday at 3"), and what's left is the subject.
    private func change(verb: String, clause: String, now: Date) -> MoveChange? {
        var rest = " " + clause + " "
        let numbers = "\\d+|a couple of|a few|an?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|fifteen|twenty|thirty"
        var change = MoveChange(verb: verb, subject: "")

        if rest.range(of: #"\bhalf an hour\b"#, options: .regularExpression) != nil {
            rest = rest.replacingOccurrences(of: #"\bhalf an hour\b"#, with: " ", options: .regularExpression)
            change.amount = 30; change.unit = .minute
        } else if let g = firstMatch(#"\b(?:by\s+)?(\#(numbers))\s+(minute|min|hour|hr|day|week|month|year)s?\b"#, in: rest),
                  let n = Int(g[1]) ?? Self.numberWords[g[1]] {
            rest = rest.replacingOccurrences(of: g[0], with: " ")
            change.amount = n
            switch g[2] {
            case "minute", "min": change.unit = .minute
            case "hour", "hr": change.unit = .hour
            case "day": change.unit = .day
            case "week": change.unit = .weekOfYear
            case "month": change.unit = .month
            default: change.unit = .year
            }
        }

        if let g = firstMatch(#"\b(later|forward|forwards|ahead|out|further|earlier|sooner|up|back|backward|backwards)\b"#, in: rest) {
            rest = rest.replacingOccurrences(of: g[0], with: " ")
            switch g[1] {
            case "earlier", "sooner", "up": change.directionWord = -1
            case "back", "backward", "backwards": change.directionWord = ["push", "postpone", "delay", "bump"].contains(verb) ? 1 : -1
            case "forward", "forwards", "ahead": change.directionWord = ["pull", "bring"].contains(verb) ? -1 : 1
            default: change.directionWord = 1
            }
        }

        if change.amount == nil, let g = firstMatch(#"\bfrom\s+(.+?)\s+(?:to|until|onto)\s+(.+?)\s*$"#, in: rest) {
            change.source = g[1]
            change.destination = g[2]
            rest = rest.replacingOccurrences(of: g[0], with: " ")
        } else if change.amount == nil, let split = rest.range(of: #"\s(?:to|until|onto)\s+(?!.*\s(?:to|until|onto)\s)"#, options: .regularExpression) {
            let destination = String(rest[split.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !destination.isEmpty { change.destination = destination }
            rest = String(rest[..<split.lowerBound])
        }

        // Who: "this event"/"it" means the open one; otherwise name it.
        change.subject = rest
            .replacingOccurrences(of: #"\b(?:this|that|the|my)\s+(?:event|appointment|meeting|one)\b|\b(?:it|this|that)\b"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return change
    }

    private static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "a couple of": 2, "a few": 3,
    ]

    private func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}

extension String {
    /// Splits on a regular expression, dropping empty pieces.
    func components(separatedBy pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [self] }
        var pieces: [String] = []
        var last = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let range = Range(match.range, in: self) else { continue }
            pieces.append(String(self[last..<range.lowerBound]))
            last = range.upperBound
        }
        pieces.append(String(self[last...]))
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
