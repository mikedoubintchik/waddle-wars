import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';

const preset = readFileSync(new URL('../export_presets.cfg', import.meta.url), 'utf8');
const shell = preset.match(/html\/head_include="([\s\S]*?)"\n/)[1]
  .replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
const script = shell.match(/\/\/ WW_AUDIO_FOCUS_BEGIN[\s\S]*?\/\/ WW_AUDIO_FOCUS_END/)[0];
const manager = readFileSync(new URL('../scripts/utilities/audio_manager.gd', import.meta.url), 'utf8');
const quietQuery = JSON.parse(manager.match(/^const SESSION_QUIET_QUERY: String = (".*")$/m)[1]);

test('session quiet query requires the exact sound=off option; normal URLs remain unchanged', () => {
  for (const [search, expected] of [
    ['', false], ['?sound=off', true], ['?x=1&sound=off', true],
    ['?sound=%6Fff', true], ['?sound=on', false], ['?sound=', false],
    ['?sound=OFF', false], ['?muted=true', false], ['?sound=office', false],
    ['?sound=on&sound=off', false], ['?sound=off&sound=on', true],
  ]) {
    assert.equal(runInContext(quietQuery, createContext({ URLSearchParams,
      window: { location: { search } } })), expected, search);
  }
});

test('session query has no side effects or browser polling', () => {
  const seen = [];
  const location = { get search() { seen.push('query'); return '?sound=off'; } };
  const window = new Proxy({ location }, { get(target, key) {
    assert.equal(key, 'location', 'only location is accessed'); return target[key];
  }, set() { assert.fail('query must not modify window'); } });
  const result = runInContext(quietQuery, createContext({ URLSearchParams, window }));
  assert.equal(result, true);
  assert.deepEqual(seen, ['query']);
  assert.equal((manager.match(/JavaScriptBridge\.eval\(SESSION_QUIET_QUERY/g) || []).length, 1);
  const ready = manager.slice(manager.indexOf('func _ready()'), manager.indexOf('func _read_session_quiet()'));
  assert.ok(ready.indexOf('_session_quiet = _read_session_quiet()') < ready.indexOf('AudioStreamPlayer.new()'));
});
class Events {
  listeners = new Map();
  addEventListener(type, callback) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(callback);
  }
  emit(type, fields = {}) {
    for (const callback of this.listeners.get(type) || []) callback({ type, isTrusted: true, ...fields });
  }
  count() { return [...this.listeners.values()].reduce((total, group) => total + group.size, 0); }
}
function fixture({ hidden = false, focused = true } = {}) {
  const window = new Events(), document = new Events();
  document.hidden = hidden; document.focused = focused; document.hasFocus = () => document.focused;
  const context = createContext({ window, document,
    setTimeout() { assert.fail('focus bridge must not poll'); },
    setInterval() { assert.fail('focus bridge must not poll'); } });
  const install = () => runInContext(script, context); install();
  const events = [], callback = active => events.push(active), bridge = window.__ww_audio_focus;
  bridge.subscribe(callback);
  return { window, document, bridge, callback, events, install };
}

test('subscription immediately reports combined initial visibility/focus', () => {
  for (const hidden of [false, true]) for (const focused of [false, true]) {
    const f = fixture({ hidden, focused });
    assert.deepEqual(f.events, [!hidden && focused]);
  }
});
test('blur immediately mutes before hasFocus changes; focus restores visible page', () => {
  const f = fixture(); f.window.emit('blur');
  assert.deepEqual(f.events, [true, false]);
  f.document.focused = false; f.window.emit('focus');
  assert.deepEqual(f.events, [true, false, true], 'focus event remains authoritative during browser state update');
});
test('hidden tab stays inactive through stray focus and visible-but-unfocused return', () => {
  const f = fixture(); f.document.hidden = true; f.document.emit('visibilitychange');
  f.window.emit('focus'); assert.deepEqual(f.events, [true, false]);
  f.document.hidden = false; f.document.focused = false; f.document.emit('visibilitychange');
  assert.deepEqual(f.events, [true, false]);
  f.document.focused = true; f.window.emit('focus'); assert.deepEqual(f.events, [true, false, true]);
});
test('visible trusted interaction repairs missing mobile focus-in; synthetic/hidden events cannot', () => {
  for (const event of ['pointerdown', 'touchstart', 'keydown']) {
    const f = fixture({ focused: false }); f.window.emit(event, { isTrusted: false });
    assert.deepEqual(f.events, [false]);
    f.document.hidden = true; f.window.emit(event); assert.deepEqual(f.events, [false]);
    f.document.hidden = false; f.window.emit(event); assert.deepEqual(f.events, [false, true]);
  }
});
test('pagehide deactivates even before document.hidden and BFCache pageshow restores current state', () => {
  const f = fixture(); f.window.emit('pagehide'); assert.deepEqual(f.events, [true, false]);
  f.window.emit('pageshow'); assert.deepEqual(f.events, [true, false, true]);
});
test('duplicate focus events and script installation do not accumulate callbacks/listeners', () => {
  const f = fixture(); const count = f.window.count() + f.document.count(); f.install();
  for (let i = 0; i < 100; i++) { f.window.emit('focus'); f.document.emit('visibilitychange'); }
  assert.equal(f.window.count() + f.document.count(), count); assert.deepEqual(f.events, [true]);
});
test('unsubscribe releases old subscriber and does not remove replacement subscriber', () => {
  const f = fixture(); const replacement = []; const next = active => replacement.push(active);
  f.bridge.subscribe(next); f.bridge.unsubscribe(f.callback); f.window.emit('blur');
  assert.deepEqual(f.events, [true]); assert.deepEqual(replacement, [true, false]);
  f.bridge.unsubscribe(next); f.window.emit('focus'); assert.deepEqual(replacement, [true, false]);
  assert.equal(f.bridge.is_active(), true);
});
