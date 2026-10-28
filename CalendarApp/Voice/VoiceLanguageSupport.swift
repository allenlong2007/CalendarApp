import Foundation

/// Partial hypotheses replace each other; completed recognition segments remain
/// when Apple's recognizer starts another segment during a long instruction.
struct SpeechTranscriptBuffer {
    private var segments: [String] = []
    private var partial = ""
    var text: String { (segments + [partial]).filter { !$0.isEmpty }.joined(separator: " ") }
    mutating func update(_ text: String) { partial = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    mutating func commitSegment() {
        if !partial.isEmpty { segments.append(partial) }
        partial = ""
    }
}

enum VoiceVocabulary {
    /// Only correct the complete known place phrase, never an ordinary "mirror".
    static func correctPlaces(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?i)\b(?:mirror|mere|mure|muir)\s+tennis\s+courts?\b"#,
            with: "Muir tennis courts", options: .regularExpression)
    }

    static func hints(calendars: [String], places: [String]) -> [String] {
        let known = ["Muir tennis courts", "Muir", "Warren tennis courts", "RIMAC", "UCSD", "SpeakUp", "pickleball"]
        var seen: Set<String> = []
        return (known + calendars + places).compactMap { text in
            let phrase = correctPlaces(text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, phrase.count <= 100, seen.insert(phrase.lowercased()).inserted else { return nil }
            return phrase
        }.prefix(100).map { $0 }
    }
}
