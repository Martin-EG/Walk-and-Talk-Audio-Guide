//
//  TourLibrary.swift
//  WalkAndTalk
//
//  Downloaded tour packs, one folder each: Documents/tours/<id>/ (tour.json + audio/).
//  A pack becomes "kept" when the user taps Keep tour (an empty `.kept` file in its folder).
//  Packs nobody kept (the app was closed during review) are deleted on the next launch.
//

import Foundation
import ZIPFoundation

struct TourLibrary {
    let root: URL

    /// What the saved-tours list shows for one kept pack.
    struct SavedTour: Identifiable {
        let id: String
        let folder: URL
        let name: String
        let stopCount: Int
        let date: Date
    }

    init(root: URL = URL.documentsDirectory.appendingPathComponent("tours")) {
        self.root = root
    }

    func folder(for tourID: String) -> URL {
        root.appendingPathComponent(tourID)
    }

    /// Unzips a downloaded pack into Documents/tours/<id>/, replacing any earlier copy.
    @discardableResult
    func install(zip: URL, tourID: String) throws -> TourLoader {
        let files = FileManager.default
        let unpacked = files.temporaryDirectory.appendingPathComponent("unzip-\(tourID)")
        try? files.removeItem(at: unpacked)
        try files.unzipItem(at: zip, to: unpacked)  // from ZIPFoundation
        let loader = TourLoader(folder: unpacked)
        _ = try loader.load()  // fail here, not mid-walk, if tour.json is broken

        try files.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = folder(for: tourID)
        try? files.removeItem(at: destination)
        try files.moveItem(at: unpacked, to: destination)
        try? files.removeItem(at: zip)
        return TourLoader(folder: destination)
    }

    func keep(_ tourID: String) throws {
        try Data().write(to: folder(for: tourID).appendingPathComponent(".kept"))
    }

    func delete(_ tourID: String) {
        try? FileManager.default.removeItem(at: folder(for: tourID))
    }

    /// Kept packs, newest first. Packs that fail to load are skipped.
    func savedTours() -> [SavedTour] {
        packFolders().compactMap { folder in
            guard isKept(folder), let tour = try? TourLoader(folder: folder).load() else { return nil }
            let date = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let name = tour.stops.first.map { "Near \($0.name)" } ?? folder.lastPathComponent
            return SavedTour(id: folder.lastPathComponent, folder: folder, name: name,
                             stopCount: tour.stops.count, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    /// Deletes packs that were downloaded but never kept.
    func removeUnkept() {
        for folder in packFolders() where !isKept(folder) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func isKept(_ folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(".kept").path)
    }

    private func packFolders() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.hasDirectoryPath }
    }
}
