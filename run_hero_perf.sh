#!/usr/bin/env bash
# Isolated frozen Glacier eight-racer authored-penguin performance probe.
# Usage: ./run_hero_perf.sh method=gl_compatibility baseline=true tier=high
# Then pass printed baseline_average_ms/baseline_p95_ms/baseline_draw_peak to
# the authored enforce=true run at the same renderer/tier/resolution.

set -u
cd "$(dirname "$0")"
WW_HERO_PERF_ROOT="$PWD"
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
    echo "run_hero_perf.sh: no Godot executable found; set GODOT=/path/to/godot." >&2
    exit 2
fi

WW_HERO_PERF_METHOD="gl_compatibility"
WW_HERO_PERF_SCENE="course"
WW_HERO_PERF_OUT=""
WW_HERO_PERF_ARGS=()
WW_HERO_PERF_ARG_COUNT=0
for argument in "$@"; do
    case "$argument" in
        method=*) WW_HERO_PERF_METHOD="${argument#method=}" ;;
        scene=*) WW_HERO_PERF_SCENE="${argument#scene=}" ;;
        out=*)
            WW_HERO_PERF_OUT="${argument#out=}"
            WW_HERO_PERF_ARGS+=("$argument")
            WW_HERO_PERF_ARG_COUNT=$((WW_HERO_PERF_ARG_COUNT + 1))
            ;;
        *)
            WW_HERO_PERF_ARGS+=("$argument")
            WW_HERO_PERF_ARG_COUNT=$((WW_HERO_PERF_ARG_COUNT + 1))
            ;;
    esac
done
case "$WW_HERO_PERF_METHOD" in
    gl_compatibility|mobile) ;;
    *) echo "run_hero_perf.sh: method must be gl_compatibility or mobile" >&2; exit 2 ;;
esac
case "$WW_HERO_PERF_SCENE" in
    course) WW_HERO_PERF_TSCN="res://tests/hero_penguin_course_perf.tscn" ;;
    focused) WW_HERO_PERF_TSCN="res://tests/hero_penguin_race_perf.tscn" ;;
    *) echo "run_hero_perf.sh: scene must be course or focused" >&2; exit 2 ;;
esac
if [ -z "$WW_HERO_PERF_OUT" ]; then
    WW_HERO_PERF_OUT="/tmp/waddle-hero-perf-${WW_HERO_PERF_METHOD}.json"
    WW_HERO_PERF_ARGS+=("out=$WW_HERO_PERF_OUT")
    WW_HERO_PERF_ARG_COUNT=$((WW_HERO_PERF_ARG_COUNT + 1))
fi

WW_HERO_PERF_TMP_BASE="${TMPDIR:-/tmp}"
WW_HERO_PERF_TMP_BASE="${WW_HERO_PERF_TMP_BASE%/}"
if [ -z "$WW_HERO_PERF_TMP_BASE" ] || [ "$WW_HERO_PERF_TMP_BASE" = "/" ]; then
    WW_HERO_PERF_TMP_BASE="/tmp"
fi
WW_HERO_PERF_PROJECT="$(mktemp -d "$WW_HERO_PERF_TMP_BASE/waddle-wars-hero-perf.XXXXXX")" || exit 2
case "$WW_HERO_PERF_PROJECT" in
    "$WW_HERO_PERF_TMP_BASE"/waddle-wars-hero-perf.*) ;;
    *) echo "run_hero_perf.sh: unsafe temporary path: $WW_HERO_PERF_PROJECT" >&2; exit 2 ;;
esac

cleanup_hero_perf() {
    if [ -f "$WW_HERO_PERF_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_HERO_PERF_PROJECT" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_HERO_PERF_PROJECT" in
        "$WW_HERO_PERF_TMP_BASE"/waddle-wars-hero-perf.*) rm -rf -- "$WW_HERO_PERF_PROJECT" ;;
    esac
}
trap cleanup_hero_perf EXIT

for WW_HERO_PERF_DIR in assets data scenes scripts tests; do
    cp -R "$WW_HERO_PERF_ROOT/$WW_HERO_PERF_DIR" "$WW_HERO_PERF_PROJECT/$WW_HERO_PERF_DIR" || exit 2
done
WW_HERO_PERF_RUN_ID="waddle-wars-hero-perf-$$-${RANDOM:-0}"
awk -v run_id="$WW_HERO_PERF_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", run_id
    }
' "$WW_HERO_PERF_ROOT/project.godot" > "$WW_HERO_PERF_PROJECT/project.godot" || exit 2

"$GODOT_BIN" --headless --import --path "$WW_HERO_PERF_PROJECT" \
    --log-file "$WW_HERO_PERF_PROJECT/import.log" \
    >"$WW_HERO_PERF_PROJECT/import.stdout" 2>"$WW_HERO_PERF_PROJECT/import.stderr" || exit 2
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' "$WW_HERO_PERF_PROJECT/import.log"; then
    sed -n '1,220p' "$WW_HERO_PERF_PROJECT/import.log" >&2
    exit 2
fi

WW_HERO_PERF_LOG="$WW_HERO_PERF_PROJECT/perf.log"
if [ "$WW_HERO_PERF_ARG_COUNT" -gt 0 ]; then
    "$GODOT_BIN" --path "$WW_HERO_PERF_PROJECT" \
        --rendering-method "$WW_HERO_PERF_METHOD" --log-file "$WW_HERO_PERF_LOG" \
        "$WW_HERO_PERF_TSCN" -- "${WW_HERO_PERF_ARGS[@]}"
else
    "$GODOT_BIN" --path "$WW_HERO_PERF_PROJECT" \
        --rendering-method "$WW_HERO_PERF_METHOD" --log-file "$WW_HERO_PERF_LOG" \
        "$WW_HERO_PERF_TSCN"
fi
WW_HERO_PERF_CODE=$?
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource|Parameter "data.tree" is null' \
        "$WW_HERO_PERF_LOG"; then
    sed -n '1,240p' "$WW_HERO_PERF_LOG" >&2
    WW_HERO_PERF_CODE=1
fi
if [ ! -s "$WW_HERO_PERF_OUT" ]; then
    echo "run_hero_perf.sh: missing report: $WW_HERO_PERF_OUT" >&2
    WW_HERO_PERF_CODE=1
fi
exit "$WW_HERO_PERF_CODE"
