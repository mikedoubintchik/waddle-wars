#!/usr/bin/env bash
# Isolated premium front-end contract, capture, and performance harness.
#   ./run_frontend_qa.sh test
#   ./run_frontend_qa.sh shot screen=title out=/absolute/path/title.png w=1920 h=1080
#   ./run_frontend_qa.sh loader_boundary out=/absolute/path/loader.png w=540 h=960
#   ./run_frontend_qa.sh loader_recovery out=/absolute/path/recovery.png w=540 h=960
#   ./run_frontend_qa.sh runner_handoff out=/absolute/path/handoff.png w=540 h=960
#   ./run_frontend_qa.sh runner_store out=/absolute/path/run.png w=1080 h=1920 phone_preview=1
#   ./run_frontend_qa.sh race_store out=/absolute/path/race.png w=1080 h=1920
#   ./run_frontend_qa.sh window_mvp
#   ./run_frontend_qa.sh menu_mvp # full phone menu reachability/captures
#   ./run_frontend_qa.sh menu_insets # focused main-menu safe-area/rotation matrix
#   ./run_frontend_qa.sh menu_audit # all menus, real windows, no captures
#   ./run_frontend_qa.sh window_mvp_remaining # retain earlier menu/orientation receipts
#   ./run_frontend_qa.sh runner_cycle # loading/input/retry captures only
#   ./run_frontend_qa.sh account_deletion out=/absolute/fresh/deletion.png w=320 h=568 ui_scale=1.4
#   ./run_frontend_qa.sh perf screen=title seconds=5 enforce=1

set -u
cd "$(dirname "$0")"
WW_FRONT_ROOT="$PWD"
WW_FRONT_MODE="${1:-test}"
if [ "$#" -gt 0 ]; then shift; fi

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

run_guarded() {
    WW_FRONT_TIMEOUT="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$WW_FRONT_TIMEOUT" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$WW_FRONT_TIMEOUT" "$@"
    else
        perl -e '$seconds = shift @ARGV; alarm $seconds; exec @ARGV' \
            "$WW_FRONT_TIMEOUT" "$@"
    fi
}
if [ -z "$GODOT_BIN" ]; then
    echo "run_frontend_qa.sh: no Godot executable found; set GODOT=/path/to/godot." >&2
    exit 2
fi

WW_FRONT_TMP_BASE="${TMPDIR:-/tmp}"
WW_FRONT_TMP_BASE="${WW_FRONT_TMP_BASE%/}"
if [ -z "$WW_FRONT_TMP_BASE" ] || [ "$WW_FRONT_TMP_BASE" = "/" ]; then
    WW_FRONT_TMP_BASE="/tmp"
fi
if ! WW_FRONT_PROJECT="$(mktemp -d "$WW_FRONT_TMP_BASE/waddle-wars-frontend.XXXXXX")"; then
    echo "run_frontend_qa.sh: could not create isolated project under $WW_FRONT_TMP_BASE" >&2
    exit 2
fi
if [ ! -d "$WW_FRONT_PROJECT" ]; then
    echo "run_frontend_qa.sh: mktemp returned a non-directory: $WW_FRONT_PROJECT" >&2
    exit 2
fi
WW_FRONT_RUN_ID="waddle-wars-frontend-$$-${RANDOM:-0}"
WW_FRONT_EVIDENCE=""

cleanup_frontend_workspace() {
    if [ -n "$WW_FRONT_EVIDENCE" ]; then
        for filename in "$WW_FRONT_PROJECT"/*.log "$WW_FRONT_PROJECT"/*.stdout \
                "$WW_FRONT_PROJECT"/*.stderr "$WW_FRONT_PROJECT"/*.status; do
            if [ -f "$filename" ]; then
                cp "$filename" "$WW_FRONT_EVIDENCE/" || \
                    echo "run_frontend_qa.sh: could not preserve $filename" >&2
            fi
        done
    fi
    if [ -f "$WW_FRONT_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_FRONT_PROJECT" \
            --log-file "$WW_FRONT_PROJECT/clean.log" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_FRONT_PROJECT" in
        "$WW_FRONT_TMP_BASE"/waddle-wars-frontend.*)
            rm -rf -- "$WW_FRONT_PROJECT"
            ;;
        *)
            echo "run_frontend_qa.sh: refusing unexpected cleanup path: $WW_FRONT_PROJECT" >&2
            ;;
    esac
}
trap cleanup_frontend_workspace EXIT
if [ "$WW_FRONT_MODE" = "menu_mvp" ] || [ "$WW_FRONT_MODE" = "menu_insets" ] || [ "$WW_FRONT_MODE" = "menu_audit" ] || [ "$WW_FRONT_MODE" = "window_mvp" ] || [ "$WW_FRONT_MODE" = "window_mvp_remaining" ] \
        || [ "$WW_FRONT_MODE" = "runner_cycle" ] || [ "$WW_FRONT_MODE" = "menu_refresh" ]; then
    if [ "$#" -ne 0 ]; then
        echo "run_frontend_qa.sh: window MVP modes use fixed local-only fixture lists; no arguments" >&2
        exit 2
    fi
    mkdir -p "$WW_FRONT_ROOT/qa_shots/tests" || exit 2
    WW_FRONT_EVIDENCE="$(mktemp -d "$WW_FRONT_ROOT/qa_shots/tests/$WW_FRONT_RUN_ID.XXXXXX")" || exit 2
    echo "Window MVP evidence: $WW_FRONT_EVIDENCE"
fi

for WW_FRONT_DIR in assets data scenes scripts tests; do
    if ! cp -R "$WW_FRONT_ROOT/$WW_FRONT_DIR" "$WW_FRONT_PROJECT/$WW_FRONT_DIR"; then
        echo "run_frontend_qa.sh: could not snapshot $WW_FRONT_DIR" >&2
        exit 2
    fi
done
# Optional fast local render iteration. Copy only content-addressed import
# outputs, not editor settings or user data. Godot still validates imports.
# Default remains an uncached import for final acceptance.
if [ "${WW_FRONT_REUSE_IMPORTS:-0}" = "1" ] && [ -d "$WW_FRONT_ROOT/.godot/imported" ]; then
    mkdir -p "$WW_FRONT_PROJECT/.godot"
    cp -R "$WW_FRONT_ROOT/.godot/imported" "$WW_FRONT_PROJECT/.godot/imported" || exit 2
    echo "Cached import artifacts reused for local visual iteration; not a fresh-import receipt."
fi
awk -v run_id="$WW_FRONT_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", run_id
    }
' "$WW_FRONT_ROOT/project.godot" > "$WW_FRONT_PROJECT/project.godot" || exit 2

preserve_import_failure() {
    local evidence=""
    local evidence_root="$WW_FRONT_ROOT/qa_shots/tests"
    local filename
    if mkdir -p "$evidence_root"; then
        evidence="$(mktemp -d "$evidence_root/$WW_FRONT_RUN_ID.XXXXXX")" || evidence=""
    fi
    if [ -n "$evidence" ] && [ -d "$evidence" ]; then
        for filename in import.log import.stdout import.stderr; do
            if [ -f "$WW_FRONT_PROJECT/$filename" ]; then
                cp "$WW_FRONT_PROJECT/$filename" "$evidence/$filename" || \
                    echo "run_frontend_qa.sh: could not preserve $filename" >&2
            fi
        done
        echo "Import failure evidence: $evidence" >&2
    else
        echo "run_frontend_qa.sh: could not create import evidence directory" >&2
    fi
    # Import may fail before creating import.log, or put a native crash only
    # on stdout. Print all available channels before EXIT cleanup removes the
    # copied project; do not rely on Godot's exit code to expose parse errors.
    if [ -f "$WW_FRONT_PROJECT/import.stdout" ]; then
        tail -80 "$WW_FRONT_PROJECT/import.stdout" >&2
    fi
    if [ -f "$WW_FRONT_PROJECT/import.stderr" ]; then
        sed -n '1,160p' "$WW_FRONT_PROJECT/import.stderr" >&2
    fi
    if [ -f "$WW_FRONT_PROJECT/import.log" ]; then
        tail -200 "$WW_FRONT_PROJECT/import.log" >&2
    fi
}

run_guarded 120 "$GODOT_BIN" --headless --import --path "$WW_FRONT_PROJECT" \
    --log-file "$WW_FRONT_PROJECT/import.log" \
    >"$WW_FRONT_PROJECT/import.stdout" 2>"$WW_FRONT_PROJECT/import.stderr"
WW_FRONT_IMPORT_CODE=$?
if [ "$WW_FRONT_IMPORT_CODE" -ne 0 ]; then
    echo "run_frontend_qa.sh: isolated project import failed (exit $WW_FRONT_IMPORT_CODE)" >&2
    preserve_import_failure
    exit 2
fi
if [ ! -f "$WW_FRONT_PROJECT/import.log" ]; then
    echo "run_frontend_qa.sh: isolated project import produced no engine log" >&2
    preserve_import_failure
    exit 2
fi
if grep -Eq 'SCRIPT ERROR:|Parse Error:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_FRONT_PROJECT/import.log" "$WW_FRONT_PROJECT/import.stdout" \
        "$WW_FRONT_PROJECT/import.stderr"; then
    echo "run_frontend_qa.sh: isolated project import reported errors" >&2
    preserve_import_failure
    exit 2
fi
# Homebrew Godot may probe a non-running Android adb daemon. Ignore only this
# exact external-tool line; all other nonblank stderr must remain actionable.
if awk '
    NF && $0 != "cannot connect to daemon at tcp:5037: Connection refused" { bad = 1 }
    END { exit bad ? 0 : 1 }
' "$WW_FRONT_PROJECT/import.stderr"; then
    echo "run_frontend_qa.sh: isolated project import wrote unexpected stderr" >&2
    preserve_import_failure
    exit 2
fi

run_window_fixture() {
    local fixture="$1" seconds="$2" scene="$3"
    shift 3
    local code=0
    run_guarded "$seconds" "$GODOT_BIN" --path "$WW_FRONT_PROJECT" \
        --rendering-method gl_compatibility \
        --log-file "$WW_FRONT_PROJECT/$fixture.log" "$scene" -- "$@" \
        >"$WW_FRONT_PROJECT/$fixture.stdout" 2>"$WW_FRONT_PROJECT/$fixture.stderr" || code=$?
    if [ ! -f "$WW_FRONT_PROJECT/$fixture.log" ]; then
        echo "$fixture: missing engine log" >&2
        [ "$code" -ne 0 ] || code=1
    elif grep -Eq 'SCRIPT ERROR:|Parse Error:|(^|[[:space:]])ERROR:|Failed loading resource' \
            "$WW_FRONT_PROJECT/$fixture.log" "$WW_FRONT_PROJECT/$fixture.stdout" \
            "$WW_FRONT_PROJECT/$fixture.stderr"; then
        [ "$code" -ne 0 ] || code=1
    fi
    printf '%s\n' "$code" > "$WW_FRONT_PROJECT/$fixture.status"
    echo "$fixture: exit $code"
    tail -8 "$WW_FRONT_PROJECT/$fixture.stdout"
    if [ "$code" -ne 0 ]; then
        tail -100 "$WW_FRONT_PROJECT/$fixture.stderr" >&2
        return "$code"
    fi
}

case "$WW_FRONT_MODE" in
    menu_refresh)
        # One import, bounded serial captures for the requested visual pass.
        for screen in base_camp_desktop leaderboard_desktop leaderboard_populated_desktop runner_results_desktop; do
            run_window_fixture "$screen" 45 res://tests/frontend_shot.tscn \
                "screen=$screen" "out=$WW_FRONT_EVIDENCE/$screen.png" w=1600 h=900 || exit $?
        done
        run_window_fixture results_portrait 45 res://tests/frontend_shot.tscn \
            screen=runner_results "out=$WW_FRONT_EVIDENCE/results_portrait.png" w=540 h=960 || exit $?
        run_window_fixture themed_loader 45 res://tests/scene_router_loader_capture.tscn \
            "out=$WW_FRONT_EVIDENCE/themed_loader.png" w=540 h=960 || exit $?
        echo "Menu refresh captures: $WW_FRONT_EVIDENCE"
        exit 0
        ;;
    menu_insets)
        run_window_fixture main_menu_insets 90 res://tests/mobile_ui_audit.tscn \
            menu_insets=true || exit $?
        echo "Main-menu inset matrix complete; logs: $WW_FRONT_EVIDENCE"
        exit 0
        ;;
    menu_audit)
        run_window_fixture mobile_ui_audit 120 res://tests/mobile_ui_audit.tscn || exit $?
        echo "Menu reachability audit complete; logs: $WW_FRONT_EVIDENCE"
        exit 0
        ;;
    menu_mvp)
		run_window_fixture mobile_ui_audit 240 res://tests/mobile_ui_audit.tscn \
            "out=$WW_FRONT_EVIDENCE/menu.png" || exit $?
        echo "Requested menu fixtures complete; logs/captures: $WW_FRONT_EVIDENCE"
        exit 0
        ;;
    window_mvp|window_mvp_remaining|runner_cycle)
        # One frozen snapshot/import, serial real-window fixtures. These prove
        # native Compatibility layout/ordering, not browser/device performance.
        if [ "$WW_FRONT_MODE" = "window_mvp" ]; then
            run_window_fixture orientation_recovery 15 res://tests/orientation_recovery_test.tscn || exit $?
            run_window_fixture mobile_ui_audit 90 res://tests/mobile_ui_audit.tscn \
                "out=$WW_FRONT_EVIDENCE/menu.png" || exit $?
        fi
        if [ "$WW_FRONT_MODE" != "runner_cycle" ]; then
            run_window_fixture race_hud_touch_layout 60 res://tests/race_hud_touch_layout.tscn || exit $?
            run_window_fixture initial_warmup 40 res://tests/scene_router_initial_warmup_test.tscn || exit $?
        fi
        run_window_fixture runner_portrait 90 res://tests/runner_presentation_capture.tscn \
            "out=$WW_FRONT_EVIDENCE/runner_portrait.png" w=540 h=960 cycle=1 || exit $?
        run_window_fixture runner_landscape 90 res://tests/runner_presentation_capture.tscn \
            "out=$WW_FRONT_EVIDENCE/runner_landscape.png" w=960 h=540 cycle=1 || exit $?
        echo "Requested window fixtures complete ($WW_FRONT_MODE); logs/captures: $WW_FRONT_EVIDENCE"
        exit 0
        ;;
    test)
        run_guarded 60 "$GODOT_BIN" --headless --path "$WW_FRONT_PROJECT" \
            --log-file "$WW_FRONT_PROJECT/test.log" \
            res://tests/frontend_presentation_test.tscn -- "$@"
        ;;
    shot)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/shot.log" \
            res://tests/frontend_shot.tscn -- "$@"
        ;;
    loader_boundary)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/loader_boundary.log" \
            res://tests/scene_router_loader_capture.tscn -- "$@"
        ;;
    loader_recovery)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/loader_recovery.log" \
            res://tests/scene_router_recovery_capture.tscn -- "$@"
        ;;
    runner_handoff)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/runner_handoff.log" \
            res://tests/runner_presentation_capture.tscn -- "$@"
        ;;
    runner_store)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/runner_store.log" \
            res://tests/runner_shot.tscn -- "$@"
        ;;
    race_store)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/race_store.log" \
            res://tests/store_race_shot.tscn -- "$@"
        ;;
    account_deletion)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/account_deletion.log" \
            res://tests/account_deletion_capture.tscn -- "$@"
        ;;
    perf)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/perf.log" \
            res://tests/frontend_perf_probe.tscn -- "$@"
        ;;
    *)
        echo "run_frontend_qa.sh: mode must be test, shot, menu_insets, menu_mvp, loader_boundary, loader_recovery, runner_handoff, runner_store, race_store, window_mvp, window_mvp_remaining, runner_cycle, account_deletion, or perf" >&2
        exit 2
        ;;
esac
WW_FRONT_CODE=$?
WW_FRONT_LOG="$WW_FRONT_PROJECT/$WW_FRONT_MODE.log"
if [ ! -f "$WW_FRONT_LOG" ]; then
    echo "run_frontend_qa.sh: runtime produced no engine log" >&2
    [ "$WW_FRONT_CODE" -ne 0 ] || WW_FRONT_CODE=1
elif grep -Eq \
        'SCRIPT ERROR:|Parse Error:|(^|[[:space:]])ERROR:|Failed loading resource' "$WW_FRONT_LOG"; then
    # Godot can exit zero after renderer/engine errors too. A screenshot or
    # fixture PASS is not a clean run if its engine log reports a failure.
    sed -n '1,220p' "$WW_FRONT_LOG" >&2
    [ "$WW_FRONT_CODE" -ne 0 ] || WW_FRONT_CODE=1
fi
exit "$WW_FRONT_CODE"
