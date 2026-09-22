import CoreLocation
import MapKit

/// Opens a location in Apple Maps -- the native equivalent of the web app's
/// "open in maps" link.
enum MapsLauncher {
    static func open(title: String, coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let item = MKMapItem(location: location, address: nil)
        item.name = title
        item.openInMaps()
    }

    /// Fallback for events with only a plain-text location (no geocoded
    /// coordinate) -- lets Maps resolve the search itself.
    static func search(query: String) {
        guard !query.isEmpty else { return }
        MKLocalSearch(request: {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            return request
        }()).start { response, _ in
            guard let item = response?.mapItems.first else { return }
            item.openInMaps()
        }
    }
}
