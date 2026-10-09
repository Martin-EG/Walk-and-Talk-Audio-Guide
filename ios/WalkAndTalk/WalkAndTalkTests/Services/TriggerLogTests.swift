//
//  TriggerLogTests.swift
//  WalkAndTalkTests
//

import XCTest
@testable import WalkAndTalk

@MainActor
final class TriggerLogTests: XCTestCase {

    func testWalkWritesEnterTriggerAndClosestRows() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "log-\(UUID()).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let log = TriggerLog(url: url)

        let a = Stop(id: "A", name: "Parque \"A\"", lat: 32.6, lon: -115.4, radiusM: 35,
                     audio: "audio/a.m4a", durationS: 10, story: "")
        let b = Stop(id: "B", name: "B", lat: 32.7, lon: -115.4, radiusM: 35,
                     audio: "audio/b.m4a", durationS: 10, story: "")
        let near = (lat: 32.6 + 20 / 111_195, lon: -115.4)   // 20 m north of A
        let now = Date()

        log.walkStarted(at: now)
        log.observe(stops: [a, b], lat: near.lat, lon: near.lon, accuracyM: 40, time: now)  // poor fix still counts as "enter"
        log.observe(stops: [a, b], lat: near.lat, lon: near.lon, accuracyM: 5, time: now)   // no second "enter"
        log.triggered(a, lat: near.lat, lon: near.lon, accuracyM: 5, time: now)
        log.walkEnded(stops: [a, b], at: now)

        let lines = log.contents().split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, TriggerLog.header)
        XCTAssertEqual(lines.map { $0.split(separator: ",")[1] },
                       ["event", "walk_start", "enter", "trigger", "closest", "closest", "walk_end"])
        XCTAssertTrue(lines[2].hasSuffix(",A,\"Parque \"\"A\"\"\",20.0,40.0"))
        XCTAssertTrue(lines[4].hasSuffix(",20.0,40.0"))   // closest keeps the first fix at that distance
    }
}
