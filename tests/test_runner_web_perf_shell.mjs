// Host-only shell checks: no browser, engine, GPU, or report artifacts.
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import test from "node:test";
import vm from "node:vm";

const shell = readFileSync(new URL("../tools/qa/runner_web_perf_shell.html", import.meta.url), "utf8")
  .replaceAll("$GODOT_URL", "index.js").replaceAll("$GODOT_CONFIG", "{}");
const blocks = [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1]);

function harness(Engine, {search = "", now = () => 123, WebGL2RenderingContext,
  runConfig = {run_id: "host-test"}} = {}) {
  const listeners = {};
  const documentListeners = {};
  const posts = [];
  const status = {};
  const canvas = {width: 1920, height: 1080, clientWidth: 1920, clientHeight: 1080,
    style: {width: "1920px", height: "1080px"}};
  const buttonListeners = {};
  const startButton = {hidden: true, disabled: false,
    addEventListener: (name, handler) => { buttonListeners[name] = handler; }};
  const captureListeners = {};
  let nextRAFID = 0;
  const rafCallbacks = new Map();
  const captureButton = {hidden: true, disabled: false,
    addEventListener: (name, handler) => { captureListeners[name] = handler; }};
  const context = vm.createContext({
    URL, URLSearchParams, performance: {now},
    location: {href: "http://127.0.0.1:4321/index.html" + search, search},
    navigator: {userAgent: "Host test", platform: "test"},
    devicePixelRatio: 1, innerWidth: 1920, innerHeight: 1080, crossOriginIsolated: true,
    requestAnimationFrame: callback => {
      const id = ++nextRAFID;
      rafCallbacks.set(id, callback);
      return id;
    },
    cancelAnimationFrame: id => { rafCallbacks.delete(id); },
    document: {title: "", visibilityState: "visible", documentElement: {clientWidth: 1920, clientHeight: 1080},
      addEventListener(name, handler) {
        if (!documentListeners[name]) documentListeners[name] = [];
        documentListeners[name].push(handler);
      },
      getElementById: id => ({status, canvas, "start-diagnostic": startButton,
        "capture-lifecycle": captureButton})[id] ?? null},
    fetch: async (_url, options) => { posts.push(JSON.parse(options.body)); return {ok: true}; },
    Engine, WebGL2RenderingContext,
  });
  context.window = context;
  context.addEventListener = (name, handler) => { listeners[name] = handler; };
  vm.runInContext(blocks[0].replaceAll("@@RUN_CONFIG@@", JSON.stringify(runConfig)), context);
  return {context, posts, status, canvas, startButton, captureButton,
    // Deliberately allows repeated callback dispatch even after disabled/once,
    // so the production single-start guard is tested independently of the DOM.
    clickStart: () => buttonListeners.click?.(),
    clickCapture: () => captureListeners.click?.(),
    frame: timestamp => {
      const callbacks = [...rafCallbacks.values()];
      rafCallbacks.clear();
      for (const callback of callbacks) callback(timestamp);
    },
    emit: (name, event) => listeners[name](event),
    emitDocument: (name, event) => {
      for (const handler of documentListeners[name] ?? []) handler(event);
    },
    boot: () => vm.runInContext(blocks[1], context)};
}

function complete(instance, overrides = {}) {
  instance.context.__wwRunnerMark("first_running");
  instance.context.__wwRunnerFinish({average_fps: 60, p95_frame_ms: 17, max_frame_ms: 20,
    workload_valid: true, workload_validation: {captured: true, valid: true},
    performance_thresholds_met: true, meets_gate: true, ...overrides}, "csv");
  return instance.posts[0];
}

function readbackBegin(instance) {
  return JSON.parse(instance.context.__wwRunnerReadbackBegin());
}
function readbackEnd(instance) {
  return JSON.parse(instance.context.__wwRunnerReadbackEnd());
}

test("local web diagnostics start with Dummy audio without changing saved preferences", async () => {
  let received;
  class Engine {
    static getMissingFeatures() { return []; }
    startGame(options) { received = options; return Promise.resolve(); }
  }
  const instance = harness(Engine);
  instance.boot();
  assert.deepEqual(Array.from(received.args), ["--audio-driver", "Dummy"]);
});

test("readback witness installs only when explicitly begun and forwards exact calls", () => {
  const seen = [];
  const returned = {native_result: true};
  class GL {getBufferSubData(...args) {seen.push({receiver: this, args}); return returned;}}
  const descriptor = Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData");
  const instance = harness(undefined, {WebGL2RenderingContext: GL});
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
  const begun = readbackBegin(instance);
  assert.equal(begun.begun, true);
  const gl = new GL();
  const view = new Uint16Array(12);
  const args = [0x8892, 4, view, 2, 5];
  assert.equal(gl.getBufferSubData(...args), returned);
  assert.equal(gl.getBufferSubData(0x8892, 0, new Uint8Array(8)), returned);
  assert.equal(seen[0].receiver, gl);
  assert.deepEqual(seen[0].args, args);
  const ended = readbackEnd(instance);
  assert.equal(ended.calls_attempted, 2);
  assert.equal(ended.calls_returned, 2);
  assert.equal(ended.nonzero_returned_calls, 2);
  assert.equal(ended.returned_bytes, 18);
  assert.equal(ended.passed, true);
  assert.equal(ended.restored, true);
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
  gl.getBufferSubData(0x8892, 0, new Uint8Array(4));
  assert.equal(readbackEnd(instance).calls_attempted, 2, "No residual measured wrapper");
  assert.equal(readbackBegin(instance).begun, false, "No new wrapper after preflight closes");
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
});

test("readback witness preserves exact prior optional-wrapper descriptor and DataView bytes", () => {
  const traceCalls = [];
  const oldWrapper = function(...args) {traceCalls.push({receiver: this, args}); return 17;};
  class GL {}
  Object.defineProperty(GL.prototype, "getBufferSubData", {value: oldWrapper,
    configurable: true, writable: false, enumerable: true});
  const descriptor = Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData");
  const instance = harness(undefined, {WebGL2RenderingContext: GL});
  assert.equal(readbackBegin(instance).begun, true);
  const gl = new GL();
  assert.equal(gl.getBufferSubData(0x8892, 0, new DataView(new ArrayBuffer(16)), 4, 8), 17);
  assert.equal(gl.getBufferSubData(0x8892, 0, new Float32Array(4), 1, 0), 17);
  const ended = readbackEnd(instance);
  assert.equal(ended.returned_bytes, 20);
  assert.equal(ended.passed, true);
  assert.equal(traceCalls.length, 2);
  assert.equal(traceCalls[0].receiver, gl);
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
});

test("readback witness preserves thrown values and restores even failed preflight", () => {
  const thrown = {native_failure: true};
  class GL {getBufferSubData() {throw thrown;}}
  const descriptor = Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData");
  const instance = harness(undefined, {WebGL2RenderingContext: GL});
  assert.equal(readbackBegin(instance).begun, true);
  assert.throws(() => new GL().getBufferSubData(0x8892, 0, new Uint8Array(8)), error => error === thrown);
  const ended = readbackEnd(instance);
  assert.equal(ended.calls_attempted, 1);
  assert.equal(ended.calls_returned, 0);
  assert.equal(ended.nonzero_returned_calls, 0);
  assert.equal(ended.calls_threw, 1);
  assert.equal(ended.passed, false);
  assert.equal(ended.restored, true);
  assert.equal(ended.reason, "readback_call_threw");
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
});

test("readback witness fails closed for missing, accessor or frozen browser method", () => {
  let getterReads = 0;
  class Accessor {}
  Object.defineProperty(Accessor.prototype, "getBufferSubData", {get() {getterReads++; return () => {};}});
  class Frozen {getBufferSubData() {}}
  Object.freeze(Frozen.prototype);
  for (const GL of [undefined, class Missing {}, Accessor, Frozen]) {
    const before = GL && Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData");
    const instance = harness(undefined, {WebGL2RenderingContext: GL});
    assert.equal(readbackBegin(instance).begun, false);
    assert.equal(readbackEnd(instance).passed, false);
    if (GL) assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), before);
  }
  assert.equal(getterReads, 0);
});

test("readback witness rejects no calls, zero bytes and unsupported destination shapes", () => {
  class GL {getBufferSubData() {return undefined;}}
  for (const mode of ["none", "zero", "unsupported"]) {
    const instance = harness(undefined, {WebGL2RenderingContext: GL});
    assert.equal(readbackBegin(instance).begun, true);
    const gl = new GL();
    if (mode === "zero") gl.getBufferSubData(0x8892, 0, new Uint8Array(0));
    if (mode === "unsupported") gl.getBufferSubData(0x8892, 0, {byteLength: 99});
    const ended = readbackEnd(instance);
    assert.equal(ended.passed, false, mode);
    assert.equal(ended.restored, true, mode);
    assert.equal(ended.returned_bytes, 0, mode);
    assert.equal(ended.reason, "insufficient_nonzero_readback_calls", mode);
  }
});

test("readback restoration failure prevents witness acceptance", () => {
  class GL {getBufferSubData() {}}
  const instance = harness(undefined, {WebGL2RenderingContext: GL});
  assert.equal(readbackBegin(instance).begun, true);
  const gl = new GL();
  gl.getBufferSubData(0x8892, 0, new Uint8Array(8));
  gl.getBufferSubData(0x8892, 0, new Uint8Array(8));
  Object.defineProperty(GL.prototype, "getBufferSubData", {configurable: false, writable: false});
  const ended = readbackEnd(instance);
  assert.equal(ended.passed, false);
  assert.equal(ended.restored, false);
  assert.equal(ended.reason, "readback_restore_failed");
});

test("fatal transport restores active preflight wrapper without accepting performance", () => {
  class GL {getBufferSubData() {}}
  const descriptor = Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData");
  const instance = harness(undefined, {WebGL2RenderingContext: GL});
  assert.equal(readbackBegin(instance).begun, true);
  instance.context.__wwRunnerFail("mesh test failed", "mesh_readback_preflight");
  assert.equal(instance.posts[0].readback_witness_cleanup.restored, true);
  assert.equal(instance.posts[0].readback_witness_cleanup.passed, false);
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
});

test("full-app entry cannot install runner readback witness", () => {
  class GL {getBufferSubData() {}}
  const descriptor = Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData");
  const instance = harness(undefined, {WebGL2RenderingContext: GL, runConfig: {run_id: "app-no-witness", entry: "app"}});
  assert.equal(readbackBegin(instance).begun, false);
  assert.equal(readbackEnd(instance).passed, false);
  assert.deepEqual(Object.getOwnPropertyDescriptor(GL.prototype, "getBufferSubData"), descriptor);
});

test("RAF gaps never invent full-app startup or gameplay attribution", () => {
  for (const entry of ["app", "runner"]) {
    const instance = harness(undefined, {now: () => 90, runConfig: {run_id: "raf-phases", entry}});
    instance.context.__wwRunnerMark("engine_start");
    instance.frame(100);
    instance.frame(3000);
    instance.context.__wwRunnerMark("first_running");
    instance.frame(4500);
    instance.context.__wwRunnerFail("test snapshot", "test_only");
    const raf = instance.posts[0].browser.request_animation_frame;
    assert.deepEqual(raf.slow_frames_over_50_ms.map(row => row.phase),
      entry === "app" ? ["app_unclassified", "app_unclassified"] : ["startup", "after_first_running"]);
    assert.equal(raf.max_ms, 2900);
    assert.equal(raf.intervals, 2);
    assert.equal(raf.rows_dropped, 0);
    assert.match(raf.phase_scope, entry === "app" ? /Unclassified/ : /Standalone runner/);
  }
});

test("manual-start waiting cannot exhaust engine RAF retention or hide the crossing interval", () => {
  let clock = 0;
  class Engine {
    static getMissingFeatures() { return []; }
    startGame() { return Promise.resolve(); }
  }
  const instance = harness(Engine, {search: "?manualstart=1", now: () => clock});
  instance.boot();
  instance.frame(0);
  for (let index = 1; index <= 140; index++) instance.frame(index * 10000);
  clock = 1400007;
  instance.clickStart();
  instance.frame(1401500);
  clock = 1401600;
  instance.context.__wwRunnerMark("first_running");
  instance.frame(1404400);
  instance.context.__wwRunnerFail("test snapshot", "test_only");
  const raf = instance.posts[0].browser.request_animation_frame;
  assert.equal(raf.schema_version, 2);
  assert.equal(raf.pre_engine.intervals, 140);
  assert.equal(raf.pre_engine.max_ms, 10000);
  assert.equal(raf.pre_engine.slow_frames_over_50_ms.length, 32);
  assert.equal(raf.pre_engine.rows_dropped, 108);
  assert.ok(raf.pre_engine.slow_frames_over_50_ms.every(row => row.phase === "pre_engine"));
  assert.equal(raf.intervals, 2);
  assert.equal(raf.max_ms, 2900);
  assert.equal(raf.rows_dropped, 0);
  assert.deepEqual(raf.whole_page, {intervals: 142, max_ms: 10000});
  assert.deepEqual(raf.slow_frames_over_50_ms.map(row => [row.start_ms, row.duration_ms,
    row.phase, row.crosses_engine_start, row.crosses_first_running]), [
    [1400000, 1500, "startup", true, false],
    [1401500, 2900, "after_first_running", false, true],
  ]);
});

test("runner startup and gameplay RAF rows have separate bounded reservations", () => {
  let clock = 0;
  const instance = harness(undefined, {now: () => clock});
  instance.context.__wwRunnerMark("engine_start");
  instance.frame(0);
  for (let index = 1; index <= 65; index++) instance.frame(index * 100);
  clock = 6500;
  instance.context.__wwRunnerMark("first_running");
  for (let index = 66; index <= 130; index++) instance.frame(index * 100);
  instance.context.__wwRunnerFail("test snapshot", "test_only");
  const raf = instance.posts[0].browser.request_animation_frame;
  assert.equal(raf.slow_frames_over_50_ms.length, 128);
  assert.equal(raf.rows_dropped, 2);
  assert.deepEqual(raf.phase_retention.startup, {limit: 64, retained: 64, dropped: 1});
  assert.deepEqual(raf.phase_retention.after_first_running, {limit: 64, retained: 64, dropped: 1});
  assert.equal(raf.slow_frames_over_50_ms[64].start_ms, 6500);
});

test("pre-engine feature failure keeps waiting evidence without inventing engine timing", () => {
  const instance = harness(undefined);
  instance.frame(0);
  instance.frame(2000);
  instance.context.__wwRunnerFail("feature failure", "engine_features");
  const raf = instance.posts[0].browser.request_animation_frame;
  assert.equal(raf.intervals, 0);
  assert.equal(raf.max_ms, 0);
  assert.equal(raf.slow_frames_over_50_ms.length, 0);
  assert.equal(raf.pre_engine.max_ms, 2000);
  assert.equal(raf.whole_page.max_ms, 2000);
});

test("lifecycle events retain repeated names in bounded performance-now order", () => {
  let clock = 10;
  const instance = harness(undefined, {now: () => clock});
  const oversizedKey = "k".repeat(80);
  const firstFields = {retry: false, path: "runner", nested: {not: "retained"},
    list: ["not", "retained"], invalid_number: Number.POSITIVE_INFINITY,
    [oversizedKey]: "x".repeat(300), null_value: null, count: 3, enabled: true,
    ninth_field_is_bounded_out: "ignored"};
  assert.equal(instance.context.__wwRunnerLifecycleEvent("runner_countdown_ready", firstFields), true);
  firstFields.path = "mutated-after-call";
  clock = 20;
  assert.equal(instance.context.__wwRunnerLifecycleEvent("runner_countdown_ready",
    {retry: true, path: "runner"}), true);
  assert.equal(instance.context.__wwRunnerLifecycleEvent("", {}), false);

  // Legacy keyed marks deliberately keep their existing latest-value contract.
  clock = 30; instance.context.__wwRunnerMark("operator_repeat");
  clock = 40; instance.context.__wwRunnerMark("operator_repeat");
  for (let index = 0; index < 128; index++) {
    clock = 50 + index;
    instance.context.__wwRunnerLifecycleEvent("extra", {index});
  }
  const saved = complete(instance);
  const events = saved.browser.lifecycle_events;
  assert.equal(events.limit, 128);
  assert.equal(events.seen, 130);
  assert.equal(events.rows.length, 128);
  assert.equal(events.dropped, 2);
  assert.equal(events.invalid, 1);
  assert.deepEqual(events.rows.slice(0, 2).map(row => [row.sequence, row.name, row.ms]), [
    [1, "runner_countdown_ready", 10], [2, "runner_countdown_ready", 20],
  ]);
  assert.deepEqual(events.rows[0].fields, {retry: false, path: "runner",
    ["k".repeat(64)]: "x".repeat(256), null_value: null, count: 3});
  assert.equal(Object.keys(events.rows[0].fields).length, 5);
  assert.deepEqual(events.rows[1].fields, {retry: true, path: "runner"});
  assert.equal(saved.browser.marks.operator_repeat, 40);
});

test("trusted input records queue and next-RAF latency without key or text data", () => {
  let clock = 500;
  const instance = harness(undefined, {now: () => clock});
  instance.emitDocument("pointerdown", {isTrusted: true, timeStamp: 480,
    target: {tagName: "CANVAS"}, clientX: 91, clientY: 72});
  instance.emitDocument("keydown", {isTrusted: false, timeStamp: 490,
    target: {tagName: "INPUT"}, key: "private", code: "KeyP"});
  instance.emitDocument("keydown", {isTrusted: 1, timeStamp: 495,
    target: {tagName: "INPUT"}, key: "private", code: "KeyP"});
  clock = 516;
  instance.frame(516);
  clock = 600;
  instance.emitDocument("keydown", {isTrusted: true, timeStamp: 590,
    target: {tagName: "BUTTON"}, key: "private", code: "KeyP"});
  clock = 616;
  instance.frame(616);

  clock = 700;
  for (let index = 0; index < 63; index++) {
    instance.emitDocument("pointerdown", {isTrusted: true, timeStamp: 699,
      target: {tagName: "CANVAS"}});
  }
  const saved = complete(instance);
  const input = saved.browser.trusted_input_latency;
  assert.equal(input.limit, 64);
  assert.equal(input.seen, 65);
  assert.equal(input.rows.length, 64);
  assert.equal(input.dropped, 1);
  assert.equal(input.untrusted_ignored, 2);
  assert.deepEqual(input.rows[0], {sequence: 1, event_type: "pointerdown",
    target_tag: "CANVAS", trusted: true, event_timestamp_ms: 480,
    handler_ms: 500, queue_delay_ms: 20, next_raf_ms: 516,
    handler_to_next_raf_ms: 16});
  assert.deepEqual(input.rows[1], {sequence: 2, event_type: "keydown",
    target_tag: "BUTTON", trusted: true, event_timestamp_ms: 590,
    handler_ms: 600, queue_delay_ms: 10, next_raf_ms: 616,
    handler_to_next_raf_ms: 16});
  for (const row of input.rows) {
    assert.deepEqual(Object.keys(row).sort(), ["event_timestamp_ms", "event_type", "handler_ms",
      "handler_to_next_raf_ms", "next_raf_ms", "queue_delay_ms", "sequence", "target_tag", "trusted"]);
    assert.equal(Object.hasOwn(row, "key"), false);
    assert.equal(Object.hasOwn(row, "code"), false);
    assert.equal(Object.hasOwn(row, "value"), false);
    assert.equal(Object.hasOwn(row, "coordinates"), false);
  }
});

test("trusted input pending RAF is cancelled and cannot mutate completed report", () => {
  let clock = 900;
  const instance = harness(undefined, {now: () => clock});
  instance.emitDocument("pointerdown", {isTrusted: true, timeStamp: 890,
    target: {tagName: "CANVAS"}});
  const saved = complete(instance);
  const row = saved.browser.trusted_input_latency.rows[0];
  assert.equal(saved.browser.trusted_input_latency.pending_raf_cancelled_at_finish, 1);
  assert.equal(row.next_raf_ms, null);
  assert.equal(row.handler_to_next_raf_ms, null);
  instance.frame(916);
  assert.equal(row.next_raf_ms, null);
  assert.equal(row.handler_to_next_raf_ms, null);
});

function setProductionSurface(instance, {layout = [1470, 827], backing = [2940, 1654], dpr = 2} = {}) {
  instance.context.document.documentElement.clientWidth = layout[0];
  instance.context.document.documentElement.clientHeight = layout[1];
  instance.context.innerWidth = layout[0];
  instance.context.innerHeight = layout[1];
  instance.context.devicePixelRatio = dpr;
  instance.canvas.clientWidth = layout[0];
  instance.canvas.clientHeight = layout[1];
  instance.canvas.width = backing[0];
  instance.canvas.height = backing[1];
}

test("production canvas reports reconciled native-size eligibility without claiming fixed PASS", async () => {
  const config = {run_id: "production-host-test", width: 1920, height: 1080,
    canvas_policy: "production", canvas_policy_source_sha256: "a".repeat(64),
    canvas_policy_fragment_sha256: "b".repeat(64)};
  const instance = harness(undefined, {runConfig: config});
  setProductionSurface(instance);
  const saved = complete(instance, {actual_window_size: [2940, 1654], resolution: [2940, 1654]});
  assert.equal(saved.report.meets_gate, false);
  assert.equal(saved.report.measurement_eligibility.eligible, true);
  assert.equal(saved.report.measurement_eligibility.native_size_workload_accepted, true);
  assert.equal(saved.report.measurement_eligibility.fixed_resolution_gate_applicable, false);
  assert.equal(saved.report.measurement_eligibility.complete_production, false);
  assert.equal(saved.browser.canvas_policy.fixed_resolution_gate_applicable, false);
  assert.equal(saved.browser.canvas_policy.complete_production, false);
  assert.equal(saved.browser.canvas_policy.native_size_workload_accepted, true);
  assert.deepEqual(saved.browser.canvas_policy.requested_probe_size, [1920, 1080]);
  assert.deepEqual(saved.browser.canvas_policy.samples.report.canvas_backing, [2940, 1654]);
  assert.deepEqual(saved.browser.canvas_policy.samples.report.layout_css, [1470, 827]);
  // The report is posted synchronously, but saved-status text follows the
  // awaited fetch response. Check that state only after the promise settles.
  await new Promise(resolve => setImmediate(resolve));
  assert.match(instance.status.textContent, /fixed-resolution gate N\/A/);
  assert.doesNotMatch(instance.status.textContent, /PASS/);
});

test("runner workload rejection is independent of passing timing thresholds", () => {
  for (const canvas_policy of ["fixed", "production"]) {
    const instance = harness(undefined, {runConfig: {run_id: "invalid-world-" + canvas_policy,
      width: 1920, height: 1080, canvas_policy}});
    if (canvas_policy === "production") setProductionSurface(instance);
    const saved = complete(instance, {actual_window_size: [2940, 1654], resolution: [2940, 1654],
      workload_valid: false, workload_validation: {captured: true, valid: false,
        reason: "invalid_runner_pose", invalid_pose_frames: 100,
        first_failure: {camera_position: [0, 1.1044764599608313e37, 1.3037546837383896e37]}}});
    assert.equal(saved.report.performance_thresholds_met, true, canvas_policy);
    assert.equal(saved.report.meets_gate, false, canvas_policy);
    assert.equal(saved.report.workload_valid, false, canvas_policy);
    assert.equal(saved.report.measurement_eligibility.eligible, false, canvas_policy);
    assert.equal(saved.report.measurement_eligibility.reason, "runner_workload_invalid", canvas_policy);
    assert.equal(saved.report.workload_validation.invalid_pose_frames, 100, canvas_policy);
    assert.ok(saved.report.workload_validation.first_failure.camera_position[1] > 1e30, canvas_policy);
  }
});

test("production workload checks fail closed for missing, contradictory, or uncaptured metadata", () => {
  const cases = [
    {workload_valid: undefined},
    {workload_validation: undefined},
    {workload_validation: {captured: false, valid: true}},
    {workload_validation: {captured: true, valid: false}},
    {measurement_eligibility: {workload_valid: false}},
  ];
  for (const [index, overrides] of cases.entries()) {
    const instance = harness(undefined, {runConfig: {run_id: "missing-world-" + index,
      width: 1920, height: 1080, canvas_policy: "production"}});
    setProductionSurface(instance);
    const saved = complete(instance, {actual_window_size: [2940, 1654], resolution: [2940, 1654], ...overrides});
    assert.equal(saved.report.measurement_eligibility.native_size_workload_accepted, false, String(index));
    assert.equal(saved.report.measurement_eligibility.workload_valid, false, String(index));
    assert.equal(saved.browser.canvas_policy.workload_valid, false, String(index));
    assert.equal(saved.report.performance_thresholds_met, true, String(index));
  }
});

test("valid workload remains independent of failed timing thresholds", () => {
  const instance = harness(undefined, {runConfig: {run_id: "valid-world-slow",
    width: 1920, height: 1080, canvas_policy: "production"}});
  setProductionSurface(instance);
  const saved = complete(instance, {actual_window_size: [2940, 1654], resolution: [2940, 1654],
    performance_thresholds_met: false});
  assert.equal(saved.report.workload_valid, true);
  assert.equal(saved.report.measurement_eligibility.workload_valid, true);
  assert.equal(saved.report.measurement_eligibility.eligible, false);
  assert.equal(saved.report.measurement_eligibility.reason, "performance_thresholds_not_met");
});

test("production canvas rejects zero or mismatched observed surfaces", () => {
  for (const [name, surface] of [["zero", {backing: [0, 0]}],
                                 ["mismatch", {backing: [1920, 1080]}]]) {
    const instance = harness(undefined, {runConfig: {run_id: "production-" + name,
      width: 1920, height: 1080, canvas_policy: "production"}});
    setProductionSurface(instance, surface);
    const saved = complete(instance, {actual_window_size: surface.backing, resolution: surface.backing});
    assert.equal(saved.report.meets_gate, false, name);
    assert.equal(saved.report.measurement_eligibility.eligible, false, name);
    assert.equal(saved.report.measurement_eligibility.native_size_workload_accepted, false, name);
    assert.equal(saved.report.measurement_eligibility.canvas_policy_reconciled, false, name);
    assert.equal(saved.browser.canvas_policy.native_size_workload_accepted, false, name);
    assert.doesNotMatch(instance.status.textContent, /PASS/, name);
  }
});

test("production canvas rejects zero or mismatched engine-reported dimensions", () => {
  for (const [name, engineSize] of [["zero", [0, 0]], ["mismatch", [1920, 1080]]]) {
    const instance = harness(undefined, {runConfig: {run_id: "production-engine-" + name,
      width: 1920, height: 1080, canvas_policy: "production"}});
    setProductionSurface(instance);
    const saved = complete(instance, {actual_window_size: engineSize, resolution: engineSize});
    assert.equal(saved.report.meets_gate, false, name);
    assert.equal(saved.report.measurement_eligibility.eligible, false, name);
    assert.equal(saved.report.measurement_eligibility.engine_window_matches_final_backing, false, name);
    assert.equal(saved.browser.canvas_policy.native_size_workload_accepted, false, name);
  }
});

test("production canvas rejects backing changes between first-running and report", () => {
  const instance = harness(undefined, {runConfig: {run_id: "production-endpoint-change",
    width: 1920, height: 1080, canvas_policy: "production"}});
  setProductionSurface(instance);
  instance.context.__wwRunnerMark("first_running");
  setProductionSurface(instance, {layout: [1400, 800], backing: [2800, 1600], dpr: 2});
  instance.context.__wwRunnerFinish({average_fps: 60, p95_frame_ms: 17, max_frame_ms: 20,
    performance_thresholds_met: true, actual_window_size: [2800, 1600], resolution: [2800, 1600],
    meets_gate: true}, "csv");
  const saved = instance.posts[0];
  assert.equal(saved.report.meets_gate, false);
  assert.equal(saved.report.measurement_eligibility.eligible, false);
  assert.equal(saved.report.measurement_eligibility.backing_stable_first_running_to_report, false);
});

test("manual diagnostic start uses an accessible static button hidden by default", () => {
  const button = shell.match(/<button\b[^>]*id="start-diagnostic"[^>]*>Start diagnostic<\/button>/)?.[0];
  assert.ok(button);
  assert.match(button, /\btype="button"/);
  assert.match(button, /\baria-describedby="status"/);
  assert.match(button, /\bhidden(?:\s|>)/);
});

test("app lifecycle snapshot uses a separate explicit button hidden by default", () => {
  const button = shell.match(/<button\b[^>]*id="capture-lifecycle"[^>]*>Save lifecycle snapshot<\/button>/)?.[0];
  assert.ok(button);
  assert.match(button, /\btype="button"/);
  assert.match(button, /\bhidden(?:\s|>)/);
});

test("app entry preserves normal UI and records only an explicit lifecycle snapshot", async () => {
  let starts = 0;
  class Engine {
    static getMissingFeatures() { return []; }
    startGame(options) {
      starts++;
      assert.equal(options.canvas, instance.canvas);
      assert.equal(options.canvasResizePolicy, 0);
      return Promise.resolve();
    }
  }
  const config = {run_id: "app-host-test", entry: "app", threads: false,
    canvas_policy: "production", width: 1920, height: 1080};
  const instance = harness(Engine, {runConfig: config});
  instance.boot();
  assert.equal(starts, 1);
  assert.equal(instance.posts.length, 0);
  assert.equal(instance.captureButton.hidden, true);
  await Promise.resolve();
  assert.equal(instance.status.hidden, true);
  assert.equal(instance.captureButton.hidden, false);
  assert.equal(instance.context.document.title, "Waddle Wars — app lifecycle diagnostic");

  instance.clickCapture();
  instance.clickCapture();
  assert.equal(instance.posts.length, 1);
  const saved = instance.posts[0];
  assert.equal(saved.kind, "app_lifecycle");
  assert.equal(saved.browser.entry, "app");
  assert.equal(saved.browser.marks.engine_start, 123);
  assert.equal(saved.browser.marks.engine_started, 123);
  assert.equal(saved.browser.marks.app_snapshot, 123);
  assert.deepEqual(Object.keys(saved.report).sort(), ["complete_production",
    "engine_fps_report_present", "measurement_kind", "meets_gate",
    "performance_gate_applicable", "schema_version", "scope"]);
  assert.equal(saved.report.measurement_kind, "app_lifecycle");
  assert.equal(saved.report.performance_gate_applicable, false);
  assert.equal(saved.report.engine_fps_report_present, false);
  assert.equal(saved.report.meets_gate, false);
  assert.equal(saved.report.complete_production, false);
  assert.equal(Object.hasOwn(saved, "csv"), false);
  assert.equal(instance.captureButton.hidden, true);
});

test("app entry rejects runner FPS callback instead of inventing a gate", async () => {
  class Engine {
    static getMissingFeatures() { return []; }
    startGame() { return Promise.resolve(); }
  }
  const instance = harness(Engine, {runConfig: {run_id: "app-contract-test",
    entry: "app", canvas_policy: "production"}});
  instance.boot();
  await Promise.resolve();
  instance.context.__wwRunnerFinish({average_fps: 60, meets_gate: true}, "fps\n60\n");
  assert.equal(instance.posts.length, 1);
  assert.equal(instance.posts[0].kind, "app_lifecycle");
  assert.equal(instance.posts[0].error_source, "entry_contract");
  assert.equal(Object.hasOwn(instance.posts[0], "report"), false);
  assert.equal(Object.hasOwn(instance.posts[0], "csv"), false);
});

test("automatic start remains default unless manualstart is exactly 1", () => {
  for (const search of ["", "?manualstart=0", "?manualstart=true", "?manualstart=01"]) {
    let starts = 0;
    class Engine {
      static getMissingFeatures() { return []; }
      startGame(options) {
        starts++;
        assert.equal(options.canvasResizePolicy, 0);
        assert.equal(options.canvas, instance.canvas);
        assert.equal(typeof options.onExit, "function");
        return Promise.resolve();
      }
    }
    const instance = harness(Engine, {search});
    instance.boot();
    assert.equal(starts, 1);
    assert.equal(instance.startButton.hidden, true);
    const saved = complete(instance);
    assert.equal(saved.browser.manual_start, false);
    assert.equal(saved.browser.marks.engine_start, 123);
  }
});

test("manual start waits for click, starts once, and records actual query opt-in", () => {
  let starts = 0, clock = 123;
  const config = {run_id: "manual-host-test", threads: false, tier: "high", seed: 20260907};
  class Engine {
    static getMissingFeatures() { return []; }
    startGame(options) {
      starts++;
      assert.equal(options.canvas, instance.canvas);
      assert.equal(options.canvasResizePolicy, 0);
      assert.deepEqual(Object.keys(options).sort(), ["canvas", "canvasResizePolicy", "onExit"]);
      return Promise.resolve();
    }
  }
  const instance = harness(Engine, {search: "?manualstart=1&shadertrace=1", runConfig: config, now: () => clock});
  instance.boot();
  assert.equal(starts, 0);
  assert.equal(instance.startButton.hidden, false);
  assert.equal(instance.startButton.disabled, false);
  assert.match(instance.status.textContent, /attach trace/);
  assert.equal(vm.runInContext("marks.engine_start", instance.context), undefined);
  clock = 1000;
  instance.clickStart();
  instance.clickStart();
  assert.equal(starts, 1);
  assert.equal(instance.startButton.hidden, true);
  assert.equal(instance.startButton.disabled, true);
  const saved = complete(instance);
  assert.equal(saved.browser.manual_start, true);
  assert.equal(saved.browser.marks.engine_start, 1000);
  assert.equal(saved.browser.shader_trace.requested, true);
  assert.equal(saved.run_id, config.run_id);
  assert.deepEqual(JSON.parse(vm.runInContext("JSON.stringify(runConfig)", instance.context)), config);
});

test("manual startup rejection stays fatal and cannot retry from another click", async () => {
  let starts = 0;
  class Engine {
    static getMissingFeatures() { return []; }
    startGame() { starts++; return Promise.reject(new Error("Manual WASM boot failed")); }
  }
  const instance = harness(Engine, {search: "?manualstart=1"});
  instance.boot();
  instance.clickStart();
  await Promise.resolve();
  instance.clickStart();
  assert.equal(starts, 1);
  assert.equal(instance.posts.length, 1);
  assert.equal(instance.posts[0].error_source, "engine_start");
  assert.match(instance.posts[0].error, /Manual WASM boot failed/);
  assert.equal(instance.posts[0].browser.manual_start, true);
});

test("manual startup synchronous throw and engine exit keep existing error attribution", () => {
  for (const failure of ["throw", "exit"]) {
    class Engine {
      static getMissingFeatures() { return []; }
      startGame(options) {
        if (failure === "throw") throw new Error("Manual synchronous failure");
        options.onExit(2);
        return Promise.resolve();
      }
    }
    const instance = harness(Engine, {search: "?manualstart=1"});
    instance.boot();
    instance.clickStart();
    assert.equal(instance.posts[0].error_source, failure === "throw" ? "engine_bootstrap" : "engine_exit");
    assert.equal(instance.posts[0].browser.manual_start, true);
    assert.equal(instance.startButton.disabled, true);
  }
});

test("manual start still rejects missing features before offering a button", () => {
  for (const threads of [false, true]) {
    let starts = 0;
    class Engine {
      static getMissingFeatures(options) {
        assert.equal(options.threads, threads);
        return ["Unavailable feature"];
      }
      startGame() { starts++; return Promise.resolve(); }
    }
    const instance = harness(Engine, {search: "?manualstart=1", runConfig: {run_id: "host-test", threads}});
    instance.boot();
    instance.clickStart();
    assert.equal(starts, 0);
    assert.equal(instance.startButton.hidden, true);
    assert.equal(instance.posts[0].error_source, "engine_features");
    assert.equal(instance.posts[0].browser.manual_start, true);
    assert.equal(Object.hasOwn(instance.posts[0].browser.marks, "engine_start"), false);
  }
});

test("fatal engine error before manual click prevents later startup", () => {
  for (const beforeBoot of [false, true]) {
    let starts = 0;
    class Engine {
      static getMissingFeatures() { return []; }
      startGame() { starts++; return Promise.resolve(); }
    }
    const instance = harness(Engine, {search: "?manualstart=1"});
    if (!beforeBoot) instance.boot();
    instance.emit("error", {filename: "http://127.0.0.1:4321/index.js", message: "Failed before start"});
    if (beforeBoot) instance.boot();
    instance.clickStart();
    assert.equal(starts, 0);
    assert.equal(instance.posts.length, 1);
    assert.equal(instance.posts[0].error_source, "owned_engine_script_error");
    assert.equal(instance.startButton.hidden, true);
    assert.equal(instance.startButton.disabled, true);
  }
});

test("extension rejection stays diagnostic; successful probe can still complete", () => {
  const instance = harness();
  const reason = new Error("i: Failed to connect to MetaMask");
  reason.stack = "Error: Failed to connect\n at chrome-extension://example/inpage.js:1:20";
  instance.emit("unhandledrejection", {reason});
  assert.equal(instance.posts.length, 0);
  assert.equal(instance.context.__wwRunnerResult, undefined);
  const saved = complete(instance);
  assert.equal(saved.report.meets_gate, true);
  assert.equal(saved.browser.page_errors.rows[0].classification, "extension");
  assert.equal(saved.browser.marks.first_running, 123);
});

test("unattributed rejections remain nonfatal and explicitly bounded", () => {
  const instance = harness();
  for (let index = 0; index < 40; index++) {
    instance.emit("unhandledrejection", {reason: "x".repeat(1000)});
  }
  assert.equal(instance.posts.length, 0);
  const errors = complete(instance).browser.page_errors;
  assert.equal(errors.rows.length, 32);
  assert.equal(errors.dropped, 8);
  assert.equal(errors.rows[0].message.length, 500);
  assert.equal(errors.rows[0].message_truncated, true);
  assert.equal(errors.rows[0].classification, "unattributed");
});

test("extension and unrelated script errors do not finish the probe", () => {
  const instance = harness();
  instance.emit("error", {filename: "chrome-extension://example/inpage.js", message: "Extension failure"});
  instance.emit("error", {filename: "http://127.0.0.1:4321/unrelated.js", message: "Other script"});
  instance.emit("error", {filename: "", message: "Script error."});
  assert.equal(instance.posts.length, 0);
  assert.equal(complete(instance).browser.page_errors.rows.length, 3);
});

test("known engine script errors remain fatal", () => {
  const instance = harness();
  instance.emit("error", {filename: "http://127.0.0.1:4321/index.js", message: "Engine runtime failure"});
  assert.equal(instance.posts[0].error, "Engine runtime failure");
  assert.equal(instance.posts[0].error_source, "owned_engine_script_error");
});

test("extension frame prevents engine-filename-only attribution", () => {
  const instance = harness();
  instance.emit("error", {filename: "http://127.0.0.1:4321/index.js", message: "Injected failure",
    error: {stack: "chrome-extension://example/inpage.js:1:20"}});
  assert.equal(instance.posts.length, 0);
  assert.equal(complete(instance).browser.page_errors.rows[0].classification, "extension");
});

test("engine startup rejection remains fatal", async () => {
  class Engine {
    static getMissingFeatures() { return []; }
    startGame() { return Promise.reject(new Error("WASM boot failed")); }
  }
  const instance = harness(Engine);
  instance.boot();
  await Promise.resolve();
  assert.equal(instance.posts[0].error_source, "engine_start");
  assert.match(instance.posts[0].error, /WASM boot failed/);
});

test("engine feature checks match explicit thread mode and preserve the old default", () => {
  for (const threads of [undefined, false, true]) {
    const operations = [];
    class Engine {
      static getMissingFeatures(options) {
        assert.deepEqual(Object.keys(options), ["threads"]);
        assert.equal(options.threads, threads === true);
        operations.push("features");
        return [];
      }
      startGame() {
        operations.push("start");
        return Promise.resolve();
      }
    }
    const runConfig = {run_id: "host-test"};
    if (threads !== undefined) runConfig.threads = threads;
    const instance = harness(Engine, {runConfig});
    instance.boot();
    assert.deepEqual(operations, ["features", "start"]);
    assert.equal(complete(instance).browser.threads_requested, threads === true);
  }
});

test("missing engine features reject both modes without starting or writing a success report", () => {
  for (const threads of [false, true]) {
    const missing = threads ? ["Cross-Origin Isolation", "SharedArrayBuffer"] : ["WebGL2"];
    let starts = 0;
    class Engine {
      static getMissingFeatures(options) {
        assert.equal(options.threads, threads);
        return missing;
      }
      startGame() { starts++; return Promise.resolve(); }
    }
    const instance = harness(Engine, {runConfig: {run_id: "host-test", threads}});
    instance.boot();
    assert.equal(starts, 0);
    assert.equal(instance.posts.length, 1);
    const saved = instance.posts[0];
    assert.equal(saved.error_source, "engine_features");
    assert.equal(saved.error, "Missing browser features: " + missing.join(", "));
    assert.equal(saved.browser.threads_requested, threads);
    assert.equal(Object.hasOwn(saved.browser.marks, "engine_start"), false);
    assert.equal(Object.hasOwn(saved, "report"), false);
    assert.equal(Object.hasOwn(saved, "csv"), false);
    complete(instance);
    assert.equal(instance.posts.length, 1, "later success must not replace missing-feature rejection");
  }
});

test("engine exit without report remains fatal", () => {
  class Engine {
    static getMissingFeatures() { return []; }
    startGame(options) { options.onExit(2); return Promise.resolve(); }
  }
  const instance = harness(Engine);
  instance.boot();
  assert.equal(instance.posts[0].error_source, "engine_exit");
});

test("bootstrap throw and explicit Godot abort remain fatal", () => {
  const bootstrap = harness(class Engine { constructor() { throw new Error("Missing engine config"); } });
  bootstrap.boot();
  assert.equal(bootstrap.posts[0].error_source, "engine_bootstrap");
  const godot = harness();
  godot.context.__wwRunnerFail("runner ended before performance sample completed");
  assert.equal(godot.posts[0].error_source, "godot_probe");
});

test("fatal abort preserves incomplete sample diagnostics without a success report", () => {
  const instance = harness();
  const diagnostics = {incomplete_sample: true, gate_evaluated: false,
    requested_sample_seconds: 100, sample_seconds: 60, sample_frames: 3500,
    average_frame_ms: 17, p95_frame_ms: 20, max_frame_ms: 160,
    slow_frames_over_50_ms: [{frame_ms: 160}], stream_trace: {events: [{id: 1}]},
    runner_state: {state_name: "DEAD", hits_left: 0, distance: 1400, biome: 2}};
  instance.context.__wwRunnerFail("runner ended before performance sample completed", "godot_abort", diagnostics);
  const saved = instance.posts[0];
  assert.equal(saved.error_source, "godot_abort");
  assert.deepEqual(saved.diagnostics, diagnostics);
  assert.equal(Object.hasOwn(saved, "report"), false);
  assert.equal(Object.hasOwn(saved, "csv"), false);
  assert.equal(Object.hasOwn(saved.diagnostics, "meets_gate"), false);
  complete(instance);
  assert.equal(instance.posts.length, 1, "later completion must not replace fatal abort evidence");
});

test("failure without diagnostic object preserves existing payload shape", () => {
  const instance = harness();
  instance.context.__wwRunnerFail("Engine failed", "engine_exit", "not an object");
  assert.equal(instance.posts[0].error_source, "engine_exit");
  assert.equal(Object.hasOwn(instance.posts[0], "diagnostics"), false);
});

function presentationHarness(search = "?presentationtrace=1") {
  let clock = 100;
  let timerReads = 0;
  const invocations = [];
  class WebGL2RenderingContext {
    getParameter(...args) {
      invocations.push({name: "getParameter", receiver: this, args});
      clock += this.duration;
      if (this.failure !== undefined) throw this.failure;
      return this.result;
    }
    blitFramebuffer(...args) {
      invocations.push({name: "blitFramebuffer", receiver: this, args});
      clock += this.duration;
      if (this.failure !== undefined) throw this.failure;
      return this.result;
    }
    compileShader(...args) {
      invocations.push({name: "compileShader", receiver: this, args});
      clock += this.duration;
      return this.result;
    }
  }
  const originals = Object.fromEntries(["getParameter", "blitFramebuffer", "compileShader"]
    .map(name => [name, WebGL2RenderingContext.prototype[name]]));
  const instance = harness(undefined, {search, WebGL2RenderingContext,
    now: () => { timerReads++; return clock; }});
  return {...instance, WebGL2RenderingContext, originals, invocations,
    timerReads: () => timerReads, clock: () => clock};
}

test("presentation trace defaults off and only exact opt-in wraps methods", () => {
  for (const search of ["", "?presentationtrace=0", "?presentationtrace=true", "?presentationtrace=01"]) {
    const instance = presentationHarness(search);
    for (const [name, original] of Object.entries(instance.originals)) {
      assert.equal(instance.WebGL2RenderingContext.prototype[name], original);
    }
    const trace = complete(instance).browser.presentation_trace;
    assert.equal(trace.enabled, false);
    assert.deepEqual(trace.calls, {});
    assert.deepEqual(trace.slow_calls, []);
  }
});

test("presentation trace forwards every argument, receiver and exact result without caching", () => {
  const instance = presentationHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  assert.notEqual(proto.getParameter, instance.originals.getParameter);
  assert.notEqual(proto.blitFramebuffer, instance.originals.blitFramebuffer);
  assert.equal(proto.compileShader, instance.originals.compileShader);
  const extra = {privateArgument: true};
  const receiver = {duration: 9, result: {privateFramebuffer: true}};
  const firstResult = receiver.result;
  assert.equal(Reflect.apply(proto.getParameter, receiver, [36006, extra]), firstResult);
  receiver.result = false;
  assert.equal(Reflect.apply(proto.getParameter, receiver, [3089]), false);
  receiver.result = {differentFramebuffer: true};
  assert.equal(Reflect.apply(proto.getParameter, receiver, [36006]), receiver.result);
  const blitArgs = [0, 1, 2, 3, 4, 5, 6, 7, 16384, 9728, extra];
  receiver.result = undefined;
  assert.equal(Reflect.apply(proto.blitFramebuffer, receiver, blitArgs), undefined);
  assert.equal(instance.invocations.length, 4);
  assert.ok(instance.invocations.every(call => call.receiver === receiver));
  assert.deepEqual(instance.invocations[0].args, [36006, extra]);
  assert.deepEqual(instance.invocations[3].args, blitArgs);
  const trace = complete(instance).browser.presentation_trace;
  assert.deepEqual(trace.calls["getParameter:36006"],
    {count: 2, total_wall_ms: 18, max_wall_ms: 9, over_threshold: 2});
  assert.equal(trace.calls["getParameter:3089"].count, 1);
  assert.equal(trace.calls.blitFramebuffer.count, 1);
  assert.deepEqual(Object.keys(trace.slow_calls[0]).sort(),
    ["duration_ms", "name", "phase", "query_enum", "start_ms"]);
  assert.deepEqual(Object.keys(trace.slow_calls[3]).sort(),
    ["duration_ms", "name", "phase", "start_ms"]);
  assert.ok(!JSON.stringify(trace).includes("privateFramebuffer"));
  assert.ok(!JSON.stringify(trace).includes("privateArgument"));
});

test("presentation trace ignores other query enums without coercion or timer reads", () => {
  const instance = presentationHarness();
  const getParameter = instance.WebGL2RenderingContext.prototype.getParameter;
  const receiver = {duration: 20, result: {unchanged: true}};
  const numericObject = {valueOf() { throw new Error("must not coerce diagnostic arguments"); }};
  const reads = instance.timerReads();
  for (const query of [37445, "3089", "36006", numericObject, undefined, null]) {
    assert.equal(Reflect.apply(getParameter, receiver, [query]), receiver.result);
    assert.equal(instance.invocations.at(-1).args[0], query);
  }
  assert.equal(instance.timerReads(), reads);
  const trace = complete(instance).browser.presentation_trace;
  assert.ok(Object.values(trace.calls).every(call => call.count === 0));
  assert.equal(trace.slow_calls.length, 0);
});

test("presentation trace preserves exact thrown values and still measures the call", () => {
  const instance = presentationHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  for (const [name, args, failure] of [
    ["getParameter", [3089], new Error("native query failed")],
    ["blitFramebuffer", [0, 1, 2], {nativeFailure: true}],
  ]) {
    const receiver = {duration: 12, failure};
    assert.throws(() => Reflect.apply(proto[name], receiver, args), error => error === failure);
    assert.equal(instance.invocations.at(-1).receiver, receiver);
    assert.deepEqual(instance.invocations.at(-1).args, args);
  }
  const trace = complete(instance).browser.presentation_trace;
  assert.equal(trace.calls["getParameter:3089"].total_wall_ms, 12);
  assert.equal(trace.calls.blitFramebuffer.total_wall_ms, 12);
  assert.equal(trace.slow_calls.length, 2);
  assert.ok(!JSON.stringify(trace).includes("native query failed"));
  assert.ok(!JSON.stringify(trace).includes("nativeFailure"));
});

test("presentation trace includes threshold equality, bounds rows and retains phase/count totals", () => {
  const instance = presentationHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  const receiver = {duration: 7.5};
  const fastStart = instance.clock();
  Reflect.apply(proto.getParameter, receiver, [3089]);
  receiver.duration = 8;
  Reflect.apply(proto.getParameter, receiver, [3089]);
  instance.context.__wwRunnerMark("first_running");
  receiver.duration = 9;
  for (let index = 0; index < 129; index++) {
    Reflect.apply(proto.blitFramebuffer, receiver, [index]);
  }
  const trace = complete(instance).browser.presentation_trace;
  assert.equal(trace.limit, 128);
  assert.equal(trace.slow_calls.length, 128);
  assert.equal(trace.dropped, 2);
  assert.deepEqual(trace.calls["getParameter:3089"],
    {count: 2, total_wall_ms: 15.5, max_wall_ms: 8, over_threshold: 1});
  assert.deepEqual(trace.calls.blitFramebuffer,
    {count: 129, total_wall_ms: 1161, max_wall_ms: 9, over_threshold: 129});
  assert.equal(trace.slow_calls[0].start_ms, fastStart + 7.5);
  assert.equal(trace.slow_calls[0].duration_ms, 8);
  assert.equal(trace.slow_calls[0].query_enum, 3089);
  assert.equal(trace.slow_calls[0].phase, "startup");
  assert.ok(trace.slow_calls.slice(1).every(row => row.phase === "after_first_running"));
});

test("presentation trace reports missing WebGL methods without breaking report completion", () => {
  const missingContext = harness(undefined, {search: "?presentationtrace=1"});
  assert.deepEqual(complete(missingContext).browser.presentation_trace.unavailable,
    ["getParameter", "blitFramebuffer"]);
  class PartialContext { getParameter() { return false; } }
  const partial = harness(undefined, {search: "?presentationtrace=1", WebGL2RenderingContext: PartialContext});
  const trace = complete(partial).browser.presentation_trace;
  assert.deepEqual(trace.unavailable, ["blitFramebuffer"]);
  assert.deepEqual(Object.keys(trace.calls), ["getParameter:3089", "getParameter:36006"]);
});

test("presentation trace stays separate from existing webgltrace instrumentation", () => {
  const glOnly = presentationHarness("?webgltrace=1");
  const glProto = glOnly.WebGL2RenderingContext.prototype;
  assert.equal(glProto.getParameter, glOnly.originals.getParameter);
  assert.equal(glProto.blitFramebuffer, glOnly.originals.blitFramebuffer);
  assert.notEqual(glProto.compileShader, glOnly.originals.compileShader);
  const glReport = complete(glOnly).browser;
  assert.equal(glReport.webgl_trace.enabled, true);
  assert.equal(glReport.presentation_trace.enabled, false);

  const both = presentationHarness("?webgltrace=1&presentationtrace=1");
  const bothProto = both.WebGL2RenderingContext.prototype;
  const receiver = {duration: 10, result: true};
  Reflect.apply(bothProto.compileShader, receiver, [{}]);
  Reflect.apply(bothProto.getParameter, receiver, [3089]);
  const bothReport = complete(both).browser;
  assert.equal(bothReport.webgl_trace.calls.compileShader.count, 1);
  assert.equal(bothReport.webgl_trace.slow_calls.length, 1);
  assert.equal(bothReport.presentation_trace.calls["getParameter:3089"].count, 1);
  assert.equal(bothReport.presentation_trace.slow_calls.length, 1);
  assert.equal(Object.hasOwn(bothReport.webgl_trace.calls, "getParameter"), false);
  assert.equal(Object.hasOwn(bothReport.presentation_trace.calls, "compileShader"), false);
});

const renderMethods = ["drawArrays", "drawElements", "drawArraysInstanced", "drawElementsInstanced",
  "bufferSubData", "texSubImage2D", "bindFramebuffer", "clientWaitSync", "finish", "flush"];

function renderHarness(search = "?rendertrace=1") {
  let clock = 100;
  let timerReads = 0;
  const invocations = [];
  class WebGL2RenderingContext {}
  for (const name of [...renderMethods, "getParameter", "blitFramebuffer", "compileShader"]) {
    WebGL2RenderingContext.prototype[name] = function (...args) {
      invocations.push({name, receiver: this, args});
      clock += this.duration;
      if (this.onInvoke) this.onInvoke();
      if (this.shouldThrow) throw this.failure;
      return this.result;
    };
  }
  const originals = {...WebGL2RenderingContext.prototype};
  const instance = harness(undefined, {search, WebGL2RenderingContext,
    now: () => { timerReads++; return clock; }});
  return {...instance, WebGL2RenderingContext, originals, invocations,
    timerReads: () => timerReads, clock: () => clock};
}

test("render trace defaults off and only exact opt-in wraps its ten methods", () => {
  for (const search of ["", "?rendertrace=0", "?rendertrace=true", "?rendertrace=01"]) {
    const instance = renderHarness(search);
    for (const [name, original] of Object.entries(instance.originals)) {
      assert.equal(instance.WebGL2RenderingContext.prototype[name], original);
    }
    const reads = instance.timerReads();
    Reflect.apply(instance.WebGL2RenderingContext.prototype.finish, {duration: 100}, []);
    assert.equal(instance.timerReads(), reads);
    const trace = complete(instance).browser.render_trace;
    assert.equal(trace.enabled, false);
    assert.deepEqual(trace.calls, {});
    assert.deepEqual(trace.slow_calls, []);
  }
  const enabled = renderHarness();
  for (const name of renderMethods) {
    assert.notEqual(enabled.WebGL2RenderingContext.prototype[name], enabled.originals[name]);
  }
  for (const name of ["getParameter", "blitFramebuffer", "compileShader"]) {
    assert.equal(enabled.WebGL2RenderingContext.prototype[name], enabled.originals[name]);
  }
  assert.equal(enabled.invocations.length, 0, "installation must not issue any GL call");
});

test("render trace forwards exact this, arguments and changed results without extra GL calls", () => {
  const instance = renderHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  const buffer = new Uint8Array([73, 19, 201]);
  const opaque = {privateBuffer: "not recorded", valueOf() { throw new Error("do not coerce"); }};
  const results = [undefined, false, 37146, {privateReturn: "not recorded"}];
  for (const [index, name] of renderMethods.entries()) {
    const args = [opaque, buffer, index, undefined];
    const receiver = {duration: 8, result: results[index % results.length]};
    assert.equal(Reflect.apply(proto[name], receiver, args), receiver.result);
    assert.equal(instance.invocations.at(-1).receiver, receiver);
    assert.deepEqual(instance.invocations.at(-1).args, args);
    receiver.result = {freshResult: true};
    assert.equal(Reflect.apply(proto[name], receiver, []), receiver.result);
    assert.deepEqual(instance.invocations.at(-1).args, []);
  }
  assert.equal(instance.invocations.length, renderMethods.length * 2);
  const trace = complete(instance).browser.render_trace;
  assert.deepEqual(Object.keys(trace.calls), renderMethods);
  assert.equal(instance.invocations.length, renderMethods.length * 2, "report must not issue GL calls");
  for (const name of renderMethods) {
    assert.equal(trace.calls[name].count, 2);
    assert.equal(trace.calls[name].total_wall_ms, 16);
    assert.equal(trace.calls[name].by_phase.startup.count, 2);
    assert.equal(trace.calls[name].by_phase.after_first_running.count, 0);
  }
  for (const row of trace.slow_calls) {
    assert.deepEqual(Object.keys(row).sort(), ["duration_ms", "name", "phase", "start_ms"]);
  }
  for (const privateValue of ["privateBuffer", "privateReturn", "freshResult", "37146"]) {
    assert.ok(!JSON.stringify(trace).includes(privateValue));
  }
});

test("render trace preserves thrown values for every method and records only timing", () => {
  const instance = renderHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  const failures = [new Error("private native error"), {privateFailure: true}, undefined, null];
  for (const [index, name] of renderMethods.entries()) {
    const failure = failures[index % failures.length];
    const receiver = {duration: 9, shouldThrow: true, failure};
    let threw = false;
    try { Reflect.apply(proto[name], receiver, [index]); }
    catch (error) { threw = true; assert.equal(error, failure); }
    assert.equal(threw, true, name + " must rethrow exact original value");
    assert.equal(instance.invocations.at(-1).receiver, receiver);
    assert.deepEqual(instance.invocations.at(-1).args, [index]);
  }
  const trace = complete(instance).browser.render_trace;
  assert.equal(trace.slow_calls.length, renderMethods.length);
  for (const name of renderMethods) {
    assert.equal(trace.calls[name].count, 1);
    assert.equal(trace.calls[name].total_wall_ms, 9);
    assert.equal(trace.calls[name].over_threshold, 1);
  }
  assert.ok(!JSON.stringify(trace).includes("private native error"));
  assert.ok(!JSON.stringify(trace).includes("privateFailure"));
});

test("render trace keeps bounded slow spans and exact startup/running aggregates", () => {
  const instance = renderHarness();
  const drawArrays = instance.WebGL2RenderingContext.prototype.drawArrays;
  const receiver = {duration: 7.5};
  const fastStart = instance.clock();
  Reflect.apply(drawArrays, receiver, []);
  receiver.duration = 8;
  Reflect.apply(drawArrays, receiver, []);
  instance.context.__wwRunnerMark("first_running");
  receiver.duration = 9;
  for (let index = 0; index < 129; index++) Reflect.apply(drawArrays, receiver, []);
  const trace = complete(instance).browser.render_trace;
  assert.equal(trace.threshold_ms, 8);
  assert.equal(trace.limit, 128);
  assert.equal(trace.slow_calls.length, 128);
  assert.equal(trace.dropped, 2);
  assert.deepEqual(trace.calls.drawArrays, {count: 131, total_wall_ms: 1176.5,
    max_wall_ms: 9, over_threshold: 130, by_phase: {
      startup: {count: 2, total_wall_ms: 15.5, max_wall_ms: 8, over_threshold: 1},
      after_first_running: {count: 129, total_wall_ms: 1161, max_wall_ms: 9, over_threshold: 129},
    }});
  assert.equal(trace.slow_calls[0].start_ms, fastStart + 7.5);
  assert.equal(trace.slow_calls[0].duration_ms, 8);
  assert.equal(trace.slow_calls[0].phase, "startup");
  assert.ok(trace.slow_calls.slice(1).every(row => row.phase === "after_first_running"));
  assert.deepEqual(Object.keys(trace.calls.drawArrays.by_phase), ["startup", "after_first_running"]);
});

test("render trace phase is captured at call start even if GO is marked inside the call", () => {
  const instance = renderHarness();
  const receiver = {duration: 10, onInvoke: () => instance.context.__wwRunnerMark("first_running")};
  Reflect.apply(instance.WebGL2RenderingContext.prototype.drawElements, receiver, []);
  receiver.onInvoke = undefined;
  Reflect.apply(instance.WebGL2RenderingContext.prototype.drawElements, receiver, []);
  const trace = complete(instance).browser.render_trace;
  assert.deepEqual(trace.slow_calls.map(row => row.phase), ["startup", "after_first_running"]);
  assert.equal(trace.calls.drawElements.by_phase.startup.total_wall_ms, 10);
  assert.equal(trace.calls.drawElements.by_phase.after_first_running.total_wall_ms, 10);
});

test("render trace reports unavailable methods without attempting GL calls", () => {
  const missing = harness(undefined, {search: "?rendertrace=1"});
  assert.deepEqual(complete(missing).browser.render_trace.unavailable, renderMethods);
  let calls = 0;
  class PartialContext { finish() { calls++; } }
  const partial = harness(undefined, {search: "?rendertrace=1", WebGL2RenderingContext: PartialContext});
  const trace = complete(partial).browser.render_trace;
  assert.equal(calls, 0);
  assert.deepEqual(trace.unavailable, renderMethods.filter(name => name !== "finish"));
  assert.deepEqual(Object.keys(trace.calls), ["finish"]);
});

test("render trace stays independent while all three diagnostic flags coexist", () => {
  const priorOnly = renderHarness("?webgltrace=1&presentationtrace=1");
  for (const name of renderMethods) {
    assert.equal(priorOnly.WebGL2RenderingContext.prototype[name], priorOnly.originals[name]);
  }
  assert.equal(complete(priorOnly).browser.render_trace.enabled, false);
  const all = renderHarness("?webgltrace=1&presentationtrace=1&rendertrace=1");
  const proto = all.WebGL2RenderingContext.prototype;
  const receiver = {duration: 10, result: true};
  Reflect.apply(proto.compileShader, receiver, [{}]);
  Reflect.apply(proto.getParameter, receiver, [3089]);
  Reflect.apply(proto.blitFramebuffer, receiver, []);
  Reflect.apply(proto.flush, receiver, []);
  const report = complete(all).browser;
  assert.equal(report.webgl_trace.calls.compileShader.count, 1);
  assert.equal(report.webgl_trace.slow_calls.length, 1);
  assert.equal(report.presentation_trace.calls["getParameter:3089"].count, 1);
  assert.equal(report.presentation_trace.calls.blitFramebuffer.count, 1);
  assert.equal(report.presentation_trace.slow_calls.length, 2);
  assert.equal(report.render_trace.calls.flush.count, 1);
  assert.equal(report.render_trace.slow_calls.length, 1);
  assert.equal(Object.hasOwn(report.webgl_trace.calls, "flush"), false);
  assert.equal(Object.hasOwn(report.presentation_trace.calls, "flush"), false);
  assert.equal(Object.hasOwn(report.render_trace.calls, "compileShader"), false);
  assert.equal(Object.hasOwn(report.render_trace.calls, "getParameter"), false);
  assert.equal(all.invocations.length, 4);
});

const allTraceOwnMethods = [...renderMethods, "getParameter", "blitFramebuffer", "compileShader",
  "uniform1i", "useProgram", "bindVertexArray", "getError", "readPixels", "getBufferSubData",
  "fenceSync", "checkFramebufferStatus", "futureNativeMethod"];
const allTraceInheritedMethods = ["texImage2D", "getShaderPrecisionFormat", "uniformMatrix4fv",
  "futureInheritedNativeMethod"];

function allTraceHarness(search = "?glalltrace=1") {
  let clock = 100, timerReads = 0, getterReads = 0;
  const invocations = [];
  class WebGLBaseContext {}
  class WebGL2RenderingContext extends WebGLBaseContext {}
  const ownSymbol = Symbol("ownNative"), inheritedSymbol = Symbol("inheritedNative");
  const install = (proto, key) => {
    Object.defineProperty(proto, key, {configurable: true, writable: true, enumerable: false,
      value: function (...args) {
        invocations.push({key, receiver: this, args});
        clock += this?.duration ?? 0;
        if (this?.onInvoke) this.onInvoke();
        if (this?.shouldThrow) throw this.failure;
        return this?.result;
      }});
  };
  for (const key of [...allTraceOwnMethods, ownSymbol]) install(WebGL2RenderingContext.prototype, key);
  for (const key of [...allTraceInheritedMethods, inheritedSymbol, "shadowedMethod"]) {
    install(WebGLBaseContext.prototype, key);
  }
  Object.defineProperty(WebGL2RenderingContext.prototype, "shadowedMethod", {value: 17});
  Object.defineProperty(WebGLBaseContext.prototype, "opaqueGetter", {
    get() { getterReads++; throw new Error("discovery must never invoke getters"); }});
  Object.defineProperty(WebGL2RenderingContext.prototype, "CONSTANT", {value: 1234});
  const keys = [...allTraceOwnMethods, ownSymbol, ...allTraceInheritedMethods, inheritedSymbol];
  const originals = new Map(keys.map(key => [key, WebGL2RenderingContext.prototype[key]]));
  const baseOriginals = new Map([...allTraceInheritedMethods, inheritedSymbol]
    .map(key => [key, WebGLBaseContext.prototype[key]]));
  const instance = harness(undefined, {search, WebGL2RenderingContext,
    now: () => { timerReads++; return clock; }});
  return {...instance, WebGL2RenderingContext, WebGLBaseContext, keys, originals, baseOriginals,
    invocations, getterReads: () => getterReads, timerReads: () => timerReads, clock: () => clock};
}

test("all-GL trace defaults off with no prototype changes or per-call overhead", () => {
  for (const search of ["", "?glalltrace=0", "?glalltrace=true", "?glalltrace=01"]) {
    const instance = allTraceHarness(search);
    const proto = instance.WebGL2RenderingContext.prototype;
    for (const [key, original] of instance.originals) assert.equal(proto[key], original);
    const reads = instance.timerReads();
    Reflect.apply(proto.useProgram, {duration: 100}, []);
    assert.equal(instance.timerReads(), reads);
    assert.equal(instance.getterReads(), 0);
    const trace = complete(instance).browser.gl_all_trace;
    assert.equal(trace.requested, false);
    assert.equal(trace.enabled, false);
    assert.equal(trace.status, "disabled");
    assert.deepEqual(trace.calls, {});
    assert.deepEqual(trace.discovered_names, []);
    assert.deepEqual(trace.method_names, []);
    assert.deepEqual(trace.slow_calls, []);
  }
});

test("all-GL trace discovers every effective own/inherited callable without invoking getters or GL", () => {
  const objectToString = Object.prototype.toString;
  const instance = allTraceHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  for (const [key, original] of instance.originals) {
    assert.notEqual(proto[key], original, String(key) + " must be wrapped");
    assert.equal(Object.hasOwn(proto, key), true, "inherited wrappers must only affect WebGL2");
    assert.equal(Object.getOwnPropertyDescriptor(proto, key).enumerable, false);
  }
  for (const [key, original] of instance.baseOriginals) {
    assert.equal(instance.WebGLBaseContext.prototype[key], original, "shared ancestors stay unchanged");
  }
  assert.equal(proto.constructor, instance.WebGL2RenderingContext);
  assert.equal(proto.CONSTANT, 1234);
  assert.equal(proto.shadowedMethod, 17);
  assert.equal(Object.prototype.toString, objectToString);
  assert.equal(Object.hasOwn(proto, "toString"), false);
  assert.equal(instance.invocations.length, 0);
  assert.equal(instance.getterReads(), 0);
  const trace = complete(instance).browser.gl_all_trace;
  assert.equal(trace.requested, true);
  assert.equal(trace.enabled, true);
  assert.equal(trace.status, "active");
  assert.deepEqual(trace.unavailable, []);
  assert.deepEqual(trace.skipped_accessors, ["opaqueGetter"]);
  assert.equal(trace.method_names.length, instance.keys.length);
  assert.deepEqual(trace.discovered_names, trace.method_names);
  assert.deepEqual(Object.keys(trace.calls), trace.method_names);
  for (const name of [...allTraceOwnMethods, ...allTraceInheritedMethods]) {
    assert.ok(trace.method_names.includes(name), name + " must not require a fixed allowlist");
  }
  assert.deepEqual(trace.method_names.filter(name => name.startsWith("[symbol")),
    ["[symbol 0] Symbol(ownNative)", "[symbol 1] Symbol(inheritedNative)"]);
  assert.ok(Object.values(trace.calls).every(totals => totals.count === 0));
  assert.equal(instance.invocations.length, 0, "reporting must not query GL");
});

test("all-GL trace forwards exact receivers/arguments/returns across all discovered methods", () => {
  const instance = allTraceHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  const opaque = {privateArgument: true, valueOf() { throw new Error("do not coerce arguments"); }};
  const buffer = new Uint8Array([99, 21, 175]);
  const results = [false, undefined, null, 37146, {privateQueryResult: true}];
  for (const [index, key] of instance.keys.entries()) {
    const receiver = {duration: 8, result: results[index % results.length]};
    const args = [opaque, buffer, undefined, index];
    assert.equal(Reflect.apply(proto[key], receiver, args), receiver.result);
    assert.equal(instance.invocations.at(-1).receiver, receiver);
    assert.deepEqual(instance.invocations.at(-1).args, args);
    receiver.result = {privateNewResult: true};
    assert.equal(Reflect.apply(proto[key], receiver, []), receiver.result);
    assert.deepEqual(instance.invocations.at(-1).args, []);
  }
  // Invalid receivers are still forwarded unchanged; a native implementation
  // decides whether to throw. Instrumentation never substitutes a GL object.
  for (const receiver of [null, undefined, 0, false]) {
    Reflect.apply(proto.getError, receiver, []);
    assert.equal(instance.invocations.at(-1).receiver, receiver);
  }
  const trace = complete(instance).browser.gl_all_trace;
  assert.equal(instance.invocations.length, instance.keys.length * 2 + 4);
  for (const [name, totals] of Object.entries(trace.calls)) {
    assert.equal(totals.count, name === "getError" ? 6 : 2);
    assert.equal(totals.total_wall_ms, 16);
    assert.equal(totals.by_phase.startup.count, totals.count);
    assert.equal(totals.by_phase.after_first_running.count, 0);
  }
  for (const row of trace.slow_calls) {
    assert.deepEqual(Object.keys(row).sort(), ["duration_ms", "name", "phase", "start_ms"]);
  }
  for (const privateValue of ["privateArgument", "privateQueryResult", "privateNewResult", "37146"]) {
    assert.ok(!JSON.stringify(trace).includes(privateValue));
  }
});

test("all-GL trace preserves every exact thrown value, retaining timing only", () => {
  const instance = allTraceHarness();
  const proto = instance.WebGL2RenderingContext.prototype;
  const failures = [new Error("private native exception"), {privateFailure: true}, undefined, null, false, 0];
  for (const [index, key] of instance.keys.entries()) {
    const failure = failures[index % failures.length];
    const receiver = {duration: 9, shouldThrow: true, failure};
    let threw = false;
    try { Reflect.apply(proto[key], receiver, [index]); }
    catch (error) { threw = true; assert.equal(error, failure); }
    assert.equal(threw, true, String(key) + " must rethrow exact original value");
    assert.equal(instance.invocations.at(-1).receiver, receiver);
    assert.deepEqual(instance.invocations.at(-1).args, [index]);
  }
  const trace = complete(instance).browser.gl_all_trace;
  assert.equal(trace.slow_calls.length, instance.keys.length);
  for (const totals of Object.values(trace.calls)) {
    assert.equal(totals.count, 1);
    assert.equal(totals.total_wall_ms, 9);
    assert.equal(totals.over_threshold, 1);
  }
  assert.ok(!JSON.stringify(trace).includes("private native exception"));
  assert.ok(!JSON.stringify(trace).includes("privateFailure"));
});

test("all-GL trace reserves bounded slow rows for both phases and retains exact totals", () => {
  const instance = allTraceHarness();
  const call = instance.WebGL2RenderingContext.prototype.uniform1i;
  const receiver = {duration: 7.5};
  const started = instance.clock();
  Reflect.apply(call, receiver, []);
  receiver.duration = 8;
  for (let index = 0; index < 66; index++) Reflect.apply(call, receiver, []);
  instance.context.__wwRunnerMark("first_running");
  receiver.duration = 9;
  for (let index = 0; index < 67; index++) Reflect.apply(call, receiver, []);
  const trace = complete(instance).browser.gl_all_trace;
  assert.equal(trace.threshold_ms, 8);
  assert.equal(trace.limit, 128);
  assert.equal(trace.slow_calls.length, 128);
  assert.equal(trace.dropped, 5);
  assert.deepEqual(trace.slow_call_retention_by_phase, {
    startup: {limit: 64, seen: 66, kept: 64, dropped: 2},
    after_first_running: {limit: 64, seen: 67, kept: 64, dropped: 3},
  });
  const retention = Object.values(trace.slow_call_retention_by_phase);
  assert.equal(retention.reduce((total, phase) => total + phase.limit, 0), trace.limit);
  assert.equal(retention.reduce((total, phase) => total + phase.kept, 0), trace.slow_calls.length);
  assert.equal(retention.reduce((total, phase) => total + phase.dropped, 0), trace.dropped);
  assert.deepEqual(trace.calls.uniform1i, {count: 134, total_wall_ms: 1138.5,
    max_wall_ms: 9, over_threshold: 133, by_phase: {
      startup: {count: 67, total_wall_ms: 535.5, max_wall_ms: 8, over_threshold: 66},
      after_first_running: {count: 67, total_wall_ms: 603, max_wall_ms: 9, over_threshold: 67},
    }});
  assert.equal(trace.slow_calls[0].start_ms, started + 7.5);
  assert.equal(trace.slow_calls[0].duration_ms, 8);
  assert.deepEqual(trace.slow_calls.reduce((counts, row) => {
    counts[row.phase]++;
    return counts;
  }, {startup: 0, after_first_running: 0}), {startup: 64, after_first_running: 64});
  assert.equal(trace.slow_calls[63].phase, "startup");
  assert.equal(trace.slow_calls[64].phase, "after_first_running");
  assert.equal(trace.slow_calls[127].phase, "after_first_running");
  for (const row of trace.slow_calls) {
    assert.deepEqual(Object.keys(row).sort(), ["duration_ms", "name", "phase", "start_ms"]);
  }
});

test("all-GL trace captures phase at call entry even when GO arrives during that call", () => {
  const instance = allTraceHarness();
  const receiver = {duration: 10, onInvoke: () => instance.context.__wwRunnerMark("first_running")};
  Reflect.apply(instance.WebGL2RenderingContext.prototype.useProgram, receiver, []);
  receiver.onInvoke = undefined;
  Reflect.apply(instance.WebGL2RenderingContext.prototype.useProgram, receiver, []);
  const trace = complete(instance).browser.gl_all_trace;
  assert.deepEqual(trace.slow_calls.map(row => row.phase), ["startup", "after_first_running"]);
  assert.equal(trace.calls.useProgram.by_phase.startup.total_wall_ms, 10);
  assert.equal(trace.calls.useProgram.by_phase.after_first_running.total_wall_ms, 10);
});

test("all-GL trace safely reports absent, empty and frozen contexts as explicit coverage gaps", () => {
  const missing = complete(harness(undefined, {search: "?glalltrace=1"})).browser.gl_all_trace;
  assert.equal(missing.requested, true);
  assert.equal(missing.enabled, false);
  assert.equal(missing.status, "unavailable");
  assert.deepEqual(missing.unavailable, [{name: "WebGL2RenderingContext", reason: "missing_prototype"}]);
  class EmptyContext {}
  const empty = complete(harness(undefined, {search: "?glalltrace=1", WebGL2RenderingContext: EmptyContext}))
    .browser.gl_all_trace;
  assert.equal(empty.enabled, false);
  assert.deepEqual(empty.unavailable, [{name: "WebGL2RenderingContext", reason: "no_callable_methods"}]);
  let calls = 0;
  class FrozenContext { finish() { calls++; } }
  const original = FrozenContext.prototype.finish;
  Object.freeze(FrozenContext.prototype);
  const frozen = complete(harness(undefined, {search: "?glalltrace=1", WebGL2RenderingContext: FrozenContext}))
    .browser.gl_all_trace;
  assert.equal(frozen.enabled, false);
  assert.equal(frozen.status, "unavailable");
  assert.equal(FrozenContext.prototype.finish, original);
  assert.deepEqual(frozen.discovered_names, ["finish"]);
  assert.deepEqual(frozen.method_names, []);
  assert.deepEqual(frozen.unavailable, [{name: "finish", reason: "wrapper_installation_failed"}]);
  assert.equal(calls, 0);
});

test("all-GL trace reports partial installation without preventing available methods", () => {
  let calls = 0;
  class PartialContext { flush() { calls++; return false; } }
  Object.defineProperty(PartialContext.prototype, "finish", {value: () => { calls++; }});
  const originalFinish = PartialContext.prototype.finish;
  const instance = harness(undefined, {search: "?glalltrace=1", WebGL2RenderingContext: PartialContext});
  assert.equal(PartialContext.prototype.finish, originalFinish);
  assert.equal(Reflect.apply(PartialContext.prototype.flush, null, []), false);
  const trace = complete(instance).browser.gl_all_trace;
  assert.equal(trace.enabled, true);
  assert.equal(trace.status, "partial");
  assert.deepEqual(trace.discovered_names, ["flush", "finish"]);
  assert.deepEqual(trace.method_names, ["flush"]);
  assert.deepEqual(trace.unavailable, [{name: "finish", reason: "wrapper_installation_failed"}]);
  assert.equal(trace.calls.flush.count, 1);
  assert.equal(calls, 1);
});

test("all-GL trace refuses every legacy timing flag combination without double wrapping", () => {
  const legacyFlags = ["webgltrace", "presentationtrace", "rendertrace"];
  for (let mask = 1; mask < 8; mask++) {
    const flags = legacyFlags.filter((_, index) => mask & (1 << index));
    const instance = allTraceHarness("?glalltrace=1&" + flags.map(name => name + "=1").join("&"));
    const proto = instance.WebGL2RenderingContext.prototype;
    assert.equal(proto.uniform1i, instance.originals.get("uniform1i"));
    const receiver = {duration: 10, result: true};
    Reflect.apply(proto.compileShader, receiver, [{}]);
    Reflect.apply(proto.getParameter, receiver, [3089]);
    Reflect.apply(proto.flush, receiver, []);
    const report = complete(instance).browser;
    assert.equal(report.gl_all_trace.requested, true);
    assert.equal(report.gl_all_trace.enabled, false);
    assert.equal(report.gl_all_trace.status, "refused_incompatible_flags");
    assert.deepEqual(report.gl_all_trace.incompatible_flags, flags);
    assert.deepEqual(report.gl_all_trace.discovered_names, []);
    assert.deepEqual(report.gl_all_trace.method_names, []);
    assert.deepEqual(report.gl_all_trace.calls, {});
    assert.equal(report.webgl_trace.enabled, flags.includes("webgltrace"));
    assert.equal(report.presentation_trace.enabled, flags.includes("presentationtrace"));
    assert.equal(report.render_trace.enabled, flags.includes("rendertrace"));
    if (flags.includes("webgltrace")) assert.equal(report.webgl_trace.calls.compileShader.count, 1);
    if (flags.includes("presentationtrace")) assert.equal(report.presentation_trace.calls["getParameter:3089"].count, 1);
    if (flags.includes("rendertrace")) assert.equal(report.render_trace.calls.flush.count, 1);
    assert.equal(instance.invocations.length, 3);
  }
  const compatible = allTraceHarness("?glalltrace=1&rendertrace=0&presentationtrace=true&webgltrace=01");
  assert.equal(complete(compatible).browser.gl_all_trace.status, "active");
});

const shaderMethods = ["createShader", "shaderSource", "compileShader", "getShaderParameter",
  "createProgram", "attachShader", "linkProgram", "getProgramParameter"];

function shaderHarness(search = "?shadertrace=1") {
  let clock = 100, timerReads = 0;
  const state = {duration: 1, result: undefined, shouldThrow: false, failure: undefined, onInvoke: undefined};
  const invocations = [];
  class BaseContext {}
  class WebGL2RenderingContext extends BaseContext {}
  for (const [index, name] of [...shaderMethods, "drawArrays", "getParameter", "blitFramebuffer", "flush"].entries()) {
    Object.defineProperty(index % 2 ? BaseContext.prototype : WebGL2RenderingContext.prototype, name,
      {configurable: true, writable: true, value: function (...args) {
        invocations.push({name, receiver: this, args}); clock += state.duration;
        if (state.onInvoke) state.onInvoke();
        if (state.shouldThrow) throw state.failure;
        return state.result;
      }});
  }
  const originals = Object.fromEntries([...shaderMethods, "drawArrays", "getParameter", "blitFramebuffer", "flush"]
    .map(name => [name, WebGL2RenderingContext.prototype[name]]));
  const baseOriginals = Object.fromEntries(Object.getOwnPropertyNames(BaseContext.prototype)
    .filter(name => name !== "constructor").map(name => [name, BaseContext.prototype[name]]));
  const instance = harness(undefined, {search, WebGL2RenderingContext,
    now: () => { timerReads++; return clock; }});
  const invoke = (name, args = [], config = {}, receiver = null) => {
    Object.assign(state, {duration: 1, result: undefined, shouldThrow: false, failure: undefined,
      onInvoke: undefined}, config);
    return Reflect.apply(WebGL2RenderingContext.prototype[name], receiver, args);
  };
  const createShader = (result = {}, type = 35633) => invoke("createShader", [type], {result});
  const createProgram = (result = {}) => invoke("createProgram", [], {result});
  return {...instance, WebGL2RenderingContext, BaseContext, originals, baseOriginals, invocations,
    invoke, createShader, createProgram, clock: () => clock, timerReads: () => timerReads};
}

test("shader trace defaults off and exact opt-in wraps only eight low-frequency methods", () => {
  for (const search of ["", "?shadertrace=0", "?shadertrace=true", "?shadertrace=01"]) {
    const instance = shaderHarness(search);
    for (const [name, original] of Object.entries(instance.originals)) {
      assert.equal(instance.WebGL2RenderingContext.prototype[name], original);
    }
    const reads = instance.timerReads(); instance.invoke("compileShader", [{}]);
    assert.equal(instance.timerReads(), reads);
    const trace = complete(instance).browser.shader_trace;
    assert.equal(trace.requested, false); assert.equal(trace.enabled, false);
    assert.equal(trace.status, "disabled"); assert.deepEqual(trace.calls, {});
    assert.deepEqual(trace.post_go_events, []); assert.deepEqual(trace.shaders, []);
  }
  const instance = shaderHarness();
  for (const name of shaderMethods) assert.notEqual(instance.WebGL2RenderingContext.prototype[name], instance.originals[name]);
  for (const name of ["drawArrays", "getParameter", "blitFramebuffer", "flush"]) {
    assert.equal(instance.WebGL2RenderingContext.prototype[name], instance.originals[name]);
  }
  for (const [name, original] of Object.entries(instance.baseOriginals)) assert.equal(instance.BaseContext.prototype[name], original);
  assert.equal(instance.invocations.length, 0);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.status, "active"); assert.deepEqual(trace.method_names, shaderMethods);
  assert.deepEqual(trace.unavailable, []); assert.equal(trace.diagnostic_errors, 0);
});

test("shader trace correlates objects, attachments, source updates and first/last compile/link phases", () => {
  const instance = shaderHarness();
  const vertex = instance.createShader({}, 35633), fragment = instance.createShader({}, 35632);
  const source1 = "#define MODE_DAY 1\nvoid main(){ private_source_body_one; }";
  const source2 = "#define MODE_NIGHT 1\nvoid main(){ private_source_body_two; }";
  instance.invoke("shaderSource", [vertex, "#define VERTEX_STAGE\nvoid main(){}"]);
  instance.invoke("shaderSource", [fragment, source1]);
  instance.invoke("compileShader", [vertex]); instance.invoke("compileShader", [fragment]);
  const program = instance.createProgram();
  instance.invoke("attachShader", [program, vertex]); instance.invoke("attachShader", [program, fragment]);
  instance.invoke("attachShader", [program, fragment]);
  instance.invoke("linkProgram", [program]);
  const afterGO = instance.clock(); instance.context.__wwRunnerMark("first_running");
  instance.invoke("shaderSource", [fragment, source2], {duration: 2});
  instance.invoke("compileShader", [fragment], {duration: 0.125});
  instance.invoke("linkProgram", [program], {duration: 0.25});
  const privateQuery = {privateQueryResult: true};
  assert.equal(instance.invoke("getShaderParameter", [fragment, 35713], {duration: 9, result: privateQuery}), privateQuery);
  assert.equal(instance.invoke("getProgramParameter", [program, 35714], {duration: 3, result: false}), false);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.shaders.length, 2); assert.equal(trace.programs.length, 1);
  assert.equal(trace.shaders[0].type_enum, 35633); assert.equal(trace.shaders[1].type_enum, 35632);
  assert.deepEqual(trace.programs[0].attached_shader_ids, ["s1", "s2"]);
  const shader = trace.shaders[1], linked = trace.programs[0];
  assert.equal(shader.source_updates, 2); assert.equal(shader.source.revision, 2);
  assert.deepEqual(shader.source.defines, ["#define MODE_NIGHT 1"]);
  assert.equal(shader.source.length_code_units, source2.length);
  assert.equal(shader.first_source.phase, "startup");
  assert.equal(shader.first_compile.phase, "startup"); assert.equal(shader.first_compile.source_revision, 1);
  assert.equal(shader.last_compile.phase, "after_first_running"); assert.equal(shader.last_compile.source_revision, 2);
  assert.notEqual(shader.first_compile.source_hash, shader.last_compile.source_hash);
  assert.equal(linked.first_link.phase, "startup"); assert.equal(linked.first_link.shader_sources[1].source_revision, 1);
  assert.equal(linked.last_link.phase, "after_first_running"); assert.equal(linked.last_link.shader_sources[1].source_revision, 2);
  assert.equal(trace.first_source.shader_id, "s1"); assert.equal(trace.first_compile.shader_id, "s1");
  assert.equal(trace.first_link.program_id, "p1");
  assert.deepEqual(trace.post_go_events.map(v => v.name), ["shaderSource", "compileShader", "linkProgram", "getShaderParameter", "getProgramParameter"]);
  assert.deepEqual(trace.post_go_events.map(v => v.start_ms), [afterGO, afterGO + 2, afterGO + 2.125, afterGO + 2.375, afterGO + 11.375]);
  assert.equal(trace.post_go_events[1].duration_ms, 0.125, "fast post-GO compile still has exact timestamp/duration");
  assert.equal(trace.post_go_events[3].query_enum, 35713); assert.equal(trace.post_go_events[4].query_enum, 35714);
  assert.deepEqual(trace.calls.shaderSource.by_phase.after_first_running,
    {count: 1, total_wall_ms: 2, max_wall_ms: 2, over_threshold: 0});
  assert.equal(trace.calls.getShaderParameter.over_threshold, 1);
  assert.equal(trace.unknown_shader_references, 0); assert.equal(trace.unknown_program_references, 0);
  assert.equal(trace.diagnostic_errors, 0);
  const serialized = JSON.stringify(trace);
  for (const privateText of ["privateQueryResult", "private_source_body_one", "private_source_body_two", "MODE_DAY"]) {
    assert.ok(!serialized.includes(privateText), "no full source, query result or previous define text retained");
  }
});

test("shader trace forwards exact receivers, arguments and return identities without inspecting objects", () => {
  const instance = shaderHarness();
  let traps = 0;
  const opaque = new Proxy({}, {get() { traps++; throw new Error("must not inspect objects"); },
    getPrototypeOf() { traps++; throw new Error("must not inspect prototypes"); }});
  const shader = instance.createShader(opaque, opaque);
  const program = instance.createProgram(Object.create(null));
  instance.context.__wwRunnerMark("first_running");
  const argsByName = {createShader: [35632, opaque], shaderSource: [shader, opaque], compileShader: [shader, opaque],
    getShaderParameter: [shader, opaque], createProgram: [opaque], attachShader: [program, shader, opaque],
    linkProgram: [program, opaque], getProgramParameter: [program, opaque]};
  const results = [undefined, false, null, 123, opaque];
  for (const [index, name] of shaderMethods.entries()) {
    const result = results[index % results.length], receiver = index % 2 ? opaque : null;
    assert.equal(instance.invoke(name, argsByName[name], {result}, receiver), result);
    assert.equal(instance.invocations.at(-1).receiver, receiver);
    assert.deepEqual(instance.invocations.at(-1).args, argsByName[name]);
  }
  for (const receiver of [undefined, 0, false]) {
    Reflect.apply(instance.WebGL2RenderingContext.prototype.getShaderParameter, receiver, [shader, 35713]);
    assert.equal(instance.invocations.at(-1).receiver, receiver);
  }
  assert.equal(traps, 0);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.shaders[0].type_enum, null);
  assert.equal(trace.nonprimitive_source_calls, 1);
  assert.equal(trace.shaders[0].source, null);
  assert.equal(trace.post_go_events.find(v => v.name === "getShaderParameter").query_enum, null);
  assert.equal(trace.post_go_events.find(v => v.name === "getProgramParameter").query_enum, null);
  assert.equal(trace.diagnostic_errors, 0); assert.equal(traps, 0);
  assert.equal(instance.invocations.length, 13, "installation/reporting must add no GL calls");
});

test("shader trace preserves exact thrown values and never treats a thrown shaderSource as an update", () => {
  const instance = shaderHarness(), shader = instance.createShader(), program = instance.createProgram();
  instance.invoke("shaderSource", [shader, "hello"]);
  instance.context.__wwRunnerMark("first_running");
  const failures = [new Error("private_error"), {privateFailure: true}, undefined, null, false, 0, "private_throw", Symbol("private_symbol")];
  for (const [index, name] of shaderMethods.entries()) {
    const args = name === "createShader" ? [35633] : name === "createProgram" ? [] :
      name === "shaderSource" ? [shader, "#define MUST_NOT_RETAIN"] :
      name === "attachShader" ? [program, shader] :
      name === "getShaderParameter" ? [shader, 35713] : name === "getProgramParameter" ? [program, 35714] :
      [name === "compileShader" ? shader : program];
    let threw = false;
    try { instance.invoke(name, args, {duration: 9, shouldThrow: true, failure: failures[index]}); }
    catch (error) { threw = true; assert.equal(error, failures[index]); }
    assert.equal(threw, true, name + " must preserve native throws");
  }
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.post_go_events.length, 8); assert.ok(trace.post_go_events.every(v => v.outcome === "threw"));
  assert.equal(trace.shaders.length, 1); assert.equal(trace.programs.length, 1);
  assert.equal(trace.shaders[0].source_updates, 1); assert.equal(trace.shaders[0].source.hash, "4f9f2cab");
  assert.equal(trace.shaders[0].first_compile.outcome, "threw");
  assert.deepEqual(trace.programs[0].attached_shader_ids, []);
  assert.equal(trace.programs[0].first_link.outcome, "threw");
  for (const name of shaderMethods) {
    assert.deepEqual(trace.calls[name].by_phase.after_first_running,
      {count: 1, total_wall_ms: 9, max_wall_ms: 9, over_threshold: 1});
  }
  for (const privateText of ["private_error", "privateFailure", "private_throw", "private_symbol", "MUST_NOT_RETAIN"]) {
    assert.ok(!JSON.stringify(trace).includes(privateText));
  }
  assert.equal(trace.diagnostic_errors, 0);
});

test("shader trace distinguishes primitive strings, labels hashes and bounds define lines/length", () => {
  const instance = shaderHarness(), shader = instance.createShader();
  instance.invoke("shaderSource", [shader, new String("#define BOXED_MUST_NOT_RETAIN")]);
  const lines = Array.from({length: 70}, (_, i) => "#define M" + i + " " + "x".repeat(190));
  const source = lines.join("\n") + "\nvoid main(){ private_source_body; }";
  instance.invoke("shaderSource", [shader, source]);
  const trace = complete(instance).browser.shader_trace, metadata = trace.shaders[0].source;
  assert.equal(trace.nonprimitive_source_calls, 1); assert.equal(trace.shaders[0].source_updates, 1);
  assert.equal(metadata.length_code_units, source.length);
  assert.match(metadata.hash, /^[0-9a-f]{8}$/);
  assert.equal(metadata.hash_algorithm, "fnv1a32_utf16_diagnostic_noncryptographic");
  assert.equal(metadata.define_lines_seen, 70); assert.equal(metadata.defines.length, 64);
  assert.equal(metadata.define_lines_omitted, 6);
  assert.ok(metadata.defines.every(line => line.length === 160));
  assert.equal(metadata.define_line_limit_truncated, true); assert.equal(metadata.define_length_truncated, true);
  assert.equal(metadata.source_text_budget_truncated, false);
  assert.equal(metadata.retained_text_bytes, 64 * 160 * 2);
  assert.equal(trace.retained_define_text_bytes, metadata.retained_text_bytes);
  assert.ok(!JSON.stringify(trace).includes("private_source_body"));
  assert.ok(!JSON.stringify(trace).includes("BOXED_MUST_NOT_RETAIN"));
});

test("shader trace reads physical define lines only and reports continuation truncation scope", () => {
  const instance = shaderHarness(), shader = instance.createShader();
  const source = "\t# define ONE 1\r\n #define TWO \\\n continuation_not_retained\n#defineX NOT_A_DEFINE\n#define THREE 😀\n";
  instance.invoke("shaderSource", [shader, source]);
  const metadata = complete(instance).browser.shader_trace.shaders[0].source;
  assert.deepEqual(metadata.defines, ["# define ONE 1", "#define TWO \\", "#define THREE 😀"]);
  assert.equal(metadata.define_lines_seen, 3); assert.equal(metadata.contains_continued_define, true);
  assert.equal(metadata.retained_text_bytes, metadata.defines.reduce((sum, line) => sum + line.length * 2, 0));
  assert.ok(!JSON.stringify(metadata).includes("continuation_not_retained"));
});

test("shader trace startup define text stays <=512KiB and source replacement reclaims budget", () => {
  const instance = shaderHarness();
  const source = Array.from({length: 64}, () => "#define M " + "x".repeat(150)).join("\n");
  const shaders = Array.from({length: 27}, () => instance.createShader());
  for (const shader of shaders) instance.invoke("shaderSource", [shader, source]);
  const before = vm.runInContext("shaderTrace", instance.context);
  assert.equal(before.retained_define_text_bytes, 524288);
  assert.equal(before.peak_retained_define_text_bytes, 524288);
  assert.equal(before.shaders[25].source.source_text_budget_truncated, true);
  assert.equal(before.shaders[26].source.source_text_budget_truncated, true);
  assert.equal(before.shaders[26].source.defines.length, 0);
  instance.invoke("shaderSource", [shaders[0], "hello"]);
  assert.equal(before.retained_define_text_bytes, 524288 - 20480);
  instance.invoke("shaderSource", [shaders[26], source]);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.retained_define_text_bytes, 524288);
  assert.equal(trace.peak_retained_define_text_bytes, 524288);
  assert.equal(trace.shaders[0].source.hash, "4f9f2cab");
  assert.equal(trace.shaders[26].source.source_text_budget_truncated, false);
  assert.equal(trace.shaders[26].source.defines.length, 64);
  assert.equal(trace.retained_define_text_bytes, trace.shaders.reduce((n, s) => n + s.source.retained_text_bytes, 0));
});

test("shader trace reserves128KiB post-GO defines independently of exhausted512KiB startup budget", () => {
  const instance = shaderHarness();
  const source = Array.from({length: 64}, () => "#define M " + "x".repeat(150)).join("\n");
  for (let index = 0; index < 27; index++) instance.invoke("shaderSource", [instance.createShader(), source]);
  instance.context.__wwRunnerMark("first_running");
  for (let index = 0; index < 4; index++) instance.invoke("shaderSource", [instance.createShader(), source]);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.limits.retained_define_text_bytes, 655360);
  assert.deepEqual(trace.limits.retained_define_text_bytes_by_phase, {startup: 524288, after_first_running: 131072});
  assert.deepEqual(trace.define_text_by_phase, {
    startup: {retained_bytes: 524288, peak_retained_bytes: 524288},
    after_first_running: {retained_bytes: 81920, peak_retained_bytes: 81920}});
  assert.equal(trace.retained_define_text_bytes, 606208); assert.equal(trace.peak_retained_define_text_bytes, 606208);
  for (const shader of trace.shaders.slice(0, 27)) assert.equal(shader.source.define_text_phase, "startup");
  for (const shader of trace.shaders.slice(27)) {
    assert.equal(shader.source.define_text_phase, "after_first_running");
    assert.equal(shader.source.defines.length, 64); assert.equal(shader.source.retained_text_bytes, 20480);
    assert.equal(shader.source.source_text_budget_truncated, false);
    assert.equal(Object.hasOwn(shader.source, "text"), false, "no source-body feature installed");
  }
  assert.equal(Object.hasOwn(trace, "post_go_sources"), false);
  assert.equal(trace.diagnostic_errors, 0);
});

test("shader trace source ownership moves budgets without transferring startup allowance into post-GO", () => {
  const instance = shaderHarness();
  const source = Array.from({length: 64}, () => "#define M " + "x".repeat(150)).join("\n");
  const startup = Array.from({length: 27}, () => instance.createShader());
  for (const shader of startup) instance.invoke("shaderSource", [shader, source]);
  instance.context.__wwRunnerMark("first_running");
  const running = Array.from({length: 7}, () => instance.createShader());
  for (const shader of running) instance.invoke("shaderSource", [shader, source]);
  const live = vm.runInContext("shaderTrace", instance.context);
  const assertBudgets = () => {
    let total = 0;
    for (const phase of ["startup", "after_first_running"]) {
      const expected = live.shaders.reduce((n, shader) => n +
        (shader.source?.define_text_phase === phase ? shader.source.retained_text_bytes : 0), 0);
      assert.equal(live.define_text_by_phase[phase].retained_bytes, expected);
      assert.ok(expected >= 0 && expected <= live.limits.retained_define_text_bytes_by_phase[phase]);
      assert.ok(live.define_text_by_phase[phase].peak_retained_bytes <= live.limits.retained_define_text_bytes_by_phase[phase]);
      total += expected;
    }
    assert.equal(live.retained_define_text_bytes, total);
    assert.ok(total <= live.limits.retained_define_text_bytes);
  };
  assertBudgets(); assert.equal(live.retained_define_text_bytes, 655360);
  assert.equal(live.define_text_by_phase.after_first_running.retained_bytes, 131072);
  assert.equal(live.shaders.at(-1).source.source_text_budget_truncated, true);
  instance.invoke("shaderSource", [startup[0], "#define MOVED 1"]);
  assertBudgets(); assert.equal(live.retained_define_text_bytes, 655360 - 20480);
  assert.equal(live.shaders[0].source.define_text_phase, "after_first_running");
  assert.equal(live.shaders[0].source.retained_text_bytes, 0,
    "released startup bytes cannot increase exhausted post-GO budget");
  assert.equal(live.shaders[0].source.source_text_budget_truncated, true);
  instance.invoke("shaderSource", [running[0], "hello"]);
  assertBudgets(); assert.equal(live.define_text_by_phase.after_first_running.retained_bytes, 131072 - 20480);
  instance.invoke("shaderSource", [startup[0], source]);
  assertBudgets(); assert.equal(live.define_text_by_phase.after_first_running.retained_bytes, 131072);
  assert.equal(live.shaders[0].source.source_text_budget_truncated, false);
  const small = "#define SMALL 1";
  instance.invoke("shaderSource", [startup[0], small]);
  assertBudgets(); assert.equal(live.define_text_by_phase.after_first_running.retained_bytes, 131072 - 20480 + small.length * 2);
  const prior = live.retained_define_text_bytes;
  instance.invoke("shaderSource", [startup[0], new String("#define BOXED")]);
  assert.throws(() => instance.invoke("shaderSource", [startup[0], "#define THROWN"],
    {shouldThrow: true, failure: new Error("expected native error")}));
  assertBudgets(); assert.equal(live.retained_define_text_bytes, prior);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.peak_retained_define_text_bytes, 655360);
  assert.equal(trace.define_text_by_phase.startup.peak_retained_bytes, 524288);
  assert.equal(trace.define_text_by_phase.after_first_running.peak_retained_bytes, 131072);
  assert.equal(trace.diagnostic_errors, 0);
});

test("shader trace lifetime IDs cap at512/256 and invalid returns/unknown refs stay explicit", () => {
  const instance = shaderHarness();
  const shaders = Array.from({length: 513}, () => instance.createShader());
  const programs = Array.from({length: 257}, () => instance.createProgram());
  instance.createShader(shaders[0]); instance.createProgram(programs[0]);
  for (const value of [null, undefined, 0, false, "not an object", Symbol("not an object")]) {
    instance.invoke("createShader", [35633], {result: value}); instance.invoke("createProgram", [], {result: value});
  }
  instance.context.__wwRunnerMark("first_running");
  instance.invoke("shaderSource", [shaders.at(-1), "#define UNTRACKED"]);
  instance.invoke("compileShader", [null]); instance.invoke("linkProgram", [programs.at(-1)]);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.shaders.length, 512); assert.equal(trace.programs.length, 256);
  assert.equal(trace.shader_id_admission_drops, 1); assert.equal(trace.program_id_admission_drops, 1);
  assert.equal(trace.invalid_shader_create_returns, 6); assert.equal(trace.invalid_program_create_returns, 6);
  assert.equal(trace.untracked_source_calls, 1); assert.equal(trace.unknown_shader_references, 2);
  assert.equal(trace.unknown_program_references, 1);
  assert.equal(trace.post_go_events[0].shader_id, null); assert.equal(trace.post_go_events[0].source_status, "untracked_shader");
  assert.equal(trace.post_go_events[2].program_id, null);
  assert.ok(!JSON.stringify(trace).includes("UNTRACKED")); assert.equal(trace.diagnostic_errors, 0);
});

test("shader trace attachment cap and duplicates are explicit in link snapshots", () => {
  const instance = shaderHarness(), program = instance.createProgram();
  const shaders = Array.from({length: 17}, () => instance.createShader());
  for (const shader of shaders) instance.invoke("attachShader", [program, shader]);
  instance.invoke("attachShader", [program, shaders[0]]);
  instance.context.__wwRunnerMark("first_running"); instance.invoke("linkProgram", [program]);
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.programs[0].attached_shader_ids.length, 16);
  assert.equal(trace.programs[0].attachment_edges_dropped, 1); assert.equal(trace.attachment_edges_dropped, 1);
  assert.equal(trace.post_go_events[0].shader_sources.length, 16);
  assert.equal(trace.post_go_events[0].attachments_truncated, true);
  assert.deepEqual(trace.post_go_events[0].shader_sources[0], {shader_id: "s1", source_revision: null, source_hash: null});
});

test("shader trace separately caps128 slow startup and512 all post-GO events with exact totals", () => {
  const instance = shaderHarness(), shader = instance.createShader();
  instance.invoke("getShaderParameter", [shader, 35713], {duration: 7.5});
  for (let index = 0; index < 130; index++) instance.invoke("getShaderParameter", [shader, 35713], {duration: 8});
  instance.context.__wwRunnerMark("first_running");
  for (let index = 0; index < 514; index++) instance.invoke("getShaderParameter", [shader, 35713], {duration: 0.25});
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.startup_slow_events.length, 128); assert.equal(trace.startup_slow_events_seen, 130);
  assert.equal(trace.startup_slow_events_dropped, 2); assert.equal(trace.startup_slow_events[0].duration_ms, 8);
  assert.equal(trace.post_go_events.length, 512); assert.equal(trace.post_go_events_seen, 514);
  assert.equal(trace.post_go_events_dropped, 2);
  assert.deepEqual(trace.calls.getShaderParameter, {count: 645, total_wall_ms: 1176, max_wall_ms: 8, over_threshold: 130,
    by_phase: {startup: {count: 131, total_wall_ms: 1047.5, max_wall_ms: 8, over_threshold: 130},
      after_first_running: {count: 514, total_wall_ms: 128.5, max_wall_ms: 0.25, over_threshold: 0}}});
});

test("shader trace phase and first-operation timestamps use entry even if GO arrives during call", () => {
  const instance = shaderHarness(), shader = instance.createShader();
  const sourceStart = instance.clock();
  instance.invoke("shaderSource", [shader, "hello"], {duration: 9,
    onInvoke: () => instance.context.__wwRunnerMark("first_running")});
  instance.invoke("compileShader", [shader], {duration: 0.25});
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.first_source.phase, "startup"); assert.equal(trace.first_source.start_ms, sourceStart);
  assert.equal(trace.shaders[0].source.define_text_phase, "startup");
  assert.equal(trace.define_text_by_phase.after_first_running.retained_bytes, 0);
  assert.equal(trace.first_compile.phase, "after_first_running"); assert.equal(trace.first_compile.start_ms, sourceStart + 9);
  assert.equal(trace.startup_slow_events[0].name, "shaderSource");
  assert.deepEqual(trace.post_go_events.map(v => v.name), ["compileShader"]);
});

test("shader trace missing/accessor/frozen methods are explicit and never invoke prototype getters", () => {
  const absent = complete(harness(undefined, {search: "?shadertrace=1"})).browser.shader_trace;
  assert.equal(absent.enabled, false); assert.equal(absent.status, "unavailable");
  assert.deepEqual(absent.unavailable.map(v => v.name), shaderMethods);
  let getterCalls = 0, nativeCalls = 0;
  class PartialContext { compileShader() { nativeCalls++; return false; } }
  Object.defineProperty(PartialContext.prototype, "createShader", {get() { getterCalls++; throw new Error("never inspect getter"); }});
  Object.defineProperty(PartialContext.prototype, "linkProgram", {value: () => { nativeCalls++; }});
  const original = PartialContext.prototype.linkProgram;
  const partial = harness(undefined, {search: "?shadertrace=1", WebGL2RenderingContext: PartialContext});
  assert.equal(getterCalls, 0); assert.equal(nativeCalls, 0); assert.equal(PartialContext.prototype.linkProgram, original);
  assert.equal(Reflect.apply(PartialContext.prototype.compileShader, null, [null]), false);
  const trace = complete(partial).browser.shader_trace;
  assert.equal(trace.status, "partial"); assert.deepEqual(trace.method_names, ["compileShader"]);
  assert.equal(trace.unavailable.find(v => v.name === "createShader").reason, "accessor_not_invoked");
  assert.equal(trace.unavailable.find(v => v.name === "linkProgram").reason, "wrapper_installation_failed");
  assert.equal(trace.unknown_shader_references, 1); assert.equal(trace.diagnostic_errors, 0);
  class FrozenContext { createShader() { nativeCalls++; } }
  Object.freeze(FrozenContext.prototype);
  const frozen = complete(harness(undefined, {search: "?shadertrace=1", WebGL2RenderingContext: FrozenContext})).browser.shader_trace;
  assert.equal(frozen.status, "unavailable"); assert.equal(frozen.enabled, false);
  assert.equal(frozen.unavailable.find(v => v.name === "createShader").reason, "wrapper_installation_failed");
  assert.equal(getterCalls, 0); assert.equal(nativeCalls, 1);
});

test("shader trace refuses all15 combinations of other timing flags without changing their behavior", () => {
  const otherFlags = ["glalltrace", "webgltrace", "presentationtrace", "rendertrace"];
  for (let mask = 1; mask < 16; mask++) {
    const flags = otherFlags.filter((_, index) => mask & (1 << index));
    const instance = shaderHarness("?shadertrace=1&" + flags.map(name => name + "=1").join("&"));
    instance.invoke("compileShader", [{}], {duration: 9});
    instance.invoke("getParameter", [3089], {duration: 9}); instance.invoke("flush", [], {duration: 9});
    const report = complete(instance).browser;
    assert.equal(report.shader_trace.requested, true); assert.equal(report.shader_trace.enabled, false);
    assert.equal(report.shader_trace.status, "refused_incompatible_flags");
    assert.deepEqual(report.shader_trace.incompatible_flags, flags);
    assert.deepEqual(report.shader_trace.calls, {}); assert.deepEqual(report.shader_trace.shaders, []);
    assert.equal(report.webgl_trace.enabled, flags.includes("webgltrace"));
    assert.equal(report.presentation_trace.enabled, flags.includes("presentationtrace"));
    assert.equal(report.render_trace.enabled, flags.includes("rendertrace"));
    assert.equal(report.gl_all_trace.requested, flags.includes("glalltrace"));
    if (flags.includes("webgltrace")) assert.equal(report.webgl_trace.calls.compileShader.count, 1);
    if (flags.includes("presentationtrace")) assert.equal(report.presentation_trace.calls["getParameter:3089"].count, 1);
    if (flags.includes("rendertrace")) assert.equal(report.render_trace.calls.flush.count, 1);
    if (flags.length === 1 && flags[0] === "glalltrace") assert.equal(report.gl_all_trace.calls.compileShader.count, 1);
    assert.equal(instance.invocations.length, 3);
  }
  const compatible = shaderHarness("?shadertrace=1&glalltrace=0&webgltrace=true&presentationtrace=01&rendertrace=0");
  assert.equal(complete(compatible).browser.shader_trace.status, "active");
});

function rendererHarness(search = "?manualstart=1&rendererinfo=1", options = {}) {
  const calls = [];
  let clock = 100;
  const values = {7936: "WebKit", 7937: "WebKit WebGL", 37445: "Google Inc. (Apple)",
    37446: "ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)", ...options.values};
  const context = {
    getParameter(queryEnum) {
      calls.push(["getParameter", queryEnum]); clock++;
      if (options.throwQuery === queryEnum) throw options.failure;
      return values[queryEnum];
    },
    getSupportedExtensions() {
      calls.push(["getSupportedExtensions"]); clock++;
      if (options.throwExtensions) throw options.failure;
      return Object.hasOwn(options, "extensions") ? options.extensions : ["KHR_parallel_shader_compile", "PRIVATE_OTHER_EXTENSION"];
    },
    getExtension(name) {
      calls.push(["getExtension", name]); clock++;
      if (options.throwDebug) throw options.failure;
      return Object.hasOwn(options, "debug") ? options.debug : {};
    },
  };
  class Engine {
    static getMissingFeatures() { return options.missing || []; }
    startGame() { return options.reject ? Promise.reject(options.failure) : Promise.resolve(); }
  }
  const instance = harness(Engine, {search, now: () => clock,
    runConfig: {run_id: "renderer-host-test", entry: options.entry || "app", canvas_policy: "production"}});
  instance.canvas.getContext = (...args) => {
    calls.push(["getContext", ...args]); clock++;
    if (options.throwContext) throw options.failure;
    return Object.hasOwn(options, "context") ? options.context : context;
  };
  const read = () => JSON.parse(vm.runInContext("JSON.stringify(rendererInfo)", instance.context));
  return {...instance, calls, read};
}

test("renderer metadata exact opt-in defaults off with zero context or GL queries", async () => {
  for (const search of ["", "?rendererinfo=0", "?rendererinfo=true", "?rendererinfo=01"]) {
    const instance = rendererHarness(search);
    instance.boot(); await Promise.resolve();
    instance.context.captureRendererInfo(); instance.clickCapture();
    assert.deepEqual(instance.calls, []);
    const metadata = instance.posts[0].browser.renderer_diagnostic;
    assert.equal(metadata.requested, false); assert.equal(metadata.attempted, false);
    assert.equal(metadata.status, "disabled"); assert.equal(metadata.start_ms, null);
  }
});

test("renderer metadata waits for actual app engine_started, queries existing canvas once, no attributes", async () => {
  const instance = rendererHarness();
  instance.boot(); instance.context.captureRendererInfo();
  assert.deepEqual(instance.calls, []); assert.equal(instance.read().status, "waiting_for_engine_started");
  instance.clickStart();
  assert.deepEqual(instance.calls, [], "resolved start promise must run before any context query");
  await Promise.resolve();
  assert.deepEqual(instance.calls, [["getContext", "webgl2"], ["getParameter", 7936],
    ["getParameter", 7937], ["getSupportedExtensions"], ["getExtension", "WEBGL_debug_renderer_info"],
    ["getParameter", 37445], ["getParameter", 37446]]);
  const before = instance.calls.length;
  instance.context.captureRendererInfo(); instance.clickStart(); instance.clickCapture();
  assert.equal(instance.calls.length, before);
  const metadata = instance.posts[0].browser.renderer_diagnostic;
  assert.equal(metadata.status, "active"); assert.equal(metadata.attempted, true);
  assert.equal(metadata.start_ms, instance.posts[0].browser.marks.engine_started);
  assert.equal(metadata.end_ms - metadata.start_ms, 7);
  assert.equal(metadata.unmasked_renderer, "ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)");
  assert.equal(metadata.khr_parallel_shader_compile_advertised, true);
  assert.equal(metadata.debug_renderer_info_available, true);
  assert.ok(!JSON.stringify(metadata).includes("PRIVATE_OTHER_EXTENSION"));
  assert.match(metadata.scope, /Separate diagnostic GL queries/);
  assert.equal(instance.posts[0].report.meets_gate, false);
});

test("renderer metadata bounds strings, avoids coercion and extension-object inspection", async () => {
  let traps = 0;
  const opaque = new Proxy({}, {get() { traps++; throw new Error("must not inspect extension object"); }});
  const instance = rendererHarness("?rendererinfo=1", {debug: opaque,
    values: {7936: "v".repeat(300), 7937: 123, 37445: "u".repeat(257), 37446: opaque}});
  instance.boot(); await Promise.resolve(); instance.clickCapture();
  const metadata = instance.posts[0].browser.renderer_diagnostic;
  assert.equal(traps, 0); assert.equal(metadata.status, "partial");
  assert.equal(metadata.masked_vendor.length, 256); assert.equal(metadata.unmasked_vendor.length, 256);
  assert.deepEqual(metadata.truncated_fields, ["masked_vendor", "unmasked_vendor"]);
  assert.equal(metadata.masked_renderer, null); assert.equal(metadata.unmasked_renderer, null);
  assert.deepEqual(metadata.unavailable, ["masked_renderer_not_string", "unmasked_renderer_not_string"]);
});

test("renderer metadata unavailable debug info is explicit, KHR advertisement not enabling extension", async () => {
  const instance = rendererHarness("?rendererinfo=1", {debug: null, extensions: ["EXT_color_buffer_float"]});
  instance.boot(); await Promise.resolve(); instance.clickCapture();
  const metadata = instance.posts[0].browser.renderer_diagnostic;
  assert.equal(metadata.status, "partial"); assert.equal(metadata.debug_renderer_info_available, false);
  assert.equal(metadata.khr_parallel_shader_compile_advertised, false);
  assert.deepEqual(metadata.unavailable, ["debug_renderer_info_unavailable"]);
  assert.equal(metadata.unmasked_renderer, null);
  assert.deepEqual(instance.calls.filter(row => row[0] === "getExtension"), [["getExtension", "WEBGL_debug_renderer_info"]]);
  assert.equal(instance.calls.some(row => row[1] === 37445 || row[1] === 37446), false);
});

test("renderer metadata query failures remain nonfatal with fixed reasons, no exception retention", async () => {
  const failure = new Error("PRIVATE_METADATA_ERROR");
  for (const options of [{throwContext: true}, {context: null}, {throwQuery: 7936},
    {throwExtensions: true}, {extensions: null}, {throwDebug: true}, {debug: undefined}, {throwQuery: 37446}]) {
    const instance = rendererHarness("?rendererinfo=1", {...options, failure});
    instance.boot(); await Promise.resolve(); instance.clickCapture();
    assert.equal(instance.posts.length, 1); assert.equal(Object.hasOwn(instance.posts[0], "error"), false);
    const metadata = instance.posts[0].browser.renderer_diagnostic;
    assert.ok(["partial", "unavailable"].includes(metadata.status));
    assert.ok(metadata.unavailable.length > 0); assert.ok(metadata.end_ms >= metadata.start_ms);
    assert.ok(!JSON.stringify(metadata).includes("PRIVATE_METADATA_ERROR"));
  }
});

test("renderer metadata never probes on failed engine startup or unsupported runner entry", async () => {
  for (const options of [{reject: true, failure: new Error("startup failed")}, {missing: ["WebGL2"]}, {entry: "runner"}]) {
    const instance = rendererHarness("?rendererinfo=1", options);
    instance.boot(); await Promise.resolve(); instance.context.captureRendererInfo();
    assert.deepEqual(instance.calls, []); assert.equal(instance.read().attempted, false);
    if (options.entry === "runner") assert.equal(instance.read().status, "unsupported_entry");
  }
});

test("renderer metadata coexists with shader trace without adding shader/program calls", async () => {
  const instance = rendererHarness("?rendererinfo=1&shadertrace=1");
  instance.boot(); await Promise.resolve(); instance.clickCapture();
  const browser = instance.posts[0].browser;
  assert.equal(browser.renderer_diagnostic.status, "active");
  assert.equal(browser.shader_trace.requested, true);
  assert.equal(browser.shader_trace.status, "unavailable", "host supplies no shader prototype; metadata needs no compile/link calls");
  assert.deepEqual(browser.shader_trace.calls, {});
});

test("shader max spans preserve exact status-query timestamp after slow-row caps fill", () => {
  const instance = shaderHarness(), shader = instance.createShader();
  for (let index = 0; index < 128; index++) instance.invoke("getShaderParameter", [shader, 35713], {duration: 8});
  const longStart = instance.clock();
  instance.invoke("getShaderParameter", [shader, 35713], {duration: 1400});
  instance.invoke("getShaderParameter", [shader, 35713], {duration: 1400});
  instance.context.__wwRunnerMark("first_running");
  const linkStart = instance.clock();
  instance.invoke("getProgramParameter", [{}, 35714], {duration: 2400});
  const trace = complete(instance).browser.shader_trace;
  assert.equal(trace.startup_slow_events.length, 128); assert.equal(trace.startup_slow_events_dropped, 2);
  assert.deepEqual(trace.max_spans.getShaderParameter.all, {name: "getShaderParameter", phase: "startup",
    start_ms: longStart, duration_ms: 1400, outcome: "returned", query_enum: 35713, shader_id: "s1"});
  assert.deepEqual(trace.max_spans.getShaderParameter.startup, trace.max_spans.getShaderParameter.all);
  assert.equal(trace.max_spans.getShaderParameter.after_first_running, null);
  assert.equal(trace.max_spans.getProgramParameter.all.start_ms, linkStart);
  assert.equal(trace.max_spans.getProgramParameter.all.duration_ms, 2400);
  assert.equal(trace.max_spans.getProgramParameter.all.query_enum, 35714);
  assert.deepEqual(trace.max_spans.getProgramParameter.after_first_running, trace.max_spans.getProgramParameter.all);
  assert.equal(trace.calls.getShaderParameter.max_wall_ms, 1400);
  assert.equal(instance.invocations.length, 132);
});
