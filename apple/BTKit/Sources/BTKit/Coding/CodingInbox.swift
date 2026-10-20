import Foundation
import os
import SwiftData

/// Moves heartbeat files that editors drop in `~/.bt/inbox/` into SwiftData.
@MainActor
final class CodingInbox {
    let directory: URL
    /// Called after an ingest that inserted at least one heartbeat.
    var onIngest: (() -> Void)?

    private let context: ModelContext
    private let now: @Sendable () -> Date
    private var source: (any DispatchSourceFileSystemObject)?

    private static let logger = Logger(subsystem: "BTKit", category: "Coding")

    init(directory: URL, context: ModelContext, now: @escaping @Sendable () -> Date) {
        self.directory = directory
        self.context = context
        self.now = now
    }

    /// `~/.bt/inbox` in the real home. Inside the sandbox `NSHomeDirectory()`
    /// is the app's container, so read the home from the password database.
    static func defaultDirectory() -> URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir.map { String(cString: $0) } } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".bt/inbox", isDirectory: true)
    }

    /// Ingests every `.jsonl` file and any `.processing` file a crash left behind.
    /// Each `.jsonl` is renamed first, so the editor's next append starts a new
    /// file instead of landing in one being read. Returns the beats inserted.
    @discardableResult
    func ingest() -> Int {
        let files = FileManager.default
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("Could not create inbox \(self.directory.path): \(error.localizedDescription)")
            return 0
        }
        for file in contents() where file.pathExtension == "jsonl" {
            let claimed = directory.appendingPathComponent(
                "\(file.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).processing"
            )
            do {
                try files.moveItem(at: file, to: claimed)
            } catch {
                Self.logger.error("Could not claim \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        var inserted = 0
        for file in contents() where file.pathExtension == "processing" {
            inserted += ingestFile(file)
        }
        if inserted > 0 { onIngest?() }
        return inserted
    }

    /// Watches the directory for new files. Appends to an existing file don't
    /// fire, but ingest removes every file, so each append creates a new one.
    func startWatching() {
        ingest()
        guard source == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Self.logger.error("Could not watch inbox \(self.directory.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { _ = self?.ingest() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func contents() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// Inserts one claimed file's beats and deletes it. A file that can't be read
    /// or saved stays for the next run.
    private func ingestFile(_ file: URL) -> Int {
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            Self.logger.error("Could not read \(file.lastPathComponent): \(error.localizedDescription)")
            return 0
        }
        let (beats, skipped) = parseHeartbeats(text, now: now())
        if skipped > 0 {
            Self.logger.warning("Skipped \(skipped) bad heartbeat lines in \(file.lastPathComponent)")
        }
        for beat in beats {
            context.insert(CodingHeartbeat(beat))
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            Self.logger.error("Could not save heartbeats from \(file.lastPathComponent): \(error.localizedDescription)")
            return 0
        }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            Self.logger.error("Could not delete \(file.lastPathComponent); its beats may be read again: \(error.localizedDescription)")
        }
        return beats.count
    }
}
