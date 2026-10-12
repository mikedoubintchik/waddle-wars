#!/usr/bin/env bash
# Untimed, isolated sequential runner replay. Never runs an FPS benchmark.
# Usage: ./run_runner_peak_replay.sh [out=/absolute/report.json] [reference=/absolute/reference.json]
# Optional: lod_sweep=true|false, verbose=true|false (retained shutdown details).
# radar_candidate=/absolute/directory adds a hash-bound QA-only mesh comparison.
# radar_extended=true adds both window-wall/three-quarter pairs and30fps distance sequences.
# Logs are retained beside the output even on import/runtime failure.

set -u
cd "$(dirname "$0")"
WW_REPLAY_ROOT="$PWD"
WW_REPLAY_OUT="$WW_REPLAY_ROOT/qa_shots/runner/peak_replay_20260907_01/report.json"
WW_REPLAY_REFERENCE="$WW_REPLAY_ROOT/qa_shots/runner/runner_perf_20260907_current_assets_census.json"
WW_REPLAY_LOD="lod_sweep=false"
WW_REPLAY_VERBOSE=false
WW_REPLAY_CANDIDATE=""
WW_REPLAY_EXTENDED="radar_extended=false"
for WW_REPLAY_ARG in "$@"; do
    case "$WW_REPLAY_ARG" in
        out=*) WW_REPLAY_OUT="${WW_REPLAY_ARG#out=}" ;;
        reference=*) WW_REPLAY_REFERENCE="${WW_REPLAY_ARG#reference=}" ;;
        lod_sweep=true|lod_sweep=false) WW_REPLAY_LOD="$WW_REPLAY_ARG" ;;
        verbose=true|verbose=false) WW_REPLAY_VERBOSE="${WW_REPLAY_ARG#verbose=}" ;;
        radar_candidate=*) WW_REPLAY_CANDIDATE="${WW_REPLAY_ARG#radar_candidate=}" ;;
        radar_extended=true|radar_extended=false) WW_REPLAY_EXTENDED="$WW_REPLAY_ARG" ;;
        *) echo "Unknown replay argument: $WW_REPLAY_ARG" >&2; exit 2 ;;
    esac
done
if [ "$WW_REPLAY_EXTENDED" = radar_extended=true ] && [ -z "$WW_REPLAY_CANDIDATE" ]; then
    echo "Extended radar QA requires a candidate directory" >&2; exit 2
fi
case "$WW_REPLAY_OUT" in /*.json) ;; *) echo "Output must be an absolute .json path" >&2; exit 2 ;; esac
if [ ! -f "$WW_REPLAY_REFERENCE" ]; then
    echo "Reference report missing: $WW_REPLAY_REFERENCE" >&2
    exit 2
fi
if [ -n "$WW_REPLAY_CANDIDATE" ]; then
    case "$WW_REPLAY_CANDIDATE" in /*) ;; *) echo "Candidate directory must be absolute" >&2; exit 2 ;; esac
    WW_REPLAY_CANDIDATE_GLB="$WW_REPLAY_CANDIDATE/runner_day_radar_landmark_lod1_candidate.glb"
    WW_REPLAY_BINDING="$WW_REPLAY_CANDIDATE/build_report.json"
    WW_REPLAY_AUTHORING="$WW_REPLAY_CANDIDATE/authoring_report.json"
    for WW_REPLAY_FILE in "$WW_REPLAY_CANDIDATE_GLB" "$WW_REPLAY_BINDING" "$WW_REPLAY_AUTHORING"; do
        if [ ! -f "$WW_REPLAY_FILE" ]; then echo "Candidate input missing: $WW_REPLAY_FILE" >&2; exit 2; fi
    done
    if ! jq -e '.qa_only == true and .production_ready == false and .runtime_changed == false
        and .visual_quality_approved == false and .independent_rebuild_byte_identical == true
        and (.input_sha256 | type == "object" and length > 0)' "$WW_REPLAY_BINDING" >/dev/null; then
        echo "Candidate source binding is not an unapproved deterministic QA artifact" >&2; exit 2
    fi
    WW_REPLAY_CANDIDATE_HASH="$(shasum -a 256 "$WW_REPLAY_CANDIDATE_GLB" | awk '{print $1}')"
    if [ "$WW_REPLAY_CANDIDATE_HASH" != "$(jq -r '.candidate_sha256' "$WW_REPLAY_BINDING")" ]; then
        echo "Candidate byte hash differs from binding" >&2; exit 2
    fi
    # Verify construction inputs against this checkout before copying anything.
    # Reject path traversal or symlink inputs rather than expanding their scope.
    while IFS=$'\t' read -r WW_REPLAY_INPUT WW_REPLAY_HASH; do
        case "$WW_REPLAY_INPUT" in ""|/*|../*|*/../*|*/..|./*|*/./*|*/.)
            echo "Unsafe candidate source binding path: $WW_REPLAY_INPUT" >&2; exit 2 ;;
        esac
        if [ ! -f "$WW_REPLAY_ROOT/$WW_REPLAY_INPUT" ] || [ -L "$WW_REPLAY_ROOT/$WW_REPLAY_INPUT" ] \
            || [ "$(shasum -a 256 "$WW_REPLAY_ROOT/$WW_REPLAY_INPUT" | awk '{print $1}')" != "$WW_REPLAY_HASH" ]; then
            echo "Candidate source binding changed: $WW_REPLAY_INPUT" >&2; exit 2
        fi
    done < <(jq -r '.input_sha256 | to_entries[] | [.key,.value] | @tsv' "$WW_REPLAY_BINDING")
fi
WW_REPLAY_EVIDENCE="$(dirname "$WW_REPLAY_OUT")"
if [ -e "$WW_REPLAY_OUT" ] || [ -e "$WW_REPLAY_EVIDENCE/replay.stdout" ]; then
    echo "Use a fresh replay output path; refusing to overwrite evidence" >&2; exit 2
fi
mkdir -p "$WW_REPLAY_EVIDENCE" || exit 2
GODOT_BIN="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    echo "Godot unavailable; set GODOT to executable path" >&2
    exit 2
fi
WW_REPLAY_TMP_BASE="${TMPDIR:-/tmp}"
WW_REPLAY_TMP_BASE="${WW_REPLAY_TMP_BASE%/}"
WW_REPLAY_PROJECT="$(mktemp -d "$WW_REPLAY_TMP_BASE/waddle-wars-peak-replay.XXXXXX")" || exit 2
WW_REPLAY_ID="waddle-wars-tests-peak-replay-$$-${RANDOM:-0}"

cleanup_replay_workspace() {
    if [ -f "$WW_REPLAY_PROJECT/tests/test_user_data_cleaner.gd" ]; then
        "$GODOT_BIN" --headless --path "$WW_REPLAY_PROJECT" \
            --log-file "$WW_REPLAY_PROJECT/clean.log" \
            --script res://tests/test_user_data_cleaner.gd >/dev/null 2>&1 || true
    fi
    case "$WW_REPLAY_PROJECT" in
        "$WW_REPLAY_TMP_BASE"/waddle-wars-peak-replay.*) rm -rf -- "$WW_REPLAY_PROJECT" ;;
        *) echo "Refusing unexpected cleanup target: $WW_REPLAY_PROJECT" >&2 ;;
    esac
}
trap cleanup_replay_workspace EXIT
for WW_REPLAY_DIR in assets data scenes scripts tests; do
    cp -R "$WW_REPLAY_ROOT/$WW_REPLAY_DIR" "$WW_REPLAY_PROJECT/$WW_REPLAY_DIR" || exit 2
done
WW_REPLAY_USER_ARGS=("reference=$WW_REPLAY_REFERENCE" "out=$WW_REPLAY_OUT" "$WW_REPLAY_LOD" "$WW_REPLAY_EXTENDED")
if [ -n "$WW_REPLAY_CANDIDATE" ]; then
    mkdir -p "$WW_REPLAY_PROJECT/qa_candidate" || exit 2
    cp "$WW_REPLAY_CANDIDATE_GLB" "$WW_REPLAY_BINDING" "$WW_REPLAY_AUTHORING" "$WW_REPLAY_PROJECT/qa_candidate/" || exit 2
    cp "$WW_REPLAY_ROOT/tests/fixtures/runner_peak_replay/radar_candidate.glb.import.template" \
        "$WW_REPLAY_PROJECT/qa_candidate/runner_day_radar_landmark_lod1_candidate.glb.import" || exit 2
    cp "$WW_REPLAY_BINDING" "$WW_REPLAY_EVIDENCE/candidate_build_report.json" || exit 2
    cp "$WW_REPLAY_AUTHORING" "$WW_REPLAY_EVIDENCE/candidate_authoring_report.json" || exit 2
    WW_REPLAY_USER_ARGS+=("radar_candidate=res://qa_candidate/runner_day_radar_landmark_lod1_candidate.glb"
        "radar_binding=res://qa_candidate/build_report.json" "radar_authoring=res://qa_candidate/authoring_report.json")
fi
awk -v ww_replay_id="$WW_REPLAY_ID" '
    /^config\/use_custom_user_dir=/ { next }
    /^config\/custom_user_dir_name=/ { next }
    { print }
    /^config\/name=/ {
        print "config/use_custom_user_dir=true"
        printf "config/custom_user_dir_name=\"%s\"\n", ww_replay_id
    }
' "$WW_REPLAY_ROOT/project.godot" > "$WW_REPLAY_PROJECT/project.godot" || exit 2

"$GODOT_BIN" --headless --import --path "$WW_REPLAY_PROJECT" \
    --log-file "$WW_REPLAY_EVIDENCE/import.log" \
    >"$WW_REPLAY_EVIDENCE/import.stdout" 2>"$WW_REPLAY_EVIDENCE/import.stderr"
WW_REPLAY_CODE=$?
if [ "$WW_REPLAY_CODE" -ne 0 ] || grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_REPLAY_EVIDENCE/import.log" "$WW_REPLAY_EVIDENCE/import.stdout" "$WW_REPLAY_EVIDENCE/import.stderr"; then
    echo "Replay import failed; evidence: $WW_REPLAY_EVIDENCE" >&2
    exit 2
fi
if awk 'NF && $0 != "cannot connect to daemon at tcp:5037: Connection refused" { bad = 1 }
    END { exit bad ? 0 : 1 }' "$WW_REPLAY_EVIDENCE/import.stderr"; then
    echo "Unexpected import stderr; evidence: $WW_REPLAY_EVIDENCE" >&2
    exit 2
fi

# Contract checks run before the window, under the same isolated identity.
"$GODOT_BIN" --headless --path "$WW_REPLAY_PROJECT" \
    --log-file "$WW_REPLAY_EVIDENCE/contract.log" \
    --quit-after 10 res://tests/runner_peak_replay_test.tscn \
    >"$WW_REPLAY_EVIDENCE/contract.stdout" 2>"$WW_REPLAY_EVIDENCE/contract.stderr"
WW_REPLAY_CODE=$?
if [ "$WW_REPLAY_CODE" -ne 0 ] || [ -s "$WW_REPLAY_EVIDENCE/contract.stderr" ] \
        || grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_REPLAY_EVIDENCE/contract.log" "$WW_REPLAY_EVIDENCE/contract.stdout"; then
    echo "Replay contract failed; evidence: $WW_REPLAY_EVIDENCE" >&2
    exit 2
fi
echo "Isolated UNTIMED replay project: $WW_REPLAY_PROJECT"
WW_REPLAY_RENDER_ARGS=(--path "$WW_REPLAY_PROJECT" --rendering-method gl_compatibility)
if [ "$WW_REPLAY_VERBOSE" = true ]; then WW_REPLAY_RENDER_ARGS+=(--verbose); fi
"$GODOT_BIN" "${WW_REPLAY_RENDER_ARGS[@]}" \
    --log-file "$WW_REPLAY_EVIDENCE/replay.log" \
    res://tests/runner_peak_replay.tscn -- "${WW_REPLAY_USER_ARGS[@]}" \
    >"$WW_REPLAY_EVIDENCE/replay.stdout" 2>"$WW_REPLAY_EVIDENCE/replay.stderr" &
WW_REPLAY_PID=$!
WW_REPLAY_TIMEOUT=120
if [ "$WW_REPLAY_EXTENDED" = radar_extended=true ]; then WW_REPLAY_TIMEOUT=220; fi
# Own child only. External watchdog also catches macOS's fully occluded window
# suspension, where an in-engine timeout would not receive process frames.
(
    for WW_REPLAY_SECOND in $(seq 1 "$WW_REPLAY_TIMEOUT"); do
        sleep 1
        kill -0 "$WW_REPLAY_PID" 2>/dev/null || exit 0
    done
    echo "Untimed replay exceeded external${WW_REPLAY_TIMEOUT}s timeout" >> "$WW_REPLAY_EVIDENCE/watchdog.log"
    kill -TERM "$WW_REPLAY_PID" 2>/dev/null || true
) &
WW_REPLAY_WATCHDOG=$!
wait "$WW_REPLAY_PID"
WW_REPLAY_CODE=$?
kill -TERM "$WW_REPLAY_WATCHDOG" 2>/dev/null || true
wait "$WW_REPLAY_WATCHDOG" 2>/dev/null || true
if [ -s "$WW_REPLAY_EVIDENCE/replay.stderr" ] \
        || grep -Eq 'SCRIPT ERROR:|(^|[[:space:]])ERROR:|Failed loading resource' \
        "$WW_REPLAY_EVIDENCE/replay.log" "$WW_REPLAY_EVIDENCE/replay.stdout"; then
    echo "Replay wrote stderr or runtime errors; retained all evidence: $WW_REPLAY_EVIDENCE" >&2
    WW_REPLAY_CODE=2
fi
echo "Untimed replay exit=$WW_REPLAY_CODE; evidence: $WW_REPLAY_EVIDENCE"
exit "$WW_REPLAY_CODE"
