import Foundation
import SwiftData

/// Works around a confirmed EventKit/Mac Catalyst limitation: only the
/// literal master instance of a recurring event reliably returns
/// `.location`/`.structuredLocation` when fetched -- every expanded
/// occurrence (the 2nd, 3rd, ... of a weekly class, say) reads back
/// `location == nil`, even though it's correctly set and shows up fine in
/// Apple's own Calendar app. Verified directly: setting the location in the
/// very same save that creates a brand-new master still doesn't fix later
/// occurrences, so this isn't a writing-order problem to code around --
/// it's a read-side quirk of this bridge. Mirroring the location locally
/// (same shape as EventCompletionStatus/EventReminderPreference) lets the
/// app's own UI show it reliably regardless of which occurrence EventKit
/// handed back.
///
/// Keyed by plain event title rather than calendarItemExternalIdentifier --
/// since location is meant to be shared across every occurrence of a title
/// (e.g. every "MATH-018 Lecture" regardless of which weekday), and title
/// has been reliable across occurrences throughout testing, whereas the
/// identifiers' reliability for this specific symptom wasn't independently
/// re-verified.
@Model
final class EventLocationOverride {
    var id: UUID = UUID()
    var titleKey: String = ""
    var locationText: String = ""
    var latitude: Double?
    var longitude: Double?

    init(titleKey: String, locationText: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.titleKey = titleKey
        self.locationText = locationText
        self.latitude = latitude
        self.longitude = longitude
    }
}
