//
//  TriggerLog.swift
//  WalkAndTalk
//
//  Field-test log: appends one CSV line per walk event to Documents/trigger-log.csv, so a
//  missed, early, or late trigger can be diagnosed after the walk.
//
//  Events:
//    walk_start / walk_end   bracket each walk (the file keeps every walk, newest last)
//    enter                   first fix inside a stop's radius, at any accuracy
//    trigger                 the engine picked this stop to play
//    closest                 at walk end, per stop: nearest fix seen and its accuracy
//
//  enter vs trigger shows trigger lag; closest explains stops that never played.
//

import Foundation

final class TriggerLog {
    static let header = "time,event,stop_id,stop_name,distance_m,accuracy_m"

    /// Local wall-clock time, so rows line up with notes and video timestamps.
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // fixed format regardless of phone settings
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    let url: URL

    // Per-walk state, keyed by stop id.
    private var entered: Set<String> = []
    private var closest: [String: (distanceM: Double, accuracyM: Double)] = [:]

    // `URL.documentsDirectory`: the app's private Documents folder, kept across launches.
    init(url: URL = URL.documentsDirectory.appending(path: "trigger-log.csv")) {
        self.url = url
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path()) }

    func walkStarted(at time: Date = .now) {
        entered = []
        closest = [:]
        write(time, "walk_start")
    }

    /// Call for every fix, including the inaccurate ones the engine ignores.
    func observe(stops: [Stop], lat: Double, lon: Double, accuracyM: Double, time: Date) {
        guard accuracyM >= 0 else { return }   // negative = invalid fix (CoreLocation convention)
        for stop in stops {
            let d = ProximityEngine.distanceM(lat, lon, stop.lat, stop.lon)
            // `map` on an optional runs only when a value exists; `?? true` covers "none yet".
            if closest[stop.id].map({ d < $0.distanceM }) ?? true {
                closest[stop.id] = (d, accuracyM)
            }
            if d <= stop.radiusM, !entered.contains(stop.id) {
                entered.insert(stop.id)
                write(time, "enter", stop, d, accuracyM)
            }
        }
    }

    func triggered(_ stop: Stop, lat: Double, lon: Double, accuracyM: Double, time: Date) {
        let d = ProximityEngine.distanceM(lat, lon, stop.lat, stop.lon)
        write(time, "trigger", stop, d, accuracyM)
    }

    func walkEnded(stops: [Stop], at time: Date = .now) {
        for stop in stops {
            if let c = closest[stop.id] {
                write(time, "closest", stop, c.distanceM, c.accuracyM)
            }
        }
        write(time, "walk_end")
    }

    /// Full file contents, for tests and quick checks.
    func contents() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: Writing

    private func write(_ time: Date, _ event: String, _ stop: Stop? = nil,
                       _ distanceM: Double? = nil, _ accuracyM: Double? = nil) {
        let fields = [
            Self.timeFormat.string(from: time),
            event,
            stop?.id ?? "",
            stop.map { csvQuoted($0.name) } ?? "",
            distanceM.map { String(format: "%.1f", $0) } ?? "",
            accuracyM.map { String(format: "%.1f", $0) } ?? "",
        ]
        append(fields.joined(separator: ",") + "\n")
    }

    private func append(_ line: String) {
        if !exists {
            FileManager.default.createFile(atPath: url.path(), contents: Data((Self.header + "\n").utf8))
        }
        // Open, append, close each time: a few lines per walk, and nothing lost if the app dies.
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }   // `defer` runs when the function exits, like `finally`
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private func csvQuoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
