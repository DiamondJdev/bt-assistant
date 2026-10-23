# Placeholder content in the Mac app

The Sand Grid screens read everything from `AppStore` (`apple/BTKit/Sources/BTKit/Store/AppStore.swift`). `AppStore.init` fills the store from `SampleData`, so every screen starts on mockup data. Only two things are real today: the BT conversation, once a server address is set, and Now Playing in Focus.

The app already has working modules that the new screens don't read yet. `BTMacApp.swift` creates them and hands them only to `ChatModel` for tool calls and to the menu bar:

| Module | Path under `apple/BTKit/Sources/BTKit/` | What it has |
| --- | --- | --- |
| `CalendarStore`, `CalendarModule` | `Calendar/` | EventKit access, reads and writes, change notifications |
| `PomodoroModule` | `Pomodoro/` | The real timer, phases, notifications and the SwiftData focus log |
| `CodingModule` | `Coding/` | Editor heartbeats and coding sessions from the VS Code extension |
| `ChatModel` | `Chat/` | Server sessions, history, streaming and tool approvals |

`Store/DataSources.swift` declares `CalendarSource` and `CodeActivitySource` for this swap. Nothing implements them yet.

## Sample data sources

| Data | Defined in | Used by |
| --- | --- | --- |
| Week of events (classes, shifts, study blocks, deadlines) | `Store/SampleData.swift`, `weekEvents` | Today, Calendar, Focus, Code booking |
| Active focus session, goals, focused-today seconds | `Store/SampleData.swift`, `init` | Today, Focus, Calendar Day |
| Projects, roadmaps and coding activity | `Store/SampleData.swift`, `projects` | Code, Today |
| BT memories, to-dos, threads and ledger | `Screens/BT/BTSampleData.swift` | BT, Today |

Rooms in sample events are the literal text `[Room]`, and one tariffninja stage is named `[Next milestone]`.

## By screen

### Today

- Events, the focus card, code time and to-dos all come from sample data.
- The ask box calls `AppStore.sendToBT`, which answers with the local `BTResponder`. It does not go to the server, even when BT is live.
- The term label uses fixed start dates (Jan 12, Jun 1, Aug 24) in `TodayModel.termLabel`.

### Focus

- The ring, goals and session count read `store.focus` from sample data. `PomodoroModule` runs a separate real timer that only the menu bar shows.
- Now Playing is real when Apple Music is available. Otherwise it shows a sample track and the label "Sample".

### Calendar

- All events are sample data. Edits change `store.events` in memory and never reach EventKit.
- The header text `Apple · Google — synced 1m ago` is hardcoded in `CalendarScreen.swift`.
- The Week BT bar proposes changes to one fixed sample block (`CalDraftReview.draftID = "draft"`).
- The Month "looking ahead" drafts come from `CalMonthMath.lookAheadDrafts`, a local rule. BT doesn't write them, and the "I can draft 4 more" line is fixed copy.
- The Blackboard deadlines feed doesn't exist yet. Deadlines are sample events with source `.blackboard`.

### Code

- Projects, roadmaps and activity are sample data. `CodingModule` sessions aren't used.
- BT's weekly summary sentences and the commit counts are fixed text in `Screens/Code/CodeSampleCopy.swift`. Git doesn't feed commits yet.
- "Draft a roadmap" sends a message through `sendToBT`, so the local responder answers it, not the server.
- The fall term start for week numbers is fixed in `CodeScreen.swift`.
- "Add project" makes a placeholder project from a path with no activity or roadmap.

### BT

- Threads, history, streaming and tool approvals are live once a server address is set. Without one, the screen shows the sample threads and a "Sample data" notice.
- The "BT remembers" list and the "Changes BT made" ledger are always sample data. The server doesn't send memories, and its tool writes don't create result cards or ledger entries, so they can't be undone from the app.
- "Ask BT about this project" opens a local thread. It doesn't scope a server conversation to the project.
- The composer chips (`/block`, `/remember`, `/todo`, `/status`, `@code`) are sent to the model as plain text. Only the local responder treats them as commands.

## Suggested order

1. Route `AppStore.sendToBT` through `ChatModel` when `btIsLive`, so Today and Code reach the server.
2. Back `store.events` with `CalendarStore` through a `CalendarSource`, and write edits back to EventKit.
3. Drive `store.focus` from `PomodoroModule` so the Focus screen and menu bar share one timer.
4. Build `projects` from `CodingModule` sessions through a `CodeActivitySource`, plus git for commits.
5. Have the server report tool writes and memories, then add them to the ledger with undo.

Remove `SampleData` fields as each one gets a real source, and update this file when you do.
