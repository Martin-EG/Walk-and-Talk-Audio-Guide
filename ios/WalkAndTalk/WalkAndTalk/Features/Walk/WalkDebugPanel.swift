//
//  WalkDebugPanel.swift
//  WalkAndTalk
//
//  Field-test info: distance to the next stop, GPS accuracy, and location permission.
//

import CoreLocation
import SwiftUI

struct WalkDebugPanel: View {
    let session: WalkSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nearest = session.nearestStop {
                Text("Nearest unplayed: \(nearest.stop.name)")
                Text("Distance: \(Int(nearest.distanceM)) m (radius \(Int(nearest.stop.radiusM)) m)")
            } else {
                Text(session.isWalking ? "Nearest unplayed: waiting for GPS…" : "Nearest unplayed: not walking")
            }
            if let location = session.tracker.lastLocation {
                Text("GPS accuracy: ±\(Int(location.horizontalAccuracy)) m (ignored above \(Int(ProximityEngine.maxAccuracyM)) m)")
            }
            Text("Permission: \(permissionText)")
        }
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
    }

    private var permissionText: String {
        switch session.tracker.authorization {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using (OK if you start the walk in the app)"
        case .denied, .restricted: "Denied: enable in Settings > Privacy > Location"
        case .notDetermined: "Not asked yet"
        @unknown default: "Unknown"
        }
    }
}

#Preview {
    WalkDebugPanel(session: WalkSession())
        .padding()
}
