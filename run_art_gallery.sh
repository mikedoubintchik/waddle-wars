#!/usr/bin/env bash
# Isolated runtime-art contact sheet / 3D gallery capture.
#   ./run_art_gallery.sh group=course_posters out=/absolute/path/posters.png

set -u
cd "$(dirname "$0")"
WW_GALLERY_ROOT="$PWD"
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
    echo "run_art_gallery.sh: no Godot executable found; set GODOT=/path/to/godot." >&2
    exit 2
fi

WW_GALLERY_TMP_BASE="${TMPDIR:-/tmp}"
WW_GALLERY_TMP_BASE="${WW_GALLERY_TMP_BASE%/}"
if [ -z "$WW_GALLERY_TMP_BASE" ] || [ "$WW_GALLERY_TMP_BASE" = "/" ]; then
    WW_GALLERY_TMP_BASE="/tmp"
fi
if ! WW_GALLERY_PROJECT="$(mktemp -d "$WW_GALLERY_TMP_BASE/waddle-wars-gallery.XXXXXX")"; then
    echo "run_art_gallery.sh: could not create isolated project" >&2
    exit 2
fi
case "$WW_GALLERY_PROJECT" in
    "$WW_GALLERY_TMP_BASE"/waddle-wars-gallery.*) ;;
    *) echo "run_art_gallery.sh: unsafe temporary path: $WW_GALLERY_PROJECT" >&2; exit 2 ;;
esac

cleanup_gallery() {
    if [ -f "$WW_GALLERY_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_GALLERY_PROJECT" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_GALLERY_PROJECT" in
        "$WW_GALLERY_TMP_BASE"/waddle-wars-gallery.*) rm -rf -- "$WW_GALLERY_PROJECT" ;;
    esac
}
trap cleanup_gallery EXIT

for WW_GALLERY_DIR in assets data scenes scripts tests; do
    if ! cp -R "$WW_GALLERY_ROOT/$WW_GALLERY_DIR" "$WW_GALLERY_PROJECT/$WW_GALLERY_DIR"; then
        echo "run_art_gallery.sh: snapshot failed for $WW_GALLERY_DIR" >&2
        exit 2
    fi
done
WW_GALLERY_RUN_ID="waddle-wars-gallery-$$-${RANDOM:-0}"
awk -v run_id="$WW_GALLERY_RUN_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", run_id
    }
' "$WW_GALLERY_ROOT/project.godot" > "$WW_GALLERY_PROJECT/project.godot" || exit 2

"$GODOT_BIN" --headless --import --path "$WW_GALLERY_PROJECT" \
    --log-file "$WW_GALLERY_PROJECT/import.log" \
    >"$WW_GALLERY_PROJECT/import.stdout" 2>"$WW_GALLERY_PROJECT/import.stderr" || exit 2
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' \
        "$WW_GALLERY_PROJECT/import.log"; then
    sed -n '1,220p' "$WW_GALLERY_PROJECT/import.log" >&2
    exit 2
fi

"$GODOT_BIN" --path "$WW_GALLERY_PROJECT" --rendering-method gl_compatibility \
    --log-file "$WW_GALLERY_PROJECT/gallery.log" \
    res://tests/art_gallery.tscn -- "$@"
WW_GALLERY_CODE=$?
if grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed loading resource' \
        "$WW_GALLERY_PROJECT/gallery.log"; then
    sed -n '1,220p' "$WW_GALLERY_PROJECT/gallery.log" >&2
    [ "$WW_GALLERY_CODE" -ne 0 ] || WW_GALLERY_CODE=1
fi
exit "$WW_GALLERY_CODE"
