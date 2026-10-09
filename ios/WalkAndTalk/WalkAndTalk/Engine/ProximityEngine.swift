//
//  ProximityEngine.swift
//  WalkAndTalk
//
//  Decides when to play a stop. Plain Swift (no CoreLocation, no UIKit) so the unit tests
//  can feed it made-up GPS fixes.
//

import Foundation

struct ProximityEngine {
    /// Fixes less precise than this (horizontal accuracy, meters) are ignored.
    static let maxAccuracyM = 25.0
    /// How many qualifying fixes in a row must agree on a stop before it triggers.
    static let requiredFixes = 2

    let stops: [Stop]

    /// Stops that already triggered. Each stop triggers at most once per walk.
    private(set) var triggered: Set<String>

    // The stop we seem to be arriving at, and how many qualifying fixes in a row picked it.
    private var candidateID: String?
    private var streak = 0

    init(stops: [Stop], alreadyTriggered: Set<String> = []) {
        self.stops = stops
        self.triggered = alreadyTriggered
    }

    /// Feed one GPS fix. Returns the stop to play now, or nil.
    ///
    /// `accuracyM` is the fix's horizontal accuracy in meters; a negative value means
    /// "invalid", which is CoreLocation's convention.
    ///
    /// `mutating`: structs are values in Swift, so a method that changes their fields must say so.
    mutating func update(lat: Double, lon: Double, accuracyM: Double) -> Stop? {
        // A poor fix tells us nothing, so it neither counts toward nor breaks a streak.
        guard accuracyM >= 0, accuracyM <= Self.maxAccuracyM else { return nil }

        // `guard let` unwraps an optional or exits early.
        guard let nearest = nearestUntriggered(lat: lat, lon: lon),
              nearest.distanceM <= nearest.stop.radiusM else {
            candidateID = nil
            streak = 0
            return nil
        }

        if nearest.stop.id == candidateID {
            streak += 1
        } else {
            candidateID = nearest.stop.id
            streak = 1
        }

        guard streak >= Self.requiredFixes else { return nil }

        triggered.insert(nearest.stop.id)
        candidateID = nil
        streak = 0
        return nearest.stop
    }

    /// The closest stop that hasn't triggered yet, at any distance (used by the debug panel too).
    /// Returns a tuple, Swift's lightweight way to return two values.
    func nearestUntriggered(lat: Double, lon: Double) -> (stop: Stop, distanceM: Double)? {
        stops
            .filter { !triggered.contains($0.id) }
            .map { (stop: $0, distanceM: Self.distanceM(lat, lon, $0.lat, $0.lon)) }
            .min { $0.distanceM < $1.distanceM }
    }

    /// Great-circle distance in meters (haversine). Plenty accurate at walking scale.
    static func distanceM(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}
