import Foundation

/// EventKit has no custom Boolean fields. A reserved notes line travels with
/// the event across iCloud and can also be written by Shivan's calendar bridge.
/// The editor keeps this metadata separate from the user's visible notes.
enum EventImportance {
    static let marker = "[CalendarApp:important=true]"

    static func isImportant(notes: String?) -> Bool {
        lines(of: notes).contains(marker)
    }

    /// Display only: never change the stored title or event identity.
    static func displayTitle(_ title: String, notes: String?) -> String {
        isImportant(notes: notes) ? "★ \(title)" : title
    }

    static func displayNotes(_ notes: String?) -> String {
        guard let notes else { return "" }
        guard isImportant(notes: notes) || !requestMarkers(notes).isEmpty else { return notes }
        var kept = notes.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
        kept.removeAll { let line = $0.trimmingCharacters(in: .whitespaces); return line == marker || isRequestMarker(line) }
        return kept.joined(separator: "\n")
    }

    static func notes(_ notes: String?, settingImportant important: Bool, preservingRequestsFrom original: String? = nil) -> String? {
        let visible = displayNotes(notes)
        var parts = visible.isEmpty ? [] : [visible]
        parts += Set(requestMarkers(notes) + requestMarkers(original)).sorted()
        if important { parts.append(marker) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// One rule for every Unicode line break, so a marker that is detected is
    /// always a marker that is removed.
    private static func lines(of notes: String?) -> [String] {
        (notes ?? "").replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func requestMarkers(_ notes: String?) -> [String] {
        lines(of: notes).filter(isRequestMarker)
    }

    private static func isRequestMarker(_ line: String) -> Bool {
        let prefix = "[Shivan:request="
        guard line.hasPrefix(prefix), line.hasSuffix("]") else { return false }
        return UUID(uuidString: String(line.dropFirst(prefix.count).dropLast())) != nil
    }

    static func fireDate(start: Date, now: Date) -> Date? {
        let fire = start.addingTimeInterval(-1800)
        return fire > now ? fire : nil
    }
}
