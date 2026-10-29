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
        guard isImportant(notes: notes) else { return notes }
        var lines = notes.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeAll { $0 == marker }
        return lines.joined(separator: "\n")
    }

    static func notes(_ notes: String?, settingImportant important: Bool) -> String? {
        let visible = displayNotes(notes)
        if important { return visible.isEmpty ? marker : visible + "\n" + marker }
        return visible.isEmpty ? nil : visible
    }

    static func fireDate(start: Date, now: Date) -> Date? {
        let fire = start.addingTimeInterval(-1800)
        return fire > now ? fire : nil
    }
}
