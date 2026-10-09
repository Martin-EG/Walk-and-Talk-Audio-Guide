//
//  AppModel.swift
//  WalkAndTalk
//
//  App-wide state: the navigation stack, the server client, and the saved-tours list.
//

import Foundation
import Observation

/// Every screen you can push. The NavigationStack's path is an array of these, so going
/// "back to the start point" is just `path = [.startPoint()]` (like setting a router's history).
enum Route: Hashable {
    /// `visit` makes each trip to the start point a new screen (HomeView applies it with `.id`),
    /// so "Start again" begins with an empty map instead of the previous pin and search.
    case startPoint(visit: UUID = UUID())
    case options(lat: Double, lon: Double)
    case building(tourID: String)
    case review(tourID: String)
    case walk(folder: URL)
}

@Observable
final class AppModel {
    var path: [Route] = []
    private(set) var savedTours: [TourLibrary.SavedTour] = []

    @ObservationIgnored let api = TourAPI()
    @ObservationIgnored let library = TourLibrary()

    init() {
        library.removeUnkept()
        refresh()
    }

    func refresh() {
        savedTours = library.savedTours()
    }

    func delete(_ tour: TourLibrary.SavedTour) {
        library.delete(tour.id)
        refresh()
    }
}
