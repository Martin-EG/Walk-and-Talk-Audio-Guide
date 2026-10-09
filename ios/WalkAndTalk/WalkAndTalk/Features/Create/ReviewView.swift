//
//  ReviewView.swift
//  WalkAndTalk
//
//  Step 4: see the route before walking it. Numbered pins joined in loop order,
//  the stop list, and Keep tour / Start again.
//

import MapKit
import SwiftUI

struct ReviewView: View {
    let tourID: String
    /// Where the pack is; nil means Documents/tours/<tourID>/. Previews pass the bundled demo.
    var folder: URL? = nil

    @Environment(AppModel.self) private var model
    @State private var tour: Tour?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let tour {
                routeMap(tour)
                    .frame(height: 320)
                List {
                    Section {
                        ForEach(Array(tour.stops.enumerated()), id: \.element.id) { index, stop in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(index + 1)").monospacedDigit().bold().foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stop.name)
                                    Text("\(Int(stop.durationS.rounded())) s story")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        let minutes = max(1, Int((tour.stops.reduce(0) { $0 + $1.durationS } / 60).rounded()))
                        // ^[...](inflect: true) lets iOS pick "stop" or "stops" to match the number.
                        Text("^[\(tour.stops.count) stop](inflect: true) · about \(minutes) min of stories")
                    }
                }
                buttons
            } else if let errorMessage {
                ContentUnavailableView("Couldn't open the tour", systemImage: "exclamationmark.triangle",
                                       description: Text(errorMessage))
                buttons
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Your tour")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()  // choose Keep or Start again
        .task { load() }
    }

    private func routeMap(_ tour: Tour) -> some View {
        let coordinates = tour.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        // `.automatic` frames everything on the map: all pins and the line.
        return Map(initialPosition: .automatic) {
            // Straight lines in walking order, closed back to stop 1 because the route is a loop.
            MapPolyline(coordinates: coordinates + coordinates.prefix(1))
                .stroke(.blue, lineWidth: 3)
            ForEach(Array(tour.stops.enumerated()), id: \.element.id) { index, stop in
                Annotation(stop.name, coordinate: coordinates[index]) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.blue))
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                model.library.delete(tourID)
                model.path = [.startPoint()]
            } label: {
                Text("Start again").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                keep()
            } label: {
                Text("Keep tour").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tour == nil)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private func load() {
        do {
            tour = try TourLoader(folder: folder ?? model.library.folder(for: tourID)).load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func keep() {
        do {
            try model.library.keep(tourID)
            model.refresh()
            model.path = [.walk(folder: model.library.folder(for: tourID))]
        } catch {
            errorMessage = "Couldn't save the tour: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack {
        ReviewView(tourID: "mexicali2", folder: TourLoader.bundled(route: "mexicali2")?.folder)
    }
    .environment(AppModel())
}
