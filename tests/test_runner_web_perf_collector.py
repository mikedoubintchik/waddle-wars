"""Real-localhost contract tests for the write-once runner QA collector."""

import copy
from contextlib import redirect_stderr, redirect_stdout
import functools
import hashlib
import http.client
from http.server import ThreadingHTTPServer
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
import zipfile
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "runner_web_perf_collector_target", ROOT / "tools/qa/runner_web_perf.py"
)
COLLECTOR_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(COLLECTOR_MODULE)
TRACE_LIMIT = 32 * 1024 * 1024


class QuietCollector(COLLECTOR_MODULE.Collector):
    def log_message(self, _format, *_args):
        pass


class RunnerWebPerfCollectorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="runner-collector-test-")
        self.addCleanup(temporary.cleanup)
        self.output = Path(temporary.name)
        web = self.output / "web"
        web.mkdir()
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(QuietCollector, directory=str(web))
        )
        self.server.daemon_threads = True
        self.server.run_id = "runner-web-collector-test"
        self.server.entry = "runner"
        self.server.output = self.output
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )
        self.thread.start()
        self.addCleanup(self._stop_server)

    def _stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.assertFalse(self.thread.is_alive(), "collector thread did not stop")

    def _trace(self):
        return {
            "run_id": self.server.run_id,
            "target_url": self.origin + "/index.html",
            "renderer_pid": 123,
            "capture": {"method": "Tracing.start", "scope": "target renderer"},
            "traceEvents": [
                {"name": "thread_name", "ph": "M", "pid": 123, "tid": 7,
                 "args": {"name": "CrRendererMain"}},
                {"name": "RunTask", "ph": "X", "pid": 123, "tid": 7,
                 "ts": 100, "dur": 20, "args": {}},
            ],
        }

    def _request(self, path="/trace", payload=None, *, body=None, headers=None):
        if body is None and payload is not None:
            body = json.dumps(payload).encode("utf-8")
        request_headers = {
            "Host": self.origin.removeprefix("http://"),
            "Origin": self.origin,
            "Content-Type": "application/json",
        }
        for key, value in (headers or {}).items():
            if value is None:
                request_headers.pop(key, None)
            else:
                request_headers[key] = value
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.server.server_port, timeout=2
        )
        try:
            connection.request("POST", path, body=body, headers=request_headers)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def _assert_rejected(self, payload, status=400, **kwargs):
        actual, _ = self._request(payload=payload, **kwargs)
        self.assertEqual(status, actual)
        self.assertFalse((self.output / "chrome_trace.json").exists())
        self.assertFalse((self.output / "browser_report.json").exists())

    def test_valid_trace_saved_without_report_side_effects(self):
        payload = self._trace()
        status, body = self._request(payload=payload)
        self.assertEqual(201, status)
        self.assertEqual({"saved": True}, json.loads(body))
        saved = json.loads((self.output / "chrome_trace.json").read_text())
        self.assertEqual(payload, saved)
        for name in ("browser_report.json", "report.json", "report.csv"):
            self.assertFalse((self.output / name).exists())

    def test_duplicate_trace_is_conflict_and_preserves_original(self):
        payload = self._trace()
        self.assertEqual(201, self._request(payload=payload)[0])
        original = (self.output / "chrome_trace.json").read_bytes()
        replacement = copy.deepcopy(payload)
        replacement["capture"]["method"] = "different capture"
        self.assertEqual(409, self._request(payload=replacement)[0])
        self.assertEqual(original, (self.output / "chrome_trace.json").read_bytes())

    def test_foreign_or_missing_origin_rejected(self):
        for origin in ("https://example.invalid", "http://localhost:1234", None):
            with self.subTest(origin=origin):
                self._assert_rejected(
                    self._trace(), 403, headers={"Origin": origin}
                )

    def test_wrong_host_rejected_even_with_correct_origin(self):
        self._assert_rejected(
            self._trace(), 403, headers={"Host": "example.invalid"}
        )

    def test_renderer_pid_requires_positive_non_boolean_integer(self):
        for pid in (0, -1, True, False, 123.0, "123", None):
            with self.subTest(pid=pid):
                payload = self._trace()
                payload["renderer_pid"] = pid
                # Match event values as well: type validation must not be
                # accidentally satisfied by Python's True == 1 semantics.
                for event in payload["traceEvents"]:
                    event["pid"] = pid
                self._assert_rejected(payload)

    def test_every_event_pid_matches_renderer_exact_integer(self):
        for pid in (124, True, 123.0, "123", None):
            with self.subTest(pid=pid):
                payload = self._trace()
                payload["traceEvents"][-1]["pid"] = pid
                self._assert_rejected(payload)
        payload = self._trace()
        del payload["traceEvents"][-1]["pid"]
        self._assert_rejected(payload)

    def test_trace_events_require_list_of_objects(self):
        for events in ({}, "events", None, [None], [123]):
            with self.subTest(events=events):
                payload = self._trace()
                payload["traceEvents"] = events
                self._assert_rejected(payload)

    def test_target_url_must_match_exact_local_index(self):
        for target in (
            "https://example.invalid/index.html",
            self.origin + "/other.html",
            self.origin + "/index.html?webgltrace=1",
            self.origin + "/index.html#trace",
            None,
        ):
            with self.subTest(target=target):
                payload = self._trace()
                payload["target_url"] = target
                self._assert_rejected(payload)

    def test_run_id_and_capture_metadata_validated(self):
        for run_id in ("another-run", "", None, 123):
            with self.subTest(run_id=run_id):
                payload = self._trace()
                payload["run_id"] = run_id
                self._assert_rejected(payload)
        for capture in (None, [], "metadata", True):
            with self.subTest(capture=capture):
                payload = self._trace()
                payload["capture"] = capture
                self._assert_rejected(payload)

    def test_undeclared_envelope_field_rejected(self):
        payload = self._trace()
        payload["unfiltered_trace"] = [{"pid": 999, "name": "other renderer"}]
        self._assert_rejected(payload)

    def test_json_content_type_required(self):
        for content_type in (None, "text/plain", "application/json; charset=utf-8"):
            with self.subTest(content_type=content_type):
                self._assert_rejected(
                    self._trace(), 413, headers={"Content-Type": content_type}
                )

    def test_malformed_json_or_non_object_payload_rejected(self):
        for body in (b"{invalid", b"[]", b"null"):
            with self.subTest(body=body):
                self._assert_rejected(None, body=body)

    def test_oversized_declared_length_rejected_before_body_read(self):
        # Deliberately send no body. Waiting for the declared bytes would hit
        # the client timeout; a correct collector immediately returns 413.
        self._assert_rejected(
            None, 413, headers={"Content-Length": str(TRACE_LIMIT + 1)}
        )

    def test_empty_body_rejected(self):
        self._assert_rejected(None, 413, body=b"")

    def test_report_size_rejection_returns_http_413(self):
        for size in (0, COLLECTOR_MODULE.MAX_REPORT_BYTES + 1):
            with self.subTest(size=size):
                status, _ = self._request(
                    "/report", headers={"Content-Length": str(size)}
                )
                self.assertEqual(413, status)
                self.assertFalse((self.output / "browser_report.json").exists())

    def test_report_behavior_and_trace_are_independent(self):
        report = {
            "run_id": self.server.run_id,
            "browser": {"ending_visibility": "visible"},
            "report": {"average_fps": 60, "meets_gate": True},
            "csv": "frame,ms\n1,16.7\n",
        }
        self.assertEqual(201, self._request("/report", report)[0])
        self.assertEqual(
            report, json.loads((self.output / "browser_report.json").read_text())
        )
        self.assertEqual(
            report["report"], json.loads((self.output / "report.json").read_text())
        )
        self.assertEqual(report["csv"], (self.output / "report.csv").read_text())
        self.assertEqual(201, self._request(payload=self._trace())[0])
        self.assertEqual(409, self._request("/report", report)[0])
        self.assertEqual(409, self._request(payload=self._trace())[0])

    def test_error_report_remains_supported(self):
        payload = {"run_id": self.server.run_id, "browser": {}, "error": "probe failed"}
        self.assertEqual(201, self._request("/report", payload)[0])
        self.assertEqual(
            payload, json.loads((self.output / "browser_report.json").read_text())
        )
        self.assertFalse((self.output / "report.json").exists())
        self.assertFalse((self.output / "report.csv").exists())

    def test_app_lifecycle_report_is_explicit_and_never_creates_fps_csv(self):
        self.server.entry = "app"
        payload = {
            "kind": "app_lifecycle",
            "run_id": self.server.run_id,
            "browser": {"entry": "app", "ending_visibility": "visible"},
            "report": {
                "schema_version": 1,
                "measurement_kind": "app_lifecycle",
                "scope": "Explicit browser-side lifecycle snapshot",
                "performance_gate_applicable": False,
                "engine_fps_report_present": False,
                "meets_gate": False,
                "complete_production": False,
            },
        }
        self.assertEqual(201, self._request("/report", payload)[0])
        self.assertEqual(payload, json.loads(
            (self.output / "browser_report.json").read_text()))
        self.assertFalse((self.output / "report.json").exists())
        self.assertFalse((self.output / "report.csv").exists())

    def test_app_lifecycle_error_uses_explicit_schema_without_gate_artifacts(self):
        self.server.entry = "app"
        payload = {
            "kind": "app_lifecycle", "run_id": self.server.run_id,
            "browser": {"entry": "app"}, "error": "engine failed",
            "error_source": "engine_start",
        }
        self.assertEqual(201, self._request("/report", payload)[0])
        self.assertEqual(payload, json.loads(
            (self.output / "browser_report.json").read_text()))
        self.assertFalse((self.output / "report.json").exists())
        self.assertFalse((self.output / "report.csv").exists())

    def test_entry_specific_report_kinds_cannot_cross_collectors(self):
        app = {
            "kind": "app_lifecycle", "run_id": self.server.run_id,
            "browser": {}, "report": {"schema_version": 1,
                "measurement_kind": "app_lifecycle", "scope": "explicit snapshot",
                "performance_gate_applicable": False,
                "engine_fps_report_present": False, "meets_gate": False,
                "complete_production": False},
        }
        self.assertEqual(400, self._request("/report", app)[0])
        self.assertFalse((self.output / "browser_report.json").exists())
        self.server.entry = "app"
        runner = {"run_id": self.server.run_id, "browser": {},
                  "report": {"average_fps": 60, "meets_gate": True}, "csv": "fps\n60\n"}
        self.assertEqual(400, self._request("/report", runner)[0])
        self.assertFalse((self.output / "browser_report.json").exists())


class RunnerWebPerfThreadExportTests(unittest.TestCase):
    """Tiny local fixtures only: no repository copy, browser or engine process."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="runner-thread-export-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "harness"
        self.source = Path(temporary.name) / "source"
        for name in COLLECTOR_MODULE.RESOURCES:
            (self.source / name).mkdir(parents=True)
        (self.root / "tests").mkdir(parents=True)
        (self.root / "tools/qa").mkdir(parents=True)
        (self.source / "project.godot").write_text(
            '[application]\nconfig/name="Thread test"\n'
            'run/main_scene="res://scenes/original.tscn"\n'
            '[rendering]\nrenderer/rendering_method="mobile"\n'
        )
        (self.source / "export_presets.cfg").write_bytes(
            (ROOT / "export_presets.cfg").read_bytes()
        )
        (self.source / "tests/runner_perf_probe.gd").write_text("extends Node\n")
        for name in COLLECTOR_MODULE.RUNNER_QA_ADAPTER_FILES:
            (self.root / "tests" / name).write_text(f"current test adapter: {name}\n")
        (self.source / "tests/runner_perf_probe.gd").write_bytes(
            (self.root / "tests/runner_perf_probe.gd").read_bytes())
        (self.root / "tools/qa/runner_web_perf_shell.html").write_text(
            '<!doctype html><head><style>@@CANVAS_CSS@@</style>\n'
            '@@CANVAS_POLICY_HEAD@@</head><body>\n'
            '<canvas id="canvas"@@CANVAS_ATTRIBUTES@@></canvas>\n'
            '<script>const config = @@RUN_CONFIG@@;</script>\n'
            '</body>\n'
        )
        self.root_patch = mock.patch.object(COLLECTOR_MODULE, "ROOT", self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def _prepare(
        self, threads=False, canvas_policy=None, msaa="default", render_scale=None,
        entry="runner", extra=()
    ):
        args = ["runner_web_perf.py", "prepare", "unit", "--source", str(self.source)]
        if entry != "runner":
            args.extend(["--entry", entry])
        if threads:
            args.append("--threads")
        if canvas_policy is not None:
            args.extend(["--canvas-policy", canvas_policy])
        if msaa != "default":
            args.extend(["--msaa", msaa])
        if render_scale is not None:
            args.extend(["--render-scale", str(render_scale)])
        args.extend(extra)
        output = io.StringIO()
        with mock.patch.object(COLLECTOR_MODULE.sys, "argv", args), \
                mock.patch.object(COLLECTOR_MODULE.subprocess, "run") as process, \
                redirect_stdout(output):
            COLLECTOR_MODULE.main()
        process.assert_not_called()
        run = Path(output.getvalue().splitlines()[0])
        self.assertEqual(self.root / "qa_shots/runner", run.parent)
        return run

    def _assert_threads(self, run, expected):
        manifest = json.loads((run / "manifest.json").read_text())
        config = json.loads((run / "project/tests/runner_web_perf_config.json").read_text())
        shell = (run / "project/tests/runner_web_perf_shell.html").read_text()
        embedded = json.loads(shell.split("const config = ", 1)[1].split(";</script>", 1)[0])
        for value in (manifest["config"]["threads"], config["threads"], embedded["threads"]):
            self.assertIs(type(value), bool)
            self.assertIs(value, expected)
        self.assertEqual(manifest["config"], config)
        self.assertEqual(config, embedded)
        self.assertEqual("runner", config["entry"])
        self.assertEqual("default", config["msaa_override"])
        self.assertIsNone(config["render_scale_override"])
        self.assertEqual("fixed", config["canvas_policy"])
        self.assertEqual("fixed", manifest["canvas_policy"]["mode"])
        self.assertEqual("runner", manifest["entry"]["mode"])
        self.assertEqual("res://scenes/original.tscn", manifest["entry"]["source_main_scene"])
        self.assertEqual("res://tests/runner_web_perf.tscn", manifest["entry"]["export_main_scene"])
        self.assertTrue(manifest["entry"]["performance_gate_applicable"])
        self.assertIn('renderer/rendering_method="gl_compatibility"',
                      (run / "project/project.godot").read_text())
        self.assertEqual("", config["canvas_policy_source_sha256"])
        self.assertEqual("", config["canvas_policy_fragment_sha256"])
        self.assertFalse(manifest["canvas_policy"]["complete_production"])
        self.assertIn('width="1920" height="1080"', shell)
        for marker, _digest in COLLECTOR_MODULE.PRODUCTION_CANVAS_SCRIPTS:
            self.assertNotIn(marker, shell)
        preset = (run / "project/export_presets.cfg").read_text().splitlines()
        self.assertEqual(
            [line for line in preset if line.startswith("variant/thread_support=")],
            ["variant/thread_support=" + str(expected).lower()],
        )
        self.assertTrue(manifest["original_probe_unchanged"])
        self.assertEqual(
            manifest["export_presets_sha256"],
            hashlib.sha256((run / "project/export_presets.cfg").read_bytes()).hexdigest(),
        )
        self.assertFalse((self.source / "tests/runner_web_perf_config.json").exists())

    def test_prepare_threads_defaults_false_everywhere(self):
        self._assert_threads(self._prepare(), False)

    def test_prepare_threads_opt_in_true_everywhere(self):
        self._assert_threads(self._prepare(threads=True), True)

    def test_prepare_includes_runtime_json_catalogs_for_real_menu_workload(self):
        # Godot's all_resources omits plain JSON unless explicitly included.
        # Missing these silently invalidates full-app wardrobe/commerce probes.
        run = self._prepare()
        preset = (run / "project/export_presets.cfg").read_text()
        self.assertIn('include_filter="tests/runner_web_perf_config.json,'
                      'data/wardrobe/*.json,data/commerce/*.json"', preset)

    def _template(self):
        path = self.root / "test-engine.zip"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("godot.js", "// host-only engine fixture")
            archive.writestr("godot.wasm", b"\x00asm\x01\x00\x00\x00")
        return path

    def test_custom_template_is_copied_pinned_and_recorded_without_global_install(self):
        source = self._template()
        original = source.read_bytes()
        run = self._prepare(threads=True, extra=("--template-release", str(source)))
        source.write_bytes(b"source may change after isolated copy")
        self.assertEqual(original, (run / "engine-template.zip").read_bytes())
        manifest = json.loads((run / "manifest.json").read_text())
        receipt = manifest["engine_template"]
        self.assertEqual(hashlib.sha256(original).hexdigest(), receipt["sha256"])
        self.assertEqual(len(original), receipt["bytes"])
        self.assertEqual("engine-template.zip", receipt["copied_path"])
        self.assertEqual(receipt["sha256"], manifest["config"]["engine_template_sha256"])
        build = self._mock_build(run)
        self.assertEqual(receipt, build["engine_template"])

    def test_custom_template_invalid_archive_or_debug_mode_rejected_before_writes(self):
        source = self._template()
        parent = self.root / "qa_shots/runner"
        for label, mutate, extra in (
                ("debug", False, ("--debug",)),
                ("invalid zip", True, ())):
            with self.subTest(reason=label):
                if mutate:
                    source.write_bytes(b"not a zip")
                before = set(parent.iterdir()) if parent.exists() else set()
                with self.assertRaises(SystemExit):
                    self._prepare(extra=("--template-release", str(source), *extra))
                self.assertEqual(before, set(parent.iterdir()) if parent.exists() else set())

    def test_custom_template_mutation_or_missing_receipt_rejected_before_engine(self):
        source = self._template()
        for mutation in ("zip", "receipt", "config", "path"):
            with self.subTest(mutation=mutation):
                run = self._prepare(extra=("--template-release", str(source)))
                path = run / "manifest.json"
                manifest = json.loads(path.read_text())
                if mutation == "zip":
                    with zipfile.ZipFile(run / "engine-template.zip", "a") as archive:
                        archive.writestr("changed.txt", "changed after prepare")
                elif mutation == "receipt":
                    del manifest["engine_template"]
                elif mutation == "config":
                    manifest["config"]["engine_template_sha256"] = "0" * 64
                else:
                    manifest["engine_template"]["copied_path"] = "../outside.zip"
                path.write_text(json.dumps(manifest))
                self._assert_build_rejected_before_side_effects(run)

    def test_frozen_runtime_receives_complete_current_runner_adapter(self):
        (self.source / "tests/runner_perf_probe.gd").write_text("older frozen probe\n")
        original_probe = (self.source / "tests/runner_perf_probe.gd").read_bytes()
        run = self._prepare()
        manifest = json.loads((run / "manifest.json").read_text())
        self.assertIs(manifest["original_probe_unchanged"], False)
        for name in COLLECTOR_MODULE.RUNNER_QA_ADAPTER_FILES:
            self.assertEqual((self.root / "tests" / name).read_bytes(),
                             (run / "project/tests" / name).read_bytes())
        self.assertEqual(original_probe, (self.source / "tests/runner_perf_probe.gd").read_bytes())
        self.assertFalse((self.source / "tests/runner_web_mesh_preflight.gd").exists())

    def test_prepare_app_defaults_to_production_canvas_and_preserves_main_and_governor(self):
        run = self._prepare(entry="app")
        manifest = json.loads((run / "manifest.json").read_text())
        config = json.loads((run / "project/tests/runner_web_perf_config.json").read_text())
        project = (run / "project/project.godot").read_text()
        shell = (run / "project/tests/runner_web_perf_shell.html").read_text()
        embedded = json.loads(shell.split("const config = ", 1)[1].split(";</script>", 1)[0])
        self.assertEqual(manifest["config"], config)
        self.assertEqual(config, embedded)
        self.assertEqual("app", config["entry"])
        self.assertEqual("production", config["canvas_policy"])
        self.assertEqual("full_app_lifecycle", config["diagnostic_scope"])
        self.assertEqual("preserved", config["quality_governor"])
        self.assertIs(config["performance_gate_applicable"], False)
        for key in ("tier", "warmup", "seconds", "seed", "stream_trace", "census",
                    "msaa_override", "render_scale_override"):
            self.assertNotIn(key, config)
        self.assertIn('run/main_scene="res://scenes/original.tscn"', project)
        self.assertNotIn('run/main_scene="res://tests/runner_web_perf.tscn"', project)
        self.assertIn('renderer/rendering_method="mobile"', project)
        self.assertNotIn('renderer/rendering_method="gl_compatibility"', project)
        self.assertFalse((run / "project/tests/runner_web_perf.gd").exists())
        self.assertFalse((run / "project/tests/runner_web_mesh_preflight.gd").exists())
        self.assertEqual((self.source / "tests/runner_perf_probe.gd").read_bytes(),
                         (run / "project/tests/runner_perf_probe.gd").read_bytes())
        self.assertEqual({"mode": "app", "source_main_scene": "res://scenes/original.tscn",
                          "export_main_scene": "res://scenes/original.tscn",
                          "quality_governor": "preserved",
                          "performance_gate_applicable": False}, manifest["entry"])
        self.assertIn("original full-app main scene and governor preserved", manifest["isolation"])
        self.assertIn("Original full-app governor preserved", manifest["canvas_policy"]["quality_governor"])
        self.assertIn('<canvas id="canvas"></canvas>', shell)
        for marker, _digest in COLLECTOR_MODULE.PRODUCTION_CANVAS_SCRIPTS:
            self.assertEqual(1, shell.split("</head>", 1)[0].count(marker))
        for forbidden in COLLECTOR_MODULE.PRODUCTION_CANVAS_FORBIDDEN:
            self.assertNotIn(forbidden.lower(), shell.split("</head>", 1)[0].lower())
        self.assertFalse((self.source / "tests/runner_web_perf_config.json").exists())

    def test_prepare_app_rejects_fixed_canvas_and_runner_controls_before_writes(self):
        parent = self.root / "qa_shots/runner"
        invalid = [
            ("fixed canvas", ["--canvas-policy", "fixed"]),
            ("tier", ["--tier", "medium"]),
            ("msaa", ["--msaa", "off"]),
            ("render scale", ["--render-scale", "0.75"]),
            ("warmup", ["--warmup", "1"]),
            ("seconds", ["--seconds", "30"]),
            ("seed", ["--seed", "7"]),
            ("stream trace", ["--stream-trace"]),
            ("census", ["--census"]),
        ]
        for name, extra in invalid:
            with self.subTest(name=name):
                before = set(parent.iterdir()) if parent.exists() else set()
                args = ["runner_web_perf.py", "prepare", "unit", "--source",
                        str(self.source), "--entry", "app", *extra]
                with mock.patch.object(COLLECTOR_MODULE.sys, "argv", args), \
                        mock.patch.object(COLLECTOR_MODULE.subprocess, "run") as process, \
                        redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), \
                        self.assertRaises(SystemExit):
                    COLLECTOR_MODULE.main()
                process.assert_not_called()
                after = set(parent.iterdir()) if parent.exists() else set()
                self.assertEqual(before, after)

    def test_prepare_msaa_off_is_explicit_and_consistent_without_runtime_edits(self):
        run = self._prepare(canvas_policy="production", msaa="off")
        manifest = json.loads((run / "manifest.json").read_text())
        config = json.loads((run / "project/tests/runner_web_perf_config.json").read_text())
        shell = (run / "project/tests/runner_web_perf_shell.html").read_text()
        embedded = json.loads(shell.split("const config = ", 1)[1].split(";</script>", 1)[0])
        self.assertEqual("off", config["msaa_override"])
        self.assertEqual("high", config["tier"])
        self.assertEqual("production", config["canvas_policy"])
        self.assertEqual(manifest["config"], config)
        self.assertEqual(config, embedded)
        self.assertTrue(manifest["original_probe_unchanged"])
        self.assertFalse(manifest["canvas_policy"]["complete_production"])

    def test_prepare_render_scale_is_optional_bounded_and_consistent(self):
        run = self._prepare(canvas_policy="production", render_scale=0.75)
        manifest = json.loads((run / "manifest.json").read_text())
        config = json.loads((run / "project/tests/runner_web_perf_config.json").read_text())
        shell = (run / "project/tests/runner_web_perf_shell.html").read_text()
        embedded = json.loads(shell.split("const config = ", 1)[1].split(";</script>", 1)[0])
        self.assertEqual(0.75, config["render_scale_override"])
        self.assertEqual("default", config["msaa_override"])
        self.assertEqual(manifest["config"], config)
        self.assertEqual(config, embedded)
        self.assertTrue(manifest["original_probe_unchanged"])

    def test_prepare_render_scale_rejects_non_finite_or_out_of_range_before_writes(self):
        parent = self.root / "qa_shots/runner"
        for value in ("0", "-0.1", "1.0001", "nan", "inf", "-inf"):
            with self.subTest(render_scale=value):
                before = set(parent.iterdir()) if parent.exists() else set()
                args = ["runner_web_perf.py", "prepare", "unit", "--source",
                        str(self.source), "--render-scale", value]
                with mock.patch.object(COLLECTOR_MODULE.sys, "argv", args), \
                        mock.patch.object(COLLECTOR_MODULE.subprocess, "run") as process, \
                        redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()), \
                        self.assertRaises(SystemExit):
                    COLLECTOR_MODULE.main()
                process.assert_not_called()
                after = set(parent.iterdir()) if parent.exists() else set()
                self.assertEqual(before, after)

    def test_build_rejects_render_scale_manifest_config_mismatch(self):
        run = self._prepare(render_scale=0.75)
        path = run / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["config"]["render_scale_override"] = 0.5
        path.write_text(json.dumps(manifest))
        self._assert_build_rejected_before_side_effects(run)

    def test_prepare_thread_variants_get_distinct_runs_without_overwrite(self):
        first = self._prepare()
        original = (first / "manifest.json").read_bytes()
        second = self._prepare(threads=True)
        self.assertNotEqual(first, second)
        self.assertEqual(original, (first / "manifest.json").read_bytes())
        self._assert_threads(first, False)
        self._assert_threads(second, True)
        first_id = json.loads(original)["run_id"]
        self.assertNotEqual(first_id, json.loads((second / "manifest.json").read_text())["run_id"])

    def test_prepare_production_canvas_embeds_only_reviewed_policy_with_receipt(self):
        run = self._prepare(canvas_policy="production")
        manifest = json.loads((run / "manifest.json").read_text())
        config = manifest["config"]
        shell = (run / "project/tests/runner_web_perf_shell.html").read_text()
        head = shell.split("</head>", 1)[0]
        self.assertEqual("production", config["canvas_policy"])
        self.assertEqual("production", manifest["canvas_policy"]["mode"])
        self.assertEqual(
            config["canvas_policy_source_sha256"],
            manifest["canvas_policy"]["source_sha256"],
        )
        self.assertEqual(
            config["canvas_policy_fragment_sha256"],
            manifest["canvas_policy"]["fragment_sha256"],
        )
        self.assertFalse(manifest["canvas_policy"]["complete_production"])
        self.assertIn('<canvas id="canvas"></canvas>', shell)
        self.assertNotRegex(shell, r'<canvas\b[^>]*\b(?:width|height)="')
        for marker, digest in COLLECTOR_MODULE.PRODUCTION_CANVAS_SCRIPTS:
            self.assertEqual(1, head.count(marker))
            self.assertIn(
                {"marker": marker, "sha256": digest},
                manifest["canvas_policy"]["scripts"],
            )
        for forbidden in COLLECTOR_MODULE.PRODUCTION_CANVAS_FORBIDDEN:
            self.assertNotIn(forbidden.lower(), head.lower())

    def test_prepare_production_canvas_fails_closed_before_run_directory(self):
        original = (self.source / "export_presets.cfg").read_text()
        mutations = {
            "changed hash": original.replace("var cap = 2.5;", "var cap = 2.4;", 1),
            "missing marker": original.replace(
                "// Canvas sizing, owned by the page.",
                "// Canvas policy marker intentionally removed.",
                1,
            ),
            "forbidden bridge": original.replace(
                "// Canvas sizing, owned by the page.",
                "// Canvas sizing, owned by the page.\nfetch('/not-allowed');",
                1,
            ),
        }
        parent = self.root / "qa_shots/runner"
        for reason, changed in mutations.items():
            with self.subTest(reason=reason):
                (self.source / "export_presets.cfg").write_text(changed)
                before = set(parent.iterdir()) if parent.exists() else set()
                args = ["runner_web_perf.py", "prepare", "unit", "--source",
                        str(self.source), "--canvas-policy", "production"]
                with mock.patch.object(COLLECTOR_MODULE.sys, "argv", args), \
                        mock.patch.object(COLLECTOR_MODULE.subprocess, "run") as process, \
                        redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
                    COLLECTOR_MODULE.main()
                process.assert_not_called()
                after = set(parent.iterdir()) if parent.exists() else set()
                self.assertEqual(before, after)
        (self.source / "export_presets.cfg").write_text(original)

    def _mock_build(self, run):
        args = mock.Mock(run=run, godot="/test-only/no-engine")
        with mock.patch.object(COLLECTOR_MODULE.subprocess, "run",
                               return_value=mock.Mock(returncode=0)) as process, \
                redirect_stdout(io.StringIO()):
            COLLECTOR_MODULE.build(args)
        self.assertEqual(process.call_count, 2)
        for call in process.call_args_list:
            self.assertEqual(call.args[0][0], "/test-only/no-engine")
            self.assertIn("--audio-driver", call.args[0])
            self.assertEqual(call.args[0][call.args[0].index("--audio-driver") + 1], "Dummy")
        return json.loads((run / "build.json").read_text())

    def test_build_receipt_records_explicit_thread_mode(self):
        for expected in (False, True):
            with self.subTest(threads=expected):
                run = self._prepare(threads=expected)
                receipt = self._mock_build(run)
                self.assertIs(type(receipt["threads"]), bool)
                self.assertIs(receipt["threads"], expected)
                self.assertEqual(receipt["export_mode"], "release")
                self.assertEqual(receipt["export_preset_integrity"], "prepared_sha256_and_thread_mode")
                self.assertEqual(
                    receipt["export_presets_sha256"],
                    json.loads((run / "manifest.json").read_text())["export_presets_sha256"],
                )

    def test_build_receipt_records_production_canvas_policy(self):
        run = self._prepare(canvas_policy="production")
        receipt = self._mock_build(run)
        manifest = json.loads((run / "manifest.json").read_text())
        self.assertEqual(manifest["canvas_policy"], receipt["canvas_policy"])
        self.assertEqual("production", receipt["canvas_policy"]["mode"])
        self.assertFalse(receipt["canvas_policy"]["complete_production"])

    def test_build_receipt_records_full_app_entry_without_runner_gate(self):
        run = self._prepare(entry="app")
        receipt = self._mock_build(run)
        self.assertEqual("app", receipt["entry"]["mode"])
        self.assertEqual("res://scenes/original.tscn", receipt["entry"]["export_main_scene"])
        self.assertEqual("preserved", receipt["entry"]["quality_governor"])
        self.assertIs(receipt["entry"]["performance_gate_applicable"], False)

    def test_build_rejects_canvas_config_or_receipt_mismatch_before_side_effects(self):
        for target in ("config", "receipt"):
            with self.subTest(target=target):
                run = self._prepare(canvas_policy="production")
                path = run / "manifest.json"
                manifest = json.loads(path.read_text())
                if target == "config":
                    manifest["config"]["canvas_policy_fragment_sha256"] = "0" * 64
                else:
                    manifest["canvas_policy"]["fragment_sha256"] = "0" * 64
                path.write_text(json.dumps(manifest))
                self._assert_build_rejected_before_side_effects(run)

    def test_build_receipt_old_manifest_defaults_threads_false(self):
        run = self._prepare()
        path = run / "manifest.json"
        manifest = json.loads(path.read_text())
        del manifest["config"]["threads"]
        del manifest["export_presets_sha256"]
        path.write_text(json.dumps(manifest))
        receipt = self._mock_build(run)
        self.assertIs(receipt["threads"], False)
        self.assertEqual(receipt["export_preset_integrity"], "legacy_thread_mode_only")

    def test_missing_manifest_threads_cannot_hide_threaded_embedded_config(self):
        run = self._prepare(threads=True)
        path = run / "manifest.json"
        manifest = json.loads(path.read_text())
        del manifest["config"]["threads"]
        path.write_text(json.dumps(manifest))
        self._assert_build_rejected_before_side_effects(run)

    def _assert_build_rejected_before_side_effects(self, run):
        args = mock.Mock(run=run, godot="/test-only/no-engine")
        with mock.patch.object(COLLECTOR_MODULE.subprocess, "run") as process, \
                mock.patch.object(Path, "mkdir") as mkdir, redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit):
                COLLECTOR_MODULE.build(args)
        process.assert_not_called()
        mkdir.assert_not_called()
        for name in ("web", "import.log", "export.log", "build.json"):
            self.assertFalse((run / name).exists(), name + " created before integrity rejection")

    def test_build_rejects_both_thread_preset_toggles_before_side_effects(self):
        for prepared in (False, True):
            with self.subTest(prepared=prepared):
                run = self._prepare(threads=prepared)
                path = run / "project/export_presets.cfg"
                text = path.read_text().replace(
                    "variant/thread_support=" + str(prepared).lower(),
                    "variant/thread_support=" + str(not prepared).lower(),
                )
                path.write_text(text)
                self._assert_build_rejected_before_side_effects(run)

    def test_build_rejects_non_thread_preset_byte_tamper(self):
        run = self._prepare()
        path = run / "project/export_presets.cfg"
        path.write_text(path.read_text() + "\n; post-prepare change unrelated to thread mode\n")
        self._assert_build_rejected_before_side_effects(run)

    def test_build_rejects_manifest_preset_mode_mismatch_even_without_legacy_hash(self):
        for legacy in (False, True):
            for prepared in (False, True):
                with self.subTest(legacy=legacy, prepared=prepared):
                    run = self._prepare(threads=prepared)
                    path = run / "manifest.json"
                    manifest = json.loads(path.read_text())
                    manifest["config"]["threads"] = not prepared
                    if legacy:
                        del manifest["export_presets_sha256"]
                    path.write_text(json.dumps(manifest))
                    self._assert_build_rejected_before_side_effects(run)

    def test_build_accepts_unchanged_legacy_presets_with_weaker_receipt(self):
        for threads in (False, True):
            with self.subTest(threads=threads):
                run = self._prepare(threads=threads)
                path = run / "manifest.json"
                manifest = json.loads(path.read_text())
                expected_hash = manifest.pop("export_presets_sha256")
                path.write_text(json.dumps(manifest))
                receipt = self._mock_build(run)
                self.assertIs(receipt["threads"], threads)
                self.assertEqual(receipt["export_presets_sha256"], expected_hash)
                self.assertEqual(receipt["export_preset_integrity"], "legacy_thread_mode_only")

    def test_build_rejects_missing_preset_before_side_effects(self):
        run = self._prepare()
        (run / "project/export_presets.cfg").unlink()
        self._assert_build_rejected_before_side_effects(run)

    def test_build_rejects_non_boolean_declared_thread_mode(self):
        for legacy in (False, True):
            for invalid in (None, 0, 1, "false", "true", []):
                with self.subTest(legacy=legacy, threads=invalid):
                    run = self._prepare()
                    path = run / "manifest.json"
                    manifest = json.loads(path.read_text())
                    manifest["config"]["threads"] = invalid
                    if legacy:
                        del manifest["export_presets_sha256"]
                    path.write_text(json.dumps(manifest))
                    self._assert_build_rejected_before_side_effects(run)

    def test_build_invalid_present_preset_hash_never_downgrades_to_legacy(self):
        for invalid in (None, "", "not-a-sha256", 0):
            with self.subTest(saved_hash=invalid):
                run = self._prepare()
                path = run / "manifest.json"
                manifest = json.loads(path.read_text())
                manifest["export_presets_sha256"] = invalid
                path.write_text(json.dumps(manifest))
                self._assert_build_rejected_before_side_effects(run)

    def test_build_rejects_invalid_or_ambiguous_legacy_preset_modes(self):
        mutations = {
            "missing mode": lambda text: text.replace("variant/thread_support=false\n", ""),
            "nonliteral mode": lambda text: text.replace("variant/thread_support=false", "variant/thread_support=0"),
            "duplicate mode": lambda text: text + "variant/thread_support=false\n",
            "wrong platform": lambda text: text.replace('platform="Web"', 'platform="Linux"'),
            "inherited mode": lambda text: "[DEFAULT]\nvariant/thread_support=false\n" + text.replace("variant/thread_support=false\n", ""),
            "duplicate named preset": lambda text: text + '\n[preset.1]\nname="Web Probe"\nplatform="Web"\n',
            "missing options": lambda text: text.split("[preset.0.options]")[0],
            "invalid encoding": lambda text: text.encode() + b"\xff",
        }
        for name, mutate in mutations.items():
            with self.subTest(reason=name):
                run = self._prepare()
                manifest_path = run / "manifest.json"
                manifest = json.loads(manifest_path.read_text())
                del manifest["export_presets_sha256"]
                manifest_path.write_text(json.dumps(manifest))
                preset = run / "project/export_presets.cfg"
                changed = mutate(preset.read_text())
                preset.write_bytes(changed if isinstance(changed, bytes) else changed.encode())
                self._assert_build_rejected_before_side_effects(run)


if __name__ == "__main__":
    unittest.main()
