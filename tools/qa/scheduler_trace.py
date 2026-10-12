#!/usr/bin/env python3
"""Read one xctrace thread-state table without exposing other processes.

Raw start/duration engineering values are nanoseconds; formatted values are never
used for timing or process identity. This is an interval reader, not a CPU profiler
or a causal explanation of a frame hitch. No third-party dependencies.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any
import xml.etree.ElementTree as ET


DEFAULT_PID = 84507
# A complete 100-second System Trace exports about 69 MiB of thread-state XML
# even when attached to one renderer. Keep a bounded envelope large enough for
# that real capture; identity/interval/reference caps remain independently set.
MAX_INPUT_BYTES = 128 * 1024 * 1024
MAX_IDENTIFIERS = 500_000
# The same full capture contains over 250,000 target state transitions.
MAX_TARGET_INTERVALS = 500_000
MAX_REFERENCE_DEPTH = 64
FIELDS = ("start", "thread", "state", "duration", "process", "core", "cputime", "waittime")
_INTEGER = re.compile(r"[0-9]+\Z")
_NAMED_THREAD = re.compile(r"^(.*?) \((?:0x[0-9a-fA-F]+|[0-9]+)\)(?: \(.*\))?$")


class SchedulerTraceError(ValueError):
    """Input cannot safely support the requested target-only timing report."""


def _tag(element: ET.Element) -> str:
    return element.tag.rsplit("}", 1)[-1]


def _child(element: ET.Element, tag: str) -> ET.Element | None:
    return next((child for child in element if _tag(child) == tag), None)


def _nonnegative_int(value: str | None, field: str) -> int:
    text = "" if value is None else value.strip()
    if not _INTEGER.fullmatch(text):
        # Do not echo raw values: malformed identity may belong to another process.
        raise SchedulerTraceError(f"{field}: expected a nonnegative raw integer")
    return int(text)


def _argument_int(value: Any, field: str, *, positive: bool = False) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < int(positive):
        raise SchedulerTraceError(f"{field}: expected {'positive' if positive else 'nonnegative'} integer")
    return value


class _References:
    def __init__(self, root: ET.Element) -> None:
        self.ids: dict[str, ET.Element] = {}
        for element in root.iter():
            identifier = element.get("id")
            if identifier is None:
                continue
            if identifier in self.ids:
                raise SchedulerTraceError("XML contains duplicate id definitions")
            if len(self.ids) >= MAX_IDENTIFIERS:
                raise SchedulerTraceError("XML identifier limit exceeded")
            self.ids[identifier] = element

    def resolve(self, element: ET.Element | None, field: str) -> ET.Element | None:
        seen: set[str] = set()
        while element is not None and element.get("ref") is not None:
            reference = element.get("ref")
            if reference in seen:
                raise SchedulerTraceError(f"{field}: cyclic XML reference")
            if len(seen) >= MAX_REFERENCE_DEPTH:
                raise SchedulerTraceError(f"{field}: XML reference depth limit exceeded")
            seen.add(reference)
            if reference not in self.ids:
                raise SchedulerTraceError(f"{field}: unresolved XML reference")
            element = self.ids[reference]
        if element is None or _tag(element) == "sentinel":
            return None
        return element

    def integer(self, element: ET.Element | None, field: str) -> int | None:
        resolved = self.resolve(element, field)
        return None if resolved is None else _nonnegative_int(resolved.text, field)

    def process_pid(self, element: ET.Element | None) -> int | None:
        process = self.resolve(element, "process")
        if process is None:
            return None
        if _tag(process) != "process":
            raise SchedulerTraceError("process: expected structured process identity")
        return self.integer(_child(process, "pid"), "process.pid")


def _thread_name(thread: ET.Element | None, refs: _References) -> str | None:
    if thread is None:
        return None
    explicit_name = refs.resolve(_child(thread, "name"), "thread.name")
    if explicit_name is not None:
        return (explicit_name.text or "").strip() or None
    # xctrace's thread label includes process details. Only retain the named
    # prefix, never that entire label and never use it to infer PID/TID.
    match = _NAMED_THREAD.fullmatch(thread.get("fmt", ""))
    return match.group(1).strip() or None if match else None


def parse_trace(xml: bytes | str, *, pid: int = DEFAULT_PID, source: str | None = None) -> dict[str, Any]:
    """Return only intervals with structured process identity matching ``pid``.

    Missing/sentinel fields become null and appear in missing_fields. Missing
    TID/start/duration makes valid_interval false; malformed/negative numbers,
    identity conflicts and broken references fail explicitly. Rows with neither
    a process-column PID nor a nested thread PID are not attributable and are
    excluded, even if their narrative mentions the target.
    """
    _argument_int(pid, "pid", positive=True)
    data = xml.encode("utf-8") if isinstance(xml, str) else xml
    if len(data) > MAX_INPUT_BYTES:
        raise SchedulerTraceError("XML input byte limit exceeded")
    # Entity expansion is unnecessary for xctrace exports. Refuse DTDs entirely.
    if b"<!DOCTYPE" in data.upper() or b"<!ENTITY" in data.upper():
        raise SchedulerTraceError("XML document type/entity declarations are unsupported")
    try:
        root = ET.fromstring(data)
    except (ET.ParseError, ValueError) as exc:
        raise SchedulerTraceError("Malformed XML") from exc
    refs = _References(root)
    tables = [
        (node, child)
        for node in root.iter()
        for child in node
        if _tag(child) == "schema" and child.get("name") == "thread-state"
    ]
    if len(tables) != 1:
        raise SchedulerTraceError("Expected exactly one thread-state schema/table")
    table, schema = tables[0]
    columns: list[dict[str, str | None]] = []
    indexes: dict[str, int] = {}
    for column in schema:
        if _tag(column) != "col":
            continue
        mnemonic_element = _child(column, "mnemonic")
        mnemonic = "" if mnemonic_element is None else (mnemonic_element.text or "").strip()
        if not mnemonic or mnemonic in indexes:
            raise SchedulerTraceError("Schema contains missing or duplicate column mnemonics")
        engineering = _child(column, "engineering-type")
        indexes[mnemonic] = len(columns)
        columns.append({"mnemonic": mnemonic, "engineering_type": None if engineering is None else engineering.text})
    if "process" not in indexes and "thread" not in indexes:
        raise SchedulerTraceError("Schema has no structured process-identity columns")

    intervals: list[dict[str, Any]] = []
    for row in table:
        if _tag(row) != "row":
            continue
        cells = list(row)

        def cell(field: str) -> ET.Element | None:
            index = indexes.get(field)
            return cells[index] if index is not None and index < len(cells) else None

        # Resolve authoritative identity before reading or retaining timing,
        # thread labels, state or any other data from this row.
        process_pid = refs.process_pid(cell("process"))
        thread = refs.resolve(cell("thread"), "thread")
        if thread is not None and _tag(thread) != "thread":
            raise SchedulerTraceError("thread: expected structured thread identity")
        thread_pid = refs.process_pid(_child(thread, "process")) if thread is not None else None
        if pid not in (process_pid, thread_pid):
            continue
        if process_pid is not None and thread_pid is not None and process_pid != thread_pid:
            raise SchedulerTraceError("Target row has conflicting structured process identities")
        if len(cells) > len(columns):
            raise SchedulerTraceError("Target row has more cells than schema columns")
        if len(intervals) >= MAX_TARGET_INTERVALS:
            raise SchedulerTraceError("Target interval limit exceeded")

        tid = refs.integer(_child(thread, "tid"), "thread.tid") if thread is not None else None
        name = _thread_name(thread, refs)
        start = refs.integer(cell("start"), "start_ns")
        duration = refs.integer(cell("duration"), "duration_ns")
        state_element = refs.resolve(cell("state"), "state")
        state = None if state_element is None else (state_element.text or "").strip() or None
        running = refs.integer(cell("cputime"), "running_ns")
        waiting = refs.integer(cell("waittime"), "wait_ns")
        core = refs.integer(cell("core"), "core")
        missing = [
            field for field, value in (
                ("tid", tid), ("name", name), ("start_ns", start), ("duration_ns", duration),
                ("state", state), ("running_ns", running), ("wait_ns", waiting), ("core", core),
                ("process", process_pid), ("thread_process", thread_pid),
            ) if value is None
        ]
        intervals.append({
            "tid": tid,
            "name": name,
            "start_ns": start,
            "duration_ns": duration,
            "end_ns": start + duration if start is not None and duration is not None else None,
            "state": state,
            "running_ns": running,
            "wait_ns": waiting,
            "core": core,
            "pid_source": "process_and_thread" if process_pid is not None and thread_pid is not None else "process" if process_pid is not None else "thread",
            "valid_interval": tid is not None and start is not None and duration is not None,
            "missing_fields": missing,
        })

    return {
        "provenance": {
            "pid": pid,
            "source": source,
            "source_sha256": hashlib.sha256(data).hexdigest(),
            "schema": {"name": "thread-state", "columns": columns},
            "units": {"start_ns": "ns", "duration_ns": "ns", "end_ns": "ns", "running_ns": "ns", "wait_ns": "ns"},
            "filter_policy": "Exact structured PID only; unattributable rows excluded; narratives and formatted labels never establish identity.",
            "clock": "Trace-relative raw start-time; not wall-clock time.",
            "cpu_policy": "Existing cputime/waittime values only; null is unavailable. State duration is elapsed time, not measured CPU time.",
            "missing_schema_fields": [field for field in FIELDS if field not in indexes],
            "limits": {"input_bytes": MAX_INPUT_BYTES, "identifiers": MAX_IDENTIFIERS, "target_intervals": MAX_TARGET_INTERVALS, "reference_depth": MAX_REFERENCE_DEPTH},
        },
        "status": "incomplete" if any(not interval["valid_interval"] for interval in intervals) else "ok",
        "target_interval_count": len(intervals),
        "intervals": intervals,
    }


def summarize_overlap(report: dict[str, Any], *, tid: int, start_ns: int, end_ns: int) -> dict[str, Any]:
    """Summarize elapsed state coverage in the half-open window [start, end).

    Duplicate/overlapping same-state ranges are unioned, not counted twice.
    Conflicting overlapping states fail rather than inventing an attribution.
    No CPU/wait counters are scaled, inferred, or summed for clipped intervals.
    """
    _argument_int(tid, "tid")
    _argument_int(start_ns, "window start_ns")
    _argument_int(end_ns, "window end_ns")
    if end_ns <= start_ns:
        raise SchedulerTraceError("Window end_ns must exceed start_ns")
    clipped: list[tuple[int, int, str | None]] = []
    matched = 0
    for interval in report["intervals"]:
        if interval["tid"] != tid:
            continue
        matched += 1
        first, last, duration = interval["start_ns"], interval["end_ns"], interval["duration_ns"]
        if first is None or last is None or duration is None:
            raise SchedulerTraceError("Chosen TID has unavailable interval bounds; cannot claim complete window coverage")
        _argument_int(first, "interval start_ns")
        _argument_int(last, "interval end_ns")
        _argument_int(duration, "interval duration_ns")
        if last != first + duration:
            raise SchedulerTraceError("Chosen TID has inconsistent interval bounds")
        left, right = max(first, start_ns), min(last, end_ns)
        if left < right:
            clipped.append((left, right, interval["state"]))

    clipped.sort(key=lambda item: (item[0], item[1]))
    merged: list[tuple[int, int, str | None]] = []
    for left, right, state in clipped:
        if merged and left < merged[-1][1] and state != merged[-1][2]:
            raise SchedulerTraceError("Chosen TID has conflicting overlapping states in window")
        if merged and left <= merged[-1][1] and state == merged[-1][2]:
            previous = merged[-1]
            merged[-1] = (previous[0], max(previous[1], right), state)
        else:
            merged.append((left, right, state))
    states: dict[str | None, int] = {}
    for left, right, state in merged:
        states[state] = states.get(state, 0) + right - left
    covered = sum(states.values())
    return {
        "pid": report["provenance"]["pid"],
        "tid": tid,
        "window": {"start_ns": start_ns, "end_ns": end_ns, "duration_ns": end_ns - start_ns, "boundary": "[start_ns, end_ns)"},
        "matched_interval_count": matched,
        "overlapping_interval_count": len(clipped),
        "covered_bounds_ns": {"start_ns": merged[0][0], "end_ns": merged[-1][1]} if merged else None,
        "covered_duration_ns": covered,
        "uncovered_duration_ns": end_ns - start_ns - covered,
        "same_state_overlap_deduplicated_ns": sum(right - left for left, right, _ in clipped) - covered,
        "state_durations": [{"state": state, "elapsed_ns": states[state]} for state in sorted(states, key=lambda item: (item is not None, item or ""))],
        "cpu_policy": "Not summarized: interval CPU/wait totals cannot be proportionally scaled to clipped boundaries. Elapsed Running state is not measured CPU time.",
    }


def read_trace(path: str | Path, *, pid: int = DEFAULT_PID) -> dict[str, Any]:
    path = Path(path)
    with path.open("rb") as stream:
        data = stream.read(MAX_INPUT_BYTES + 1)
    return parse_trace(data, pid=pid, source=path.name)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="xctrace thread-state XML export")
    parser.add_argument("--pid", type=int, default=DEFAULT_PID, help=f"Exact target PID (default: {DEFAULT_PID})")
    parser.add_argument("--tid", type=int, help="Optionally summarize this TID/window")
    parser.add_argument("--start-ns", type=int)
    parser.add_argument("--end-ns", type=int)
    args = parser.parse_args(argv)
    window = (args.tid, args.start_ns, args.end_ns)
    if any(value is not None for value in window) and any(value is None for value in window):
        parser.error("--tid, --start-ns and --end-ns must be supplied together")
    try:
        report = read_trace(args.trace, pid=args.pid)
        if args.tid is not None:
            report["window_summary"] = summarize_overlap(report, tid=args.tid, start_ns=args.start_ns, end_ns=args.end_ns)
    except (OSError, SchedulerTraceError) as exc:
        # No partial JSON report is printed on failure.
        print(f"scheduler_trace: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
