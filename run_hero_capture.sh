#!/usr/bin/env bash
# Isolated authored-penguin visual matrix.
# Usage: ./run_hero_capture.sh output=/tmp/hero [render=silhouette]
# Optional matrix filters: views=side,chase orientations=landscape
# Optional cosmetic args pass through: hat=hat_beanie scarf=scarf_red goggles=goggles_ski
# Motion: ./run_hero_capture.sh motion=run fps=30 seconds=2 output=/tmp/hero-run-30
# Motion defaults: front/side/chase, landscape, beauty+silhouette. Use fresh output.
# Narrow capture: views=side renders=beauty always_on_top=true
# Import/parser check without opening a renderer: verify_only=true

set -u
cd "$(dirname "$0")"
WW_HERO_ROOT="$PWD"
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
    echo "run_hero_capture.sh: no Godot executable found; set GODOT=/path/to/godot." >&2
    exit 2
fi

WW_HERO_OUTPUT="/tmp/waddle-hero-penguin-polish"
WW_HERO_VIEWS="close threequarter side chase"
WW_HERO_ORIENTATIONS="landscape portrait"
WW_HERO_RENDERS="beauty"
WW_HERO_VIEWS_SET=0
WW_HERO_ORIENTATIONS_SET=0
WW_HERO_RENDERS_SET=0
WW_HERO_MOTION=""
WW_HERO_FPS=60
WW_HERO_SECONDS=2
WW_HERO_VERIFY_ONLY=0
WW_HERO_HAT=""
WW_HERO_SCARF=""
WW_HERO_GOGGLES=""
WW_HERO_EXTRA=()
WW_HERO_EXTRA_COUNT=0
for argument in "$@"; do
    case "$argument" in
        output=*) WW_HERO_OUTPUT="${argument#output=}" ;;
        views=*)
            WW_HERO_VIEWS="${argument#views=}"; WW_HERO_VIEWS="${WW_HERO_VIEWS//,/ }"
            WW_HERO_VIEWS_SET=1
            ;;
        orientations=*)
            WW_HERO_ORIENTATIONS="${argument#orientations=}"
            WW_HERO_ORIENTATIONS="${WW_HERO_ORIENTATIONS//,/ }"
            WW_HERO_ORIENTATIONS_SET=1
            ;;
        render=*)
            WW_HERO_RENDERS="${argument#render=}"
            WW_HERO_RENDERS_SET=1
            ;;
        renders=*)
            WW_HERO_RENDERS="${argument#renders=}"; WW_HERO_RENDERS="${WW_HERO_RENDERS//,/ }"
            WW_HERO_RENDERS_SET=1
            ;;
        motion=*) WW_HERO_MOTION="${argument#motion=}" ;;
        fps=*) WW_HERO_FPS="${argument#fps=}" ;;
        seconds=*) WW_HERO_SECONDS="${argument#seconds=}" ;;
        verify_only=true) WW_HERO_VERIFY_ONLY=1 ;;
        hat=*)
            WW_HERO_HAT="${argument#hat=}"
            WW_HERO_EXTRA+=("$argument")
            WW_HERO_EXTRA_COUNT=$((WW_HERO_EXTRA_COUNT + 1))
            ;;
        scarf=*)
            WW_HERO_SCARF="${argument#scarf=}"
            WW_HERO_EXTRA+=("$argument")
            WW_HERO_EXTRA_COUNT=$((WW_HERO_EXTRA_COUNT + 1))
            ;;
        goggles=*)
            WW_HERO_GOGGLES="${argument#goggles=}"
            WW_HERO_EXTRA+=("$argument")
            WW_HERO_EXTRA_COUNT=$((WW_HERO_EXTRA_COUNT + 1))
            ;;
        *) WW_HERO_EXTRA+=("$argument"); WW_HERO_EXTRA_COUNT=$((WW_HERO_EXTRA_COUNT + 1)) ;;
    esac
done

case "$WW_HERO_MOTION" in
    "") ;;
    run)
        [ "$WW_HERO_VIEWS_SET" -ne 0 ] || WW_HERO_VIEWS="front side chase"
        [ "$WW_HERO_ORIENTATIONS_SET" -ne 0 ] || WW_HERO_ORIENTATIONS="landscape"
        [ "$WW_HERO_RENDERS_SET" -ne 0 ] || WW_HERO_RENDERS="beauty silhouette"
        ;;
    *) echo "run_hero_capture.sh: motion must be run." >&2; exit 2 ;;
esac
case "$WW_HERO_FPS" in
    30|60) ;;
    *) echo "run_hero_capture.sh: fps must be 30 or 60." >&2; exit 2 ;;
esac
if ! LC_ALL=C awk -v value="$WW_HERO_SECONDS" 'BEGIN {
    exit !(value ~ /^[0-9]+([.][0-9]+)?$/ && value >= 0.1 && value <= 10)
}'; then
    echo "run_hero_capture.sh: seconds must be between 0.1 and 10." >&2
    exit 2
fi
WW_HERO_FRAME_COUNT="$(LC_ALL=C awk -v duration="$WW_HERO_SECONDS" -v fps="$WW_HERO_FPS" \
    'BEGIN { printf "%d", int(duration * fps + 0.5) }')"
if [ -z "${WW_HERO_VIEWS//[[:space:]]/}" ] \
    || [ -z "${WW_HERO_ORIENTATIONS//[[:space:]]/}" ] \
    || [ -z "${WW_HERO_RENDERS//[[:space:]]/}" ]; then
    echo "run_hero_capture.sh: matrix filters must not be empty." >&2
    exit 2
fi
for WW_HERO_RENDER in $WW_HERO_RENDERS; do
    case "$WW_HERO_RENDER" in
        beauty|silhouette) ;;
        *) echo "run_hero_capture.sh: invalid render: $WW_HERO_RENDER" >&2; exit 2 ;;
    esac
done

for WW_HERO_VIEW in $WW_HERO_VIEWS; do
    case "$WW_HERO_VIEW" in
        close|front|threequarter|side|chase|rear_chase) ;;
        *) echo "run_hero_capture.sh: invalid view: $WW_HERO_VIEW" >&2; exit 2 ;;
    esac
done
for WW_HERO_ORIENTATION in $WW_HERO_ORIENTATIONS; do
    case "$WW_HERO_ORIENTATION" in
        landscape|portrait) ;;
        *) echo "run_hero_capture.sh: invalid orientation: $WW_HERO_ORIENTATION" >&2; exit 2 ;;
    esac
done
mkdir -p "$WW_HERO_OUTPUT" || exit 2

WW_HERO_TMP_BASE="${TMPDIR:-/tmp}"
WW_HERO_TMP_BASE="${WW_HERO_TMP_BASE%/}"
if [ -z "$WW_HERO_TMP_BASE" ] || [ "$WW_HERO_TMP_BASE" = "/" ]; then
    WW_HERO_TMP_BASE="/tmp"
fi
WW_HERO_PROJECT="$(mktemp -d "$WW_HERO_TMP_BASE/waddle-wars-hero.XXXXXX")" || exit 2
case "$WW_HERO_PROJECT" in
    "$WW_HERO_TMP_BASE"/waddle-wars-hero.*) ;;
    *) echo "run_hero_capture.sh: unsafe temporary path: $WW_HERO_PROJECT" >&2; exit 2 ;;
esac

cleanup_hero() {
    if [ -f "$WW_HERO_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_HERO_PROJECT" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_HERO_PROJECT" in
        "$WW_HERO_TMP_BASE"/waddle-wars-hero.*) rm -rf -- "$WW_HERO_PROJECT" ;;
    esac
}
trap cleanup_hero EXIT

# Capture owns a deliberately tiny fresh-import project. Copying every global
# class made unrelated in-flight art wrappers able to block hero review before
# their GLBs were imported. Keep exact hero runtime dependencies only.
mkdir -p \
    "$WW_HERO_PROJECT/assets/art" \
    "$WW_HERO_PROJECT/assets/shaders" \
    "$WW_HERO_PROJECT/scripts/art" \
    "$WW_HERO_PROJECT/scripts/characters" \
    "$WW_HERO_PROJECT/scripts/progression" \
    "$WW_HERO_PROJECT/scripts/shaders" \
    "$WW_HERO_PROJECT/tests" || exit 2
cp -R "$WW_HERO_ROOT/assets/art/characters" "$WW_HERO_PROJECT/assets/art/characters" || exit 2
cp "$WW_HERO_ROOT/assets/shaders/penguin.gdshader" "$WW_HERO_PROJECT/assets/shaders/" || exit 2
cp "$WW_HERO_ROOT/scripts/art/character_look.gd" "$WW_HERO_PROJECT/scripts/art/" || exit 2
cp "$WW_HERO_ROOT/scripts/characters/hero_penguin_rig.gd" \
    "$WW_HERO_ROOT/scripts/characters/penguin_visual.gd" \
    "$WW_HERO_PROJECT/scripts/characters/" || exit 2
cp "$WW_HERO_ROOT/scripts/progression/cosmetics_db.gd" \
    "$WW_HERO_PROJECT/scripts/progression/" || exit 2
cp "$WW_HERO_ROOT/scripts/shaders/hero_penguin_v1.gdshader" \
    "$WW_HERO_PROJECT/scripts/shaders/" || exit 2
cp "$WW_HERO_ROOT/tests/hero_penguin_capture.gd" \
    "$WW_HERO_ROOT/tests/hero_penguin_capture.tscn" \
    "$WW_HERO_ROOT/tests/test_user_data_cleaner.gd" \
    "$WW_HERO_PROJECT/tests/" || exit 2
WW_HERO_RUN_ID="waddle-wars-hero-$$-${RANDOM:-0}"
awk -v run_id="$WW_HERO_RUN_ID" 'BEGIN {
    print "; Engine configuration file."
    print "config_version=5"
    print ""
    print "[application]"
    print "config/name=\"Waddle Wars Hero Capture\""
    print "run/main_scene=\"res://tests/hero_penguin_capture.tscn\""
    print "config/features=PackedStringArray(\"4.7\", \"GL Compatibility\")"
    print "config/use_custom_user_dir=true"
    printf "config/custom_user_dir_name=\"%s\"\n", run_id
    print ""
    print "[display]"
    print "window/size/viewport_width=1280"
    print "window/size/viewport_height=720"
    print "window/stretch/mode=\"canvas_items\""
    print ""
    print "[rendering]"
    print "renderer/rendering_method=\"gl_compatibility\""
    print "renderer/rendering_method.mobile=\"gl_compatibility\""
}' > "$WW_HERO_PROJECT/project.godot" || exit 2

"$GODOT_BIN" --headless --import --path "$WW_HERO_PROJECT" \
    --log-file "$WW_HERO_PROJECT/import.log" \
    >"$WW_HERO_PROJECT/import.stdout" 2>"$WW_HERO_PROJECT/import.stderr" || exit 2
if grep -Eq 'SCRIPT ERROR:|Parse Error:|(^|[[:space:]])ERROR:|Failed loading resource' "$WW_HERO_PROJECT/import.log"; then
    sed -n '1,220p' "$WW_HERO_PROJECT/import.log" >&2
    exit 2
fi
if [ "$WW_HERO_VERIFY_ONLY" -eq 1 ]; then
    echo "HERO CAPTURE IMPORT: PASS (headless; no images captured)"
    exit 0
fi

for WW_HERO_RENDER in $WW_HERO_RENDERS; do
    WW_HERO_SUFFIX=""
    if [ "$WW_HERO_RENDER" != "beauty" ]; then WW_HERO_SUFFIX="_${WW_HERO_RENDER}"; fi
    if [ -n "$WW_HERO_HAT" ]; then WW_HERO_SUFFIX="${WW_HERO_SUFFIX}_${WW_HERO_HAT}"; fi
    if [ -n "$WW_HERO_SCARF" ]; then WW_HERO_SUFFIX="${WW_HERO_SUFFIX}_${WW_HERO_SCARF}"; fi
    if [ -n "$WW_HERO_GOGGLES" ]; then WW_HERO_SUFFIX="${WW_HERO_SUFFIX}_${WW_HERO_GOGGLES}"; fi
    for WW_HERO_ORIENTATION in $WW_HERO_ORIENTATIONS; do
      for WW_HERO_VIEW in $WW_HERO_VIEWS; do
        WW_HERO_LOG="$WW_HERO_PROJECT/${WW_HERO_RENDER}_${WW_HERO_ORIENTATION}_${WW_HERO_VIEW}.log"
        WW_HERO_CAPTURE_ARGS=("output=$WW_HERO_OUTPUT" "view=$WW_HERO_VIEW"
            "orientation=$WW_HERO_ORIENTATION" "render=$WW_HERO_RENDER"
            "motion=$WW_HERO_MOTION" "fps=$WW_HERO_FPS" "seconds=$WW_HERO_SECONDS")
        if [ "$WW_HERO_EXTRA_COUNT" -gt 0 ]; then
            WW_HERO_CAPTURE_ARGS+=("${WW_HERO_EXTRA[@]}")
        fi
        "$GODOT_BIN" --path "$WW_HERO_PROJECT" --rendering-method gl_compatibility \
            --quit-after 18000 --log-file "$WW_HERO_LOG" res://tests/hero_penguin_capture.tscn -- \
            "${WW_HERO_CAPTURE_ARGS[@]}" || exit 2
        if grep -Eq 'SCRIPT ERROR:|Parse Error:|(^|[[:space:]])ERROR:|Failed loading resource' "$WW_HERO_LOG"; then
            sed -n '1,220p' "$WW_HERO_LOG" >&2
            exit 2
        fi
        if [ -n "$WW_HERO_MOTION" ]; then
            WW_HERO_SEQUENCE="$WW_HERO_OUTPUT/hero_penguin_${WW_HERO_MOTION}_${WW_HERO_VIEW}_${WW_HERO_ORIENTATION}${WW_HERO_SUFFIX}_${WW_HERO_FPS}fps"
            for WW_HERO_ARTIFACT in contact_sheet.png timeline.json; do
                if [ ! -s "$WW_HERO_SEQUENCE/$WW_HERO_ARTIFACT" ]; then
                    echo "run_hero_capture.sh: missing motion artifact: $WW_HERO_SEQUENCE/$WW_HERO_ARTIFACT" >&2
                    exit 2
                fi
            done
            WW_HERO_INDEX=0
            while [ "$WW_HERO_INDEX" -lt "$WW_HERO_FRAME_COUNT" ]; do
                WW_HERO_FRAME="$WW_HERO_SEQUENCE/$(printf 'frame_%04d.png' "$WW_HERO_INDEX")"
                if [ ! -s "$WW_HERO_FRAME" ]; then
                    echo "run_hero_capture.sh: missing motion frame: $WW_HERO_FRAME" >&2
                    exit 2
                fi
                WW_HERO_INDEX=$((WW_HERO_INDEX + 1))
            done
        else
            for WW_HERO_POSE in neutral run jump slide hit celebrate; do
                WW_HERO_FRAME="$WW_HERO_OUTPUT/hero_penguin_${WW_HERO_POSE}_${WW_HERO_VIEW}_${WW_HERO_ORIENTATION}${WW_HERO_SUFFIX}.png"
                if [ ! -s "$WW_HERO_FRAME" ]; then
                    echo "run_hero_capture.sh: missing frame: $WW_HERO_FRAME" >&2
                    exit 2
                fi
            done
        fi
      done
    done
done
echo "HERO MATRIX: PASS $WW_HERO_OUTPUT"
