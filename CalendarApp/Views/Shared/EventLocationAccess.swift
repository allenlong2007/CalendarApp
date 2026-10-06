import CoreLocation
import EventKit
import SwiftData

/// Resolves an event's display location, falling back to the app-local
/// EventLocationOverride when EventKit's own `.location` is empty (see
/// EventLocationOverride's doc comment for why that happens for most
/// occurrences of a recurring event).
enum EventLocationAccess {
    static func displayLocation(for event: EKEvent, in rows: [EventLocationOverride]) -> (text: String, coordinate: CLLocationCoordinate2D?)? {
        if let text = event.location, !text.isEmpty {
            return (text, event.structuredLocation?.geoLocation?.coordinate)
        }
        guard let title = event.title, let row = rows.first(where: { $0.titleKey == title }) else { return nil }
        let coordinate: CLLocationCoordinate2D? = {
            guard let lat = row.latitude, let lon = row.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }()
        return (row.locationText, coordinate)
    }

    /// Overrides that should exist but don't: for every title with no
    /// override row yet, the location EventKit itself returns on some event
    /// of that title (in practice the series' first event -- the only
    /// occurrence that reliably reads one back). Override rows live in this
    /// device's own store and don't sync, so this is how a second device
    /// (the phone) learns the locations the first one already has. It only
    /// ever fills gaps, never overwrites -- a location the user edited here
    /// must win over whatever EventKit's master still says.
    static func missingOverrides(
        from events: [EKEvent],
        existingTitles: Set<String>
    ) -> [(title: String, text: String, coordinate: CLLocationCoordinate2D?)] {
        var seen = existingTitles
        var result: [(title: String, text: String, coordinate: CLLocationCoordinate2D?)] = []
        for event in events {
            guard event.calendar?.allowsContentModifications == true,
                  let title = event.title, !seen.contains(title),
                  let text = event.location, !text.isEmpty else { continue }
            seen.insert(title)
            result.append((title, text, event.structuredLocation?.geoLocation?.coordinate))
        }
        return result
    }

    static func mirrorMissing(from events: [EKEvent], context: ModelContext) {
        // Fetched from the context, not a view's @Query snapshot, which can
        // lag a just-inserted row and let two back-to-back calls (launch
        // task + the foreground refresh's change token) insert duplicates.
        let existing = (try? context.fetch(FetchDescriptor<EventLocationOverride>())) ?? []
        let missing = missingOverrides(from: events, existingTitles: Set(existing.map(\.titleKey)))
        for item in missing {
            context.insert(EventLocationOverride(
                titleKey: item.title,
                locationText: item.text,
                latitude: item.coordinate?.latitude,
                longitude: item.coordinate?.longitude
            ))
        }
    }

    static func setLocation(_ text: String?, coordinate: CLLocationCoordinate2D?, title: String, rows: [EventLocationOverride], context: ModelContext) {
        let existing = rows.first { $0.titleKey == title }
        guard let text, !text.isEmpty else {
            if let existing { context.delete(existing) }
            return
        }
        if let existing {
            existing.locationText = text
            existing.latitude = coordinate?.latitude
            existing.longitude = coordinate?.longitude
        } else {
            context.insert(EventLocationOverride(titleKey: title, locationText: text, latitude: coordinate?.latitude, longitude: coordinate?.longitude))
        }
    }
}
