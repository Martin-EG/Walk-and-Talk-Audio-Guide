//
//  HomeView.swift
//  WalkAndTalk
//
//  First screen: create a tour, or walk a saved one (or the bundled demo).
//  Owns the NavigationStack for the whole create -> build -> review -> walk flow.
//

import MapKit
import SwiftUI

struct HomeView: View {
    // Created once and handed to every screen through the environment (like a React context).
    @State private var model = AppModel()

    private let demo = TourLoader.bundled(route: "mexicali2")
        .flatMap { TourLibrary.summary(of: $0.folder, name: "Mexicali downtown") }

    var body: some View {
        // `$model.path` is a two-way binding: pushing a screen appends to path, Back removes it.
        NavigationStack(path: $model.path) {
            List {
                Section {
                    hero
                    howItWorks
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)

                Section {
                    if model.savedTours.isEmpty {
                        emptyState
                    }
                    ForEach(model.savedTours) { tour in
                        NavigationLink(value: Route.walk(folder: tour.folder)) {
                            TourCard(tour: tour, showDate: true)
                        }
                    }
                    .onDelete { offsets in  // swipe left to delete
                        offsets.map { model.savedTours[$0] }.forEach(model.delete)
                    }
                } header: {
                    sectionHeader("Your tours", systemImage: "bookmark.fill")
                } footer: {
                    if !model.savedTours.isEmpty {
                        Text("Saved on this phone. They play offline, even in airplane mode.")
                    }
                }

                if let demo {
                    Section {
                        NavigationLink(value: Route.walk(folder: demo.folder)) {
                            TourCard(tour: demo, showDate: false)
                        }
                    } header: {
                        sectionHeader("Try the demo", systemImage: "play.circle.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .toolbar(.hidden, for: .navigationBar)  // the hero card is the title on this screen
            // One place maps each Route to its screen, like a router's route table.
            .navigationDestination(for: Route.self) { route in
                switch route {
                // .id gives each visit fresh @State (empty pin and search); position alone would reuse it.
                case .startPoint(let visit): StartPointView().id(visit)
                case .options(let lat, let lon): TourOptionsView(lat: lat, lon: lon)
                case .building(let tourID): BuildingView(tourID: tourID)
                case .review(let tourID): ReviewView(tourID: tourID)
                case .walk(let folder): TourWalkView(folder: folder)
                }
            }
            .onAppear { model.refresh() }
        }
        .environment(model)
    }

    // MARK: Pieces

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image("HomeIcon")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Walk-and-Talk")
                        .font(.title.bold())
                    Text("Stories that play as you walk")
                        .font(.subheadline)
                        .opacity(0.85)
                }
            }

            Text("Pick any spot. Open AI models write and narrate a short story for each place nearby. Download once, then walk it offline.")
                .font(.callout)
                .opacity(0.9)
                .fixedSize(horizontal: false, vertical: true)  // wrap instead of truncating

            Button {
                model.path.append(.startPoint())
            } label: {
                Label("Create a tour", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.indigo)
            }
            .buttonStyle(.plain)  // keeps our capsule look instead of the List row's tint
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(colors: [.teal, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    private var howItWorks: some View {
        HStack(alignment: .top, spacing: 8) {
            step("mappin.and.ellipse", "Pick a spot")
            step("text.bubble.fill", "Stories are written and recorded")
            step("figure.walk", "Walk with your phone locked")
        }
        .padding(.vertical, 4)
    }

    private func step(_ systemImage: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("No tours yet")
                    .font(.headline)
                Text("Create one, keep it, and it shows up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .textCase(nil)  // List headers are UPPERCASE by default
    }
}

/// One tour on the home screen: a mini map of the route plus stops, minutes, and date.
struct TourCard: View {
    let tour: TourLibrary.SavedTour
    let showDate: Bool

    var body: some View {
        HStack(spacing: 14) {
            RouteThumbnail(route: tour.route)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(tour.name)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    Label("^[\(tour.stopCount) stop](inflect: true)", systemImage: "mappin")
                    Label("\(tour.minutes) min", systemImage: "headphones")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if showDate {
                    Text(tour.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small non-interactive map of the loop: blue line and dots, framed automatically.
struct RouteThumbnail: View {
    let route: [CLLocationCoordinate2D]

    /// Region around the stops with a margin (`.automatic` frames thumbnails too loosely).
    private var region: MKCoordinateRegion {
        let lats = route.map(\.latitude), lons = route.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion()
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.5, 0.003),
                                   longitudeDelta: max((maxLon - minLon) * 1.5, 0.003)))
    }

    var body: some View {
        // `interactionModes: []` turns off pan/zoom so the row stays tappable as a whole.
        Map(initialPosition: .region(region), interactionModes: []) {
            MapPolyline(coordinates: route + route.prefix(1))
                .stroke(.blue, lineWidth: 2)
            ForEach(Array(route.enumerated()), id: \.offset) { _, coordinate in
                Annotation("", coordinate: coordinate) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))  // no shop icons at thumbnail size
        .allowsHitTesting(false)
    }
}

/// Walk mode for any pack folder (bundled or downloaded), using the existing WalkView unchanged.
struct TourWalkView: View {
    // @State keeps the same WalkSession while this screen is on the stack.
    @State private var session: WalkSession

    init(folder: URL) {
        _session = State(initialValue: WalkSession(loader: TourLoader(folder: folder), name: folder.lastPathComponent))
    }

    var body: some View {
        WalkView(session: session)
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { session.stop() }  // leaving the screen ends the walk and turns GPS off
    }
}

#Preview("Home") {
    HomeView()
}

#Preview("Tour card") {
    List {
        if let folder = TourLoader.bundled(route: "mexicali2")?.folder,
           let tour = TourLibrary.summary(of: folder, name: "Mexicali downtown") {
            TourCard(tour: tour, showDate: true)
        }
    }
}

#Preview("Walk a pack") {
    NavigationStack {
        if let folder = TourLoader.bundled(route: "mexicali2")?.folder {
            TourWalkView(folder: folder)
        }
    }
}
