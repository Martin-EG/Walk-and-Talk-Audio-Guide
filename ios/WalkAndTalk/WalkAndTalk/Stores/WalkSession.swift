//
//  WalkSession.swift
//  WalkAndTalk
//
//  Wires the pieces together: GPS fix -> ProximityEngine -> AudioPlayer queue.
//  This runs in LocationTracker's callback, not in a view, so it keeps working with the
//  screen locked (SwiftUI stops updating views in the background).
//

import CoreLocation
import Observation

@Observable
final class WalkSession {
    let tour: Tour?
    private(set) var errorMessage: String?

    private(set) var isWalking = false
    private(set) var playedIDs: Set<String> = []
    /// The stop whose story started most recently.
    private(set) var currentStop: Stop?

    let tracker = LocationTracker()
    @ObservationIgnored private let audio = AudioPlayer()
    @ObservationIgnored private let loader: TourLoader?
    private var engine: ProximityEngine

    init(route: String = "mexicali") {
        // Work in local variables first: Swift won't let us read `self` until every
        // property has a value.
        let loader = TourLoader.bundled(route: route)
        var tour: Tour?
        var errorMessage: String?
        if let loader {
            do {
                tour = try loader.load()
            } catch {
                errorMessage = "Couldn't read tour \"\(route)\": \(error)"
            }
        } else {
            errorMessage = "Tour \"\(route)\" isn't in the app bundle. Check the folder reference."
        }
        self.loader = loader
        self.tour = tour
        self.errorMessage = errorMessage
        self.engine = ProximityEngine(stops: tour?.stops ?? [])

        tracker.onFix = { [weak self] location in
            self?.handle(location)
        }
        audio.onStart = { [weak self] stop in
            // A stop counts as played the moment its audio starts.
            self?.playedIDs.insert(stop.id)
            self?.currentStop = stop
        }
    }

    /// Starts a fresh walk: every stop can play again.
    func start() {
        guard !isWalking, let tour else { return }
        do {
            try audio.begin()
        } catch {
            errorMessage = "Audio unavailable: \(error.localizedDescription)"
            return
        }
        engine = ProximityEngine(stops: tour.stops)
        playedIDs = []
        currentStop = nil
        errorMessage = nil
        isWalking = true
        tracker.start()
    }

    /// Ends the walk: stops the story, clears the queue, and turns GPS off.
    func stop() {
        guard isWalking else { return }
        isWalking = false
        tracker.stop()
        audio.end()
    }

    /// Nearest stop that hasn't triggered yet, with distance, for the debug panel.
    var nearestStop: (stop: Stop, distanceM: Double)? {
        guard let location = tracker.lastLocation else { return nil }
        return engine.nearestUntriggered(lat: location.coordinate.latitude,
                                         lon: location.coordinate.longitude)
    }

    private func handle(_ location: CLLocation) {
        guard isWalking, let loader else { return }
        if let stop = engine.update(lat: location.coordinate.latitude,
                                    lon: location.coordinate.longitude,
                                    accuracyM: location.horizontalAccuracy) {
            audio.enqueue(stop, url: loader.audioURL(for: stop))
        }
    }
}
