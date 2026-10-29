import Foundation

/// A deliberately small, typed contract for Shivan's approved local commands.
/// Explicit offsets avoid interpreting cloud computer dates in the wrong zone.
struct CalendarBridgeRequest: Decodable {
    enum Action: String, Decodable { case calendars, events, create, update, delete }
    var action: Action
    var title: String?
    var start: String?
    var end: String?
    var calendarID: String?
    var eventID: String?
    var requestID: UUID?
    var location: String?
    var notes: String?
    var important: Bool?
    var allDay: Bool?

    var startDate: Date? { start.flatMap { ISO8601DateFormatter().date(from: $0) } }
    var endDate: Date? { end.flatMap { ISO8601DateFormatter().date(from: $0) } }

    func validate() throws {
        if action == .calendars { return }
        if action == .delete {
            guard let eventID, !eventID.isEmpty else { throw Failure.invalid("An eventID is required.") }
            return
        }
        guard let startDate, let endDate, endDate > startDate,
              endDate.timeIntervalSince(startDate) <= 366 * 86400 else {
            throw Failure.invalid("Provide a start and later end as ISO8601 timestamps with timezone offsets (range at most 366 days).")
        }
        if action == .events { return }
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalid("A nonempty title is required.")
        }
        if action == .create, requestID == nil {
            throw Failure.invalid("A stable UUID requestID is required for deduplication.")
        }
        if action == .update, eventID?.isEmpty != false {
            throw Failure.invalid("An eventID is required to update an event.")
        }
    }

    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { message } else { "Invalid request." } }
    }
}
