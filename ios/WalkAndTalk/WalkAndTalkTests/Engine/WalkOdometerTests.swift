//
//  WalkOdometerTests.swift
//  WalkAndTalkTests
//

import XCTest
@testable import WalkAndTalk

@MainActor
final class WalkOdometerTests: XCTestCase {

    let origin = (lat: 32.661753, lon: -115.4897029)

    /// Feeds one fix at `northM` meters north of `origin`.
    func fix(_ odometer: inout WalkOdometer, northM: Double, accuracyM: Double = 5) {
        odometer.update(lat: origin.lat + northM / 111_195, lon: origin.lon, accuracyM: accuracyM)
    }

    func testStraightWalkAddsUp() {
        var odometer = WalkOdometer()
        for northM in stride(from: 0.0, through: 200, by: 20) {
            fix(&odometer, northM: northM)
        }
        XCTAssertEqual(odometer.distanceM, 200, accuracy: 1)
    }

    func testJitterWhileStandingStillAddsNothing() {
        var odometer = WalkOdometer()
        for northM in [0.0, 3, -2, 4, -3, 1] {
            fix(&odometer, northM: northM)
        }
        XCTAssertEqual(odometer.distanceM, 0)
    }

    func testSmallStepsAccumulateOnceTheyClearTheFloor() {
        var odometer = WalkOdometer()
        for northM in stride(from: 0.0, through: 30, by: 5) {
            fix(&odometer, northM: northM)
        }
        // Counted at 10, 20, 30.
        XCTAssertEqual(odometer.distanceM, 30, accuracy: 1)
    }

    func testPoorFixesAreIgnored() {
        var odometer = WalkOdometer()
        fix(&odometer, northM: 0)
        fix(&odometer, northM: 500, accuracyM: 80)
        fix(&odometer, northM: 50, accuracyM: -1)
        fix(&odometer, northM: 40)
        XCTAssertEqual(odometer.distanceM, 40, accuracy: 1)
    }
}
