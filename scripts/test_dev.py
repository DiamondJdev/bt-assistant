import importlib.util
import io
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("bt_dev", Path(__file__).with_name("dev.py"))
dev = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dev)


class DeveloperCommandsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve() / "checkout"
        self.root.mkdir()
        self.wrapper = dev.Developer(self.root)
        self.wrapper.cache = Path(self.temporary.name) / "cache"
        self.commands = []

    def fake_run(self, command, **kwargs):
        self.commands.append((command, kwargs))
        output = ""
        if command[:2] == ["git", "rev-parse"]:
            output = "a" * 40 + "\n"
        if command[0] == "swift":
            output = "Executed 2 tests, with 0 failures\n"
        if command[0] == "node":
            output = "# tests 2\n# pass 2\n# skipped 0\n"
        return output

    def install_fixture(self):
        for filename in ("server/.venv/bin/python", "server/.venv/bin/bt-dev", "server/tests/audio.test.mjs", "editors/vscode/heartbeat.test.mjs"):
            target = self.root / filename
            target.parent.mkdir(parents=True, exist_ok=True)
            target.touch()

    def build_fixture(self, mode="debug"):
        app = self.wrapper.app_path(mode)
        app.mkdir(parents=True)
        return app

    def test_cache_is_stable_unique_and_outside_documents(self):
        first = dev.Developer(Path("/Users/test/Documents/first"))
        again = dev.Developer(Path("/Users/test/Documents/first"))
        second = dev.Developer(Path("/Users/test/Documents/second"))
        self.assertEqual(first.cache, again.cache)
        self.assertNotEqual(first.cache, second.cache)
        self.assertNotIn("Documents", first.cache.parts)

    def test_unknown_mode_and_suite_fail_before_commands(self):
        with patch.object(self.wrapper, "run", side_effect=self.fake_run):
            with self.assertRaises(dev.DevError):
                self.wrapper.build("fast")
            with self.assertRaises(dev.DevError):
                self.wrapper.test("backend", "")
        self.assertEqual(self.commands, [])

    def test_modes_build_incrementally_with_source_sha(self):
        with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            for mode, configuration in dev.MODES.items():
                self.wrapper.build(mode)
                command = self.commands[-1][0]
                self.assertIn(configuration, command)
                self.assertIn("BT_BUILD_SHA=" + "a" * 40, command)
                self.assertIn("BT_BUILD_MODE=" + mode, command)
                self.assertIn(str(self.wrapper.cache / f"derived-data-{mode}"), command)
                self.assertNotIn("clean", command)
                diagnostics = [arg for arg in command if "-DBT_DIAGNOSTICS" in arg]
                self.assertEqual(bool(diagnostics), mode == "profile")

    def test_profile_and_release_never_share_build_products(self):
        self.assertNotEqual(self.wrapper.app_path("profile"), self.wrapper.app_path("release"))

    def test_build_failure_never_launches(self):
        with patch.object(self.wrapper, "build", side_effect=dev.DevError("failed", 65)), patch.object(self.wrapper, "run") as run:
            with self.assertRaises(dev.DevError) as error:
                self.wrapper.launch("debug", False)
        self.assertEqual(error.exception.code, 65)
        run.assert_not_called()

    def test_launch_uses_exact_built_app(self):
        app = self.build_fixture()
        with patch.object(self.wrapper, "build", return_value=app), patch.object(self.wrapper, "running_apps", return_value=[]), patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.launch("debug", False)
        self.assertEqual(self.commands[-1][0], ["open", "-n", str(app)])

    def test_missing_app_never_launches(self):
        with patch.object(self.wrapper, "build", return_value=self.wrapper.app_path("debug")), patch.object(self.wrapper, "run") as run:
            with self.assertRaises(dev.DevError):
                self.wrapper.launch("debug", False)
        run.assert_not_called()

    def test_noninteractive_running_app_requires_explicit_relaunch(self):
        app = self.build_fixture()
        with patch.object(self.wrapper, "build", return_value=app), patch.object(self.wrapper, "running_apps", return_value=[123]), patch.object(self.wrapper, "mac_tools"), patch("sys.stdin.isatty", return_value=False), patch.object(self.wrapper, "run") as run:
            with self.assertRaisesRegex(dev.DevError, "RELAUNCH=1"):
                self.wrapper.launch("debug", False)
        run.assert_not_called()

    def test_relaunch_terminates_gracefully_before_open(self):
        app = self.build_fixture()
        with patch.object(self.wrapper, "build", return_value=app), patch.object(self.wrapper, "running_apps", side_effect=[[123], []]), patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.launch("debug", True)
        self.assertIn("terminate()", self.commands[0][0][-1])
        self.assertEqual(self.commands[-1][0], ["open", "-n", str(app)])

    def test_cancelled_confirmation_does_not_terminate(self):
        app = self.build_fixture()
        with patch.object(self.wrapper, "build", return_value=app), patch.object(self.wrapper, "running_apps", return_value=[123]), patch.object(self.wrapper, "mac_tools"), patch("sys.stdin.isatty", return_value=True), patch("builtins.input", return_value="no"), patch.object(self.wrapper, "run") as run:
            with self.assertRaises(dev.DevError):
                self.wrapper.launch("debug", False)
        run.assert_not_called()

    def test_relaunch_timeout_does_not_launch_or_force_kill(self):
        app = self.build_fixture()
        with patch.object(self.wrapper, "build", return_value=app), patch.object(self.wrapper, "running_apps", return_value=[123]), patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", side_effect=self.fake_run), patch("time.monotonic", side_effect=[0, 11]):
            with self.assertRaisesRegex(dev.DevError, "still running"):
                self.wrapper.launch("debug", True)
        self.assertEqual(len(self.commands), 1)

    def test_default_swift_test_and_literal_filter(self):
        with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.test("swift", "CalendarTests/testSave")
        command = self.commands[0][0]
        self.assertEqual(command[:2], ["swift", "test"])
        self.assertEqual(command[-2:], ["--filter", "CalendarTests/testSave"])
        self.assertIn(str(self.wrapper.cache / "swift"), command)

    def test_swift_zero_tests_fails_even_when_runner_exits_successfully(self):
        with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", return_value="Executed 0 tests, with 0 failures\n✔ Test run with 0 tests passed after 0.001 seconds.\n"):
            with self.assertRaisesRegex(dev.DevError, "zero tests"):
                self.wrapper.test("swift", "does-not-exist")

    def test_swift_testing_positive_count_is_accepted(self):
        with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", return_value="Executed 0 tests, with 0 failures\n✔ Test run with 3 tests passed after 0.1 seconds.\n"):
            self.wrapper.test("swift", "Example")

    def test_pytest_failure_stops_later_suites_and_keeps_code(self):
        self.install_fixture()
        def fail_pytest(command, **kwargs):
            if "pytest" in command:
                raise dev.DevError("Tests failed", 1)
            return self.fake_run(command, **kwargs)
        with patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=fail_pytest):
            with self.assertRaises(dev.DevError) as error:
                self.wrapper.test("server", "missing")
        self.assertEqual(error.exception.code, 1)
        self.assertFalse(any(command[0] == "node" for command, _ in self.commands))

    def test_missing_tool_is_an_actionable_error(self):
        with patch("shutil.which", return_value=None):
            with self.assertRaisesRegex(dev.DevError, "Missing prerequisite: uv"):
                self.wrapper.require("uv")

    def test_server_filter_is_forwarded_without_shell_expansion(self):
        self.install_fixture()
        with patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.test("server", "audio")
        python_test = next(command for command, _ in self.commands if "pytest" in command)
        node_test = next(command for command, _ in self.commands if command[0] == "node")
        self.assertEqual(python_test[-2:], ["-k", "audio"])
        self.assertIn("--test-name-pattern", node_test)
        self.assertIn("audio", node_test)

    def test_server_and_all_suites(self):
        self.install_fixture()
        with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.test("all", "")
        commands = [entry[0] for entry in self.commands]
        python_test = next(command for command in commands if "pytest" in command)
        self.assertEqual(python_test[-4:], ["python", "-m", "pytest", "-q"])
        self.assertIn("--no-sync", python_test)
        self.assertIn("--no-python-downloads", python_test)
        self.assertEqual(sum(command[0] == "node" for command in commands), 2)
        # A bare folder makes Node load extension.js, which needs VS Code.
        self.assertTrue(any(command[-1] == "editors/vscode/heartbeat.test.mjs" for command in commands))
        self.assertEqual(next(kwargs["cwd"] for command, kwargs in self.commands if "pytest" in command), self.root / "server")

    def test_filtered_suites_require_a_collective_match(self):
        self.install_fixture()
        for suite, selected in (("server", "python"), ("server", "server-node"), ("all", "python"), ("all", "server-node"), ("all", "editor-node"), ("all", "swift"), ("server", None), ("all", None)):
            with self.subTest(suite=suite, selected=selected):
                self.commands.clear()
                def filtered_run(command, **kwargs):
                    self.commands.append((command, kwargs))
                    if "pytest" in command:
                        if selected != "python":
                            raise dev.DevError("No tests collected", 5)
                        return "1 passed\n"
                    if command[0] == "swift":
                        return f"Executed {int(selected == 'swift')} tests, with 0 failures\n"
                    if command[0] == "node":
                        runner = "editor-node" if command[-1].startswith("editors/") else "server-node"
                        if selected == runner:
                            return "# tests 1\n# pass 1\n# fail 0\n"
                        return "1..0\n# Subtest: empty.test.mjs\nok 1 - empty.test.mjs\n1..1\n# tests 1\n# pass 1\n# fail 0\n"
                    return ""
                with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=filtered_run):
                    if selected:
                        self.wrapper.test(suite, "example")
                    else:
                        with self.assertRaisesRegex(dev.DevError, "zero tests"):
                            self.wrapper.test(suite, "example")
                self.assertEqual(sum(command[0] == "node" for command, _ in self.commands), 2 if suite == "all" else 1)

    def test_node_empty_filter_output_is_not_a_match(self):
        for output in (
            "# tests 8\n# pass 0\n# fail 0\n# skipped 8\n",
            "1..0\n1..0\n1..2\n# tests 2\n# pass 2\n# fail 0\n",
            "no test counts\n",
        ):
            with self.subTest(output=output), patch.object(self.wrapper, "run", return_value=output):
                self.assertFalse(self.wrapper.node_tests(["example.test.mjs"], self.root, "missing"))

    def test_node_match_with_an_empty_file_is_accepted(self):
        with patch.object(self.wrapper, "run", return_value="1..0\n# tests 2\n# pass 2\n# fail 0\n"):
            self.assertTrue(self.wrapper.node_tests(["example.test.mjs"], self.root, "example"))

    def test_later_runner_failures_override_earlier_matches(self):
        self.install_fixture()
        for failing in ("swift", "server-node", "editor-node"):
            with self.subTest(failing=failing):
                def fail_runner(command, **kwargs):
                    runner = command[0]
                    if runner == "node":
                        runner = "editor-node" if command[-1].startswith("editors/") else "server-node"
                    if runner == failing:
                        raise dev.DevError("Tests failed", 2)
                    return self.fake_run(command, **kwargs)
                with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=fail_runner):
                    with self.assertRaises(dev.DevError) as error:
                        self.wrapper.test("all", "example")
                self.assertEqual(error.exception.code, 2)

    def test_unfiltered_pytest_empty_selection_keeps_exit_code(self):
        self.install_fixture()
        def empty_pytest(command, **kwargs):
            if "pytest" in command:
                raise dev.DevError("No tests collected", 5)
            return self.fake_run(command, **kwargs)
        with patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=empty_pytest):
            with self.assertRaises(dev.DevError) as error:
                self.wrapper.test("server", "")
        self.assertEqual(error.exception.code, 5)

    def test_missing_server_environment_has_explicit_setup_guidance(self):
        with patch.object(self.wrapper, "require"):
            with self.assertRaisesRegex(dev.DevError, "uv sync --python 3.14"):
                self.wrapper.server()

    def test_server_is_foreground_existing_entrypoint(self):
        self.install_fixture()
        with patch.object(self.wrapper, "require"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.server()
        self.assertEqual(self.commands[-1][0][-1], "bt-dev")
        self.assertEqual(self.commands[-1][1]["cwd"], self.root / "server")

    def test_log_category_cannot_inject_a_predicate(self):
        with patch.object(self.wrapper, "mac_tools"), patch.object(self.wrapper, "run", side_effect=self.fake_run):
            self.wrapper.logs('Chat" OR TRUEPREDICATE OR category == "')
        predicate = self.commands[-1][0][-1]
        self.assertIn('category == "Chat\\" OR TRUEPREDICATE OR category == \\""', predicate)

    def test_run_streams_full_output_and_preserves_failure_code(self):
        process = unittest.mock.MagicMock()
        process.stdout = io.StringIO("first\nlast\n")
        process.wait.return_value = 65
        with patch("subprocess.Popen", return_value=process) as popen, patch("sys.stdout", new_callable=io.StringIO) as output:
            with self.assertRaises(dev.DevError) as error:
                self.wrapper.run(["fake-build"])
        self.assertEqual(error.exception.code, 65)
        self.assertIn("first\nlast", output.getvalue())
        self.assertIn("first\nlast", next((self.wrapper.cache / "logs").glob("*.log")).read_text())
        self.assertFalse(popen.call_args.kwargs.get("shell", False))


if __name__ == "__main__":
    unittest.main()
