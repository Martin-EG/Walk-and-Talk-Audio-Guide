//
//  ContentView.swift
//  WalkAndTalk
//
//  Created by Martin Espericueta on 07/10/26.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    // @State: SwiftUI-owned value, like useState. Holding the player here keeps it alive
    // while it plays (a local variable would be freed and the sound would cut off).
    @State private var player: AVAudioPlayer?
    @State private var status = "Ready"

    var body: some View {
        VStack(spacing: 24) {
            Text("Walk-and-Talk")
                .font(.largeTitle.bold())

            Button("Play hello") {
                playHello()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text(status)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func playHello() {
        // Bundle.main.url finds files copied into the app at build time. It returns an
        // optional (nil if missing), so `guard let` unwraps it or exits early.
        guard let url = Bundle.main.url(forResource: "hello", withExtension: "wav") else {
            status = "hello.wav not found in app bundle"
            return
        }
        do {
            // .playback category = play even when the silent switch is on (and later, in background).
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)

            // `try` marks calls that can throw; `do/catch` is Swift's try/catch.
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()  // `?.` is optional chaining, same idea as JS.
            status = "Playing…"
        } catch {
            status = "Playback failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
