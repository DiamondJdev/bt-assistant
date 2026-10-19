# Private NixOS server

BT runs as one server process for one owner. Your Mac and iPhone use the browser client at `/`. Voice supports one device at a time. Disconnect voice before sending typed messages in that conversation.

## Install

1. Place this checkout at `/opt/bt-assistant`, outside any user's home directory. Keep the checkout and `.venv` writable only by its administrator and readable/executable by the `bt` service user. Install dependencies on the server with the repository's Nix shell:

   ```sh
   cd /opt/bt-assistant
   nix develop ./nix --profile /opt/bt-assistant/.nix-runtime --command uv sync --frozen --no-dev --python python3.11 --no-python-downloads
   ```

   Python must come from Nix, not a downloaded uv interpreter under an administrator's home. Keep `.nix-runtime` and its profile generations in place: they retain the exact interpreter and libraries against Nix garbage collection. See [Nix development profiles](https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-develop). The service uses the installed environment directly and does not update it at startup. For reproducible upgrades, check out a reviewed commit and rerun this command while the service is stopped.

2. Optionally create `/etc/bt.env`, owned by root with mode `0600`, for provider settings and secrets. Keep secrets out of Nix expressions and Git.

   ```dotenv
   BT_OLLAMA_MODEL=qwen3:8b
   BT_WHISPER_DEVICE=cpu
   BT_WHISPER_COMPUTE=int8
   # Optional cloud fallback:
   # OPENAI_API_KEY=...
   ```

   Install the selected Ollama model before starting BT. Whisper's faster-whisper backend uses CPU or CUDA; an AMD GPU used by Ollama does not automatically accelerate Whisper. The first voice startup downloads Whisper, Piper and VAD assets into the service's writable cache. Allow network access during this setup.

3. Import the module in your NixOS configuration:

   ```nix
   {
     imports = [ /opt/bt-assistant/nix/module.nix ];
     services.bt-assistant.enable = true;
     services.ollama.enable = true;
     services.tailscale.enable = true;
   }
   ```

   Run your normal `nixos-rebuild` command. The service starts at boot and restarts after a crash. It uses `/var/lib/bt/bt.sqlite3` and `/var/cache/bt`, leaving the checkout read-only. Confirm startup with `systemctl status bt-assistant` and `journalctl -u bt-assistant -n 50`. BT fails startup when voice dependencies cannot load; `/health` alone does not verify inference.

4. Expose the loopback service privately:

   ```sh
   sudo tailscale serve --bg 8080
   tailscale serve status
   ```

   Open the reported HTTPS URL on your Mac or iPhone while connected to Tailscale. BT has no login, so the tailnet is the only access boundary. Configure tailnet grants so only your intended devices can reach this host on HTTPS. Keep port 8080 bound to `127.0.0.1`; do not open it to the LAN or Internet. Use Serve, not Funnel. See the [Tailscale Serve documentation](https://tailscale.com/docs/reference/tailscale-cli/serve).

5. Test typed chat and a foreground voice session from each device. Restart BT, reopen the browser, and confirm the conversation is restored. Check readiness with an authenticated `GET /ready`; it returns 503 if the database cannot be read, Ollama is unreachable, or the selected model is missing. Run a 24-hour trial before depending on the service daily.

The browser microphone needs HTTPS or localhost. iOS background/lock-screen listening and wake words are outside this release. Denying microphone permission leaves typed chat available. Every device that can reach BT sees every conversation; this is not a multi-user service. To revoke a device, remove its tailnet access.

## Backups and restore

`bt-backup.timer` runs daily and keeps the latest 14 snapshots under `/var/lib/bt/backups`. SQLite's backup API includes committed WAL writes. Each backup is integrity-checked and restricted to the service user. Copy snapshots to another machine for protection against server disk failure.

Run a backup now with `sudo systemctl start bt-backup`. Inspect its result with `journalctl -u bt-backup -n 20` and check the timer with `systemctl list-timers bt-backup`.

For a restore, first inspect the chosen snapshot with `sqlite3 /path/to/backup.sqlite3 'PRAGMA integrity_check;'`; the result must be `ok`. Stop BT. Preserve the current database and any WAL/SHM files before replacing anything:

```sh
sudo systemctl stop bt-assistant
sudo install -d -o bt -g bt -m 0700 /var/lib/bt/before-restore
# Move each existing bt.sqlite3, bt.sqlite3-wal and bt.sqlite3-shm into
# before-restore, using a fresh directory if an earlier restore exists.
# Then install the verified snapshot:
sudo install -o bt -g bt -m 0600 /path/to/backup.sqlite3 /var/lib/bt/bt.sqlite3
sudo systemctl start bt-assistant
```

Confirm an expected conversation is present before deleting any preserved files. Do not copy only the live database file while BT is running; use the backup command or service.

## Limits and recovery

Run one Uvicorn process. Conversation leases and voice capacity live in that process; adding workers would bypass them. A busy conversation returns HTTP 409 rather than mixing two devices' turns. Failed chat input remains in history and the client keeps the draft so you can retry deliberately.

Voice streams locally and falls back to cloud if the provider fails before producing response text. A failure after text starts surfaces an error instead of replaying an answer you have partly heard. Voice models are prepared during startup; after disconnect they are loaded in a background thread for the next connection. Reconnect can therefore take several seconds. The client mutes microphone transmission until you hold the talk button and never resumes recording automatically after a network interruption.

Keep `BT_DEVUI=0` in production. The `/` client works without developer routes. The old standalone dashboard is for localhost development; BT rejects cross-origin requests, so the dashboard cannot reach a remote server.

Local verification covers storage, HTTP/voice access, provider failure handling, backup restoration, queued-audio cancellation and reconnect state. NixOS module evaluation, real model throughput, device audio routes, reboot recovery and the 24-hour trial must run on the target server and devices.
