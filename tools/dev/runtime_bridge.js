// Injected into the copied export only. Godot calls onExit AFTER cleanup().
let devReadyResolve, devReadyReject, devExitResolve;
const devReady = new Promise((resolve, reject) => { devReadyResolve = resolve; devReadyReject = reject; });
const devExited = new Promise(resolve => { devExitResolve = resolve; });
window.__wwDevRuntime = {
  ready: devReady,
  exited: devExited,
  async stop() {
    await devReady;
    engine.requestQuit();
    return devExited;
  }
};
GODOT_CONFIG.args = [...(GODOT_CONFIG.args || []), '--audio-driver', 'Dummy'];
const devEngineStart = engine.startGame.bind(engine);
engine.startGame = (options = {}) => devEngineStart({
  ...options,
  args: GODOT_CONFIG.args,
  onExit(code) { devExitResolve(code); if (options.onExit) options.onExit(code); }
}).then(value => {
  devReadyResolve(value);
  return value;
}, error => { devReadyReject(error); throw error; });
