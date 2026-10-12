"""Guard lifecycle regression: closed renderer must not stop next page."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('watch', ROOT/'tools/qa/chrome_reference_watch.py')
watch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watch)

def sample(t, renderer=True, footprint=100, cpu=0):
    rows = [{'pid':1,'role':'browser','phys_footprint':100,'cpu_seconds':0}]
    if renderer:
        rows.append({'pid':2,'role':'renderer','phys_footprint':footprint,'cpu_seconds':cpu})
    return {'utc':str(t),'monotonic_s':t,'processes':rows}

class GuardLifecycleTest(unittest.TestCase):
    def run_case(self, samples, *, seconds=100, clock=None):
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            (out/'server.json').write_text('{}')
            original = '{"stop": false, "preserve": "unchanged"}\n'
            (out/'qa-stop.json').write_text(original)
            with patch.object(watch.counters, 'sample', side_effect=samples), \
                 patch.object(watch.time, 'sleep'), \
                 patch.object(watch.time, 'monotonic', side_effect=clock or [0,1,2,3]), \
                 contextlib.redirect_stdout(io.StringIO()):
                watch.run(out, 2, seconds, 1)
            return ((out/'qa-stop.json').read_text(),
                    json.loads((out/'guard-end.json').read_text()),
                    [json.loads(s) for s in (out/'guard-counters.jsonl').read_text().splitlines()], original)

    def test_renderer_exit_preserves_false_marker_byte_for_byte(self):
        marker, end, rows, original = self.run_case([sample(0), sample(1, renderer=False)])
        self.assertEqual(marker, original)
        self.assertFalse(end['engine_stop_requested'])
        self.assertEqual(end['reason'], 'Observed QA renderer exited; stop watcher')
        self.assertEqual(rows[-1]['stop_reason'], end['reason'])

    def test_footprint_threshold_still_requests_engine_stop(self):
        marker, end, _, _ = self.run_case([sample(0), sample(1, footprint=100+1024**3+1)])
        self.assertTrue(json.loads(marker)['stop'])
        self.assertTrue(end['engine_stop_requested'])
        self.assertIn('footprint grew', end['reason'])

    def test_sustained_cpu_threshold_still_requests_engine_stop(self):
        marker, end, _, _ = self.run_case([sample(0),sample(10,cpu=30),sample(30,cpu=90)])
        self.assertTrue(json.loads(marker)['stop'])
        self.assertTrue(end['engine_stop_requested'])
        self.assertIn('CPU exceeded', end['reason'])

    def test_duration_bound_still_requests_engine_stop(self):
        marker, end, _, _ = self.run_case([sample(0),sample(1)], seconds=1, clock=[0,2])
        self.assertTrue(json.loads(marker)['stop'])
        self.assertTrue(end['engine_stop_requested'])
        self.assertEqual(end['reason'], 'Bounded QA watcher duration elapsed')

if __name__ == '__main__':
    unittest.main()
