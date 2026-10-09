//
//  LocationTracker.swift
//  WalkAndTalk
//
//  Wraps CLLocationManager: asks for permission, keeps GPS running with the screen locked,
//  and hands every fix to `onFix`.
//

import CoreLocation
import Observation

// @Observable: SwiftUI re-renders views that read these properties when they change
// (like state in a React store, without needing setState).
// NSObject: CLLocationManagerDelegate is an Objective-C protocol, so the class must inherit NSObject.
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var lastLocation: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    /// Called for every new fix, foreground or background. WalkSession plugs the proximity
    /// engine in here instead of reacting in a view, because views don't update while locked.
    @ObservationIgnored var onFix: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5                       // meters between updates
        manager.activityType = .fitness                  // pedestrian movement
        manager.pausesLocationUpdatesAutomatically = false  // never let iOS pause us mid-walk
        authorization = manager.authorizationStatus
    }

    func start() {
        // First launch shows "Allow While Using App"; iOS asks about "Always" later on its own.
        // Background updates work with either, because they start while the app is on screen.
        manager.requestAlwaysAuthorization()
        manager.allowsBackgroundLocationUpdates = true   // needs the "location" background mode (Info.plist)
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        lastLocation = nil
    }

    // MARK: CLLocationManagerDelegate
    //
    // The delegate methods are declared `nonisolated` because CoreLocation calls them from
    // Objective-C. It calls them on the thread that created the manager, which is the main
    // thread here, so `MainActor.assumeIsolated` safely lets us touch main-actor state.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            for location in locations {
                lastLocation = location
                onFix?(location)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Usually transient (no fix yet, e.g. indoors). CoreLocation keeps trying on its own.
        print("Location error: \(error.localizedDescription)")
    }
}
