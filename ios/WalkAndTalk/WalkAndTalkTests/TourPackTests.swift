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

    func testBundledTourLoadsAndEveryAudioFileExists() throws {
        // XCTUnwrap fails the test (instead of crashing) if the value is nil.
        let loader = try XCTUnwrap(TourLoader.bundled(route: "mexicali"), "tours/mexicali folder reference missing")
        let tour = try loader.load()

        XCTAssertEqual(tour.route, "mexicali")
        XCTAssertFalse(tour.stops.isEmpty)
        for stop in tour.stops {
            let path = loader.audioURL(for: stop).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "missing \(stop.audio)")
        }
    }
}
