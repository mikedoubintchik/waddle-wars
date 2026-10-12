# Live local Web preview

Run from the repository:

```sh
python3 tools/dev/web_preview.py
```

Open **http://127.0.0.1:54620/** in one Chrome tab. Root coordinates browser use.
The development game is always silent (`--audio-driver Dummy`); production audio
settings and preset remain unchanged. The dedicated `waddle-wars-web-dev` save
identity persists between builds. Existing QA and production saves are not copied.

Changes to scripts, scenes, assets, data, Web boot assets, project configuration or
export presets trigger a debounced cached release export. This is automatic Web
rebuild/restart, not Godot in-place hot swapping: an active run returns to the last menu after a code change.
Menu page, Settings section and wardrobe category restore where supported.

Only complete successful builds publish. Compile failures leave the current game
running; the status strip points to logs. Changes during export discard stale output
and build again. One build process runs at a time. Old game receives `requestQuit`;
the wrapper waits for Godot `onExit` (after engine cleanup), removes its iframe, then
starts one new frame. A20-second teardown timeout blocks automatic replacement and
shows a Retry button, rather than starting overlapping engines. A stuck/crashed tab
may require closing it before reopening the URL. Cleanup does not force Chrome GC.

`build/dev-web/server.json` records PID/URL. `status.json`, `current.json` and
`build-*.log` record actual outcomes. Build directories are immutable and retained
for the local session; stop server before deleting `build/dev-web` to reclaim space.
Do not delete that directory while a preview is loading. Ctrl-C stops the server;
close preview tab to stop its game. For a coordinated multi-file edit, create `build/dev-web/hold-builds` to keep
serving the last working game without rebuilding partial edits. Remove that marker
to resume automatic rebuilds. Helper/server-code edits require restarting the
server. Override port/cache/workspace via `--help`.

Focused checks:

```sh
python3 -m unittest discover -s tools/dev -p 'test_*.py'
node --test tools/dev/test_web_lifecycle.mjs
```

Chrome acceptance: leave dev tab on wardrobe category, edit a source, observe
building→stopping→loading→ready and category restoration. `window.__wwDev.history`
must show exit/removal before the next frame creation; DOM has exactly one iframe.
Introduce and then repair a compile error: current game stays usable, repaired
build publishes. Observe browser/renderer memory across several rebuilds; unit
tests prove lifecycle ordering, not browser memory reclamation.

## Actual Chrome verification —2026-10-08

One comment-triggered refresh completed: quit14:20:15.546UTC →exit16.136 →frame removed16.383 →new frame16.956 →started20.785. One iframe observed. Renderer physical footprint was about953MiB before,1399MiB at8seconds,928MiB at16seconds, then about990MiB while menus were explored. This demonstrates teardown ordering and recovery during one refresh, not universal leak-free behavior. User navigation changed during the trial, so Hats-category persistence was not independently verified. Exact scalar receipt: `build/dev-web/checks/chrome-refresh-receipt.json`.
