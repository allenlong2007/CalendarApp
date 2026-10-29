import Foundation

/// EventKit has no custom Boolean fields. A reserved notes line travels with
/// the event across iCloud and can also be written by Shivan's calendar bridge.
/// The editor keeps this metadata separate from the user's visible notes.
enum EventImportance {
    static let marker = "[CalendarApp:important=true]"

    static func isImportant(notes: String?) -> Bool {
        notes?.components(separatedBy: .newlines).contains(marker) == true
    }

    static func displayNotes(_ notes: String?) -> String {
        guard let notes else { return "" }
        guard isImportant(notes: notes) || !requestMarkers(notes).isEmpty else { return notes }
        var lines = notes.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeAll { $0 == marker || isRequestMarker($0) }
        return lines.joined(separator: "\n")
    }

    static func notes(_ notes: String?, settingImportant important: Bool, preservingRequestsFrom original: String? = nil) -> String? {
        let visible = displayNotes(notes)
        var parts = visible.isEmpty ? [] : [visible]
        parts += Set(requestMarkers(notes) + requestMarkers(original)).sorted()
        if important { parts.append(marker) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func requestMarkers(_ notes: String?) -> [String] {
        (notes ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n").map(String.init).filter(isRequestMarker)
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
