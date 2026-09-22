import Foundation

struct GmailEventCandidate: Identifiable {
    let id: String
    let subject: String
    let from: String
    var detectedDate: Date?
    let sourceSnippet: String
}

/// Heuristic, not ML: search for email that reads like a reservation/
/// confirmation/invitation, then pull the most plausible future date out of
/// the body with Foundation's own date detector. Every result is reviewed
/// and explicitly picked by the user before anything is added -- this never
/// creates events on its own.
enum GmailEventExtractor {
    static let searchQuery = "(reservation OR confirmed OR confirmation OR itinerary OR booking OR appointment OR invitation) newer_than:30d"

    static func extractCandidates(accessToken: String) async throws -> [GmailEventCandidate] {
        let ids = try await GmailAPIClient.searchMessages(query: searchQuery, accessToken: accessToken)
        var candidates: [GmailEventCandidate] = []
        for id in ids {
            guard let detail = try? await GmailAPIClient.fetchMessage(id: id, accessToken: accessToken) else { continue }
            let date = detectDate(in: detail.bodyText, fallback: detail.internalDate)
            candidates.append(GmailEventCandidate(
                id: detail.id,
                subject: detail.subject,
                from: detail.from,
                detectedDate: date,
                sourceSnippet: detail.snippet
            ))
        }
        return candidates
    }

    private static func detectDate(in text: String, fallback: Date?) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return fallback
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)
        // Prefer a future-looking date (a reservation's own date) over one
        // that's merely the "today" the email happened to be sent.
        let future = matches.compactMap(\.date).first { $0 > .now.addingTimeInterval(-86400) }
        return future ?? matches.first?.date ?? fallback
    }
}
