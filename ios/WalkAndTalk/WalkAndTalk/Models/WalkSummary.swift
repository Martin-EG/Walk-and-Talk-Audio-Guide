//
//  WalkSummary.swift
//  WalkAndTalk
//
//  What the walk screen shows after "Stop walk": stops reached, time, distance, and the
//  stops the walker never got to, which can still be played from here.
//

import Foundation

struct WalkSummary {
    let reachedCount: Int
    let totalCount: Int
    let duration: TimeInterval
    let distanceM: Double
    /// Untriggered stops, in tour order.
    let missed: [Stop]
}
