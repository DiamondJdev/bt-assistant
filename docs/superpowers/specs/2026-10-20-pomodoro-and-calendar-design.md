# Pomodoro and Calendar modules (phases 2 and 3)

Parent plan: [monorepo and Mac client](../plans/2026-10-19-monorepo-and-mac-client.md). Phase 1 delivered `ToolSidebar`, `ToolModule` and the BT placeholder in `apple/BTKit`, with a thin `apple/BTMac` app target.

## Why

The owner is a student. A typical session is a two-hour block in the library. During it they want to know how long they actually worked, get told when to take a break, and control their music without switching to the browser or Apple Music. Their calendar holds study blocks, classes, meetings and assignment due dates. Due dates come from a subscribed school calendar, and a Google Calendar subscription also feeds Apple Calendar. They add one-off events during the day as meetings come up or to block off time.

The app must feel like one product. Every module works alone, but they share data and conventions so later phases can join them up. The first planned join (phase 8) is Pomodoro recognizing an upcoming study event and logging focus time against it, so the owner can compare planned and actual study time.

## Goals

Pomodoro:

- Work and break phases with a countdown in the menu bar and in the Pomodoro pane.
- Store `phase` and `endsAt` instead of decrementing a counter, so the timer is correct after sleep, relaunch or a stalled main thread. Paused state stores the remaining interval.
- Local notification when a phase ends.
- Log every completed or stopped work phase as a `FocusSession` (start, end, focused seconds, optional label, optional calendar event identifier). The pane shows total focused time today and for the current run of phases.
- A now-playing card that controls the track already playing in the Music app: artwork, title, artist, play/pause, next, previous.
- `focus_*` tool declarations and a snapshot string through `ToolModule`.

Calendar:

- Permission flow for full calendar access, with a clear screen when access is denied and a button that opens System Settings.
- Day, week and month views. The app opens to the day view, which shows what comes next (the next event from now) above the timeline.
- All calendars EventKit knows about, including the school and Google subscriptions. Events on read-only calendars display normally but cannot be edited or deleted, and the UI says so.
- Quick create (title, start, duration, calendar) and a full create/edit sheet (title, start, end, all-day, calendar, location, notes, recurrence).
- Edits and deletes of recurring events ask "this event" or "this and future events" and map to `EKSpan.thisEvent` and `.futureEvents`.
- Live refresh on `.EKEventStoreChanged`.
- `calendar_*` tool declarations and a snapshot string through `ToolModule`.

## Non-goals for this round

- Linking focus sessions to events in the UI, starting focus from an event, planned-versus-actual stats. Phase 8. This round only stores the optional event identifier on `FocusSession`.
- Audio visualizer. Nice to have, deferred; album artwork stands in for it.
- Picking playlists or browsing the music library. Only the currently playing track is controlled.
- Reminders. Assignment due dates are calendar events.
- Executing tools, argument schemas, socket routing. Phases 5 and 6. Modules only declare tools and produce snapshots.
- iOS targets. Code goes in BTKit where it can, but nothing is built or tested for iOS yet.
- Charts and history views beyond today's totals. Phase 7 brings Swift Charts for the coding tracker; focus history can join it then.

## Anti-goals

- Two modules that look like different apps. Both use the Phase 1 sidebar, standard SwiftUI controls and the system font, and they share empty and error state patterns (`ContentUnavailableView`).
- A copy of calendar data. EventKit stays the source of truth so events keep syncing to Google and the owner's phone.
- Silent edits to the wrong occurrence of a recurring class event.

## Constraints

- Swift 6 language mode, macOS 14 minimum, sandboxed app with ad-hoc signing.
- Code that could run on iOS lives in `apple/BTKit`. Mac-only services (menu bar, Apple Events to Music) live in `apple/BTMac` and are injected into BTKit views.
- Keep `.pbxproj` edits small. Info.plist keys use the existing `INFOPLIST_KEY_*` build settings; entitlements go in `apple/BTMac/BTMac.entitlements`.
- Tool names match `^[a-zA-Z0-9_-]+$`. Each tool's result should answer a question on its own, because Qwen3 rarely chains a second call.
- Logic gets tests in `swift test --package-path apple/BTKit`. EventKit, notifications and Apple Events get manual verification in the running app.

## Decided design

### Shared pieces (cohesion)

- `FocusSession.eventIdentifier: String?` exists from day one, holding an `EKEvent.calendarItemIdentifier` (or external identifier, builder's choice, documented).
- Calendar exposes a small read API in BTKit, beyond its own pane: `events(from:to:)` and `nextEvent(after:)`, observable so other modules can react to changes. Phase 8 Pomodoro uses this to find the upcoming study event.
- `BTMacApp` builds the module list and passes Mac-only services in. Module order in the sidebar: BT, Pomodoro, Calendar.
- Stateful modules are `@MainActor @Observable final class`es conforming to the existing `ToolModule` protocol, with `snapshot` and `content` as computed properties. The protocol already allows this, so neither branch changes `ToolModule.swift`. If a branch finds it must, it stops and reports instead of reshaping it alone.
- One SwiftData `ModelContainer`, built in `BTMacApp` and handed to modules, in the default sandbox container. Every module registers its models there (phase 5's chat cache joins it later). Models stay CloudKit-compatible from the start: every attribute optional or defaulted, no `@Attribute(.unique)`. No sync is turned on now; this only avoids a migration if the iOS app wants it.
- Notifications for phase ends are scheduled with `UNUserNotificationCenter` when the phase starts (and removed on pause, skip or stop), so they fire even if the app isn't running.
- Closing the main window does not quit the app. It keeps running with the menu bar timer, and the menu reopens the window. The Dock icon stays. Launch at login is out of scope.

### Pomodoro

- Defaults: 25 minutes work, 5 minutes short break, 15 minutes long break after every 4 work phases. Durations are editable in the pane and persist (`@AppStorage` or `UserDefaults`).
- Controls: start, pause/resume, skip phase, stop. Stop logs the partial work phase if it ran at least one minute.
- Phases do not auto-advance. When a phase ends, the notification fires and the next phase waits for start. (Builder may revisit if this feels wrong in use.)
- Timer state persists across relaunch: an `endsAt` in the past at launch means the phase finished while the app was closed, and it is logged with its scheduled end time.
- `FocusSession` storage: SwiftData in the app's container.
- Menu bar: `MenuBarExtra` in BTMac showing the remaining time (for example `18:42`) while a phase is active and an icon otherwise. The menu has start/pause/stop and opens the main window.
- Music control: Apple Events to `com.apple.Music` via ScriptingBridge or `NSAppleScript`, with `NSAppleEventsUsageDescription` and the narrowest sandbox entitlement that works (`com.apple.security.scripting-targets` if Music publishes an access group, otherwise `com.apple.security.temporary-exception.apple-events` for `com.apple.Music`). Track changes come from the `com.apple.Music.playerInfo` distributed notification instead of polling. When Music isn't running, the card says so and offers to open it.
- Tools: `focus_get_status` (phase, remaining, today's total), `focus_start`, `focus_pause`, `focus_stop`, `focus_get_stats` (totals for today and the past 7 days).
- Snapshot: one line, for example `Focus: work phase, 12m left, 1h 35m focused today.`

### Calendar

- `EKEventStore.requestFullAccessToEvents()`, `NSCalendarsFullAccessUsageDescription`, and the `com.apple.security.personal-information.calendars` entitlement.
- Views switch with a segmented control in the toolbar plus today/previous/next buttons. Day and week are hour timelines with all-day events in a strip at the top; month is a grid with up to a few event titles per day and a "+N" overflow. Events use their calendar's color.
- Clicking an event shows its details; editable events offer edit and delete.
- Quick create is a popover from a toolbar `+` button and from clicking an empty time slot. It defaults to a 30-minute event in the default calendar for new events.
- Recurrence in the edit sheet: none, daily, weekly, every two weeks, monthly, yearly, with an optional end date. Custom rules from other apps display as read-only text and are preserved on save.
- Tools: `calendar_list_events` (range; each result has event identifier, occurrence start, title, times, calendar, location, whether it recurs and whether it is editable), `calendar_create_event`, `calendar_update_event` and `calendar_delete_event`. Update and delete take the identifier, the occurrence start and a span (`this_event` by default, or `future_events`), so a recurring class is never edited by title matching. The snapshot includes the identifier of the next event so a single call can act on it.
- Snapshot: next event and the rest of today's count, for example `Calendar: next is CS 3013 at 2:00 PM (in 40m); 3 more events today.`
- Early check: build the recurring edit path first and test it by hand against a copy of a real class event (duplicate one, edit one occurrence, then edit future occurrences) before building the rest of the UI on top.

## Left to the builder

- File layout inside BTKit, view decomposition, names of types other than `FocusSession`.
- The precise visual layout of the timeline and month grid, within the cohesion rules above.
- Whether week view starts on Sunday or Monday (follow `Calendar.current.firstWeekday`).
- How the timer pane looks, provided remaining time, phase, controls, today's total and the now-playing card are all visible without scrolling at the default window size.

## Build order

Phase 1 is committed first so both branches start from it. Pomodoro and Calendar are built in parallel in separate git worktrees on branches off `feat/macos-app-shell`. They touch different files except `BTMacApp.swift`, `BTMac.entitlements`, `project.pbxproj` build settings and `apple/README.md`; those conflicts are small and resolved when the second branch merges. Pomodoro merges first.
