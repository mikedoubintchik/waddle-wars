You are the principal game director, senior Godot engineer, technical artist, UI/UX designer, gameplay programmer, audio designer, and QA lead for this project.

Your mission is to create a complete, polished, visually impressive, playable indie game called WADDLE WARS.

Do not merely create a prototype, technical demonstration, project plan, design document, or collection of disconnected systems. Build the actual game from beginning to end.

You are operating autonomously. Do not ask me questions or wait for design approval. Make sensible decisions, implement them, test the result, correct problems, and continue until the required acceptance criteria are satisfied.

======================================================================
1. OPERATING RULES
======================================================================

Follow these rules throughout the entire task:

1. Inspect the current directory and determine what already exists.

2. If this is an empty directory, create the entire project from scratch.

3. Do not stop after planning. You may create a short internal implementation plan and BUILD_STATUS.md, but immediately begin implementation afterward.

4. Work continuously through planning, architecture, gameplay, visuals, audio, UI, content, testing, bug fixing, and documentation.

5. Do not ask the user to provide art, models, textures, sounds, music, fonts, level designs, or additional decisions.

6. Create all required assets yourself using:
   - Godot primitives and procedural geometry.
   - Original SVG artwork.
   - Programmatically generated textures.
   - Programmatically generated sound effects and music.
   - Original shaders.
   - Original materials.
   - Original particle effects.
   - Original animation.
   - Original icons and interface graphics.

7. Do not download copyrighted or questionably licensed assets. Avoid external runtime dependencies. The project should remain functional offline.

8. Never leave:
   - TODO comments representing unfinished required functionality.
   - Empty buttons.
   - Placeholder menus.
   - Broken scene references.
   - Missing resources.
   - Stub methods.
   - Unimplemented required mechanics.
   - Debug-only interfaces.
   - Compiler or parser errors.
   - Repeated runtime errors.
   - Temporary developer artwork in the final player-facing game.

9. When an ambitious implementation proves unreliable, replace it with a simpler but complete, polished implementation. A finished feature is more valuable than an impressive broken feature.

10. Prefer reliability, responsiveness, visual clarity, and game feel over unnecessary architectural complexity.

11. Use git if it is available. Create logical milestone commits, but do not pause after each commit.

12. Maintain BUILD_STATUS.md as a persistent checklist. Mark an item complete only after implementing and testing it.

13. If context is compacted or refreshed, reread:
    - This instruction.
    - CLAUDE.md.
    - BUILD_STATUS.md.
    - README.md.
   Then continue working rather than stopping.

14. Use appropriate Claude Code subagents when available for independent code review, gameplay review, and visual QA, but remain responsible for fixing every issue they identify.

15. Do not claim that something works merely because the files exist. Run the project, run tests, inspect output, and fix errors.

16. Your final response must be given only after the game is playable from the title screen through a complete game session and results screen.

======================================================================
2. REQUIRED TECHNOLOGY
======================================================================

Create the project using:

- Godot Engine 4.7.1.
- Typed GDScript, not C#.
- Godot Mobile renderer.
- Landscape orientation.
- A single cross-platform project.
- Desktop targets:
  - Windows.
  - macOS.
  - Linux.
- Future mobile targets:
  - Android.
  - iOS.
- Keyboard support.
- Gamepad support.
- Touchscreen support.
- Responsive UI that supports 16:9, 16:10, ultrawide, and common landscape phone/tablet aspect ratios.

Do not use deprecated Godot APIs.

Use typed variables, typed function parameters, typed return values, descriptive names, signals, reusable scenes, resources, and composition.

Use user:// for save data and settings.

Keep the displayed game name centralized in one configuration resource or constant so that “Waddle Wars” can be renamed without searching the entire project.

Do not implement online multiplayer in this version. Separate racer movement, player input, and AI decision-making cleanly so networking or local multiplayer can be added later.

======================================================================
3. PRODUCT DEFINITION
======================================================================

WADDLE WARS is a polished, stylized 3D party racing runner starring competitive penguins.

The player races against seven AI-controlled penguins through colorful Antarctic obstacle courses. Races combine waddling, belly sliding, jumping, swimming, shortcuts, environmental hazards, collectible fish, physical interference, and comedic power-ups.

The tone is:

- Playful.
- Energetic.
- Family-friendly.
- Competitive without violence or cruelty.
- Visually charming.
- Easy to understand.
- Difficult to master.
- Full of physical comedy.

A race should normally last approximately two to four minutes.

The primary gameplay promise is:

“Waddle precisely, slide for speed, use the environment, and outsmart seven chaotic penguin rivals.”

The game must feel distinct from a generic runner. Penguin movement, momentum, ice traction, downhill sliding, water transitions, flipper attacks, snow effects, and Antarctic course hazards must define the experience.

======================================================================
4. CORE GAMEPLAY
======================================================================

Create a third-person 3D point-to-point racing game with eight racers:

- One human-controlled penguin.
- Seven AI-controlled penguins.

The player automatically moves forward at a manageable base speed. Skill comes from steering, route choice, maintaining momentum, jumping, sliding, timing attacks, avoiding hazards, and using items.

Implement a polished racer state machine with at least these states:

- Waddling.
- Belly sliding.
- Airborne.
- Swimming.
- Boosted.
- Stunned.
- Recovering.
- Finished.

Required player actions:

1. Steering
   - Responsive left/right movement.
   - Analog gamepad support.
   - Smooth keyboard steering.
   - Touch drag or virtual steering support.
   - Reduced air control compared with ground control.

2. Penguin hop
   - Used to clear obstacles and gaps.
   - Include coyote time.
   - Include input buffering.
   - Include squash-and-stretch animation.
   - Include landing particles and sound.
   - Prevent frustrating edge failures.

3. Belly slide
   - Hold to lower the penguin and enter a momentum-based slide.
   - Accelerate downhill.
   - Retain more speed on ice.
   - Lose speed on deep snow and uphill surfaces.
   - Allow controlled drifting.
   - Pass beneath low obstacles.
   - Include snow or ice trails, animation, camera effects, and sound.
   - Transition smoothly in and out.

4. Flipper shove
   - Short-range side attack with a cooldown.
   - Gives nearby opponents a humorous stumble.
   - Does not cause excessive chain-stunning.
   - Includes clear anticipation, impact feedback, and recovery.
   - AI racers must also be able to use it intelligently.

5. Item use
   - Carry one power-up at a time.
   - Show the held item clearly in the HUD.
   - Support keyboard, gamepad, and touch input.
   - Prevent accidental repeated activation.

6. Swimming
   - Enter naturally after landing in designated water routes.
   - Maintain forward momentum.
   - Allow steering and short dives or dolphin-like bursts.
   - Provide underwater bubbles, splashes, altered sound, and camera feedback.
   - Return smoothly to land using ramps or ice edges.

7. Recovery
   - Falling off the course or entering a fatal hazard returns the racer to the most recent checkpoint.
   - Apply a fair time and speed penalty.
   - Use a quick, polished transition.
   - Never leave the racer stuck.

Create distinct surface behavior for:

- Packed snow.
- Deep snow.
- Smooth ice.
- Rough ice.
- Water.
- Boost surfaces.

Implement slope-aware acceleration and traction. The controls must feel responsive rather than physically uncontrollable.

======================================================================
5. POWER-UPS AND PICKUPS
======================================================================

Implement at least five polished power-ups:

1. Snowball
   - Throws toward a valid racer ahead.
   - Uses forgiving targeting.
   - Causes a brief tumble or slowdown.
   - Can miss or hit course geometry.

2. Ice Shield
   - Blocks one attack or major hazard.
   - Has a clearly visible translucent shield effect.
   - Breaks with satisfying visual and audio feedback.

3. Fish Frenzy
   - Provides a temporary speed boost.
   - Produces speed lines, trail effects, increased FOV, and energetic audio.
   - Does not make steering impossible.

4. Fish Magnet
   - Attracts nearby fish collectibles.
   - Shows a clear magnetic or spiral visual effect.

5. Blizzard Burst
   - Creates a short localized cloud behind or around the user.
   - Briefly reduces traction or visibility for opponents.
   - Must remain readable and not obscure the player’s entire screen.

Implement collectible fish along courses.

Fish serve as:

- In-race score pickups.
- Persistent cosmetic currency.
- A reason to explore alternate routes.

Use satisfying pickup animation, sound, particle effects, and HUD feedback.

Use fair item distribution. Racers in lower positions may receive slightly stronger assistance, but avoid obvious or frustrating cheating.

======================================================================
6. GAME MODES
======================================================================

Implement these four playable modes:

1. Quick Race
   - Select a course.
   - Select AI difficulty.
   - Race against seven opponents.
   - Show complete results and rewards.

2. Grand Prix
   - Three consecutive races.
   - Award points based on finishing position.
   - Show standings after each event.
   - Show a final cup ceremony.
   - Save the best Grand Prix result.

3. Endless Expedition
   - A continuously assembled obstacle course made from reusable course segments.
   - Difficulty and speed increase gradually.
   - Score is based on distance, fish, near misses, and opponent placement.
   - End after elimination or a clearly defined failure condition.
   - Save the local high score.

4. Time Trial
   - No combat items.
   - Race against the player’s locally recorded best ghost.
   - Record checkpoints and transforms efficiently.
   - Save best times separately for each course.
   - Allow restarting quickly.

Also implement a short interactive tutorial called Waddle School.

The tutorial must teach:

- Steering.
- Jumping.
- Sliding.
- Surface differences.
- Shoving.
- Power-ups.
- Checkpoints.
- Finishing a race.

The tutorial must use actual gameplay instead of text-only instruction screens.

======================================================================
7. COURSES
======================================================================

Create at least three visually and mechanically distinct complete courses.

Each course must have:

- A clear starting area.
- A countdown.
- Checkpoints.
- Alternate paths.
- At least one shortcut.
- Safe introductory obstacles.
- Increasing challenge.
- A recognizable final sequence.
- A finish line.
- AI-compatible navigation.
- Respawn support.
- Decorative scenery.
- Ambient animation.
- Course-specific hazards.
- Approximately two to four minutes of gameplay for an average player.

Course 1: GLACIER GAUNTLET

Theme:
- Bright daytime glacier.
- Snowbanks.
- Blue ice caves.
- Wooden research walkways.
- Flags.
- Distant mountains.
- Friendly spectator penguins.

Signature moments:
- Wide beginner slope.
- Ice cave slalom.
- Low tunnel requiring a belly slide.
- Cracking ice shortcut.
- Rolling snowball section.
- Large final downhill slide.

Course 2: AURORA ASCENT

Theme:
- Twilight mountain course.
- Green, cyan, and violet aurora.
- Dark blue snow.
- Windy ridges.
- Ice crystals.
- Warm research lights.

Signature moments:
- Zigzag uphill section.
- Strong side winds.
- Falling icicles with readable warnings.
- Narrow ridge shortcut.
- Ice geyser jumps.
- Fast corkscrew-like downhill finish.

Course 3: ICEBERG BAY

Theme:
- Open ocean.
- Floating icebergs.
- Sunrise or sunset lighting.
- Water routes.
- Buoys.
- Distant whales represented non-disruptively.
- Snow-covered research boats or stations in the distance.

Signature moments:
- Moving ice platforms.
- Swim channel.
- Wave ramps.
- Tilting ice slabs.
- Seal obstacles that slide across the path without being harmed.
- Final sequence alternating between water and ice.

Use reusable procedural and modular track components, but hand-curate each required course so it has intentional pacing and recognizable landmarks. Endless Expedition may assemble variants of these components procedurally using a deterministic seed.

======================================================================
8. HAZARDS AND COURSE INTERACTIONS
======================================================================

Implement at least seven hazard types chosen from:

- Rolling snowballs.
- Falling icicles.
- Cracking ice.
- Deep snow drifts.
- Strong wind zones.
- Ice geysers.
- Moving icebergs.
- Tilting ice platforms.
- Sliding seals.
- Collapsing snow ledges.
- Low ice tunnels.
- Rotating research barriers.

Every hazard must:

- Telegraph danger.
- Have fair collision.
- Work with AI.
- Provide feedback when triggered.
- Avoid repeated unavoidable hits.
- Have a reasonable recovery behavior.
- Be visually integrated into its environment.

Include optional boost ramps, downhill speed lanes, jump pads disguised as ice geysers, and risky shortcuts.

======================================================================
9. AI RACERS
======================================================================

Create seven AI opponents with distinct names, colors, cosmetic combinations, and behavior personalities.

Example personalities:

- Balanced.
- Aggressive.
- Shortcut-seeking.
- Item-focused.
- Defensive.
- High-risk.
- Consistent.

Do not make all opponents follow the exact same line.

AI must be able to:

- Follow course routes.
- Choose between route branches.
- Navigate checkpoints.
- Jump obstacles.
- Slide under barriers.
- Use downhill sliding.
- Enter and exit water.
- Avoid major hazards.
- Recover if displaced.
- Use items.
- Shove opponents.
- Finish every course.
- Adapt to each difficulty setting.

Implement three difficulty levels:

- Chill.
- Competitive.
- Emperor.

Difficulty should adjust:

- Reaction delay.
- Route quality.
- Ability timing.
- Mistake frequency.
- Steering precision.

Do not rely on extreme speed cheating. Use subtle bounded catch-up assistance only when necessary to keep a race engaging. Never teleport visible racers forward.

AI should continue functioning if it leaves the ideal path. Include unstuck detection and checkpoint recovery.

======================================================================
10. PROGRESSION AND CUSTOMIZATION
======================================================================

Create a local progression system without monetization.

Persistent systems:

- Fish currency.
- Player level or reputation.
- Cosmetic unlocks.
- Best course times.
- Endless high score.
- Grand Prix records.
- Achievements.
- Settings.
- Tutorial completion.

Create at least twelve cosmetic unlocks, such as:

- Scarves.
- Winter hats.
- Goggles.
- Bow ties.
- Ear warmers.
- Crown.
- Research headset.
- Snowflake trail.
- Fish trail.
- Aurora trail.

Create multiple penguin body appearances inspired by broad real-world penguin traits, but keep them stylized and original.

Cosmetics must not affect gameplay.

Create a customization screen with:

- Rotating 3D penguin preview.
- Category tabs.
- Locked/unlocked states.
- Price or unlock requirements.
- Equip interaction.
- Saved selection.
- Controller and touch usability.

Implement at least twelve achievements, including examples such as:

- Finish the tutorial.
- Win a Quick Race.
- Win on each course.
- Complete a Grand Prix.
- Collect a large number of fish.
- Land several successful shoves.
- Use every item.
- Set a Time Trial record.
- Reach a distance milestone in Endless Expedition.
- Win without using an item.
- Recover from last place.
- Find every course shortcut.

Achievement notifications should be visible but not disruptive.

Use versioned save data and graceful fallback if the save file is missing or invalid.

======================================================================
11. VISUAL DIRECTION
======================================================================

The game must look intentionally designed and polished, not like a collection of default Godot primitives.

Art style:

- Stylized low-poly 3D.
- Rounded shapes.
- Clean silhouettes.
- Saturated but controlled colors.
- Soft snow lighting.
- Strong contrast between the racers and course.
- Expressive animation.
- Wholesome physical comedy.
- Premium indie-game presentation.
- Original design rather than imitation of an existing franchise.

Create an appealing procedural penguin character using original meshes or composed geometry.

The penguin must include:

- Rounded black or dark navy body.
- Light belly patch.
- Beak.
- Feet.
- Flippers.
- Eyes.
- Expressive brows or eye shapes where useful.
- Cosmetic attachment points.
- A readable silhouette at gameplay distance.

Use animation and secondary motion to prevent the character from looking rigid:

- Side-to-side waddle.
- Flipper swing.
- Head bob.
- Anticipation before jumping.
- Squash and stretch.
- Flattened belly-slide pose.
- Airborne pose.
- Swimming stroke.
- Stumble.
- Victory celebration.
- Defeat reaction.
- Idle variations.
- Cosmetic bounce or sway where appropriate.

Use AnimationPlayer, Tween, procedural animation, or a simple custom rig. Choose the method that produces the most reliable result.

Create original environment visuals, including:

- Layered snow.
- Ice formations.
- Mountains.
- Ocean.
- Clouds.
- Aurora.
- Research props.
- Course signage.
- Flags.
- Buoys.
- Snow-covered rocks.
- Spectator penguins.
- Distant scenery.

Create polished shaders suitable for mobile:

- Stylized ice with controlled highlights and fresnel-like edge response.
- Lightweight animated water.
- Unshaded or inexpensive aurora ribbons.
- Snow sparkle used sparingly.
- Pickup glow.
- Shield effect.
- Speed trail.
- Finish-line effect.

Avoid expensive full-screen effects that substantially harm mobile performance.

Add visual effects for:

- Snowfall.
- Landing puffs.
- Sliding trails.
- Water splashes.
- Swimming bubbles.
- Fish pickups.
- Boosting.
- Impacts.
- Shield breaking.
- Blizzard power-up.
- Checkpoints.
- Finish line.
- Victory ceremony.

Use a polished WorldEnvironment with suitable tonemapping, fog, ambient light, and platform-sensitive quality settings.

Build a live animated title-screen diorama rather than using a blank static background.

Create an original game logo and icon. The logo should be bold, playful, readable, and usable on both desktop and phone screens.

======================================================================
12. CAMERA AND GAME FEEL
======================================================================

Implement a responsive third-person chase camera.

Required behavior:

- Smooth positional follow.
- Predictive look direction.
- Speed-sensitive FOV.
- Course-aware height.
- Reduced clipping.
- Clear visibility during jumps and slides.
- Water transition behavior.
- Finish-line camera.
- Victory camera.
- Optional subtle camera shake.

Add game-feel improvements:

- Brief hit-stop where appropriate.
- Controller vibration with an enable/disable setting.
- Squash and stretch.
- Impact flashes that do not obscure gameplay.
- Speed lines.
- Audio pitch changes based on speed.
- Responsive UI animation.
- Smooth transitions.
- Strong countdown feedback.
- Clear checkpoint feedback.
- Slow-motion finish moment for close races when practical.

Camera shake must have:

- Full.
- Reduced.
- Off.

Do not use excessive camera movement.

======================================================================
13. USER INTERFACE
======================================================================

Create a complete, polished, animated UI.

Required screens:

- Boot or studio splash.
- Title screen.
- Main menu.
- Mode selection.
- Course selection.
- Difficulty selection.
- Penguin customization.
- Progress and achievements.
- Settings.
- Controls and remapping.
- Credits.
- Tutorial prompts.
- Pause menu.
- Race HUD.
- Grand Prix standings.
- Results screen.
- Reward and unlock presentation.
- Confirmation dialogs where needed.

Required title-menu options:

- Play.
- Waddle School.
- Customize.
- Achievements.
- Settings.
- Credits.
- Quit on desktop.

Race HUD must show:

- Current position.
- Racer count.
- Course progress.
- Current item.
- Fish collected.
- Speed feedback.
- Checkpoint or section information where useful.
- Time in Time Trial.
- Score and distance in Endless mode.

The UI must:

- Use an original coherent visual theme.
- Support mouse, keyboard, gamepad, and touch.
- Have correct gamepad focus navigation.
- Scale responsively.
- Respect safe areas.
- Use large enough mobile touch targets.
- Have hover, focus, pressed, disabled, and locked states.
- Include transitions and subtle animation.
- Avoid tiny text.
- Avoid text overlapping at unusual resolutions.
- Keep important information away from device cutouts.

Create an original bundled font solution using a redistributable system-safe approach or use Godot’s built-in fallback safely. Do not package a font without a compatible license.

Use localization keys and a translation-ready structure even though only English content is required now.

======================================================================
14. CONTROLS
======================================================================

Default desktop keyboard controls:

- Steer left/right: A/D or Left/Right arrows.
- Jump: Space.
- Belly slide: Left Ctrl or S/Down.
- Flipper shove: E.
- Use item: Q.
- Pause: Escape.

Default gamepad controls:

- Steer: Left stick or D-pad.
- Jump: South face button.
- Slide: East face button or left trigger.
- Shove: West face button.
- Item: North face button or right trigger.
- Pause: Start/Menu.

Touch controls:

- Virtual steering zone or horizontal drag.
- Jump button.
- Slide button.
- Shove button.
- Item button.
- Pause button.

Touch controls should appear only on touchscreen/mobile configurations unless enabled manually.

Implement keyboard and gamepad remapping. Preserve remapped controls in settings.

Provide options for:

- Touch control scale.
- Touch control opacity.
- Steering sensitivity.
- Gamepad dead zone.
- Hold or toggle slide.

======================================================================
15. AUDIO
======================================================================

Create original audio assets programmatically.

Create at least:

- Two or more looping music tracks.
- Title-menu music.
- Race music.
- Final-lap or high-intensity variation where appropriate.
- Fifteen or more sound effects.

Sound effects should include:

- Menu hover.
- Menu select.
- Countdown.
- Race start.
- Jump.
- Landing.
- Sliding.
- Swimming.
- Splash.
- Fish pickup.
- Power-up pickup.
- Power-up activation.
- Snowball impact.
- Shield break.
- Shove.
- Stumble.
- Checkpoint.
- Finish.
- Victory.
- Unlock.
- Penguin chirps.

Use synthesized or procedurally generated original sounds. A helper script may generate WAV files. Retain that generation script in tools/ so the assets can be reproduced.

Music should be playful and energetic, using an original combination of light percussion, bells, plucked tones, bass, and wintry ambience. Do not imitate a copyrighted melody.

Implement an AudioManager with:

- Master volume.
- Music volume.
- Sound-effect volume.
- Muting.
- Smooth music transitions.
- Basic pooling for overlapping sound effects.
- Saved settings.

======================================================================
16. SETTINGS AND ACCESSIBILITY
======================================================================

Implement these settings:

Display:
- Windowed.
- Borderless or fullscreen.
- Resolution selection on desktop.
- VSync.
- Quality preset.
- Shadow quality.
- Particle quality.
- Anti-aliasing when supported.
- Frame-rate limit.

Audio:
- Master volume.
- Music volume.
- Sound-effect volume.
- Mute when unfocused where supported.

Gameplay:
- Steering sensitivity.
- Controller vibration.
- Hold/toggle slide.
- Tutorial prompts.
- Touch controls.

Accessibility:
- Camera shake: full, reduced, off.
- High-contrast pickups.
- Reduced flashing effects.
- Colorblind-safe interface cues.
- Larger HUD option.
- Adjustable UI scale.
- Pause during controller disconnection.
- Separate visual cues for important audio events.

Settings must apply immediately where practical and persist between launches.

======================================================================
17. MOBILE READINESS
======================================================================

Build mobile readiness into the project now rather than treating it as a future rewrite.

Requirements:

- Use the Mobile renderer.
- Use landscape orientation.
- Create responsive safe-area-aware UI.
- Include touch controls.
- Do not require hover interactions.
- Avoid reliance on right-click.
- Avoid reliance on precise mouse pointing.
- Use user:// storage.
- Include Android export configuration where possible.
- Include an iOS export preset or documented setup where possible.
- Use scalable interface assets.
- Avoid overly large textures.
- Avoid excessive transparent layers.
- Pool frequently created gameplay objects.
- Avoid per-frame memory allocation in core race loops.
- Use lightweight shaders.
- Use platform quality presets.
- Pause correctly when the app loses focus.
- Handle touchscreen and controller coexistence.
- Provide a mobile performance profile.

Performance targets:

Desktop:
- Target 60 FPS at 1920×1080 on ordinary modern hardware.

Mobile:
- Target 60 FPS on capable devices.
- Maintain a usable 30 FPS quality fallback.
- Provide lower particle, shadow, and scenery settings.

These are optimization targets, not excuses to reduce visual quality indiscriminately. Create graceful quality scaling.

======================================================================
18. PROJECT ARCHITECTURE
======================================================================

Organize the project clearly.

A suitable structure is:

res://
  autoload/
  assets/
    audio/
    icons/
    materials/
    models/
    shaders/
    textures/
    ui/
  data/
    achievements/
    cosmetics/
    courses/
    racers/
    settings/
  scenes/
    characters/
    courses/
    gameplay/
    hazards/
    menus/
    pickups/
    powerups/
    ui/
    vfx/
  scripts/
    ai/
    camera/
    characters/
    courses/
    gameplay/
    input/
    mobile/
    progression/
    save/
    ui/
    utilities/
  tests/
  tools/
  project.godot
  export_presets.cfg
  README.md
  GAME_DESIGN.md
  ARCHITECTURE.md
  TESTING.md
  ATTRIBUTION.md
  BUILD_STATUS.md

Use autoloads only for genuinely global responsibilities, such as:

- Game flow.
- Save management.
- Settings.
- Audio.
- Scene transitions.
- Achievement tracking.

Keep gameplay logic out of UI scripts.

Separate:

- Racer physics.
- Player input.
- AI decisions.
- Race rules.
- Course data.
- Presentation.
- Save data.
- Audio.
- UI.

Use resources or data files for:

- Course metadata.
- Power-up definitions.
- Cosmetics.
- Achievements.
- Difficulty settings.
- Racer personalities.
- Surface properties.

Implement object pooling for:

- Fish pickups where useful.
- Snowballs.
- Repeated particles.
- Temporary impact effects.
- Floating HUD notifications.

Use signals to avoid hard-coded dependencies.

Use deterministic random seeds for procedural course generation and reproducible tests.

======================================================================
19. SAVE SYSTEM
======================================================================

Implement versioned local save data.

Save:

- Fish currency.
- Equipped cosmetics.
- Unlocked cosmetics.
- Player progression.
- Achievements.
- Tutorial completion.
- Best times.
- Endless high score.
- Grand Prix records.
- Control bindings.
- Settings.

Requirements:

- Save atomically or use a safe temporary-file replacement strategy.
- Gracefully recover from invalid or partially corrupt data.
- Preserve compatible data during save-version upgrades.
- Never erase valid progress merely because one optional field is missing.
- Provide a development-only reset mechanism that is not exposed accidentally in the release UI.
- Test save/load round trips.

======================================================================
20. TESTING AND VALIDATION
======================================================================

Create an automated lightweight testing system that does not depend on a third-party plugin.

At minimum, test:

- Project scripts parse.
- Main scene loads.
- Save/load round trip works.
- Default settings load.
- Each required course loads.
- Each course contains valid checkpoints.
- All eight racers spawn.
- Racer states transition without invalid states.
- Every power-up can be instantiated and activated.
- Every required menu scene loads.
- UI buttons reference valid destinations.
- Touch controls instantiate.
- AI can progress through course checkpoints.
- Recovery returns a racer to a valid checkpoint.
- Time Trial ghost data can be recorded and loaded.
- Grand Prix scoring produces valid standings.
- Endless segment generation is deterministic for a given seed.

Discover the available Godot executable rather than assuming a single command name. Common possibilities include godot, godot4, or a platform-specific executable.

Run Godot in headless/editor mode to import and validate the project.

Run the automated test suite.

Launch the main scene and inspect runtime logs.

When display tools are available:

- Capture screenshots of the title screen.
- Capture screenshots of each course.
- Capture the HUD.
- Capture the customization screen.
- Inspect the screenshots for clipping, poor composition, missing assets, broken lighting, unreadable text, and placeholder-looking visuals.
- Correct visible issues and capture again.

Test at representative resolutions:

- 1920×1080.
- 1280×720.
- 2560×1440 where practical.
- A wide mobile landscape resolution such as 2400×1080.
- A tablet-like landscape resolution.

Check for:

- Parser errors.
- Missing resources.
- Invalid node paths.
- Repeated runtime errors.
- Navigation failures.
- Racers getting stuck.
- Broken menu focus.
- Save failures.
- UI overflow.
- Audio clipping.
- Particles that obscure gameplay.
- Unfair hazards.
- Inconsistent frame-time spikes.

Fix all critical and high-severity issues before finishing.

If export templates are installed, create test exports. If templates or signing tools are unavailable, validate export presets and document the exact remaining platform setup without treating that external setup as a game-code failure.

======================================================================
21. DOCUMENTATION
======================================================================

Create a clear README.md containing:

- Game overview.
- Controls.
- Game modes.
- System requirements.
- Exact Godot version.
- How to open the project.
- How to run from the editor.
- How to run automated tests.
- How to export for Windows.
- How to export for macOS.
- How to export for Linux.
- Android export preparation.
- iOS export preparation.
- Project structure.
- Save-data location.
- How to add a course.
- How to add a cosmetic.
- How to add a power-up.
- Known non-critical limitations, if any.

Create GAME_DESIGN.md containing:

- Design pillars.
- Core loop.
- Mechanics.
- Courses.
- Modes.
- Progression.
- Difficulty.
- Accessibility.
- Art and audio direction.

Create ARCHITECTURE.md containing:

- Major systems.
- Scene hierarchy.
- Data flow.
- Autoload responsibilities.
- Input abstraction.
- AI architecture.
- Save format.
- Mobile considerations.

Create TESTING.md containing:

- Test commands.
- Automated test coverage.
- Manual QA checklist.
- Tested resolutions.
- Tested input methods.
- Last validation results.

Create ATTRIBUTION.md.

Even if all assets are original and procedural, state that clearly and document any engine or third-party licensing obligations that actually apply.

======================================================================
22. PRIORITY ORDER
======================================================================

Use this priority order:

Priority 1: A complete playable loop.
- Launch.
- Main menu.
- Mode selection.
- Race.
- Finish.
- Results.
- Return to menu.

Priority 2: Excellent movement and game feel.
- Steering.
- Jumping.
- Sliding.
- Surface behavior.
- Camera.
- Feedback.

Priority 3: Reliable courses and AI.
- Three courses.
- Checkpoints.
- Recovery.
- Seven functional opponents.

Priority 4: Visual and audio polish.
- Character.
- Environment.
- Animation.
- VFX.
- Music.
- Sound.

Priority 5: Full game systems.
- Four modes.
- Tutorial.
- Progression.
- Cosmetics.
- Achievements.
- Saves.
- Settings.

Priority 6: Mobile readiness and optimization.

Priority 7: Additional polish after all required features work.

Do not spend excessive time perfecting an optional visual detail while the main game loop remains incomplete.

======================================================================
23. REQUIRED ACCEPTANCE CRITERIA
======================================================================

Do not consider the task finished until all of the following are true:

[ ] The project opens in Godot 4.7.1 without missing-resource errors.

[ ] The title screen is visually polished and animated.

[ ] Every main-menu button works.

[ ] A first-time player can complete Waddle School.

[ ] Quick Race is fully playable.

[ ] Grand Prix is fully playable.

[ ] Endless Expedition is fully playable.

[ ] Time Trial and local ghost recording are functional.

[ ] Three complete courses exist and are visually distinct.

[ ] One player and seven AI racers can complete every course.

[ ] Jumping, sliding, swimming, shoving, items, pickups, hazards, checkpoints, and recovery work.

[ ] At least five power-ups work.

[ ] At least seven hazard types work.

[ ] Keyboard controls work.

[ ] Gamepad controls and menu focus work.

[ ] Touch controls exist and are usable.

[ ] Race HUD is complete.

[ ] Pause and resume work.

[ ] Results and reward screens work.

[ ] Progression persists.

[ ] Cosmetics can be unlocked, equipped, previewed, and saved.

[ ] At least twelve cosmetics exist.

[ ] At least twelve achievements exist.

[ ] Audio settings work.

[ ] Display and gameplay settings work.

[ ] Accessibility options work.

[ ] The interface scales across desktop and wide mobile resolutions.

[ ] The game contains original music and sound effects.

[ ] The game has an original logo and icon.

[ ] There are no required features represented only by TODOs or stubs.

[ ] Automated tests pass.

[ ] Runtime logs contain no repeated errors.

[ ] README.md explains how to run, test, and export the game.

[ ] BUILD_STATUS.md accurately reflects the completed project.

======================================================================
24. FINAL POLISH PASS
======================================================================

After all required features work, perform a dedicated polish pass.

Review the game as a player, not only as a programmer.

Improve:

- First launch experience.
- Menu presentation.
- Movement responsiveness.
- Course readability.
- Shortcut visibility.
- AI fairness.
- Race pacing.
- Camera behavior.
- Character animation.
- Sound balance.
- Impact feedback.
- UI hierarchy.
- Results presentation.
- Unlock presentation.
- Loading transitions.
- Mobile button placement.
- Performance hotspots.

Remove:

- Debug labels.
- Temporary buttons.
- Test geometry visible to players.
- Excessive developer logging.
- Awkward pauses.
- Dead menu ends.
- Unnecessary instructions.
- Repetitive sound effects.
- Visually inconsistent assets.

Use screenshots and runtime inspection when available. Fix obvious visual problems instead of merely documenting them.

======================================================================
25. FINAL RESPONSE FORMAT
======================================================================

Only after implementation and validation, provide a concise completion report containing:

1. What was built.
2. The exact command or steps to launch it.
3. The test commands that were run.
4. Test results.
5. Export status for each target platform.
6. Any genuinely external requirement that could not be completed locally, such as signing credentials or unavailable export templates.
7. The location of the main documentation.

Do not provide a future plan as a substitute for implementation.

Begin now. Create the complete Waddle Wars project, run it, test it, fix it, and continue until the acceptance criteria are satisfied.
