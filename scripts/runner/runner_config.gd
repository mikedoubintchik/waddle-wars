class_name RunnerConfig
## Shared contract for Waddle Run, the endless-runner mode.
##
## Everything that more than one runner script needs to agree on lives here:
## lane geometry, chunk size, the speed ramp and the group names used to find
## hazards and pickups. Runner scripts import nothing from the racing game
## except the art (PenguinVisual, VisualLibrary), so the two modes cannot break
## each other.

## --- Track geometry ---------------------------------------------------------
## The run goes down -Z, exactly like the racing courses, so the penguin art,
## the chase camera conventions and every "forward is -Z" assumption in the
## visual code carry over unchanged.
const LANE_COUNT: int = 3
const LANE_WIDTH: float = 3.1
## Half-width of the walkable deck, used for the side walls and the snow deck.
const DECK_HALF_WIDTH: float = 5.4
## One streamed piece of track. Long enough that a chunk holds a real obstacle
## pattern, short enough that the build cost per chunk stays under a frame.
const CHUNK_LENGTH: float = 36.0
## Chunks kept live ahead of the player, and behind before recycling.
const CHUNKS_AHEAD: int = 7
const CHUNKS_BEHIND: int = 2

## --- Motion -----------------------------------------------------------------
const START_SPEED: float = 15.0
const MAX_SPEED: float = 38.0
## Metres per second gained per second of running.
const SPEED_RAMP: float = 0.26
## Time to slide fully from one lane to the next.
const LANE_CHANGE_TIME: float = 0.16
const JUMP_SPEED: float = 9.4
const GRAVITY: float = 27.0
const SLIDE_TIME: float = 0.72
## Height of the collision probe when upright and when sliding; the slide value
## is what lets a slide pass under a bar.
const STAND_HEIGHT: float = 1.35
const SLIDE_HEIGHT: float = 0.55

## --- Scoring ----------------------------------------------------------------
## Points per metre, before the multiplier.
const POINTS_PER_METRE: float = 1.0
const POINTS_PER_FISH: int = 25
## The multiplier climbs one step per this many metres of clean running and
## resets to 1 on any hit.
const MULTIPLIER_STEP_METRES: float = 260.0
const MAX_MULTIPLIER: int = 6

## --- Failure ----------------------------------------------------------------
## Hits the player can take before the run ends. A hit costs speed and lets the
## avalanche close in; the third one is fatal.
const MAX_HITS: int = 3
## Seconds of invulnerability after a hit, so one obstacle cannot double-hit.
const HIT_IFRAMES: float = 1.1
## Speed lost per hit, recovered by the normal ramp.
const HIT_SPEED_LOSS: float = 6.0

## --- Avalanche --------------------------------------------------------------
## Metres behind the player the wall sits when running clean, and how far it
## lunges forward on each hit. Reaching zero ends the run.
const CHASER_BASE_GAP: float = 34.0
const CHASER_GAP_PER_HIT: float = 11.0
## How fast the gap recovers toward CHASER_BASE_GAP, in metres per second.
const CHASER_RECOVER: float = 3.4

## --- Power-ups --------------------------------------------------------------
## The three that carry an endless runner: one that changes how you COLLECT
## (magnet), one that changes what a MISTAKE costs (shield), and one that
## changes what the run is WORTH (double). Anything past those three is
## decoration; these three each rewrite a different verb.
const POWERUP_MAGNET: StringName = &"magnet"
const POWERUP_SHIELD: StringName = &"shield"
const POWERUP_DOUBLE: StringName = &"double"
const POWERUP_IDS: Array[StringName] = [POWERUP_MAGNET, POWERUP_SHIELD, POWERUP_DOUBLE]
const POWERUP_TIME: float = 9.0
## Radius the magnet sweeps fish in from, and how fast they fly.
const MAGNET_RADIUS: float = 9.0
const MAGNET_SPEED: float = 26.0

## --- Ramps ------------------------------------------------------------------
## A ramp launches the player over the next stretch. It is the one obstacle
## that is pure reward, and the reason to look forward rather than down.
const RAMP_LAUNCH: float = 13.5

## --- Group names ------------------------------------------------------------
## Runner-only groups: the racing game's hazard/pickup groups are deliberately
## not reused, so nothing in a race can ever see a runner object or vice versa.
const GROUP_HAZARD: StringName = &"runner_hazard"
const GROUP_PICKUP: StringName = &"runner_pickup"
## Power-up crates. A separate group from fish so the magnet cannot suck in a
## power-up and so the two can never be confused at the collision site.
const GROUP_POWERUP: StringName = &"runner_powerup"

## Lane centre in metres on X. Lane 0 is left, LANE_COUNT-1 is right.
static func lane_x(lane: int) -> float:
	var mid := float(LANE_COUNT - 1) * 0.5
	return (float(lane) - mid) * LANE_WIDTH


## Run speed after `elapsed` seconds, before any hit penalty.
static func speed_at(elapsed: float) -> float:
	return minf(START_SPEED + elapsed * SPEED_RAMP, MAX_SPEED)


## Score multiplier for a distance run without being hit.
static func multiplier_for(clean_metres: float) -> int:
	return clampi(1 + int(clean_metres / MULTIPLIER_STEP_METRES), 1, MAX_MULTIPLIER)
