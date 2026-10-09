//
//  AddressSearch.swift
//  WalkAndTalk
//
//  Address autocomplete for the start point: MKLocalSearchCompleter suggests as you type,
//  MKLocalSearch turns the chosen suggestion into a coordinate.
//

import MapKit
import Observation

@Observable
final class AddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    // `didSet` runs after every change, like a useEffect on `query`.
    var query = "" {
        didSet {
            if query.isEmpty { results = [] } else { completer.queryFragment = query }
        }
    }
    private(set) var results: [MKLocalSearchCompletion] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Looks up where a suggestion is. nil if Apple Maps can't place it.
    func coordinate(for completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first else {
            errorMessage = "Couldn't find that place. Try another address or drop a pin."
            return nil
        }
        errorMessage = nil
        if #available(iOS 26, *) {
            return item.location.coordinate
        }
        return item.placemark.coordinate
    }

    // MARK: MKLocalSearchCompleterDelegate
    // Same pattern as LocationTracker: MapKit calls these on the main thread.

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        MainActor.assumeIsolated {
            self.results = results
            errorMessage = nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            results = []
            errorMessage = "Address search isn't available right now. Drop a pin on the map instead."
        }
    }
}
