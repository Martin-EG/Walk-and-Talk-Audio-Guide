//
//  TourLibraryTests.swift
//  WalkAndTalkTests
//
//  Install / keep / list / delete for downloaded packs, using a zip of the bundled mexicali2
//  pack (the same layout the server sends) in a throwaway folder instead of Documents.
//

import XCTest
import ZIPFoundation
@testable import WalkAndTalk

@MainActor
final class TourLibraryTests: XCTestCase {
    private var root: URL!
    private var library: TourLibrary!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
        library = TourLibrary(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Zips the bundled mexicali2 folder the way the server does: tour.json and audio/ at the top level.
    private func makePackZip() throws -> URL {
        let pack = try XCTUnwrap(TourLoader.bundled(route: "mexicali2")).folder
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try FileManager.default.zipItem(at: pack, to: zip, shouldKeepParent: false)
        return zip
    }

    func testInstallUnzipsIntoTheToursFolderAndLoads() throws {
        let loader = try library.install(zip: makePackZip(), tourID: "t1")

        XCTAssertEqual(loader.folder.path, root.appendingPathComponent("t1").path)  // .path ignores a trailing "/"
        let tour = try loader.load()
        XCTAssertEqual(tour.stops.count, 5)
        for stop in tour.stops {
            XCTAssertTrue(FileManager.default.fileExists(atPath: loader.audioURL(for: stop).path), stop.audio)
        }
    }

    func testOnlyKeptToursAreListedAndUnkeptOnesAreRemoved() throws {
        try library.install(zip: makePackZip(), tourID: "kept")
        try library.install(zip: makePackZip(), tourID: "abandoned")
        try library.keep("kept")

        XCTAssertEqual(library.savedTours().map(\.id), ["kept"])
        XCTAssertEqual(library.savedTours().first?.stopCount, 5)

        library.removeUnkept()
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder(for: "abandoned").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder(for: "kept").path))
    }

    func testDeleteRemovesThePack() throws {
        try library.install(zip: makePackZip(), tourID: "t1")
        try library.keep("t1")
        library.delete("t1")

        XCTAssertTrue(library.savedTours().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder(for: "t1").path))
    }

    func testDownloadedPackOpensInWalkMode() throws {
        let loader = try library.install(zip: makePackZip(), tourID: "t1")
        let session = WalkSession(loader: loader, name: "t1")
        XCTAssertNotNil(session.tour, session.errorMessage ?? "")
    }
}
