# BT for iPhone: design

Date: 2026-10-26. Status: approved

## Why

The owner wants to talk to BT the way they talk to Siri: phone locked in a pocket, AirPods in, say a phrase, give a command like "I have a chemistry assignment due later today, add it to my to-do list and remind me tonight", and have BT do it. Reminders and the to-do list are the main reasons the app exists. This plan is staged after the agent pipeline hardening and the new escalation rules, so we can assume OpenAI models will be used

## Success for version 1

1. Voice works end to end from a locked phone with AirPods.
2. Reminders fire reliably, as notifications or as alarms.
3. BT answers while the phone stays locked.

## Goals

- Wake BT hands-free from a locked phone, give one or more commands, hear short spoken confirmations.
- A server-side to-do list shared by the iPhone and Mac apps.
- Reminders (notification by default, alarm when the owner agrees) that fire on the device without the server.
- A small phone UI: past conversations, to-dos, settings.

## Non-goals

- App Store or TestFlight distribution. The owner has only a free Apple ID.
- Push notifications of any kind (APNs, ntfy, or similar).
- Instant cross-device delivery of reminders. Syncing is lazy (see Reminders).
- Calendar, Pomodoro, Coding, and Roadmap screens on the phone.
- Retiring the existing Pipecat voice pipeline. The browser client and dev UI still use it.
- iPad layouts.

## Anti-goals

These would make the app a failure even if it technically works:

- BT bringing up overdue to-dos while answering an unrelated request ("what's the capital of France?" gets "Paris" and nothing else).
- To-dos that are hard to see, go stale silently, or never get mentioned.
- A reminder that was confirmed but never fires.
- BT setting an alarm without asking.

## Constraints

- **Free Apple ID.** The app is installed from Xcode onto the owner's iPhone with a personal team. No APNs, no CloudKit, no paid entitlements. The signing profile expires every 7 days; the owner re-runs from Xcode or uses SideStore/AltStore to re-sign over Wi-Fi.
- **No iCloud Reminders.** Apple Reminders does not sync for the owner, so it cannot carry reminders between devices.
- **Network.** The server runs on an always-on NixOS homelab. Devices reach it over Tailscale. The iPhone runs the Tailscale app with VPN On Demand always on.
- **iOS 26.** AlarmKit and SpeechAnalyzer need it. `BTKit` currently declares iOS 17; the iPhone target raises its own deployment target to 26.

## Architecture

### Speech moves to the phone

The phone does wake handoff, listening, end-of-turn detection, speech recognition and speech output. Each spoken command goes to the server as an ordinary text message over the existing `/chat/ws` socket. This was chosen over the OpenAI Realtime API (better voice, higher cost, a second tool path) and over adding client tools to the Pipecat pipeline (keeps two model paths).

Consequences:

- Voice and text share one model path, `bt/llm/router.py::respond`, so the "text and voice use separate model paths" problem in `AGENTS.md` goes away for the apps.
- Client tools and approvals, which `/chat/ws` already supports (`hello.tools`, `tool_call`, `tool_result`, `tool_approval`), work in voice with no new protocol.
- `/chat/ws` needs one addition: the `message` frame carries whether it was spoken, so the server stores `input_mode="voice"` and renders the system prompt with `surface="voice"` (short, speakable replies). Today `answer()` hardcodes `input_mode="text"` and `respond()` hardcodes `surface="text"`.
- Speech output uses on-device `AVSpeechSynthesizer`, speaking each sentence as `delta` text completes. If the voice quality is not good enough, the server can later stream OpenAI TTS audio instead without changing anything else.

### Waking BT from a locked phone

1. The owner says "Hey Siri, BT", or holds the AirPods stem and says "BT". The phrase comes from an App Shortcut.
2. The shortcut runs an App Intent that does not require unlocking. On iOS 18 and later an audio recording intent (`AudioRecordingIntent`) can start the microphone from the background; it requires a Live Activity while recording.
3. A short chime plays in the AirPods, the Live Activity shows "Listening" on the lock screen, and the phone starts recognizing speech with SpeechAnalyzer.
4. Siri may mishear "BT". Keep a fallback phrase such as "Hey Siri, talk to BT".

### One conversation

1. The phone decides the owner has stopped talking (silence threshold, tuned during the spike) and sends the text.
2. The server runs the model. Server tools run on the server; device tools are forwarded to the phone.
3. Replies stream back and are spoken sentence by sentence. Confirmations are one short sentence ("Added chemistry to your to-dos. I'll remind you at 8 tonight.").
4. After BT finishes speaking, a soft tone plays and the phone listens again for a short window (default 5 seconds, adjustable in Settings). Speech in that window is a follow-up in the same conversation. Silence ends the session with a closing tone and the mic turns off.
5. The phone owns the timers, so a slow network never shortens the listening window.
6. Audio input and output both go through the AirPods using the voice-processing audio mode, so BT does not hear itself.

A voice session is one `/chat/ws` connection and one server conversation. Each wake starts a new conversation (owner's call left open; see Left to the builder).

### Approval for alarms

When the model calls `reminder_set` with `kind: "alarm"`, the phone treats it as an approval. In voice, the phone speaks a fixed question itself while the tool call is pending ("This seems important. Want an alarm at 8 instead of a notification?"), listens, and matches the answer locally against yes and no phrases. The answer is not sent as a chat message, because the turn is still running. An unclear answer counts as no. If the listening window closes without an answer, the reminder is scheduled as a notification. On the Mac, the existing approval card handles it. `CLIENT_TOOL_TIMEOUT_SECS` is 120 s, which covers a spoken answer.

## To-dos

### Data

Stored on the server in SQLite (the transcript database or a sibling file; builder's choice).

| Field | Notes |
| --- | --- |
| `id` | UUID |
| `title` | required |
| `notes` | optional |
| `due` | optional; either a date or a date-time with offset |
| `done_at` | null until checked off |
| `created_at`, `updated_at` | UTC |
| `last_checkin` | date BT last asked "did you finish this?"; null if never |

The owner's time zone comes from the device: each `message` frame carries the client's IANA time zone, and the server keeps the most recent one for date-only due dates and phrases like "tonight". (Builder's call, made during review.)

Status is derived, never stored: done if `done_at` is set, overdue if `due` has passed and it is not done, otherwise open. A date-only due date is overdue after the end of that day in the owner's time zone; a date-time is overdue at that minute.

Done items are hidden from every list immediately. Rows with `done_at` older than 24 hours are deleted, lazily, whenever to-dos are listed. Within those 24 hours the owner can undo by voice ("actually I didn't finish chemistry").

Items overdue for more than 3 days are flagged "still relevant?" in the apps so they can be dropped in one tap.

### API

REST endpoints for the apps, next to the existing `/memories` and `/sessions` in `bt/gateway/gateway.py`: list, create, update (including done/undone), delete. The Mac's `AppStore.todos` switches from `SampleData.todos` to this list, the way `shownMemories` loads from the server.

### Server tools

Declared with `@tool` in `bt/tools/`:

- `todo_add(title, notes?, due?)`
- `todo_list(filter?: open|overdue|done|all, due_before?, due_after?)` returns full items. Overdue items whose `last_checkin` is not today are marked "ask about this", and listing them sets `last_checkin` to today.
- `todo_update(id, title?, notes?, due?, done?)`
- `todo_delete(id)`

### Check-ins without interruptions

Overdue items are never added to the per-turn note. They only reach the model through `todo_list`, so BT only sees them when the request is already about to-dos, reminders, or plans. The system prompt tells BT to raise at most one check-in per reply. The digest notification's Done and Snooze buttons handle the rest outside conversations.

### Visibility

- iPhone: To-dos is the first tab. The app icon badge is the count of overdue plus due-today items, set locally on every sync.
- Mac: the Today screen's to-do panel uses the server list; the dock icon gets the same badge.
- iPhone morning summary: a local notification at a set time (default 8:00 AM, adjustable) listing what is overdue and due today, with Done and Snooze actions. It is rescheduled on every sync from the latest data, so it can be stale if the phone has not synced recently.
- Mac first focus session: when the owner starts the first Pomodoro focus session of the day (`PomodoroModule.start`), the Mac shows a summary card of overdue and due-today items with Done buttons and a Start button. It shows once per day and uses live data.

## Reminders

### Data

Stored on the server:

| Field | Notes |
| --- | --- |
| `id` | UUID, created by the device that set it |
| `title` | what is spoken or shown |
| `fire_at` | date-time with offset |
| `kind` | `notification` or `alarm` |
| `todo_id` | optional link |
| `origin_device` | the device that set it |
| `cancelled_at`, `fired_at` | optional |
| `updated_at` | for sync |

### Device tools

Declared by each app in its `hello` frame and run on the device:

- `reminder_set(title, fire_at, kind, todo_id?)` asks approval if `kind` is alarm, schedules locally, then saves the record to the server. It returns the scheduled time and kind so BT can confirm.
- `reminder_cancel(id)` cancels locally and marks the server record cancelled.
- `reminder_list(from?, to?)` reads from the server.

The chemistry example is two tool calls in one turn: `todo_add` then `reminder_set`.

### Scheduling on each device

- iPhone notification: `UNUserNotificationCenter` local notification. Tapping it opens the linked to-do.
- iPhone alarm: AlarmKit, with Snooze and Stop. It breaks through silent mode and Focus.
- Mac notification: macOS local notification; fires even when the app is closed.
- Mac alarm: AlarmKit is not on macOS. Use a notification that stays on screen until dismissed, plus a repeating sound while the app runs. The Mac app launches at login.

Once scheduled, every reminder fires with no server and no network.

### Lazy sync

1. The device that sets a reminder schedules it immediately.
2. Other devices pull reminder changes whenever they already sync: the Mac continuously while connected, the iPhone when the app opens or a voice session starts. There is no background syncing.
3. On each sync a device schedules future reminders it lacks, removes cancelled ones, and reschedules edited ones.
4. Both devices may ring for the same reminder. The owner accepted this. Dismissing on the iPhone tells the server when iOS gives the app a chance to run (best effort; an alarm stopped from the lock screen may not), and the Mac stops if it hears in time. Dismissing on the Mac does not reach the phone unless it syncs first.
5. If a reminder is edited on one device and the other has not synced, the other rings at the old time. Accepted.
6. Checking off a to-do cancels its linked reminders the same way.

## iPhone app

A new thin target in `apple/BT.xcodeproj` (for example `apple/BTiOS/`) around `BTKit`, using the Sand Grid design adapted for phone sizes.

Screens:

1. To-dos (first tab): open and overdue items, overdue first in the warning color; check off, edit, swipe to delete; "still relevant?" flag.
2. Conversations: past threads from `/sessions` and `/history`, both voice and typed. Typing a message reuses `ChatModel`.
3. Settings: server address, listening window length, default reminder kind, morning summary time, voice, a "test Siri phrase" button.
4. A full-screen listening view when BT is woken with the app open.

`BTKit` already lists iOS as a platform, but seven files use AppKit or `#if os(macOS)` code, and the iOS build stops at `Screens/Focus/NowPlayingCell.swift`. Those files are guarded or moved so the shared parts build for iOS: `Calendar/CalendarView.swift`, `Chat/ChatView.swift`, `Screens/Calendar/CalEventPopover.swift`, `Screens/Focus/NowPlayingCell.swift`, `Pomodoro/PomodoroView.swift`, `Coding/RoadmapModule.swift`, `Coding/ProjectEditing.swift`.

## Networking

- The server is published inside the tailnet with `tailscale serve`, giving `https://<host>.<tailnet>.ts.net` with a valid certificate. iOS App Transport Security blocks plain HTTP to non-local hosts, so this avoids an exception, and `wss://` works for the socket. The Mac app moves to the same address.
- Being on the tailnet is the access control, as it is for the Mac today. Tailscale identity headers from `tailscale serve` are available later if per-device rules are wanted.
- On cellular, Tailscale may relay through DERP when a direct path fails. Measure the added delay in the spike.

## Order of work

1. Spike (below).
2. Server: to-do and reminder storage, endpoints, tools, and the spoken-message flag on `/chat/ws`.
3. iPhone app: voice session, device reminder tools, the three tabs.
4. Mac app: real to-do list, the same reminder tools and sync, the first-focus summary card.

Version 1 success is measured after step 3. Step 4 is in scope for this project, but nothing in step 3 waits for it.

## Spike first

Before building the app, a throwaway app signed with the free Apple ID checks the assumptions that would change the design:

1. The App Shortcut phrase runs from a locked phone with AirPods.
2. The audio recording intent can start listening in the background without unlocking, with a Live Activity.
3. AlarmKit is available to a personal team and an alarm fires from a locked phone.
4. SpeechAnalyzer recognizes speech through AirPods with acceptable delay.
5. A round trip to the server over Tailscale on cellular, from a locked phone.

If any of 1 to 3 fail with a free account, stop and revisit the trigger or alarm design with the owner.

## Left to the builder

- Whether each wake starts a new conversation or continues the latest one within some time window.
- Silence threshold for end of turn.
- Where to-do and reminder tables live (transcript database or a new file) and the sync endpoint shape (for example `GET /reminders?since=<updated_at>`).
- The exact phone layout within the Sand Grid tokens.
- How Snooze from a notification action reaches the server (background URLSession from the notification action is expected to work). Snooze length defaults to 5 minutes.
