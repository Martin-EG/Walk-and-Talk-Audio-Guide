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
    /// Set when a walk ends; cleared when the next one starts.
    private(set) var summary: WalkSummary?
    /// True while missed stops play after the walk (no GPS).
    private(set) var isReplaying = false

    let tracker = LocationTracker()
    /// Field-test CSV of enter/trigger/closest events, exported from the walk screen.
    @ObservationIgnored let log = TriggerLog()
    @ObservationIgnored private let audio = AudioPlayer()
    @ObservationIgnored private let loader: TourLoader?
    private var engine: ProximityEngine
    @ObservationIgnored private var odometer = WalkOdometer()
    @ObservationIgnored private var startedAt: Date?

    /// The pack bundled inside the app.
    // `convenience` init: a shortcut that must hand off to the main (designated) init below.
    convenience init(route: String = "mexicali2") {
        self.init(loader: TourLoader.bundled(route: route), name: route)
    }

    /// Any pack folder: bundled, or downloaded to Documents/tours/<id>/.
    init(loader: TourLoader?, name: String) {
        let route = name
        // Work in local variables first: Swift won't let us read `self` until every
        // property has a value.
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
            guard let self else { return }
            // A stop counts as reached the moment its audio starts. Replays after the walk
            // don't count: the walker never got there.
            if isWalking { playedIDs.insert(stop.id) }
            currentStop = stop
        }
        audio.onIdle = { [weak self] in
            guard let self, isReplaying else { return }
            isReplaying = false
            audio.end()
        }
    }

    /// Starts a fresh walk: every stop can play again.
    func start() {
        guard !isWalking, let tour else { return }
        stopReplay()
        do {
            try audio.begin()
        } catch {
            errorMessage = "Audio unavailable: \(error.localizedDescription)"
            return
        }
        engine = ProximityEngine(stops: tour.stops)
        playedIDs = []
        currentStop = nil
        summary = nil
        odometer = WalkOdometer()
        startedAt = Date()
        errorMessage = nil
        isWalking = true
        log.walkStarted()
        tracker.start()
    }

    /// Ends the walk: stops the story, clears the queue, and turns GPS off.
    func stop() {
        guard isWalking else { return }
        isWalking = false
        tracker.stop()
        audio.end()
        log.walkEnded(stops: tour?.stops ?? [])
        let stops = tour?.stops ?? []
        summary = WalkSummary(
            reachedCount: playedIDs.count,
            totalCount: stops.count,
            duration: startedAt.map { Date().timeIntervalSince($0) } ?? 0,
            distanceM: odometer.distanceM,
            missed: stops.filter { !playedIDs.contains($0.id) }
        )
    }

    /// Plays stops' stories back to back after the walk, wherever the listener is.
    /// Replaces any replay already in progress.
    func replay(_ stops: [Stop]) {
        guard !isWalking, let loader, !stops.isEmpty else { return }
        stopReplay()
        do {
            try audio.begin()
        } catch {
            errorMessage = "Audio unavailable: \(error.localizedDescription)"
            return
        }
        isReplaying = true
        for stop in stops {
            audio.enqueue(stop, url: loader.audioURL(for: stop))
        }
    }

    func stopReplay() {
        guard isReplaying else { return }
        isReplaying = false
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
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy
        // Log before the engine sees the fix, so an "enter" row always precedes its "trigger".
        log.observe(stops: engine.stops, lat: lat, lon: lon, accuracyM: accuracy, time: location.timestamp)
        odometer.update(lat: lat, lon: lon, accuracyM: accuracy)
        if let stop = engine.update(lat: lat, lon: lon, accuracyM: accuracy) {
            log.triggered(stop, lat: lat, lon: lon, accuracyM: accuracy, time: location.timestamp)
            audio.enqueue(stop, url: loader.audioURL(for: stop))
        }
    }
}
