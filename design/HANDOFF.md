# BT for macOS — design handoff

This folder is the design spec for the BT macOS client ("Sand Grid" direction). Build the app in **SwiftUI** to match it.

- `screens/*.dc.html` — the 7 screens of the clickable prototype. They are HTML/CSS mockups written in a templated format (`<x-dc>`, `{{holes}}`, `<sc-for>`, `<sc-if>`, plus a `class Component` script). **They will not open in a browser on their own and are not meant to be ported as web code.** Read them for layout, exact values (sizes, spacing, colors, copy) and behavior. The script block at the bottom of each file shows the state and actions each screen needs.
- `screenshots/` — (optional) PNG exports of each screen from the design canvas, if added. When present, treat them as the visual source of truth for spacing and hierarchy.
- All data in the screens is **sample data**. `[Room]`, `[Track title]`, `[Artist]`, `[DATE]` are placeholders for real values.

## How to work through this

1. Build the **design system** first (tokens + shared components below). No screen work until it exists.
2. Build **one screen per pass**, in this order: Today → Focus → Calendar (Week, then Day, then Month) → Code → BT.
3. Back every screen with **one shared app store** (see Data model). The prototype keeps state per screen; the real app must not. A block booked on Today has to show up in Calendar, Focus and BT.
4. Use sample data first, behind protocols, so real sources (EventKit, editor plugins, BT API, Apple Music) can be swapped in later.

---

## Design tokens

### Color
| Token | Hex | Use |
|---|---|---|
| `ground` | `#E9DFD3` | Window background (sand) |
| `groundDeep` | `#DCD0C2` | Behind the window / outer background |
| `paper` | `#F4EDE4` | Raised cells: selected rows, cards, popovers, BT result cards |
| `ink` | `#2E2218` | Primary text, filled buttons, solid "focus logged" blocks |
| `inkOnDark` | `#F4EDE4` | Text on ink fills |
| `muted` | `#6B5C4C` | Secondary text, mono labels |
| `subtle` | `#8C7E70` | Tertiary marks, borders on outlined blocks, other-month dates |
| `line` | `#B5A796` | **Dashed grid lines** between cells (1px dashed) |
| `rule` | `#D6C9B9` | Solid 1px row separators inside cells |
| `track` | `#CDBFAE` | Empty tick-bar segments, inactive bars |
| `fillClass` | `#DCCFBF` | Class blocks, bar backgrounds |
| `accent` | `#D9531E` | The single accent: timer progress, primary CTA fill, "now" line, due tags |
| `accentText` | `#B8431A` | Accent used **as text** (passes contrast on sand) |
| `accentDeep` | `#8A3412` | Accent text on light accent tints (BT drafts, warnings) |
| `accentTint` | `rgba(217,83,30,0.06–0.10)` | Background of BT draft / suggestion areas |
| `onAccent` | `#1F120A` | Text on accent fills |
| `breakGreen` | `#2E6B4F` | Ring progress during a break |

### Type
- **Inter Tight**: UI and display. Weights 400 / 500 / 600.
- **Geist Mono**: labels, times, numbers in tables. Weights 400 / 500.
- Both are free Google Fonts (OFL). Bundle them in the app.

| Style | Font | Size | Weight | Tracking | Notes |
|---|---|---|---|---|---|
| Hero greeting | Inter Tight | 96 | 500 | −0.055em | line-height 0.88 |
| Hero timer (Focus) | Inter Tight | 92 | 500 | −0.055em | tabular numbers |
| Big stat | Inter Tight | 52–64 | 500 | −0.045em | line-height 0.9 |
| Page title | Inter Tight | 40 | 500 | −0.045em | Calendar toolbar, "Stage 3" |
| BT statement | Inter Tight | 24–30 | 500 | −0.025em | muted spans for secondary clauses, `accentText` for the key action |
| Row title | Inter Tight | 17 | 500 | — | agenda rows |
| Body | Inter Tight | 14–15 | 400 | — | |
| **Cell label** | Geist Mono | 11 | 400 | +0.08em | UPPERCASE, `muted`. Every cell starts with one |
| Times / meta | Geist Mono | 10–12 | 400–500 | +0.06em | |

### Shape and spacing
- Cells: **20px padding**, no corner radius, separated by **1px dashed `line`** borders.
- Buttons: pill (`radius 999`), height 36 (small 28–32, large 44). Primary = `ink` fill, CTA = `accent` fill, secondary = 1px `ink` outline on transparent.
- Popovers and cards: square corners, 1px `ink` border, `paper` fill, hard offset shadow `8px 8px 0 rgba(46,34,24,0.12)`.
- Minimum hit target 44pt for primary controls.
- No gradients, no emoji, no rounded-card-with-left-border patterns.

---

## Shared components

1. **AppWindow + Header**: 52pt bar, 4-column grid, dashed bottom border.
   - Column 1: traffic lights and the "B T" wordmark (Inter Tight 600, 13pt, +0.32em).
   - Columns 2–3: module nav (Today · Focus · Code · Calendar · BT) in uppercase mono. The active item is `ink` with a 1.5px underline; the others are `muted`.
   - Column 4: a context slot that each screen sets (e.g. "Ask BT ⌘K", "Do not disturb", "Apple · Google — synced").
2. **SandGrid**: a 4-equal-column grid where each cell draws dashed right/bottom borders. Cells can span columns and rows.
3. **GridCell**: padding 20, a mono label row (left label, optional right meta or link), and content pushed to the bottom (`justify-content: space-between`).
4. **TickBar**: N thin segments (usually 24 or 40) with 3px gaps, filled `ink` up to the value and `track` after. A dashed variant marks "booked but not done".
5. **LineRing** (signature element): 160–220 short line segments arranged in a wobbling ring. Each line runs from an inner to an outer radius with a slight twist.
   - The formula is in `Focus.dc.html` and `Today.dc.html`: `r1 = 92 + 9·sin(3a + 0.6)`, `r2 = 132 + 4.5·sin(3a + 0.6)`, twist 0.36 rad.
   - Lines before the progress fraction are `accent` (green during a break). The rest alternate `#8C7E70` and `#B3A595`.
   - Draw it with `Canvas` or a `Shape`, and redraw once per second.
6. **SemicircleDial / HeatGrid / ProgressBar**: simple bar and grid views used in Code. The heat grid is 7 rows × 16 hour columns, 5 shades from `#E2D7CA` to `ink`, with future cells drawn as a dashed outline.
7. **BTStatement**: mono "BT · …" label, a 24–30pt sentence in three tones (ink / muted / accentText), then 1–2 pill actions.
8. **BTResultCard**: `paper` card with a 1px ink border showing a mono kind label ("CALENDAR · MOVED", "MEMORY · SAVED", "TO-DO · ADDED", "STATUS · UPDATED"), a bold title, a mono detail and an optional deep link. The undone state uses a dashed border, 60% opacity and strikethrough.
9. **EventBlock** (calendar), one style per kind:
   - `class`: `fillClass` fill
   - `work`: `ground` fill with a 1px `subtle` border
   - `focusLogged`: `ink` fill with light text
   - `studyPlanned`: transparent with a 1.5px dashed `ink` border
   - `btDraft`: `#F7E4D8` fill with a 1.5px dashed `accent` border and `accentDeep` text
   - `selected`: an extra 3px `accent` ring
10. **DueTag**: `accent` fill, `onAccent` text, 11pt bold.

---

## Screens

The prototype window is 1440×900 with a 1100pt minimum content width. Grid rows are given as fractions in each file.

### 1. Today — `screens/Today.dc.html`
- **Row 1:** clock cell (date and week label, 64pt time) · agenda spanning 2 columns (live rows from the store, each `time · title · meta`; the "N remaining →" link opens Calendar Day) · Code time cell (linked to Code: today's total, a 24-segment tick bar, per-project mono line).
- **Row 2:** Focus cell spanning 2 columns. On the left are the session label, task, project and Pause/Resume and +5 min. On the right is the LineRing with a mono countdown. Next to it is the BT statement spanning 2 columns.
- **Row 3:** greeting "Afternoon, Cameron" (96pt) spanning 2 columns · "Tell BT" composer spanning 2 columns.
- **Behavior:**
  - The timer counts down every second, and the ring progress = 1 − left/total.
  - Pause/Resume and +5 min (which adds 300s to both left and total) work as on Focus.
  - "Book 2:55" creates a Focus-linked study block, inserts it into the agenda, and switches the BT statement to its confirmed state with Undo and "See in Calendar".
  - Composer Enter/Send posts to BT and shows a "Sent to BT … Open thread →" confirmation.

### 2. Focus — `screens/Focus.dc.html`
- **Column 1:** Hard stop (minutes until the next calendar event, links to Day) / Goal for this session (checklist with a done count) / Focused today (total plus a tick bar against a 2h goal).
- **Columns 2–3 (all 3 rows):** large LineRing (500pt) with a 92pt countdown, "of 25:00", corner labels (session, task, next break, next class), and Pause/Resume, +5 min, End session.
- **Column 4:** Now Playing (rows 1–2) with generated art, track and artist, a live level bar, a progress bar, prev/play-pause/next, and a source label. Below it (row 3), a one-line BT note.
- **State machine:**
  - `focus(left, total)` → End session or timer reaching 0 → `break(300s)`. During a break the ring turns green, music pauses and the labels change.
  - From `break`, "Start session 3" goes back to `focus(1500s)`.
  - Paused shows "Paused · of 25:00" in `accentText`.
- **Header slot:** a Do Not Disturb toggle (dot `accent` when on).
- Focused-today minutes grow only while in focus mode and not paused.
- **Integrations:** sessions are written to Calendar as `focusLogged` blocks, and coding inside sessions feeds Code's "Inside Focus".

### 3. Calendar — Week — `screens/CalWeek.dc.html` (default Calendar view)
- **Toolbar:** title (week range), meta (hours booked / study), prev/Today/next, Day/Week/Month segmented control (navigates between the 3 views), "+ New event" (accent).
- **Sidebar (column 1):**
  - mini month with the current week shaded and today in accent
  - calendar layer checkboxes, each with a swatch and source (APPLE / GOOGLE / BT / FOCUS) — toggling hides that kind
  - "Due this week" list
- **Grid (columns 2–4):**
  - 7 day columns, 8 AM–10 PM, with a DUE row under the day headers
  - today's column is tinted and has the "now" line
  - events are absolutely positioned by start and end
- **Selecting an event** opens a popover anchored beside it. It flips to the left when the event is Friday–Sunday. It contains:
  - title field and time
  - −30/+30 nudge
  - "Run as Focus session · 50/10" toggle
  - Save, "Start focus now" (go to Focus), Delete
- "+ New event" creates an event and opens it.
- **BT bar** (bottom): a proposal about a BT draft block with Keep / Move later / Discard. Each choice changes the block and the sentence, with Undo.

### 4. Calendar — Day — `screens/CalDay.dc.html`
- **Columns 1–2, agenda list:**
  - past rows are muted
  - the NOW row is an ink band linking to Focus
  - study blocks are clickable and **edit inline**: title, −15/+15, Run as Focus, Save, Delete
  - the free-time gap row has "+ Fill with study"
  - the deadline row is in accent
- **Column 3, "Tell BT what to schedule":** a natural-language input. Send re-drafts BT's card (title, when, calendar, focus plan, why). "Add to calendar" inserts it into the agenda. "Edit details" adds it and opens inline edit. "Try" prompts fill the input.
- **Column 4:** today's hours as a stacked bar (class / focus planned / open / other) with numbers that update as blocks are added. "Due soon" countdowns flag deadlines with no time booked.

### 5. Calendar — Month — `screens/CalMonth.dc.html`
- **Toolbar:** layer pills (Study / Due / Class / Work) that filter the grid. Work is off by default.
- **Grid:**
  - 7 × 5 month (weeks start Monday)
  - each cell shows the date (today circled in accent), a due tag, a 3px load bar for how booked the day is, and up to 3 items with kind swatches
  - clicking a day selects it
- **Side panel:**
  - the selected day's items, with "Open day →" for today or "Open week →" otherwise
  - "Study this month" (logged hours plus booked-ahead as a 40-segment tick bar against a goal)
  - BT look-ahead card: "Draft blocks" adds BT draft items to next week's cells and updates booked hours, with "Review in Week" and Undo

### 6. Code — `screens/Code.dc.html`
- **Column 1 (all rows):** "All projects" weekly total with a goal tick bar, then a project list. Each project shows name, hours, share bar, status (accent when active or dropping) and a 7-day spark. Clicking selects the project and drives every other cell. Below is "+ Track a repo".
- **Header (columns 2–4):**
  - path/stack in mono, project name at 80pt, stats (this week / streak / commits)
  - BT summary paragraph with numbered superscript notes `1 2 3` that point to the cells below
- **Roadmap (column 2, rows 2–3), note 2:**
  - "Stage N of M"
  - a vertical dashed timeline: done stages are solid dots, muted, with a ✓ date; the current stage is a `paper` card with an accent border, progress bar, tasks with statuses (DONE struck through, IN REVIEW, NEEDS YOU in accent) and a target date; next stages are dashed hollow dots; the final release is a dashed diamond
  - "Plan stage N+1 with BT"
  - a project with no roadmap shows an empty state with "Draft a roadmap"
- **Heat grid (columns 3–4), note 1:** when you work on the project, with a "Best: …" label.
- **Inside Focus (column 3), note 3:** % of work done inside Focus sessions, an ink vs. hatched bar, and an "unbroken minutes" note.
- **BT suggests (column 4):** booked vs. goal for the project, 2 actions that toggle to a done label ("Added ✓"), and an "Ask about <project>" link to BT.
- The user does mostly **agentic coding**, so "time" metrics should come from agent sessions and reviews, not keystrokes alone.

### 7. BT — `screens/BT.dc.html`
- **Column 1:** New thread (⌘N), thread list (selectable; a new thread opens an empty state), and "BT remembers": the newest memory highlighted with `paper`, an accent border and a "NEW ·" tag, with "See all" to expand.
- **Columns 2–3, conversation:**
  - user bubbles are `ink` blocks aligned right
  - BT messages have a "BT · time" mono label, text, and an optional **insight card** (big number, sentence, deep link) and/or a grid of **BTResultCards**
  - chips above the composer fill in `/block`, `/remember`, `/todo`, `/status`, `@code`
  - Enter sends
- **Column 4, "Changes BT made":** a reverse-chronological ledger of every write BT performed (`time · KIND · text · Undo`). Undo reverts the change in its module, marks the card in the thread as undone, and removes a memory if it was one.
- **Routing (the prototype uses keywords; real app uses BT's tool calls):**
  - remember → Memory
  - todo/add → To-do
  - block/book/schedule/move → Calendar
  - status/mark/merged → project roadmap
  - questions or @code → insight card

---

## Data model (shared store)

```swift
enum EventKind { case classSession, work, focusLogged, studyPlanned, btDraft, deadline }
struct CalendarEvent { id; title; start; end; kind; source /* apple, google, bt, focus, blackboard */; runAsFocus: Bool; focusPlan /* e.g. 2×25 */; linkedProjectID?; linkedAssignmentID? }

struct FocusSession { id; taskTitle; projectID?; plannedSeconds; remainingSeconds; mode /* focus, break */; isPaused; goals: [SessionGoal]; startedAt }
struct SessionGoal { id; title; isDone }

struct Project { id; name; path; stack; weeklyGoalHours?; stages: [RoadmapStage]; activity: [CodingActivity] }
struct RoadmapStage { id; index; name; status /* done, current, next, final */; targetDate?; completedDate?; progress: Double; tasks: [RoadmapTask] }
struct RoadmapTask { id; title; status /* done, inReview, inProgress, todo, needsYou */ }
struct CodingActivity { start; end; projectID; insideFocusSessionID?; source /* agent, review, manual */ }

struct Memory { id; text; tag; createdAt; sourceThreadID? }
struct TodoItem { id; title; due?; projectID?; isDone }
struct Thread { id; title; messages: [Message] }
struct Message { id; role /* user, bt */; text?; insight?; resultCards: [ResultCard]; time }
struct ResultCard { id; kind /* calendar, memory, todo, status */; verb /* moved, added, saved, updated */; title; detail; deepLink?; isUndone }
struct LedgerEntry { id; time; kind; summary; undo: UndoToken }
```

Every BT action produces both a `ResultCard` in the thread **and** a `LedgerEntry`. Undo uses the ledger, and both views update.

## Cross-module links (must work in the real app)
- **Today:** agenda → Calendar Day · Code time cell → Code · Focus label → Focus · Reply / Ask BT → BT
- **Focus:** Hard stop → Calendar Day · BT note → BT
- **Calendar:** event "Start focus now" → Focus (pre-filled with the event's task and plan)
- **Code:** suggestions write to Calendar and Focus goals · "Ask about…" → BT, scoped to the project
- **BT:** result cards deep-link to the module they changed

## Real data sources (later)
- **Calendar:** EventKit (Apple and Google accounts through macOS Calendar), plus the Blackboard calendar feed for due dates. Due dates should become timed blocks, not all-day reminders.
- **Code activity:** editor and agent-session plugins, plus git for commits.
- **Music:** MusicKit / Now Playing info.
- **BT:** the BT assistant API, which needs tool calls that map to the actions above.

## Out of scope for the first pass
- Prev/next week data beyond the sample week.
- iOS layout (a separate design pass).
