# Private NixOS server

BT runs as one server process for one owner. Your Mac and iPhone use the browser client at `/`. Voice supports one device at a time. Disconnect voice before sending typed messages in that conversation.

## Install

The systemd unit itself is not shipped from this repo — it lives in the host's own NixOS configuration, since it needs host-specific choices (service user, checkout path, state/cache directories). This repo only provides the application and its Nix dev shell.

1. The server runs releases that `bt-deploy` builds from `main` (see [Updates](#updates)), so production doesn't need a checkout. A manual checkout is for development. To set one up, install dependencies with the repository's Nix shell:

   ```sh
   cd bt-assistant/server
   nix develop ./nix --command uv sync --frozen --no-dev --python python3.11 --no-python-downloads
   ```

   The backend lives in the `server/` subdirectory, so the host module's working directory and executable are `<checkout>/server` and `<checkout>/server/.venv/bin/bt`. Python must come from Nix, not a downloaded uv interpreter. The host's systemd unit should run `server/.venv/bin/bt` directly rather than `uv run bt`, so the service never re-resolves the environment (or needs network access) at startup or on a crash restart. Each release that `bt-deploy` builds gets the same `uv sync --frozen` before its tests run.

2. Create `/etc/bt-assistant/bt.env`, owned by root with mode `0600`, for provider settings and secrets. The service won't start without it. Settings go here, not in a `.env` inside a checkout: a release built from git has no `.env`. Leave out `BT_HOST`, `BT_DB_PATH` and `BT_MEMORY_DIR`. The host module sets those, and values in this file would override them. Keep secrets out of Nix expressions and Git.

   ```dotenv
   BT_OLLAMA_MODEL=qwen3:8b
   BT_WHISPER_DEVICE=cpu
   BT_WHISPER_COMPUTE=int8
   # Optional cloud fallback:
   # OPENAI_API_KEY=...
   ```

   Install the selected Ollama model before starting BT. Whisper's faster-whisper backend uses CPU or CUDA; an AMD GPU used by Ollama does not automatically accelerate Whisper. The first voice startup downloads Whisper, Piper and VAD assets into the service's writable cache. Allow network access during this setup.

3. Enable the service in the host's NixOS configuration (module and options are host-specific; see that repo for `services.bt-assistant.*`):

   ```nix
   services.bt-assistant.enable = true;
   services.bt-deploy.enable = true;
   services.ollama.enable = true;
   services.tailscale.enable = true;
   ```

   Run your normal `nixos-rebuild` command. The service runs from `/var/lib/bt-deploy/current`, which doesn't exist until the first deploy, so BT stays down after the first switch until you run `bt-deploy now`. Log out and back in first so your user's new `systemd-journal` group applies. After that, the service starts at boot and restarts after a crash. The database and model cache live under directories systemd manages (`StateDirectory`/`CacheDirectory`); the code is read-only to the service, and the rest of the host's filesystem stays hidden from it. Confirm startup with `systemctl status bt-assistant` and `journalctl -u bt-assistant -n 50`. BT fails startup when voice dependencies cannot load; `/health` alone does not verify inference.

4. Expose the loopback service privately:

   ```sh
   sudo tailscale serve --bg 8080
   tailscale serve status
   ```

   Open the reported HTTPS URL on your Mac or iPhone while connected to Tailscale. BT has no login, so the tailnet is the only access boundary. Configure tailnet grants so only your intended devices can reach this host on HTTPS. Keep port 8080 bound to `127.0.0.1`; do not open it to the LAN or Internet. Use Serve, not Funnel. See the [Tailscale Serve documentation](https://tailscale.com/docs/reference/tailscale-cli/serve).

   The macOS app uses the same HTTPS address: enter it under BT › Settings. Its chat socket, `/chat/ws`, goes through the same Serve port, so no extra port is needed.

5. Test typed chat and a foreground voice session from each device. Restart BT, reopen the browser, and confirm the conversation is restored. Check readiness with an authenticated `GET /ready`; it returns 503 if the database cannot be read, Ollama is unreachable, or the selected model is missing. Run a 24-hour trial before depending on the service daily.

The browser microphone needs HTTPS or localhost. iOS background/lock-screen listening and wake words are outside this release. Denying microphone permission leaves typed chat available. Every device that can reach BT sees every conversation; this is not a multi-user service. To revoke a device, remove its tailnet access.

## Updates

The server deploys `main` by itself. Two minutes after the last check finished, a timer fetches `main` from GitHub. When it finds a new commit, `bt-deploy` exports it into `/var/lib/bt-deploy/releases/<sha>`, runs `uv sync` and `pytest` there as the service user, and only then backs up the database, points `current` at the new release and restarts BT. A merge to `main` is usually live a few minutes later, depending on how long the tests take. If `/ready` doesn't answer within 180 seconds, `current` goes back to the previous release and BT restarts on it.

Run these on the server as the owner, without `sudo`:

- `bt-deploy status` prints the last and next check, the newest commit on `main`, the commit under test, the live release, the commit the running process uses, and the last failure.
- `bt-deploy now` runs a check right away and streams its log. If the timer's check is already running, it waits for that one instead of starting a second.
- `bt-deploy log` shows the last 50 lines of the deploy journal. Extra arguments go to `journalctl`, for example `bt-deploy log -f`.

From a laptop, `dj deploy status`, `dj deploy now` and `dj deploy log` run the same commands over SSH.

A commit whose tests fail, or that doesn't become ready, is recorded in `/var/lib/bt-deploy/failed/<sha>` with a one-line reason and is never retried. The log shows `tests failed <sha>` or `not ready <sha>, rolled back to <sha>`, and later checks print `skipped, failed before`. To deploy a fix, merge a new commit.

Before each restart, `bt-deploy` copies the database to `/var/lib/bt-deploy/backups/<previous-sha>-<UTC time>.sqlite3` and keeps the five newest copies. A rollback only switches the code back. If the failed release ran a database migration before it stopped, the old code now sees the migrated schema. To undo that, stop BT and restore the matching backup by hand, following the steps in the next section.

## Backups and restore

`bt-deploy` backs up the database before every deploy that restarts BT (see Updates). Those copies live in `/var/lib/bt-deploy/backups/`, which only root can read, and only the five newest are kept. Nothing backs up the database between deploys, and nothing copies it off the server.

For a backup at any other time, use SQLite's online backup, which is safe while BT is writing. Copying the database file directly is not.

```sh
sqlite3 /path/to/bt.sqlite3 ".backup /path/to/snapshot.sqlite3"
sqlite3 /path/to/snapshot.sqlite3 "PRAGMA integrity_check;"  # must print "ok"
```

To restore, stop BT and keep a copy of the current database and any WAL/SHM files before replacing anything. Then put the snapshot in their place and start BT. Check that a conversation you expect is there before deleting the copies. A deploy backup needs `sudo` to read, and its name includes the commit that was live when it was taken.

## Limits and recovery

Run one Uvicorn process. Conversation leases and voice capacity live in that process; adding workers would bypass them. A busy conversation returns HTTP 409 rather than mixing two devices' turns. Failed chat input remains in history and the client keeps the draft so you can retry deliberately.

Voice streams locally and falls back to cloud if the provider fails before producing response text. A failure after text starts surfaces an error instead of replaying an answer you have partly heard. Voice models are prepared during startup; after disconnect they are loaded in a background thread for the next connection. Reconnect can therefore take several seconds. The client mutes microphone transmission until you hold the talk button and never resumes recording automatically after a network interruption.

Keep `BT_DEVUI=0` in production. The `/` client works without developer routes. The old standalone dashboard is for localhost development; BT rejects cross-origin requests, so the dashboard cannot reach a remote server.

Local verification covers storage, HTTP/voice access, provider failure handling, backup restoration, queued-audio cancellation and reconnect state. NixOS module evaluation, real model throughput, device audio routes, reboot recovery and the 24-hour trial must run on the target server and devices.
