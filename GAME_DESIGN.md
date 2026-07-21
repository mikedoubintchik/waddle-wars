# Waddle Wars — Game Design

## Design pillars

1. **Waddle precisely** — steering, hopping, and route choice are the skill core.
2. **Slide for speed** — momentum management (slide downhill/ice, waddle powder/uphill) is the mastery layer.
3. **Use the environment** — shortcuts, hazards, boost pads, water routes reward course knowledge.
4. **Outsmart seven chaotic rivals** — personality-driven AI, comedic interference, no cruelty.

Tone: playful, energetic, family-friendly, physical comedy. A race lasts ~1.5–3 minutes.

## Core loop

Race → collect fish + place well → earn fish/XP → unlock cosmetics + achievements → race faster, riskier, prettier.

## Mechanics

- **Auto-run** with full lateral steering (reduced control airborne).
- **Hop**: coyote time (0.14s), jump buffering (0.16s), squash & stretch, landing puffs.
- **Belly slide**: hold-to-slide (or toggle); momentum-based; accelerates downhill (slope-projected gravity), keeps speed on ice (per-surface `slide_keep`), bleeds in deep snow/uphill (auto-stand when stalled climbing); fits under low bars (collision crouch); drift via reduced steering grip.
- **Surfaces**: packed snow (baseline), deep snow (slow, grippy), smooth ice (fast, slippery), rough ice (mid), water (swim), boost (fast emissive lanes).
- **Swim**: buoyancy spring to surface, dive (slide), dolphin burst (jump), auto-entry on water contact, ramp exits.
- **Flipper shove**: 1.6s cooldown, short range, stumble not stun, 2.2s victim immunity prevents chain-stunning.
- **Recovery**: kill-plane / stuck detection → respawn at last checkpoint with speed penalty + 2s invulnerability. Checkpoints are progress-based so no route can miss one.

## Power-ups (one held at a time, HUD slot)

Snowball (forgiving homing lob), Ice Shield (blocks one hit, visible bubble),
Fish Frenzy (speed burst + FOV kick), Fish Magnet (attracts fish 6s),
Blizzard Burst (slippery low-visibility cloud dropped behind).
Distribution is position-weighted (trailing racers get stronger offense) but bounded — no obvious rubber-band cheating, no teleports.

## Courses

Three hand-curated point-to-point courses (Glacier Gauntlet, Aurora Ascent, Iceberg Bay), each with: countdown start, progress checkpoints, one risky branch shortcut, escalating hazards, signature finale, spectators, and themed environment/lighting. Hazards always telegraph (warnings, fixed lanes, phase cycles) and never chain-hit (per-racer cooldowns).

## Modes

Quick Race, Grand Prix (3 races, 10/8/6/5/4/3/2/1 points, cup ceremony, records),
Endless Expedition (seeded segment assembly, storm-front elimination, score chase),
Time Trial (no items, local ghost), Waddle School (interactive tutorial).

## AI

Seven named personalities (Gus/Pippa/Scooter/Marina/Bruno/Ziggy/Nova) with distinct colors, cosmetics, and parameter sets (aggression, shortcut preference, item focus, caution, risk, consistency, skill). Difficulty (Chill/Competitive/Emperor) scales reaction delay, steering precision, mistake frequency, speed, item aggression, shortcut usage. Bounded rubberband (±14% speed max) keeps races close; stuck detection + checkpoint recovery guarantees every AI finishes.

## Progression

Fish currency (in-race pickups + placement rewards) buys 16 cosmetics across 5 categories (4 penguin bodies, hats, neckwear, eyewear, trails). XP levels (400 XP/level, achievements grant 150). 14 achievements. All local, no monetization.

## Accessibility

Camera shake full/reduced/off, high-contrast pickups, reduced flashing, colorblind-safe UI cues, HUD/UI scale, hold-or-toggle slide, remappable inputs, pause-on-focus-loss, visual cues for audio events.

## Art & audio direction

Stylized low-poly 3D: rounded procedural penguins with expressive squash-and-stretch animation; saturated-but-controlled Antarctic palettes (bright glacier day, twilight aurora, sunset bay); soft snow lighting with filmic tonemap and gentle fog. Audio is fully synthesized: playful pentatonic music loops (bells, plucks, bass, light percussion) and cartoon-friendly SFX.
