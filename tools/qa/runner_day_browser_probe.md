# Scoped DAY Chrome comparison

Candidate only; production catalog unchanged. Use root-owned Chrome and the
already-muted `127.0.0.1:54615` origin. No native captures. QA scripts are `.in`
templates so ordinary Godot exports do not discover their QA-only inheritance.

## Prepared candidate

`qa_shots/tests/runner-day-scoped-candidate-20261008/browser-candidate-v1/server.json`
contains the verified URL. Source base: frozen Chrome v3 snapshot, plus precisely
six DAY visual roles /18 dependencies. Heavy landmarks and authored obstacles
remain excluded. Compiler/importer used Dummy; browser runtime retains ordinary
WebAudio and relies on existing site mute.

- Import/export logs: no `ERROR` or `SCRIPT ERROR`.
- QA metadata/guard tests:15/15, stderr empty.
- Actual PCK inspection in empty project:39/39; selected18 available,
  unapproved20 absent, mount succeeded.
- Pack425,561,608bytes. This is5,865,668bytes more than v3's pack, which also has a
  different QA fixture. It is not a pure matched asset-only size comparison.
- Main candidate gates:124 static,160 headless, six Khronos meshes without
  errors/warnings. Strict whole-art baseline180/candidate180; zero added errors.

## Operator sequence

1. Preserve current evidence. Reuse the task Chrome tab at the verified candidate
   URL; keep site muted. Set intended viewport before navigation. Confirm
   `window.__wwQAGate.phase === 'active'`, `window.__wwDay` exists, and
   `window.__wwQA.read().build` matches candidate `build.json`.
2. For visual-first review call `window.__wwDay.start('stills')`. Poll only as
   needed. Wait for `day_course.state === 'checkpoint'` and at least two submitted
   frames beyond `day_course.latest_checkpoint.submitted_frames`. Capture actual
   browser pixels. First checkpoint is real opening countdown at0m.
3. Call `window.__wwDay.next()` to naturally move to60,146,266,600and650m.
   Each checkpoint freezes simulation solely for pixels. `read()` records actual
   distance, biome, loaded/live authored IDs and mesh origins inside the frustum.
   Origin census does not prove pixel visibility; inspect the screenshot.
4. Save actual image dimensions/hash and `read()` metadata. Stills expire after
   240seconds total. Root may stop early after enough visual evidence, via
   `window.__wwDay.stop()`; it pauses the isolated scene.
5. Only if artwork merits further consideration, coordinate a matched baseline
   export. Prepare from **the same frozen v3 base and exact probe templates**, using
   `--variant baseline`; main production files remain unchanged. Keep quality,
   viewport, governor, V-Sync and FPS settings identical. Mirror prior stills/run
   order or use fresh isolated profiles; mission/progression history is real.
6. **Frozen v1 restart workaround:** first call `__wwDay.stop()` then
   `__wwQA.route('main_menu')`. Poll separately until `status === 'ready'`,
   `scene === 'res://scenes/menus/main_menu.tscn'` and `runner` is absent. Only then
   call `__wwDay.start('continuous')` once. Verify the report's first checkpoint
   is0m/0elapsed and seed20260818. Immediate command return can precede the next
   engine callback; use a subsequent `read()` to confirm state. Do not use
   repeated starts while the old course remains current.

   For timing, use genuinely foreground Chrome with focus emulation disabled.
   Close DevTools. Arm the existing process-specific resource guard after finding
   this test renderer. Call `window.__wwDay.start('continuous')` and leave browser
   untouched until `day_course.state === 'complete'` (650m). No checkpoint pauses
   occur in continuous mode. Ninety-second running watchdog and12,000sample bound
   prevent unbounded timing history. Startup has separate60second bound.
7. `window.__wwDay.report()` returns summary, checkpoints and bounded raw samples.
   Use its `summary` for quick review; preserve full report once, avoid repeatedly
   serializing it. `performance_evidence` stays false for stills, incomplete runs,
   headless, or observed hidden/blurred samples. Same-source baseline comparison
   and root acceptance remain required; it is not an automatic performance pass.
8. Finished scene is paused, not an engine shutdown. To release GPU/WebAudio after
   preserving evidence call `window.__wwQA.stop()` and navigate to the candidate
   `control.html` or close only the task tab. Root owns browser lifecycle.

Continuous samples are monotonic intervals between actual `frame_post_draw`
signals plus real draw/primitives counters, distance and render scale. First draw
is omitted because no prior interval exists. No screenshot/readback in engine.
No forced delta, quality, render resolution, speed, invulnerability, teleport or
power grant. Fixed seed20260818 and normal autopilot verbs are explicitly
synthetic, not physical-input evidence. Default governor can reduce effective
quality; checkpoints and samples record changes, so lower quality cannot silently
count as equal-tier acceptance. Godot's aggregate primitive counter retains its
known GLES3 MultiMesh LOD accounting limitation; no guessed correction applied.

The QA stop-marker URL is relative to the candidate alias and resolves its own
`qa-stop.json`. Existing causal HTML/PCK/WASM/JS/control files remained byte-identical.

### v1 restart finding / source correction

The first candidate continuous attempt after the expired600m still session was
invalid: it resumed the old course around601m. `_process` could accept the old
course's ready flags while `_enter_course` was still deferred/awaiting teardown,
changing the session to running and canceling its own route wait. Preserve that
trial separately; it is neither a full-run benchmark nor a production failure.
The frozen candidate and baseline exports remain unchanged and use the explicit
Home reset above. Source now requires both an issued route and a different scene
instance, and rejects stale/canceled deferred session callbacks. Focused native
metadata checks cover these boundaries; they are not browser timing evidence.

## Reproduction

```sh
python3 tools/qa/runner_day_browser_export.py prepare NEW_OUTPUT --variant candidate
python3 tools/qa/runner_day_browser_export.py build NEW_OUTPUT
```

Use `--base` to explicitly select the frozen base. Baseline build is intentionally
deferred until candidate visual review warrants it. Coordinator must serialize
exports with other engine/profiling work. Fresh output required; no overwrite of
prior evidence. Main manifest integration and deployment are separate actions.
