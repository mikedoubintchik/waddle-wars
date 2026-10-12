#!/usr/bin/env python3
"""Read-only Chrome process counters; no page/profile contents retained."""
import argparse, ctypes, datetime, json, pathlib, subprocess, time
FIELDS = 'user_time system_time pkg_idle_wkups interrupt_wkups pageins wired_size resident_size phys_footprint proc_start_abstime proc_exit_abstime child_user_time child_system_time child_pkg_idle_wkups child_interrupt_wkups child_pageins child_elapsed_abstime diskio_bytesread diskio_byteswritten cpu_time_qos_default cpu_time_qos_maintenance cpu_time_qos_background cpu_time_qos_utility cpu_time_qos_legacy cpu_time_qos_user_initiated cpu_time_qos_user_interactive billed_system_time serviced_system_time logical_writes lifetime_max_phys_footprint instructions cycles billed_energy serviced_energy interval_max_phys_footprint runnable_time'.split()
class Usage(ctypes.Structure):
    _fields_ = [('uuid',ctypes.c_ubyte*16)] + [(key,ctypes.c_uint64) for key in FIELDS]
LIB = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
LIB.proc_pid_rusage.argtypes = [ctypes.c_int,ctypes.c_int,ctypes.c_void_p]
LIB.proc_pid_rusage.restype = ctypes.c_int

class Timebase(ctypes.Structure):
    _fields_ = [('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
TIMEBASE = Timebase()
ctypes.CDLL('/usr/lib/libSystem.B.dylib').mach_timebase_info(ctypes.byref(TIMEBASE))
CLOCK_SECONDS = TIMEBASE.numer / TIMEBASE.denom / 1e9

def sample():
    raw = subprocess.check_output(['ps','-axo','pid=,ppid=,rss=,%cpu=,command='],text=True)
    rows=[]
    for line in raw.splitlines():
        fields=line.strip().split(None,4)
        if len(fields)!=5: continue
        pid,ppid,rss,cpu,command=fields
        if not command.startswith('/Applications/Google Chrome.app/Contents/'): continue
        role=('browser' if command == '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' else 'other') if '--type=' not in command else next((s[7:] for s in command.split() if s.startswith('--type=')),'unknown')
        row={'pid':int(pid),'ppid':int(ppid),'role':role,'extension_renderer':'--extension-process' in command,'rss_ps_bytes':int(rss)*1024,'cpu_percent':float(cpu)}
        usage=Usage()
        if LIB.proc_pid_rusage(int(pid),4,ctypes.byref(usage))==0:
            row.update({k:getattr(usage,k) for k in ('resident_size','phys_footprint','lifetime_max_phys_footprint','pageins','user_time','system_time','runnable_time','proc_start_abstime')})
        else: row['rusage_error']=ctypes.get_errno()
        if 'user_time' in row:
            row['cpu_seconds']=(row['user_time']+row['system_time'])*CLOCK_SECONDS
            row['runnable_seconds']=row['runnable_time']*CLOCK_SECONDS
        rows.append(row)
    return {'phase': pathlib.Path(__file__).with_name('phase.txt').read_text().strip() if pathlib.Path(__file__).with_name('phase.txt').exists() else 'unspecified', 'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'monotonic_s':time.monotonic(),'processes':rows, 'clock_timebase':{'numer':TIMEBASE.numer,'denom':TIMEBASE.denom,'raw_time_scope':'Mach absolute ticks; converted CPU checked against ps in native v5'}}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path);p.add_argument('--seconds',type=float,default=0);p.add_argument('--interval',type=float,default=5);a=p.parse_args()
    if not a.output:
        print(json.dumps(sample(),indent=2));raise SystemExit
    end=time.monotonic()+a.seconds
    with a.output.open('x') as stream:
        while True:
            stream.write(json.dumps(sample())+'\n');stream.flush()
            if time.monotonic()>=end: break
            time.sleep(min(a.interval,max(0,end-time.monotonic())))
