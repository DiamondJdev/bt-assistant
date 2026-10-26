const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vscode = require("vscode");
const { heartbeatLine, createThrottle, inboxFile } = require("./heartbeat.js");

function activate(context) {
	const output = vscode.window.createOutputChannel("BT Heartbeat");
	const shouldSend = createThrottle();

	function beat(document, force) {
		try {
			if (!document || document.uri.scheme !== "file") return;
			const folder = vscode.workspace.getWorkspaceFolder(document.uri);
			if (!folder) return;
			const project = folder.name;
			const language = document.languageId;
			const now = Date.now();
			if (!shouldSend(project, language, now, force)) return;
			const file = inboxFile(os.homedir(), new Date(now));
			fs.mkdirSync(path.dirname(file), { recursive: true });
			fs.appendFileSync(file, heartbeatLine({ ts: now / 1000, project, language }));
		} catch (error) {
			output.appendLine(`Could not write heartbeat: ${error.message}`);
		}
	}

	context.subscriptions.push(
		output,
		vscode.workspace.onDidChangeTextDocument((event) => beat(event.document, false)),
		vscode.workspace.onDidSaveTextDocument((document) => beat(document, true)),
		vscode.window.onDidChangeActiveTextEditor((editor) => beat(editor?.document, false)),
	);
}

function deactivate() {}

module.exports = { activate, deactivate };
