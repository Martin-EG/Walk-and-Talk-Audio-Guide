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
}
