# Preserved surface normals

`preserved_normals_c380.glb` is the exact historical c380 candidate used by
`tools/art/build_penguin_rear_surface_v3.py` to restore unchanged body, feet and
flipper normals and tangents after the tail join is exported. Its SHA-256 is
`c380a0f91dd2149936f9dd6bb5de9a8fb4e2a6631090a8e27e731d47a1a01dc5`.

The original lived inside an ignored local QA directory. This byte-identical
copy makes the build input available in a clean checkout. `provenance.json`
records the old location. Existing dated verification receipts retain their
historical paths and builder hashes; they have not been regenerated.

The c380 candidate was rejected visually. Only its unchanged-region data is
used by the builder. Keeping this input does not approve or ship that candidate.
