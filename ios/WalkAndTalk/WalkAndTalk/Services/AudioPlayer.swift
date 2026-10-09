//
//  AudioPlayer.swift
//  WalkAndTalk
//
//  Plays stop stories one after another. If you reach a stop while another story is playing,
//  the new one waits its turn, so stories never overlap.
//

import AVFoundation

// NSObject: AVAudioPlayerDelegate is an Objective-C protocol, like CLLocationManagerDelegate.
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    /// Called when a story actually starts playing (not when it's queued).
    var onStart: ((Stop) -> Void)?
    /// Called when the last queued story finishes (or fails) and nothing is left to play.
    var onIdle: (() -> Void)?

    private var queue: [(stop: Stop, url: URL)] = []
    private var player: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?

    /// Call once when the walk starts, while the app is on screen. The session stays active for
    /// the whole walk so iOS lets us start new stories later from the background.
    func begin() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback: plays with the silent switch on and with the screen locked.
        // .spokenAudio: tells iOS the content is speech.
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)

        // A phone call or Siri pauses us; resume the current story when it ends.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            // `[weak self]` avoids a retain cycle, like cleaning up a listener in useEffect.
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            MainActor.assumeIsolated {  // queue: .main means we're on the main thread
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.player?.play()
            }
        }
    }

    func enqueue(_ stop: Stop, url: URL) {
        queue.append((stop: stop, url: url))
        if player == nil {
            playNext()
        }
    }

    /// Stops the current story, drops anything queued, and releases the audio session.
    func end() {
        queue.removeAll()
        player?.stop()
        player = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func playNext() {
        guard !queue.isEmpty else {
            player = nil
            onIdle?()
            return
        }
        let next = queue.removeFirst()
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: next.url)
            newPlayer.delegate = self
            guard newPlayer.play() else {
                print("Could not start \(next.url.lastPathComponent)")
                playNext()
                return
            }
            player = newPlayer  // keep a reference, or the audio stops when it's freed
            onStart?(next.stop)
        } catch {
            print("Skipping \(next.stop.name): \(error.localizedDescription)")
            playNext()
        }
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        storyEnded(ObjectIdentifier(finished))
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ failed: AVAudioPlayer, error: Error?) {
        storyEnded(ObjectIdentifier(failed))
    }

    /// Hops to the main actor and moves the queue on, unless the walk was stopped meanwhile.
    nonisolated private func storyEnded(_ id: ObjectIdentifier) {
        Task { @MainActor in
            guard let player = self.player, ObjectIdentifier(player) == id else { return }
            self.playNext()
        }
    }
}
