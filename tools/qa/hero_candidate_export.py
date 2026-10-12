"""Install canonical material fixture in a copied Chrome QA export only."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

MODEL = "assets/art/characters/hero_penguin_v1.glb"
WRAPPER = "assets/art/characters/hero_penguin_v1.tscn"
CONTROLLER = "scripts/characters/hero_penguin_rig.gd"
HELPER = "tools/qa/hero_candidate_browser.gd"
RESOURCES = (
    "assets/art/characters/hero_penguin_v1_material.tres",
    "scripts/shaders/hero_penguin_v1.gdshader",
    *(f"assets/art/characters/textures/hero_penguin_v1_{kind}.png" for kind in ("albedo", "normal", "orm")),
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def review_controls() -> str:
    """Optional candidate-only review UI; caller inserts before </body>."""
    return '''
<style>
#ww-candidate-review { position:fixed; z-index:2147483646; left:50%; bottom:max(8px,env(safe-area-inset-bottom)); transform:translateX(-50%); width:min(390px,calc(100vw - 16px)); box-sizing:border-box; padding:10px 12px; border:1px solid #7298a3; border-radius:14px; background:rgba(12,29,42,.96); color:#f1f8fa; box-shadow:0 3px 18px #0007; font:13px/1.3 system-ui,sans-serif; }
#ww-candidate-review[hidden] { display:none; }
#ww-candidate-review .ww-candidate-heading { display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:8px; }
#ww-candidate-review strong { font-size:14px; }
#ww-candidate-status { color:#c8dce3; font-size:12px; text-align:right; }
#ww-candidate-review[data-state="verified"] #ww-candidate-status { color:#9ee3bc; }
#ww-candidate-review[data-state="error"] #ww-candidate-status { color:#ffc3b2; }
#ww-candidate-review .ww-candidate-options { display:grid; grid-template-columns:repeat(3,1fr); gap:6px; }
#ww-candidate-review .ww-candidate-options + .ww-candidate-options { margin-top:6px; }
#ww-candidate-review button { min-height:34px; border:1px solid #668696; border-radius:8px; background:#203c50; color:inherit; font:inherit; cursor:pointer; touch-action:manipulation; }
#ww-candidate-review button[aria-pressed="true"] { background:#d0eff2; border-color:#d0eff2; color:#102e3a; }
#ww-candidate-review button:disabled { opacity:.5; cursor:wait; }
#ww-candidate-review button:focus-visible { outline:2px solid #fff; outline-offset:2px; }
</style>
<section id="ww-candidate-review" aria-label="Candidate preview controls" hidden>
  <div class="ww-candidate-heading"><strong>Candidate preview</strong><span id="ww-candidate-status" role="status" aria-live="polite">Preparing preview…</span></div>
  <div class="ww-candidate-options" role="group" aria-label="View">
    <button type="button" data-candidate-view="chase" aria-pressed="true">Chase</button>
    <button type="button" data-candidate-view="front" aria-pressed="false">Front</button>
    <button type="button" data-candidate-view="side" aria-pressed="false">Side</button>
  </div>
  <div class="ww-candidate-options" role="group" aria-label="Action">
    <button type="button" data-candidate-pose="runner_hud" aria-pressed="true">Run</button>
    <button type="button" data-candidate-pose="runner_jump" aria-pressed="false">Jump</button>
    <button type="button" data-candidate-pose="runner_slide" aria-pressed="false">Slide</button>
  </div>
</section>
<script>
(() => {
  const panel = document.getElementById('ww-candidate-review');
  if (!panel || !window.__wwQABuild?.hero_candidate ||
      !['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname) ||
      !new URLSearchParams(location.search).get('qa_token')) return;
  const status = document.getElementById('ww-candidate-status');
  const views = [...panel.querySelectorAll('[data-candidate-view]')];
  const poses = [...panel.querySelectorAll('[data-candidate-pose]')];
  const buttons = [...views, ...poses];
  let busy = false, generation = 0, selectedView = 'chase', selectedPose = 'runner_hud';
  const delay = () => new Promise(resolve => setTimeout(resolve, 160));
  const twoFrames = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  function show(state, label) { panel.dataset.state = state; status.textContent = label; }
  function lock(value) { busy = value; for (const button of buttons) button.disabled = value; }
  function selection() {
    for (const button of views) button.setAttribute('aria-pressed', String(button.dataset.candidateView === selectedView));
    for (const button of poses) button.setAttribute('aria-pressed', String(button.dataset.candidatePose === selectedPose));
  }
  async function waitReady(token, route, minimumDraw = 0, frozen = true) {
    const deadline = Date.now() + 180000;
    while (token === generation && Date.now() < deadline) {
      if (window.__wwQA && window.__wwHeroCandidate) {
        const stage = window.__wwQA.read();
        if (stage?.status === 'error' || stage?.status === 'stopped') throw new Error('Preview unavailable');
        if (stage?.status === 'ready' && (!frozen || stage.tree_paused === true) &&
            stage.settled_frames >= 2 && stage.submitted_frames >= minimumDraw &&
            (!route || stage.route === route)) return stage;
      }
      await delay();
    }
    throw new Error('Preview unavailable');
  }
  function verify() {
    // Expensive renderer fingerprints are sampled only after each completed
    // user action, never on the lightweight readiness polling loop.
    const result = window.__wwHeroCandidate.read();
    if (result?.status !== 'ready' || result.tree_paused !== true || result.settled_frames < 2 ||
        !result.active_renderer?.signature || result.active_renderer.errors?.length) {
      throw new Error('Verification failed');
    }
    selectedView = result.view;
    show('verified', 'Verified');
    selection();
  }
  async function changeView(view) {
    if (busy) return;
    const token = ++generation;
    lock(true); show('pending', 'Preparing view…');
    try {
      const stage = await waitReady(token, selectedPose);
      window.__wwHeroCandidate.view(view);
      await waitReady(token, selectedPose, stage.submitted_frames + 2);
      await twoFrames();
      verify();
    } catch (error) { show('error', error.message === 'Verification failed' ? error.message : 'Preview unavailable'); }
    finally { lock(false); }
  }
  async function changePose(route, initial = false) {
    if (busy) return;
    const token = ++generation;
    lock(true); show('pending', 'Preparing preview…');
    try {
      const current = await waitReady(token, null, 0, false);
      // Preserve an explicitly staged initial jump/slide. Ordinary menu entry
      // moves to the real runner through the existing QA route bridge.
      const target = initial && poses.some(button => button.dataset.candidatePose === current.route) ? current.route : route;
      if (!initial || current.route !== target) window.__wwQA.route(target);
      await waitReady(token, target);
      await twoFrames();
      selectedPose = target;
      selectedView = 'chase';
      verify();
    } catch (error) { show('error', error.message === 'Verification failed' ? error.message : 'Preview unavailable'); }
    finally { lock(false); }
  }
  for (const button of views) button.addEventListener('click', () => changeView(button.dataset.candidateView));
  for (const button of poses) button.addEventListener('click', () => changePose(button.dataset.candidatePose));
  panel.hidden = false;
  changePose('runner_hud', true);
})();
</script>
'''


def install(source: Path, project: Path) -> dict:
    source, project = source.resolve(), project.resolve()
    local = project / "_qa_local"
    if source == project or not local.is_dir() or local.is_symlink():
        raise ValueError("Candidate installation requires a separate prepared QA project")

    def local_file(name: str) -> Path:
        path = project / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(project):
            raise ValueError("Missing or unsafe prepared project file: " + name)
        return path

    # Read and validate every input before creating a candidate directory or
    # modifying the copied project. A stale map must not produce a misleading
    # source binding; malformed config/wrapper/presets must leave no partial kit.
    config_path = local_file("project.godot")
    config = config_path.read_text()
    if "HeroCandidateQA=" in config:
        raise ValueError("Candidate already installed; use fresh output")
    source_names = (MODEL, MODEL + ".import", WRAPPER, CONTROLLER, HELPER, *RESOURCES)
    source_bytes = {name: (source / name).read_bytes() for name in source_names}
    for name in (MODEL, WRAPPER, CONTROLLER, *RESOURCES):
        if local_file(name).read_bytes() != source_bytes[name]:
            raise ValueError("Prepared runtime resource differs from source: " + name)
    folder = project / "qa_hero"
    if folder.exists() or folder.is_symlink() or (local / "hero_candidate_browser.gd").exists() \
            or (local / "hero_candidate_browser.gd").is_symlink():
        raise ValueError("Candidate files already exist; use fresh output")
    identity = re.findall(r'^config/custom_user_dir_name="waddle-chrome-reference-[^"\r\n]+"$', config, re.M)
    if len(identity) != 1 or len(re.findall(r"^config/custom_user_dir_name=", config, re.M)) != 1 \
            or len(re.findall(r"^config/use_custom_user_dir=true$", config, re.M)) != 1 \
            or len(re.findall(r"^config/use_custom_user_dir=", config, re.M)) != 1 \
            or config.count('ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"') != 1 \
            or config.count("[qa]\n") != 1 or "hero_candidate_enabled=" in config:
        raise ValueError("Missing or ambiguous Chrome QA isolation, bridge or QA section")
    autoload = re.findall(r"^\[autoload\]\n(.*?)(?=^\[|\Z)", config, re.M | re.S)
    if len(autoload) != 1 or 'ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"' not in autoload[0]:
        raise ValueError("Chrome QA bridge must be in the autoload section")

    # Exact canonical importer parameters are retained; generated remap paths
    # are regenerated for the copied source by Godot's normal importer.
    importer = source_bytes[MODEL + ".import"].decode()
    if importer.count("[params]") != 1:
        raise ValueError("Canonical importer must have one parameter section")
    params = importer.split("[params]", 1)[1]
    wrapper = source_bytes[WRAPPER].decode()
    if wrapper.count('res://' + MODEL) != 1 or wrapper.count('[node name="ImportedRig"') != 1 \
            or wrapper.count('res://' + CONTROLLER) != 1:
        raise ValueError("Canonical wrapper structure changed")
    wrapper = wrapper.replace('res://' + MODEL, "res://qa_hero/candidate.glb").replace('[node name="ImportedRig"', '[node name="Model"')
    presets = local_file("export_presets.cfg")
    text = presets.read_text()
    if len(re.findall(r'^include_filter="[^"\n]*,_qa_local/\*\.js"$', text, re.M)) != 1 \
            or len(re.findall(r"^include_filter=", text, re.M)) != 1:
        raise ValueError("QA include filter missing or ambiguous")

    binding = {"schema_version": 1, "material_mode": "runtime",
        "candidate_label": "Canonical runtime integration fixture",
        "color_contract": "runtime-semantic-COLOR_0", "glb_sha256": hashlib.sha256(source_bytes[MODEL]).hexdigest(),
        "runtime_resources": {name: hashlib.sha256(source_bytes[name]).hexdigest() for name in RESOURCES},
        "production_ready": False, "source_fidelity_approved": False,
        "scope": "Existing authored model, production controller/materials, explicit isolated QA selection; shipping procedural default unchanged"}
    folder.mkdir()
    (folder / "candidate.glb").write_bytes(source_bytes[MODEL])
    (folder / "candidate.glb.import").write_text('[remap]\nimporter="scene"\ntype="PackedScene"\n\n[params]' + params)
    (folder / "candidate_binding.json").write_text(json.dumps(binding, indent=2) + "\n")
    (project / WRAPPER).write_text(wrapper)
    (local / "hero_candidate_browser.gd").write_bytes(source_bytes[HELPER])
    config = config.replace('ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"',
        'ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"\nHeroCandidateQA="*res://_qa_local/hero_candidate_browser.gd"', 1)
    config = config.replace('[qa]\n', '[qa]\nhero_candidate_enabled=true\n', 1)
    config_path.write_text(config)
    presets.write_text(text.replace(',_qa_local/*.js"', ',_qa_local/*.js,qa_hero/*.json"', 1))
    return {"binding": binding, "wrapper_sha256": sha(project / WRAPPER),
        "helper_sha256": sha(project / "_qa_local/hero_candidate_browser.gd"),
        "controls_sha256": hashlib.sha256(review_controls().encode()).hexdigest(),
        "gallery_eligible": False,
        "reason": "Candidate-only evidence must not be promoted as shipping gallery captures"}
