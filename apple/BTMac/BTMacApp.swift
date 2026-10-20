import BTKit
import SwiftData
import SwiftUI
import UserNotifications

@main
struct BTMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let container: ModelContainer
    @State private var pomodoro: PomodoroModule
    @State private var clock: PomodoroClock

    init() {
        do {
            container = try ModelContainer(for: Schema(BTModels.all))
        } catch {
            fatalError("Could not open the BT data store: \(error)")
        }
        let pomodoro = PomodoroModule(modelContext: container.mainContext, nowPlaying: MusicController())
        _pomodoro = State(initialValue: pomodoro)
        _clock = State(initialValue: PomodoroClock(pomodoro: pomodoro))
    }

    var body: some Scene {
        Window("BT", id: "main") {
            ToolSidebar(modules: [BTModule(), pomodoro])
                .frame(minWidth: 640, minHeight: 400)
        }
        .defaultSize(width: 960, height: 640)

        MenuBarExtra {
            PomodoroMenu(pomodoro: pomodoro)
        } label: {
            PomodoroMenuBarLabel(pomodoro: pomodoro, clock: clock)
        }
    }
}

/// Shows phase-end notifications while BT is the active app too.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
