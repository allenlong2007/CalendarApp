import Foundation
import SwiftData

/// A reusable "quick add" preset -- schedule the same activity again with one tap.
@Model
final class EventTemplate: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var isAllDay: Bool = false
    var durationMinutes: Int = 60
    /// Minutes since midnight -- the template's own remembered time of day
    /// (e.g. 540 = 9:00 AM), applied to whatever date it's quick-added to.
    /// Optional only for templates saved before this field existed; new
    /// ones always get one (see EventTemplateEditorView/EventEditorView).
    var preferredStartMinutes: Int?
    var categoryIdentifier: String?
    var savedAddressID: UUID?
    var notes: String?
    var reminderMinutesBefore: Int?

    init(
        title: String,
        isAllDay: Bool = false,
        durationMinutes: Int = 60,
        preferredStartMinutes: Int? = nil,
        categoryIdentifier: String? = nil,
        savedAddressID: UUID? = nil,
        notes: String? = nil,
        reminderMinutesBefore: Int? = nil
    ) {
        self.title = title
        self.isAllDay = isAllDay
        self.durationMinutes = durationMinutes
        self.preferredStartMinutes = preferredStartMinutes
        self.categoryIdentifier = categoryIdentifier
        self.savedAddressID = savedAddressID
        self.notes = notes
        self.reminderMinutesBefore = reminderMinutesBefore
    }
}
