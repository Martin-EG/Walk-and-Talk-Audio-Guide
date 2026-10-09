//
//  WalkAndTalkApp.swift
//  WalkAndTalk
//
//  Created by Martin Espericueta on 07/10/26.
//

import SwiftUI

@main
struct WalkAndTalkApp: App {
    // Created once for the app's lifetime and shared with the view.
    @State private var session = WalkSession()

    var body: some Scene {
        WindowGroup {
            WalkView(session: session)
        }
    }
}
