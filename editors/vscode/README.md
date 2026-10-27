# BT heartbeat for VS Code

Records coding time for the BT Mac app. The extension has no dependencies and no build step.

## Install

From the repository root:

```sh
ln -s "$PWD/editors/vscode" ~/.vscode/extensions/diamondjdev.bt-heartbeat-0.0.1
```

Then reload VS Code (Developer: Reload Window).

## What it records

On text changes, saves and active editor changes, the extension appends one line to `~/.bt/inbox/vscode-YYYY-MM-DD.jsonl`:

```json
{"ts": 1792512000.5, "editor": "vscode", "project": "bt-assistant", "language": "swift"}
```

`project` is the workspace folder name and `language` is VS Code's language ID. It writes at most one line a minute for the same project and language, and writes at once when either changes or you save.

It never records file paths, file names or file contents. Files outside a workspace folder and unsaved buffers are ignored. Write errors go to the "BT Heartbeat" output channel.

## Test

```sh
node --test editors/vscode/*.test.mjs
```
