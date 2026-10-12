// One runtime at a time. Kept separate so real async races can be tested in Node.
export class RuntimeSwitcher {
  constructor({ mount, report, settle = () => new Promise(r => setTimeout(r, 500)) }) {
    this.mount = mount; this.report = report; this.settle = settle;
    this.active = null; this.desired = null; this.busy = false; this.blocked = false;
    this.history = [];
  }
  request(build) { this.desired = build; return this.pump(); }
  retry() { this.blocked = false; return this.pump(); }
  event(type, id) {
    this.history.push({ type, id, at: Date.now() });
    if (this.history.length > 24) this.history.shift();
  }
  async pump() {
    if (this.busy || this.blocked) return;
    this.busy = true;
    try {
      while (this.desired && this.active?.id !== this.desired.id) {
        if (this.active) {
          this.report('Stopping previous game…');
          const old = this.active;
          this.event('quit_requested', old.id);
          // A timeout rejects. Keep old frame and stop here, never overlap.
          await old.stop();
          this.event('exit_observed', old.id);
          old.remove(); this.active = null;
          this.event('frame_removed', old.id);
          await this.settle();
        }
        // Latest request wins while teardown is pending.
        const build = this.desired;
        this.report('Loading updated game…');
        this.active = this.mount(build);
        this.event('frame_created', build.id);
        await this.active.ready;
        this.event('started', build.id);
        this.report('Ready · sound off · changes refresh automatically');
      }
    } catch (error) {
      this.blocked = true;
      this.report(`Reload stopped: ${error.message}. Retry after the game responds; close this tab if it remains stuck.`, true);
    } finally { this.busy = false; }
  }
}

export function bounded(promise, ms, message) {
  let timer;
  return Promise.race([promise, new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), ms);
  })]).finally(() => clearTimeout(timer));
}
