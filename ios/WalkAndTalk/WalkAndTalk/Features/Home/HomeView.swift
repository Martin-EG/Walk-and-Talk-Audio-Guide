//
//  HomeView.swift
//  WalkAndTalk
//
//  First screen: create a tour, or walk a saved one (or the bundled demo).
//  Owns the NavigationStack for the whole create -> build -> review -> walk flow.
//

import SwiftUI

struct HomeView: View {
    // Created once and handed to every screen through the environment (like a React context).
    @State private var model = AppModel()

    var body: some View {
        // `$model.path` is a two-way binding: pushing a screen appends to path, Back removes it.
        NavigationStack(path: $model.path) {
            List {
                Section {
                    Button {
                        model.path.append(.startPoint())
                    } label: {
                        Label("Create a tour", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                Section("Your tours") {
                    if model.savedTours.isEmpty {
                        Text("Tours you keep show up here and work offline.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.savedTours) { tour in
                        NavigationLink(value: Route.walk(folder: tour.folder)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tour.name)
                                Text("\(tour.stopCount) stops · \(tour.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in  // swipe left to delete
                        offsets.map { model.savedTours[$0] }.forEach(model.delete)
                    }
                }

                if let demo = TourLoader.bundled(route: "mexicali2") {
                    Section("Demo") {
                        NavigationLink("Mexicali demo walk", value: Route.walk(folder: demo.folder))
                    }
                }
            }
            .navigationTitle("Walk-and-Talk")
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

#Preview {
    HomeView()
}
