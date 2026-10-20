import AppKit
import BTKit
import SwiftUI

/// Ticks the timer every second so phases complete and the menu bar
/// countdown updates while the main window is closed. `MenuBarExtra`
/// labels don't run `TimelineView`, so the label reads `now` instead.
@MainActor
@Observable
final class PomodoroClock {
    private(set) var now = Date()

    // ponytail: the timer runs for the app's lifetime and is never invalidated.
    init(pomodoro: PomodoroModule) {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                pomodoro.tick()
                self?.now = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

struct PomodoroMenuBarLabel: View {
    let pomodoro: PomodoroModule
    let clock: PomodoroClock

    var body: some View {
        let _ = clock.now
        if let title = pomodoro.menuBarTitle {
            Text(title).monospacedDigit()
        } else {
            Image(systemName: "timer")
        }
    }
}

struct PomodoroMenu: View {
    let pomodoro: PomodoroModule
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if pomodoro.state.isRunning {
            Button("Pause") { pomodoro.pause() }
        } else if pomodoro.state.isPaused {
            Button("Resume") { pomodoro.resume() }
        } else {
            Button("Start") { pomodoro.start() }
        }
        Button("Stop") { pomodoro.stop() }
            .disabled(!pomodoro.state.isRunning && !pomodoro.state.isPaused)
        Divider()
        Button("Open BT") {
            openWindow(id: "main")
            NSApp.activate()
        }
    }
}
