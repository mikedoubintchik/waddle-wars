// Injected only into a query-token-gated localhost QA export by its autoload.
// No telemetry history or game-side image readback. Production canvas untouched.
(() => {
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(location.hostname)) return;
  const query = new URLSearchParams(location.search);
  if (!query.get('qa_token')) return;
  let readCallback, commandCallback;
  window.__wwQA = {
    _reply: null,
    bind_callbacks(read, command) { readCallback = read; commandCallback = command; },
    read() {
      readCallback();
      const canvas = document.getElementById('canvas');
      return {...this._reply, capture_utc: new Date().toISOString(), source_url: location.href,
        build: window.__wwQABuild || null,
        canvas_backing: canvas ? [canvas.width, canvas.height] : null,
        canvas_css: canvas ? [canvas.clientWidth, canvas.clientHeight] : null,
        window_css: [innerWidth, innerHeight], dpr: devicePixelRatio,
        browser_visible: !document.hidden, browser_focused: document.hasFocus(),
        touch_points: navigator.maxTouchPoints || 0};
    },
    route(name) { commandCallback(JSON.stringify({op:'route', name})); return this.read(); },
    release() { commandCallback(JSON.stringify({op:'release'})); return this.read(); },
    stop() { commandCallback(JSON.stringify({op:'stop'})); }
  };
})();
