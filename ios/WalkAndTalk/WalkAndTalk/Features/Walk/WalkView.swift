//
//  WalkView.swift
//  WalkAndTalk
//

import SwiftUI

struct WalkView: View {
    // Passed in from the App. Because WalkSession is @Observable, SwiftUI re-renders this view
    // whenever a property it reads changes; no props drilling of individual values needed.
    let session: WalkSession

    // @State: view-local state, like useState.
    @State private var showDebug = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let message = session.errorMessage {
                    Text(message).foregroundStyle(.red)
                }

                walkButton

                if let stop = session.currentStop {
                    Text(stop.name)
                        .font(.title2.bold())
                    Text(stop.story)
                        .font(.title3)          // large type, readable at arm's length
                        .lineSpacing(4)
                } else if session.isWalking {
                    Text("Walk toward the first stop. Stories play on their own, so you can lock the screen.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Toggle("Debug info", isOn: $showDebug)  // `$` passes a two-way binding to the toggle
                if showDebug {
                    WalkDebugPanel(session: session)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Walk-and-Talk")
                .font(.largeTitle.bold())
            if let tour = session.tour {
                Text("\(session.playedIDs.count) of \(tour.stops.count) stops")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var walkButton: some View {
        Button {
            if session.isWalking { session.stop() } else { session.start() }
        } label: {
            Text(session.isWalking ? "Stop walk" : "Start walk")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(session.isWalking ? Color.red : Color.accentColor)
        .controlSize(.large)
        .disabled(session.tour == nil)
    }
}

#Preview {
    WalkView(session: WalkSession())
}
