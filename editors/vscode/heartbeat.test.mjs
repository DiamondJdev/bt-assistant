import assert from "node:assert/strict";
import { test } from "node:test";
import heartbeat from "./heartbeat.js";

const { heartbeatLine, createThrottle, inboxFile } = heartbeat;

test("line has exactly the four keys and a trailing newline", () => {
	const line = heartbeatLine({ ts: 1792512000.5, project: "bt-assistant", language: "swift" });
	assert.ok(line.endsWith("\n"));
	const parsed = JSON.parse(line);
	assert.deepEqual(Object.keys(parsed).sort(), ["editor", "language", "project", "ts"]);
	assert.deepEqual(parsed, { ts: 1792512000.5, editor: "vscode", project: "bt-assistant", language: "swift" });
});

test("throttle allows the first beat and blocks a repeat inside a minute", () => {
	const shouldSend = createThrottle();
	assert.equal(shouldSend("bt", "swift", 0), true);
	assert.equal(shouldSend("bt", "swift", 59_999), false);
});

test("throttle allows a changed language or project immediately", () => {
	const shouldSend = createThrottle();
	assert.equal(shouldSend("bt", "swift", 0), true);
	assert.equal(shouldSend("bt", "python", 1_000), true);
	assert.equal(shouldSend("other", "python", 2_000), true);
});

test("throttle allows the same pair after a minute", () => {
	const shouldSend = createThrottle();
	assert.equal(shouldSend("bt", "swift", 0), true);
	assert.equal(shouldSend("bt", "swift", 60_000), true);
	assert.equal(shouldSend("bt", "swift", 61_000), false);
});

test("inbox file uses the local date", () => {
	const date = new Date(2026, 0, 5, 23, 30);
	assert.equal(inboxFile("/Users/me", date), "/Users/me/.bt/inbox/vscode-2026-01-05.jsonl");
});
