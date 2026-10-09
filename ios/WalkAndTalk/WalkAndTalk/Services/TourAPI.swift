//
//  TourAPI.swift
//  WalkAndTalk
//
//  Talks to the tour server (server/app.py): create a tour, poll its status, fetch the
//  stop preview, download the finished pack. Every request carries the shared API key.
//

import Foundation

struct TourAPI {
    var baseURL = Secrets.serverURL
    var apiKey = Secrets.apiKey

    /// GET /tours/{id}. `status` is one of: queued, finding_places, writing_stories, recording, done, failed.
    struct Status: Decodable {
        let status: String
        let progress: String
        let stopsFound: Int?
        let error: String?
    }

    struct PreviewStop: Decodable, Identifiable {
        let id: String
        let name: String
        let lat: Double
        let lon: Double
    }

    // `LocalizedError` gives each case a human message via `error.localizedDescription`.
    enum Failure: LocalizedError {
        case unreachable
        case alreadyBuilding(tourID: String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .unreachable: "Can't reach the tour server. Check your internet connection and try again."
            case .alreadyBuilding: "A tour is already building."
            case .server(let message): message
            }
        }
    }

    func createTour(lat: Double, lon: Double, radiusM: Int, maxStops: Int, lang: String) async throws -> String {
        struct Body: Encodable { let lat: Double, lon: Double, radius_m: Int, max_stops: Int, lang: String }
        struct Created: Decodable { let tourId: String }
        var request = request("tours")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(lat: lat, lon: lon, radius_m: radiusM, max_stops: maxStops, lang: lang))
        return try decode(Created.self, from: await send(request)).tourId
    }

    func status(_ tourID: String) async throws -> Status {
        try decode(Status.self, from: await send(request("tours/\(tourID)")))
    }

    func preview(_ tourID: String) async throws -> [PreviewStop] {
        struct Preview: Decodable { let stops: [PreviewStop] }
        return try decode(Preview.self, from: await send(request("tours/\(tourID)/preview"))).stops
    }

    /// Downloads the pack zip to a temporary file and returns its location.
    func downloadPack(_ tourID: String) async throws -> URL {
        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await URLSession.shared.download(for: request("tours/\(tourID)/pack"))
        } catch {
            throw Self.mapTransport(error)
        }
        try check(response, body: (try? Data(contentsOf: tempURL)) ?? Data())
        // Move it somewhere we own right away; URLSession may clean up its own temp file.
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(tourID).zip")
        try? FileManager.default.removeItem(at: zipURL)
        try FileManager.default.moveItem(at: tempURL, to: zipURL)
        return zipURL
    }

    // MARK: Plumbing

    private func request(_ path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 30)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Self.mapTransport(error)
        }
        try check(response, body: data)
        return data
    }

    /// No answer at all: either the task was cancelled (view went away) or the server is unreachable.
    private static func mapTransport(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return CancellationError()
        }
        return Failure.unreachable
    }

    /// Turns a non-2xx answer into a Failure, using FastAPI's {"detail": ...} body.
    private func check(_ response: URLResponse, body: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200..<300).contains(code) else { return }
        // `detail` is a string, a {message, tour_id} object (409), or a list of validation errors (422).
        let detail = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["detail"]
        if let object = detail as? [String: Any] {
            if code == 409, let tourID = object["tour_id"] as? String { throw Failure.alreadyBuilding(tourID: tourID) }
            if let message = object["message"] as? String { throw Failure.server(message) }
        }
        if code == 401 { throw Failure.server("The tour server rejected this app's API key.") }
        if let message = detail as? String { throw Failure.server(message) }
        if let list = detail as? [[String: Any]], let message = list.first?["msg"] as? String {
            throw Failure.server(message)
        }
        throw Failure.server("The tour server answered with error \(code).")
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // stops_found -> stopsFound
        return try decoder.decode(type, from: data)
    }
}
