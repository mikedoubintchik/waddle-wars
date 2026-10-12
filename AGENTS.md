# Incremental visual QA

For work that can change visible game pages, use **one snapshot at the start of the user turn**, before editing runtime files. Accumulate all work/checks for that request. **Capture frames only once all work is complete at the end of the entire turn**, never after each internal sub-iteration or partial fix.

1. Run `tools/qa/gallery_iteration.py start` with the latest accepted gallery as the base. It hashes runtime files, including untracked files; Git HEAD is not the baseline in this dirty workspace.
2. Finish all edits and local checks, freeze sources, then run final `plan`. Intermediate `plan` calls are metadata-only and do not authorize captures. Use its desktop/mobile capture matrix. Unknown runtime dependencies require a conservative full-catalogue refresh; do not silently exclude them.
3. Capture the requested views through the coordinated silent Chrome workflow. Run `review`, inspect originals against references, then record explicit acceptance. Failed or missing views remain pending.
4. Run `build` and `delivery-delta`. Keep the full left page list, dated older evidence, and the This turn view. Publish only changed files after verification; update any current pointer last.

Exact commands, source scope, acceptance rules and tests: [incremental gallery guide](tools/qa/gallery_iteration.md).
Do not regenerate unchanged screenshots or references merely to obtain a new iteration number. Coordinate browser/export ownership; these tools never start an engine or browser.
