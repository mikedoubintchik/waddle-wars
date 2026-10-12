#!/usr/bin/env bash
# Isolated untimed Compatibility pixel study. Usage: bash run_dusk_warmup_raster.sh fresh_label
set -euo pipefail
cd "$(dirname "$0")"
WW_RASTER_ROOT="$PWD"
WW_RASTER_LABEL="${1:-}"
if [ "$#" -ne 1 ] || [[ ! "$WW_RASTER_LABEL" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$ ]]; then
    echo "Usage: bash run_dusk_warmup_raster.sh fresh_label (letters, digits, _, -; <=80 chars)" >&2
    exit 2
fi
WW_RASTER_OUT="$WW_RASTER_ROOT/qa_shots/runner/$WW_RASTER_LABEL"
if [ -e "$WW_RASTER_OUT" ]; then
    echo "Refusing to overwrite existing output: $WW_RASTER_OUT" >&2
    exit 2
fi
WW_RASTER_GODOT="${GODOT:-godot}"
if ! command -v "$WW_RASTER_GODOT" >/dev/null 2>&1; then
    echo "Godot not found; set GODOT to its executable path." >&2
    exit 2
fi
WW_RASTER_TMP="$(mktemp -d /tmp/waddle-dusk-raster.XXXXXX)"
WW_RASTER_ID="waddle-dusk-raster-${WW_RASTER_TMP##*.}"
mkdir -p "$WW_RASTER_OUT/source_snapshot"
for WW_RASTER_DIR in assets data scenes scripts tests; do
    cp -R "$WW_RASTER_ROOT/$WW_RASTER_DIR" "$WW_RASTER_TMP/$WW_RASTER_DIR"
    cp -R "$WW_RASTER_TMP/$WW_RASTER_DIR" "$WW_RASTER_OUT/source_snapshot/$WW_RASTER_DIR"
done
awk -v identity="$WW_RASTER_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", identity
    }
' "$WW_RASTER_ROOT/project.godot" > "$WW_RASTER_TMP/project.godot"
cp "$WW_RASTER_TMP/project.godot" "$WW_RASTER_OUT/source_snapshot/project.godot"
echo "Isolated project retained: $WW_RASTER_TMP"
echo "Evidence: $WW_RASTER_OUT"
set +e
"$WW_RASTER_GODOT" --headless --import --path "$WW_RASTER_TMP" \
    --log-file "$WW_RASTER_OUT/import.log" > "$WW_RASTER_OUT/import.stdout" 2> "$WW_RASTER_OUT/import.stderr"
WW_RASTER_CODE=$?
set -e
if [ "$WW_RASTER_CODE" -ne 0 ] || rg -q 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_RASTER_OUT/import.log" "$WW_RASTER_OUT/import.stdout"; then
    echo "Import failed; retained logs and temporary project." >&2
    exit 2
fi
if awk 'NF && $0 != "cannot connect to daemon at tcp:5037: Connection refused" { bad=1 }
        END { exit bad ? 0 : 1 }' "$WW_RASTER_OUT/import.stderr"; then
    echo "Import stderr not clean; retained evidence." >&2
    exit 2
fi
set +e
"$WW_RASTER_GODOT" --path "$WW_RASTER_TMP" --rendering-method gl_compatibility \
    --log-file "$WW_RASTER_OUT/capture.log" res://tests/dusk_warmup_raster_test.tscn \
    -- "out=$WW_RASTER_OUT" > "$WW_RASTER_OUT/capture.stdout" 2> "$WW_RASTER_OUT/capture.stderr"
WW_RASTER_CODE=$?
set -e
if [ "$WW_RASTER_CODE" -ne 0 ] || rg -q 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_RASTER_OUT/capture.log" "$WW_RASTER_OUT/capture.stdout" "$WW_RASTER_OUT/capture.stderr"; then
    echo "Capture failed; retained all evidence." >&2
    exit 2
fi
if [ ! -f "$WW_RASTER_OUT/report.json" ] \
        || ! rg -q '"fixture_valid": true' "$WW_RASTER_OUT/report.json" \
        || ! rg -q '"complete": true' "$WW_RASTER_OUT/report.json"; then
    echo "No complete, valid fixture report; retained all evidence." >&2
    exit 2
fi
echo "Capture complete. Read fixture_valid and production_surface_coverage_pass separately in report.json."
