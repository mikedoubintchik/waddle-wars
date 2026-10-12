#!/usr/bin/env bash
# Windowed runner performance probe under an isolated project identity/user://.
# Usage: ./run_runner_perf.sh tier=high w=1920 h=1080 seconds=30 enforce=true

set -u
cd "$(dirname "$0")"
WW_PERF_ROOT="$PWD"

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
    echo "run_runner_perf.sh: no Godot executable found; set GODOT=/path/to/godot." >&2
    exit 2
fi

WW_PERF_TMP_BASE="${TMPDIR:-/tmp}"
if [ "$WW_PERF_TMP_BASE" != "/" ]; then
    WW_PERF_TMP_BASE="${WW_PERF_TMP_BASE%/}"
fi
if ! WW_PERF_PROJECT="$(mktemp -d "$WW_PERF_TMP_BASE/waddle-wars-perf.XXXXXX")"; then
    echo "run_runner_perf.sh: could not create isolated project under $WW_PERF_TMP_BASE" >&2
    exit 2
fi
if [ ! -d "$WW_PERF_PROJECT" ]; then
    echo "run_runner_perf.sh: mktemp returned a non-directory: $WW_PERF_PROJECT" >&2
    exit 2
fi
WW_PERF_RUN_ID="waddle-wars-perf-$$-${RANDOM:-0}"

cleanup_perf_workspace() {
    if [ -f "$WW_PERF_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_PERF_PROJECT" \
            --log-file "$WW_PERF_PROJECT/clean.log" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_PERF_PROJECT" in
        "$WW_PERF_TMP_BASE"/waddle-wars-perf.*)
            rm -rf -- "$WW_PERF_PROJECT"
            ;;
        *)
            echo "run_runner_perf.sh: refusing to remove unexpected path: $WW_PERF_PROJECT" >&2
            ;;
    esac
}
trap cleanup_perf_workspace EXIT

for WW_RESOURCE_DIR in assets data scenes scripts tests; do
    if ! cp -R "$WW_PERF_ROOT/$WW_RESOURCE_DIR" \
            "$WW_PERF_PROJECT/$WW_RESOURCE_DIR"; then
        echo "run_runner_perf.sh: could not snapshot $WW_RESOURCE_DIR" >&2
        exit 2
    fi
done
awk -v ww_perf_id="$WW_PERF_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", ww_perf_id
    }
' "$WW_PERF_ROOT/project.godot" > "$WW_PERF_PROJECT/project.godot" || {
    echo "run_runner_perf.sh: could not write isolated project.godot" >&2
    exit 2
}

if ! "$GODOT_BIN" --headless --import --path "$WW_PERF_PROJECT" \
        --log-file "$WW_PERF_PROJECT/import.log" \
        >"$WW_PERF_PROJECT/import.stdout" 2>"$WW_PERF_PROJECT/import.stderr"; then
    echo "run_runner_perf.sh: isolated import failed" >&2
    sed -n '1,160p' "$WW_PERF_PROJECT/import.stderr" >&2
    exit 2
fi
if grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_PERF_PROJECT/import.log"; then
    echo "run_runner_perf.sh: isolated import reported errors" >&2
    sed -n '1,200p' "$WW_PERF_PROJECT/import.log" >&2
    exit 2
fi
if awk '
    NF && $0 != "cannot connect to daemon at tcp:5037: Connection refused" { bad = 1 }
    END { exit bad ? 0 : 1 }
' "$WW_PERF_PROJECT/import.stderr"; then
    echo "run_runner_perf.sh: isolated import wrote unexpected stderr" >&2
    sed -n '1,160p' "$WW_PERF_PROJECT/import.stderr" >&2
    exit 2
fi

WW_PERF_HAS_OUT=0
for WW_PERF_ARG in "$@"; do
    case "$WW_PERF_ARG" in
        out=*) WW_PERF_HAS_OUT=1 ;;
    esac
done
WW_PERF_DEFAULT_OUT=""
if [ "$WW_PERF_HAS_OUT" -eq 0 ]; then
    if ! mkdir -p "$WW_PERF_ROOT/qa_shots/runner"; then
        echo "run_runner_perf.sh: could not create qa_shots/runner" >&2
        exit 2
    fi
    WW_PERF_DEFAULT_OUT="out=$WW_PERF_ROOT/qa_shots/runner/runner_perf.json"
fi

echo "Isolated performance project: $WW_PERF_PROJECT"
if [ -n "$WW_PERF_DEFAULT_OUT" ]; then
    "$GODOT_BIN" --path "$WW_PERF_PROJECT" --rendering-method gl_compatibility \
        --log-file "$WW_PERF_PROJECT/perf.log" \
        res://tests/runner_perf_probe.tscn -- "$WW_PERF_DEFAULT_OUT" "$@"
else
    # Bash 3.2 treats expansion of an empty array as an unbound variable under
    # `set -u`; keep the explicit-output path array-free for macOS runners.
    "$GODOT_BIN" --path "$WW_PERF_PROJECT" --rendering-method gl_compatibility \
        --log-file "$WW_PERF_PROJECT/perf.log" \
        res://tests/runner_perf_probe.tscn -- "$@"
fi
WW_PERF_CODE=$?
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' \
        "$WW_PERF_PROJECT/perf.log"; then
    echo "run_runner_perf.sh: probe reported runtime script/resource errors" >&2
    sed -n '1,200p' "$WW_PERF_PROJECT/perf.log" >&2
    if [ "$WW_PERF_CODE" -eq 0 ]; then
        WW_PERF_CODE=1
    fi
fi
exit "$WW_PERF_CODE"
