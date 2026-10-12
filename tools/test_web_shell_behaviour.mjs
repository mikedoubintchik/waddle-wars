// Behavioural tests for the web export's HTML shell.
//
// check_web_shell.py proves the shell parses. This runs it. The scripts in
// export_presets.cfg decide the single most consequential number in the
// browser build -- how many pixels a phone renders every frame -- and until
// now nothing exercised that arithmetic on a real device profile. A phone
// that renders 2 megapixels through a mobile tiler is the difference between
// the game feeling fine and feeling broken, and the only way that was ever
// checked was by loading it on a phone and squinting.
//
// The scripts are extracted from export_presets.cfg and run against a
// deliberately small DOM stub, one profile at a time, in a fresh vm context.
// No browser, no network: this runs anywhere the rest of the suite does.
//
//   node tools/test_web_shell_behaviour.mjs
//
// Exits 0 when every check passes, 1 otherwise.

import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const REPO = dirname(dirname(fileURLToPath(import.meta.url)));
const PRESETS = join(REPO, 'export_presets.cfg');

// The megapixel budget the shell targets on touch devices, and the caps it
// clamps to. Kept here so a change to the policy has to be a deliberate one.
const BUDGET_MP = 1.25;
const MIN_RATIO = 1.0;
const MAX_RATIO = 2.5;

let passes = 0;
let failures = 0;

function check(name, ok, detail = '') {
  if (ok) {
    passes += 1;
    console.log(`[web-behaviour] PASS ${name}`);
  } else {
    failures += 1;
    console.log(`[web-behaviour] FAIL ${name}${detail ? ': ' + detail : ''}`);
  }
}

function shellScripts() {
  const text = readFileSync(PRESETS, 'utf8');
  const match = text.match(/html\/head_include="([\s\S]*?)"\n/);
  if (!match) throw new Error('no html/head_include in export_presets.cfg');
  const shell = match[1]
    .replace(/\\n/g, '\n')
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\');
  return [...shell.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
}

function scriptContaining(scripts, marker) {
  const found = scripts.filter((s) => s.includes(marker));
  if (found.length !== 1) {
    throw new Error(`expected exactly one script containing ${marker}, got ${found.length}`);
  }
  return found[0];
}

// --- A DOM small enough to read, large enough to run the shell -------------

function makeElement(tag) {
  const el = {
    tagName: tag.toUpperCase(),
    style: { cssText: '' },
    children: [],
    attributes: {},
    textContent: '',
    id: '',
    hidden: false,
    listeners: {},
    width: 0,
    height: 0,
    setAttribute(k, v) { this.attributes[k] = String(v); },
    getAttribute(k) { return this.attributes[k] ?? null; },
    hasAttribute(k) { return Object.hasOwn(this.attributes, k); },
    removeAttribute(k) { delete this.attributes[k]; },
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
    removeChild(child) {
      this.children = this.children.filter((c) => c !== child);
      child.parentNode = null;
      return child;
    },
    remove() { if (this.parentNode) this.parentNode.removeChild(this); },
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); },
    getContext() { return null; },
  };
  el.style.width = '';
  el.style.height = '';
  return el;
}

function makeWorld(profile) {
  const canvas = makeElement('canvas');
  canvas.id = 'canvas';
  const head = makeElement('head');
  const body = makeElement('body');

  const byId = new Map();
  const document = {
    head,
    body,
    readyState: 'complete',
    documentElement: { clientWidth: profile.css[0], clientHeight: profile.css[1] },
    listeners: {},
    createElement: (tag) => makeElement(tag),
    getElementById(id) {
      if (id === 'canvas') return canvas;
      function find(node) {
        if (node.id === id) return node;
        for (const child of node.children) { const found = find(child); if (found) return found; }
        return null;
      }
      return find(body) || find(head);
    },
    querySelector(sel) {
      if (sel === 'canvas') return canvas;
      if (sel.startsWith('meta')) return null;
      return null;
    },
    addEventListener(type, fn) { (this.listeners[type] ||= []).push(fn); },
    removeEventListener() {},
  };
  // Anything the shell appends to body becomes findable by id, the way a real
  // document would -- the context-loss overlay is located that way.
  const appendToBody = body.appendChild.bind(body);
  body.appendChild = (child) => {
    if (child.id) byId.set(child.id, child);
    return appendToBody(child);
  };

  const window = {
    document,
    innerWidth: profile.css[0],
    innerHeight: profile.css[1],
    devicePixelRatio: profile.dpr,
    navigator: { maxTouchPoints: profile.touch ? 5 : 0, userAgent: profile.ua ?? '' },
    matchMedia: (q) => ({ matches: profile.touch && q.includes('coarse') }),
    listeners: {},
    location: { reload() { window.__reloaded = true; window.__reloadCount++; } },
    __reloadCount: 0,
    __reloaded: false,
    addEventListener(type, fn, capture) {
      (this.listeners[type] ||= []).push({ fn, capture: !!capture });
    },
    removeEventListener() {},
    setInterval: () => 0,
    setTimeout: () => 0,
    clearInterval: () => {},
    clearTimeout: () => {},
  };
  window.window = window;
  window.self = window;
  window.globalThis = window;
  window.console = console;
  window.Math = Math;
  window.visualViewport = profile.visualViewport ?? null;

  return { window, document, canvas, body };
}

function run(script, world) {
  world.context ||= createContext(world.window);
  runInContext(script, world.context);
}

// --- Device profiles -------------------------------------------------------
//
// Real CSS viewport and device pixel ratio values. The Android ones are what
// this pass was chasing; the iPhone entries are the devices already verified
// on hardware, kept so a policy change cannot quietly regress them.

const DEVICES = [
  { name: 'pixel_7', css: [412, 915], dpr: 2.625, touch: true },
  { name: 'pixel_9_pro_xl', css: [412, 923], dpr: 3.5, touch: true },
  { name: 'galaxy_s23', css: [360, 780], dpr: 3, touch: true },
  { name: 'galaxy_a54_small', css: [360, 640], dpr: 3, touch: true },
  { name: 'iphone_14_pro', css: [393, 852], dpr: 3, touch: true },
  { name: 'iphone_se', css: [375, 667], dpr: 2, touch: true },
  { name: 'ipad_air', css: [820, 1180], dpr: 2, touch: true },
  { name: 'desktop_1080p', css: [1920, 1080], dpr: 1, touch: false },
  { name: 'desktop_retina', css: [1728, 1117], dpr: 3, touch: false },
];

function testPixelBudget(scripts) {
  const policy = scriptContaining(scripts, 'Resolution policy');
  for (const device of DEVICES) {
    const world = makeWorld(device);
    run(policy, world);
    const effective = world.window.devicePixelRatio;
    const megapixels = (device.css[0] * device.css[1] * effective * effective) / 1e6;

    if (device.touch) {
      // The budget is a ceiling, not a target: a device whose native ratio is
      // already under it keeps its own, which is why the comparison is
      // against min(native, budget) rather than the budget alone.
      const withinBudget = megapixels <= BUDGET_MP + 0.02;
      const nativeWasLower = device.dpr <= effective + 1e-6;
      check(
        `pixel_budget_${device.name}`,
        withinBudget || nativeWasLower,
        `${megapixels.toFixed(2)} Mp at dpr ${effective.toFixed(2)}`
      );
      check(
        `ratio_floor_${device.name}`,
        effective >= MIN_RATIO,
        `dpr fell to ${effective}`
      );
      check(
        `never_upscales_${device.name}`,
        effective <= device.dpr + 1e-6,
        `dpr rose from ${device.dpr} to ${effective}`
      );
    } else {
      check(
        `desktop_cap_${device.name}`,
        effective === Math.min(device.dpr, MAX_RATIO),
        `dpr ${effective} for native ${device.dpr}`
      );
    }
  }

  // The worst case the policy exists for: a large, dense phone. Without the
  // budget this renders over 4 Mp per frame in a single-threaded WASM build.
  const dense = { name: 'dense', css: [430, 932], dpr: 3, touch: true };
  const world = makeWorld(dense);
  const nativeMp = (dense.css[0] * dense.css[1] * 9) / 1e6;
  run(scriptContaining(scripts, 'Resolution policy'), world);
  const cappedMp =
    (dense.css[0] * dense.css[1] * world.window.devicePixelRatio ** 2) / 1e6;
  check(
    'pixel_budget_cuts_dense_phone_load',
    nativeMp > 3.5 && cappedMp <= BUDGET_MP + 0.02,
    `${nativeMp.toFixed(2)} Mp native -> ${cappedMp.toFixed(2)} Mp`
  );

  const desktop = makeWorld({name: 'desktop_cap_exact', css: [1470, 827], dpr: 3, touch: false});
  run(policy, desktop);
  check('production_desktop_dpr_caps_at_2_5',
    desktop.window.devicePixelRatio === 2.5,
    `effective dpr ${desktop.window.devicePixelRatio}`);
  check('production_coarse_surface_stays_within_1_25mp',
    cappedMp <= 1.25 + 1e-6,
    `${cappedMp.toFixed(4)} Mp`);
}

function testCanvasSizing(scripts) {
  const sizing = scriptContaining(scripts, 'Canvas sizing, owned by the page.');
  const resolution = scriptContaining(scripts, 'Resolution policy');
  // A zoomed-out iOS Safari reports a visual viewport WIDER than the layout
  // viewport. Sizing from that is the feedback loop that put a 472 px canvas
  // in a 402 px phone, so the layout viewport has to win.
  const profile = {
    name: 'zoomed_safari',
    css: [402, 780],
    dpr: 2,
    touch: true,
    visualViewport: { width: 472, height: 900, addEventListener() {} },
  };
  const world = makeWorld(profile);
  run(sizing, world);
  const fired = world.document.listeners['DOMContentLoaded'] ?? [];
  for (const fn of fired) fn();

  check(
    'canvas_css_width_follows_layout_viewport',
    world.canvas.style.width === '402px',
    `canvas style width ${world.canvas.style.width}`
  );
  check(
    'canvas_backing_store_matches_ratio',
    world.canvas.width === Math.round(402 * 2) &&
      world.canvas.height === Math.round(780 * 2),
    `${world.canvas.width}x${world.canvas.height}`
  );
  check(
    'canvas_sizing_ignores_zoomed_visual_viewport',
    world.canvas.style.width !== '472px',
    'sized from visualViewport, which preserves the zoom'
  );

  // Exact current desktop production geometry reported by Chrome: CSS layout
  // 1470x827 at DPR 2 must remain a 2940x1654 backing store.
  const desktop = makeWorld({name: 'reported_desktop', css: [1470, 827], dpr: 2, touch: false});
  run(resolution, desktop);
  run(sizing, desktop);
  for (const fn of desktop.document.listeners.DOMContentLoaded ?? []) fn();
  check('production_desktop_1470x827_dpr2_backing',
    desktop.canvas.width === 2940 && desktop.canvas.height === 1654,
    `${desktop.canvas.width}x${desktop.canvas.height}`);

  // The page fitter avoids redundant backing/CSS writes; its 500 ms poll and
  // resize listener therefore do not continually invalidate an unchanged canvas.
  let backingWidth = desktop.canvas.width, backingHeight = desktop.canvas.height;
  let cssWidth = desktop.canvas.style.width, cssHeight = desktop.canvas.style.height;
  const writes = {backing: 0, css: 0};
  Object.defineProperty(desktop.canvas, 'width', {configurable: true,
    get: () => backingWidth, set: value => { writes.backing++; backingWidth = value; }});
  Object.defineProperty(desktop.canvas, 'height', {configurable: true,
    get: () => backingHeight, set: value => { writes.backing++; backingHeight = value; }});
  Object.defineProperty(desktop.canvas.style, 'width', {configurable: true,
    get: () => cssWidth, set: value => { writes.css++; cssWidth = value; }});
  Object.defineProperty(desktop.canvas.style, 'height', {configurable: true,
    get: () => cssHeight, set: value => { writes.css++; cssHeight = value; }});
  for (const listener of desktop.window.listeners.resize ?? []) listener.fn();
  check('canvas_resize_identical_dimensions_no_writes',
    writes.backing === 0 && writes.css === 0, JSON.stringify(writes));

  desktop.document.documentElement.clientWidth = 1400;
  desktop.document.documentElement.clientHeight = 800;
  desktop.window.innerWidth = 1400;
  desktop.window.innerHeight = 800;
  for (const listener of desktop.window.listeners.resize ?? []) listener.fn();
  check('canvas_resize_updates_css_and_backing',
    desktop.canvas.style.width === '1400px' && desktop.canvas.style.height === '800px' &&
      desktop.canvas.width === 2800 && desktop.canvas.height === 1600,
    `${desktop.canvas.style.width} ${desktop.canvas.style.height} / ` +
      `${desktop.canvas.width}x${desktop.canvas.height}`);
}

function testContextLossScreen(scripts) {
  const recovery = scriptContaining(scripts, 'webglcontextlost');
  const world = makeWorld(DEVICES[0]);
  run(recovery, world);

  const lost = (world.window.listeners['webglcontextlost'] ?? []);
  check('context_loss_listener_registered', lost.length === 1);
  check(
    'context_loss_listener_captures',
    lost.length === 1 && lost[0].capture === true,
    'must run before the canvas handler that raises Godot\'s alert()'
  );

  let prevented = false;
  let stopped = false;
  if (lost.length === 1) {
    lost[0].fn({
      target: world.canvas,
      preventDefault() { prevented = true; },
      stopPropagation() { stopped = true; },
    });
  }
  check('context_loss_prevents_default', prevented);
  check('context_loss_stops_propagation', stopped,
    'without this Godot still shows its blocking alert()');

  const overlay = world.document.getElementById('ww-gpu-lost');
  check('context_loss_overlay_shown', overlay !== null);
  if (overlay) {
    const text = overlay.children.map((c) => c.textContent).join(' ');
    check('context_loss_overlay_offers_reload', /Reload/.test(text), text);
    const button = overlay.children.find((c) => c.tagName === 'BUTTON');
    check('context_loss_overlay_has_button', !!button);
    if (button) {
      (button.listeners.click ?? []).forEach((fn) => fn());
      check('context_loss_reload_button_reloads', world.window.__reloaded === true);
      (button.listeners.click ?? []).forEach((fn) => fn());
      check('context_loss_reload_button_single_click', world.window.__reloadCount === 1 && button.disabled);
    }
  }

  const restored = world.window.listeners['webglcontextrestored'] ?? [];
  check('context_restored_listener_registered', restored.length === 1);
  const before = world.window.__reloadCount;
  for (let i = 0; i < 20; i++) {
    restored[0].fn({target: world.canvas});
    lost[0].fn({target: world.canvas, preventDefault() {}, stopPropagation() {}});
  }
  check('repeated_graphics_recovery_never_auto_reloads', world.window.__reloadCount === before);
  check('repeated_graphics_recovery_keeps_one_overlay',
    world.body.children.filter(n => n.id === 'ww-gpu-lost').length === 1);
  const other = makeWorld(DEVICES[0]); run(recovery, other);
  let intercepted = false;
  other.window.listeners.webglcontextlost[0].fn({target: makeElement('canvas'),
    preventDefault() {intercepted = true;}, stopPropagation() {intercepted = true;}});
  other.window.listeners.webglcontextrestored[0].fn({target: makeElement('canvas')});
  check('unrelated_canvas_loss_is_ignored', !intercepted && other.body.children.length === 0 && !other.window.__reloaded);
  const recoveredOnly = makeWorld(DEVICES[0]); run(recovery, recoveredOnly);
  recoveredOnly.window.listeners.webglcontextrestored[0].fn({target: recoveredOnly.canvas});
  check('recovery_without_loss_event_still_needs_user_retry',
    !!recoveredOnly.document.getElementById('ww-gpu-lost') && !recoveredOnly.window.__reloaded);

}

function adviceWorld(options = {}) {
  const profile = {css: [1470, 936], dpr: 2, touch: false,
    ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/154.0.0.0 Safari/537.36',
    ...options.profile};
  const world = makeWorld(profile);
  const calls = [];
  const observers = [];
  const timers = new Map();
  let timerId = 0;
  world.window.setTimeout = (callback, delay) => { timers.set(++timerId, {callback, delay}); return timerId; };
  world.window.clearTimeout = (id) => timers.delete(id);
  world.window.MutationObserver = class {
    constructor(callback) { this.callback = callback; this.disconnected = false; observers.push(this); }
    observe(target, config) { this.target = target; this.config = config; }
    disconnect() { this.disconnected = true; }
    deliver() { if (!this.disconnected) this.callback([]); }
  };
  const notice = makeElement('div'); notice.id = 'status-notice'; notice.style.display = 'none';
  world.body.appendChild(notice);
  const gl = {
    getExtension(name) {
      calls.push(['getExtension', name]);
      if (options.throwExtension) throw new Error('private extension error');
      return options.restricted ? null : {};
    },
    getParameter(queryEnum) {
      calls.push(['getParameter', queryEnum]);
      if (options.throwParameter) throw new Error('private renderer error');
      return Object.hasOwn(options, 'renderer') ? options.renderer
        : 'ANGLE (Apple, ANGLE Metal Renderer: Apple M2, Unspecified Version)';
    },
  };
  world.canvas.getContext = (...args) => {
    calls.push(['getContext', ...args]);
    if (options.throwContext) throw new Error('private context error');
    return options.noContext ? null : gl;
  };
  let focused = 0, reloaded = 0;
  world.canvas.focus = () => { focused++; };
  world.window.location.reload = () => { reloaded++; };
  const created = [];
  const create = world.document.createElement;
  world.document.createElement = tag => { created.push(tag); return create(tag); };
  const inspect = () => world.window.__wwGraphicsAdvice.inspectRunningCanvas();
  const card = () => world.document.getElementById('ww-graphics-advice');
  return {...world, calls, observers, timers, notice, inspect, card, created,
    focused: () => focused, reloaded: () => reloaded};
}

function content(node) {
  return node ? [node.textContent, ...node.children.map(content)].join(' ') : '';
}

function event(key = '') {
  return {key, prevented: false, stopped: false,
    preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }};
}

function testGraphicsAdvice(scripts) {
  const advice = scriptContaining(scripts, '// Graphics acceleration advice');
  const hw = adviceWorld();
  run(advice, hw);
  check('graphics_advice_no_preengine_context_or_canvas_creation', hw.calls.length === 0 && hw.created.length === 0);
  check('graphics_advice_bounded_notice_observer_only', hw.observers.length === 1 &&
    hw.observers[0].target === hw.notice && hw.observers[0].config.subtree === true &&
    hw.observers[0].config.attributeFilter.join(',') === 'style' &&
    [...hw.timers.values()].every(timer => timer.delay === 30000));
  hw.inspect(); hw.inspect();
  check('graphics_advice_hardware_no_warning_once', hw.card() === null &&
    JSON.stringify(hw.calls) === JSON.stringify([['getContext', 'webgl2'],
      ['getExtension', 'WEBGL_debug_renderer_info'], ['getParameter', 37446]]));
  check('graphics_advice_boot_stops_observer_and_timer', hw.observers[0].disconnected && hw.timers.size === 0);

  for (const renderer of ['SwiftShader Device', 'Mesa llvmpipe', 'SOFTPIPE',
    'Software Rasterizer', 'GDI Generic', 'Microsoft Basic Render Driver']) {
    const world = adviceWorld({renderer}); run(advice, world); world.inspect();
    const card = world.card();
    check(`graphics_advice_software_${renderer.replaceAll(' ', '_')}`, !!card &&
      /reports software graphics/.test(content(card)) &&
      /cannot read that browser setting/.test(content(card)) &&
      /Settings > System > Use graphics acceleration when available/.test(content(card)) &&
      /save work.*before relaunching/.test(content(card)));
    check(`graphics_advice_renderer_private_${renderer.replaceAll(' ', '_')}`,
      !content(card).includes(renderer) && Object.keys(world.window.__wwGraphicsAdvice).join(',') === 'inspectRunningCanvas');
  }
  const software = adviceWorld({renderer: 'SwiftShader'}); run(advice, software); software.inspect();
  const card = software.card(); const button = card.children.find(child => child.tagName === 'BUTTON');
  check('graphics_advice_accessible_nonblocking_card', card.attributes.role === 'region' &&
    card.attributes['aria-live'] === 'polite' && card.attributes['aria-labelledby'] === 'ww-graphics-advice-title' &&
    button.type === 'button' && button.textContent === 'Continue' &&
    /safe-area-inset/.test(card.style.cssText) && software.focused() === 0);
  const tab = event('Tab'); card.listeners.keydown[0](tab);
  check('graphics_advice_preserves_keyboard_tab_navigation', tab.stopped && !tab.prevented);
  const click = event(); button.listeners.click[0](click); software.inspect();
  check('graphics_advice_dismiss_no_click_focus_reload_leak', click.prevented && click.stopped &&
    software.card() === null && software.calls.length === 3 && software.focused() === 0 && software.reloaded() === 0);
  for (const key of ['Enter', ' ', 'Escape']) {
    const world = adviceWorld({renderer: 'SwiftShader'}); run(advice, world); world.inspect();
    const button = world.card().children.find(child => child.tagName === 'BUTTON'); const keyEvent = event(key);
    button.listeners.keydown[0](keyEvent);
    check(`graphics_advice_keyboard_dismiss_${key === ' ' ? 'Space' : key}`,
      keyEvent.prevented && keyEvent.stopped && world.card() === null && world.focused() === 0);
  }
  for (const options of [{restricted: true, renderer: 'WebKit WebGL'}, {renderer: 'Unknown GPU'},
    {renderer: null}, {noContext: true}, {throwContext: true}, {throwExtension: true}, {throwParameter: true}]) {
    const world = adviceWorld(options); run(advice, world); world.inspect(); world.inspect();
    check(`graphics_advice_unknown_safe_${JSON.stringify(options)}`, world.card() === null &&
      world.calls.filter(row => row[0] === 'getContext').length === 1 && world.focused() === 0);
  }
  const maskedSoftware = adviceWorld({restricted: true, renderer: 'GDI Generic'});
  run(advice, maskedSoftware); maskedSoftware.inspect();
  check('graphics_advice_clear_software_masked_fallback', !!maskedSoftware.card() &&
    maskedSoftware.calls.some(row => row[0] === 'getParameter' && row[1] === 7937));
  for (const profile of [
    {touch: true, ua: 'Mozilla/5.0 (Linux; Android 15) Chrome/154.0.0.0 Mobile Safari/537.36'},
    {touch: true, ua: 'Mozilla/5.0 (iPhone) CriOS/154.0.0.0 Mobile Safari/604.1'},
    {ua: 'Mozilla/5.0 Firefox/144.0'}, {ua: ''},
  ]) {
    const world = adviceWorld({profile, renderer: 'SwiftShader'}); run(advice, world); world.inspect();
    check(`graphics_advice_generic_platform_${profile.ua || 'unknown'}`,
      /Update your browser and system software/.test(content(world.card())) &&
      !/Settings > System|desktop Chrome/.test(content(world.card())));
  }

  const fatalText = 'Error The following features required to run Godot projects on the Web are missing: '
    + 'WebGL2 - Check web browser configuration and hardware support';
  const fatal = adviceWorld(); run(advice, fatal);
  fatal.notice.textContent = fatalText; fatal.notice.style.display = 'block'; fatal.observers[0].deliver();
  check('graphics_advice_exact_fatal_preserved_without_context_probe', fatal.notice.textContent === fatalText &&
    fatal.card() && fatal.card().parentNode === fatal.notice && fatal.calls.length === 0 &&
    /does not tell us whether acceleration is switched off/.test(content(fatal.card())));
  check('graphics_advice_fatal_shows_error_stops_observer',
    fatal.observers[0].disconnected && fatal.timers.size === 0 && fatal.notice.style.overflow === 'auto');
  const fatalButton = fatal.card().children.find(child => child.tagName === 'BUTTON'); fatalButton.listeners.click[0](event());
  check('graphics_advice_fatal_dismiss_keeps_original_error', fatal.card() === null && fatal.notice.textContent === fatalText);

  const initialFatal = adviceWorld(); initialFatal.document.readyState = 'loading';
  initialFatal.notice.textContent = fatalText; initialFatal.notice.style.display = 'block';
  run(advice, initialFatal);
  check('graphics_advice_fatal_waits_until_load', initialFatal.card() === null);
  initialFatal.window.listeners.load[0].fn();
  check('graphics_advice_initial_fatal_detected_after_load', initialFatal.card() &&
    initialFatal.calls.length === 0 && initialFatal.observers.length === 0);
  for (const text of ['WebGL2 shader compilation error',
    'The following features required to run Godot projects on the Web are missing: Fetch - Check web browser version',
    'An unknown error occurred.']) {
    const world = adviceWorld(); run(advice, world);
    world.notice.textContent = text; world.notice.style.display = 'block'; world.observers[0].deliver();
    check(`graphics_advice_unrelated_error_not_acceleration_${text}`, world.card() === null &&
      world.notice.textContent === text && world.calls.length === 0);
  }
  const cap = adviceWorld(); run(advice, cap);
  for (let i = 0; i < 40; i++) cap.observers[0].deliver();
  check('graphics_advice_observer_callback_cap_stops', cap.observers[0].disconnected && cap.timers.size === 0);
  const deadline = adviceWorld(); run(advice, deadline);
  [...deadline.timers.values()][0].callback();
  check('graphics_advice_observer_deadline_stops', deadline.observers[0].disconnected && deadline.timers.size === 0);
  check('graphics_advice_no_persistence_network_logging_polling_or_monkeypatch',
    !/localStorage|sessionStorage|fetch\(|console\.|prototype|setInterval|requestAnimationFrame/.test(advice));
  const bootSource = readFileSync(join(REPO, 'scripts/ui/boot.gd'), 'utf8');
  check('graphics_advice_boot_hook_web_guard_once',
    bootSource.includes('if OS.has_feature("web"):\n\t\tJavaScriptBridge.eval(') &&
    (bootSource.match(/window\.__wwGraphicsAdvice\.inspectRunningCanvas\(\)/g) || []).length === 1);
}

function testForwardOnlyDownloadBar(scripts) {
  const script = scriptContaining(scripts, '// Follow Godot\'s real downloaded-byte count');
  const world = makeWorld(DEVICES.find(device => device.name === 'iphone_14_pro'));
  const status = makeElement('div'); status.id = 'status'; status.isConnected = true;
  const nativeBar = makeElement('progress'); nativeBar.id = 'status-progress';
  const notice = makeElement('div'); notice.id = 'status-notice'; notice.style.display = 'none';
  status.appendChild(nativeBar); status.appendChild(notice); world.body.appendChild(status);
  const observers = [];
  world.window.MutationObserver = class {
    constructor(callback) { this.callback = callback; this.disconnected = false; observers.push(this); }
    observe() {}
    disconnect() { this.disconnected = true; }
  };
  let cleared = false;
  let deadline;
  world.window.setTimeout = callback => { deadline = callback; return 1; };
  world.window.clearTimeout = id => { cleared = id === 1; };
  run(script, world);
  const layer = world.document.getElementById('ww-boot-layer');
  layer.isConnected = true;
  const track = world.document.getElementById('ww-progress-track');
  const fill = world.document.getElementById('ww-progress-fill');
  check('single_startup_cover_starts_empty_and_determinate', !!layer && !!track && !!fill &&
    track.attributes.role === 'progressbar' && track.attributes['aria-valuenow'] === '0' &&
    nativeBar.attributes['aria-hidden'] === 'true' && fill.style.transform === undefined);
  nativeBar.value = 25; nativeBar.max = 100;
  nativeBar.setAttribute('value', '25'); nativeBar.setAttribute('max', '100');
  observers[0].callback();
  check('download_bar_follows_real_bytes', fill.style.transform === 'scaleX(0.25)' &&
    track.attributes['aria-valuenow'] === '25');
  nativeBar.value = 10; nativeBar.setAttribute('value', '10'); observers[0].callback();
  nativeBar.removeAttribute('value'); nativeBar.removeAttribute('max'); observers[0].callback();
  check('download_bar_never_reverses_or_marquees', fill.style.transform === 'scaleX(0.25)');
  nativeBar.value = 80; nativeBar.max = 100;
  nativeBar.setAttribute('value', '80'); nativeBar.setAttribute('max', '100');
  observers[0].callback();
  check('download_bar_resumes_forward_after_unknown_phase',
    fill.style.transform === 'scaleX(0.8)' && track.attributes['aria-valuenow'] === '80');
  nativeBar.value = 100; nativeBar.setAttribute('value', '100'); observers[0].callback();
  check('startup_cover_distinguishes_engine_phase',
    track.attributes['aria-valuenow'] === '100' &&
    world.document.getElementById('ww-boot-message').textContent === 'Opening the game…' &&
    layer.parentNode === world.body);
  deadline();
  const retry = world.document.getElementById('ww-boot-retry');
  check('startup_cover_offers_recovery_only_after_deadline',
    retry.style.display === 'block' &&
    world.document.getElementById('ww-boot-message').textContent ===
      'Taking longer than expected…');
  retry.listeners.click[0]();
  check('startup_cover_retry_reloads', world.window.__reloaded);
  notice.style.display = 'block'; observers[0].callback();
  check('startup_cover_reveals_native_error', layer.parentNode === null &&
    observers[0].disconnected && cleared);
  const ready = makeWorld(DEVICES.find(device => device.name === 'iphone_14_pro'));
  const readyStatus = makeElement('div'); readyStatus.id = 'status';
  const readyBar = makeElement('progress'); readyBar.id = 'status-progress';
  const readyNotice = makeElement('div'); readyNotice.id = 'status-notice';
  readyStatus.appendChild(readyBar); readyStatus.appendChild(readyNotice);
  ready.body.appendChild(readyStatus);
  ready.window.MutationObserver = class { observe() {} disconnect() {} };
  run(script, ready);
  const readyLayer = ready.document.getElementById('ww-boot-layer');
  ready.window.__wwBootReady();
  check('startup_cover_closes_only_on_menu_draw', readyLayer.parentNode === null &&
    ready.window.__wwBootReady === null);
}

function main() {
  const scripts = shellScripts();
  const preset = readFileSync(PRESETS, 'utf8');
  const boot = readFileSync(join(REPO, 'scripts/ui/boot.gd'), 'utf8');
  const menu = readFileSync(join(REPO, 'scripts/ui/main_menu_premium.gd'), 'utf8');
  const config = readFileSync(join(REPO, 'scripts/utilities/game_config.gd'), 'utf8');
  const webPreset = preset.match(/\[preset\.4\]([\s\S]*?)\[preset\.4\.options\]/)?.[1] ?? '';
  const runtimeArt = JSON.parse(readFileSync(join(REPO, 'assets/art/art_manifest.json'), 'utf8'));
  const excludesRaceArt = webPreset.includes('assets/art/courses/*') &&
    webPreset.includes('assets/art/ui/course_posters/*');
  const excludesDayReview = webPreset.includes('assets/art/runner/day/*');
  const dayPromoted = runtimeArt.assets.some(asset =>
    String(asset.id).startsWith('runner_day_') && asset.production_ready === true);
  check('web_race_art_filter_requires_hidden_race', !excludesRaceArt ||
    config.includes('const RACE_VISIBLE_IN_MVP: bool = false'));
  check('web_day_review_filter_requires_unpromoted_art', !excludesDayReview ||
    !dayPromoted);
  check('one_branded_startup_cover', preset.includes('ww-boot-layer') &&
    !preset.includes('Waddling in') && menu.includes('window.__wwBootReady();'));
  check('startup_cover_waits_for_router_completion',
    menu.includes('while SceneRouter.is_presenting()') &&
    menu.includes('not SceneRouter.is_loading_recovery_active()') &&
    menu.indexOf('while SceneRouter.is_presenting()') <
      menu.indexOf('window.__wwBootReady();'));
  check('boot_routes_directly_to_main_menu',
    boot.includes('SceneRouter.go_to(Game.SCENE_MAIN_MENU)') &&
    !boot.includes('SceneRouter.go_to(Game.SCENE_TITLE)'));
  check('web_boot_has_no_hidden_minimum_hold',
    boot.includes('BootWarmup.warm(SceneRouter)') &&
    boot.includes('SceneRouter.go_to(Game.SCENE_MAIN_MENU)') &&
    !boot.includes('MIN_HOLD') && !boot.includes('_elapsed'));
  const router = readFileSync(join(REPO, 'scripts/utilities/scene_router.gd'), 'utf8');
  check('web_boot_skips_hidden_router_fade',
    /if _from_boot:\s+_fade_rect\.modulate\.a = 1\.0\s+_begin_threaded_load\(scene_path, _transition_serial\)\s+return\s+_transition_tween = create_tween\(\)/.test(router));
  check('home_back_does_not_reopen_title', !menu.includes('Game.SCENE_TITLE'));
  testPixelBudget(scripts);
  testCanvasSizing(scripts);
  testContextLossScreen(scripts);
  testGraphicsAdvice(scripts);
  testForwardOnlyDownloadBar(scripts);
  console.log(`[web-behaviour] DONE: ${passes} passed, ${failures} failed`);
  return failures > 0 ? 1 : 0;
}

process.exit(main());
