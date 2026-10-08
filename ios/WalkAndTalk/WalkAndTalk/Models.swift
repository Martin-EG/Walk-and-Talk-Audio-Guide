//
//  Models.swift
//  WalkAndTalk
//
//  The tour pack format (tours/<route>/tour.json) and a loader that reads it from the app bundle.
//

import Foundation

// `Decodable` lets JSONDecoder build these structs from JSON, like a typed JSON.parse.
// Keys that aren't listed here (models, sources, thin_facts...) are simply ignored.
struct Tour: Decodable {
    let route: String
    let language: String
    let stops: [Stop]
}

// `Identifiable` (has an `id`) lets SwiftUI lists use stops directly; `Hashable` lets them go in Sets.
struct Stop: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    let radiusM: Double
    let audio: String       // path relative to the tour folder, e.g. "audio/01-....m4a"
    let durationS: Double
    let story: String
}

/// Finds a tour pack inside the app bundle and decodes it.
///
/// The Xcode project adds `tours/mexicali` as a *folder reference* (blue folder), so the app
/// bundle contains `mexicali/tour.json` and `mexicali/audio/*.m4a` with the folders intact.
struct TourLoader {
    let folder: URL

    /// The bundled pack for `route`, or nil if that folder isn't in the app.
    static func bundled(route: String) -> TourLoader? {
        guard let folder = Bundle.main.url(forResource: route, withExtension: nil) else { return nil }
        return TourLoader(folder: folder)
    }

    func load() throws -> Tour {
        let data = try Data(contentsOf: folder.appendingPathComponent("tour.json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // radius_m -> radiusM, duration_s -> durationS
        return try decoder.decode(Tour.self, from: data)
    }

    func audioURL(for stop: Stop) -> URL {
        folder.appendingPathComponent(stop.audio)
    }
}
