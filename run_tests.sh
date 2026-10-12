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
WW_TEST_WINDOW_ONLY="${WW_TEST_WINDOW_ONLY:-0}"
if [ -n "$WW_TEST_FILTER" ]; then
    echo "Case filter: $WW_TEST_FILTER"
fi
if [ "$WW_TEST_WINDOW_ONLY" = "1" ]; then
    echo "Visible-window fixtures only (isolated test project)"
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
WW_TEST_EVIDENCE="$WW_PROJECT_ROOT/qa_shots/tests/$WW_TEST_RUN_ID"
mkdir -p "$WW_TEST_EVIDENCE"
WW_GODOT_DIAGNOSTICS=()
if [ "${WW_TEST_VERBOSE:-0}" = "1" ]; then
    WW_GODOT_DIAGNOSTICS+=(--verbose)
fi

clean_test_user_data() {
    "$GODOT_BIN" --headless --path "$WW_TEST_PROJECT" \
        --log-file "$WW_TEST_PROJECT/clean.log" \
        --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1
}

set_case_user_identity() {
    local label="$1"
    local identity="$WW_TEST_RUN_ID"
    local suffix="${WW_TEST_RUN_ID#waddle-wars-tests-}"
    case "$label" in
        cosmetic_trail) identity="waddle-wars-trail-$suffix" ;;
        equipment_art) identity="waddle-wars-equipment-$suffix" ;;
        runner_apparel) identity="waddle-wars-apparel-$suffix" ;;
        menu_composition_fidelity|wardrobe_preview_flow)
            identity="waddle-wars-wardrobe-$suffix" ;;
        shop_functionality) identity="waddle-wars-shop-$suffix" ;;
    esac
    # The previous identity must be cleaned before this copied project changes.
    # Keep each fixture's own strict prefix guard and never change the source.
    if ! awk -v identity="$identity" '
        /^config\/custom_user_dir_name=/ {
            printf "config/custom_user_dir_name=\"%s\"\n", identity
            seen++
            next
        }
        { print }
        END { if (seen != 1) exit 1 }
    ' "$WW_TEST_PROJECT/project.godot" > "$WW_TEST_PROJECT/project.godot.next"; then
        return 1
    fi
    mv "$WW_TEST_PROJECT/project.godot.next" "$WW_TEST_PROJECT/project.godot"
}

run_test_process() {
    local seconds="$1"
    shift
    if [ "$seconds" = "0" ]; then
        "$@"
        return $?
    fi
    python3 - "$seconds" "$@" <<'PYWATCH'
import os
import signal
import subprocess
import sys

seconds = float(sys.argv[1])
process = subprocess.Popen(sys.argv[2:], start_new_session=True)

def stop():
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()

def interrupted(signum, _frame):
    stop()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGTERM, interrupted)
try:
    code = process.wait(timeout=seconds)
except subprocess.TimeoutExpired:
    print("run_tests.sh: fixture exceeded %.0fs; terminating isolated process" % seconds,
          file=sys.stderr, flush=True)
    stop()
    code = 124
raise SystemExit(code if code >= 0 else 128 - code)
PYWATCH
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

for WW_RESOURCE_DIR in art_src assets data scenes scripts tests tools addons; do
    if ! cp -R "$WW_PROJECT_ROOT/$WW_RESOURCE_DIR" \
            "$WW_TEST_PROJECT/$WW_RESOURCE_DIR"; then
        echo "run_tests.sh: could not snapshot $WW_RESOURCE_DIR" >&2
        exit 2
    fi
done
for WW_TEST_PROJECT_FILE in .gitattributes export_presets.cfg; do
    if ! cp "$WW_PROJECT_ROOT/$WW_TEST_PROJECT_FILE" "$WW_TEST_PROJECT/$WW_TEST_PROJECT_FILE"; then
        echo "run_tests.sh: could not snapshot $WW_TEST_PROJECT_FILE" >&2
        exit 2
    fi
done
# Backend host fixtures need only source, schema and migrations, never deployment
# credentials, local databases, Wrangler state or node_modules.
mkdir -p "$WW_TEST_PROJECT/leaderboard"
for WW_BACKEND_DIR in src migrations; do
    if ! cp -R "$WW_PROJECT_ROOT/leaderboard/$WW_BACKEND_DIR" "$WW_TEST_PROJECT/leaderboard/$WW_BACKEND_DIR"; then
        echo "run_tests.sh: could not snapshot commerce $WW_BACKEND_DIR" >&2
        exit 2
    fi
done
if ! cp "$WW_PROJECT_ROOT/leaderboard/schema.sql" "$WW_TEST_PROJECT/leaderboard/schema.sql"; then
    echo "run_tests.sh: could not snapshot leaderboard schema.sql" >&2
    exit 2
fi
# Sandbox guards compare public deployment identity to reject the production D1
# binding. Never copy credentials if a future edit puts them in this public file.
if ! python3 "$WW_PROJECT_ROOT/tools/commerce/sandbox_preflight.py" \
        --check-production-public-config "$WW_PROJECT_ROOT/leaderboard/wrangler.toml" >/dev/null; then
    echo "run_tests.sh: refusing credentials in public backend configuration" >&2
    exit 2
fi
if ! cp "$WW_PROJECT_ROOT/leaderboard/wrangler.toml" "$WW_TEST_PROJECT/leaderboard/wrangler.toml"; then
    echo "run_tests.sh: could not snapshot public backend wrangler.toml" >&2
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
preserve_import_failure() {
    local evidence="$WW_PROJECT_ROOT/qa_shots/tests/$WW_TEST_RUN_ID"
    mkdir -p "$evidence"
    local filename
    for filename in import.log import.stdout import.stderr; do
        if [ -f "$WW_TEST_PROJECT/$filename" ]; then
            cp "$WW_TEST_PROJECT/$filename" "$evidence/$filename"
        fi
    done
    echo "Import failure evidence: $evidence" >&2
    # Native crashes can leave stderr empty while the last imported resource
    # and the engine's diagnostic messages remain on stdout/the log file.
    tail -80 "$WW_TEST_PROJECT/import.stdout" >&2
    sed -n '1,160p' "$WW_TEST_PROJECT/import.stderr" >&2
}

if ! "$GODOT_BIN" --headless --import --path "$WW_TEST_PROJECT" \
        --log-file "$WW_TEST_PROJECT/import.log" \
        >"$WW_TEST_PROJECT/import.stdout" 2>"$WW_TEST_PROJECT/import.stderr"; then
    echo "run_tests.sh: isolated project import failed" >&2
    preserve_import_failure
    exit 2
fi
if grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_TEST_PROJECT/import.log"; then
    echo "run_tests.sh: isolated project import reported errors" >&2
    preserve_import_failure
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
    preserve_import_failure
    exit 2
fi
echo "Isolated test project: $WW_TEST_PROJECT"
echo "Test evidence: $WW_TEST_EVIDENCE"
cp "$WW_TEST_PROJECT/import.log" "$WW_TEST_EVIDENCE/import.log"

# Historical recipe fixtures retain their original class_name declarations.
# Their .gdignore must keep them out of this fresh engine class cache.
if ! python3 - "$WW_TEST_PROJECT/.godot/global_script_class_cache.cfg" \
        > "$WW_TEST_EVIDENCE/runner-class-cache.json" <<'PYCLASSES'
import json
from pathlib import Path
import re
import sys

expected = {
    "RunnerGame": "res://scripts/runner/runner_game.gd",
    "RunnerTrack": "res://scripts/runner/runner_track.gd",
    "RunnerPaintedSea": "res://scripts/runner/runner_painted_sea.gd",
}
source = Path(sys.argv[1]).read_text()
observed = {name: [] for name in expected}
for block in re.findall(r"\{([^{}]*)\}", source, re.S):
    fields = dict(re.findall(r'"(class|path)"\s*:\s*&?"([^"]+)"', block))
    if fields.get("class") in observed:
        observed[fields["class"]].append(fields.get("path"))
passed = all(observed[name] == [path] for name, path in expected.items())
print(json.dumps({"passed": passed, "expected": expected, "observed": observed}, indent=2))
raise SystemExit(0 if passed else 1)
PYCLASSES
then
    echo "run_tests.sh: fresh class cache does not resolve production runner scripts" >&2
    cat "$WW_TEST_EVIDENCE/runner-class-cache.json" >&2
    exit 2
fi

overall=0
summary=""
selected=0

run_case() {
    local label="$1"
    shift
    if [ "$WW_TEST_WINDOW_ONLY" = "1" ] \
            && [[ ! "$label" =~ ^(hero_v12_atlas_shader|orientation_recovery|mobile_ui_audit|race_hud_touch_layout)$ ]]; then
        return
    fi
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
    if ! set_case_user_identity "$label"; then
        overall=1
        summary="${summary}FAIL  ${label} (could not set isolated user identity)\n"
        return
    fi
    local log_path="$WW_TEST_PROJECT/${label// /_}.log"
    local stdout_path="$WW_TEST_EVIDENCE/${label// /_}.stdout.txt"
    local code
    local display_mode=(--headless)
    local fixture_args=()
    if [ "$WW_TEST_WINDOW_ONLY" = "1" ]; then
        display_mode=()
        if [ "$label" = "hero_v12_atlas_shader" ]; then
            fixture_args=(-- renderer=mobile)
        fi
    fi
    # Engine log files omit some final stderr diagnostics. Retain both streams
    # and preserve the engine's status rather than trusting tee's exit code.
    if (
        set -o pipefail
        run_test_process "${WW_TEST_CASE_TIMEOUT:-0}" \
            "$GODOT_BIN" "${display_mode[@]}" "${WW_GODOT_DIAGNOSTICS[@]}" --path "$WW_TEST_PROJECT" \
            --log-file "$log_path" "$@" "${fixture_args[@]}" 2>&1 | tee "$stdout_path"
    ); then
        code=0
    else
        code=$?
    fi
    if [ ! -f "$log_path" ]; then
        overall=1
        summary="${summary}FAIL  ${label} (missing engine log)\n"
        return
    fi
    cp "$log_path" "$WW_TEST_EVIDENCE/${label// /_}.log"
    local diagnostic_inputs=("$log_path" "$stdout_path")
    if [ "$label" = "threaded_resource_lifetime" ]; then
        # ControlledLoader intentionally returns ERR_CANT_OPEN for these three
        # exact paths. Preserve raw logs; allow each expected line once per
        # stream only. A duplicate, different resource, or other error survives.
        local filtered_path="$WW_TEST_EVIDENCE/threaded_resource_lifetime.diagnostics.txt"
        awk '
            BEGIN {
                expected["ERROR: Failed loading resource: res://tests/fixtures/failure_catalog.wwlifetest."] = 1
                expected["ERROR: Failed loading resource: res://tests/fixtures/failure_wardrobe.wwlifetest."] = 1
                expected["ERROR: Failed loading resource: res://tests/fixtures/failure_abandoned.wwlifetest."] = 1
            }
            expected[$0] && !seen[FILENAME SUBSEP $0]++ { next }
            { print }
        ' "${diagnostic_inputs[@]}" > "$filtered_path"
        diagnostic_inputs=("$filtered_path")
    fi
    local engine_errors
    # Godot can return zero after engine-level errors, including invalid string
    # formatting. Keep only explicit, already-known diagnostic exceptions:
    # shutdown resource leaks (still an open release issue), and the unit case
    # that deliberately corrupts both save JSON files to test recovery.
    engine_errors=$(awk -v test_label="$label" '
        /^ERROR:/ {
            if ($0 ~ /^ERROR: [0-9]+ resources still in use at exit \(run with --verbose for details\)\.$/) next
            if (test_label == "unit_tests" && $0 == "ERROR: Parse JSON failed. Error at line 0: Expected key") next
            print
        }
    ' "${diagnostic_inputs[@]}")
    if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' "${diagnostic_inputs[@]}"; then
        overall=1
        summary="${summary}FAIL  ${label} (runtime script/resource error)\n"
        sed -n '1,200p' "$log_path" >&2
    elif [ -n "$engine_errors" ]; then
        overall=1
        summary="${summary}FAIL  ${label} (unexpected engine error)\n"
        echo "$engine_errors" >&2
    elif [ "$code" -ne 0 ]; then
        overall=1
        summary="${summary}FAIL  ${label} (exit ${code})\n"
    elif [[ "$label" =~ ^(hero_v12_atlas_shader|runner_dusk_warmup_raster|orientation_recovery|mobile_ui_audit|race_hud_touch_layout)$ ]] \
            && grep -Eq '^\[(hero_v12_atlas_shader|dusk_warmup_raster|orientation|mobile-ui|hud-touch)\] SKIP' "$log_path"; then
        # These entire fixtures explicitly return before testing when no
        # window exists. Do not turn an intentional zero-test skip into PASS.
        summary="${summary}SKIP  ${label} (real window/renderer required)\n"
    else
        summary="${summary}PASS  ${label}\n"
    fi
}

skip_case() {
    local label="$1"
    local reason="$2"
    if [ "$WW_TEST_WINDOW_ONLY" = "1" ]; then
        return
    fi
    if [ -n "$WW_TEST_FILTER" ] && [[ "$label" != *"$WW_TEST_FILTER"* ]]; then
        return
    fi
    selected=$((selected + 1))
    summary="${summary}SKIP  ${label} (${reason})\n"
}

run_host_case() {
    local label="$1"
    shift
    if [ "$WW_TEST_WINDOW_ONLY" = "1" ]; then
        return
    fi
    if [ -n "$WW_TEST_FILTER" ] && [[ "$label" != *"$WW_TEST_FILTER"* ]]; then
        return
    fi
    selected=$((selected + 1))
    echo ""
    echo "=== $label ==="
    local log_path="$WW_TEST_EVIDENCE/${label// /_}.log"
    # Preserve both streams without hiding a command failure behind tee.
    if (
        set -o pipefail
        (cd "$WW_TEST_PROJECT" && "$@") 2>&1 | tee "$log_path"
    ); then
        summary="${summary}PASS  ${label}\n"
    else
        local code=$?
        overall=1
        summary="${summary}FAIL  ${label} (exit ${code})\n"
    fi
}

# Development tree intentionally includes unapproved review fragments. Check
# their complete integrity here; strict production readiness remains the
# separate release gate: python3 tools/art/validate_art.py (without this flag).
run_host_case "art_review_integrity" python3 tools/art/validate_art.py --review-fragments
run_host_case "art_tool_tests" python3 -m unittest tests/test_art_tools.py
run_host_case "hero_v12_candidate_tools" python3 tests/test_hero_v12_candidate.py
run_host_case "hero_v12_runner_review_tools" python3 tests/test_hero_v12_runner_review.py
run_host_case "hero_v12_atlas_runner_review_tools" python3 tests/test_hero_v12_atlas_runner_review.py
run_host_case "hero_v12_atlas_material_diagnostic" python3 tests/test_hero_v12_atlas_material_diagnostic.py
run_host_case "hero_v12_runner_rim_study" python3 tests/test_hero_v12_runner_rim_study.py
run_host_case "hero_v12_atlas_tools" python3 tests/test_hero_v12_atlas.py
run_host_case "hero_v12_mouth_projection" python3 tests/test_hero_v12_mouth_projection.py
run_host_case "hero_v12_atlas_export" python3 tests/test_hero_v12_atlas_export.py
run_host_case "hero_v12_shared_texture_package" python3 tests/test_hero_v12_shared_texture_package.py
run_host_case "hero_eye_pigment" python3 tests/test_hero_penguin_eye_pigment.py
run_host_case "hero_feather_detail_recipe" python3 tests/test_hero_penguin_v12_feather_detail_recipe.py
run_host_case "hero_source_study" python3 tests/test_hero_penguin_v12_source_study.py
run_host_case "hero_face_z07" python3 -m unittest tests.test_hero_penguin_v12_face_z07
run_host_case "hero_face_z08_scope" python3 -m unittest tests.test_hero_penguin_v12_face_z08.FaceZ08ScopeTests
if python3 -c 'import numpy' >/dev/null 2>&1; then
    run_host_case "hero_face_z08_field" python3 -m unittest tests.test_hero_penguin_v12_face_z08.FaceZ08FieldTests
else
    skip_case "hero_face_z08_field" "NumPy required; use Blender standalone Python for these three field guards"
fi
run_host_case "hero_face_z09_scope" python3 -m unittest tests.test_hero_penguin_v12_face_z09.FaceZ09ScopeTests
if python3 -c 'import numpy' >/dev/null 2>&1; then
    run_host_case "hero_face_z09_field" python3 -m unittest tests.test_hero_penguin_v12_face_z09.FaceZ09FieldTests
else
    skip_case "hero_face_z09_field" "NumPy required; use Blender standalone Python for these four field guards"
fi
run_host_case "hero_juvenile_sculpt" python3 -m unittest tests.test_hero_penguin_v12_juvenile_sculpt.JuvenileSculptTests
if python3 -c 'import numpy' >/dev/null 2>&1; then
    run_host_case "hero_juvenile_socket_geometry" python3 -m unittest tests.test_hero_penguin_v12_juvenile_sculpt.JuvenileSocketFieldTests
else
    skip_case "hero_juvenile_socket_geometry" "NumPy required; use Blender standalone Python for these three shape guards"
fi
run_host_case "hero_orbital_saddle" python3 tests/test_hero_penguin_v12_orbital_saddle.py
run_host_case "hero_source_study_provenance" python3 tests/test_hero_penguin_v12_study_provenance.py
run_host_case "runner_day_geometry" python3 tests/test_runner_day_duplicate_geometry.py
run_host_case "runner_radar_lod1_candidate" python3 tests/test_runner_radar_lod1_candidate.py
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
run_host_case "web_auth_identity" node --test tests/web_auth_identity.test.mjs
run_host_case "account_deletion_web_transport" node --test tests/account_deletion_web_transport.test.mjs
run_host_case "web_api_lifetime" node --test tests/web_api_lifetime.test.mjs
run_host_case "web_audio_keepalive" node --test tests/web_audio_keepalive.test.mjs
run_host_case "web_audio_focus" node --test tests/web_audio_focus.test.mjs
run_host_case "account_deletion_page" node --test tests/account_deletion_page.test.mjs
run_host_case "commerce_backend" node --test tests/commerce_backend.test.mjs tests/commerce_notifications.test.mjs tests/commerce_native_auth.test.mjs
run_host_case "commerce_sandbox_preflight" python3 -m unittest discover -s tools/commerce -p 'test_*.py'
run_host_case "android_integration_qa_helper" python3 -m unittest discover -s tools/release -p test_android_integration_qa.py
run_host_case "android_fullgame_debug_helper" python3 -m unittest discover -s tools/release -p test_android_debug.py
run_host_case "android_relro_structural" python3 -m unittest discover -s tools/release -p test_android_relro.py
run_host_case "android_release_signature" python3 -m unittest discover -s tools/release -p test_android_release.py
run_host_case "android_release_build_gate" python3 -m unittest discover -s tools/release -p test_build_native.py
run_host_case "leaderboard_name_privacy" node --test tests/leaderboard_privacy.test.mjs
run_host_case "cloud_save_privacy_backend" node --test tests/cloud_save_privacy.test.mjs
run_host_case "account_retirement_backend" node --test tests/account_retirement.test.mjs
run_host_case "runner_web_probe_shell" node tests/test_runner_web_perf_shell.mjs
run_host_case "runner_web_probe_collector" python3 -m unittest tests.test_runner_web_perf_collector
run_host_case "perf_browser_context" node tests/test_perf_browser_context.mjs
run_host_case "loader_presentation_source" python3 -m unittest tests.test_loader_presentation_boundary
run_host_case "scheduler_trace_parser" python3 -m unittest tests.test_scheduler_trace
# Main development regressions and production reviewed-runner integration.
# Bound newly registered fixtures; timeout remains a failed case, never a skip.
WW_TEST_CASE_TIMEOUT=240
run_case "achievement_detail_reference" res://tests/achievement_detail_reference_test.tscn
run_case "controls_binding_icons" res://tests/controls_binding_icons_test.tscn
run_case "cosmetic_trail" res://tests/cosmetic_trail_test.tscn
run_case "equipment_art" res://tests/equipment_art_test.tscn
run_case "feedback_form" res://tests/feedback_form_test.tscn
run_case "glacier_gauntlet_art" res://tests/glacier_gauntlet_art_test.tscn
run_case "home_missions_fidelity" res://tests/home_missions_fidelity_test.tscn
run_case "item_cache_art" res://tests/item_cache_art_test.tscn
run_case "leaderboard_post_action" res://tests/leaderboard_post_action_test.tscn
run_case "menu_composition_fidelity" res://tests/menu_composition_fidelity_test.tscn
run_case "menu_navigation_history" res://tests/menu_navigation_history_test.tscn
run_case "native_ios_auth_v2" res://tests/native_ios_auth_v2_test.tscn
run_case "page_fidelity_corrections" res://tests/page_fidelity_corrections_test.tscn
run_case "phone_safe_header" res://tests/phone_safe_header_test.tscn
run_case "runner_apparel" res://tests/runner_apparel_test.tscn
run_case "runner_camera_motion" res://tests/runner_camera_motion_test.tscn
run_case "runner_course_reference" res://tests/runner_course_reference_test.tscn
run_case "runner_covered_world" res://tests/runner_covered_world_test.tscn
run_case "runner_end_fidelity" res://tests/runner_end_fidelity_test.tscn
run_case "runner_pacing_calibration" res://tests/runner_pacing_calibration_test.tscn
run_case "runner_reference_ice" res://tests/runner_reference_ice_test.tscn
run_case "runner_reference_pose" res://tests/runner_reference_pose_test.tscn
run_case "runner_reference_walls" res://tests/runner_reference_walls_test.tscn
run_case "save_progress_prompt" res://tests/save_progress_prompt_test.tscn
run_case "settings_account_reference" res://tests/settings_account_reference_test.tscn
run_case "shop_functionality" res://tests/shop_functionality_test.tscn
run_case "shop_reference_bounds" res://tests/shop_reference_bounds_test.tscn
run_case "threaded_resource_lifetime" res://tests/threaded_resource_lifetime_test.tscn
run_case "wardrobe_outfit_catalog" res://tests/wardrobe_outfit_catalog_test.tscn
run_case "wardrobe_preview_flow" res://tests/wardrobe_preview_flow_test.tscn
run_case "reviewed_runner_penguin" res://tests/reviewed_runner_penguin_test.tscn
WW_TEST_CASE_TIMEOUT=0
run_case "unit_tests" res://tests/unit_tests.tscn
run_case "blizzard_lifetime" res://tests/blizzard_lifetime_test.tscn
run_case "menu_load_test" res://tests/menu_load_test.tscn
run_case "native_offline_mvp" res://tests/native_offline_mvp_test.tscn
run_case "commerce_contract" res://tests/commerce_contract_test.tscn
run_case "online_auth_contract" res://tests/online_auth_contract_test.tscn
run_case "native_accounts_client" res://tests/native_accounts_client_test.tscn
run_case "account_auth_ui" res://tests/account_auth_ui_test.tscn
run_case "cloud_save_privacy" res://tests/cloud_save_privacy_test.tscn
run_case "cloud_save_reconcile" res://tests/cloud_save_reconcile_test.tscn
run_case "account_deletion_cache" res://tests/account_deletion_cache_test.tscn
run_case "account_deletion_client" res://tests/account_deletion_client_test.tscn
run_case "account_deletion_retry" res://tests/account_deletion_retry_test.tscn
run_case "web_bridge_lifetime" res://tests/web_bridge_lifetime_test.tscn
run_case "account_deletion_ui" res://tests/account_deletion_ui_test.tscn
run_case "frontend_presentation_test" res://tests/frontend_presentation_test.tscn
run_case "customize_orientation_reflow_test" res://tests/customize_orientation_reflow_test.tscn
run_case "touch_scroll_gesture" res://tests/touch_scroll_gesture_test.tscn
run_case "utility_frontend_test" res://tests/utility_frontend_test.tscn
run_case "settings_governor_state" res://tests/settings_governor_state_test.tscn
run_case "perf_ticker_clock" res://tests/perf_ticker_clock_test.tscn
run_case "visual_library_live_detail" res://tests/visual_library_live_detail_test.tscn
run_case "course_poster_wave1_test" res://tests/course_poster_wave1_test.tscn
run_case "course_poster_wave2_test" res://tests/course_poster_wave2_test.tscn
run_case "art_foundation_test" res://tests/art_foundation_test.tscn
run_case "penguin_visual_contract" res://tests/penguin_visual_contract_test.tscn
run_case "penguin_authored_only" res://tests/penguin_authored_only_test.tscn
run_case "hero_penguin_asset_test" res://tests/hero_penguin_asset_test.tscn
run_case "hero_penguin_motion_test" res://tests/hero_penguin_motion_test.tscn
run_case "hero_penguin_controller_test" res://tests/hero_penguin_controller_test.tscn
run_case "hero_penguin_transition_test" res://tests/hero_penguin_transition_test.tscn
# Quantitative atlas shader proof needs a real window; headless explicitly
# skips. Run its isolated fixture in Compatibility and Mobile for visual gates.
run_case "hero_v12_atlas_shader" res://tests/hero_v12_atlas_shader_test.tscn
run_case "runner_platform_tests" res://tests/runner_platform_tests.tscn
run_case "runner_end_save" res://tests/runner_end_save_test.tscn
run_case "runner_progression" res://tests/runner_progression_test.tscn
run_case "mission_map_progression" res://tests/mission_map_progression_test.tscn
run_case "runner_death_boundary" res://tests/runner_death_boundary_test.tscn
run_case "runner_catch_pose" res://tests/runner_catch_pose_test.tscn
run_case "runner_retry_hud" res://tests/runner_retry_hud_test.tscn
run_case "runner_stream_staging" res://tests/runner_stream_staging_test.tscn
run_case "runner_live_quality" res://tests/runner_live_quality_test.tscn
run_case "runner_slide" res://tests/runner_slide_test.tscn
run_case "runner_sky_uniform" res://tests/runner_sky_uniform_test.tscn
run_case "runner_web_clock" res://tests/runner_web_clock_test.tscn
run_case "runner_audio_warmup" res://tests/runner_audio_warmup_test.tscn
run_case "audio_focus_runner" res://tests/audio_focus_runner_test.tscn
run_case "settings_tabs_reference" res://tests/settings_tabs_reference_test.tscn
run_case "runner_hud_shader_warmup" res://tests/runner_hud_shader_warmup_test.tscn
run_case "scene_router_presentation" res://tests/scene_router_presentation_test.tscn
run_case "scene_router_recovery" res://tests/scene_router_recovery_test.tscn
# Real >300-geometry warmup needs actual draws, not manually emitted signals.
# This fixture intentionally fails if run headless; execute it separately in
# an isolated-user-data project using the windowed command in TESTING.md.
skip_case "scene_router_initial_warmup" "real window required; separate actual-draw gate"
run_case "scene_router_recovery_capture_parse" res://tests/scene_router_recovery_capture.tscn -- parse_only=1
run_case "race_presentation_gate" res://tests/race_presentation_gate_test.tscn
run_case "tutorial_presentation_gate" res://tests/tutorial_presentation_gate_test.tscn
run_case "race_warmup_boundary" res://tests/race_warmup_boundary_test.tscn
run_case "runner_presentation_capture_parse" res://tests/runner_presentation_capture.tscn -- parse_only=1
run_case "runner_biome_readability" res://tests/runner_biome_readability_test.tscn
run_case "runner_camera_composition" res://tests/runner_camera_composition_test.tscn
run_case "runner_posed_mesh_bounds" res://tests/posed_mesh_screen_bounds_test.tscn
run_case "runner_perf_metadata" res://tests/runner_perf_metadata_test.tscn
run_case "runner_dusk_warmup" res://tests/runner_dusk_warmup_test.tscn
# Exact buffer/material pixel coverage needs a Compatibility window. The
# isolated run_dusk_warmup_raster.sh wrapper retains that separate evidence.
run_case "runner_dusk_warmup_raster" res://tests/dusk_warmup_raster_test.tscn
run_case "runner_peak_replay_contract" res://tests/runner_peak_replay_test.tscn
run_case "runner_shader_warmup_geometry" res://tests/shader_warmup_geometry_test.tscn
run_case "runner_shader_warmup_scope" res://tests/shader_warmup_scope_test.tscn
run_case "runner_initial_visual_warmup" res://tests/initial_visual_warmup_tests.tscn
run_case "runner_golden_slice" res://tests/runner_golden_slice.tscn
run_case "runner_day_kit_test" res://tests/runner_day_kit_test.tscn
run_case "runner_day_scoped_candidate_test" res://tests/runner_day_scoped_candidate_test.tscn
run_case "runner_start_apron_test" res://tests/runner_start_apron_test.tscn
run_case "runner_banner_timing" res://tests/runner_banner_timing_test.tscn
run_case "loader_style" res://tests/loader_style_test.tscn
run_case "menu_fidelity" res://tests/menu_fidelity_test.tscn
run_case "leaderboard_reference" res://tests/leaderboard_reference_test.tscn
run_case "utility_final_bounds" res://tests/utility_final_bounds_test.tscn
run_case "runner_powder_bounds" res://tests/runner_powder_bounds_test.tscn
run_case "runner_inrun_art" res://tests/runner_inrun_art_test.tscn
run_case "runner_readability" res://tests/runner_readability_test.tscn
run_case "runner_life_pressure" res://tests/runner_life_pressure_test.tscn
run_case "runner_rear_pressure" res://tests/runner_rear_pressure_test.tscn
run_case "runner_mobile_whiteout" res://tests/runner_mobile_whiteout_test.tscn
run_case "runner_results_rows" res://tests/runner_results_rows_test.tscn
run_case "runner_powerup_countdown" res://tests/runner_powerup_countdown_test.tscn
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
# The HUD and the touch buttons share the bottom strip of a phone screen, and
# nothing checked that they share it without colliding: the course gauge's
# right end -- the end carrying the percentage -- was drawn under SHOVE.
# Needs a window for the same reason the audit does.
run_case "race_hud_touch_layout" res://tests/race_hud_touch_layout.tscn
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
printf "%b" "$summary" > "$WW_TEST_EVIDENCE/summary.txt"
if [ "$overall" -ne 0 ]; then
    echo "RESULT: FAILURES PRESENT"
elif [[ "$summary" == *"SKIP  "* ]]; then
    echo "RESULT: ALL EXECUTED CHECKS PASSED"
else
    echo "RESULT: ALL PASSED"
fi
exit $overall
