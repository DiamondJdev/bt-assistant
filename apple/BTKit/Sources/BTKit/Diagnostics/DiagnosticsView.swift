#if BT_DIAGNOSTICS
import SwiftUI
import UniformTypeIdentifiers

/// Developer → Diagnostics… (⌥⌘I). Only in builds with `BT_DIAGNOSTICS`.
public struct DiagnosticsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some Commands {
        CommandMenu("Developer") {
            Button("Diagnostics…") { openWindow(id: DiagnosticsView.windowID) }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

/// Live view of the recorder: latest turn, client timings, recent turns and events.
public struct DiagnosticsView: View {
    public static let windowID = "diagnostics"

    private let serverAddress: String
    @State private var capture = DiagnosticsRecorder.shared.enabled
    @State private var traces = DiagnosticsRecorder.shared.tracesEnabled
    @State private var exporting = false
    @State private var document = DiagnosticsDocument(data: Data())
    @State private var error: String?

    public init(serverAddress: String) {
        self.serverAddress = serverAddress
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            header
            if let error { Text(error).foregroundStyle(.red) }
            // Refreshes twice a second, not on every streamed delta.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                content(DiagnosticsRecorder.shared.snapshot())
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 560)
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText,
                      defaultFilename: "bt-diagnostics.jsonl") { result in
            if case .failure = result {
                error = "Could not export diagnostics. Choose a writable folder and try again."
            }
        }
    }

    private var controls: some View {
        HStack {
            Toggle("Capture", isOn: $capture)
                .onChange(of: capture) { DiagnosticsRecorder.shared.enabled = capture }
            Toggle("Instruments signposts", isOn: $traces)
                .onChange(of: traces) { DiagnosticsRecorder.shared.tracesEnabled = traces }
            Spacer()
            Button("Clear") { DiagnosticsRecorder.shared.clear() }
            Button("Export JSONL…", action: export)
        }
    }

    private var header: some View {
        let build = BuildMetadata.current
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(build.mode) · \(build.sha.prefix(12)) · BT \(build.appVersion) · \(build.osVersion)")
                .font(.caption.monospaced())
            Text("Server: \(DiagnosticsFormat.safeServer(serverAddress))").font(.caption)
            Text("Stays on this Mac. Exports hold timings and counts only: no message text, tool arguments or results, or server address.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func content(_ snapshot: DiagnosticSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let latest = snapshot.turns.last {
                    DiagnosticsTurnDetails(turn: latest)
                } else {
                    Text("Send a chat message to capture a turn.").foregroundStyle(.secondary)
                }
                performance(snapshot.performance)
                recentTurns(snapshot.turns)
                timeline(snapshot.events)
            }
        }
    }

    private func performance(_ entries: [DiagnosticPerformance]) -> some View {
        GroupBox("Client work · last 128 samples each") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries, id: \.operation) { entry in
                    Text("\(entry.operation.rawValue): latest \(DiagnosticsFormat.ms(entry.latestMs)) · p95 \(DiagnosticsFormat.ms(entry.p95Ms)) · max \(DiagnosticsFormat.ms(entry.maximumMs)) · n=\(entry.count)")
                        .font(.caption.monospaced())
                }
                Text("Time spent in BT's own code, not time to draw. For drawing, hitches, CPU and memory use Instruments (SwiftUI, Hangs, Time Profiler, Allocations) on a `make build MODE=profile` app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recentTurns(_ turns: [DiagnosticTurn]) -> some View {
        GroupBox("Recent turns · last 50") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(turns.reversed()) { turn in
                    HStack {
                        Text(turn.id.prefix(8)).font(.caption.monospaced())
                        Text(turn.status.rawValue)
                        Spacer()
                        Text("total \(DiagnosticsFormat.ms(turn.elapsedMs))")
                        Text("first text \(DiagnosticsFormat.ms(turn.firstTextMs))")
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeline(_ events: [DiagnosticEvent]) -> some View {
        GroupBox("Timeline · last 500 events") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(events.reversed()) { event in
                    Text("\(event.timestamp.formatted(date: .omitted, time: .standard))  \(event.turnID.prefix(8))  \(event.kind.rawValue)")
                        .font(.caption.monospaced())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func export() {
        do {
            document = DiagnosticsDocument(data: try DiagnosticsRecorder.shared.export())
            error = nil
            exporting = true
        } catch {
            self.error = "Could not encode diagnostics. Clear the capture and try again."
        }
    }
}

/// The latest turn: client timings plus whatever the server reported per model call.
struct DiagnosticsTurnDetails: View {
    let turn: DiagnosticTurn

    var body: some View {
        GroupBox("Latest turn") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(turn.status.rawValue) · total \(DiagnosticsFormat.ms(turn.elapsedMs)) · first visible text \(DiagnosticsFormat.ms(turn.firstTextMs)) · \(turn.chunks) text updates")
                Text("Module context: \(turn.contextChars) / \(contextSnapshotBudget) characters · \(turn.omittedSnapshots) snapshots left out")
                    .font(.caption)
                if let server = turn.server {
                    Text("Server \(DiagnosticsFormat.ms(server.durationMs)) · waiting on app tools \(DiagnosticsFormat.ms(server.toolWaitMs)) · \(DiagnosticsFormat.count(server.historyTurns)) history messages")
                        .font(.caption)
                    ForEach(server.calls ?? []) { call in
                        callDetails(call)
                    }
                } else {
                    Text("No server metrics. The server may predate diagnostics.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Tokens/s is output tokens over the whole call, so it includes prompt processing and network time. It is lower than the engine's generation speed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func callDetails(_ call: ModelCallMetrics) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(call.provider ?? "unknown") / \(call.model ?? "unknown") · \(call.status ?? "unknown")")
            Text("Tokens in \(DiagnosticsFormat.count(call.promptTokens)) · out \(DiagnosticsFormat.count(call.completionTokens)) · \(DiagnosticsFormat.rate(call.observedTokensPerSecond)) · \(DiagnosticsFormat.ms(call.durationMs))")
            Text("First output \(DiagnosticsFormat.ms(call.firstOutputMs)) · first visible text \(DiagnosticsFormat.ms(call.firstVisibleTextMs))")
            Text("Context \(DiagnosticsFormat.count(call.promptTokens)) / \(DiagnosticsFormat.count(call.contextLimit)) tokens\(call.contextPercent.map { String(format: " (%.1f%%)", $0) } ?? "") · output cap \(DiagnosticsFormat.count(call.outputLimit))")
        }
        .font(.caption)
        .padding(.vertical, 4)
    }
}

/// Formatting shared by the diagnostics views. Missing values read "unavailable", never zero.
enum DiagnosticsFormat {
    static func ms(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "unavailable" }
        return String(format: "%.1f ms", value)
    }

    static func count(_ value: Int?) -> String { value.map(String.init) ?? "unavailable" }

    static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.1f tokens/s", $0) } ?? "tokens/s unavailable"
    }

    /// Scheme, host and port only; drops any path, query or credentials.
    static func safeServer(_ address: String) -> String {
        guard let parts = URLComponents(string: address), let host = parts.host else { return "not set" }
        return "\(parts.scheme ?? "http")://\(host)" + (parts.port.map { ":\($0)" } ?? "")
    }
}

private struct DiagnosticsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif
