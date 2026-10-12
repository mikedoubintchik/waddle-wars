#!/usr/bin/env python3
"""Bounded OS-only guard for a coordinator-confirmed local Chrome QA renderer.

Arm after game boot, with its observed renderer PID. Reads process counters;
requests only this QA engine stop through a local marker. Does not kill Chrome,
close tabs, or interact with a browser. If the JS main thread cannot poll the
marker, coordinator must close its QA tab through CUA.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import time

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('counters',ROOT/'tools/qa/chrome_process_sampler.py')
counters=importlib.util.module_from_spec(spec);spec.loader.exec_module(counters)

def run(out, renderer_pid, seconds, interval):
    if not (out/'server.json').exists(): raise SystemExit('Requires served isolated QA export')
    if (out/'qa-stop.json').exists() and json.loads((out/'qa-stop.json').read_text()).get('stop'):
        raise SystemExit('Prior stop marker preserved; choose fresh run')
    sample=counters.sample()
    rows={p['pid']:p for p in sample['processes'] if p['pid']==renderer_pid or p['role']=='browser'}
    if renderer_pid not in rows or rows[renderer_pid]['role']!='renderer':
        raise SystemExit('Observed renderer PID is not active Chrome renderer')
    baseline={pid:p['phys_footprint'] for pid,p in rows.items()}
    previous=sample; previous_rows=rows; high_since=None; deadline=time.monotonic()+seconds
    with (out/'guard-counters.jsonl').open('x') as log:
        while True:
            sample=counters.sample(); now=sample['monotonic_s']
            rows={p['pid']:p for p in sample['processes'] if p['pid'] in baseline}
            delta=now-previous['monotonic_s']; cpu=0.0; growth={}
            for pid,p in rows.items():
                if pid in previous_rows and delta>0:
                    p['interval_cpu_percent']=max(0.0,(p['cpu_seconds']-previous_rows[pid]['cpu_seconds'])/delta*100)
                    cpu+=p['interval_cpu_percent']
                growth[str(pid)]=p['phys_footprint']-baseline[pid]
            high_since=(high_since if high_since is not None else now) if cpu>220 else None
            reason=''
            if renderer_pid not in rows: reason='Observed QA renderer exited; stop watcher'
            elif any(n>1024**3 for n in growth.values()): reason='Tracked process footprint grew more than 1 GiB after arm'
            elif high_since is not None and now-high_since>=15: reason='Browser plus QA renderer CPU exceeded 220 percent for 15 seconds'
            elif time.monotonic()>=deadline: reason='Bounded QA watcher duration elapsed'
            row={'utc':sample['utc'],'monotonic_s':now,'tracked_renderer_pid':renderer_pid,
                 'processes':list(rows.values()),'baseline_footprints':baseline,
                 'growth_bytes':growth,'combined_interval_cpu_percent':cpu,'stop_reason':reason}
            log.write(json.dumps(row)+'\n');log.flush()
            if reason:
                # An exited renderer has no engine left to stop. Leaving a
                # stop marker here can kill the next page at the same URL.
                request_engine_stop = renderer_pid in rows
                terminal={'reason':reason,'utc':sample['utc'],'renderer_pid':renderer_pid,
                          'engine_stop_requested':request_engine_stop}
                if request_engine_stop:
                    marker={'stop':True,'reason':reason,'utc':sample['utc'],'renderer_pid':renderer_pid,
                            'scope':'Requests this QA engine quit; never terminates Chrome or other applications'}
                    (out/'qa-stop.json').write_text(json.dumps(marker,indent=2)+'\n')
                (out/'guard-end.json').write_text(json.dumps(terminal,indent=2)+'\n')
                print(json.dumps(terminal),flush=True);return
            previous=sample;previous_rows=rows;time.sleep(interval)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('out',type=Path);p.add_argument('--renderer-pid',type=int,required=True);p.add_argument('--seconds',type=int,default=1200);p.add_argument('--interval',type=float,default=5)
    a=p.parse_args()
    if not 1<=a.seconds<=1800 or not 1<=a.interval<=10:p.error('Bounds: seconds1–1800, interval1–10')
    run(a.out.resolve(),a.renderer_pid,a.seconds,a.interval)
