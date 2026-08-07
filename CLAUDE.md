# Waddle Wars Operating Contract

## Source of truth

GAME_SPEC.md is the authoritative product specification.

BUILD_STATUS.md records implementation status, test evidence, blockers, and the next highest-priority work. It must reflect reality rather than optimistic claims.

QA_FINDINGS.md contains independently verified defects from a supervisor QA session. Treat OPEN items there as high-priority work: fix them and mark them FIXED with evidence, or rebut them with evidence. Check it every work cycle.

The project is not complete merely because it launches. Completion requires the functionality, content, quality, testing, visual review, documentation, and platform-readiness requirements in GAME_SPEC.md.

## Primary objective

Build the strongest complete version of Waddle Wars possible.

Continue improving the game even after a first playable or apparently complete build exists. Use the time available for implementation, testing, visual review, debugging, optimization, game-feel improvements, accessibility, content polish, and documentation.

## Autonomous behavior

Do not wait for routine approval.

Do not ask questions whose answers can be reasonably inferred from GAME_SPEC.md, the repository, Godot conventions, test results, or the existing implementation.

Make conservative, production-oriented decisions when requirements are ambiguous.

When one task is blocked, record the blocker and immediately continue with the highest-value unblocked task.

Never stop merely because:
- A prototype works.
- The main loop works once.
- Files for a feature exist.
- A checklist was filled in.
- A test was written but not run.
- A visual feature was implemented but not inspected.
- An individual subsystem is complete.

Do not weaken requirements to make the completion checklist easier to satisfy.

## Continuous execution loop

During every work cycle:

1. Read GAME_SPEC.md and BUILD_STATUS.md.
2. Inspect the repository and recent test evidence.
3. Select the highest-impact unmet, defective, or under-polished requirement.
4. Implement it as a complete vertical slice.
5. Run focused tests.
6. Run the broader regression suite when the change could affect other systems.
7. Run Godot headlessly to detect parser, import, resource, and scene errors.
8. Launch the game when practical and inspect the affected gameplay or interface.
9. Capture and inspect screenshots for visual work when tools permit.
10. Fix defects rather than merely documenting them.
11. Update BUILD_STATUS.md and TESTING.md with exact evidence.
12. Create a checkpoint commit after a stable body of work.
13. Continue with the next highest-impact task.

## Quality rules

Preserve a working playable build throughout development.

Do not leave required functionality as TODOs, stubs, empty handlers, fake menus, placeholder screens, or documentation-only claims.

Do not mark a requirement complete without verifiable evidence.

Test player-facing paths from the title screen through gameplay, results, rewards, saving, and return to the menu.

Prioritize movement quality, camera behavior, race readability, AI reliability, course completion, responsive UI, audio feedback, visual consistency, save integrity, and mobile compatibility.

Prefer a smaller feature that is complete and polished over a larger feature that is unstable.

Do not repeatedly rewrite stable systems without evidence that the rewrite is necessary.

## Parallel work

Use subagents or dynamic workflows for independent workstreams when doing so will produce more verified work.

Suitable independent workstreams include:
- Gameplay and racer mechanics.
- Course and hazard development.
- AI behavior and recovery.
- UI, settings, accessibility, and touch controls.
- Procedural visual assets and shaders.
- Audio generation and integration.
- Automated testing and QA.
- Performance and mobile-readiness review.

Avoid simultaneous edits to the same files. Use isolated worktrees or clearly separated file ownership for parallel implementation.

Every subagent result must be reviewed, integrated, and tested by the primary agent.
