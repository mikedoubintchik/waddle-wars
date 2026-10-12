#!/usr/bin/env bash
# Isolated normal-import atlas proof; no live scene, autoload, or player saves.
# Usage: ./run_hero_atlas_capture.sh CANDIDATE_LOD_DIR OUTPUT_LABEL \
#   [view=threequarter] [fps=60] [renderer=gl_compatibility] [mode=atlas] [lighting=legacy]
#   [normal-strength=1] (atlas only unless strength=1)
# OUTPUT_LABEL is a new child of qa_shots/hero. Logs/temp retained on failure.
set -u
WW_ROOT="$(cd "$(dirname "$0")" && pwd -P)" || exit 2
fail() { echo "[hero-atlas] FAIL $*" >&2; exit 2; }
[ "$#" -ge 2 ] || fail "usage: CANDIDATE_LOD_DIR OUTPUT_LABEL [view=.. fps=.. renderer=.. mode=.. lighting=.. normal-strength=..]"
WW_CANDIDATE="$1"; WW_LABEL="$2"; shift 2
WW_VIEW=threequarter; WW_FPS=60; WW_RENDERER=gl_compatibility; WW_MODE=atlas; WW_LIGHTING=legacy
WW_NORMAL_STRENGTH=1
for WW_ARG in "$@"; do
    case "$WW_ARG" in
        view=*) WW_VIEW="${WW_ARG#view=}" ;;
        fps=*) WW_FPS="${WW_ARG#fps=}" ;;
        renderer=*) WW_RENDERER="${WW_ARG#renderer=}" ;;
        mode=*) WW_MODE="${WW_ARG#mode=}" ;;
        lighting=*) WW_LIGHTING="${WW_ARG#lighting=}" ;;
        normal-strength=*) WW_NORMAL_STRENGTH="${WW_ARG#normal-strength=}" ;;
        *) fail "unknown option: $WW_ARG" ;;
    esac
done
[[ "$WW_LABEL" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$ ]] || fail "label must be 1-80 letters/digits/underscore/hyphen, beginning with letter/digit"
case "$WW_VIEW" in front|threequarter|side|chase) ;; *) fail "invalid view: $WW_VIEW" ;; esac
case "$WW_FPS" in 30|60) ;; *) fail "fps must be 30 or 60" ;; esac
case "$WW_RENDERER" in gl_compatibility|mobile) ;; *) fail "renderer must be gl_compatibility or mobile" ;; esac
case "$WW_MODE" in imported|atlas) ;; *) fail "mode must be imported or atlas" ;; esac
case "$WW_LIGHTING" in legacy|soft-review|balanced-review) ;; *) fail "lighting must be legacy, soft-review, or balanced-review" ;; esac
case "$WW_NORMAL_STRENGTH" in 0|0.35|1) ;; *) fail "normal-strength must be 0, 0.35, or 1" ;; esac
[ "$WW_MODE" = atlas ] || [ "$WW_NORMAL_STRENGTH" = 1 ] || fail "normal-strength other than 1 requires mode=atlas"
[ -d "$WW_CANDIDATE" ] || fail "candidate directory missing: $WW_CANDIDATE"
WW_CANDIDATE="$(cd -- "$WW_CANDIDATE" && pwd -P)" || fail "cannot resolve candidate"
WW_GODOT="$(command -v "${GODOT:-godot}")" || fail "Godot not found; set GODOT=/absolute/path"
WW_FIXTURES="$WW_ROOT/tests/fixtures/hero_v12_atlas_capture"
for WW_FILE in hero_penguin_v12_atlas.glb atlas_binding.json \
    hero_penguin_v12_atlas_albedo.png hero_penguin_v12_atlas_normal.png \
    hero_penguin_v12_atlas_orm.png hero_penguin_v12_atlas_masks.png; do
    [ -f "$WW_CANDIDATE/$WW_FILE" ] || fail "incomplete candidate: $WW_FILE"
done
python3 - "$WW_CANDIDATE" <<'PY' || fail "candidate binding failed preflight"
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
binding = json.loads((root / "atlas_binding.json").read_text())
if binding.get("schema_version") != 1 or binding.get("uv_contract") != "unique-nonoverlapping-v1":
    raise SystemExit("Invalid atlas binding contract")
expected = {"hero_penguin_v12_atlas.glb": binding.get("glb_sha256")}
for kind in ("albedo", "normal", "orm", "masks"):
    expected[f"hero_penguin_v12_atlas_{kind}.png"] = binding.get("textures", {}).get(kind)
for name, digest in expected.items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f"Binding hash mismatch: {name}")
PY
[ ! -L "$WW_ROOT/qa_shots" ] && [ ! -L "$WW_ROOT/qa_shots/hero" ] || fail "output parents must not be symlinks"
mkdir -p "$WW_ROOT/qa_shots/hero" || fail "cannot create QA parent"
WW_OUT="$WW_ROOT/qa_shots/hero/$WW_LABEL"
[ ! -e "$WW_OUT" ] && [ ! -L "$WW_OUT" ] || fail "output already exists; choose a fresh label"
mkdir "$WW_OUT" || fail "cannot reserve fresh output"
WW_PROJECT="$(mktemp -d /tmp/waddle-v12-candidate-atlas.XXXXXX)" || fail "cannot create isolated project"
echo "[hero-atlas] output=$WW_OUT temporary_project=$WW_PROJECT"
trap 'echo "[hero-atlas] logs=$WW_OUT retained_project=$WW_PROJECT"' EXIT
mkdir "$WW_PROJECT/atlas" || fail "cannot create isolated resource directory"
cp "$WW_FIXTURES/project.godot.template" "$WW_PROJECT/project.godot" || fail "cannot copy project fixture"
cp "$WW_ROOT/tests/hero_v12_candidate_capture.gd" "$WW_PROJECT/" || fail "capture harness missing"
cp "$WW_ROOT/tests/shaders/hero_v12_atlas_review.gdshader" "$WW_PROJECT/" || fail "QA shader missing"
cp "$WW_CANDIDATE/hero_penguin_v12_atlas.glb" "$WW_CANDIDATE/atlas_binding.json" "$WW_PROJECT/atlas/" || fail "cannot copy candidate"
for WW_KIND in albedo normal orm masks; do
    WW_FILE="hero_penguin_v12_atlas_$WW_KIND.png"
    cp "$WW_CANDIDATE/$WW_FILE" "$WW_PROJECT/atlas/$WW_FILE" || fail "cannot copy $WW_KIND"
    WW_IMPORT=data_texture.import
    [ "$WW_KIND" != normal ] || WW_IMPORT=normal_texture.import
    cp "$WW_FIXTURES/$WW_IMPORT" "$WW_PROJECT/atlas/$WW_FILE.import" || fail "cannot seed $WW_KIND import"
done
run_logged() {
    local stage="$1" result=0 pid watchdog
    shift
    "$WW_GODOT" --log-file "$WW_OUT/$stage.engine.log" "$@" \
        >"$WW_OUT/$stage.stdout.log" 2>"$WW_OUT/$stage.stderr.log" &
    pid=$!
    (sleep 180 & timer=$!; trap 'kill "$timer" 2>/dev/null || true' EXIT
        trap 'exit 0' TERM INT; wait "$timer" && kill -TERM "$pid" 2>/dev/null) &
    watchdog=$!
    wait "$pid" || result=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    [ "$result" -eq 0 ] || fail "$stage exited $result; logs retained"
    [ -f "$WW_OUT/$stage.engine.log" ] || fail "$stage did not produce engine log"
    if rg -ni 'SCRIPT ERROR:|SHADER ERROR:|(^|[[:space:]])ERROR:|Failed loading resource|COMPILATION FAILED|Shader compilation failed' \
        "$WW_OUT/$stage.engine.log" "$WW_OUT/$stage.stdout.log" "$WW_OUT/$stage.stderr.log" \
        >"$WW_OUT/$stage.errors.log"; then
        fail "$stage reported engine errors despite exit 0"
    fi
}
run_logged import --headless --editor --import --path "$WW_PROJECT" --rendering-method "$WW_RENDERER"
WW_ARGS=(--glb="$WW_CANDIDATE/hero_penguin_v12_atlas.glb" --out="$WW_OUT/frames" \
    --imported-res=res://atlas/hero_penguin_v12_atlas.glb --view="$WW_VIEW" --fps="$WW_FPS" --seconds=0.8 \
    --lighting="$WW_LIGHTING" --normal-strength="$WW_NORMAL_STRENGTH")
[ "$WW_MODE" != atlas ] || WW_ARGS+=(--atlas-res=res://atlas)
run_logged capture --path "$WW_PROJECT" --rendering-method "$WW_RENDERER" --audio-driver Dummy \
    --always-on-top --script res://hero_v12_candidate_capture.gd -- "${WW_ARGS[@]}"
python3 - "$WW_OUT/frames/capture_audit.json" "$WW_MODE" "$WW_FPS" "$WW_RENDERER" "$WW_LIGHTING" "$WW_NORMAL_STRENGTH" <<'PY' || fail "capture audit failed"
import json, pathlib, sys
audit = json.loads(pathlib.Path(sys.argv[1]).read_text())
if audit.get("import_path") != "PackedScene" or audit.get("renderer") != sys.argv[4]:
    raise SystemExit("Normal resource import / requested renderer not verified")
if audit.get("lighting_profile") != sys.argv[5]:
    raise SystemExit("Requested lighting profile not verified")
if not audit.get("structural_pass") or not audit.get("constant_sole_fit_pass"):
    raise SystemExit("Candidate structural/contact checks failed")
if len(audit.get("rendered_frames", [])) != round(0.8 * int(sys.argv[3])):
    raise SystemExit("Rendered frame sequence incomplete")
if bool(audit.get("material_override")) != (sys.argv[2] == "atlas"):
    raise SystemExit("Material mode did not match request")
if sys.argv[2] == "atlas":
    if abs(audit.get("atlas_review", {}).get("normal_strength", -1) - float(sys.argv[6])) > 0.000001:
        raise SystemExit("Requested diagnostic normal strength not verified")
    textures = audit.get("atlas_review", {}).get("textures", [])
    if len(textures) != 4 or any(not t.get("compressed") or t.get("mipmap_count", 0) <= 0 or t.get("stored_payload_bytes", 0) <= 0 for t in textures):
        raise SystemExit("Expected four genuinely compressed, mipmapped imported maps")
    for texture in textures:
        print(f"[hero-atlas] {texture['kind']} format={texture['stored_format']} mips={texture['mipmap_count']} stored_bytes={texture['stored_payload_bytes']}")
print("[hero-atlas] PASS normal-import capture; stored payload is not driver VRAM or an FPS claim")
PY
