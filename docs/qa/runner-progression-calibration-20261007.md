# Waddle Run progression calibration — 7 October 2026

## Intended journey

A new player gets attainable early milestones and four increasingly demanding tiers. Completing the **current 32-trophy runner collection requires at least 10 hours of moving gameplay**, plus the skill and collection goals. This is a calibrated design, not a measured claim that a person will finish in exactly ten hours. Players who keep ending runs early will need to improve; this is not a promise of completion through idle time.

Subway Surfers supplies the structure: [SYBO documents three missions per set and a reward for clearing the set](https://sybo.helpshift.com/hc/en/5-subway-surfers/faq/143-missions/), and [four achievement tiers, Bronze through Diamond, with increasing difficulty and reward](https://sybo.helpshift.com/hc/en/5-subway-surfers/faq/144-achievements/). Waddle keeps its own fish/star economy and clean-run score multiplier. The sources do not publish completion-hour targets or spawn rates; none are attributed to SYBO here.

## Current trophy collection

| Family | Bronze | Silver | Gold | Diamond | Feed |
|---|---:|---:|---:|---:|---|
| Trailblazer | 1,000 m | 25,000 m | 150,000 m | 500,000 m | Actual distance advanced during live runner steps |
| Fish Finder | 100 | 1,500 | 10,000 | 35,000 | Actual fish pickup events; excludes wallet grants and mission rewards |
| Goal Getter | 3 | 25 | 75 | 150 | Newly completed missions, persisted with their rewards |
| Ice Veteran | 10 min | 1 hour | 4 hours | **10 hours** | Moving, alive gameplay only |
| Long Haul | 750 m | 2,000 m | 4,000 m | 7,000 m | Best single run |
| Untouchable | 400 m | 1,000 m | 2,000 m | 3,500 m | Best stretch without taking an unshielded hit |
| Close Shave | 3 | 30 | 150 | 600 | Actual close hazard dodges; ordinary passes/collisions excluded by player authority |
| Power Player | 3 | 30 | 150 | 600 | Actual power-up pickup events |

Tier XP: 50 / 100 / 175 / 300. Every ID awards once. Achievements page shows live numeric progress and the real tier reward. Its collection ring counts only the 32 current runner trophies.

The 14 existing IDs retain their original names, meanings and 150 XP reward. Earned legacy trophies remain in a separate section; inactive race goals do not gate the runner collection. Existing known runner best-distance and completed-mission totals qualify for the appropriate new tiers. Historic play time, total distance, pickups and clean streaks were not recorded reliably, so none are invented. Legacy wallet-based Fish Tycoon stays earned, but its wallet total is not reused as genuine runner pickups.

## Mission corrections

- All goals count actions **after assignment**. A fresh mid-run distance/clean goal no longer inherits the previous set's distance; death reconciliation no longer retroactively fills a fish goal with earlier pickups.
- Unfinished “in one run” goals reset on retry. Cumulative goals retain progress. Completed rows do not replay rewards.
- A hit resets unfinished clean-streak goals immediately in the saved in-memory board, so opening Missions reads the reset value.
- A multiplier mission credits only the metres after its threshold is crossed, rather than the entire crossing frame.
- A completion saves its row state, completed-mission count, trophy XP, star, and fish together. Before this fix, the counter increment happened after the set's disk write.
- Leaving a living run checkpoints current mission progress and active metrics. It does not bank an unfinished run's score or pickup wallet.
- Existing saved targets and progress remain intact. Updated target rungs apply when the next set is drawn.

### New mission target rungs

| Goal | Four target rungs |
|---|---|
| Distance, one run | 500 / 900 / 1,400 / 2,200 m |
| Distance, cumulative | 1,200 / 3,000 / 6,000 / 10,000 m |
| Clean stretch, one run | 250 / 500 / 900 / 1,400 m |
| Metres at multiplier | 150 at x2 / 250 at x2 / 400 at x3 / 650 at x4 |
| Fish, cumulative | 40 / 100 / 220 / 400 |
| Fish, one run | 15 / 30 / 55 / 90 |
| Jumps, cumulative / one run | 12 / 30 / 60 / 100; 4 / 7 / 10 / 14 |
| Slides, cumulative / one run | 10 / 25 / 50 / 80; 3 / 5 / 8 / 10 |
| Lane changes, cumulative / one run | 25 / 60 / 120 / 220; 10 / 18 / 28 / 40 |
| Close dodges, cumulative / one run | 3 / 8 / 15 / 25; 1 / 2 / 2 / 3 |
| Power-ups, cumulative / one run | 3 / 8 / 18 / 30; 1 / 2 / 3 / 4 |
| Named power-up | 1 / 2 / 4 / 6 |
| Ramps, cumulative / one run | 3 / 8 / 18 / 30; 1 / 2 / 3 / 4 |

Four cleared sets advance the base rung; the last goal is one rung higher until the maximum. Three completed goals grant one star, 120 XP, and fish starting at 25, increasing by 5 per star to a 120 cap. The stricter new close-dodge detector justified lower near-miss targets. The rate study exposed unrealistic ramp/action requirements for moderate-length runs; those were reduced.

## Actual game rates and bounded model

Source speed: 15 m/s + 0.065 m/s each second, capped at 27 m/s after about 184.6 seconds. Hit slowdown is separate. Score is 1 point/metre before the clean multiplier, +25 per fish; multiplier rises every 260 clean metres to x6. Double Points doubles applicable scoring. Score is deliberately not used to infer time, since skill and power-ups change it substantially.

The headless pacing fixture builds the real course colliders/pickups for seeds 419, 1701 and 90210, preserving normal spacing, rejection and biome logic. It samples 60-, 150- and 300-second runs, integrating `RunnerConfig.speed_at` at 60 Hz. These are unpenalized distances; they do not include menu time or hit slowdown.

| Run duration | Metres/run | Fish opportunities/km | Crates/km | Actual ramps/km | Distance over 10 active hours |
|---|---:|---:|---:|---:|---:|
| 60 sec | 1,017 | 344.8 | 2.95 | 4.59 | 610 km |
| 150 sec | 2,981 | 327.1 | 3.35 | 3.58 | 716 km |
| 300 sec | 6,992 | 313.4 | 3.15 | 2.76 | 839 km |

The mission model runs the real `RunnerMissions` implementation for 36,000 active seconds under explicitly synthetic assumptions: fish capture 12% / 24% / 40%, crate/ramp capture 40%, one jump per 9 sec, slide per 12 sec, lane change per 3 sec and close dodge per 45 sec after the introductory distance. The shorter two scenarios take one hit per run; the longest takes none. Model speed omits hit slowdown. This is an opportunity/goal pacing study, not a playable bot, statistical population study or measured human completion test.

| Assumed run duration | First set cleared | Missions after 1 hour | Missions after 10 hours |
|---|---:|---:|---:|
| 60 sec | 144 sec | 11 | 11 |
| 150 sec | 74 sec | 30 | 137 |
| 300 sec | 49 sec | 34 | 146 |

The fixed 60-second scenario stalls on a per-run power-up goal: improved collection or survival is required. Practiced scenarios approach the 150-mission Diamond around ten hours, while the time capstone enforces a hard ten-hour minimum for everyone. The best-run and clean-streak Diamonds require skill beyond a fixed novice or moderate scenario. A human longitudinal test remains necessary to validate enjoyment, variance and an eventual completion-time distribution.

## Active-time authority and persistence

The game starts an activity step only while running, alive, presentation-ready and unpaused. A positive actual distance advance is required. Countdown, menu, pause, death animation and Results contribute zero. A single stalled/background frame contributes at most 0.25 seconds. This intentionally undercounts long stalls rather than granting hidden wall-clock time. No input-spam counter can unlock the time capstone.

A pending step is consumed once, including synchronous fatal collisions; its stats are included in the final save. Threshold evaluation runs twice per active second, with immediate checks for pickup/mission events and death/exit. No course RNG changes. Normal disk autosave is every three seconds; missions refresh their in-memory snapshot every 30 metres, and completed missions, run end, live-run exit and application close use existing durable-save paths. New optional stat keys use SaveManager's existing default merge and cloud progress preservation; no destructive save-version rewrite.

## Evidence and limits

Receipt: `qa_shots/tests/waddle-progression-646cuor3/RECEIPT.md`.

Final focused checks: **510/510 passed**, all five stderr logs empty. Includes every mission feed, real player slide/jump/lane action wiring, active clock exclusions, fatal-frame/retry/exit behavior, saved progress/reward-once, migration, UI metric binding, and atomic earned-fish bundle validation. Pacing run completed without engine errors; raw output in `pacing.json`.

No live account operations, deployment, native window launch, or ten-hour human playtest. Updated achievement layout has headless state/binding checks; no new pixel-fidelity claim is made here. The first rate-study attempt omitted the track's history initializer and emitted bounds errors; that attempt is rejected and preserved separately. The accepted run initializes the production track history before generating chunks.
