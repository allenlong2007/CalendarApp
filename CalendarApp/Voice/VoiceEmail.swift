import Foundation

struct VoiceEmailRequest: Equatable {
    var sender: String?
    var topic: String?
    var subjectOnly = false

    var searchQuery: String? {
        func quoted(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\\", with: " ").replacingOccurrences(of: "\"", with: " ") + "\""
        }
        let parts = [sender.map { "from:" + quoted($0) }, topic.map { (subjectOnly ? "subject:" : "") + quoted($0) }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func parse(_ spoken: String) -> Self? {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"(?i)^(?:please\s+)?(?:add|import|schedule|create|put)\b"#, options: .regularExpression) != nil,
              let emailRange = text.range(of: #"(?i)\b(?:e-?mail|message)\b"#, options: .regularExpression) else { return nil }
        var rest = String(text[emailRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        rest = rest.replacingOccurrences(of: #"(?i)\s+(?:onto|to|on) (?:my |the )?calendar[.!?]?$"#, with: "", options: .regularExpression)
        var request = Self()
        if rest.lowercased().hasPrefix("from ") {
            rest = String(rest.dropFirst(5))
            if let split = rest.range(of: #"(?i)\s+(?:about|regarding|with subject|titled)\s+"#, options: .regularExpression) {
                request.sender = String(rest[..<split.lowerBound])
                request.topic = String(rest[split.upperBound...])
            } else { request.sender = rest }
        } else {
            request.subjectOnly = rest.range(of: #"(?i)^(?:with (?:the )?subject|titled)\b"#, options: .regularExpression) != nil
            rest = rest.replacingOccurrences(of: #"(?i)^(?:about|regarding|with (?:the )?subject|titled)\s+"#, with: "", options: .regularExpression)
            if !rest.isEmpty { request.topic = rest }
        }
        if request.sender == nil, request.topic == nil {
            var prefix = String(text[..<emailRange.lowerBound])
            prefix = prefix.replacingOccurrences(of: #"(?i)\b(?:please|add|import|schedule|create|put|the|an?|event|from|that|this|my|onto|to|on|calendar)\b"#, with: " ", options: .regularExpression)
            prefix = prefix.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !prefix.isEmpty { request.topic = prefix }
        }
        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let result = value.replacingOccurrences(of: #"(?i)^(?:my|the|an?)\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }
        request.sender = clean(request.sender)
        request.topic = clean(request.topic)
        return request
    }

    static func selectionIndex(from text: String) -> Int? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = ["first", "second", "third", "fourth", "fifth"]
        for (index, word) in words.enumerated() {
            if normalized.range(of: "^(?:(?:use|choose|pick|select) )?(?:the )?(?:\(word)|\(index + 1))(?: (?:one|email|message|date))?$", options: .regularExpression) != nil { return index }
        }
        return nil
    }
}

/// Email content is data: it is never passed to the voice intent classifier.
/// A received timestamp is never used as an appointment date.
enum VoiceEmailDrafts {
    static func extract(from message: GmailMessageDetail) -> [EventDraft] {
        var body = message.bodyText.components(separatedBy: "\nOn ").first ?? message.bodyText
        let originalLines = body.components(separatedBy: .newlines)
        if originalLines.contains(where: { $0.range(of: #"(?i)^\s*(?:from|to|subject|sent):"#, options: .regularExpression) != nil }) {
            var readingHeaders = true
            body = originalLines.filter { line in
                guard readingHeaders else { return true }
                if line.trimmingCharacters(in: .whitespaces).isEmpty { readingHeaders = false; return false }
                if line.range(of: #"(?i)^\s*(?:from|to|subject|sent|date|cc|bcc):"#, options: .regularExpression) != nil { return false }
                readingHeaders = false
                return true
            }.joined(separator: "\n")
        }
        body = body.replacingOccurrences(of: #"(?i)\n\s*Time:\s*"#, with: " at ", options: .regularExpression)
        let lines = body.components(separatedBy: .newlines)
        let labelled = lines.filter { $0.range(of: #"(?i)\b(?:appointment|meeting|reservation|departure|when|date|starts?)\s*:?"#, options: .regularExpression) != nil }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        func matches(in text: String) -> [(Date, Bool, TimeInterval)] {
            (detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []).compactMap { match in
                guard let date = match.date, let range = Range(match.range, in: text) else { return nil }
                let phrase = String(text[range])
                // A bare time in a signature or email header is not an event day.
                guard phrase.range(of: #"(?i)\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|mon|tue|wed|thu|fri|sat|sun|today|tomorrow)[a-z]*\b|\d{1,4}[-/]\d{1,2}[-/]\d{1,4}"#, options: .regularExpression) != nil else { return nil }
                let timeKnown = phrase.range(of: #"(?i)\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b|\b(?:noon|midnight)\b"#, options: .regularExpression) != nil
                let relative = phrase.range(of: #"(?i)\b(?:today|tomorrow|tonight|next)\b"#, options: .regularExpression) != nil
                if relative {
                    guard let received = message.internalDate else { return nil }
                    let calendar = Calendar.current
                    let receivedDay = calendar.startOfDay(for: received)
                    let day: Date?
                    if phrase.localizedCaseInsensitiveContains("day after tomorrow") {
                        day = calendar.date(byAdding: .day, value: 2, to: receivedDay)
                    } else if phrase.localizedCaseInsensitiveContains("tomorrow") {
                        day = calendar.date(byAdding: .day, value: 1, to: receivedDay)
                    } else if phrase.range(of: #"(?i)\b(?:today|tonight)\b"#, options: .regularExpression) != nil {
                        day = receivedDay
                    } else {
                        var relativePhrase = phrase.lowercased()
                        day = SpokenDateResolver().extractDay(&relativePhrase, now: received)
                    }
                    guard let day else { return nil }
                    let resolved = timeKnown ? calendar.date(bySettingHour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date), second: 0, of: day) : day
                    return resolved.map { ($0, timeKnown, match.duration) }
                }
                return (date, timeKnown, match.duration)
            }
        }
        let prioritized = matches(in: labelled.joined(separator: "\n"))
        let dates = prioritized.isEmpty ? matches(in: String((message.subject + "\n" + body).prefix(30_000))) : prioritized
        let location = lines.first { $0.range(of: #"(?i)^\s*(?:location|where|venue):"#, options: .regularExpression) != nil }?
            .replacingOccurrences(of: #"(?i)^\s*(?:location|where|venue):\s*"#, with: "", options: .regularExpression)
        var base = EventDraft()
        base.title = message.subject
        base.location = location
        base.notes = "From email: \(message.from)\nSubject: \(message.subject)\n" + (message.accountEmail.map { "Inbox: \($0)\n" } ?? "") + "\n\(String(body.prefix(4000)))"
        var seen = Set<Date>()
        let unique = dates.filter { seen.insert($0.0).inserted }
        guard !unique.isEmpty else { return [base] }
        return unique.prefix(5).map { date, timeKnown, duration in
            var draft = base
            draft.start = date
            draft.timeKnown = timeKnown
            if timeKnown { draft.end = date.addingTimeInterval(duration > 0 ? duration : 3600) }
            return draft
        }
    }
}

enum VoiceEmailLookup {
    @MainActor
    static func findAcrossInboxes(query: String, oauth: GoogleOAuthService) async throws -> (messages: [GmailMessageDetail], failedAccounts: [String]) {
        var messages: [GmailMessageDetail] = []
        var failedAccounts: [String] = []
        let searchedAccounts = oauth.accounts
        for account in searchedAccounts {
            try Task.checkCancellation()
            do {
                let token = try await oauth.validAccessToken(account: account)
                var found = try await find(query: query, accessToken: token)
                for index in found.indices { found[index].accountEmail = account }
                messages.append(contentsOf: found)
            } catch is CancellationError { throw CancellationError() }
            catch { failedAccounts.append(account) }
        }
        guard oauth.accounts == searchedAccounts else { throw GmailError.notSignedIn }
        return (Array(messages.sorted { ($0.internalDate ?? .distantPast) > ($1.internalDate ?? .distantPast) }.prefix(5)), failedAccounts)
    }

    static func find(query: String, accessToken: String) async throws -> [GmailMessageDetail] {
        let ids = try await GmailAPIClient.searchMessages(query: query, accessToken: accessToken, maxResults: 5)
        var messages: [GmailMessageDetail] = []
        for id in ids {
            try Task.checkCancellation()
            messages.append(try await GmailAPIClient.fetchMessage(id: id, accessToken: accessToken))
        }
        return messages.sorted { ($0.internalDate ?? .distantPast) > ($1.internalDate ?? .distantPast) }
    }
}
