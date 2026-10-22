import AppKit
import SwiftUI

/// Music for the session: the real source's track when there is one, sample data otherwise.
/// The position is simulated in `FocusScreenState`.
struct NowPlayingCell: View {
    let store: AppStore

    private var state: FocusScreenState { store.focusScreen }
    private var live: NowPlayingTrack? { store.liveMusicTrack }
    private var isPlaying: Bool { live?.isPlaying ?? state.samplePlaying }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isPlaying ? "Now playing" : "Paused")
                Spacer()
                Text(live == nil ? "Sample" : "Apple Music")
            }
            .monoLabel()
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text(live?.title ?? "[Track \(state.track + 1) title]")
                    .interStyle(20, .medium, tracking: -0.015)
                    .lineLimit(1)
                Text(live?.artist ?? "[Artist] · Deep Work · \(state.track + 1) of \(FocusScreenState.trackCount)")
                    .foregroundStyle(Color.btMuted)
                    .lineLimit(1)
            }
            LevelBars(levels: state.levels(playing: isPlaying), progress: state.progress)
            progressBar
            controls
        }
        .padding(BTMetrics.cellPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashedEdges(right: false, bottom: true)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                state.advance(playing: isPlaying)
            }
        }
    }

    @ViewBuilder private var artwork: some View {
        ZStack {
            Color.btInk
            if let data = live?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ConcentricArt().frame(width: 180, height: 180)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
        .accessibilityHidden(true)
    }

    private var progressBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.btTrack)
                    Rectangle().fill(Color.btInk).frame(width: geo.size.width * state.progress)
                }
            }
            .frame(height: 2)
            HStack {
                Text(state.positionLabel)
                Spacer()
                Text(state.lengthLabel)
            }
            .font(.mono(11))
            .foregroundStyle(Color.btMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.positionLabel) of \(state.lengthLabel)")
    }

    private var controls: some View {
        HStack {
            iconButton("backward.end.fill", label: "Previous track", size: 44) { skip(-1) }
            Spacer()
            Button(action: togglePlay) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.btInkOnDark)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.btInk))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause music" : "Play music")
            Spacer()
            iconButton("forward.end.fill", label: "Next track", size: 44) { skip(1) }
        }
    }

    private func iconButton(_ symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func togglePlay() {
        if live != nil { store.nowPlaying?.playPause() } else { state.samplePlaying.toggle() }
    }

    private func skip(_ offset: Int) {
        if live != nil { offset > 0 ? store.nowPlaying?.next() : store.nowPlaying?.previous() }
        state.skip(by: offset)
    }
}

/// 32 level bars; bars before the playback position are ink.
private struct LevelBars: View {
    let levels: [Double]
    let progress: Double

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(levels.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Double(i) / Double(levels.count) < progress ? Color.btInk : Color.btSubtleLight)
                    .frame(height: levels[i])
            }
        }
        .frame(height: 36, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Generated cover: 14 concentric circles, every third in accent.
private struct ConcentricArt: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 200
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<14 {
                let r = (8 + Double(i) * 6.5) * scale
                let circle = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.stroke(circle, with: .color(i % 3 == 0 ? .btAccent : .btSubtle), lineWidth: scale)
            }
        }
    }
}
