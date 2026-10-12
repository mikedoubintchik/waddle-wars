// Exact shipping inline helper. Synthetic platform/media only; this is not a
// substitute for the real Chrome controls or an iOS silent-switch test.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';

const preset = readFileSync(new URL('../export_presets.cfg', import.meta.url), 'utf8');
const shell = preset.match(/html\/head_include="([\s\S]*?)"\n/)[1]
  .replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
const script = shell.match(/\/\/ WW_IOS_AUDIO_KEEPALIVE_BEGIN[\s\S]*?\/\/ WW_IOS_AUDIO_KEEPALIVE_END/)[0];
const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
const gestures = ['pointerup', 'click', 'touchend'];

class Events {
  listeners = new Map();
  addEventListener(type, callback) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(callback);
  }
  removeEventListener(type, callback) { this.listeners.get(type)?.delete(callback); }
  emit(type, properties = {}) {
    for (const callback of [...this.listeners.get(type) || []]) {
      callback({ type, currentTarget: this, isTrusted: true, ...properties });
    }
  }
  count(type) { return this.listeners.get(type)?.size || 0; }
  total() { return [...this.listeners.values()].reduce((sum, callbacks) => sum + callbacks.size, 0); }
}

function fixture({ userAgent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)',
  platform = 'iPhone', maxTouchPoints = 5, hidden = false, mode = 'resolve' } = {}) {
  const window = new Events(), document = new Events(), elements = [];
  document.hidden = hidden;
  document.createElement = type => {
    assert.equal(type, 'audio');
    if (mode === 'create-throw') throw new Error('synthetic creation failure');
    const element = new Events();
    Object.assign(element, { attributes: {}, plays: 0, pauses: 0, loads: 0, src: '', duration: NaN, readyState: 0 });
    element.setAttribute = (name, value) => { element.attributes[name] = value; };
    element.removeAttribute = name => { delete element.attributes[name]; if (name === 'src') element.src = ''; };
    element.pause = () => { element.pauses++; };
    element.load = () => { element.loads++; };
    element.play = () => {
      element.plays++;
      if (mode === 'play-throw') throw new Error('synthetic play failure');
      if (mode === 'legacy') return undefined;
      if (mode === 'reject') return Promise.reject(new Error('synthetic playback denial'));
      if (mode === 'pending') return new Promise((resolve, reject) => {
        element.resolve = resolve; element.reject = reject;
      });
      return Promise.resolve();
    };
    elements.push(element);
    return element;
  };
  const context = createContext({ window, document, navigator: { userAgent, platform, maxTouchPoints },
    btoa: input => Buffer.from(input, 'binary').toString('base64'),
    setTimeout() { assert.fail('helper must not automatically retry on a timer'); },
    setInterval() { assert.fail('helper must not install a recurring timer'); } });
  const install = () => runInContext(script, context);
  install();
  return { window, document, elements, install,
    click: trusted => window.emit('click', { isTrusted: trusted ?? true }),
    visibility(hidden) { document.hidden = hidden; document.emit('visibilitychange'); } };
}

test('desktop, Android, and touch Windows create no helper, audio, or listeners', () => {
  for (const identity of [
    { userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/154', platform: 'MacIntel', maxTouchPoints: 0 },
    { userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/154', platform: 'Win32', maxTouchPoints: 10 },
    { userAgent: 'Mozilla/5.0 (Linux; Android 16) Chrome/154', platform: 'Linux armv8l', maxTouchPoints: 5 },
    { userAgent: '', platform: '', maxTouchPoints: 0 },
  ]) {
    const f = fixture(identity); f.click();
    assert.equal(f.elements.length, 0); assert.equal(f.window.total(), 0); assert.equal(f.document.total(), 0);
    assert.equal(f.document.__ww_ios_audio_helper, undefined);
  }
});

test('iPhone, iPod, iPad, and desktop-UA iPadOS wait for a trusted gesture', () => {
  for (const identity of [
    {}, { userAgent: 'Mozilla/5.0 (iPod touch)', platform: 'iPod' },
    { userAgent: 'Mozilla/5.0 (iPad; CPU OS 18)', platform: 'iPad' },
    { userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', platform: 'MacIntel', maxTouchPoints: 5 },
  ]) {
    const f = fixture(identity);
    assert.equal(f.elements.length, 0); f.click(false); assert.equal(f.elements.length, 0);
    for (const gesture of gestures) assert.equal(f.window.count(gesture), 1);
    f.click(); assert.equal(f.elements.length, 1); assert.equal(f.elements[0].plays, 1);
    assert.equal(f.document.__ww_silent_keepalive, f.elements[0]);
  }
});

test('shipping payload decodes to exactly one second of valid PCM8 silence', () => {
  const f = fixture(); f.click();
  const element = f.elements[0];
  const wav = Buffer.from(element.src.split(',')[1], 'base64');
  assert.equal(wav.length, 8044); assert.equal(wav.toString('ascii', 0, 4), 'RIFF');
  assert.equal(wav.readUInt32LE(4), wav.length - 8); assert.equal(wav.toString('ascii', 8, 12), 'WAVE');
  assert.equal(wav.toString('ascii', 12, 16), 'fmt '); assert.equal(wav.readUInt32LE(16), 16);
  assert.equal(wav.readUInt16LE(20), 1); assert.equal(wav.readUInt16LE(22), 1);
  assert.equal(wav.readUInt32LE(24), 8000); assert.equal(wav.readUInt32LE(28), 8000);
  assert.equal(wav.readUInt16LE(32), 1); assert.equal(wav.readUInt16LE(34), 8);
  assert.equal(wav.toString('ascii', 36, 40), 'data'); assert.equal(wav.readUInt32LE(40), 8000);
  assert.equal(wav.readUInt32LE(40) / wav.readUInt32LE(28), 1);
  assert.ok(wav.subarray(44).every(sample => sample === 128));
  assert.equal(element.loop, true); assert.equal(element.preload, 'auto');
  assert.equal(element.attributes['x-webkit-airplay'], 'deny');
  assert.equal(element.muted, undefined, 'do not change game volume or mute the media-session workaround');
});

test('repeated gesture and duplicate installation retain exactly one element/listener set', async () => {
  const f = fixture(); f.install(); f.click(); await flush();
  for (let i = 0; i < 100; i++) for (const gesture of gestures) f.window.emit(gesture);
  assert.equal(f.elements.length, 1); assert.equal(f.elements[0].plays, 1);
  for (const gesture of gestures) assert.equal(f.window.count(gesture), 0);
  assert.equal(f.window.count('pagehide'), 1); assert.equal(f.window.count('pageshow'), 1);
  assert.equal(f.document.count('visibilitychange'), 1);
});

test('failed play retries only on a new trusted gesture and stops after three failures', async () => {
  const f = fixture({ mode: 'reject' });
  for (let attempt = 1; attempt <= 3; attempt++) {
    f.click(); await flush();
    assert.equal(f.elements.length, attempt); assert.equal(f.document.__ww_silent_keepalive, undefined);
    assert.equal(f.elements.at(-1).pauses, 1); assert.equal(f.elements.at(-1).loads, 1);
    assert.equal(f.elements.at(-1).src, '');
    await flush(); assert.equal(f.elements.length, attempt);
  }
  f.click(); f.visibility(true); f.visibility(false); f.click();
  assert.equal(f.elements.length, 3);
  for (const gesture of gestures) assert.equal(f.window.count(gesture), 0);
});

test('synchronous creation/play failure is contained with bounded gesture retries', () => {
  for (const mode of ['create-throw', 'play-throw']) {
    const f = fixture({ mode });
    for (let i = 0; i < 5; i++) f.click();
    assert.equal(f.elements.length, mode === 'create-throw' ? 0 : 3);
    assert.equal(f.document.__ww_silent_keepalive, undefined);
    for (const gesture of gestures) assert.equal(f.window.count(gesture), 0);
  }
});

test('media error releases source and permits a later gesture without an auto-loop', () => {
  const f = fixture(); f.click(); const failed = f.elements[0];
  failed.emit('error');
  assert.equal(failed.count('error'), 0); assert.equal(failed.pauses, 1); assert.equal(failed.loads, 1);
  assert.equal(f.elements.length, 1); assert.equal(f.document.__ww_silent_keepalive, undefined);
  f.click(); assert.equal(f.elements.length, 2);
});

test('decoded zero, near-zero, nonfinite duration is stopped and all media handlers released', () => {
  for (const duration of [0, 1 / 44100, 0.1, NaN, Infinity]) {
    const f = fixture(); f.click(); const element = f.elements[0];
    element.duration = duration; element.readyState = 1; element.emit('loadedmetadata');
    assert.equal(element.pauses, 1); assert.equal(element.loads, 1); assert.equal(element.src, '');
    assert.equal(element.total(), 0); assert.equal(f.document.__ww_silent_keepalive, undefined);
    f.click(); assert.equal(f.elements.length, 2, 'only a later trusted gesture can retry');
  }
});

test('initial unknown duration is ignored; real one-second metadata survives; later zero is stopped', () => {
  const f = fixture(); f.click(); const element = f.elements[0];
  element.emit('durationchange'); assert.equal(element.pauses, 0);
  element.duration = 1; element.readyState = 1; element.emit('loadedmetadata');
  assert.equal(element.pauses, 0); assert.equal(f.document.__ww_silent_keepalive, element);
  element.duration = 0; element.emit('durationchange');
  assert.equal(element.pauses, 1); assert.equal(element.total(), 0);
  assert.equal(f.document.__ww_silent_keepalive, undefined);
});

test('hidden page releases audio and resumes only on a fresh trusted gesture', async () => {
  const f = fixture();
  for (let i = 0; i < 5; i++) {
    f.click(); await flush(); const previous = f.elements.at(-1);
    f.visibility(true); f.click();
    assert.equal(previous.pauses, 1); assert.equal(previous.loads, 1); assert.equal(previous.src, '');
    assert.equal(previous.count('error'), 0); assert.equal(f.document.__ww_silent_keepalive, undefined);
    f.visibility(false); assert.equal(f.elements.length, i + 1);
  }
  f.click(); assert.equal(f.elements.length, 6, 'successful foreground visits do not exhaust failure budget');
});

test('pagehide cleans up even while visible; BFCache pageshow only rearms gesture', () => {
  const f = fixture(); f.click(); const previous = f.elements[0];
  f.window.emit('pagehide', { persisted: true }); f.click();
  assert.equal(previous.pauses, 1); assert.equal(previous.src, ''); assert.equal(f.elements.length, 1);
  assert.equal(f.document.__ww_silent_keepalive, undefined);
  f.window.emit('pageshow', { persisted: true }); assert.equal(f.elements.length, 1);
  f.click(); assert.equal(f.elements.length, 2);
});

test('pending play cannot accumulate elements; late rejection cannot clear a replacement', async () => {
  const f = fixture({ mode: 'pending' }); f.click(); const previous = f.elements[0];
  for (let i = 0; i < 100; i++) f.click(); assert.equal(f.elements.length, 1);
  f.visibility(true); f.visibility(false); f.click(); const replacement = f.elements[1];
  previous.reject(new Error('old source aborted')); await flush();
  assert.equal(f.document.__ww_silent_keepalive, replacement); assert.equal(replacement.pauses, 0);
  f.visibility(true); replacement.resolve(); await flush();
  assert.equal(f.document.__ww_silent_keepalive, undefined);
});

test('initial hidden page cannot start until visible and trusted gesture arrives', () => {
  const f = fixture({ hidden: true }); f.click(); assert.equal(f.elements.length, 0);
  for (const gesture of gestures) assert.equal(f.window.count(gesture), 0);
  f.visibility(false); assert.equal(f.elements.length, 0); f.click(); assert.equal(f.elements.length, 1);
});

test('legacy play without a Promise still remains single and cleans up', () => {
  const f = fixture({ mode: 'legacy' }); f.click(); f.click();
  assert.equal(f.elements.length, 1); f.window.emit('pagehide');
  assert.equal(f.document.__ww_silent_keepalive, undefined); assert.equal(f.elements[0].loads, 1);
});
