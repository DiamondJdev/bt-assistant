import BTKit
import Carbon.HIToolbox
import OSLog
import SwiftData
import SwiftUI
import UserNotifications

@main
struct BTMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    private let container: ModelContainer
    @State private var pomodoro: PomodoroModule
    @State private var clock: PomodoroClock
    @State private var store: AppStore
    @State private var hotkey = GlobalHotkey()

    init() {
        do {
            container = try ModelContainer(for: Schema(BTModels.all))
        } catch {
            fatalError("Could not open the BT data store: \(error)")
        }
        let music = MusicController()
        let pomodoro = PomodoroModule(modelContext: container.mainContext, nowPlaying: music)
        _pomodoro = State(initialValue: pomodoro)
        _clock = State(initialValue: PomodoroClock(pomodoro: pomodoro))
        let coding = CodingModule(modelContext: container.mainContext)
        coding.startWatching()
        let chat = ChatModel()
        // The new screens read AppStore; these modules still serve BT's tool calls and the menu bar.
        chat.modules = [BTModule(chat: chat), pomodoro, CalendarModule(), coding]
        _store = State(initialValue: AppStore(nowPlaying: music, chat: chat))
    }

    var body: some Scene {
        Window("BT", id: "main") {
            BTAppView(store: store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)

        MenuBarExtra {
            PomodoroMenu(pomodoro: pomodoro)
        } label: {
            PomodoroMenuBarLabel(pomodoro: pomodoro, clock: clock, store: store, hotkey: hotkey)
        }

        Settings {
            ChatSettingsView()
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

/// ⌃⌥Space from any app. Carbon hot keys need no Accessibility permission.
@MainActor
final class GlobalHotkey {
    private static let logger = Logger(subsystem: "BTMac", category: "Hotkey")
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var action: (() -> Void)?

    /// Registers once; later calls only replace the action.
    func install(_ action: @escaping () -> Void) {
        self.action = action
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue().action?()
                }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard status == noErr else {
            Self.logger.error("Hotkey handler install failed: \(status)")
            return
        }
        let id = EventHotKeyID(signature: OSType(0x4254_484B), id: 1)  // "BTHK"
        let registered = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if registered != noErr {
            // Usually another app owns ⌃⌥Space. BT works without it.
            Self.logger.error("Hotkey registration failed: \(registered)")
        }
    }
}
