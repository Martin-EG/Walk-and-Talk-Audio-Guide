//
//  BuildingView.swift
//  WalkAndTalk
//
//  Step 3: poll the server every 3 seconds and show each build step, then download the pack.
//

import SwiftUI

struct BuildingView: View {
    let tourID: String

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var status: TourAPI.Status?
    @State private var preview: [TourAPI.PreviewStop] = []
    @State private var downloading = false
    @State private var warning: String?   // temporary: server unreachable, still retrying
    @State private var failure: String?   // final: build failed, no places, download failed

    private static let steps = [
        (key: "finding_places", title: "Finding places"),
        (key: "writing_stories", title: "Writing stories"),
        (key: "recording", title: "Recording audio"),
        (key: "downloading", title: "Downloading"),
    ]

    /// Index of the step in progress; -1 while queued, steps.count when everything is done.
    private var currentStep: Int {
        if downloading { return 3 }
        guard let status else { return -1 }
        if status.status == "done" { return 3 }
        return Self.steps.firstIndex { $0.key == status.status } ?? -1
    }

    var body: some View {
        List {
            Section {
                Text("This usually takes a few minutes. You can leave the app; it checks again when you come back.")
                    .foregroundStyle(.secondary)
            }

            Section("Progress") {
                if status?.status == "queued" {
                    Label("Waiting for the server…", systemImage: "hourglass")
                }
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        stepIcon(index).frame(width: 24)
                        Text(step.title)
                        Spacer()
                        if index == currentStep, step.key != "downloading", let progress = status?.progress, !progress.isEmpty {
                            Text(progress).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !preview.isEmpty {
                Section("^[\(preview.count) stop](inflect: true) found") {
                    ForEach(Array(preview.enumerated()), id: \.element.id) { index, stop in
                        Text("\(index + 1). \(stop.name)")
                    }
                }
            }

            if let warning {
                Section {
                    Label(warning, systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
                }
            }

            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Start again") { model.path = [.startPoint()] }
                }
            }
        }
        .navigationTitle("Building your tour")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { model.path = [] }
            }
        }
        // `.task(id:)` restarts whenever scenePhase changes and is cancelled when the view goes away.
        // Going to the background cancels polling; coming back to .active starts it again.
        .task(id: scenePhase) {
            if scenePhase == .active { await poll() }
        }
    }

    @ViewBuilder
    private func stepIcon(_ index: Int) -> some View {
        if index < currentStep {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if index == currentStep, failure == nil {
            ProgressView()
        } else if index == currentStep {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    private func poll() async {
        while !Task.isCancelled, failure == nil {
            do {
                let latest = try await model.api.status(tourID)
                status = latest
                warning = nil
                if preview.isEmpty, latest.stopsFound != nil {
                    preview = (try? await model.api.preview(tourID)) ?? []
                }
                switch latest.status {
                case "done":
                    await download()
                    return
                case "failed":
                    failure = latest.error ?? "The tour couldn't be built."
                    return
                default:
                    break
                }
            } catch is CancellationError {
                return
            } catch TourAPI.Failure.unreachable {
                warning = "Can't reach the tour server. Retrying…"
            } catch {
                failure = error.localizedDescription
                return
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func download() async {
        downloading = true
        defer { downloading = false }
        do {
            let zip = try await model.api.downloadPack(tourID)
            try model.library.install(zip: zip, tourID: tourID)
            // Replace this screen with the review, so Back can't return to a finished build.
            model.path.removeLast()
            model.path.append(.review(tourID: tourID))
        } catch is CancellationError {
            return  // app went to the background; the next poll downloads again
        } catch {
            failure = "Couldn't download the tour: \(error.localizedDescription)"
        }
    }
}

// Polls the server in Secrets.swift: shows live progress if it's running locally,
// otherwise the "Can't reach the tour server" or "No tour with that id" message.
#Preview {
    NavigationStack { BuildingView(tourID: "preview") }
        .environment(AppModel())
}
