#!/usr/bin/env python3
"""Launch Claude Code and stop it shortly before a weekly usage reset."""

from __future__ import annotations

import datetime as dt
import os
import signal
import subprocess
import sys
from typing import NoReturn


STOP_EARLY_SECONDS = 90

# Change "ultracode" to "max" for maximum per-turn reasoning consumption.
CLAUDE_COMMAND = [
    "claude",
    "--model",
    "fable",
    "--effort",
    "ultracode",
    "--permission-mode",
    "auto",
    "--name",
    "waddle-wars",
    # Headless (no TTY) requires a prompt; this kicks off the autonomous run.
    "-p",
    "Read GAME_SPEC.md and CLAUDE.md in the current directory, then execute "
    "the mission autonomously until the acceptance criteria are satisfied or "
    "the session cutoff is reached.",
]


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def parse_reset_timestamp(raw_value: str) -> dt.datetime:
    try:
        parsed = dt.datetime.fromisoformat(raw_value)
    except ValueError as exc:
        fail(
            "Invalid timestamp. Use ISO 8601 with an offset, for example: "
            "2026-07-24T21:00:00-04:00"
        )

    if parsed.tzinfo is None:
        fail("The reset timestamp must include a UTC offset such as -04:00.")

    return parsed


def interrupt_process(process: subprocess.Popen[bytes]) -> None:
    """Request a clean interrupt, then escalate if Claude does not exit."""
    if process.poll() is not None:
        return

    print(
        "\nWeekly-reset cutoff reached. Interrupting Claude Code.",
        flush=True,
    )

    try:
        if os.name == "nt":
            process.send_signal(signal.CTRL_BREAK_EVENT)
        else:
            os.killpg(process.pid, signal.SIGINT)

        process.wait(timeout=20)
        return
    except (subprocess.TimeoutExpired, ProcessLookupError):
        pass

    try:
        if os.name == "nt":
            process.terminate()
        else:
            os.killpg(process.pid, signal.SIGTERM)

        process.wait(timeout=10)
        return
    except (subprocess.TimeoutExpired, ProcessLookupError):
        pass

    if process.poll() is None:
        if os.name == "nt":
            process.kill()
        else:
            os.killpg(process.pid, signal.SIGKILL)


def main() -> int:
    if len(sys.argv) != 2:
        fail(
            "Usage:\n"
            '  python run_until_reset.py "2026-07-24T21:00:00-04:00"\n\n'
            "Supply the exact reset timestamp shown by Claude."
        )

    reset_at = parse_reset_timestamp(sys.argv[1])
    stop_at = reset_at - dt.timedelta(seconds=STOP_EARLY_SECONDS)
    now = dt.datetime.now(reset_at.tzinfo)
    remaining_seconds = (stop_at - now).total_seconds()

    if remaining_seconds <= 0:
        fail("The safe cutoff has already passed. Claude was not started.")

    print(f"Weekly reset: {reset_at.isoformat()}")
    print(f"Hard cutoff:  {stop_at.isoformat()}")
    print(f"Starting:     {' '.join(CLAUDE_COMMAND)}")
    print(flush=True)

    popen_options: dict[str, object] = {}

    if os.name == "nt":
        popen_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        popen_options["start_new_session"] = True

    process = subprocess.Popen(CLAUDE_COMMAND, **popen_options)

    try:
        return process.wait(timeout=remaining_seconds)
    except subprocess.TimeoutExpired:
        interrupt_process(process)
        return process.returncode if process.returncode is not None else 0
    except KeyboardInterrupt:
        print("\nManual interruption received.", flush=True)
        interrupt_process(process)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
