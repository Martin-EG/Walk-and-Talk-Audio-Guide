//
//  WalkAndTalkApp.swift
//  WalkAndTalk
//
//  Created by Martin Espericueta on 07/10/26.
//

import SwiftUI

@main
struct WalkAndTalkApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()  // saved tours, the demo, and "Create a tour"; walk mode opens from there
        }
    }
}
