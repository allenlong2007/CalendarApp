import Foundation
import SwiftData

/// A reusable "quick add" preset -- schedule the same activity again with one tap.
@Model
final class EventTemplate: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var isAllDay: Bool = false
    var durationMinutes: Int = 60
    var categoryIdentifier: String?
    var savedAddressID: UUID?
    var notes: String?
    var reminderMinutesBefore: Int?

    init(
        title: String,
        isAllDay: Bool = false,
        durationMinutes: Int = 60,
        categoryIdentifier: String? = nil,
        savedAddressID: UUID? = nil,
        notes: String? = nil,
        reminderMinutesBefore: Int? = nil
    ) {
        self.title = title
        self.isAllDay = isAllDay
        self.durationMinutes = durationMinutes
        self.categoryIdentifier = categoryIdentifier
        self.savedAddressID = savedAddressID
        self.notes = notes
        self.reminderMinutesBefore = reminderMinutesBefore
    }
}
