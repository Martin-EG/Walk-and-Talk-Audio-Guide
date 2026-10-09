//
//  TourPackTests.swift
//  WalkAndTalkTests
//
//  Checks that the tour pack really ships inside the app (the tests run inside the app,
//  so Bundle.main is the app bundle).
//

import XCTest
@testable import WalkAndTalk

@MainActor
final class TourPackTests: XCTestCase {

    func testBundledToursLoadAndEveryAudioFileExists() throws {
        for route in ["mexicali", "mexicali2"] {
            // XCTUnwrap fails the test (instead of crashing) if the value is nil.
            let loader = try XCTUnwrap(TourLoader.bundled(route: route), "tours/\(route) folder reference missing")
            let tour = try loader.load()

            XCTAssertEqual(tour.route, route)
            XCTAssertFalse(tour.stops.isEmpty)
            for stop in tour.stops {
                let path = loader.audioURL(for: stop).path
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), "\(route): missing \(stop.audio)")
            }
        }
    }

    func testAppLoadsItsDefaultTour() {
        // WalkSession() is what the app creates on launch; a missing tour shows up as an error.
        let session = WalkSession()
        XCTAssertNotNil(session.tour, session.errorMessage ?? "")
    }
}
