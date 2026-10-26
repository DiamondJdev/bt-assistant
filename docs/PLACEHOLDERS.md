# Placeholder content in the Mac app

The Sand Grid screens read everything from `AppStore` (`apple/BTKit/Sources/BTKit/Store/AppStore.swift`). `BTMacApp.swift` gives the store its real sources:

| Data | Source | Without the source |
| --- | --- | --- |
| Timed and all-day calendar events | `CalendarStore` through `CalendarSource` (`Calendar/CalendarSourceEventKit.swift`) | `SampleData.events` and `SampleData.allDayEvents` |
| Focus timer and focused time | `PomodoroModule`, the same timer the menu bar shows | A sample session counted down by `AppStore.tick` |
| Logged focus blocks | The Pomodoro focus log | Kept in memory |
| Projects and coding activity | `CodingModule` through `CodeActivitySource` | `SampleData.projects` |
| Focus task and goals, project weekly goals, roadmaps, tracked repos | `SavedPlans` in `UserDefaults` (`Store/SavedPlans.swift`) | Kept in memory |
| "BT remembers" | `GET /memories` on the server, once an address is set | `SampleData.memories` (`Screens/BT/BTSampleData.swift`) |
| Today and Code asks to BT | `ChatModel`, as a new server conversation, once an address is set | The local `BTResponder` |

Tests and previews build `AppStore` without sources, so `SampleData` stays as their fixture.

## How the real sources behave

Edits on the Calendar, Today and Code screens are written to EventKit. BT's own fields (kind, focus plan, linked project and a stable id) are stored in the event's URL as `bt://event?...`. An event that already has a URL, such as a meeting link, keeps it, so BT's fields on that event don't survive a reload. Events from other calendars get the kind `work` when the calendar title contains "work" and `classSession` otherwise.

All-day events are kept in `AppStore.allDayEvents`, apart from the timed `events`, so they never count as busy time when BT looks for a free slot. Week shows them in an "All day" row under the dates, Day and Today list them first, and Month shows up to two per cell. They can't be edited in the app yet, and the layer toggles don't hide them.

The store reads events six weeks either side of today and the shown date, and reloads when EventKit reports a change. A failed write shows its error in the Calendar header and puts the event back the way EventKit has it.

`SavedPlans` is written whenever the focus task, its goals or the project list changes. The timer ticking alone writes nothing. Every project is saved, so a project stays listed however long ago it was last coded on. The Code screen loads the last five weeks of activity for each one.

Coding time and focus time are stored in SwiftData (`CodingHeartbeat` and `FocusSession`) and never pruned, and the running Pomodoro phase is kept in `UserDefaults`, so a relaunch picks up where the last session stopped. `RelaunchTests` checks this against an on-disk store.

For a tracked project without stages, "Draft a roadmap" starts a live BT conversation using the repo's root README. BT is instructed to ask one question at a time about missing goals, scope, priorities or progress, rather than assume the README describes future work. The README is sent to the configured server as reference text, capped at 12,000 bytes before and after JSON encoding; longer content is truncated. Missing or unreadable READMEs leave BT to ask the owner for context. The approval-required `roadmap_create` tool saves ordered stages and tasks through `SavedPlans` and refuses to replace an existing roadmap. This requires a server address; there is no sample roadmap fallback.

Existing roadmaps have an "Edit" sheet for renaming, adding, removing and reordering stages and tasks, and setting task statuses. Save writes the draft; Cancel leaves the roadmap unchanged. "Edit with BT" starts a live conversation: `roadmap_get` reads the current roadmap and `roadmap_update` saves the owner's approved changes. Both paths calculate stage progress from completed tasks, advance to the first unfinished stage, and reopen a completed stage when a task is reopened. Existing IDs and dates are preserved, and an edit based on an older roadmap is rejected rather than overwrite newer changes.

## Still sample or fixed

Each item below says what still runs on fixed data and what has to change to make it real.

### Today

- To-dos come from `SampleData.todos` (`Screens/BT/BTSampleData.swift`). To make them real, the server needs a to-do store with a list endpoint (like `GET /memories`) and a tool that adds to it. Then `AppStore.todos` loads from `ChatModel` the way `shownMemories` does.
- The greeting uses the fixed name in `TodayFormat.ownerName`. Read the name from Settings, or from the macOS account with `NSFullUserName()`.
- The term label uses fixed start dates (Jan 12, Jun 1, Aug 24) in `TodayModel.termLabel`. Add a term start setting and read it here and in `CodeTermWeek`.
- The Code time cell measures against a fixed 4h goal (`CodeTimeSummary.goalSeconds`, shown as "Goal 4h"). Keep it in `SavedPlans`, or derive it from the projects' weekly goals.
- BT's booking sentence and its "Book" slot come from a local rule (`todayProposal` and `todayBookingSlot` in `TodayModel.swift`), not from the server.

### Focus

- The daily goal is a fixed two hours in `AppStore.focusGoalSeconds`. Add it to `SavedPlans` with a control on Focus to change it.
- The break label reads `ActiveFocusSession.breakLength` (5 min), not the Pomodoro durations. `syncFocus` should copy the real break length into the session.
- Now Playing shows a sample track labeled "Sample" when Apple Music isn't available. Spotify or other players need their own `NowPlayingSource`.
- The BT note (`FocusSummary.btNote`) is fixed copy. It says BT will fade the music at the break, but the app stops the player instead. "Leave by" is always 10 minutes before the next event (`FocusSummary.leadMinutes`), whatever the location.

### Calendar

- The Week sidebar's calendar list (`CalWeekLayer`) is a fixed set of kinds with sample names such as "UARK classes". To list real calendars, read `CalendarStore.writableCalendars()`, keep each event's calendar name on `CalendarEvent`, and filter by calendar instead of by kind.
- Kinds for events BT didn't create are guessed from the calendar title. With the real calendar list, the owner could pick a kind per calendar and `SavedPlans` could keep that choice.
- The Week BT bar's sentences are fixed copy about CHEM SI and the lab report (`CalWeekBTBar.sentence`). They should describe the draft from its own fields, or come from the server with the draft.
- Month "looking ahead" drafts come from a local rule (`CalMonthMath.lookAheadDrafts`), and the "I can draft 4 more" line is fixed copy. BT should propose these through a server tool that returns blocks, which the app adds as `btDraft` events.
- The Day composer's prompt and its draft come from a local parser (`CalDayDraft`). Send the prompt to BT instead and show the block it proposes.
- There is no Blackboard deadlines feed, so with EventKit connected there are no deadline events. Blackboard can share its calendar as an iCal feed. Subscribing to it in macOS Calendar would bring due dates into EventKit, and marking that calendar's events as `deadline` would put them in the DUE row.

### Code

- Roadmap target dates are not editable, and progress is entered by the owner or through approved BT updates, not inferred from commits or GitHub issues. Existing dates are kept when a roadmap is edited.
- There are no commit counts, because heartbeats carry only a project name. Have the VS Code extension send the workspace path, store it on the project, and run `git log --since` there.
- The fall term start for week numbers is fixed in `CodeTermWeek.termStart`; see the term setting under Today.
- The "BT suggests" rows come from local rules in `CodeSuggestions` (book a block, set a weekly goal, make the next task a Focus goal). The 3h default weekly goal and the 10 AM weekend block are fixed there.

### BT

- The "Changes BT made" ledger starts from `SampleData.ledger` (`Screens/BT/BTSampleData.swift`). Tool calls that run in the app (calendar and focus) pass through `ChatModel.run`, so the app can record those itself with an undo token. Server-side writes such as `memory_write` need the `done` frame to list what changed, with enough detail to undo it.
- Threads are sample data until a server address is set.
- "Ask BT about this project" opens a local thread. With a server address set, BT shows the server conversation instead, so the project is dropped. The server would need a way to start a conversation with a project attached, for example a `project` field on the first message that goes into the turn note.
- The composer chips (`/block`, `/remember`, `/todo`, `/status`, `@code`) are sent to the model as plain text. Only the local responder treats them as commands. Either teach the system prompt what they mean or turn each into a direct tool call.

## Suggested order

1. The ledger for in-app tool calls, then for server writes.
2. Real calendar layers from EventKit, with a kind per calendar.
3. A server to-do store for Today.
4. A term start setting.
