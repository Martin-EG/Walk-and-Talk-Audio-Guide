//
//  Secrets.example.swift
//  WalkAndTalk
//
//  Copy to WalkAndTalk/App/Secrets.swift (git-ignored) and fill in your server.
//  Simulator: http://localhost:8000 reaches a server running on this Mac.
//  Note: anything compiled into the app can be extracted from it, so treat this key as a
//  speed bump against casual use, not a real secret. Rotate it after the challenge.
//

import Foundation

enum Secrets {
    static let serverURL = URL(string: "http://localhost:8000")!
    static let apiKey = "dev-key"
}
