#!/usr/bin/env node
/** Exact WebGL readback contract in modeled thread realms, not browser or native proof. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const filename = process.argv[2];
if (!filename) throw new Error('Usage: node test_web_readback_context.mjs EXACT_ENGINE_JS_FILE');
const lock = JSON.parse(readFileSync(resolve(dirname(fileURLToPath(import.meta.url)), 'web_worker_template.lock.json'), 'utf8'));
const variant = lock.qa_readback_variants.current_context;
const input = readFileSync(filename, 'utf8');
const baseline = input.replace(variant.replace_after, variant.replace_before);
const patched = baseline.replace(variant.replace_before, variant.replace_after);
const digest = (value) => createHash('sha256').update(value).digest('hex');
assert.equal(digest(baseline), variant.before_sha256, 'Not the pinned official Godot readback source');
assert.equal(digest(patched), variant.after_sha256, 'Unexpected readback patch content');
assert.ok(input === baseline || input === patched, 'Reject unrelated source edits');

function realm(source, { tlsHandle = 0, activeHandle = 17, memory = new SharedArrayBuffer(96) } = {}) {
  const heap = new Uint8Array(memory);
  heap.fill(0xa5);
  const calls = [];
  let tlsQueries = 0;
  const buffers = new Map([[17, new Uint8Array([11, 22, 33, 44, 55, 66])], [23, new Uint8Array([91, 82, 73, 64, 55, 46])]]);
  const contexts = new Map([...buffers.keys()].map((handle) => [handle, { handle, GLctx: {
    getBufferSubData(target, offset, destination, data, size) {
      calls.push({ handle, target, offset, data, size });
      assert.equal(destination, heap);
      assert.ok(offset >= 0 && offset + size <= buffers.get(handle).length);
      assert.ok(data >= 0 && data + size <= heap.length);
      destination.set(buffers.get(handle).subarray(offset, offset + size), data);
    },
  } }]));
  const sandbox = {
    HEAPU8: heap,
    LibraryManager: { library: {} },
    autoAddDeps() {},
    mergeInto(target, object) { Object.assign(target, object); },
    GodotRuntime: { error() { throw new Error('Unexpected unrelated WebGL error'); } },
    GL: { currentContext: contexts.get(activeHandle) || null, getContext: (handle) => contexts.get(handle) },
    _emscripten_webgl_get_current_context() { tlsQueries += 1; return tlsHandle; },
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename });
  const library = sandbox.LibraryManager.library;
  return { heap, calls, library, contexts, sandbox, tlsQueries: () => tlsQueries,
    read(target = 0x8892, offset = 0, size = 6, data = 24) {
      library.godot_webgl2_glGetBufferSubData(target, offset, size, data);
    } };
}

let count = 0;
function check(name, callback) {
  callback();
  count += 1;
  console.log(`PASS ${name}`);
}

check('official main-thread proxy with worker-only TLS leaves destination sentinel untouched', () => {
  const main = realm(baseline, { tlsHandle: 0 });
  main.read();
  assert.deepEqual([...main.heap.subarray(24, 30)], [0xa5, 0xa5, 0xa5, 0xa5, 0xa5, 0xa5]);
  assert.deepEqual(main.calls, []);
  assert.equal(main.tlsQueries(), 1);
});
check('fixed sync proxy reads active browser context without consulting wrong-thread TLS', () => {
  const memory = new SharedArrayBuffer(96);
  const workerHeap = new Uint8Array(memory);
  const main = realm(patched, { tlsHandle: 0, memory });
  main.read();
  assert.deepEqual([...workerHeap.subarray(24, 30)], [11, 22, 33, 44, 55, 66]);
  assert.equal(main.calls.length, 1);
  assert.equal(main.tlsQueries(), 0);
});
check('single-thread active context preserves exact baseline bytes', () => {
  for (const source of [baseline, patched]) {
    const main = realm(source, { tlsHandle: 17 });
    main.read();
    assert.deepEqual([...main.heap.subarray(24, 30)], [11, 22, 33, 44, 55, 66]);
  }
});
check('context switches select current context each call, never stale TLS or cached context', () => {
  const main = realm(patched, { tlsHandle: 17 });
  main.read();
  main.sandbox.GL.currentContext = main.contexts.get(23);
  main.read();
  assert.deepEqual(main.calls.map((call) => call.handle), [17, 23]);
  assert.deepEqual([...main.heap.subarray(24, 30)], [91, 82, 73, 64, 55, 46]);
  assert.equal(main.tlsQueries(), 0);
});
check('offset, length, destination pointer and buffer target remain unchanged', () => {
  const main = realm(patched);
  main.read(0x8893, 2, 3, 31);
  assert.deepEqual(main.calls, [{ handle: 17, target: 0x8893, offset: 2, size: 3, data: 31 }]);
  assert.deepEqual([...main.heap.subarray(30, 35)], [0xa5, 33, 44, 55, 0xa5]);
});
check('sync proxy signature and dependencies remain identical', () => {
  const before = realm(baseline).library;
  const after = realm(patched).library;
  for (const field of ['__proxy', '__sig', '__deps']) {
    const oldValue = before[`godot_webgl2_glGetBufferSubData${field}`];
    const newValue = after[`godot_webgl2_glGetBufferSubData${field}`];
    assert.deepEqual(Array.isArray(newValue) ? [...newValue] : newValue, Array.isArray(oldValue) ? [...oldValue] : oldValue);
  }
  assert.equal(after.godot_webgl2_glGetBufferSubData__proxy, 'sync');
  assert.equal(after.godot_webgl2_glGetBufferSubData__sig, 'vippp');
});
check('neighboring multiview functions and metadata remain unchanged', () => {
  const before = realm(baseline).library;
  const after = realm(patched).library;
  for (const name of ['godot_webgl2_glFramebufferTextureMultiviewOVR', 'godot_webgl2_glFramebufferTextureMultisampleMultiviewOVR']) {
    assert.equal(after[name].toString(), before[name].toString());
    for (const field of ['__proxy', '__sig', '__deps']) {
      const oldValue = before[name + field];
      const newValue = after[name + field];
      assert.deepEqual(Array.isArray(newValue) ? [...newValue] : newValue, Array.isArray(oldValue) ? [...oldValue] : oldValue);
    }
  }
});
console.log(`${count} readback context checks passed. Browser mesh-readback and visible-render acceptance still required.`);
