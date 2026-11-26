import AVFoundation
import Combine
import Foundation

/// Keeps only the newest scrub position. A paused seek displays a frame without
/// decoding and playing a second recording alongside the main player.
final class RecordingPreview: ObservableObject {
    let player = AVPlayer()

    private struct Target {
        let name: String
        let url: URL
        let offset: Double
    }

    private var currentName = ""
    private var pending: Target?
    private var seekInFlight = false
    private var scheduled: DispatchWorkItem?
    private var lastSeek = Date.distantPast
    private var generation = 0

    func request(name: String, url: URL, offset: Double) {
        pending = Target(name: name, url: url, offset: offset)
        schedule()
    }

    func clear() {
        generation += 1
        scheduled?.cancel()
        scheduled = nil
        pending = nil
        seekInFlight = false
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.replaceCurrentItem(with: nil)
        currentName = ""
    }

    private func schedule() {
        guard pending != nil, !seekInFlight, scheduled == nil else { return }
        let delay = max(0, 0.18 - Date().timeIntervalSince(lastSeek))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scheduled = nil
            self.issueSeek()
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func issueSeek() {
        guard let target = pending, !seekInFlight else { return }
        pending = nil
        if currentName != target.name {
            player.replaceCurrentItem(with: AVPlayerItem(url: target.url))
            currentName = target.name
        }
        player.pause()
        player.isMuted = true
        seekInFlight = true
        lastSeek = Date()
        let requestGeneration = generation
        let point = CMTime(seconds: target.offset, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
        player.seek(to: point, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == requestGeneration else { return }
                self.seekInFlight = false
                self.schedule()
            }
        }
    }
}
