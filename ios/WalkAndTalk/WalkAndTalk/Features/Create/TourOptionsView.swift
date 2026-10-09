//
//  TourOptionsView.swift
//  WalkAndTalk
//
//  Step 2: how far to search and how many stops, then ask the server to build the tour.
//

import MapKit
import SwiftUI

struct TourOptionsView: View {
    let lat: Double
    let lon: Double

    @Environment(AppModel.self) private var model
    @State private var radius = 600.0
    @State private var stops = 8
    @State private var lang = "en"
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .automatic

    private var center: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }

    /// Frames the whole search circle with a little margin.
    private func cameraFor(_ radius: Double) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: center, latitudinalMeters: radius * 2.4, longitudinalMeters: radius * 2.4))
    }

    var body: some View {
        Form {
            Section {
                Map(position: $camera) {
                    Marker("Start", systemImage: "figure.walk", coordinate: center)
                    MapCircle(center: center, radius: radius)
                        .foregroundStyle(.blue.opacity(0.15))
                        .stroke(.blue, lineWidth: 1)
                }
                .frame(height: 220)
                .allowsHitTesting(false)
                .listRowInsets(EdgeInsets())
                // `initial: true` also runs it once when the screen appears; afterwards on every slider change.
                .onChange(of: radius, initial: true) { camera = cameraFor(radius) }
            }

            Section("Search radius: \(Int(radius)) m") {
                Slider(value: $radius, in: 200...2000, step: 100) {
                    Text("Radius")
                } minimumValueLabel: {
                    Text("200 m").font(.caption)
                } maximumValueLabel: {
                    Text("2 km").font(.caption)
                }
            }

            Section("Stops") {
                Stepper("\(stops) stops", value: $stops, in: 3...12)
            }

            Section("Language") {
                Picker("Language", selection: $lang) {
                    Text("English").tag("en")
                    Text("Español").tag("es")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if isCreating { ProgressView() } else { Text("Create tour").bold() }
                        Spacer()
                    }
                }
                .disabled(isCreating)
            } footer: {
                Text("Building takes a few minutes. If the area has fewer places, the tour uses what it finds.")
            }
        }
        // An alert is always on screen, unlike a section below the fold. The Binding turns
        // "errorMessage is set" into the true/false the alert needs, and clears it on dismiss.
        .alert("Couldn't create the tour", isPresented: Binding(get: { errorMessage != nil },
                                                               set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationTitle("Tour options")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }  // runs when the function exits, however it exits
        do {
            let tourID = try await model.api.createTour(lat: lat, lon: lon, radiusM: Int(radius),
                                                        maxStops: stops, lang: lang)
            model.path.append(.building(tourID: tourID))
        } catch TourAPI.Failure.alreadyBuilding(let tourID) {
            model.path.append(.building(tourID: tourID))  // one build per key: watch the one in progress
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { TourOptionsView(lat: 32.661938, lon: -115.489149) }
        .environment(AppModel())
}
