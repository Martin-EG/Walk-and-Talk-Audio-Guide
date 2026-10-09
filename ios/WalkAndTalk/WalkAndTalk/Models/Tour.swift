//
//  Tour.swift
//  WalkAndTalk
//
//  The tour pack format (tours/<route>/tour.json).
//

import Foundation

// `Decodable` lets JSONDecoder build these structs from JSON, like a typed JSON.parse.
// Keys that aren't listed here (models, sources, thin_facts...) are simply ignored.
struct Tour: Decodable {
    let route: String
    let language: String
    let stops: [Stop]
}
