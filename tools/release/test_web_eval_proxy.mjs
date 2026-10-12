#!/usr/bin/env node
/** Exact Godot eval contract and Emscripten dispatch model, not native concurrency proof. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const filename = process.argv[2];
if (!filename) throw new Error('Usage: node test_web_eval_proxy.mjs EXACT_ENGINE_JS_FILE');
const lock = JSON.parse(readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'web_worker_template.lock.json'), 'utf8'));
const variant = lock.qa_variants.eval_main_thread;
const proxy = "\tgodot_js_eval__proxy: 'sync',\n";
const anchor = "\tgodot_js_eval__sig: 'iiiiiii',\n";
const input = readFileSync(filename, 'utf8');
const baseline = input.replace(proxy, '');
const patched = baseline.replace(anchor, anchor + proxy);
const digest = (value) => createHash('sha256').update(value).digest('hex');
assert.equal(digest(baseline), variant.before_sha256, 'Not the pinned official Godot source');
assert.equal(digest(patched), variant.after_sha256, 'Unexpected patch content');
assert.ok(input === baseline || input === patched, 'Reject unrelated source edits');

function realm(source, browser, memory = new SharedArrayBuffer(4096)) {
  const heap = new Uint8Array(memory);
  const values = new Map();
  const strings = new Map();
  const errors = [];
  const callbacks = [];
  const marks = [];
  let nextString = 1200;
  const sandbox = {
    HEAPU8: heap,
    LibraryManager: { library: {} },
    autoAddDeps() {},
    mergeInto(target, object) { Object.assign(target, object); },
    GodotRuntime: {
      parseString(pointer) { return strings.get(pointer); },
      setHeapValue(pointer, value, type) { values.set(pointer, { value, type }); },
      allocString(value) { const pointer = nextString++; strings.set(pointer, value); return pointer; },
      get_func(pointer) {
        assert.equal(pointer, 33);
        return (array, write, length) => {
          callbacks.push({ array, write, length });
          assert.equal(array, 11);
          assert.equal(write, 22);
          return 128;
        };
      },
      error(error) { errors.push(String(error)); },
    },
  };
  if (browser) {
    sandbox.window = { __waddleNativeBridgeQaMark: (mark) => marks.push(mark) };
    sandbox.document = { title: 'Waddle Wars QA' };
  }
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename });
  return {
    sandbox, heap, errors, marks, callbacks, values, strings,
    call(code, global = true) {
      strings.set(1, code);
      values.clear();
      return sandbox.LibraryManager.library.godot_js_eval(1, Number(global), 44, 11, 22, 33);
    },
  };
}

let count = 0;
function check(name, callback) {
  callback();
  count += 1;
  console.log(`PASS ${name}`);
}

check('official worker reproduces missing window without browser shim', () => {
  const worker = realm(baseline, false);
  assert.equal(worker.call("window.__waddleNativeBridgeQaMark('GO')"), 0);
  assert.equal(worker.errors.length, 1);
  assert.match(worker.errors[0], /window is not defined/);
});
check('only one proxy metadata field changes', () => {
  const original = realm(baseline, false).sandbox.LibraryManager.library;
  const candidate = realm(patched, false).sandbox.LibraryManager.library;
  assert.equal(original.godot_js_eval__proxy, undefined);
  assert.equal(candidate.godot_js_eval__proxy, 'sync');
  assert.equal(candidate.godot_js_eval__sig, original.godot_js_eval__sig);
  assert.equal(candidate.godot_js_eval.toString(), original.godot_js_eval.toString());
  assert.equal(candidate.godot_js_wrapper_object_transfer_buffer__proxy, 'sync');
});
check('sync dispatcher selects browser realm for DOM and QA transport', () => {
  const memory = new SharedArrayBuffer(4096);
  const worker = realm(patched, false, memory);
  const main = realm(patched, true, memory);
  const target = worker.sandbox.LibraryManager.library.godot_js_eval__proxy === 'sync' ? main : worker;
  assert.equal(target.call("window.__waddleNativeBridgeQaMark('GO'); document.title"), 4);
  assert.equal(target.strings.get(target.values.get(44).value), 'Waddle Wars QA');
  assert.deepEqual(main.marks, ['GO']);
  assert.deepEqual(worker.marks, []);
  assert.deepEqual(main.errors, []);
});
for (const [name, code, type, value, heapType] of [
  ['boolean true', 'true', 1, true, 'i32'],
  ['boolean false', 'false', 1, false, 'i32'],
  ['finite number', '3.14159', 3, 3.14159, 'double'],
  ['negative number', '-12', 3, -12, 'double'],
  ['infinity number', 'Infinity', 3, Infinity, 'double'],
  ['unicode string', "'fish 🐧'", 4, 'fish 🐧', '*'],
  ['empty string', "''", 4, '', '*'],
]) {
  check(`preserves ${name} return contract`, () => {
    for (const source of [baseline, patched]) {
      const main = realm(source, true);
      assert.equal(main.call(code), type);
      const result = main.values.get(44);
      assert.equal(result.type, heapType);
      assert.equal(type === 4 ? main.strings.get(result.value) : result.value, value);
    }
  });
}
for (const [name, code, expected] of [
  ['Uint8Array', 'new Uint8Array([3, 1, 4, 1, 5])', [3, 1, 4, 1, 5]],
  ['ArrayBuffer', 'new Uint8Array([9, 8, 7]).buffer', [9, 8, 7]],
  ['typed-array full-buffer behavior', 'new Uint16Array([0x0102, 0x0304])', [2, 1, 4, 3]],
  ['Uint8Array subview', 'new Uint8Array([5, 6, 7, 8]).subarray(1, 3)', [6, 7]],
  ['empty byte array', 'new Uint8Array(0)', []],
]) {
  check(`preserves ${name} resize callback and shared-memory bytes`, () => {
    for (const source of [baseline, patched]) {
      const memory = new SharedArrayBuffer(4096);
      const main = realm(source, true, memory);
      const workerHeap = new Uint8Array(memory);
      assert.equal(main.call(code), 29);
      assert.deepEqual(main.callbacks, [{ array: 11, write: 22, length: expected.length }]);
      assert.deepEqual([...workerHeap.subarray(128, 128 + expected.length)], expected);
      assert.equal(main.values.size, 0);
    }
  });
}
for (const code of ['null', 'undefined', '({ key: 1 })', '(() => 1)', "throw new Error('eval failure')"]) {
  check(`preserves NIL result for ${code}`, () => {
    for (const source of [baseline, patched]) {
      const main = realm(source, true);
      assert.equal(main.call(code), 0);
      assert.equal(main.values.size, 0);
      assert.equal(main.callbacks.length, 0);
      assert.equal(main.errors.length, code.startsWith('throw ') ? 1 : 0);
    }
  });
}
check('global and local evaluation remain distinct', () => {
  for (const source of [baseline, patched]) {
    const main = realm(source, true);
    assert.equal(main.call('typeof p_use_global_ctx'), 4);
    assert.equal(main.strings.get(main.values.get(44).value), 'undefined');
    assert.equal(main.call('p_use_global_ctx', false), 3);
    assert.equal(main.values.get(44).value, 0);
  }
});
console.log(`${count} eval proxy contract checks passed. Native callback concurrency/browser preflight still required.`);
