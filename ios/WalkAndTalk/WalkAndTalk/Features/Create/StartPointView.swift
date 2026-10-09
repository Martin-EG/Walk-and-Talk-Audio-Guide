//
//  StartPointView.swift
//  WalkAndTalk
//
//  Step 1: pick where the tour starts, by tapping the map or searching an address.
//

import MapKit
import SwiftUI

struct StartPointView: View {
    @Environment(AppModel.self) private var model
    @State private var pin: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32.661938, longitude: -115.489149),
                           latitudinalMeters: 3000, longitudinalMeters: 3000)))
    @State private var search = AddressSearch()
    // @FocusState tracks whether the search field has the keyboard (to show/hide suggestions).
    @FocusState private var searchFocused: Bool

    var body: some View {
        // MapReader gives `proxy`, which converts a tap's screen point into a coordinate.
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let pin {
                    Marker("Start", systemImage: "figure.walk", coordinate: pin)
                }
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    pin = coordinate
                    searchFocused = false
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
        }
        .safeAreaInset(edge: .top) { searchBox }
        .safeAreaInset(edge: .bottom) { nextButton }
        .navigationTitle("Start point")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search an address or place", text: $search.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if searchFocused, !search.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // MKLocalSearchCompletion is an NSObject, so it's Hashable and can be its own id.
                    ForEach(search.results.prefix(5), id: \.self) { result in
                        Button {
                            Task { await choose(result) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                        if result != search.results.prefix(5).last { Divider() }
                    }
                }
                .padding(.horizontal, 8)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 4)
            }

            if let message = search.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).padding(.top, 4)
            }
        }
        .padding()
        .background(.bar)
    }

    private var nextButton: some View {
        VStack(spacing: 8) {
            Text(pin == nil ? "Tap the map or search to set the start point." : "Tap the map to move the pin.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                if let pin { model.path.append(.options(lat: pin.latitude, lon: pin.longitude)) }
            } label: {
                Text("Next").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(pin == nil)
        }
        .padding()
        .background(.bar)
    }

    private func choose(_ result: MKLocalSearchCompletion) async {
        guard let coordinate = await search.coordinate(for: result) else { return }
        pin = coordinate
        camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
        searchFocused = false
    }
}

#Preview {
    NavigationStack { StartPointView() }
        .environment(AppModel())
}
