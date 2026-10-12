# Hero penguin material audit — 2026-09-07

Read-only material/UV inspection; no runtime changes, renderer runs, or performance claims.

## Evidence and fidelity boundary

- Reference: `art_src/characters/hero_penguin_user_reference_2026-08-18.png`.
- Reviewed Compatibility captures: `qa_shots/hero/waddle_20260907_30/hero_penguin_run_front_landscape_30fps/frame_0000.png` and `qa_shots/hero/waddle_20260907_30/hero_penguin_run_side_landscape_30fps/frame_0000.png` (also side frame 0010).
- Capture timeline reports `gl_compatibility` and GLB SHA-256 `6f29c700e5755fa95c788351097aa5fd197cb53bd0cc4776f7353495e43df9e1`. Current `assets/art/characters/hero_penguin_v1.glb` is `cc1528969bb9603b437f6074ba8c8e806e74b2fe8f01b5289753c41c4678c915`. The separate export audit confirmed this difference is run animation only: mesh, morph, and skin bytes are unchanged. Captures remain geometry-equivalent for this material review, not proof of a newly sculpted model.
- Reference has integrated facial forms, directional feather highlights, and soft contact shading. Current captures show smooth, nearly featureless dark flanks and weak cream grain. Stronger material response cannot repair eye placement, bill shape, cheek volume, or silhouette; new geometry remains the first fidelity priority.

## Actual runtime material path

`scripts/characters/hero_penguin_rig.gd::_apply_materials` installs `assets/art/characters/hero_penguin_v1_material.tres` on the rendered path. That resource references `scripts/shaders/hero_penguin_v1.gdshader` and these existing maps:

- `assets/art/characters/textures/hero_penguin_v1_albedo.png`
- `assets/art/characters/textures/hero_penguin_v1_normal.png`
- `assets/art/characters/textures/hero_penguin_v1_orm.png`

This is not a missing-texture/placeholder path in ordinary rendered captures. Headless deliberately substitutes a neutral material, so headless visual output is not material evidence. The current GLB supplies normals, tangents, and UVs; tangent XYZ lengths are approximately one. All inspected UVs are within 0–1, and no all-feather triangle has degenerate UV area.

## Measurable detail suppression

1. **Normal detail is attenuated twice.** Shader first blends the sampled normal toward flat by 0.62 dark / 0.70 cream, then applies `NORMAL_MAP_DEPTH` 0.42 / 0.48. Small-angle effective strengths are approximately **0.26 / 0.34**. Existing 1024² maps imply median angular perturbations of only **0.185° dark / 0.385° cream**, with p95 **1.125° / 2.072°**, before mipmapping and filtering. These are CPU small-angle estimates, not measured rendered normals.
2. **Feather reflection is extremely weak and uniform.** Current shader uses feather `SPECULAR = 0.15`; effective roughness from the existing ORM averages **0.822 dark / 0.784 cream**, with standard deviations approximately **0.0046 / 0.0053**. Godot 4.7.1 Compatibility computes dielectric F0 as `0.16 * specular * specular`: 0.15 therefore gives **0.36%**, versus 4% at 0.5. This suppresses the directional glints that make fine feather normals readable. Source: [pinned GLES3 scene shader, F0 and normal mapping](https://raw.githubusercontent.com/godotengine/godot/4.7.1-stable/drivers/gles3/shaders/scene.glsl).
3. **The atlas is detail, not a character-specific bake.** ORM AO averages about **0.963** in both halves with very little variation. It cannot supply sculpt-specific eyelid, bill, flipper-root, or foot contact occlusion. Current additional vertex AO is broad procedural shading, not a replacement for those contact forms.

## UV seam defect

`tools/art/build_hero_penguin_v1.py` assigns cylindrical `u = (atan2(x, y) + pi) / tau` independently per corner, without unwrapping rear seam-crossing triangles. In the inspected current GLB, **362 of 13,234 all-feather triangles span more than 0.5 in U**. “All-feather” means all three vertex alphas meet the shader's feather threshold of 0.5.

These triangles interpolate across most of the atlas instead of across a narrow local seam, stretching detail and inflating texture derivatives. Moving the discontinuity to the rear does not fix interpolation. The shader's `clamp(UV, 0, 1)` cannot repair this. Its fixed half-texel inset also protects only the base atlas level, not every mip footprint at the two-half boundary.

## Smallest next corrections

- Keep the single material and current albedo/normal/ORM resources. Use **one tunable normal strength**, not two independent attenuations; evaluate grain on both dark and cream areas at chase and close-up scales.
- Preserve meaningful local UV continuity in the new geometry export. Split/unwrap seam corners correctly and validate triangle UV spans. If UVs cross 0–1 intentionally, update sampling coherently; do not clamp away the correction. Provide mip-safe atlas padding or equivalent island-safe sampling.
- After new geometry is in place, adjust feather specular and existing roughness-map contrast together, keeping separate eye/bill/foot response tags. Do not substitute a bright smooth rim for directional feather detail.
- Recheck actual Compatibility captures. None of these changes requires another material, extra draw calls, runtime fur, or a renderer switch. Their visual quality and GPU cost still require rendered validation; this audit does not claim either gate passes.
