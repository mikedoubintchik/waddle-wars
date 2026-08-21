#!/usr/bin/env bash
# Isolated windowed capture for runner's deterministic 360 m DAY golden slice.
# Usage: ./run_runner_capture.sh
#        ./run_runner_capture.sh w=540 h=960 out=/absolute/path/golden_portrait.png

set -u
cd "$(dirname "$0")"
WW_CAPTURE_ROOT="$PWD"

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
    echo "run_runner_capture.sh: no Godot executable found; set GODOT=/path/to/godot." >&2
    exit 2
fi

WW_CAPTURE_TMP_BASE="${TMPDIR:-/tmp}"
if [ "$WW_CAPTURE_TMP_BASE" != "/" ]; then
    WW_CAPTURE_TMP_BASE="${WW_CAPTURE_TMP_BASE%/}"
fi
if ! WW_CAPTURE_PROJECT="$(mktemp -d "$WW_CAPTURE_TMP_BASE/waddle-wars-capture.XXXXXX")"; then
    echo "run_runner_capture.sh: could not create isolated project under $WW_CAPTURE_TMP_BASE" >&2
    exit 2
fi
if [ ! -d "$WW_CAPTURE_PROJECT" ]; then
    echo "run_runner_capture.sh: mktemp returned a non-directory: $WW_CAPTURE_PROJECT" >&2
    exit 2
fi
WW_CAPTURE_RUN_ID="waddle-wars-capture-$$-${RANDOM:-0}"

cleanup_capture_workspace() {
    if [ -f "$WW_CAPTURE_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_CAPTURE_PROJECT" \
            --log-file "$WW_CAPTURE_PROJECT/clean.log" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_CAPTURE_PROJECT" in
        "$WW_CAPTURE_TMP_BASE"/waddle-wars-capture.*)
            rm -rf -- "$WW_CAPTURE_PROJECT"
            ;;
        *)
            echo "run_runner_capture.sh: refusing to remove unexpected path: $WW_CAPTURE_PROJECT" >&2
            ;;
    esac
}
trap cleanup_capture_workspace EXIT

for WW_RESOURCE_DIR in assets data scenes scripts tests; do
    if ! cp -R "$WW_CAPTURE_ROOT/$WW_RESOURCE_DIR" \
            "$WW_CAPTURE_PROJECT/$WW_RESOURCE_DIR"; then
        echo "run_runner_capture.sh: could not snapshot $WW_RESOURCE_DIR" >&2
        exit 2
    fi
done
awk -v ww_capture_id="$WW_CAPTURE_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", ww_capture_id
    }
' "$WW_CAPTURE_ROOT/project.godot" > "$WW_CAPTURE_PROJECT/project.godot" || {
    echo "run_runner_capture.sh: could not write isolated project.godot" >&2
    exit 2
}

if ! "$GODOT_BIN" --headless --import --path "$WW_CAPTURE_PROJECT" \
        --log-file "$WW_CAPTURE_PROJECT/import.log" \
        >"$WW_CAPTURE_PROJECT/import.stdout" 2>"$WW_CAPTURE_PROJECT/import.stderr"; then
    echo "run_runner_capture.sh: isolated import failed" >&2
    sed -n '1,160p' "$WW_CAPTURE_PROJECT/import.stderr" >&2
    exit 2
fi
if grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_CAPTURE_PROJECT/import.log"; then
    echo "run_runner_capture.sh: isolated import reported errors" >&2
    sed -n '1,200p' "$WW_CAPTURE_PROJECT/import.log" >&2
    exit 2
fi
if awk '
    NF && $0 != "cannot connect to daemon at tcp:5037: Connection refused" { bad = 1 }
    END { exit bad ? 0 : 1 }
' "$WW_CAPTURE_PROJECT/import.stderr"; then
    echo "run_runner_capture.sh: isolated import wrote unexpected stderr" >&2
    sed -n '1,160p' "$WW_CAPTURE_PROJECT/import.stderr" >&2
    exit 2
fi

if ! mkdir -p "$WW_CAPTURE_ROOT/qa_shots/runner"; then
    echo "run_runner_capture.sh: could not create qa_shots/runner" >&2
    exit 2
fi
WW_CAPTURE_DEFAULT_ARGS=(
    "out=$WW_CAPTURE_ROOT/qa_shots/runner/golden_review.png"
    "w=1600"
    "h=900"
    "touch=1"
)

echo "Isolated capture project: $WW_CAPTURE_PROJECT"
"$GODOT_BIN" --path "$WW_CAPTURE_PROJECT" --rendering-method gl_compatibility \
    --log-file "$WW_CAPTURE_PROJECT/capture.log" \
    res://tests/runner_golden_shot.tscn -- "${WW_CAPTURE_DEFAULT_ARGS[@]}" "$@"
WW_CAPTURE_CODE=$?
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' \
        "$WW_CAPTURE_PROJECT/capture.log"; then
    echo "run_runner_capture.sh: capture reported runtime script/resource errors" >&2
    sed -n '1,200p' "$WW_CAPTURE_PROJECT/capture.log" >&2
    if [ "$WW_CAPTURE_CODE" -eq 0 ]; then
        WW_CAPTURE_CODE=1
    fi
fi
exit "$WW_CAPTURE_CODE"
