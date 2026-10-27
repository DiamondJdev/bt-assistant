#!/usr/bin/env python3
"""Run checkout-local development commands without changing app settings."""

import argparse
from collections import deque
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time


# Profile is an optimized Release build with diagnostics compiled in.
MODES = {"debug": "Debug", "profile": "Release", "release": "Release"}
BUNDLE_ID = "com.diamondjdev.bt"
APP_QUERY = (
    'ObjC.import("AppKit"); '
    f'var apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier("{BUNDLE_ID}"); '
)


class DevError(Exception):
    def __init__(self, message, code=1):
        super().__init__(message)
        self.code = code if code >= 0 else 128 - code


class Developer:
    def __init__(self, root):
        self.root = Path(root).resolve()
        checkout = hashlib.sha256(os.fsencode(self.root)).hexdigest()[:16]
        temporary = Path("/private/tmp" if sys.platform == "darwin" else "/tmp")
        self.cache = temporary / f"bt-dev-{os.getuid()}-{checkout}"

    def require(self, *tools):
        for tool in tools:
            if shutil.which(tool) is None:
                raise DevError(f"Missing prerequisite: {tool}. Install or select it yourself, then retry; nothing was installed.")

    def mac_tools(self, *tools):
        if sys.platform != "darwin":
            raise DevError("This command requires macOS and full Xcode. Server commands can run separately.")
        self.require(*tools)

    def run(self, command, cwd=None, capture=False, timeout=15):
        logs = self.cache / "logs"
        logs.mkdir(parents=True, exist_ok=True)
        descriptor, filename = tempfile.mkstemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), suffix=".log", dir=logs)
        print(f"Log: {filename}\n$ {shlex.join(command)}", flush=True)
        with os.fdopen(descriptor, "w") as logfile:
            logfile.write(f"cwd: {cwd or self.root}\n$ {shlex.join(command)}\n")
            logfile.flush()
            try:
                if capture:
                    result = subprocess.run(command, cwd=cwd or self.root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
                    output, code = result.stdout, result.returncode
                    print(output, end="", flush=True)
                    logfile.write(output)
                else:
                    process = subprocess.Popen(command, cwd=cwd or self.root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
                    chunks = deque(maxlen=200)
                    try:
                        for line in process.stdout:
                            print(line, end="", flush=True)
                            logfile.write(line)
                            logfile.flush()
                            chunks.append(line)
                        code = process.wait()
                    except KeyboardInterrupt:
                        process.send_signal(signal.SIGINT)
                        try:
                            remaining, _ = process.communicate(timeout=10)
                        except subprocess.TimeoutExpired:
                            logfile.write(f"\nInterrupted (exit 130); child PID {process.pid} did not exit.\n")
                            raise DevError(f"Interrupted; child PID {process.pid} has not exited. No force kill was sent. Log: {filename}", 130)
                        print(remaining, end="", flush=True)
                        logfile.write(remaining)
                        logfile.write("\nInterrupted (exit 130).\n")
                        raise DevError(f"Interrupted. Log: {filename}", 130)
                    finally:
                        process.stdout.close()
                    output = "".join(chunks)
            except subprocess.TimeoutExpired as error:
                partial = error.output or b""
                output = partial.decode(errors="replace") if isinstance(partial, bytes) else partial
                logfile.write(output)
                logfile.write("\nTimed out (exit 124).\n")
                raise DevError(f"Command timed out after {timeout} seconds; BT was not force-killed. Log: {filename}", 124) from error
            except OSError as error:
                logfile.write(f"\n{error}\n")
                raise DevError(f"Cannot run {command[0]}: {error}. Log: {filename}") from error
            logfile.write(f"\nExit code: {code}\n")
        if code:
            raise DevError(f"{command[0]} failed with exit code {code}. Full log: {filename}", code)
        return output

    def configuration(self, mode):
        if mode not in MODES:
            raise DevError(f"Unknown MODE={mode!r}; use debug, profile, or release.")
        return MODES[mode]

    def app_path(self, mode):
        return self.derived_data(mode) / "Build" / "Products" / self.configuration(mode) / "BT.app"

    def derived_data(self, mode):
        # One folder per mode, so profile and release never overwrite each other's app.
        return self.cache / f"derived-data-{mode}"

    def build(self, mode):
        configuration = self.configuration(mode)
        self.mac_tools("xcodebuild", "git")
        try:
            self.run(["xcodebuild", "-version"], capture=True)
        except DevError as error:
            raise DevError("Full Xcode is required. Check `xcode-select -p` and select your Xcode installation yourself. " + str(error), error.code) from error
        sha = self.run(["git", "rev-parse", "HEAD"], capture=True).strip()
        if re.fullmatch(r"[0-9a-fA-F]{40,64}", sha) is None:
            raise DevError("git rev-parse HEAD did not return a commit SHA; refusing to build with an unknown source revision.")
        self.run([
            "xcodebuild", "-project", str(self.root / "apple/BT.xcodeproj"),
            "-scheme", "BTMac", "-configuration", configuration,
            "-destination", "platform=macOS", "-derivedDataPath", str(self.derived_data(mode)),
            f"BT_BUILD_SHA={sha}", f"BT_BUILD_MODE={mode}",
            # Command-line settings reach the BTKit package targets too.
            *(["OTHER_SWIFT_FLAGS=$(inherited) -DBT_DIAGNOSTICS"] if mode == "profile" else []),
            "build",
        ])
        return self.app_path(mode)

    def running_apps(self, timeout=5):
        output = self.run([
            "osascript", "-l", "JavaScript", "-e", APP_QUERY
            + "var pids = []; for (var index = 0; index < apps.count; index++) { pids.push(Number(apps.objectAtIndex(index).processIdentifier)); } JSON.stringify(pids);",
        ], capture=True, timeout=timeout)
        try:
            pids = json.loads(output)
        except ValueError as error:
            raise DevError("Could not determine whether BT is running; refusing to launch another build.") from error
        if not isinstance(pids, list) or any(type(pid) is not int or pid <= 0 for pid in pids):
            raise DevError("Invalid running-app response; refusing to launch another build.")
        return pids

    def launch(self, mode, relaunch):
        app = self.build(mode)
        if not app.is_dir():
            raise DevError(f"Build succeeded but expected app is missing: {app}. Nothing was launched.")
        self.mac_tools("osascript", "open")
        if self.running_apps():
            if not relaunch:
                if not sys.stdin.isatty():
                    raise DevError("BT is already running. Quit it yourself or explicitly retry with RELAUNCH=1; nothing was launched.")
                if input("BT is running. Request a graceful quit and launch this build? [y/N] ").strip().lower() not in {"y", "yes"}:
                    raise DevError("Relaunch cancelled; the existing app was left running.")
            self.run([
                "osascript", "-l", "JavaScript", "-e", APP_QUERY
                + 'for (var index = 0; index < apps.count; index++) { if (!apps.objectAtIndex(index).terminate()) { throw new Error("BT declined to quit"); } }',
            ], capture=True, timeout=10)
            deadline = time.monotonic() + 10
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise DevError("BT is still running after 10 seconds. Finish any save prompt and quit it yourself; no force kill or launch was attempted.")
                if not self.running_apps(timeout=min(remaining, 2)):
                    break
                time.sleep(0.25)
        self.run(["open", "-n", str(app)])

    def server_command(self):
        self.require("uv")
        python = self.root / "server/.venv/bin/python"
        if not python.is_file():
            raise DevError("Missing server/.venv. Explicit setup: `cd server && uv sync --python 3.14`. This wrapper does not install dependencies or write environment files.")
        return ["uv", "run", "--no-sync", "--no-python-downloads", "--python", str(python)]

    def server(self):
        command = self.server_command()
        if not (self.root / "server/.venv/bin/bt-dev").is_file():
            raise DevError("Missing bt-dev entry point. Explicit setup: `cd server && uv sync --python 3.14`.")
        self.run(command + ["bt-dev"], cwd=self.root / "server")

    def test(self, suite, test_filter):
        if suite not in {"swift", "server", "all"}:
            raise DevError(f"Unknown SUITE={suite!r}; use swift, server, or all.")
        selected = False
        if suite in {"swift", "all"}:
            self.mac_tools("swift")
            command = ["swift", "test", "--package-path", str(self.root / "apple/BTKit"), "--scratch-path", str(self.cache / "swift")]
            if test_filter:
                command += ["--filter", test_filter]
            output = self.run(command)
            selected |= any(int(count) > 0 for count in re.findall(r"(?:Executed |Test run with )(\d+) tests?", output))
        if suite in {"server", "all"}:
            command = self.server_command()
            self.require("node")
            self.run(command + ["python", "-c", "import pytest"], cwd=self.root / "server")
            python_tests = command + ["python", "-m", "pytest", "-q"]
            if test_filter:
                python_tests += ["-k", test_filter]
            try:
                self.run(python_tests, cwd=self.root / "server")
                selected = True
            except DevError as error:
                if not test_filter or error.code != 5:
                    raise
            selected |= self.node_tests(self.node_files("server/tests", self.root / "server"), self.root / "server", test_filter)
        if suite == "all":
            # Pass files, not the folder: Node would load extension.js, which needs VS Code.
            selected |= self.node_tests(self.node_files("editors/vscode", self.root), self.root, test_filter)
        if test_filter and not selected:
            raise DevError(f"FILTER={test_filter!r} selected zero tests across SUITE={suite} (or the runners reported no count).")

    def node_files(self, folder, cwd):
        files = sorted(str(path.relative_to(cwd)) for path in (self.root / folder).glob("*.test.mjs"))
        if not files:
            raise DevError(f"No {folder}/*.test.mjs files found; refusing an empty Node test run.")
        return files

    def node_tests(self, paths, cwd, test_filter):
        command = ["node", "--test", "--test-reporter=tap"]
        if test_filter:
            command += ["--test-name-pattern", test_filter]
        output = self.run(command + paths, cwd=cwd)
        passed = sum(int(count) for count in re.findall(r"^# pass (\d+)\s*$", output, re.MULTILINE))
        empty_files = len(re.findall(r"^1\.\.0\s*$", output, re.MULTILINE))
        return not test_filter or passed > empty_files

    def logs(self, category):
        self.mac_tools("log")
        predicate = '(process == "BT" OR subsystem == "BT" OR subsystem == "BTKit" OR subsystem == "com.diamondjdev.bt")'
        if category:
            predicate += " AND category == " + json.dumps(category)
        self.run(["log", "stream", "--style", "compact", "--level", "debug", "--predicate", predicate])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["run", "build", "test", "server", "logs", "help"])
    args = parser.parse_args()
    developer = Developer(Path(__file__).resolve().parent.parent)
    try:
        if args.command == "run":
            relaunch = os.environ.get("RELAUNCH", "0")
            if relaunch not in {"0", "1"}:
                raise DevError("RELAUNCH must be 0 or 1.")
            developer.launch(os.environ.get("MODE", "debug"), relaunch == "1")
        elif args.command == "build":
            developer.build(os.environ.get("MODE", "debug"))
        elif args.command == "test":
            developer.test(os.environ.get("SUITE", "swift"), os.environ.get("FILTER", ""))
        elif args.command == "server":
            developer.server()
        elif args.command == "logs":
            developer.logs(os.environ.get("CATEGORY", ""))
        else:
            print("make run [MODE=debug|profile|release] [RELAUNCH=1]\nmake build MODE=debug|profile|release\nmake test [SUITE=swift|server|all] [FILTER=pattern]\nmake server\nmake logs [CATEGORY=category]\nSee docs/DEVELOPMENT.md.\nArtifacts: " + str(developer.cache))
        return 0
    except DevError as error:
        print(f"Error: {error}", file=sys.stderr)
        return error.code
    except (KeyboardInterrupt, EOFError):
        print("Cancelled; nothing else was launched.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
