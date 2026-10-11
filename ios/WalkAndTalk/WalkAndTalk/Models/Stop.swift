//
//  Stop.swift
//  WalkAndTalk
//
//  One point of interest in a tour pack.
//

import Foundation

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
    /// The place's outline, when OpenStreetMap has one (parks, ballparks, plazas): closed rings of
    /// [lat, lon] points. The stop then triggers anywhere inside it or within `radiusM` of its edge.
    /// Missing in older packs and for single-point places, which trigger within `radiusM` of `lat`/`lon`.
    var area: [[[Double]]]? = nil
}
