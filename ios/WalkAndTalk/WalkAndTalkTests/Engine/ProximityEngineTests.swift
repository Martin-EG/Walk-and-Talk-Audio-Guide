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

    // MARK: Outlines

    /// A stop shaped like a ballpark: a 400 m tall, 100 m wide rectangle from `origin` northward.
    /// Its point sits in the middle, 200 m north.
    func fieldStop(_ id: String = "Field") -> Stop {
        let dLon = 100 / (111_195 * cos(origin.lat * .pi / 180))
        let south = origin.lat, north = point(northM: 400).lat
        let west = origin.lon, east = origin.lon + dLon
        let ring = [[south, west], [south, east], [north, east], [north, west], [south, west]]
        let middle = point(northM: 200)
        return Stop(id: id, name: id, lat: middle.lat, lon: middle.lon + dLon / 2, radiusM: 35,
                    audio: "audio/\(id).m4a", durationS: 10, story: "", area: [ring])
    }

    func testOutlineDistanceIsZeroInsideAndToTheEdgeOutside() {
        let field = fieldStop()
        let inside = point(northM: 20)
        XCTAssertEqual(ProximityEngine.distanceM(inside.lat, inside.lon + 0.0003, to: field), 0)
        let south = point(northM: -50)
        XCTAssertEqual(ProximityEngine.distanceM(south.lat, south.lon, to: field), 50, accuracy: 0.5)
    }

    func testOutlineStopTriggersAtItsEdgeFarFromItsPoint() {
        var engine = ProximityEngine(stops: [fieldStop()])
        // 20 m south of the field: 220 m from its point, but within 35 m of its outline.
        XCTAssertNil(fix(&engine, northM: -20))
        XCTAssertEqual(fix(&engine, northM: -20), "Field")
    }

    func testOutlineStopDoesNotTriggerBeyondRadiusOfItsEdge() {
        var engine = ProximityEngine(stops: [fieldStop()])
        XCTAssertNil(fix(&engine, northM: -60))
        XCTAssertNil(fix(&engine, northM: -60))
    }

    func testStopsWithoutOutlineStillUseTheirPoint() {
        var engine = ProximityEngine(stops: [stop("A", northM: 0)])
        XCTAssertNil(fix(&engine, northM: 30))
        XCTAssertEqual(fix(&engine, northM: 30), "A")
    }

    func testAreaDecodesFromTourJSONAndIsOptional() throws {
        let json = """
        [{"id": "a", "name": "A", "lat": 1, "lon": 2, "radius_m": 35, "audio": "a.m4a", "duration_s": 3,
          "story": "", "area": [[[0, 0], [0, 1], [1, 1], [0, 0]]]},
         {"id": "b", "name": "B", "lat": 1, "lon": 2, "radius_m": 35, "audio": "b.m4a", "duration_s": 3,
          "story": ""}]
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let stops = try decoder.decode([Stop].self, from: Data(json.utf8))
        XCTAssertEqual(stops[0].area?.first?.count, 4)
        XCTAssertNil(stops[1].area)
    }
}
