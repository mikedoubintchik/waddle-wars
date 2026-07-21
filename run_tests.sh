#!/usr/bin/env bash
# Waddle Wars automated test suite (headless).
# Usage: ./run_tests.sh            — run everything available
#        GODOT=/path/to/godot ./run_tests.sh — use a specific Godot binary
# Exits nonzero if any test case fails.

set -u
cd "$(dirname "$0")"

GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
    for candidate in godot godot4 godot4.7 Godot \
        /Applications/Godot.app/Contents/MacOS/Godot; do
        if command -v "$candidate" >/dev/null 2>&1; then
            GODOT_BIN="$candidate"
            break
        fi
    done
fi
if [ -z "$GODOT_BIN" ]; then
    echo "run_tests.sh: no Godot executable found on PATH (tried godot, godot4, godot4.7, Godot)." >&2
    echo "run_tests.sh: set GODOT=/path/to/godot and retry." >&2
    exit 2
fi
echo "Using Godot binary: $GODOT_BIN"

overall=0
summary=""

run_case() {
    label="$1"
    shift
    echo ""
    echo "=== $label ==="
    "$GODOT_BIN" --headless --path . "$@"
    code=$?
    if [ "$code" -ne 0 ]; then
        overall=1
        summary="${summary}FAIL  ${label} (exit ${code})\n"
    else
        summary="${summary}PASS  ${label}\n"
    fi
}

skip_case() {
    label="$1"
    reason="$2"
    summary="${summary}SKIP  ${label} (${reason})\n"
}

run_case "unit_tests" res://tests/unit_tests.tscn
run_case "menu_load_test" res://tests/menu_load_test.tscn
run_case "race_sim glacier" res://tests/race_sim.tscn -- course=glacier

if test -f scripts/courses/course_aurora.gd; then
    run_case "race_sim aurora" res://tests/race_sim.tscn -- course=aurora
else
    skip_case "race_sim aurora" "scripts/courses/course_aurora.gd not present yet"
fi

if test -f scripts/courses/course_iceberg.gd; then
    run_case "race_sim iceberg" res://tests/race_sim.tscn -- course=iceberg
else
    skip_case "race_sim iceberg" "scripts/courses/course_iceberg.gd not present yet"
fi

run_case "time_trial ghost" res://tests/race_sim.tscn -- course=glacier tt
run_case "endless_sim" res://tests/endless_sim.tscn
run_case "tutorial_sim" res://tests/tutorial_sim.tscn
run_case "grand_prix_sim" res://tests/gp_sim.tscn

echo ""
echo "=== SUMMARY ==="
printf "%b" "$summary"
if [ "$overall" -ne 0 ]; then
    echo "RESULT: FAILURES PRESENT"
else
    echo "RESULT: ALL PASSED"
fi
exit $overall
