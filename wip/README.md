# Held-back work

`round3-heldback.patch` is the full 2026-08-06 round-3 agent output, taken
before the sim-regressing parts were dropped. It applies on top of commit
`038a3c4` (not on current main).

Landed from it already (see commit `0026ca2`): AI difficulty + projected
finish times, race-flow HUD/pause work, menu touch scaling, Settings
redesign, Ninja Consulting credit, water shader.

Still held back, each because it regressed the sim suite and needs its own
verified pass:

- **Ultra-physics contact pass** (`racer.gd`, `trail_effect.gd`) — wall
  glancing, mass-weighted racer bumps, moving-platform carry, apex-hang
  jump arc. Broke the tutorial hop lesson (racers grind along the low
  hurdle bars instead of hopping; hint-based jumps stop firing once
  progress passes the hint offset) and caused iceberg AI DNFs.
- **Compound hazard motion** (`hazard_platform.gd`, iceberg platform
  configs) — lurch/yaw/heave/telegraph. Iceberg sims TIMEOUT: AI cannot
  cross the lurching slabs.
- **Dressing grounding** (`course_base.gd` ray-seating + per-course use) —
  not individually validated once the other reverts landed.
- **Chrome shader warm-up** (`shader_warmup.gd`, `race.gd` wiring,
  `game_config.is_web_chrome()`) — unvalidated in a race.

Rework guidance: land each independently with its own sim battery
(`tests/race_sim.tscn` at all three difficulties on all three courses plus
`tests/tutorial_sim.tscn` x3), not as a batch.
