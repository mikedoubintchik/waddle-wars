"""Fail-closed auth/network isolation for copied visual QA HTML only.

Never reads browser storage, credentials or production saves. Original exported
HTML and PCK remain intact. Not a production-auth or full-shell performance test.
"""
import hashlib
import re

MARKER = 'WW_QA_OFFLINE_AUTH_V1'
CSP = '<meta http-equiv="Content-Security-Policy" content="connect-src \'self\'; frame-src \'none\'; form-action \'none\';" data-ww-qa="offline-network">'
AUTH_SCRIPT = """<script data-ww-qa="offline-auth">
// WW_QA_OFFLINE_AUTH_V1 — copied visual QA export only; no Clerk SDK/session.
(() => {
  const counters = {sign_in_attempts: 0, sign_out_attempts: 0, blocked_api_calls: 0};
  const auth = Object.freeze({ready: true, signedIn: false, name: '', token: '',
    loading: false, error: 'qa_offline', identityEpoch: 0,
    signIn() { counters.sign_in_attempts++; return false; },
    signOut() { counters.sign_out_attempts++; return false; }});
  Object.defineProperty(window, '__ww_auth', {value: auth, writable: false, configurable: false});
  Object.defineProperty(window, '__wwQAOffline', {value: Object.freeze({
    mode: 'offline_visual_qa', clerk_sdk_enabled: false, remote_connections_allowed: false,
    counters}), writable: false, configurable: false});
})();
</script>"""
API_SCRIPT = """<script data-ww-qa="offline-api">
// No request body, token or URL is retained. Bounded unavailable results only.
(() => {
  let sequence = 0;
  const pending = new Set();
  function blocked() {
    const id = ++sequence;
    window.__wwQAOffline.counters.blocked_api_calls++;
    if (pending.size >= 32) pending.delete(pending.values().next().value);
    pending.add(id);
    return id;
  }
  const api = Object.freeze({start: blocked, startReceipt: blocked,
    cancel(id) { pending.delete(id); },
    poll(id) {
      if (!pending.delete(id)) return '';
      return JSON.stringify({done: true, ok: false, status: 0,
        body: '{"error":"qa_offline"}'});
    }});
  Object.defineProperty(window, '__ww_api', {value: api, writable: false, configurable: false});
})();
</script>"""


def _replace_script(html, comment, replacement):
    if html.count(comment) != 1:
        raise ValueError('Expected exactly one production bridge: ' + comment)
    at = html.index(comment)
    start = html.rfind('<script>', 0, at)
    end = html.find('</script>', at)
    if start < 0 or end < 0 or '<script' in html[start + 8:at]:
        raise ValueError('Production bridge boundary is ambiguous')
    end += len('</script>')
    original = html[start:end]
    return html[:start] + replacement + html[end:], original


def install(html):
    if MARKER in html:
        raise ValueError('QA isolation already installed; refusing double patch')
    result, auth = _replace_script(html, '// Optional Clerk auth for the global leaderboard.', AUTH_SCRIPT)
    result, api = _replace_script(result, "// Plain-fetch bridge for the game's API calls:", API_SCRIPT)
    result, count = re.subn(r'<head(\s[^>]*)?>', lambda match: match.group(0) + '\n' + CSP, result, count=1)
    if count != 1:
        raise ValueError('Missing HTML head for pre-runtime connection fence')
    sha = lambda value: hashlib.sha256(value.encode()).hexdigest()
    receipt = {'mode': 'offline_visual_qa', 'production_pck_unchanged': True,
               'production_source_files_unchanged': True,
               'clerk_sdk_enabled': False, 'remote_connections_allowed': False,
               'removed_auth_script_sha256': sha(auth), 'removed_api_script_sha256': sha(api),
               'served_auth_script_sha256': sha(AUTH_SCRIPT), 'served_api_script_sha256': sha(API_SCRIPT),
               'input_html_sha256': sha(html), 'output_html_sha256': sha(result),
               'csp': "connect-src 'self'; frame-src 'none'; form-action 'none';",
               'limits': 'Auth, cloud sync, commerce transport and feedback submission are disabled; visual QA only.'}
    return result, receipt
