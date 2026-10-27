import Foundation
import SwiftData

/// One editor heartbeat. Attributes are defaulted so the model stays
/// CloudKit-compatible.
@Model
final class CodingHeartbeat {
    var timestamp: Date = Date.distantPast
    var editor: String = ""
    var project: String = ""
    var language: String = ""

    init(timestamp: Date, editor: String, project: String, language: String) {
        self.timestamp = timestamp
        self.editor = editor
        self.project = project
        self.language = language
    }

    convenience init(_ beat: Heartbeat) {
        self.init(timestamp: beat.timestamp, editor: beat.editor, project: beat.project, language: beat.language)
    }

    var beat: Heartbeat {
        Heartbeat(timestamp: timestamp, editor: editor, project: project, language: language)
    }
}

struct Heartbeat: Equatable, Sendable {
    var timestamp: Date
    var editor: String
    var project: String
    var language: String
}

private struct HeartbeatLine: Decodable {
    let ts: Double
    let editor: String
    let project: String
    let language: String
}

/// 2020-01-01T00:00:00Z.
private let earliestHeartbeat = Date(timeIntervalSince1970: 1_577_836_800)

/// Parses inbox JSON lines. Blank lines are ignored; lines that don't decode
/// or whose fields are out of range count as skipped.
func parseHeartbeats(_ text: String, now: Date) -> (beats: [Heartbeat], skipped: Int) {
    let decoder = JSONDecoder()
    var beats: [Heartbeat] = []
    var skipped = 0
    for line in text.split(whereSeparator: \.isNewline) where !line.allSatisfy(\.isWhitespace) {
        guard let raw = try? decoder.decode(HeartbeatLine.self, from: Data(line.utf8)),
              let beat = validated(raw, now: now)
        else {
            skipped += 1
            continue
        }
        beats.append(beat)
    }
    return (beats, skipped)
}

private func validated(_ raw: HeartbeatLine, now: Date) -> Heartbeat? {
    let timestamp = Date(timeIntervalSince1970: raw.ts)
    guard timestamp >= earliestHeartbeat, timestamp <= now + 5 * 60,
          (1...200).contains(raw.project.count),
          (1...50).contains(raw.language.count),
          !raw.editor.isEmpty
    else { return nil }
    return Heartbeat(timestamp: timestamp, editor: raw.editor, project: raw.project, language: raw.language)
}
