import Foundation
import MapKit
import Observation

/// A resolved location result: display title/subtitle plus a coordinate,
/// ready to become an EKStructuredLocation or a SavedAddress.
struct ResolvedLocation: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: ResolvedLocation, rhs: ResolvedLocation) -> Bool {
        lhs.id == rhs.id
    }
}

/// Wraps MKLocalSearchCompleter for live-typing autocomplete, then resolves a
/// chosen completion to a coordinate via MKLocalSearch -- mirrors Apple Maps'
/// own search-as-you-type behavior, replacing the web app's Photon geocoding.
@Observable
@MainActor
final class LocationSearchService: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()

    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var isResolving = false

    var queryFragment: String = "" {
        didSet { completer.queryFragment = queryFragment }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    // MKLocalSearchCompleter always calls its delegate on the main thread, so
    // assumeIsolated avoids hopping through a Task just to cross into
    // MainActor -- which would otherwise require MKLocalSearchCompletion
    // (not Sendable) to cross an actor boundary.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            // Read from self.completer (actor-isolated state), not the
            // nonisolated parameter -- referencing the parameter here would
            // require sending a non-Sendable MKLocalSearchCompleter across
            // the isolation boundary.
            self.results = self.completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            self.results = []
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedLocation? {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start(), let item = response.mapItems.first else {
            return nil
        }
        return ResolvedLocation(
            title: completion.title,
            subtitle: completion.subtitle,
            coordinate: item.location.coordinate
        )
    }
}
