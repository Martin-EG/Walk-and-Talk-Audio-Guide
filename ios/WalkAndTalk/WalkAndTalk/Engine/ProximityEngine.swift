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
            .map { (stop: $0, distanceM: Self.distanceM(lat, lon, to: $0)) }
            .min { $0.distanceM < $1.distanceM }
    }

    /// How far a walker is from a stop: 0 inside its outline, else the distance to the outline's
    /// edge; from its single point when it has no outline.
    static func distanceM(_ lat: Double, _ lon: Double, to stop: Stop) -> Double {
        guard let area = stop.area, !area.isEmpty else {
            return distanceM(lat, lon, stop.lat, stop.lon)
        }
        // Flat local projection in meters around the walker; plenty accurate across one place.
        let k = 111_195.0
        let cosLat = cos(lat * .pi / 180)
        func xy(_ p: [Double]) -> (x: Double, y: Double) {
            ((p[1] - lon) * k * cosLat, (p[0] - lat) * k)
        }
        var nearest = Double.infinity
        for ring in area where ring.count >= 4 && ring.allSatisfy({ $0.count == 2 }) {
            let points = ring.map(xy)
            var inside = false
            // Walker is at (0, 0). Ray casting for inside, point-to-segment for distance.
            for (a, b) in zip(points, points.dropFirst()) {
                if (a.y > 0) != (b.y > 0), 0 < a.x + (0 - a.y) * (b.x - a.x) / (b.y - a.y) {
                    inside.toggle()
                }
                let dx = b.x - a.x, dy = b.y - a.y
                let length2 = dx * dx + dy * dy
                let t = length2 == 0 ? 0 : max(0, min(1, -(a.x * dx + a.y * dy) / length2))
                nearest = min(nearest, hypot(a.x + t * dx, a.y + t * dy))
            }
            if inside { return 0 }
        }
        // Every ring was malformed: fall back to the point.
        return nearest.isFinite ? nearest : distanceM(lat, lon, stop.lat, stop.lon)
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
