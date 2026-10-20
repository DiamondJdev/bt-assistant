# Server and client readiness implementation plan

> Implement inline using Ponytail and regression tests. The user authorized issues 1 through 4 from the readiness review.

Goal: run one private BT server for the owner's Mac and iPhone.

Architecture: retain FastAPI, SQLite and Pipecat. Serve a small browser client from the same origin. Use one shared access token with an HTTP-only browser cookie; native/API callers use a bearer token. Keep one server process and one active voice connection to bound model memory.

Constraints: preserve existing transcripts, local-first inference, voice streaming and existing routing fixes on main. No account system, native apps, new database or frontend framework. Do not deploy, change the host firewall, or call paid models during tests.

1. Conversation safety: tests for recent history, unknown sessions and overlapping turns; add a shared conversation lease and bounded session listing. Preserve the recent-history fix already on main.
2. Private gateway: tests for HTTP and WebSocket authentication, same-origin browser access, input validation and readiness failure; add token login/logout and service lifecycle cleanup.
3. Voice: test malformed frames and routing; retain Pipecat streaming, bound connections and model loading, fix interruption playback, and report setup failures. Add the platform dependency needed by Pipecat on Apple Silicon.
4. Browser client: test audio cancellation and reconnect state with Node; build typed chat, saved session selection, transcript restoration, push-to-talk and explicit voice disconnect. Reuse existing audio wire format.
5. Operations: add a NixOS module, restart policy, persistent paths, daily SQLite backup and restore instructions. Verify backups against a real temporary database. Run Python and Node tests, inspect the complete diff, and obtain a fresh review.

Verification: pytest, Node's test runner, Python compilation, dependency lock check, HTTP smoke checks, browser inspection if available. Nix evaluation and real iPhone/NixOS audio require their target environments.

Progress: implemented on `codex/server-client-readiness`, based on main `554c2cd`. All five tasks are complete. Verification: 38 Python tests, 4 Node tests, compilation, dependency lock check and browser login/chat/history restoration passed. The browser smoke test used a fake provider. Apple Silicon Whisper imports passed outside the sandbox.

Review: an independent reviewer found a browser WebSocket rejection/retry bug and an unretained Nix interpreter. The rejection fix passed tests that require the upgrade before the close code. Deployment now uses a persistent development profile to retain the interpreter. Nix evaluation and garbage-collection behavior cannot be exercised on this Mac because Nix is absent.

Limits: one owner and one server process; one voice connection; no native apps or background iPhone listening. Live NixOS model throughput, device audio, reboot recovery and a 24-hour trial remain deployment checks. Unrelated AGENTS.md and CLAUDE.md files were left untouched.
