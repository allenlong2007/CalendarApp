import Foundation
import SwiftData

/// EventKit has no "completed" concept, so it's tracked here, keyed to a real
/// EKEvent. `eventIdentifier` can change if the event moves between calendars,
/// so `calendarItemExternalIdentifier` (Apple's recommended stable
/// cross-store key) is the primary lookup. Both identifiers are shared by
/// every occurrence of a recurring event, though, so `lastKnownStartDate`
/// isn't just cosmetic -- it's required alongside the identifier to pin a
/// row to one specific occurrence (see EventCompletionAccess.row); without
/// it, completing one lecture would complete the whole series.
///
/// There is no schema-level uniqueness constraint (SwiftData's CloudKit
/// mirroring doesn't support @Attribute(.unique)) -- callers must fetch-then-
/// upsert by calendarItemExternalIdentifier before inserting a new row.
@Model
final class EventCompletionStatus {
    var id: UUID = UUID()
    var eventIdentifier: String = ""
    var calendarItemExternalIdentifier: String?
    var completed: Bool = false
    var lastKnownStartDate: Date?
    var lastKnownTitle: String?

    init(
        eventIdentifier: String,
        calendarItemExternalIdentifier: String? = nil,
        completed: Bool = false,
        lastKnownStartDate: Date? = nil,
        lastKnownTitle: String? = nil
    ) {
        self.eventIdentifier = eventIdentifier
        self.calendarItemExternalIdentifier = calendarItemExternalIdentifier
        self.completed = completed
        self.lastKnownStartDate = lastKnownStartDate
        self.lastKnownTitle = lastKnownTitle
    }
}
