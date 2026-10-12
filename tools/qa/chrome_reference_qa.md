# Chrome reference QA harness

Local only. Root owns CUA Chrome; these tools never open a browser. Preserve old
causal exports. Wait for coordinator's source freeze before `prepare` / `build`.

## Export

```sh
python3 tools/qa/chrome_reference_export.py prepare qa_shots/tests/chrome-reference-final-20261008
python3 tools/qa/chrome_reference_export.py build qa_shots/tests/chrome-reference-final-20261008
python3 tools/qa/chrome_reference_export.py serve qa_shots/tests/chrome-reference-final-20261008 --port 54616
```

Default engine shell, production PCK/exclusions and script export mode retained.
Original production head and standard exported HTML are saved unchanged as
evidence. Served visual-QA HTML replaces its auth and API bridges with signed-out,
non-networked stubs and adds a same-origin connection fence. This prevents Clerk
session restoration and synthetic scores/save data reaching a real account.
A fresh localhost port alone does not isolate a provider session. Direct remote
HTTPRequest paths (including feedback/commerce) are also blocked by CSP.

`qa-auth-isolation.json` records exact removed/replacement script hashes and HTML
hashes; `__wwQABuild.qa_auth_isolation` and `__wwQAOffline.mode` expose
`offline_visual_qa`. These captures do **not** verify auth, cloud sync, commerce or
feedback transport. Use no live account or cloud-recovery action in this harness.

Other QA additions: isolated user identity, QA autoload and explicit JS include,
scalar helper and bounded stop-marker poll. `--silent` requests Dummy runtime
audio for visual-only QA; otherwise normal WebAudio requires Chrome site mute.
Pass it to the `build` command (not `prepare` or `serve`). The flag preserves
existing engine arguments, adds Dummy before engine construction, and records
the override in the manifest, build receipt and browser scalar. It does not
modify the production preset or standard exported HTML. Silent captures cannot
accept audio behavior.
No forced quality, canvas dimensions, touch flag or governor override. Compiler
itself always uses Dummy.

Use supported Chrome viewport/touch emulation **before navigation** so original
production DPR policy runs against intended device metrics. Desktop/mobile image
dimensions come from actual saved image bytes, never inferred from request.

Generated `server.json` gives URL with random localhost token. Optional initial
`qa_route` query selects named state after normal boot/title. Without exact token
or on nonlocal origin, GDScript bridge does not activate.

## Browser commands through CUA

```js
window.__wwQA.read()
window.__wwQA.route('settings_audio')
window.__wwQA.release()
```

If bridge is absent, inspect `window.__wwQAGate` and `[chrome-qa-gate]` boot
messages. They expose the current autoload/query/install phase without keeping
history. Never inject a replacement bridge into a page to conceal failed setup.
Chrome's Godot bridge returned the query's JavaScript boolean as Variant `INT1`
in the actual browser. The QA gate accepts only `BOOL true` or `INT1`; all other
types/values remain denied. The observed failure and actual v3 activation are
recorded in `qa_shots/tests/chrome-reference-qa-20261008/activation-investigation.json`.

Poll read only as needed; no history or periodic engine sampling. `status` must be
`ready`, `route` requested state, `settled_frames >= 2`, and Chrome's frame visible
before capturing. `error` means failure, never acceptance. `ready_draw` marks eight
real submitted draws plus 900 ms after staging. Each route has a 45-second bound.
No game-side PNG readback, forced draw, changed production timing or raster claim
from headless checks. Screenshot via CUA; preserve original JPEG/PNG format.

Stable names (24 states):

```text
main_menu base_camp missions account feedback customize cosmetic_shop
achievements leaderboard credits controls mode_select loader
settings_accessibility settings_gameplay settings_audio settings_display settings_online
runner_hud runner_jump runner_slide pause avalanche_catch results
```

Menu routes instantiate actual production scenes through SceneRouter and restore
actual internal page state. Hover remains root's real pointer action. Loader uses
real SceneRouter subclass held at resource-request boundary: artwork stage only.

Runner stages execute real countdown/route. HUD/pause/action stills grant three
powers, advance actual movement for 2.25 seconds, then freeze tree (or open actual
Pause). Jump/slide invoke real action method and observe accepted signal. Catch
and Results advance actual movement then execute three `take_hit` calls with
iframes cleared. Full catch/fade runs; catch freezes at >=1.8 seconds, Results
after full cover and score count-up. All synthetic setup recorded in `read()`;
these are design captures, **not physical-input/gameplay performance evidence**.
`release()` resumes a frozen still without dismissing a real Pause overlay.

`read()` includes real Master bus mute/db, explicit/master/focus flags, actual mute
settings, bounded playing SFX pool, accepted jump/slide counts and last accepted
pool snapshot, current draw/memory/quality counters, source/pack/engine hashes,
timestamp/URL, CSS/backing viewport and browser focus. It stores no identity,
tokens from production auth, API bodies or save dumps. `__wwMemorySample()` adds
bounded JS/WASM/canvas scalar diagnostics. No forced GC or heap contents.

Capture files: `desktop/<state>.jpg`, `mobile/<state>.jpg` when CUA returns JPEG;
retain PNG only when actual PNG. Sidecar JSON should combine `read()` with raw
image path/hash/dimensions/MIME and root's acceptance; never claim unstaged
gameplay acceptance from these frame fixtures.

## Bounded resource guard

After boot, root identifies actual local test renderer PID. Arm OS-only guard:

```sh
python3 tools/qa/chrome_reference_watch.py qa_shots/tests/chrome-reference-final-20261008 --renderer-pid PID --seconds 1200
```

Tracks browser main + that renderer only. >1 GiB growth for either since arm, or
combined CPU >220% for 15 seconds, writes `qa-stop.json`. QA page polls every3 s
for at most30 min and requests its own engine quit. No other app/tab terminated.
If Chromium main thread stalls, poll cannot guarantee stopping it: root closes
only QA tab through CUA. Keep original counter/stop evidence before retry.
When the observed renderer exits, the guard records `guard-end.json` and stops
without changing `qa-stop.json`; there is no engine left to stop. Before replacing
a tab, stop its watcher first and preserve outcomes before resetting any prior
threshold marker. Then reopen and arm the new observed renderer after live-engine
confirmation. This prevents an old exit marker from killing the next boot.

## Existing gates

`tests/test_chrome_reference_export.py`: production contract and original files
preserved, only isolated QA additions. `tests/chrome_reference_bridge_shell.test.mjs`:
host/token checks, bounded reads, command/scalar contract. Godot
`tests/chrome_reference_bridge_test.tscn` requires bridge copied to `_qa_local`
inside an isolated project; verifies native disabled, allowlisted routes and
actual read-only audio/settings scalars. None substitutes for Chrome QA.
