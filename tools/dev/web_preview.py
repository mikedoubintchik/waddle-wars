#!/usr/bin/env python3
"""Silent localhost Web preview with serialized, cached, last-good rebuilds.

No browser control, deployment, production preset changes, or save writes.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import threading
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WATCH_DIRS = ('scripts', 'scenes', 'assets', 'data', 'web')
WATCH_FILES = ('project.godot', 'export_presets.cfg',
               'tools/dev/runtime_bridge.js', 'tools/dev/navigation_bridge.gd',
               'tools/release/web_import_profile.py', 'tools/release/web_pack_memory.py',
               'data/web/ui_import_profile.json')
GODOT = '/Applications/Godot.app/Contents/MacOS/Godot'
_profile_spec = importlib.util.spec_from_file_location('web_import_profile', ROOT/'tools/release/web_import_profile.py')
import_profile = importlib.util.module_from_spec(_profile_spec)
_profile_spec.loader.exec_module(import_profile)
_memory_spec = importlib.util.spec_from_file_location('web_pack_memory', ROOT/'tools/release/web_pack_memory.py')
pack_memory = importlib.util.module_from_spec(_memory_spec)
_memory_spec.loader.exec_module(pack_memory)


def atomic_json(path: Path, value):
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n')
    os.replace(temp, path)


def inventory(root: Path):
    """mtime/size change detection avoids repeatedly reading multi-GB assets."""
    entries = []
    for name in WATCH_DIRS:
        for folder, dirs, files in os.walk(root / name):
            dirs[:] = sorted(d for d in dirs if d not in ('.godot', '__pycache__', '.git'))
            for name in sorted(files):
                if name == '.DS_Store' or name.endswith(('.tmp', '.swp', '~')):
                    continue
                p = Path(folder) / name
                try:
                    st = p.stat()
                    entries.append((str(p.relative_to(root)), st.st_size, st.st_mtime_ns))
                except FileNotFoundError:
                    pass  # Next scan observes a file being atomically replaced.
    for name in WATCH_FILES:
        p = root / name
        if p.exists():
            st = p.stat(); entries.append((name, st.st_size, st.st_mtime_ns))
            if name in ('tools/release/web_import_profile.py', 'tools/release/web_pack_memory.py', 'data/web/ui_import_profile.json'):
                entries.append((name, import_profile.sha(p)))
    return hashlib.sha256(json.dumps(entries, separators=(',', ':')).encode()).hexdigest()


class Debounce:
    def __init__(self, delay=1.5):
        self.delay = delay; self.signature = None; self.changed = 0; self.attempted = None

    def observe(self, signature, now):
        if signature != self.signature:
            self.signature = signature; self.changed = now
        return signature != self.attempted and now - self.changed >= self.delay

    def start(self):
        self.attempted = self.signature
        return self.signature


def inject_runtime(html, bridge):
    needle = 'const engine = new Engine(GODOT_CONFIG);'
    if html.count(needle) != 1:
        raise RuntimeError('Godot shell changed; expected one engine constructor')
    return html.replace(needle, needle + '\n' + bridge, 1)


def publish(stage: Path, builds: Path, current_file: Path, build, expected, observed):
    if observed != expected:
        shutil.rmtree(stage)
        return False
    # Every resource URL stays within an immutable complete build directory.
    os.replace(stage, builds / build['id'])
    atomic_json(current_file, build)
    return True


class Preview:
    def __init__(self, root, work, godot, seed_cache=None):
        self.root = root; self.work = work; self.godot = godot; self.seed_cache = seed_cache
        self.project = work / 'project'; self.builds = work / 'builds'
        self.project.mkdir(parents=True, exist_ok=True); self.builds.mkdir(exist_ok=True)
        (work / '.gdignore').touch()
        self.current_file = work / 'current.json'
        self.current = json.loads(self.current_file.read_text()) if self.current_file.exists() else None
        self.status = {'current': self.current, 'building': False, 'error': None}
        self.stop = threading.Event()

    def set_status(self, **kw):
        self.status = {**self.status, **kw}
        atomic_json(self.work / 'status.json', self.status)

    def sync(self):
        cache = self.project / '.godot'
        if not cache.exists() and self.seed_cache and self.seed_cache.exists():
            if os.uname().sysname == 'Darwin':
                subprocess.run(['cp', '-cR', str(self.seed_cache), str(cache)], check=True)
            else:
                shutil.copytree(self.seed_cache, cache)
        for name in WATCH_DIRS:
            destination = self.project / name
            destination.mkdir(exist_ok=True)
            subprocess.run(['rsync', '-a', '--delete', str(self.root / name) + '/',
                            str(destination) + '/'], check=True, stdout=subprocess.DEVNULL)
        project = (self.root / 'project.godot').read_text()
        # Dedicated, stable save namespace for continuous local testing.
        project = re.sub(r'^config/(?:use_custom_user_dir|custom_user_dir_name)=.*\n', '', project, flags=re.M)
        project = project.replace('[application]\n', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="waddle-wars-web-dev"\n', 1)
        project = project.replace('[display]', 'WaddleDev="*res://_dev_local/navigation_bridge.gd"\n\n[display]', 1)
        (self.project / 'project.godot').write_text(project)
        shutil.copy2(self.root / 'export_presets.cfg', self.project / 'export_presets.cfg')
        local = self.project / '_dev_local'; local.mkdir(exist_ok=True)
        shutil.copy2(HERE / 'navigation_bridge.gd', local / 'navigation_bridge.gd')
        self.import_receipt = import_profile.apply_to_project(
            self.project, self.project/'data/web/ui_import_profile.json', self.root)

    def build(self, signature):
        build_id = str(time.time_ns())
        stage = self.builds / ('.staging-' + build_id)
        stage.mkdir()
        log = self.work / ('build-' + build_id + '.log')
        started = time.time()
        self.set_status(building=True, error=None, log=str(log), requested_fingerprint=signature)
        try:
            self.sync()
            with log.open('w') as output:
                for args in (['--import'], ['--export-release', 'Web', str(stage / 'index.html')]):
                    command = [self.godot, '--headless', '--audio-driver', 'Dummy', '--path', str(self.project), *args]
                    output.write(' '.join(command) + '\n'); output.flush()
                    subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=300)
            logged = log.read_text()
            if 'SCRIPT ERROR:' in logged or re.search(r'^ERROR:', logged, re.M):
                raise RuntimeError('Godot reported an error; see ' + log.name)
            for name in ('index.html', 'index.pck', 'index.wasm', 'index.js'):
                if not (stage / name).is_file() or (stage / name).stat().st_size == 0:
                    raise RuntimeError('Incomplete export: ' + name)
            pack_profile = import_profile.verify_pack(stage/'index.pck', self.project/'data/web/ui_import_profile.json')
            memory_receipt = pack_memory.apply(stage/'index.js')
            html = (stage / 'index.html').read_text()
            html = inject_runtime(html, (HERE / 'runtime_bridge.js').read_text())
            (stage / 'index.html').write_text(html)
            for pattern in ('share.png', 'manifest.webmanifest', 'icon-*.png', 'favicon-*',
                            'favicon.ico', 'apple-touch-icon.png', 'loader-*-v3.webp'):
                for p in (self.project / 'web').glob(pattern):
                    shutil.copy2(p, stage / p.name)
            build = {'id': build_id, 'source_fingerprint': signature, 'seconds': round(time.time() - started, 2),
                     'published_at': time.time(), 'audio': 'Dummy (dev only)', 'save_identity': 'waddle-wars-web-dev',
                     'pack_bytes': (stage / 'index.pck').stat().st_size, 'log': str(log),
                     'web_import_profile': pack_profile, 'web_pack_memory': memory_receipt}
            atomic_json(stage / 'dev-build.json', build)
            if publish(stage, self.builds, self.current_file, build, signature, inventory(self.root)):
                self.current = build
                self.set_status(current=build, building=False, error=None)
                print('Published ' + json.dumps(build), flush=True)
            else:
                self.set_status(building=False, error=None, note='Source changed during build; stale result discarded')
        except Exception as error:
            self.set_status(building=False, error=f'{type(error).__name__}: {error}', log=str(log))
            print('Build failed; current game retained: ' + str(error), flush=True)
            shutil.rmtree(stage, ignore_errors=True)

    def watch(self):
        gate = Debounce()
        # Reuse an existing current build only when inputs are exactly unchanged.
        if self.current:
            gate.attempted = self.current['source_fingerprint']
        while not self.stop.is_set():
            # Serve the last complete build while a coordinated multi-file
            # correction is staged. Removing this local marker resumes watch.
            if (self.work / 'hold-builds').exists():
                if not self.status.get('held', False):
                    self.set_status(held=True)
                self.stop.wait(0.5)
                continue
            if self.status.get('held', False):
                self.set_status(held=False)
            signature = inventory(self.root)
            if gate.observe(signature, time.monotonic()):
                self.build(gate.start())
            self.stop.wait(0.5)


def server(preview, port):
    class Handler(SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(preview.work), **kwargs)

        def translate_path(self, path):
            route = urlsplit(path).path
            shell_files = {'/': 'index.html', '/shell.mjs': 'shell.mjs', '/web_lifecycle.mjs': 'web_lifecycle.mjs'}
            if route in shell_files:
                return str(HERE / shell_files[route])
            # Do not expose copied source project or arbitrary build-work files.
            if route == '/status.json' or route.startswith('/builds/'):
                resolved = Path(super().translate_path(path)).resolve()
                allowed = resolved == preview.work / 'status.json' or resolved.is_relative_to(preview.builds)
                if allowed:
                    return str(resolved)
            return str(preview.work / '__not_found__')

        def list_directory(self, path):
            self.send_error(403); return None

        def end_headers(self):
            self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
            self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
            self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
            self.send_header('Cache-Control', 'no-store')
            super().end_headers()

        def log_message(self, fmt, *args):
            if args and str(args[1]) not in ('200', '304'):
                super().log_message(fmt, *args)

    preview.set_status()
    httpd = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    atomic_json(preview.work / 'server.json', {'url': f'http://127.0.0.1:{port}/', 'pid': os.getpid(),
                'work': str(preview.work), 'logs': str(preview.work / 'build-*.log')})
    print(f'Preview: http://127.0.0.1:{port}/ (silent, local only)', flush=True)
    thread = threading.Thread(target=preview.watch, daemon=True); thread.start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        preview.stop.set(); httpd.server_close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=54620)
    parser.add_argument('--work', type=Path, default=ROOT / 'build/dev-web')
    parser.add_argument('--godot', default=GODOT)
    parser.add_argument('--seed-cache', type=Path, default=ROOT / '.godot')
    args = parser.parse_args()
    server(Preview(ROOT, args.work.resolve(), args.godot, args.seed_cache), args.port)
