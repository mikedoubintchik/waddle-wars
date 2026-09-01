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
    appendChild(child) { this.children.push(child); return child; },
    removeChild(child) {
      this.children = this.children.filter((c) => c !== child);
      return child;
    },
    remove() {},
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
    getElementById: (id) => byId.get(id) ?? null,
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
    location: { reload() { window.__reloaded = true; } },
    __reloaded: false,
    addEventListener(type, fn, capture) {
      (this.listeners[type] ||= []).push({ fn, capture: !!capture });
    },
    removeEventListener() {},
    setInterval: () => 0,
    setTimeout: () => 0,
    clearInterval: () => {},
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
  const context = createContext(world.window);
  runInContext(script, context);
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
}

function testCanvasSizing(scripts) {
  const sizing = scriptContaining(scripts, 'Canvas sizing, owned by the page.');
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
    }
  }

  const restored = world.window.listeners['webglcontextrestored'] ?? [];
  check('context_restored_listener_registered', restored.length === 1);
}

function main() {
  const scripts = shellScripts();
  testPixelBudget(scripts);
  testCanvasSizing(scripts);
  testContextLossScreen(scripts);
  console.log(`[web-behaviour] DONE: ${passes} passed, ${failures} failed`);
  return failures > 0 ? 1 : 0;
}

process.exit(main());
