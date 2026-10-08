//
//  ProximityEngineTests.swift
//  WalkAndTalkTests
//

import XCTest
@testable import WalkAndTalk  // @testable exposes the app's internal types to the tests.

// The app target defaults everything to the main actor, so the tests run there too.
@MainActor
final class ProximityEngineTests: XCTestCase {

    // El cocinero chino, the first Mexicali stop.
    let origin = (lat: 32.661753, lon: -115.4897029)

    /// A stop `northM` meters north of `origin` with a 35 m radius.
    func stop(_ id: String, northM: Double = 0) -> Stop {
        let p = point(northM: northM)
        return Stop(id: id, name: id, lat: p.lat, lon: p.lon, radiusM: 35,
                    audio: "audio/\(id).m4a", durationS: 10, story: "")
    }

    /// A coordinate `northM` meters north of `origin` (negative = south).
    func point(northM: Double) -> (lat: Double, lon: Double) {
        (origin.lat + northM / 111_195, origin.lon)
    }

    /// Feeds one fix at `northM` meters north of `origin` and returns the triggered stop's id.
    func fix(_ engine: inout ProximityEngine, northM: Double, accuracyM: Double = 5) -> String? {
        let p = point(northM: northM)
        return engine.update(lat: p.lat, lon: p.lon, accuracyM: accuracyM)?.id
    }

    func testDistanceHelperMatchesTestOffsets() {
        let p = point(northM: 100)
        XCTAssertEqual(ProximityEngine.distanceM(origin.lat, origin.lon, p.lat, p.lon), 100, accuracy: 0.5)
    }

    func testInsideRadiusTriggersOnSecondFixAndOnlyOnce() {
        var engine = ProximityEngine(stops: [stop("A")])

        XCTAssertNil(fix(&engine, northM: 10), "one fix is not enough")
        XCTAssertEqual(fix(&engine, northM: 8), "A")
        XCTAssertNil(fix(&engine, northM: 5), "a stop never triggers twice")
        XCTAssertNil(fix(&engine, northM: 0))
        XCTAssertEqual(engine.triggered, ["A"])
    }

    func testOutsideRadiusNeverTriggers() {
        var engine = ProximityEngine(stops: [stop("A")])
        for _ in 0..<5 {
            XCTAssertNil(fix(&engine, northM: 40))
        }
    }

    func testJitterAtTheEdgeDoesNotTrigger() {
        var engine = ProximityEngine(stops: [stop("A")])

        // Standing at the 35 m edge, GPS bounces in (33 m) and out (37 m).
        for _ in 0..<5 {
            XCTAssertNil(fix(&engine, northM: 33))
            XCTAssertNil(fix(&engine, northM: 37))
        }
        // Two inside fixes in a row finally trigger it.
        XCTAssertNil(fix(&engine, northM: 33))
        XCTAssertEqual(fix(&engine, northM: 32), "A")
    }

    func testAlreadyPlayedStopIsSkipped() {
        var engine = ProximityEngine(stops: [stop("A")], alreadyTriggered: ["A"])
        for _ in 0..<5 {
            XCTAssertNil(fix(&engine, northM: 0))
        }
    }

    func testTwoStopsCloseTogetherPlayNearestFirstThenTheOther() {
        // B is 20 m north of A; standing between them we're inside both radii.
        var engine = ProximityEngine(stops: [stop("A"), stop("B", northM: 20)])

        XCTAssertNil(fix(&engine, northM: 5))
        XCTAssertEqual(fix(&engine, northM: 6), "A", "nearest stop wins")
        XCTAssertNil(fix(&engine, northM: 7), "B needs its own two fixes")
        XCTAssertEqual(fix(&engine, northM: 8), "B")
        XCTAssertNil(fix(&engine, northM: 9))
    }

    func testSwitchingCandidateStopRestartsTheCount() {
        // A and B are far apart; one fix near each must not add up to a trigger.
        var engine = ProximityEngine(stops: [stop("A"), stop("B", northM: 200)])

        XCTAssertNil(fix(&engine, northM: 0))
        XCTAssertNil(fix(&engine, northM: 200))
        XCTAssertEqual(fix(&engine, northM: 200), "B")
    }

    func testPoorAccuracyFixIsIgnored() {
        var engine = ProximityEngine(stops: [stop("A")])

        // Right on top of the stop, but accuracy is 30 m (worse than 25 m) or invalid (-1).
        XCTAssertNil(fix(&engine, northM: 0, accuracyM: 30))
        XCTAssertNil(fix(&engine, northM: 0, accuracyM: 30))
        XCTAssertNil(fix(&engine, northM: 0, accuracyM: -1))
        XCTAssertTrue(engine.triggered.isEmpty)

        // Exactly 25 m counts. A poor fix between two good ones doesn't break the streak.
        XCTAssertNil(fix(&engine, northM: 0, accuracyM: 25))
        XCTAssertNil(fix(&engine, northM: 0, accuracyM: 80))
        XCTAssertEqual(fix(&engine, northM: 0, accuracyM: 10), "A")
    }
}
