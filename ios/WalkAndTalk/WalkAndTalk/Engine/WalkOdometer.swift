//
//  WalkOdometer.swift
//  WalkAndTalk
//
//  Adds up the distance walked from GPS fixes. Plain Swift, like ProximityEngine, so the
//  unit tests can feed it made-up fixes.
//

import Foundation

struct WalkOdometer {
    /// Moves shorter than this (meters) aren't counted yet, so GPS jitter while standing
    /// still doesn't add up to phantom distance.
    static let minStepM = 10.0

    private(set) var distanceM = 0.0

    // The last fix we counted from.
    private var anchor: (lat: Double, lon: Double)?

    /// Feed one GPS fix. Poor fixes (same threshold as the proximity engine) are ignored.
    mutating func update(lat: Double, lon: Double, accuracyM: Double) {
        guard accuracyM >= 0, accuracyM <= ProximityEngine.maxAccuracyM else { return }
        guard let anchor else {
            self.anchor = (lat, lon)
            return
        }
        let step = ProximityEngine.distanceM(anchor.lat, anchor.lon, lat, lon)
        // A step must clear both the jitter floor and the fix's own uncertainty.
        guard step >= max(Self.minStepM, accuracyM) else { return }
        distanceM += step
        self.anchor = (lat, lon)
    }
}
