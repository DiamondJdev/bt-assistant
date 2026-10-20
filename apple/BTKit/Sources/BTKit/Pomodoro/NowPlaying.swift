import Foundation
import Observation

public struct NowPlayingTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var artwork: Data?
    public var isPlaying: Bool

    public init(title: String, artist: String, artwork: Data?, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.isPlaying = isPlaying
    }
}

public enum NowPlayingStatus: Equatable, Sendable {
    case notRunning, notPermitted, stopped, playing(NowPlayingTrack)

    public var message: String? {
        switch self {
        case .notRunning: "Music isn't open."
        case .notPermitted: "Allow BT to control Music in System Settings › Privacy & Security › Automation."
        case .stopped: "Nothing playing."
        case .playing: nil
        }
    }
}

/// The track already playing in a music app. The Mac app supplies one backed by Music.
@MainActor
public protocol NowPlayingSource: AnyObject, Observable {
    var status: NowPlayingStatus { get }
    func playPause()
    func next()
    func previous()
    func openMusic()
}
