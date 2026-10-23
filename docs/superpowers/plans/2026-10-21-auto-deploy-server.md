# BT Auto-Deploy (Server) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The home server deploys each new commit on `main` by itself, after tests pass, and the owner can trigger a check by hand and see when checks ran and which commit is being tested and which is live.

**Architecture:** A new NixOS module, `bt-deploy`, adds a oneshot service and a timer. The service mirrors the public GitHub repo, builds each new commit into `/var/lib/bt-deploy/releases/<sha>`, runs `pytest` there as the service user, switches the `current` symlink, restarts `bt-assistant`, and rolls back if `/ready` doesn't answer. One shell script, `bt-deploy`, is both the service's entry point (`run`) and the owner's command (`status`, `now`, `log`). The `dj` side is a separate plan: `djCLI/docs/superpowers/plans/2026-10-21-dj-deploy.md`.

**Tech Stack:** NixOS modules, systemd timers, polkit, bash (`pkgs.writeShellApplication`, which runs shellcheck at build time), git, uv, Python 3.11.

**Spec:** No separate spec file. The design was agreed in chat on 2026-10-21 and is summarized under Design below.

## Design

- Every 2 minutes (counted from the end of the last run), fetch `main` over HTTPS. If its commit equals the live commit, or has already failed, log one line and exit 0.
- Otherwise: write the sha to `testing`, export the tree into `releases/<sha>`, `uv sync`, run `pytest`. If that fails, write `failed/<sha>` with a reason and exit 1. Failed commits are never retried.
- On success: back up the SQLite database, point `current` at the new release, restart `bt-assistant`, and poll `/ready`. If it isn't ready in time, point `current` back, restart again, write `failed/<sha>` and exit 1.
- `bt-deploy now` starts the same systemd unit and streams its log, so a manual run and a timer run can never overlap.
- `bt-deploy status` shows the last and next check, `origin/main`, the commit under test, the live commit on disk, the commit the running process actually uses, and the last failure.

State layout, all under `/var/lib/bt-deploy/`:

| Path | Owner | Meaning |
| --- | --- | --- |
| `repo.git` | service user | Bare mirror of the repo |
| `releases/<sha>/` | service user | One exported, synced and tested tree per commit |
| `current` | root | Symlink to the live release |
| `testing` | root | Sha under test; removed when the run ends |
| `failed/<sha>` | root | Reason the commit failed (one line) |
| `backups/<old-sha>-<UTC time>.sqlite3` | root | DB snapshot taken before each restart |

## Global Constraints

- Tasks 1–3 run on the server (hostname `nixos`) in the flake repo `~/nixos` (`github.com/DiamondJdev/nixos`), and paths are relative to it. Work on a new branch `feat/bt-deploy` cut from `feat/bt`, not `main`: `feat/bt` holds the current `bt-assistant` module and is far ahead of `main`. Leave the uncommitted `modules/home/` changes alone, and never stage them.
- Flakes only see files git knows about. `git add` new files before any `nixos-rebuild`, or the build reports the module as missing.
- Repo URL: `https://github.com/DiamondJdev/bt-assistant.git` (public, no key). Branch: `main`.
- Check interval: `2min`. Readiness timeout: `180` seconds (cold model loading is slow; the unit already allows `TimeoutStartSec = "300s"`).
- Readiness URL: `http://127.0.0.1:8080/ready`.
- Releases kept: the 3 newest plus whatever `current` points at. Backups kept: 5 newest.
- Python: `pkgs.python311` and `pkgs.uv`, with `uv sync --frozen --python <python311>/bin/python3.11 --no-python-downloads`. Tests: `.venv/bin/python -m pytest -q` from `server/` (never `uv run pytest`; see the `.pth` note in `AGENTS.md`).
- Build and test steps never run as root. They run as `config.services.bt-assistant.user` through `runuser -u <user> --`.
- Commit messages follow `<type>: <description>`.

## Review Focus

1. **The live service never sees a half-built tree.** `current` changes with `ln -sfn` to a temp name plus `mv -T`, never by overwriting a directory. Pinned by the "tests fail" case in Task 1.
2. **A crash mid-run leaves a stale `testing` file.** `run` removes it in an `EXIT` trap. Pinned by the "tests fail" case (file is gone after a failing run).
3. **The first ever run has no `current` and nothing to roll back to.** If `/ready` fails then, remove `current`, mark the commit failed, and exit 1 instead of crashing. Pinned by the "first deploy not ready" case in Task 1.
4. **`status` runs as the owner over SSH, not as root.** Every file it reads must be world-readable, and it must not need `sudo`. Checked by hand in Task 3, step 5.
5. **Settings from the gitignored `.env` vanish in a release.** `main.py` loads `server/.env` relative to the code, and a release built from git doesn't have one. Task 2 moves those settings to an `EnvironmentFile`, and Task 3 checks the running process sees `BT_OLLAMA_MODEL`.

---

### Task 1: `bt-deploy` script with a local test

**Files:**
- Create: `modules/nixos/bt-deploy/bt-deploy.sh`
- Test: `modules/nixos/bt-deploy/test.sh`

**Interfaces:**
- Produces: `bt-deploy <run|status|now|log>`. Every path and command comes from these environment variables, which the module sets and the test overrides:

| Variable | Module value |
| --- | --- |
| `BT_DEPLOY_STATE` | `/var/lib/bt-deploy` |
| `BT_DEPLOY_REPO_URL` | repo URL above |
| `BT_DEPLOY_BRANCH` | `main` |
| `BT_DEPLOY_USER` | `services.bt-assistant.user` |
| `BT_DEPLOY_SERVICE` | `bt-assistant.service` |
| `BT_DEPLOY_READY_URL` | readiness URL above |
| `BT_DEPLOY_READY_TIMEOUT` | `180` |
| `BT_DEPLOY_DB` | `/var/lib/bt-assistant/bt.sqlite3` |
| `BT_DEPLOY_CHECK` | shell command run as the user inside `releases/<sha>/server`; module value: `uv sync --frozen --python $PY --no-python-downloads && .venv/bin/python -m pytest -q` |

- Log lines from `run` (the journal is the history, so the format matters for `status`):
  - `check origin=<short> live=<short|none> → no change`
  - `check origin=<short> live=<short> → skipped, failed before: <reason>`
  - `check origin=<short> live=<short> → testing`
  - `deployed <short>` / `tests failed <short>` / `not ready <short>, rolled back to <short|none>`

- [ ] **Step 1: Write `test.sh`**

A plain bash script, no framework. It makes a temp dir with a local git repo (one commit on `main`, then a second), a stub `bin/` first on `PATH` with `systemctl`, `runuser`, `curl` and `sqlite3`, and sets every `BT_DEPLOY_*` variable to point inside the temp dir. Stubs append their arguments to `calls.log`. `runuser -u x -- cmd…` runs `cmd…`. `curl` exits with the contents of `ready.code` (0 or 22). `BT_DEPLOY_CHECK` is `test ! -e FAIL`, so a commit containing a file named `FAIL` fails its tests. `BT_DEPLOY_READY_TIMEOUT=2`.

Cases, each asserting with `[ … ] || { echo "FAIL: <case>"; exit 1; }`:

1. **First deploy:** `run` exits 0; `readlink current` ends in sha1; `calls.log` has exactly one `systemctl restart bt-assistant.service`; `testing` doesn't exist.
2. **No change:** second `run` exits 0, no new restart, and stdout contains `→ no change`.
3. **New commit passes:** commit 2, `run` exits 0, `current` → sha2, one `sqlite3` call whose args contain `.backup`.
4. **Tests fail:** commit 3 adds `FAIL`. `run` exits 1, `current` still → sha2, `failed/<sha3>` exists, `testing` gone, no restart.
5. **Failed commit is skipped:** `run` again exits 0 and prints `skipped, failed before`.
6. **Not ready → rollback:** commit 4 (no `FAIL`), `ready.code` = 22. `run` exits 1, `current` → sha2, two restarts recorded, `failed/<sha4>` contains `not ready`.
7. **First deploy not ready:** fresh state dir, `ready.code` = 22. `run` exits 1, `current` doesn't exist, `failed/<sha1>` exists.
8. **Status:** `status` exits 0 and prints lines starting `origin/main:`, `testing:` (value `idle`), `live:` and `last failed:` (sha4 short plus `not ready`).
9. **Pruning:** after 5 passing commits, `releases/` holds at most 3 entries plus the one `current` targets.

Finish with `echo "all bt-deploy tests passed"`.

- [ ] **Step 2: Run it and watch it fail**

Run: `bash modules/nixos/bt-deploy/test.sh`
Expected: fails at case 1 because `bt-deploy.sh` doesn't exist.

- [ ] **Step 3: Implement `bt-deploy.sh`**

`set -euo pipefail`. Dispatch on `$1`:

- `run`: requires the env vars above (fail with the variable's name if one is missing). The state dir is root-owned, so create `repo.git` and `releases/` first and `chown` them to the user. Only do the `chown` when running as root, so the test can run unprivileged. Clone `repo.git` as the user with `git clone --bare` on first use, then `git fetch --prune origin +refs/heads/$BRANCH:refs/heads/$BRANCH` as the user. Then the flow in Design. Export the tree with `git archive <sha> | tar -x -C releases/<sha>` as the user, deleting any half-built `releases/<sha>` first. Readiness: `curl -fsS --max-time 5` once a second until the timeout. The backup goes to `backups/` with `sqlite3 "$BT_DEPLOY_DB" ".backup <path>"`; skip it with a log line if the DB file doesn't exist. Prune releases and backups after a successful deploy.
- `status`: read-only, works as a non-root user. "Last check" is the last line of `journalctl -u bt-deploy -n 1 -o short-iso`. "Next check" comes from `systemctl show bt-deploy.timer -p NextElapseUSecRealtime --value`. "Running" is `basename` of `dirname` of `readlink /proc/<MainPID>/cwd`, where the PID comes from `systemctl show $BT_DEPLOY_SERVICE -p MainPID --value`. Print `unknown` when the PID is 0 or `/proc` is missing. All shas are shown as 7-character short shas.
- `now`: `journalctl -fu bt-deploy -n 0 &`, then `systemctl start bt-deploy.service` (this blocks until the oneshot ends, and joins a run already in progress), then kill the follower, print `status`, and exit with the start command's exit code.
- `log`: `journalctl -u bt-deploy -n 50 --no-pager "${@:2}"`.
- Anything else: print `usage: bt-deploy <status|now|log>` to stderr and exit 2.

- [ ] **Step 4: Run the tests**

Run: `bash modules/nixos/bt-deploy/test.sh`
Expected: `all bt-deploy tests passed`.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/bt-deploy/bt-deploy.sh modules/nixos/bt-deploy/test.sh
git commit -m "feat: add bt-deploy script with local tests"
```

### Task 2: NixOS module and `bt-assistant` changes

**Files:**
- Create: `modules/nixos/bt-deploy/default.nix`
- Modify: `modules/nixos/bt-assistant.nix` (`serviceConfig` block, and a new `EnvironmentFile`)
- Modify: `hosts/desktop/default.nix`: add `../../modules/nixos/bt-deploy` to `imports`, set `services.bt-deploy.enable = true;`

**Interfaces:**
- Consumes: `bt-deploy.sh` and its env vars from Task 1; `config.services.bt-assistant.{user,projectDir}`; `config.systemd.services.bt-assistant.environment.LD_LIBRARY_PATH`.
- Produces: options `services.bt-deploy.enable`, `.repoUrl` (default the repo URL), `.branch` (`"main"`), `.interval` (`"2min"`), `.readyTimeout` (`180`). Units `bt-deploy.service` and `bt-deploy.timer`. Command `bt-deploy` on the system `PATH`.

- [ ] **Step 1: Write `default.nix`**

- `pkgs.writeShellApplication { name = "bt-deploy"; text = builtins.readFile ./bt-deploy.sh; runtimeInputs = [ git gnutar coreutils curl sqlite util-linux systemd uv python311 ]; }`.
- Put the `BT_DEPLOY_*` values in one attrset. Use it as the service's `environment`, and wrap the package for `environment.systemPackages` with `pkgs.symlinkJoin` + `makeWrapper --set …` so `bt-deploy status` gets the same values over SSH.
- `systemd.services.bt-deploy`: `Type = "oneshot"`, `ExecStart = "${pkg}/bin/bt-deploy run"`, `StateDirectory = "bt-deploy"`, `StateDirectoryMode = "0755"`, `TimeoutStartSec = "30min"`, `after`/`wants` `network-online.target`. Also set `environment.LD_LIBRARY_PATH` from `bt-assistant`'s environment, because the tests import numpy and onnxruntime. Set `UV_CACHE_DIR = "/var/lib/bt-deploy/uv-cache"` and add that dir to the ones `run` creates and `chown`s. Without it, uv running under `runuser` inherits root's `HOME` and can't write its cache. No `wantedBy`; only the timer starts it.
- `systemd.timers.bt-deploy`: `wantedBy = [ "timers.target" ]`, `OnBootSec = "2min"`, `OnUnitInactiveSec = cfg.interval`.
- `services.bt-assistant.projectDir = "/var/lib/bt-deploy/current";` (the module derives `serverDir` from it).
- `users.users.${user}.extraGroups = [ "systemd-journal" ];`
- `security.polkit.extraConfig`: allow `subject.user == "<user>"` the action `org.freedesktop.systemd1.manage-units` only when `action.lookup("unit") == "bt-deploy.service"` and `action.lookup("verb") == "start"`.

- [ ] **Step 2: Change the `bt-assistant` module**

- Delete `BindPaths` and `ReadWritePaths`. `ProtectHome = "tmpfs"` doesn't hide `/var/lib`, and `ProtectSystem = "strict"` already makes it read-only, which is what production needs for its code. Don't bind-mount `current`: it's a symlink, and the bind would pin whichever release was live at boot.
- Add `EnvironmentFile = "/etc/bt-assistant/bt.env";` (required, no `-` prefix: starting without the model settings is worse than not starting). Remove the commented-out `secretsFile` option.
- Update the module's header comment: production runs from `/var/lib/bt-deploy/current`; `~/Projects/bt-assistant` is the dev checkout only.

- [ ] **Step 3: Create the env file on the server**

Copy the provider settings from `~/Projects/bt-assistant/server/.env` (not the topology values the module already sets) into `/etc/bt-assistant/bt.env`, owned by `root:root`, mode `0600`.

- [ ] **Step 4: Build without switching**

Run: `nixos-rebuild build --flake ~/nixos#nixos`
Expected: the build succeeds (it also passes shellcheck) and nothing restarts.

- [ ] **Step 5: Commit**

```bash
git add modules/nixos/bt-deploy/default.nix modules/nixos/bt-assistant.nix hosts/desktop/default.nix
git commit -m "feat: deploy bt-assistant from main with tests and rollback"
```

### Task 3: First switch and acceptance on the server

**Files:** none.

**Interfaces:**
- Consumes: everything from Tasks 1–2.

- [ ] **Step 1: Switch.** Run `sudo nixos-rebuild switch --flake ~/nixos#nixos`. BT goes down here until step 2 finishes, because `current` doesn't exist yet. Expect a few minutes of downtime.
- [ ] **Step 2: First deploy by hand.** Log out and back in so the `systemd-journal` group applies, then run `bt-deploy now`. Expected: the log streams through `testing` and ends with `deployed <sha>`, which is the same commit as `git ls-remote https://github.com/DiamondJdev/bt-assistant.git main`.
- [ ] **Step 3: Live service is healthy.** `curl -fsS http://127.0.0.1:8080/ready` returns `"status":"ready"`, and `sudo cat /proc/$(systemctl show bt-assistant -p MainPID --value)/environ | tr '\0' '\n' | grep BT_OLLAMA_MODEL` prints your model.
- [ ] **Step 4: Timer runs.** `systemctl list-timers bt-deploy.timer` shows a next run within 2 minutes. After it fires, `bt-deploy log` ends with `→ no change`.
- [ ] **Step 5: Status as the owner, no sudo.** `bt-deploy status` prints all six fields, and `running:` equals `live:`.
- [ ] **Step 6: Merge a trivial PR** to `main` (a docs typo). Within about 5 minutes `bt-deploy status` shows the new commit as live, with no SSH session needed.

### Task 4: Update `docs/DEPLOYMENT.md` in bt-assistant

**Files:**
- Modify: `docs/DEPLOYMENT.md` (Install steps 1–3, plus a new "Updates" section after Install)

- [ ] **Step 1: Edit the doc.** Run the `humanizer:humanizer` skill on the new text. Changes:
  - Install step 1: the server runs releases built by `bt-deploy`; a manual checkout is for development.
  - Install step 2: settings go in `/etc/bt-assistant/bt.env`, not in a `.env` inside the checkout.
  - New "Updates" section: merges to `main` deploy within about 2 minutes after the tests pass. Cover `bt-deploy status | now | log` (and `dj deploy …` from a laptop), what a failed commit looks like, where DB backups go, and that a code rollback doesn't undo a database migration (restore a backup from `/var/lib/bt-deploy/backups/` by hand).
- [ ] **Step 2: Commit**

```bash
git add docs/DEPLOYMENT.md
git commit -m "docs: Describe automatic deploys from main"
```
