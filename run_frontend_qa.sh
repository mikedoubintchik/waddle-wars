#!/usr/bin/env bash
# Isolated premium front-end contract, capture, and performance harness.
#   ./run_frontend_qa.sh test
#   ./run_frontend_qa.sh shot screen=title out=/absolute/path/title.png w=1920 h=1080
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

cleanup_frontend_workspace() {
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

for WW_FRONT_DIR in assets data scenes scripts tests; do
    if ! cp -R "$WW_FRONT_ROOT/$WW_FRONT_DIR" "$WW_FRONT_PROJECT/$WW_FRONT_DIR"; then
        echo "run_frontend_qa.sh: could not snapshot $WW_FRONT_DIR" >&2
        exit 2
    fi
done
awk -v run_id="$WW_FRONT_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", run_id
    }
' "$WW_FRONT_ROOT/project.godot" > "$WW_FRONT_PROJECT/project.godot" || exit 2

run_guarded 120 "$GODOT_BIN" --headless --import --path "$WW_FRONT_PROJECT" \
    --log-file "$WW_FRONT_PROJECT/import.log" \
    >"$WW_FRONT_PROJECT/import.stdout" 2>"$WW_FRONT_PROJECT/import.stderr" || exit 2
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' \
        "$WW_FRONT_PROJECT/import.log"; then
    sed -n '1,200p' "$WW_FRONT_PROJECT/import.log" >&2
    exit 2
fi

case "$WW_FRONT_MODE" in
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
    perf)
        run_guarded 90 "$GODOT_BIN" --path "$WW_FRONT_PROJECT" --rendering-method gl_compatibility \
            --log-file "$WW_FRONT_PROJECT/perf.log" \
            res://tests/frontend_perf_probe.tscn -- "$@"
        ;;
    *)
        echo "run_frontend_qa.sh: mode must be test, shot, or perf" >&2
        exit 2
        ;;
esac
WW_FRONT_CODE=$?
WW_FRONT_LOG="$WW_FRONT_PROJECT/$WW_FRONT_MODE.log"
if [ -f "$WW_FRONT_LOG" ] && grep -Eq \
        'SCRIPT ERROR:|Parse Error:|Failed loading resource' "$WW_FRONT_LOG"; then
    sed -n '1,220p' "$WW_FRONT_LOG" >&2
    [ "$WW_FRONT_CODE" -ne 0 ] || WW_FRONT_CODE=1
fi
exit "$WW_FRONT_CODE"
