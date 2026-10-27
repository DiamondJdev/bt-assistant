# Developer commands

Run these from the repository root. The wrappers in `scripts/dev.py` use only Python's standard library. They never install dependencies, write `.env` files, change the app's server address, or start the server when launching the app.

| Command | What it does |
| --- | --- |
| `make run` | Builds the diagnostic Debug app, then launches that exact `BT.app`. `make` alone does the same. |
| `make build MODE=profile` | Builds without launching. Modes are `debug` (default), `profile` and `release`. |
| `make test` | Runs the BTKit Swift tests. `SUITE=server` runs Python and server Node tests; `SUITE=all` adds the VS Code extension. |
| `make server` | Runs `bt-dev` in the foreground on port 8081. |
| `make logs CATEGORY=chat` | Streams BT's unified logs. Leave out `CATEGORY` to see every category. |
| `make help` | Lists the commands and this checkout's artifact folder. |

Unknown modes and suites fail before anything builds or runs.

## Prerequisites

- `make` and `python3` on `PATH`.
- For app commands: macOS and full Xcode, with `xcode-select -p` pointing at it.
- For server commands: `uv` and an existing `server/.venv`. Create it yourself with `cd server && uv sync --python 3.14`.
- For server and all-suite tests: Node.js with `node --test`.

## Build modes

| Mode | Xcode configuration | Diagnostics | Use it for |
| --- | --- | --- | --- |
| `debug` | Debug | Yes | Everyday work. `make run` uses it. |
| `profile` | Release, plus `-DBT_DIAGNOSTICS` | Yes | Instruments and timing numbers you can trust. |
| `release` | Release | No | Checking what users get. |

Each mode builds into its own derived-data folder, so switching modes never overwrites another mode's app. Every build stamps the current commit SHA and mode into the app's Info.plist (`BTBuildSHA`, `BTBuildMode`), and the Diagnostics window shows them. Uncommitted edits are built but don't change the SHA.

Running from Xcode's Run button uses Debug, so it has diagnostics too. Xcode's Profile action uses plain Release; for Instruments, build with `make build MODE=profile` and choose that app as the target.

## Relaunching

A failed build stops before anything launches. If BT is already running, `make run` asks before requesting a graceful quit. Without a terminal it refuses unless you pass `RELAUNCH=1`. It never force-kills: if BT is still running 10 seconds after the quit request (an open save prompt, for example), the new build doesn't launch.

## Focused tests

```sh
make test FILTER=ChatModelTests
make test SUITE=server FILTER=telemetry
make test SUITE=all
```

`FILTER` goes to Swift's `--filter`, pytest's `-k` and Node's `--test-name-pattern`. A filtered runner may select no tests if another runner in the requested suite has a match. The command fails when none of the runners select tests. Test failures and runner errors still stop the suite immediately.

The wrapper has its own tests, which mock every subprocess:

```sh
python3 -B -m unittest discover -s scripts -p 'test_dev.py'
```

## Artifacts and logs

Each checkout gets a stable folder at `/private/tmp/bt-dev-<uid>-<hash>/`, outside `~/Documents` to avoid the code-signing xattr problem. It holds `swift/` (test scratch), `derived-data-<mode>/` and `logs/`. Builds are incremental and nothing is cleaned automatically.

Every command prints the path of its full log. Output also streams to the terminal unchanged. Logs are kept until you delete them and can contain app output.

## Diagnostics

Debug and profile builds add a Developer menu with **Diagnostics…** (⌥⌘I, the same key as Safari's Web Inspector). It records each chat turn without storing message text, tool arguments or tool results:

- Client timings: total turn time, time to first visible text, and how many text updates arrived.
- Module context sent with the message, in characters against the 2,000-character budget, and how many module snapshots didn't fit.
- Per model call, from the server: provider and model, input and output tokens, observed tokens per second, time to first output and first visible text, and context use against the configured limit.
- Time spent in BT's own code (frame decoding, delta handling, Markdown parsing, message building, scrolling, history loads, tool runs, approval waits), shown as latest, p95 and max over the last 128 samples.
- A timeline of the last 500 events and a list of the last 50 turns.

**Export JSONL…** writes the build info, turns, events and timing samples to a file. The **Instruments signposts** switch adds intervals for the timed operations to the os_signpost stream, so they line up with the SwiftUI, Hangs and Time Profiler instruments. Timings measure BT's work, not the time to draw a frame; use Instruments for drawing, hitches, CPU and memory.

Observed tokens per second is output tokens divided by the whole call's duration, which includes prompt processing and network time. It reads lower than the engine's generation speed.

### Context window

The server reports context use only when it knows the real limit. Set all three in `server/.env` to the values Ollama actually runs with (its `num_ctx`, not the model's advertised maximum):

```sh
BT_CONTEXT_LIMIT_PROVIDER=ollama
BT_CONTEXT_LIMIT_MODEL=qwen3:8b
BT_CONTEXT_LIMIT=8192
```

Calls to any other provider or model show the limit as unavailable.

### Wire format

The app opts in per message with `"diagnostics": true` and a UUID `turn_id`. The server then sends `metrics` frames during the turn and adds `turn_id` and `metrics` to `done` and `error`. Servers without diagnostics ignore the extra fields, and older apps never ask for them. When diagnostics are on, server error logs carry the turn ID and error type but not the exception message.

### Log categories

`make logs CATEGORY=<name>` filters on one of `chat`, `transport`, `tools`, `context` or `performance`. Server-side, each finished turn logs one `text_chat_metrics` line under `bt.telemetry`.
