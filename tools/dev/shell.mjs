import { RuntimeSwitcher, bounded } from '/web_lifecycle.mjs';
const host = document.querySelector('#game'), status = document.querySelector('#status');
const retry = document.querySelector('#retry');
let pageState = null, lastBuild = null;
const switcher = new RuntimeSwitcher({
  report(message, error = false) {
    status.textContent = message; status.classList.toggle('error', error); retry.hidden = !error;
  },
  mount(build) {
    if (host.querySelector('iframe')) throw new Error('Previous frame still exists');
    const frame = document.createElement('iframe');
    frame.title = 'Waddle Wars silent local preview';
    frame.allow = 'gamepad; fullscreen';
    frame.src = `/builds/${encodeURIComponent(build.id)}/index.html`;
    let bridge;
    const ready = new Promise((resolve, reject) => {
      frame.onload = () => {
        bridge = frame.contentWindow.__wwDevRuntime;
        if (!bridge) { reject(new Error('Development lifecycle bridge missing')); return; }
        bridge.ready.then(resolve, reject);
      };
      frame.onerror = () => reject(new Error('Game frame failed to load'));
    });
    // Snapshot only menu navigation, never save data or a partially running race.
    window.__wwDevRestoreState = pageState;
    host.append(frame);
    return {
      id: build.id,
      ready: bounded(ready, 120000, 'Game startup exceeded two minutes'),
      async stop() {
        bridge ||= frame.contentWindow.__wwDevRuntime;
        if (!bridge) throw new Error('Cannot confirm old engine teardown');
        pageState = frame.contentWindow.__wwDevPageState || pageState;
        await bounded(bridge.stop(), 20000, 'Old engine has not confirmed exit');
      },
      remove() { frame.onload = frame.onerror = null; frame.remove(); bridge = null; }
    };
  }
});
window.__wwDev = switcher; // Bounded scalar lifecycle history for Chrome checks.
retry.onclick = () => switcher.retry();
async function poll() {
  try {
    const response = await fetch('/status.json', { cache: 'no-store' });
    const state = await response.json();
    if (state.current && state.current.id !== lastBuild) {
      lastBuild = state.current.id;
      void switcher.request(state.current);
    }
    if (!switcher.busy && !switcher.blocked) {
      if (state.error) { status.textContent = `Build failed; current game retained. ${state.error}`; status.classList.add('error'); }
      else if (state.held) { status.textContent = 'Update in progress · current game stays available · sound off'; status.classList.remove('error'); }
      else if (state.building) { status.textContent = 'Building changes… current game stays available'; status.classList.remove('error'); }
      else if (state.current) { status.textContent = 'Ready · sound off · changes refresh automatically'; status.classList.remove('error'); }
    }
  } catch (_) { if (!switcher.busy) status.textContent = 'Local build server unavailable; current game retained'; }
  setTimeout(poll, 1500);
}
poll();
