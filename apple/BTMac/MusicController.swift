import AppKit
import BTKit
import Observation
import os

/// Reads and controls the track playing in Music over Apple Events.
/// Never launches Music except from `openMusic()`.
@MainActor
@Observable
final class MusicController: NowPlayingSource {
    private(set) var status: NowPlayingStatus = .notRunning

    private nonisolated static let bundleID = "com.apple.Music"
    private nonisolated static let notPermitted = -1743
    private nonisolated static let logger = Logger(subsystem: "BTMac", category: "Music")

    // ponytail: observers live for the app's lifetime, so they're never removed.
    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    func openMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // ponytail: scripts run on the main actor (NSAppleScript isn't thread-safe and this keeps
    // results in order); a hung Music would stall the UI, move to a serial actor if that happens.
    func refresh() {
        status = Self.fetchStatus()
    }

    private func send(_ command: String) {
        if Self.isRunning { _ = Self.run("tell application \"Music\" to \(command)") }
        refresh()
    }

    private nonisolated static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func fetchStatus() -> NowPlayingStatus {
        guard isRunning else { return .notRunning }
        let script = """
        tell application "Music"
            set s to player state as string
            if s is "stopped" then return {s}
            return {s, name of current track, artist of current track}
        end tell
        """
        switch run(script) {
        case .failure(let error):
            return error.code == notPermitted ? .notPermitted : .stopped
        case .success(let result):
            guard result.numberOfItems >= 3,
                  let state = result.atIndex(1)?.stringValue, state != "stopped"
            else { return .stopped }
            let artwork = try? run("tell application \"Music\" to if (count of artworks of current track) > 0 then get data of artwork 1 of current track").get().data
            return .playing(NowPlayingTrack(
                title: result.atIndex(2)?.stringValue ?? "",
                artist: result.atIndex(3)?.stringValue ?? "",
                artwork: artwork,
                isPlaying: state == "playing"
            ))
        }
    }

    private struct ScriptError: Error {
        let code: Int
    }

    private static func run(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            let code = error?[NSAppleScript.errorNumber] as? Int ?? 0
            logger.error("Music script failed (\(code)): \(error?[NSAppleScript.errorMessage] as? String ?? "")")
            return .failure(ScriptError(code: code))
        }
        return .success(result)
    }
}
