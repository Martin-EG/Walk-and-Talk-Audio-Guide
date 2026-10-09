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

                if !session.isWalking, let summary = session.summary {
                    summaryCard(summary)
                }

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

                // ShareLink opens the iOS share sheet (AirDrop, Save to Files, Mail) for the file.
                // Hidden mid-walk so the end-of-walk "closest" rows are in the export.
                if !session.isWalking, session.log.exists {
                    ShareLink(item: session.log.url) {
                        Label("Export trigger log", systemImage: "square.and.arrow.up")
                    }
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

    private func summaryCard(_ summary: WalkSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Walk complete")
                .font(.title2.bold())
            HStack(spacing: 24) {
                stat("Stops", "\(summary.reachedCount) of \(summary.totalCount)")
                stat("Time", Duration.seconds(summary.duration)
                    .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                stat("Distance", Measurement(value: summary.distanceM, unit: UnitLength.meters)
                    .formatted(.measurement(width: .abbreviated, usage: .road)))
            }

            if !summary.missed.isEmpty {
                Divider()
                HStack {
                    Text("Missed stops")
                        .font(.headline)
                    Spacer()
                    if session.isReplaying {
                        Button("Stop", systemImage: "stop.fill") { session.stopReplay() }
                    } else {
                        Button("Play all", systemImage: "play.fill") { session.replay(summary.missed) }
                    }
                }
                ForEach(summary.missed) { stop in
                    Button {
                        session.replay([stop])
                    } label: {
                        HStack {
                            Text(stop.name)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            let playing = session.isReplaying && session.currentStop?.id == stop.id
                            Image(systemName: playing ? "speaker.wave.2.fill" : "play.circle")
                        }
                    }
                }
            }
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
