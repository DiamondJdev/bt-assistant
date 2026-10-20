import SwiftUI

struct PomodoroView: View {
    @Bindable var module: PomodoroModule
    @State private var showingSettings = false

    init(module: PomodoroModule) {
        self.module = module
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                timer
                    .onChange(of: context.date) { module.tick() }
            }
            controls
            Spacer()
            if let source = module.nowPlaying {
                NowPlayingCard(source: source)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            Button("Durations", systemImage: "slider.horizontal.3") { showingSettings = true }
                .popover(isPresented: $showingSettings) { settings }
        }
    }

    private var timer: some View {
        VStack(spacing: 8) {
            Text(phaseTitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(module.menuBarTitle ?? Self.clock(module.durations.duration(of: module.state.phase)))
                .font(.system(size: 72, weight: .light, design: .monospaced))
                .monospacedDigit()
                .accessibilityIdentifier("pomodoro-remaining")
            Text("Today: \(PomodoroModule.format(module.todayFocused))")
                .foregroundStyle(.secondary)
        }
    }

    private var phaseTitle: String {
        let phase = switch module.state.phase {
        case .work: "Work"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
        return module.state.isPaused ? "\(phase) (paused)" : phase
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if module.state.isRunning {
                Button("Pause", systemImage: "pause.fill") { module.pause() }
            } else if module.state.isPaused {
                Button("Resume", systemImage: "play.fill") { module.resume() }
            } else {
                Button("Start", systemImage: "play.fill") { module.start() }
                    .keyboardShortcut(.defaultAction)
            }
            Button("Skip", systemImage: "forward.end.fill") { module.skip() }
            Button("Stop", systemImage: "stop.fill") { module.stop() }
                .disabled(!module.state.isRunning && !module.state.isPaused)
        }
        .controlSize(.large)
    }

    private var settings: some View {
        Form {
            Stepper("Work: \(minutes(\.work)) min", value: minutesBinding(\.work), in: 1...120)
            Stepper("Short break: \(minutes(\.shortBreak)) min", value: minutesBinding(\.shortBreak), in: 1...60)
            Stepper("Long break: \(minutes(\.longBreak)) min", value: minutesBinding(\.longBreak), in: 1...60)
            Stepper("Long break every \(module.durations.longBreakEvery) work blocks",
                    value: $module.durations.longBreakEvery, in: 1...10)
        }
        .padding()
        .frame(width: 320)
    }

    private func minutes(_ keyPath: WritableKeyPath<PomodoroDurations, TimeInterval>) -> Int {
        Int(module.durations[keyPath: keyPath] / 60)
    }

    private func minutesBinding(_ keyPath: WritableKeyPath<PomodoroDurations, TimeInterval>) -> Binding<Int> {
        Binding(
            get: { Int(module.durations[keyPath: keyPath] / 60) },
            set: { module.durations[keyPath: keyPath] = TimeInterval($0 * 60) }
        )
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct NowPlayingCard: View {
    let source: any NowPlayingSource

    var body: some View {
        HStack(spacing: 16) {
            switch source.status {
            case .playing(let track):
                artwork(track.artwork)
                VStack(alignment: .leading) {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text(track.artist).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Previous", systemImage: "backward.fill") { source.previous() }
                Button(track.isPlaying ? "Pause" : "Play",
                       systemImage: track.isPlaying ? "pause.fill" : "play.fill") { source.playPause() }
                Button("Next", systemImage: "forward.fill") { source.next() }
            default:
                Image(systemName: "music.note")
                    .font(.title)
                    .frame(width: 64, height: 64)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                Text(source.status.message ?? "")
                    .foregroundStyle(.secondary)
                Spacer()
                if source.status == .notRunning {
                    Button("Open Music") { source.openMusic() }
                }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(12)
        .frame(maxWidth: 480)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func artwork(_ data: Data?) -> some View {
        if let image = data.flatMap(Self.image) {
            image.resizable().scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: "music.note")
                .font(.title)
                .frame(width: 64, height: 64)
                .background(.quaternary, in: .rect(cornerRadius: 8))
        }
    }

    private static func image(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map(Image.init(nsImage:))
        #else
        UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }
}
