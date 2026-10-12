"""Source-only auth isolation checks. No browser, Godot or network requests."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('qa_export',ROOT/'tools/qa/chrome_reference_export.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
offline = qa.offline


class OfflineVisualQATest(unittest.TestCase):
    def fixture(self):
        sections = qa.helpers._preset_sections((ROOT/'export_presets.cfg').read_text())
        head = qa.helpers._quoted_multiline_option(sections['preset.4.options'],'html/head_include')
        return '<!doctype html><html><head>'+head+'</head><body><canvas></canvas><script>const engineSentinel="unchanged";</script></body></html>'

    def test_exactly_two_bridges_and_csp_change(self):
        before = self.fixture()
        after, receipt = offline.install(before)
        original_auth = re.search(r'<script>\s*// Optional Clerk auth.*?</script>',before,re.S).group(0)
        original_api = re.search(r'<script>\s*// Plain-fetch bridge.*?</script>',before,re.S).group(0)
        restored = after.replace('\n'+offline.CSP,'',1).replace(offline.AUTH_SCRIPT,original_auth,1).replace(offline.API_SCRIPT,original_api,1)
        self.assertEqual(restored,before)
        self.assertNotIn('clerk.browser.js',after)
        self.assertNotIn('session.getToken()',after)
        self.assertTrue(receipt['production_pck_unchanged'])
        self.assertFalse(receipt['remote_connections_allowed'])
        self.assertLess(after.index(offline.CSP),after.index('<script'))
        self.assertIn("connect-src 'self'; frame-src 'none'; form-action 'none';",after)

    def test_fail_closed_when_source_contract_changes(self):
        before = self.fixture()
        for invalid in [before.replace('// Optional Clerk auth for the global leaderboard.','changed'),
                        before.replace('// Plain-fetch bridge for the game\'s API calls:','changed'),
                        before.replace('<head>',''),before+before]:
            with self.assertRaises(ValueError):offline.install(invalid)
        once,_ = offline.install(before)
        with self.assertRaises(ValueError):offline.install(once)

    def test_stubs_cannot_restore_or_contact_real_account(self):
        node = shutil.which('node')
        self.assertIsNotNone(node,'Node required; missing runtime is not a pass')
        scripts = '\n'.join(re.search(r'<script[^>]*>(.*?)</script>',s,re.S).group(1)
                            for s in [offline.AUTH_SCRIPT,offline.API_SCRIPT])
        check = '''
const assert = require('node:assert/strict');
let external=0;
global.window={Clerk:{load(){external++;throw Error('must not load');},signOut(){external++;}}};
global.fetch=()=>{external++;throw Error('network forbidden');};
global.XMLHttpRequest=function(){external++;throw Error('network forbidden');};
'''+scripts+'''
assert.equal(window.__ww_auth.ready,true);
assert.equal(window.__ww_auth.signedIn,false);
assert.equal(window.__ww_auth.token,'');
assert.equal(window.__ww_auth.signIn(),false);
assert.equal(window.__ww_auth.signOut(),false);
assert.throws(()=>Object.defineProperty(window,'__ww_auth',{value:{signedIn:true}}));
let first,last;
for(let i=0;i<64;i++){last=window.__ww_api.start('PUT','https://example.invalid/api/save','synthetic-marker','synthetic-body');if(i===0)first=last;}
assert.equal(window.__ww_api.poll(first),'');
assert.equal(JSON.parse(window.__ww_api.poll(last)).ok,false);
assert.equal(window.__ww_api.poll(last),'');
let receipt=window.__ww_api.startReceipt('https://example.invalid','synthetic-marker');
window.__ww_api.cancel(receipt);
assert.equal(window.__ww_api.poll(receipt),'');
assert.equal(external,0);
assert.deepEqual(window.__wwQAOffline.counters,{sign_in_attempts:1,sign_out_attempts:1,blocked_api_calls:65});
console.log(JSON.stringify({assertions:12,external_calls:external}));
'''
        result = subprocess.run([node,'-e',check],capture_output=True,text=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(result.stdout)['external_calls'],0)


if __name__=='__main__':unittest.main()
