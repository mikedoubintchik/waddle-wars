# SDK presentation-query QA candidate

QA only. Candidate template compiled locally; first foreground comparison
completed but is invalid because the control camera/world failed. Production
presets and gameplay/art sources are unchanged.

## Compiled comparison — 2026-10-01

Candidate T5 and control T6 were exported from the same frozen runtime source
fingerprint `1cc05eb6ee6ad039bc5be3e6a6d4a8b601e53e043097fc8bbbe72822179815ef`.
Both use the worker template with the separate eval-main-thread correction.
Their WASM bytes are identical (`4f3857ffa7869385b06552908a646d6a5dc3eee4cea7f3b454e77309f00ddcd6`);
their engine JavaScript differs only by this scissor-query replacement.
Thus this pair isolates the query change, not worker-versus-main-thread behavior.
Candidate ZIP SHA-256: `f0d0281db50cd7d248b0d166c304594b9d67597c30b1514b3234f6779b28e226`.
Control ZIP SHA-256: `aaec2d8253a13d6d55360dc545aae948bb351775bd95f88d88cdc4bc6fb8be27`.
Both fresh import/export gates pass. Detailed identity receipt:
`qa_shots/runner/chrome-worker-scissor-t5.shp0l_to/comparison.json`.
First foreground samples now exist. T5 fails frame thresholds (49.07 FPS,
p95 37.33 ms, maximum 153.04 ms, four frames above 100 ms). T6's numeric pass
is rejected: camera coordinates reached about 1e37, with zero visible 3D at
the in-sample primitive-peak snapshot and only 59.12 average draw calls versus
T5's 182.48. This is not comparable rendering work. No visual pass or speedup
is recorded. Original raw reports remain unchanged; see the comparison receipt
for the explicit rejection and next correctness gate.

## Exact candidate

### Correctness-fixed pair prepared — 2026-10-01

Two additional immutable QA templates now share both the eval-main-thread
correction and the separate `GL.currentContext` buffer-readback correction.
The original T5/T6 pair remains invalid and is not overwritten. New artifacts:

- Official SDK query, readback corrected: ZIP SHA-256
  `d30d91a83c4f85c9a3423eb107726f3bf6e7c81d9be3f4e2b438098f43a7f9a2`,
  directory `qa_shots/native-headers-4.7.1.seSHFR/web-worker-eval-readback-current-context/`.
- Candidate SDK query, readback corrected: ZIP SHA-256
  `023f3fc48e7ff1f2987f14d4ba82581dc90c9b421f8622ac15862d5c7e3cbf30`,
  directory `qa_shots/native-headers-4.7.1.seSHFR/web-worker-eval-readback-scissor-current-context/`.

Both compiled successfully. Byte comparison confirms identical WASM
(`4f3857ffa7869385b06552908a646d6a5dc3eee4cea7f3b454e77309f00ddcd6`)
and JavaScript differing only in the one `.getParameter(3089)` to
`.isEnabled(3089)` replacement. Both emitted readback functions preserve exact
arguments and synchronous worker-to-main dispatch. Installed SDK source was
restored to its verified official hash after compilation. No global template
installation or production export change occurred. Real mesh readback, valid
foreground 3D workload, and responsiveness remain required; these builds alone
are not acceptance evidence.

Emscripten 4.0.11 `src/lib/libwebgl.js:976`, inside `GL.blitOffscreenFramebuffer`:

```diff
-      var prevScissorTest = gl.getParameter(0xC11 /*GL_SCISSOR_TEST*/);
+      var prevScissorTest = gl.isEnabled(0xC11 /*GL_SCISSOR_TEST*/);
```

Only this query changes. Existing disable, drawing, and caller-state restoration remain byte-identical. No capability wrappers, custom cache, assumed final rasterizer state, framebuffer query change, or OffscreenCanvas migration.

The capability is valid and both APIs return its boolean state on a live context. Context loss changes `getParameter`'s `null` to `isEnabled`'s `false`; both are falsy in the unchanged conditional. Native browser ownership of capability state avoids custom tracking across enable/disable, multiple contexts, and restoration.

## Source-supported lead, not a measured fix

Current Chromium primary source routes [WebGL `getParameter(SCISSOR_TEST)`](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/third_party/blink/renderer/modules/webgl/webgl_rendering_context_base.cc) through `GetBooleanParameter`, and `isEnabled` through `ContextGL()->IsEnabled` (main source lines 4138 and 4992–5001 at inspection).

[GLES2Implementation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/gpu/command_buffer/client/gles2_implementation.cc) first asks `state_.GetEnabled` in `IsEnabled` (860–881). `GetHelper` explicitly returns false for `GL_SCISSOR_TEST` (1076–1097), so `GetBooleanvHelper` cannot use that cache (1285–1293). [ClientContextState](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/gpu/command_buffer/client/client_context_state_impl_autogen.h) stores and returns `enable_flags.scissor_test` and updates it on capability changes.

Those are current main-branch sources, not proof of the installed Chrome revision's exact implementation. The hypothesis is that this query avoids a recurring synchronous state-query boundary. Any wait may instead move to another operation. A frozen-source A/B remains required; no GPU-cause claim follows from frame-phase wall spans.

Historical receipt: `qa_shots/runner/chrome-skyguard-presentation60.u05f05jv/browser_report.json` and `presentation_trace_analysis.md`, run `runner-web-4f85e30aa9614362bfecb458eefd933b`. Official Godot 4.7.1 release, non-worker, Compatibility, 1920×1080 backing, high, actual 2× MSAA despite requested 4×. Authored DAY kit inactive. Presentation instrumentation enabled; broad WebGL instrumentation disabled; stream/frame-phase diagnostics enabled; no CPU/CDP sampling. Whole-page `getParameter(3089)` count 3,913, total 8,955.180 ms instrumented wall time, mean 2.289 ms, maximum 14.655 ms. Its 112.580 ms hitch **does not overlap** any recorded slow presentation query. This older fixture is not attribution for current sample S, nor an explanation for visible freezes.

## Build identity and preservation

`--qa-variant official|eval_main_thread` stays independent. SDK default `--qa-sdk-variant official` requires the exact original installed `upstream/emscripten/src/lib/libwebgl.js` hash. The opt-in `--qa-sdk-variant scissor_is_enabled` requires the exact candidate hash, patch-artifact hash, and whole original-file hash reconstructed by reversing the single reviewed replacement. Installed SDK files are not necessarily tracked by the emsdk Git checkout; a clean Git diff is not their identity proof.

Pinned hashes:

| Input | SHA256 |
| --- | --- |
| Original SDK file | `99d70e3ed68f7a6a0752ce3983092c173ca0d16b082575f5498cf2a23945a352` |
| Candidate SDK file | `9ddf411c9bc2dc88446aead3dcc079826682ee85efe2a42f2c4f53b81e64dce8` |
| Reviewed patch | `93113fa70ac0aaa4a5f4e8f71c29bc16aa1b243fe4210c698c1933690d07a792` |

Every explicit build archives only the current regular `bin/godot.web.template_release.<arch>.js` into that new run's `prelink-inputs`, recording path/hash/bytes. The missing exact target forces relinking without deleting C++ objects or earlier ZIPs. Source identities are checked before and after building. The receipt records both Godot eval and installed SDK source-file hashes, both variant identities, contract output, preserved prelink input, and emitted ZIP's actual scissor-query method. A stale `getParameter` ZIP is rejected for the candidate; a stale `isEnabled` ZIP is rejected for SDK default. Candidate artifact names include the SDK variant; existing official/eval immutable outputs are not overwritten.

## Local host validation

- `node tools/release/test_web_scissor_presentation.mjs <installed libwebgl.js>`: 17 checks passed. Exact one-line delta; original/candidate parity for enabled/disabled/lost contexts, WebGL2 blit and both fallback paths, clipping/restoration, repeated capability changes, resize, interleaved contexts, modeled worker forwarding, and native draw exceptions.
- `python3 tools/release/test_web_worker_sdk.py`: 16 tests passed. Original/candidate installed-file guards, clean-Git non-proof, unrelated edits, unknown variants, patch/baseline hashes, one replacement, missing/symlink sources, stale/duplicate emitted blitters, and recoverable exact prelink preservation.
- Existing `test_web_eval_proxy.mjs`: 21 checks passed; eval-main-thread source and patch unchanged.

Host mocks do not prove real browser context loss, native concurrency, driver behavior, visual acceptance, or speed. Coordinate compilation and real browser A/B through root; do not overlap compiler work with timing runs.
