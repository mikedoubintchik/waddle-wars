# Audited Web UI imports

`data/web/ui_import_profile.json` records the Web-only compression policy for
480 complete wardrobe illustrations and 119 menu WebPs. Original image bytes,
dimensions, alpha, existing mipmap policy, asset paths and runtime caches stay
unchanged. Primary checkout import sidecars are not rewritten.

The former lossless Godot import re-encoded already-compressed source WebPs.
Those 599 imported textures occupied 359.04 MB of the deployed 451.37 MB pack.
The admitted imports occupy 115.76 MB. A full pack is estimated at 208.10 MB;
the actual complete export must pass the **220,000,000-byte** ceiling. The
smaller texture-only verification pack is not a complete-game size result.

## Admission

- 595 textures use quality 0.95; four portrait plates use 0.98.
- Every admitted decoded base image must have exact alpha, unchanged dimensions,
  unchanged mipmap presence, luminance SSIM at least 0.995 on both black and white
  composites, and visible RGB PSNR at least 35 dB.
- SSIM uses an 11×11 uniform window with reflected borders. Visible RGB metrics
  include pixels whose original alpha exceeds 0.05. Pixel-perfect RGB is not
  claimed: the measured maximum single-channel RGB error is also recorded.
- Mipmap presence/policy is preserved; per-mip RGB identity is not claimed.
- Any failed image is raised in quality and decoded again. Never lower the gate
  or remove an equipment option to fit the package budget.

The profile pins each source, sampler configuration and admitted CTEX hash,
plus both import and JavaScript-memory helper hashes. A changed source, new
WebP in either audited directory, sampler change or helper change invalidates
the profile. Re-audit and regenerate it explicitly.

## Build integration

Before Godot imports an isolated export project:

```python
receipt = web_import_profile.apply_to_project(project, profile_path)
```

After export, before recording published artifact hashes:

```python
pack_receipt = web_import_profile.verify_pack(web / "index.pck", profile_path)
memory_receipt = web_pack_memory.apply(web / "index.js")
```

Production, Chrome QA and local dev builds use the same profile and memory
helper. The pack check verifies every admitted texture's actual payload hash
and the complete pack size. A failure must leave the prior build unpublished.

## Re-audit

`tools/art/ui_texture_imports.py prepare` takes an immutable deployed PCK and
creates a new isolated image-only project. It extracts exact baseline CTEXs;
it does not infer baseline pixels from the source format. Import that project
with headless Godot and the Dummy audio driver, then run its `decode.gd` to
produce paired decoded PNG evidence outside the project. Run `analyze` with
the bundled NumPy/Pillow Python environment. Once every row passes, `profile`
writes the checked-in policy. The decoded evidence and metric receipt remain
local QA artifacts, not runtime assets.

Compression reduces download and MEMFS pack storage, not decoded texture VRAM.
The separate pinned JavaScript helper removes the redundant startup pack copy.
Neither change alone proves that every reported browser crash is resolved;
the exact final production wrapper still requires bounded browser verification.
