//
//  TourLoader.swift
//  WalkAndTalk
//
//  Finds a tour pack inside the app bundle and decodes it.
//

import Foundation

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
