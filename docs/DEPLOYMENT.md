# Private NixOS server

BT runs as one server process for one owner. Your Mac and iPhone use the browser client at `/`. Voice supports one device at a time. Disconnect voice before sending typed messages in that conversation.

## Install

The systemd unit itself is not shipped from this repo — it lives in the host's own NixOS configuration, since it needs host-specific choices (service user, checkout path, state/cache directories). This repo only provides the application and its Nix dev shell.

1. Clone this checkout wherever the host's module expects it (readable/executable by whichever user the module runs the service as). Install dependencies with the repository's Nix shell:

   ```sh
   cd bt-assistant/server
   nix develop ./nix --command uv sync --frozen --no-dev --python python3.11 --no-python-downloads
   ```

   The backend lives in the `server/` subdirectory, so the host module's working directory and executable are `<checkout>/server` and `<checkout>/server/.venv/bin/bt`. Python must come from Nix, not a downloaded uv interpreter. The host's systemd unit should run `server/.venv/bin/bt` directly rather than `uv run bt`, so the service never re-resolves the environment (or needs network access) at startup or on a crash restart. For reproducible upgrades, check out a reviewed commit and rerun `uv sync` while the service is stopped.

2. Optionally create `/etc/bt.env`, owned by root with mode `0600`, for provider settings and secrets. Keep secrets out of Nix expressions and Git.

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
   services.ollama.enable = true;
   services.tailscale.enable = true;
   ```

   Run your normal `nixos-rebuild` command. The service starts at boot and restarts after a crash. The database and model cache live under directories systemd manages (`StateDirectory`/`CacheDirectory`), outside the checkout, which otherwise stays sandboxed off the rest of the host's filesystem. Confirm startup with `systemctl status bt-assistant` and `journalctl -u bt-assistant -n 50`. BT fails startup when voice dependencies cannot load; `/health` alone does not verify inference.

4. Expose the loopback service privately:

   ```sh
   sudo tailscale serve --bg 8080
   tailscale serve status
   ```

   Open the reported HTTPS URL on your Mac or iPhone while connected to Tailscale. BT has no login, so the tailnet is the only access boundary. Configure tailnet grants so only your intended devices can reach this host on HTTPS. Keep port 8080 bound to `127.0.0.1`; do not open it to the LAN or Internet. Use Serve, not Funnel. See the [Tailscale Serve documentation](https://tailscale.com/docs/reference/tailscale-cli/serve).

5. Test typed chat and a foreground voice session from each device. Restart BT, reopen the browser, and confirm the conversation is restored. Check readiness with an authenticated `GET /ready`; it returns 503 if the database cannot be read, Ollama is unreachable, or the selected model is missing. Run a 24-hour trial before depending on the service daily.

The browser microphone needs HTTPS or localhost. iOS background/lock-screen listening and wake words are outside this release. Denying microphone permission leaves typed chat available. Every device that can reach BT sees every conversation; this is not a multi-user service. To revoke a device, remove its tailnet access.

## Backups and restore

No automated backup timer is wired up yet — that's a gap in the current deployment, not a feature of this release. Until one exists, back up manually with SQLite's online backup API (safe against a running writer) rather than copying the database file directly:

```sh
sqlite3 /path/to/bt.sqlite3 ".backup /path/to/snapshot.sqlite3"
sqlite3 /path/to/snapshot.sqlite3 "PRAGMA integrity_check;"  # must print "ok"
```

For a restore, stop BT first and preserve the current database and any WAL/SHM files before replacing anything, then install the verified snapshot in their place and restart the service. Confirm an expected conversation is present before deleting any preserved files.

## Limits and recovery

Run one Uvicorn process. Conversation leases and voice capacity live in that process; adding workers would bypass them. A busy conversation returns HTTP 409 rather than mixing two devices' turns. Failed chat input remains in history and the client keeps the draft so you can retry deliberately.

Voice streams locally and falls back to cloud if the provider fails before producing response text. A failure after text starts surfaces an error instead of replaying an answer you have partly heard. Voice models are prepared during startup; after disconnect they are loaded in a background thread for the next connection. Reconnect can therefore take several seconds. The client mutes microphone transmission until you hold the talk button and never resumes recording automatically after a network interruption.

Keep `BT_DEVUI=0` in production. The `/` client works without developer routes. The old standalone dashboard is for localhost development; BT rejects cross-origin requests, so the dashboard cannot reach a remote server.

Local verification covers storage, HTTP/voice access, provider failure handling, backup restoration, queued-audio cancellation and reconnect state. NixOS module evaluation, real model throughput, device audio routes, reboot recovery and the 24-hour trial must run on the target server and devices.
