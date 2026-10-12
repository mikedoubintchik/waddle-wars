import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('memory', ROOT/'tools/release/web_pack_memory.py')
memory = importlib.util.module_from_spec(spec); spec.loader.exec_module(memory)
TEMPLATE = Path.home()/'Library/Application Support/Godot/export_templates/4.7.1.stable/web_nothreads_release.zip'

class PackMemoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(TEMPLATE) as z:
            cls.text = z.read('godot.js').decode()

    def test_reviewed_sdk_and_only_one_change(self):
        optimized = memory.optimize_text(self.text)
        self.assertEqual(optimized.replace(memory.OWNED, memory.ORIGINAL), self.text)
        self.assertEqual(optimized.count(memory.OWNED), 1)

    def test_unknown_sdk_fails_closed(self):
        with self.assertRaises(ValueError): memory.optimize_text(self.text+'\n')
        with self.assertRaises(ValueError): memory.optimize_text(memory.optimize_text(self.text))

    def test_real_memfs_owns_pack_but_copies_other_files(self):
        # Execute the actual pinned SDK's MEMFS write implementation, not a mock.
        start = self.text.index('write(stream,buffer,offset,length,position,canOwn){')
        end = self.text.index(',llseek', start)
        method = self.text[start:end]
        program = r'''
const assert = require('node:assert/strict');
const HEAP8 = new Uint8Array(64);
const MEMFS = {expandFileStorage(){throw Error('Unexpected expansion');}};
const writer = ({METHOD}).write;
for (const path of ['index.pck','small.json','index.pck.fake']) {
  const input = new Uint8Array([2,3,5,7,11]), stream={node:{contents:null,usedBytes:0}};
  const count=writer(stream,input,0,input.length,0,path.endsWith('.pck'));
  assert.equal(count,input.length); assert.deepEqual([...stream.node.contents],[2,3,5,7,11]);
  assert.equal(stream.node.contents.buffer===input.buffer,path==='index.pck');
}
const stream={node:{contents:null,usedBytes:0}};
writer(stream,HEAP8,0,8,0,true);
assert.notEqual(stream.node.contents.buffer,HEAP8.buffer,'WASM heap still cannot be owned');
console.log('4 actual MEMFS ownership cases pass');
'''.replace('METHOD',method)
        result=subprocess.run(['node','-e',program],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)

if __name__ == '__main__': unittest.main(verbosity=2)
