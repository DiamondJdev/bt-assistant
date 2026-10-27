import Foundation
import Observation

/// UI state that only the Focus screen uses. Shared data belongs on `AppStore`.
/// Holds the simulated playback position; the real source has no position API.
@MainActor
@Observable
public final class FocusScreenState {
    static let trackCount = 18
    static let trackLength = 221
    static let barCount = 32

    /// Zero-based sample track.
    var track = 3
    /// Seconds into the track.
    var position = 84
    /// Sample playback only; a real source reports its own.
    var samplePlaying = true

    public init() {}

    var progress: Double { Double(position) / Double(Self.trackLength) }
    var positionLabel: String { ActiveFocusSession.clock(position) }
    var lengthLabel: String { ActiveFocusSession.clock(Self.trackLength) }

    /// One second of playback. Wraps to the next track at the end.
    func advance(playing: Bool) {
        guard playing else { return }
        if position + 1 >= Self.trackLength {
            position = 0
            track = (track + 1) % Self.trackCount
        } else {
            position += 1
        }
    }

    func skip(by offset: Int) {
        track = (track + offset + Self.trackCount) % Self.trackCount
        position = 0
    }

    /// Bar heights for the level meter, 4pt flat when stopped.
    func levels(playing: Bool) -> [Double] {
        (0..<Self.barCount).map { i in
            guard playing else { return 4 }
            let base = abs(sin(Double(i) * 0.7 + Double(position) * 0.9) * cos(Double(i) * 0.23))
            return 6 + (28 * base).rounded()
        }
    }
}
