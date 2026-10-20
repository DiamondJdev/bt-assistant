// Pure heartbeat helpers. No `vscode` import, so tests run under plain node.
const path = require("node:path");

const THROTTLE_MS = 60_000;

/** One JSON line. Only these four fields leave the editor: no paths, no contents. */
function heartbeatLine({ ts, project, language }) {
	return JSON.stringify({ ts, editor: "vscode", project, language }) + "\n";
}

/** Returns `shouldSend(project, language, nowMs)`: true when the pair changed or `intervalMs` passed. */
function createThrottle(intervalMs = THROTTLE_MS) {
	let last = null;
	return (project, language, nowMs) => {
		if (last && last.project === project && last.language === language && nowMs - last.at < intervalMs) {
			return false;
		}
		last = { project, language, at: nowMs };
		return true;
	};
}

/** `<home>/.bt/inbox/vscode-YYYY-MM-DD.jsonl`, using the local date. */
function inboxFile(home, date) {
	const pad = (n) => String(n).padStart(2, "0");
	const day = `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
	return path.join(home, ".bt", "inbox", `vscode-${day}.jsonl`);
}

module.exports = { heartbeatLine, createThrottle, inboxFile };
