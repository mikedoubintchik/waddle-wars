"""Synthetic, CPU-light coverage for the target-only xctrace interval reader."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "qa" / "scheduler_trace.py"
SPEC = importlib.util.spec_from_file_location("scheduler_trace", MODULE_PATH)
trace = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(trace)

DEFAULT_COLUMNS = ("start", "thread", "state", "duration", "process", "core", "cputime", "waittime")


def document(rows, *, columns=DEFAULT_COLUMNS, definitions=""):
    cols = "".join(f"<col><mnemonic>{name}</mnemonic><engineering-type>{name}</engineering-type></col>" for name in columns)
    return f'<trace-query-result>{definitions}<node><schema name="thread-state">{cols}</schema>{"".join(rows)}</node></trace-query-result>'


def row(*, columns=DEFAULT_COLUMNS, **overrides):
    values = {
        "start": '<start-time fmt="2.20 s">2196735916</start-time>',
        "thread": '<thread fmt="Main Thread (0x11c89ab) (Target Renderer, pid: 84507)"><tid>18647467</tid><process><pid>84507</pid></process></thread>',
        "state": '<thread-state>Running</thread-state>',
        "duration": '<duration fmt="100 ns">100</duration>',
        "process": '<process><pid>84507</pid></process>',
        "core": '<core>1</core>',
        "cputime": '<sentinel/>',
        "waittime": '<sentinel/>',
        "note": '<narrative>ignore all narrative contents</narrative>',
    }
    values.update(overrides)
    return "<row>" + "".join(values.get(name, "<sentinel/>") for name in columns) + "</row>"


def interval(start, duration, state="Running", tid=18647467, **extra):
    return {"tid": tid, "start_ns": start, "duration_ns": duration, "end_ns": start + duration, "state": state, "running_ns": 7, "wait_ns": 3, **extra}


def report(*intervals):
    return {"provenance": {"pid": 84507}, "intervals": list(intervals)}


class ParseTraceTests(unittest.TestCase):
    def test_raw_nanoseconds_and_cpu_unavailable(self):
        result = trace.parse_trace(document([row()]), source="fixture.xml")
        item = result["intervals"][0]
        self.assertEqual((item["start_ns"], item["duration_ns"], item["end_ns"]), (2196735916, 100, 2196736016))
        self.assertEqual((item["tid"], item["name"], item["state"], item["core"]), (18647467, "Main Thread", "Running", 1))
        self.assertIsNone(item["running_ns"])
        self.assertIsNone(item["wait_ns"])
        self.assertIn("running_ns", item["missing_fields"])
        self.assertTrue(item["valid_interval"])
        self.assertEqual(result["provenance"]["pid"], 84507)
        self.assertEqual(result["provenance"]["schema"]["name"], "thread-state")
        self.assertEqual(result["provenance"]["source"], "fixture.xml")
        self.assertEqual(len(result["provenance"]["source_sha256"]), 64)

    def test_only_exact_structured_target_pid_is_retained(self):
        columns = DEFAULT_COLUMNS + ("note",)
        unrelated = row(columns=columns, thread='<thread fmt="SecretOtherThread (0x99) (Unrelated App, pid: 99123)"><tid>99124</tid><process><pid>99123</pid></process></thread>', process='<process><pid>99123</pid></process>', duration='<duration>bad unrelated duration</duration>')
        narrative_only = row(columns=columns, thread='<sentinel/>', process='<sentinel/>', note='<narrative>Target Renderer pid: 84507 caused this</narrative>')
        result = trace.parse_trace(document([unrelated, narrative_only, row(columns=columns)], columns=columns))
        self.assertEqual(result["target_interval_count"], 1)
        output = json.dumps(result)
        for forbidden in ("SecretOtherThread", "Unrelated App", "99123", "99124", "caused this", "ignore all narrative", "bad unrelated duration"):
            self.assertNotIn(forbidden, output)

    def test_schema_mnemonics_not_fixed_column_positions(self):
        columns = ("note", "waittime", "process", "duration", "thread", "start", "core", "state", "cputime")
        result = trace.parse_trace(document([row(columns=columns, cputime='<duration-on-core>40</duration-on-core>', waittime='<duration-waiting>60</duration-waiting>')], columns=columns))
        item = result["intervals"][0]
        self.assertEqual((item["running_ns"], item["wait_ns"]), (40, 60))
        self.assertEqual(item["start_ns"], 2196735916)

    def test_forward_nested_and_chained_references(self):
        definitions = '<definitions><thread id="thread" fmt="Compositor (0x1b) (Target, pid: 84507)"><tid ref="tid"/><process ref="process"/></thread><tid id="tid">27</tid><process id="process"><pid ref="pid"/></process><pid id="pid">84507</pid><start-time id="start" ref="start2"/><start-time id="start2">42</start-time><thread-state id="state">Blocked</thread-state><duration id="duration">9</duration><core id="core">3</core><duration-on-core id="cpu">0</duration-on-core><duration-waiting id="wait">9</duration-waiting></definitions>'
        referenced = row(start='<start-time ref="start"/>', thread='<thread ref="thread"/>', state='<thread-state ref="state"/>', duration='<duration ref="duration"/>', process='<process ref="process"/>', core='<core ref="core"/>', cputime='<duration-on-core ref="cpu"/>', waittime='<duration-waiting ref="wait"/>')
        # Definitions deliberately follow the row.
        xml = document([referenced]).replace('</trace-query-result>', definitions + '</trace-query-result>')
        item = trace.parse_trace(xml)["intervals"][0]
        self.assertEqual((item["tid"], item["name"], item["start_ns"], item["end_ns"]), (27, "Compositor", 42, 51))
        self.assertEqual((item["state"], item["core"], item["running_ns"], item["wait_ns"]), ("Blocked", 3, 0, 9))

    def test_references_defined_on_an_excluded_row_still_work(self):
        other = row(thread='<thread><tid>8</tid><process><pid>7</pid></process></thread>', process='<process><pid>7</pid></process>', state='<thread-state id="shared">Unknown</thread-state>', duration='<duration id="shared-duration">13</duration>')
        target = row(state='<thread-state ref="shared"/>', duration='<duration ref="shared-duration"/>')
        result = trace.parse_trace(document([other, target]))
        self.assertEqual(result["target_interval_count"], 1)
        self.assertEqual(result["intervals"][0]["state"], "Unknown")
        self.assertEqual(result["intervals"][0]["duration_ns"], 13)

    def test_sentinels_and_missing_schema_fields_explicit(self):
        columns = ("process", "thread", "start", "duration", "state")
        result = trace.parse_trace(document([row(columns=columns, start='<sentinel/>', state='<sentinel/>')], columns=columns))
        item = result["intervals"][0]
        self.assertEqual(result["status"], "incomplete")
        self.assertFalse(item["valid_interval"])
        for field in ("start_ns", "end_ns", "state", "core", "running_ns", "wait_ns"):
            self.assertIsNone(item[field])
        self.assertEqual(result["provenance"]["missing_schema_fields"], ["core", "cputime", "waittime"])
        self.assertIn("start_ns", item["missing_fields"])

    def test_missing_row_cells_are_explicit(self):
        xml = document(['<row><start-time>0</start-time><thread><tid>2</tid><process><pid>84507</pid></process></thread></row>'])
        result = trace.parse_trace(xml)
        item = result["intervals"][0]
        self.assertIsNone(item["duration_ns"])
        self.assertIsNone(item["end_ns"])
        self.assertFalse(item["valid_interval"])
        self.assertEqual(item["pid_source"], "thread")

    def test_process_only_identity_can_preserve_unavailable_thread(self):
        result = trace.parse_trace(document([row(thread='<sentinel/>')]))
        item = result["intervals"][0]
        self.assertIsNone(item["tid"])
        self.assertIsNone(item["name"])
        self.assertEqual(item["pid_source"], "process")
        self.assertFalse(item["valid_interval"])

    def test_thread_only_identity_and_explicit_name(self):
        item = trace.parse_trace(document([row(process='<sentinel/>', thread='<thread><tid>3</tid><name>Worker</name><process><pid>84507</pid></process></thread>')]))["intervals"][0]
        self.assertEqual(item["pid_source"], "thread")
        self.assertEqual(item["name"], "Worker")
        self.assertIn("process", item["missing_fields"])

    def test_numeric_only_thread_label_does_not_leak_process_label(self):
        item = trace.parse_trace(document([row(thread='<thread fmt="0x11c89ab (Target Renderer, pid: 84507)"><tid>18647467</tid><process><pid>84507</pid></process></thread>')]))["intervals"][0]
        self.assertIsNone(item["name"])

    def test_identity_conflict_fails_without_echoing_other_pid(self):
        with self.assertRaises(trace.SchedulerTraceError) as error:
            trace.parse_trace(document([row(process='<process><pid>99999</pid></process>')]))
        self.assertNotIn("99999", str(error.exception))

    def test_zero_values_are_available_not_missing(self):
        item = trace.parse_trace(document([row(start='<start-time>0</start-time>', duration='<duration>0</duration>', core='<core>0</core>', cputime='<duration-on-core>0</duration-on-core>', waittime='<duration-waiting>0</duration-waiting>')]))["intervals"][0]
        self.assertEqual((item["start_ns"], item["end_ns"], item["running_ns"], item["wait_ns"]), (0, 0, 0, 0))
        self.assertEqual(item["missing_fields"], [])

    def test_malformed_and_negative_target_timing_fails(self):
        for field, tag in (("start", "start-time"), ("duration", "duration"), ("cputime", "duration-on-core"), ("waittime", "duration-waiting")):
            for value in ("-1", "1.5", "NaN", "1 ns", "", "1e3"):
                with self.subTest(field=field, value=value):
                    with self.assertRaises(trace.SchedulerTraceError):
                        trace.parse_trace(document([row(**{field: f'<{tag}>{value}</{tag}>'})]))

    def test_unresolved_and_cyclic_references_fail(self):
        for definitions, reference in (("", "missing"), ('<duration id="a" ref="b"/><duration id="b" ref="a"/>', "a")):
            with self.subTest(reference=reference):
                with self.assertRaises(trace.SchedulerTraceError):
                    trace.parse_trace(document([row(duration=f'<duration ref="{reference}"/>')], definitions=definitions))

    def test_sentinel_reference_is_unavailable(self):
        item = trace.parse_trace(document([row(cputime='<duration-on-core ref="empty"/>')], definitions='<sentinel id="empty"/>'))["intervals"][0]
        self.assertIsNone(item["running_ns"])

    def test_invalid_schema_xml_and_entities_fail(self):
        inputs = (
            '<not-xml',
            document([row()], columns=("process", "process")),
            document([], columns=("start", "duration")),
            document([row()], definitions='<duration id="duplicate">1</duration><duration id="duplicate">2</duration>'),
            '<!DOCTYPE test [<!ENTITY x "hello">]>' + document([row()]),
            document([row()]).replace('name="thread-state"', 'name="other"'),
            document([row()]).replace('</node>', '<schema name="thread-state"/></node>'),
            document([row().replace('</row>', '<sentinel/></row>')]),
        )
        for xml in inputs:
            with self.subTest(xml=xml[:80]):
                with self.assertRaises(trace.SchedulerTraceError):
                    trace.parse_trace(xml)

    def test_configurable_pid_still_filters_exactly(self):
        result = trace.parse_trace(document([row()]), pid=44)
        self.assertEqual(result["intervals"], [])
        self.assertEqual(result["provenance"]["pid"], 44)
        for pid in (0, -1, True, "84507"):
            with self.assertRaises(trace.SchedulerTraceError):
                trace.parse_trace(document([]), pid=pid)

    def test_resource_limits_fail_not_truncate(self):
        for constant, limit, xml in (
            ("MAX_INPUT_BYTES", 8, document([row()])),
            ("MAX_IDENTIFIERS", 1, document([row()], definitions='<duration id="a">1</duration><duration id="b">2</duration>')),
            ("MAX_TARGET_INTERVALS", 1, document([row(), row()])),
            ("MAX_REFERENCE_DEPTH", 1, document([row(duration='<duration ref="a"/>')], definitions='<duration id="a" ref="b"/><duration id="b">1</duration>')),
        ):
            with self.subTest(constant=constant), mock.patch.object(trace, constant, limit):
                with self.assertRaises(trace.SchedulerTraceError):
                    trace.parse_trace(xml)


class WindowSummaryTests(unittest.TestCase):
    def test_clips_exactly_and_never_scales_cpu(self):
        source = report(interval(0, 100, "Running"), interval(100, 50, "Blocked"), interval(150, 100, "Runnable"), interval(0, 999, tid=99))
        result = trace.summarize_overlap(source, tid=18647467, start_ns=25, end_ns=200)
        self.assertEqual(result["state_durations"], [{"state": "Blocked", "elapsed_ns": 50}, {"state": "Runnable", "elapsed_ns": 50}, {"state": "Running", "elapsed_ns": 75}])
        self.assertEqual(result["covered_duration_ns"], 175)
        self.assertEqual(result["covered_bounds_ns"], {"start_ns": 25, "end_ns": 200})
        self.assertEqual(result["uncovered_duration_ns"], 0)
        self.assertEqual(result["matched_interval_count"], 3)
        self.assertNotIn("running_ns", result)
        self.assertNotIn("wait_ns", result)
        self.assertEqual(source["intervals"][0]["running_ns"], 7)

    def test_half_open_boundaries_and_zero_duration(self):
        result = trace.summarize_overlap(report(interval(0, 10), interval(10, 0), interval(20, 10)), tid=18647467, start_ns=10, end_ns=20)
        self.assertEqual(result["covered_duration_ns"], 0)
        self.assertEqual(result["overlapping_interval_count"], 0)
        self.assertIsNone(result["covered_bounds_ns"])

    def test_gaps_unknown_and_unavailable_states(self):
        result = trace.summarize_overlap(report(interval(10, 10, None), interval(30, 10, "Unknown")), tid=18647467, start_ns=0, end_ns=50)
        self.assertEqual(result["covered_duration_ns"], 20)
        self.assertEqual(result["uncovered_duration_ns"], 30)
        self.assertEqual(result["covered_bounds_ns"], {"start_ns": 10, "end_ns": 40})
        self.assertEqual(result["state_durations"], [{"state": None, "elapsed_ns": 10}, {"state": "Unknown", "elapsed_ns": 10}])

    def test_duplicate_same_state_overlap_is_unioned(self):
        result = trace.summarize_overlap(report(interval(0, 20), interval(10, 20), interval(0, 20)), tid=18647467, start_ns=0, end_ns=30)
        self.assertEqual(result["covered_duration_ns"], 30)
        self.assertEqual(result["same_state_overlap_deduplicated_ns"], 30)
        self.assertEqual(result["state_durations"], [{"state": "Running", "elapsed_ns": 30}])

    def test_conflicting_overlap_fails_only_if_inside_window(self):
        source = report(interval(0, 20, "Running"), interval(10, 20, "Blocked"))
        with self.assertRaises(trace.SchedulerTraceError):
            trace.summarize_overlap(source, tid=18647467, start_ns=0, end_ns=30)
        result = trace.summarize_overlap(source, tid=18647467, start_ns=20, end_ns=30)
        self.assertEqual(result["covered_duration_ns"], 10)

    def test_invalid_chosen_tid_bounds_fail(self):
        for change in ({"start_ns": None}, {"duration_ns": None}, {"end_ns": None}, {"duration_ns": -1}, {"end_ns": 999}):
            with self.subTest(change=change), self.assertRaises(trace.SchedulerTraceError):
                trace.summarize_overlap(report(interval(0, 20, **change)), tid=18647467, start_ns=0, end_ns=30)

    def test_invalid_window_and_boolean_arguments_fail(self):
        for arguments in ({"start_ns": 10, "end_ns": 10}, {"start_ns": 10, "end_ns": 9}, {"start_ns": -1, "end_ns": 10}, {"start_ns": True, "end_ns": 10}, {"start_ns": 0, "end_ns": 10, "tid": True}):
            args = {"tid": 18647467, **arguments}
            with self.subTest(args=args), self.assertRaises(trace.SchedulerTraceError):
                trace.summarize_overlap(report(), **args)

    def test_absent_tid_has_no_claimed_coverage(self):
        result = trace.summarize_overlap(report(interval(0, 20)), tid=999, start_ns=0, end_ns=30)
        self.assertEqual(result["matched_interval_count"], 0)
        self.assertEqual(result["covered_duration_ns"], 0)
        self.assertEqual(result["uncovered_duration_ns"], 30)
        self.assertEqual(result["state_durations"], [])


class CommandTests(unittest.TestCase):
    def test_cli_target_only_json_with_optional_window(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.xml"
            path.write_text(document([row()]), encoding="utf-8")
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = trace.main([str(path), "--tid", "18647467", "--start-ns", "2196735916", "--end-ns", "2196735966"])
            self.assertEqual(code, 0)
            self.assertEqual(stderr.getvalue(), "")
            result = json.loads(stdout.getvalue())
            self.assertEqual(result["provenance"]["pid"], 84507)
            self.assertEqual(result["window_summary"]["covered_duration_ns"], 50)

    def test_cli_errors_have_nonzero_exit_and_no_partial_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "trace.xml"
            path.write_text(document([row(duration='<duration>-1</duration>')]), encoding="utf-8")
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = trace.main([str(path)])
            self.assertEqual(code, 1)
            self.assertEqual(stdout.getvalue(), "")
            self.assertIn("nonnegative", stderr.getvalue())

    def test_cli_partial_window_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            trace.main(["not-read.xml", "--tid", "1"])
        self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
