// Isolated, token-gated QA only. No interval, console history or pixel readback.
(() => {
  if (!window.__wwQA || !['127.0.0.1','localhost','[::1]'].includes(location.hostname)) return;
  let command, report;
  window.__wwDay = {
    _report: null,
    bind_callbacks(c, r) { command=c; report=r; },
    start(mode='continuous') { command(JSON.stringify({op:'start',mode})); return this.read(); },
    next() { command(JSON.stringify({op:'next'})); return this.read(); },
    stop() { command(JSON.stringify({op:'stop'})); return this.read(); },
    read() { return window.__wwQA.read(); },
    report() { report(); return { ...this._report, browser: this.read() }; }
  };
})();
