import Foundation
import SwiftData

/// A practice/scratch event in the Planner's imaginary week -- keyed by weekday,
/// not a real date, and never touches EventKit. Mirrors the web app's
/// scheduler-events model (date stored as a weekday index '0'-'6').
///
/// All properties have defaults, per SwiftData's CloudKit-mirroring constraints.
@Model
final class PlannerEvent {
    var id: UUID = UUID()
    /// 0 = Sunday ... 6 = Saturday.
    var weekday: Int = 0
    var title: String = ""
    var isAllDay: Bool = false
    /// Minutes from midnight -- simpler than Date for a slot with no real date.
    var startMinutes: Int?
    var endMinutes: Int?
    /// The EKCalendar.calendarIdentifier this practice event previews as, if any.
    var categoryIdentifier: String?
    var notes: String?
    var createdAt: Date = Date.now

    init(
        weekday: Int,
        title: String,
        isAllDay: Bool = false,
        startMinutes: Int? = nil,
        endMinutes: Int? = nil,
        categoryIdentifier: String? = nil,
        notes: String? = nil
    ) {
        self.weekday = weekday
        self.title = title
        self.isAllDay = isAllDay
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.categoryIdentifier = categoryIdentifier
        self.notes = notes
    }
}
