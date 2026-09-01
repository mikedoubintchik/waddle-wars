#!/usr/bin/env bash
# Waddle Wars automated test suite (headless).
# Usage: ./run_tests.sh            — run everything available
#        ./run_tests.sh runner     — run labels containing "runner"
#        GODOT=/path/to/godot ./run_tests.sh — use a specific Godot binary
# Exits nonzero if any test case fails.

set -u
cd "$(dirname "$0")"
WW_PROJECT_ROOT="$PWD"

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
WW_TEST_FILTER="${1:-}"
if [ -n "$WW_TEST_FILTER" ]; then
    echo "Case filter: $WW_TEST_FILTER"
fi

# Every Godot project with the same identity shares user://. Tests exercise
# save corruption, runner mission progress and settings persistence, so running
# them against the player's real directory is unsafe. Snapshot the resource
# folders into a temporary project identity with its own custom user directory.
# A snapshot also prevents a concurrent editor/code task from changing global
# script classes halfway through a long suite.
WW_TEST_TMP_BASE="${TMPDIR:-/tmp}"
if [ "$WW_TEST_TMP_BASE" != "/" ]; then
    WW_TEST_TMP_BASE="${WW_TEST_TMP_BASE%/}"
fi
if ! WW_TEST_PROJECT="$(mktemp -d "$WW_TEST_TMP_BASE/waddle-wars-tests.XXXXXX")"; then
    echo "run_tests.sh: could not create isolated project under $WW_TEST_TMP_BASE" >&2
    exit 2
fi
if [ ! -d "$WW_TEST_PROJECT" ]; then
    echo "run_tests.sh: mktemp returned a non-directory: $WW_TEST_PROJECT" >&2
    exit 2
fi
WW_TEST_RUN_ID="waddle-wars-tests-$$-${RANDOM:-0}"

clean_test_user_data() {
    "$GODOT_BIN" --headless --path "$WW_TEST_PROJECT" \
        --log-file "$WW_TEST_PROJECT/clean.log" \
        --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1
}

cleanup_test_workspace() {
    if [ -f "$WW_TEST_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        clean_test_user_data || true
    fi
    case "$WW_TEST_PROJECT" in
        "$WW_TEST_TMP_BASE"/waddle-wars-tests.*)
            rm -rf -- "$WW_TEST_PROJECT"
            ;;
        *)
            echo "run_tests.sh: refusing to remove unexpected test path: $WW_TEST_PROJECT" >&2
            ;;
    esac
}
trap cleanup_test_workspace EXIT

for WW_RESOURCE_DIR in art_src assets data scenes scripts tests tools; do
    if ! cp -R "$WW_PROJECT_ROOT/$WW_RESOURCE_DIR" \
            "$WW_TEST_PROJECT/$WW_RESOURCE_DIR"; then
        echo "run_tests.sh: could not snapshot $WW_RESOURCE_DIR" >&2
        exit 2
    fi
done
if ! cp "$WW_PROJECT_ROOT/.gitattributes" "$WW_TEST_PROJECT/.gitattributes"; then
    echo "run_tests.sh: could not snapshot .gitattributes" >&2
    exit 2
fi
# Deliberately omit .godot: the isolated project's import/class cache must be
# rebuilt from raw sources. This catches fresh-clone ordering failures (notably
# project themes, fonts and global classes) that a warm editor cache can hide.
awk -v ww_test_id="$WW_TEST_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", ww_test_id
    }
' "$WW_PROJECT_ROOT/project.godot" > "$WW_TEST_PROJECT/project.godot" || {
    echo "run_tests.sh: could not write isolated project.godot" >&2
    exit 2
}

# Prime imports and global class discovery once. `--import` waits for the scan
# to finish before quitting; `--quit-after 1` can leave a partial class cache.
if ! "$GODOT_BIN" --headless --import --path "$WW_TEST_PROJECT" \
        --log-file "$WW_TEST_PROJECT/import.log" \
        >"$WW_TEST_PROJECT/import.stdout" 2>"$WW_TEST_PROJECT/import.stderr"; then
    echo "run_tests.sh: isolated project import failed" >&2
    sed -n '1,160p' "$WW_TEST_PROJECT/import.stderr" >&2
    exit 2
fi
if grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_TEST_PROJECT/import.log"; then
    echo "run_tests.sh: isolated project import reported errors" >&2
    sed -n '1,200p' "$WW_TEST_PROJECT/import.log" >&2
    exit 2
fi
# Homebrew Godot may probe a non-running Android adb daemon during import.
# Ignore that one external-tool line; any other stderr means the fresh-cache
# path is not clean and must fail before tests hide the import problem.
if awk '
    NF && $0 != "cannot connect to daemon at tcp:5037: Connection refused" { bad = 1 }
    END { exit bad ? 0 : 1 }
' "$WW_TEST_PROJECT/import.stderr"; then
    echo "run_tests.sh: isolated project import wrote unexpected stderr" >&2
    sed -n '1,160p' "$WW_TEST_PROJECT/import.stderr" >&2
    exit 2
fi
echo "Isolated test project: $WW_TEST_PROJECT"

overall=0
summary=""
selected=0

run_case() {
    local label="$1"
    shift
    if [ -n "$WW_TEST_FILTER" ] && [[ "$label" != *"$WW_TEST_FILTER"* ]]; then
        return
    fi
    selected=$((selected + 1))
    echo ""
    echo "=== $label ==="
    if ! clean_test_user_data; then
        overall=1
        summary="${summary}FAIL  ${label} (could not reset isolated user data)\n"
        return
    fi
    local log_path="$WW_TEST_PROJECT/${label// /_}.log"
    "$GODOT_BIN" --headless --path "$WW_TEST_PROJECT" \
        --log-file "$log_path" "$@"
    local code=$?
    if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' "$log_path"; then
        overall=1
        summary="${summary}FAIL  ${label} (runtime script/resource error)\n"
        sed -n '1,200p' "$log_path" >&2
    elif [ "$code" -ne 0 ]; then
        overall=1
        summary="${summary}FAIL  ${label} (exit ${code})\n"
    else
        summary="${summary}PASS  ${label}\n"
    fi
}

skip_case() {
    local label="$1"
    local reason="$2"
    if [ -n "$WW_TEST_FILTER" ] && [[ "$label" != *"$WW_TEST_FILTER"* ]]; then
        return
    fi
    selected=$((selected + 1))
    summary="${summary}SKIP  ${label} (${reason})\n"
}

run_host_case() {
    local label="$1"
    shift
    if [ -n "$WW_TEST_FILTER" ] && [[ "$label" != *"$WW_TEST_FILTER"* ]]; then
        return
    fi
    selected=$((selected + 1))
    echo ""
    echo "=== $label ==="
    if (cd "$WW_TEST_PROJECT" && "$@"); then
        summary="${summary}PASS  ${label}\n"
    else
        local code=$?
        overall=1
        summary="${summary}FAIL  ${label} (exit ${code})\n"
    fi
}

run_host_case "art_manifest_validation" python3 tools/art/validate_art.py
run_host_case "art_tool_tests" python3 -m unittest tests/test_art_tools.py
# The browser build's entire pre-engine layer -- audio unlock, pixel budget,
# canvas sizing, PWA metadata, graphics-loss recovery -- lives in one escaped
# string in export_presets.cfg that no Godot test reads. A syntax error there
# ships a black page with a silent console.
run_host_case "web_shell" python3 tools/check_web_shell.py
# ...and this runs it: the pixel budget that decides how many pixels a phone
# renders every frame, the canvas sizing that iOS Safari's zoom feedback loop
# used to defeat, and the graphics-loss screen, all exercised against real
# device profiles in a DOM stub.
run_host_case "web_shell_behaviour" node tools/test_web_shell_behaviour.mjs
run_case "unit_tests" res://tests/unit_tests.tscn
run_case "menu_load_test" res://tests/menu_load_test.tscn
run_case "frontend_presentation_test" res://tests/frontend_presentation_test.tscn
run_case "utility_frontend_test" res://tests/utility_frontend_test.tscn
run_case "course_poster_wave1_test" res://tests/course_poster_wave1_test.tscn
run_case "course_poster_wave2_test" res://tests/course_poster_wave2_test.tscn
run_case "art_foundation_test" res://tests/art_foundation_test.tscn
run_case "penguin_visual_contract" res://tests/penguin_visual_contract_test.tscn
run_case "hero_penguin_asset_test" res://tests/hero_penguin_asset_test.tscn
run_case "runner_platform_tests" res://tests/runner_platform_tests.tscn
run_case "runner_golden_slice" res://tests/runner_golden_slice.tscn
run_case "runner_day_kit_test" res://tests/runner_day_kit_test.tscn
# Phone layout is a regression surface like any other: every menu is loaded at
# real device sizes (converted to the logical canvas the UI actually lays out
# in) and any interactive control a thumb cannot reach fails the run.
# Needs a real window (it resizes one per device), so it is skipped in the
# headless suite and run explicitly:
#   godot --path . --resolution 390x844 res://tests/mobile_ui_audit.tscn
# A VRAM-compressed non-power-of-two texture renders as magenta garbage on
# iOS Safari while looking perfect in desktop Chrome. Cheap to check, and it
# shipped once already.
run_case "texture_format" --script tests/texture_format_test.gd

# Needs a window: the design canvas is display-only, and this asserts it
# recovers when the first window shape read was wrong (the iOS Safari case).
run_case "orientation_recovery" res://tests/orientation_recovery_test.tscn

run_case "mobile_ui_audit" res://tests/mobile_ui_audit.tscn
run_case "runner_sim" res://tests/runner_sim.tscn -- seconds=60
run_case "runner_churn" res://tests/runner_churn.tscn -- runs=8
run_case "race_sim glacier" res://tests/race_sim.tscn -- course=glacier

if test -f "$WW_TEST_PROJECT/scripts/courses/course_aurora.gd"; then
    run_case "race_sim aurora" res://tests/race_sim.tscn -- course=aurora
else
    skip_case "race_sim aurora" "scripts/courses/course_aurora.gd not present yet"
fi

if test -f "$WW_TEST_PROJECT/scripts/courses/course_iceberg.gd"; then
    run_case "race_sim iceberg" res://tests/race_sim.tscn -- course=iceberg
else
    skip_case "race_sim iceberg" "scripts/courses/course_iceberg.gd not present yet"
fi

if test -f "$WW_TEST_PROJECT/scripts/courses/course_cinder.gd"; then
    run_case "race_sim cinder" res://tests/race_sim.tscn -- course=cinder
else
    skip_case "race_sim cinder" "scripts/courses/course_cinder.gd not present yet"
fi

if test -f "$WW_TEST_PROJECT/scripts/courses/course_hollow.gd"; then
    run_case "race_sim hollow" res://tests/race_sim.tscn -- course=hollow
else
    skip_case "race_sim hollow" "scripts/courses/course_hollow.gd not present yet"
fi

run_case "time_trial ghost" res://tests/race_sim.tscn -- course=glacier tt
run_case "endless_sim" res://tests/endless_sim.tscn
run_case "tutorial_sim" res://tests/tutorial_sim.tscn
run_case "grand_prix_sim" res://tests/gp_sim.tscn

if [ "$selected" -eq 0 ]; then
    overall=1
    summary="${summary}FAIL  no cases matched filter '${WW_TEST_FILTER}'\n"
fi

echo ""
echo "=== SUMMARY ==="
printf "%b" "$summary"
if [ "$overall" -ne 0 ]; then
    echo "RESULT: FAILURES PRESENT"
else
    echo "RESULT: ALL PASSED"
fi
exit $overall
