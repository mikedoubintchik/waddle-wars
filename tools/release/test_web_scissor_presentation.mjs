#!/usr/bin/env node
/** Exact SDK blitter model. Not a browser, GPU, or native concurrency proof. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const filename = process.argv[2];
if (!filename) throw new Error('Usage: node test_web_scissor_presentation.mjs EXACT_SDK_LIBWEBGL_JS');
const folder = dirname(fileURLToPath(import.meta.url));
const lock = JSON.parse(readFileSync(resolve(folder, 'web_worker_template.lock.json'), 'utf8'));
const variant = lock.qa_sdk_variants.scissor_is_enabled;
const digest = (value) => createHash('sha256').update(value).digest('hex');
const input = readFileSync(filename, 'utf8');
const baseline = input.replace(variant.replace_after, variant.replace_before);
const candidate = baseline.replace(variant.replace_before, variant.replace_after);

let checks = 0;
function check(name, callback) {
  callback();
  checks += 1;
  console.log(`PASS ${name}`);
}
check('pinned SDK hash and exactly one query replacement, no wrappers or other edits', () => {
  assert.equal(digest(baseline), variant.before_sha256);
  assert.equal(digest(candidate), variant.after_sha256);
  assert.ok(input === baseline || input === candidate, 'Unreviewed SDK edit');
  assert.equal(baseline.split(variant.replace_before).length - 1, 1);
  assert.equal(candidate.split(variant.replace_after).length - 1, 1);
  const beforeLines = baseline.split('\n');
  const afterLines = candidate.split('\n');
  assert.equal(beforeLines.length, afterLines.length);
  assert.equal(beforeLines.filter((line, index) => line !== afterLines[index]).length, 1);
  assert.equal(digest(readFileSync(resolve(folder, variant.patch_file))), variant.patch_sha256);
});

function blitter(source) {
  const startMarker = '    blitOffscreenFramebuffer: ';
  const endMarker = '\n    },\n#endif\n\n    registerContext:';
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, 'Pinned blitter boundaries changed');
  // Retain the WebGL2 if/else and fallback body; remove only preprocessor lines.
  const body = (source.slice(start + startMarker.length, end) + '\n    }').replace(/^#.*$/gm, '');
  return vm.runInNewContext(`(${body})`, {}, { filename, timeout: 1000 });
}
const oldBlit = blitter(baseline);
const newBlit = blitter(candidate);
const SCISSOR = 0xC11;

function context({ enabled = false, lost = false, branch = 'webgl2', failDraw = false } = {}) {
  const caps = new Set([0xBE2, 0xB71]);
  if (enabled) caps.add(SCISSOR);
  const state = { drawFbo: 'caller-fbo', readFbo: 'caller-fbo', program: 'caller-program',
    buffer: 'caller-buffer', texture: 'caller-texture', activeTexture: 0x84C0, vao: 'caller-vao' };
  const attribEnabled = [true, false, true];
  const calls = [];
  const draws = [];
  const gl = { canvas: { width: 540, height: 960 }, lost, calls, draws,
    getParameter(cap) {
      assert.equal(this, gl);
      calls.push(['getParameter', cap]);
      if (cap === SCISSOR) return this.lost ? null : caps.has(cap);
      const values = { [0x8CA6]: state.drawFbo, [0x8B8D]: state.program, [0x8894]: state.buffer,
        [0x84E0]: state.activeTexture, [0x8069]: state.texture, [0x85B5]: state.vao, [0x8869]: 3 };
      if (cap in values) return values[cap];
      if ([0xBE2, 0xB44, 0xB71, 0xB90].includes(cap)) return caps.has(cap);
      throw new Error(`Unmodeled getParameter ${cap}`);
    },
    isEnabled(cap) {
      assert.equal(this, gl);
      assert.equal(cap, SCISSOR, 'Only reviewed query may use isEnabled');
      calls.push(['isEnabled', cap]);
      return this.lost ? false : caps.has(cap);
    },
    enable(cap) { assert.equal(this, gl); calls.push(['enable', cap]); if (!this.lost) caps.add(cap); },
    disable(cap) { assert.equal(this, gl); calls.push(['disable', cap]); if (!this.lost) caps.delete(cap); },
    bindFramebuffer(target, value) {
      calls.push(['bindFramebuffer', target, value]);
      if (target !== 0x8CA8) state.drawFbo = value;
      if (target !== 0x8CA9) state.readFbo = value;
    },
    blitFramebuffer(...args) { draw('blitFramebuffer', args); },
    drawArrays(...args) { draw('drawArrays', args); },
    useProgram(value) { calls.push(['useProgram', value]); state.program = value; },
    isProgram(value) { calls.push(['isProgram', value]); return value !== null; },
    bindBuffer(target, value) { calls.push(['bindBuffer', target, value]); state.buffer = value; },
    activeTexture(value) { calls.push(['activeTexture', value]); state.activeTexture = value; },
    bindTexture(target, value) { calls.push(['bindTexture', target, value]); state.texture = value; },
    bindVertexArray(value) { calls.push(['bindVertexArray', value]); state.vao = value; },
    vertexAttribPointer(...args) { calls.push(['vertexAttribPointer', ...args]); },
    enableVertexAttribArray(index) { calls.push(['enableVertexAttribArray', index]); attribEnabled[index] = true; },
    disableVertexAttribArray(index) { calls.push(['disableVertexAttribArray', index]); attribEnabled[index] = false; },
    getVertexAttrib(index, cap) {
      calls.push(['getVertexAttrib', index, cap]);
      const values = { [0x889F]: 'attribute-buffer', [0x8623]: 4, [0x8624]: 16,
        [0x8625]: 0x1406, [0x886A]: false, [0x8622]: attribEnabled[index] };
      assert.ok(cap in values);
      return values[cap];
    },
    getVertexAttribOffset(...args) { calls.push(['getVertexAttribOffset', ...args]); return 8; },
    snapshot() { return { ...state, caps: [...caps].sort(), attribEnabled: [...attribEnabled] }; },
    restoreNativeDefaults() { this.lost = false; caps.clear(); },
  };
  function draw(name, args) {
    calls.push([name, ...args]);
    if (failDraw) throw new Error('native draw failure');
    draws.push({ name, args, clipped: !gl.lost && caps.has(SCISSOR), lost: gl.lost });
  }
  return { GLctx: gl, defaultFbo: 'offscreen-fbo', defaultFboForbidBlitFramebuffer: branch !== 'webgl2',
    defaultVao: branch === 'fallback-vao' ? 'blit-vao' : null,
    blitProgram: 'blit-program', blitVB: 'blit-buffer', blitPosLoc: 1 };
}
function normalizedCalls(gl) {
  return gl.calls.map(([name, ...args]) =>
    args[0] === SCISSOR && ['getParameter', 'isEnabled'].includes(name) ? ['scissor-query', ...args] : [name, ...args]);
}
function compare(options, operation = (blit, ctx) => blit(ctx)) {
  const oldContext = context(options);
  const newContext = context(options);
  operation(oldBlit, oldContext);
  operation(newBlit, newContext);
  assert.deepEqual(newContext.GLctx.snapshot(), oldContext.GLctx.snapshot());
  assert.deepEqual(newContext.GLctx.draws, oldContext.GLctx.draws);
  assert.deepEqual(normalizedCalls(newContext.GLctx), normalizedCalls(oldContext.GLctx));
  assert.equal(newContext.GLctx.calls.filter(([name, cap]) => name === 'getParameter' && cap === SCISSOR).length, 0);
  assert.ok(newContext.GLctx.calls.some(([name, cap]) => name === 'isEnabled' && cap === SCISSOR));
  return { oldContext, newContext };
}

for (const branch of ['webgl2', 'fallback-vao', 'fallback-client-attributes']) {
  for (const condition of ['enabled', 'disabled', 'lost']) {
    check(`${branch}: ${condition} preserves clipping, caller scissor and original state restoration`, () => {
      const enabled = condition === 'enabled';
      const lost = condition === 'lost';
      const { newContext } = compare({ branch, enabled, lost });
      assert.equal(newContext.GLctx.draws.length, 1);
      assert.equal(newContext.GLctx.draws[0].clipped, false);
      assert.equal(newContext.GLctx.draws[0].lost, lost);
      assert.equal(newContext.GLctx.snapshot().caps.includes(SCISSOR), enabled);
    });
  }
}
check('successive capability changes use native context state without custom cache', () => {
  compare({}, (blit, ctx) => {
    for (const enabled of [true, false, true, false]) {
      ctx.GLctx[enabled ? 'enable' : 'disable'](SCISSOR);
      blit(ctx);
      assert.equal(ctx.GLctx.snapshot().caps.includes(SCISSOR), enabled);
    }
  });
});
check('resize uses new backing dimensions and keeps same caller clip state', () => {
  const { newContext } = compare({ enabled: true }, (blit, ctx) => {
    blit(ctx);
    ctx.GLctx.canvas.width = 1920;
    ctx.GLctx.canvas.height = 1080;
    blit(ctx);
  });
  assert.deepEqual(newContext.GLctx.draws[1].args.slice(0, 8), [0, 0, 1920, 1080, 0, 0, 1920, 1080]);
});
check('context loss and restored native defaults require no stale custom capability state', () => {
  compare({ enabled: true }, (blit, ctx) => {
    blit(ctx);
    ctx.GLctx.lost = true;
    blit(ctx);
    ctx.GLctx.restoreNativeDefaults();
    blit(ctx);
    assert.equal(ctx.GLctx.snapshot().caps.includes(SCISSOR), false);
  });
});
check('interleaved contexts preserve independent true and false capability state', () => {
  const first = context({ enabled: true });
  const second = context({ enabled: false, branch: 'fallback-vao' });
  newBlit(first);
  newBlit(second);
  newBlit(first);
  assert.equal(first.GLctx.snapshot().caps.includes(SCISSOR), true);
  assert.equal(second.GLctx.snapshot().caps.includes(SCISSOR), false);
  assert.equal(first.GLctx.draws.length, 2);
});
check('modeled main-thread forwarding observes preceding worker capability commands', () => {
  compare({}, (blit, ctx) => {
    const forwarded = [() => ctx.GLctx.enable(SCISSOR), () => blit(ctx),
      () => ctx.GLctx.disable(SCISSOR), () => blit(ctx)];
    for (const call of forwarded) call();
  });
});
for (const branch of ['webgl2', 'fallback-vao']) {
  check(`${branch}: native draw exception and original partial-state behavior unchanged`, () => {
    compare({ branch, enabled: true, failDraw: true }, (blit, ctx) => {
      assert.throws(() => blit(ctx), /native draw failure/);
    });
  });
}
console.log(`${checks} SDK presentation contract checks passed. Browser/GPU/context-loss and performance acceptance remain required.`);
