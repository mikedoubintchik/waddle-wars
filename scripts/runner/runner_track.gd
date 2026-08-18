class_name RunnerTrack
extends Node3D
## Infinite track streamer for Waddle Run, the endless-runner mode.
##
## The run is a straight polar causeway heading down -Z, streamed in fixed
## chunks of RunnerConfig.CHUNK_LENGTH. update_stream() keeps CHUNKS_AHEAD
## chunks in front of the player and frees anything further than CHUNKS_BEHIND
## behind, so the live node count is flat no matter how long a run lasts.
##
## Every mesh and material a chunk uses comes out of a static cache built once,
## at setup(). That is not micro-optimisation. On WebGL a first-sight material
## is a program link that stalls the frame it appears in, and an endless mode
## manufactures geometry forever -- a per-chunk material would hitch every few
## seconds, right in the middle of the only thing the mode does. Repeated
## dressing goes through MultiMesh for the same reason: draw-call overhead
## through ANGLE, not shading, is what a streamed course runs out of first.
##
## THE WORLD HAS TO MOVE. A runner whose only moving parts are the ones the
## player dodges reads as a corridor with props in it, however good the props
## are. So: seals slide across the lanes, banners flap on the kerb, ice shards
## tumble past the verge, gulls drift overhead, the fish bob and spin, crates
## turn on two axes, and the whole look changes every BIOME_LENGTH metres. All
## of it is instance-transform writes into MultiMeshes that already exist -- no
## extra nodes, no extra draw calls, and the entire animated set for a chunk is
## one _process() loop over three arrays.
##
## Fairness is a BUILD-TIME invariant here, not a runtime hope:
##   * no obstacle row ever fills all three lanes with solid blocks;
##   * a jump-required obstacle is never placed within a jump's worth of
##     travel of a slide-required one in the same lane (see _can_place());
##   * nothing at all is built inside a ramp's launch corridor, because a
##     launched penguin has no input that matters until it lands;
##   * moving seals own one Z band each, so however their sweeps line up there
##     are always two clear lanes at any point on the track;
##   * the first WARMUP_CHUNKS of a run carry no obstacles at all, so the
##     player gets to find the lanes and the controls before being tested.
## Placement helpers REFUSE rather than compromise: when a pattern asks for
## something unfair the obstacle is dropped, which can only ever make a chunk
## gentler than authored.
##
## Deliberately isolated from the racing game: nothing here touches Racer,
## CourseBase, RaceManager or PathGuide, and hazards/pickups live on their own
## collision layer and in the runner-only groups from RunnerConfig, so a race
## and a run can never see each other's objects.

## --- Collision --------------------------------------------------------------
## Runner hazards and pickups share one layer well clear of the racing game's
## (GameConfig only uses bits 0-5). They never scan for anything themselves --
## the runner player owns the overlap test -- so their mask is 0 and their own
## monitoring stays off; being monitorABLE is the whole job.
const HAZARD_LAYER: int = 1 << 9

## --- Corridor geometry ------------------------------------------------------
## Low kerb walls rather than a tunnel: they have to say "the deck ends here"
## without eating the horizon, because the vista past the drop-off is most of
## what sells forward speed when the deck itself is featureless white.
const WALL_HEIGHT: float = 1.35
const WALL_THICKNESS: float = 0.55
## Depth of the drop beyond the kerb, and how far the snowfield below it runs
## before the dressing takes over.
const SHELF_DROP: float = 3.0
const SHELF_WIDTH: float = 26.0

## --- Obstacle dimensions ----------------------------------------------------
## A block is taller than the jump apex on purpose. JUMP_SPEED^2 / (2*GRAVITY)
## is about 1.64 m, so 2.0 m cannot be cleared and cannot be slid under: the
## only answer is a lane change, which is exactly what "block" means.
const BLOCK_WIDTH: float = 2.3
const BLOCK_HEIGHT: float = 2.0
const BLOCK_DEPTH: float = 1.5
## Shin-high, so a jump clears it with ~0.8 m to spare and a slide does not.
## 0.80 rather than 0.72: a sliding capsule is 0.85 m tall (the radius floors
## it), and a ridge much shorter than that starts letting slides through by
## accident -- and a ridge that low is invisible against snow at 50 m anyway.
const LOW_HEIGHT: float = 0.80
const LOW_DEPTH: float = 1.15
## Overhead bar clearance: the midpoint between the sliding and standing probe
## heights. Derived from the config rather than typed as a number so the bar
## keeps its meaning if the movement tuning moves -- it must always sit above
## SLIDE_HEIGHT (a slide fits) and below STAND_HEIGHT (running upright does
## not), and the midpoint is the placement with the most margin on both sides.
const BAR_CLEARANCE: float = (RunnerConfig.SLIDE_HEIGHT + RunnerConfig.STAND_HEIGHT) * 0.5
const BAR_THICKNESS: float = 1.05
const BAR_DEPTH: float = 1.3
## Launch ramp. One lane wide, so the other two stay an ordinary run; long
## enough that the wedge reads as a ramp rather than a step from 50 m out.
## Short and steep (about 21 degrees) rather than long and shallow. The first
## pass was 1.15 m over 5.2 m, and from the chase camera -- which looks along
## the slope, not across it -- a 12-degree wedge is indistinguishable from a
## painted rectangle lying on the deck.
const RAMP_WIDTH: float = 2.55
const RAMP_HEIGHT: float = 1.55
const RAMP_DEPTH: float = 4.0
## Sliding seal. Its long axis lies along X because it travels along X: a seal
## that crosses the deck nose-first is the only version that reads as an animal
## going somewhere rather than a log being dragged sideways.
const SEAL_LENGTH: float = 2.25
const SEAL_GIRTH: float = 0.46
const SEAL_HEIGHT: float = 0.92
## How far across the deck one seal travels, and how long a full there-and-back
## takes. Just past the outer lane centres, so a seal always has somewhere to
## be that is not on top of the player.
const SEAL_SWEEP: float = RunnerConfig.LANE_WIDTH * 1.08
const SEAL_PERIOD_EASY: float = 6.8
const SEAL_PERIOD_HARD: float = 4.2
## Ice arch tunnel. The apex clears a ramp launch (3.38 m of air plus a 1.35 m
## penguin) with room to spare, because a tunnel that decapitates a launched
## player is the single worst thing this file could ship.
const TUNNEL_SEGMENT: float = 6.0
const TUNNEL_APEX: float = 5.3
const TUNNEL_SPRING: float = 2.05

## --- Pickups ----------------------------------------------------------------
## Chest height on a standing penguin. The grab sphere is generous but no
## longer absurd: the first pass used a 0.95 m radius, which put a 1.9 m ball
## of "fish" across the lane and over the kerb walls.
const FISH_Y: float = 1.08
const FISH_RADIUS: float = 0.62
const FISH_SPACING: float = 3.6
## Nose-to-tail length of the fish art. Roughly a real Antarctic silverfish
## against a 1.1 m penguin, which is the whole reason the pickup reads as food.
const FISH_LENGTH: float = 0.62
## Apex of a fish arc laid over a jumpable obstacle -- inside the 1.64 m jump
## so the arc is collectable, above the 0.80 m obstacle so it is not free.
const FISH_ARC_APEX: float = 1.52
## Every fish stays this far inside the kerb walls. Belt and braces on top of
## the lane maths: sweeps, arcs and (at runtime) the magnet all move fish in X,
## and a fish inside a wall is the defect players notice first.
const FISH_WALL_MARGIN: float = 1.1

## --- Power-ups --------------------------------------------------------------
## Metres between crates: rare enough that finding one is an event, common
## enough that a good run is never without one for long.
const POWERUP_GAP_MIN: float = 250.0
const POWERUP_GAP_MAX: float = 400.0
## The first crate of a run, close enough that a new player meets the mechanic
## before they have decided the mode does not have one.
const POWERUP_FIRST: float = 165.0
const POWERUP_RADIUS: float = 1.05
const POWERUP_Y: float = 1.25
## Clearance a crate keeps from every obstacle in its chunk. Wider than a lane
## change, so a crate can never be the reason a row became unsurvivable.
const POWERUP_CLEARANCE: float = 6.5

## --- Pacing -----------------------------------------------------------------
## Chunks at the very start of a run that are guaranteed empty.
const WARMUP_CHUNKS: int = 3
## Keeps obstacle rows off the chunk seams, so two chunks authored independently
## cannot butt two rows up against each other.
const CHUNK_EDGE_MARGIN: float = 4.5
## Spacing between obstacle rows INSIDE a pattern. In TIME (which is what a
## player actually experiences) these are ~1.0 s apart at the start speed and
## ~0.25 s apart at MAX_SPEED, which is where an endless runner should end up.
## The density the player actually feels is this crossed with the pattern
## weights in _pick_pattern(): about one hostile row every 27 m at difficulty
## 0, tightening to one every 14 m at difficulty 1.
const ROW_GAP_EASY: float = 16.0
const ROW_GAP_HARD: float = 8.4
## Minimum distance between a jump-required and a slide-required obstacle in
## the SAME lane. The design floor is 6 m, which is far too tight once the run
## is fast: a jump is airborne 2*JUMP_SPEED/GRAVITY (~0.70 s) and spends about
## 0.48 s of it above bar height, which at MAX_SPEED is ~18 m of track, and a
## slide is committed for SLIDE_TIME (0.72 s) -- the same trap in reverse. So
## the real gap scales with how fast the run has become.
const KIND_GAP_EASY: float = 14.0
const KIND_GAP_HARD: float = 22.0
## Chunks built per update_stream() call. Streaming only ever needs one; the
## cap exists so a teleport or a long frame hitch cannot turn into a multi-
## hundred-millisecond build spike.
const MAX_SPAWNS_PER_UPDATE: int = 3
## Distance over which RunnerGame ramps difficulty from 0 to 1. Mirrored here
## rather than imported because the streamer has to answer "how fast will the
## player be going when they reach this chunk" while building it -- see
## _speed_estimate(), which is what lets a ramp's fish arc be laid along the
## trajectory the player will actually fly.
const DIFFICULTY_DISTANCE: float = 2600.0

## --- Biomes -----------------------------------------------------------------
## Metres of running per biome band. Long enough to settle into (25-40 seconds
## depending on speed), short enough that a five-minute run sees all four.
const BIOME_LENGTH: float = 600.0
const BIOME_COUNT: int = 4

## Obstacle kinds. The index doubles as the lookup into KIND_NAMES, which is
## what lands in the "kind" metadata the runner player reads. RAMP is in the
## hazard group with the others even though it is pure reward: the player
## resolves it out of the same overlap scan, and a separate group would mean a
## second per-frame query for one object type.
enum Kind {
	NONE,
	BLOCK,
	BAR,
	LOW,
	RAMP,
	SEAL,
}

const KIND_NAMES: Array[String] = ["", "block", "bar", "low", "ramp", "seal"]

## Chunk archetypes. Named because a run should be recognisable in the replay
## of the player's memory ("the slide gallery got me") rather than a uniform
## sprinkle of hazards.
enum Pattern {
	OPEN,           ## Breathing room: a flowing fish line and one small hop.
	LANE_WEAVE,     ## Rows of solid blocks; the survivable lane moves.
	SLIDE_GALLERY,  ## Consecutive ice arches with fish laid low underneath.
	JUMP_STUTTER,   ## Staggered shin-high ridges, fish arcs over them.
	FISH_ARC,       ## Reward chunk: a sweeping fish line across the lanes.
	MIXED_GAUNTLET, ## Block row, arch, ridge row in sequence. Late-run only.
	PINCH,          ## Two lanes blocked; one thread of survivable track.
	SEAL_SLIDE,     ## Seals crossing the lanes, singly and in diagonal trains.
	TUNNEL,         ## Ice arch tunnel: enclosed, dim, slide bars inside.
	RAMP_RUN,       ## Launch ramp with its fish arc hanging in the air over it.
}

## Biome bands. Purely a LOOK: the same patterns run in all four, because a
## runner that changes its rules every 600 m stops being learnable. What
## changes is the palette, the dressing and how often the sky is the show.
enum Biome {
	DAY,     ## Bright glacier under a blue sky.
	DUSK,    ## Low sun, warm deck, long shadows.
	CAVE,    ## Blue ice cavern: darker, and where the tunnels live.
	NIGHT,   ## Aurora night: cold deck, curtains overhead, few bergs.
}

## --- Static art cache -------------------------------------------------------
## One instance of each, shared by every chunk of every run in the process.
static var _deck_mesh_cache: PlaneMesh = null
static var _seam_mesh_cache: ArrayMesh = null
static var _verge_mesh_cache: ArrayMesh = null
static var _block_mesh_cache: ArrayMesh = null
static var _low_mesh_cache: ArrayMesh = null
static var _arch_mesh_cache: ArrayMesh = null
static var _fish_mesh_cache: ArrayMesh = null
static var _ramp_mesh_cache: ArrayMesh = null
static var _seal_mesh_cache: ArrayMesh = null
static var _tunnel_mesh_cache: ArrayMesh = null
static var _mark_mesh_cache: ArrayMesh = null
static var _banner_mesh_cache: ArrayMesh = null
static var _bird_mesh_cache: ArrayMesh = null
static var _shard_mesh_cache: ArrayMesh = null
static var _curtain_mesh_cache: ArrayMesh = null
static var _crate_meshes: Dictionary = {}
static var _mark_material_cache: StandardMaterial3D = null
static var _tunnel_material_cache: StandardMaterial3D = null
static var _box_shapes: Dictionary = {}
static var _sphere_shapes: Dictionary = {}

var _seed: int = 0
var _headless: bool = false
## Live chunks, oldest first. Contiguous, so the index of _chunks[0] is enough
## to know every chunk's index.
var _chunks: Array[RunnerChunk] = []
var _first_index: int = 0
var _next_index: int = 0
var _last_pattern: int = -1
## Chunks of tunnel still owed. A 36 m tunnel is a doorway; the enclosure only
## reads as a PLACE once you have been inside it for a couple of seconds, so
## TUNNEL sometimes claims the following chunk as well.
var _tunnel_left: int = 0
## World z of the most recent jump-required and slide-required obstacle in each
## lane. Kept on the streamer rather than per chunk so the fairness rule holds
## across a chunk seam, where two independently-authored patterns meet.
var _lane_jump_z: PackedFloat32Array = PackedFloat32Array()
var _lane_slide_z: PackedFloat32Array = PackedFloat32Array()
## The stretch of track a launched penguin is flying over, in world z
## (_air_from_z is the ramp, _air_to_z the far end of the arc). Nothing is built
## inside it: mid-flight the player has no jump, no slide and no lane change
## worth the name, so anything in there is a hit they could not have avoided.
var _air_from_z: float = 1.0e9
var _air_to_z: float = 1.0e9
## World z at which the next power-up crate is due.
var _next_powerup_z: float = 0.0
## Rotates through RunnerConfig.POWERUP_IDS instead of rolling dice, so a run
## can never hand out four shields before its first magnet.
var _powerup_cursor: int = 0


## --- Public API -------------------------------------------------------------

## Builds the opening run of chunks from z = 0 heading toward -Z. Also primes
## the static mesh cache, so the first STREAMED chunk of a run never pays for
## mesh construction mid-frame -- the whole cost lands here, during the load.
func setup(seed_value: int) -> void:
	_headless = GameConfig.is_headless()
	_seed = seed_value
	_clear()
	if not _headless:
		_prime_art_cache()
	for i: int in RunnerConfig.CHUNKS_AHEAD:
		_spawn_chunk(i, 0.0)


## Frees every live chunk and rebuilds from z = 0. Used by "retry" so a restart
## costs a couple of milliseconds instead of a scene reload.
func reset(seed_value: int) -> void:
	setup(seed_value)


## Keeps CHUNKS_AHEAD chunks in front of the player and drops what is spent.
## difficulty is 0 at the start of a run and approaches 1 as it gets long; it
## raises obstacle density, unlocks the nastier patterns and tightens spacing.
func update_stream(player_z: float, difficulty: float) -> void:
	var diff := clampf(difficulty, 0.0, 1.0)
	var current := _chunk_index_at(player_z)
	var spawned := 0
	while _next_index < current + RunnerConfig.CHUNKS_AHEAD and spawned < MAX_SPAWNS_PER_UPDATE:
		_spawn_chunk(_next_index, diff)
		spawned += 1
	var cull_before := current - RunnerConfig.CHUNKS_BEHIND
	while not _chunks.is_empty() and _first_index < cull_before:
		var spent: RunnerChunk = _chunks.pop_front()
		_free_chunk(spent)
		_first_index += 1


## Deck height at a given z. The deck is deliberately dead flat in v1: the
## jump arc, the bar clearance and the slide window are all tuned against a
## y = 0 floor, and elevation would put all three back in play for a feature
## the mode does not need yet. Kept as a function so adding rolling terrain
## later is a one-body change with no call-site churn.
func floor_y_at(_z: float) -> float:
	return 0.0


## Which biome band a world z falls in. Public so the mode's environment -- sky,
## sun and fog, all owned by RunnerGame -- can follow the track's look instead
## of staying on one setting while the ground changes underneath it.
func biome_at_z(z: float) -> int:
	return _biome_for(_chunk_index_at(z))


## Sky/sun/fog suggestion for a biome, for whoever owns the environment. Lives
## here beside the deck tints so the two can never drift apart.
static func biome_environment(biome: int) -> Dictionary:
	match biome:
		Biome.DUSK:
			return {
				"sky_top": Color(0.16, 0.16, 0.44),
				"sky_horizon": Color(1.0, 0.62, 0.42),
				"sun": Color(1.0, 0.74, 0.52),
				"sun_energy": 1.15,
				"fog": Color(0.72, 0.48, 0.52),
				"ambient": 0.62,
			}
		Biome.CAVE:
			return {
				"sky_top": Color(0.03, 0.10, 0.20),
				"sky_horizon": Color(0.24, 0.52, 0.70),
				"sun": Color(0.72, 0.88, 1.0),
				"sun_energy": 0.72,
				"fog": Color(0.22, 0.42, 0.60),
				"ambient": 0.52,
			}
		Biome.NIGHT:
			return {
				"sky_top": Color(0.02, 0.04, 0.14),
				"sky_horizon": Color(0.10, 0.22, 0.44),
				"sun": Color(0.66, 0.78, 1.0),
				"sun_energy": 0.55,
				"fog": Color(0.10, 0.20, 0.40),
				"ambient": 0.46,
			}
		_:
			return {
				"sky_top": Color(0.06, 0.26, 0.68),
				"sky_horizon": Color(0.66, 0.83, 0.98),
				"sun": Color(1.0, 0.95, 0.86),
				"sun_energy": 1.32,
				"fog": Color(0.5, 0.66, 0.86),
				"ambient": 0.74,
			}


## --- Streaming --------------------------------------------------------------

## Chunk containing a world z. Chunk i owns z in (-(i+1)*L, -i*L].
func _chunk_index_at(z: float) -> int:
	return int(floor(-z / RunnerConfig.CHUNK_LENGTH))


func _biome_for(index: int) -> int:
	var band := int(floor(float(index) * RunnerConfig.CHUNK_LENGTH / BIOME_LENGTH))
	return posmod(band, BIOME_COUNT)


func _clear() -> void:
	for chunk: RunnerChunk in _chunks:
		_free_chunk(chunk)
	_chunks.clear()
	_first_index = 0
	_next_index = 0
	_last_pattern = -1
	_tunnel_left = 0
	_powerup_cursor = 0
	_next_powerup_z = -POWERUP_FIRST
	_air_from_z = 1.0e9
	_air_to_z = 1.0e9
	# Positive infinity-ish sentinel: the run only ever moves to negative z, so
	# "no obstacle of this kind yet" is a value no real gap check can match.
	_lane_jump_z = PackedFloat32Array()
	_lane_slide_z = PackedFloat32Array()
	for i: int in RunnerConfig.LANE_COUNT:
		_lane_jump_z.append(1.0e9)
		_lane_slide_z.append(1.0e9)


## Detaches before freeing. queue_free() alone leaves the node in the tree for
## the rest of the frame, which on reset() would overlap the old chunk 0 with
## the new one -- and leave its hazards visible to a group query.
func _free_chunk(chunk: RunnerChunk) -> void:
	if not is_instance_valid(chunk):
		return
	if chunk.get_parent() == self:
		remove_child(chunk)
	chunk.queue_free()


func _spawn_chunk(index: int, difficulty: float) -> void:
	var chunk := RunnerChunk.new()
	chunk.name = "Chunk%d" % index
	chunk.index = index
	chunk.difficulty = difficulty
	chunk.biome = _biome_for(index)
	chunk.position = Vector3(0.0, 0.0, -float(index) * RunnerConfig.CHUNK_LENGTH)
	add_child(chunk)
	# Seeded from (run seed, chunk index) rather than from a rolling stream, so
	# a chunk is identical however the streaming happened to be scheduled --
	# which is what makes a seeded run reproducible in a test.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 1000003 + index * 7919 + 11
	# The pattern is chosen before the geometry because the deck and the roof
	# depend on it: a tunnel darkens its own floor.
	var pattern := _pick_pattern(rng, difficulty, index)
	if not _headless:
		_build_deck(chunk, pattern)
		_build_dressing(chunk, rng)
		if pattern == Pattern.TUNNEL:
			_build_tunnel(chunk)
	_run_pattern(pattern, chunk, rng, difficulty)
	_last_pattern = pattern
	# Crates go in last, so the placement can see every obstacle the pattern
	# actually managed to build rather than the ones it asked for.
	if index >= WARMUP_CHUNKS:
		_maybe_add_powerup(chunk, rng)
	chunk.finish(_headless)
	_chunks.append(chunk)
	_next_index = index + 1


## --- Patterns ---------------------------------------------------------------

func _pick_pattern(rng: RandomNumberGenerator, difficulty: float, index: int) -> int:
	if index < WARMUP_CHUNKS:
		return Pattern.OPEN
	# A tunnel that owes another chunk takes it before anything is rolled.
	if _tunnel_left > 0:
		_tunnel_left -= 1
		return Pattern.TUNNEL
	# Indexed by Pattern value. Weights that start negative stay clamped at
	# zero until difficulty crosses their gate, which is how MIXED_GAUNTLET and
	# PINCH stay out of the first minute of a run entirely.
	var weights := PackedFloat32Array()
	weights.append(lerpf(2.2, 0.5, difficulty))             # OPEN
	weights.append(lerpf(1.7, 2.4, difficulty))             # LANE_WEAVE
	weights.append(lerpf(0.9, 2.0, difficulty))             # SLIDE_GALLERY
	weights.append(lerpf(1.4, 2.0, difficulty))             # JUMP_STUTTER
	weights.append(lerpf(1.4, 0.7, difficulty))             # FISH_ARC
	weights.append(maxf(0.0, lerpf(-1.4, 2.6, difficulty))) # MIXED_GAUNTLET
	weights.append(maxf(0.0, lerpf(-1.1, 2.0, difficulty))) # PINCH
	weights.append(lerpf(1.0, 2.2, difficulty))             # SEAL_SLIDE
	weights.append(lerpf(0.6, 1.6, difficulty))             # TUNNEL
	weights.append(lerpf(1.3, 1.4, difficulty))             # RAMP_RUN
	# The ice cave is where overhead architecture belongs and the aurora night
	# is where the sky is the show, so the tunnel weight follows the biome.
	# Same patterns everywhere, different mix -- the run stays learnable while
	# still feeling like it went somewhere.
	match _biome_for(index):
		Biome.CAVE:
			weights[Pattern.TUNNEL] *= 2.6
		Biome.NIGHT:
			weights[Pattern.TUNNEL] *= 0.4
			weights[Pattern.RAMP_RUN] *= 1.4
	# Back-to-back repeats are what make a streamed course feel generated, so
	# the last pattern is heavily discouraged rather than banned (banning it
	# would make OPEN impossible to repeat during the calm early run).
	if _last_pattern >= 0 and _last_pattern < weights.size():
		weights[_last_pattern] *= 0.2
	var total := 0.0
	for w: float in weights:
		total += w
	if total <= 0.0:
		return Pattern.OPEN
	var roll := rng.randf() * total
	for i: int in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			if i == Pattern.TUNNEL:
				_tunnel_left = 1 if rng.randf() < 0.55 else 0
			return i
	return Pattern.OPEN


func _run_pattern(pattern: int, chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	match pattern:
		Pattern.LANE_WEAVE:
			_pattern_lane_weave(chunk, rng, difficulty)
		Pattern.SLIDE_GALLERY:
			_pattern_slide_gallery(chunk, rng, difficulty)
		Pattern.JUMP_STUTTER:
			_pattern_jump_stutter(chunk, rng, difficulty)
		Pattern.FISH_ARC:
			_pattern_fish_arc(chunk, rng, difficulty)
		Pattern.MIXED_GAUNTLET:
			_pattern_mixed_gauntlet(chunk, rng, difficulty)
		Pattern.PINCH:
			_pattern_pinch(chunk, rng, difficulty)
		Pattern.SEAL_SLIDE:
			_pattern_seal_slide(chunk, rng, difficulty)
		Pattern.TUNNEL:
			_pattern_tunnel(chunk, rng, difficulty)
		Pattern.RAMP_RUN:
			_pattern_ramp_run(chunk, rng, difficulty)
		_:
			_pattern_open(chunk, rng, difficulty)


## Local z of each obstacle row in a chunk, front (nearest the player) first.
func _row_positions(difficulty: float) -> PackedFloat32Array:
	var gap := lerpf(ROW_GAP_EASY, ROW_GAP_HARD, difficulty)
	var rows := PackedFloat32Array()
	var z := -CHUNK_EDGE_MARGIN
	while z > -(RunnerConfig.CHUNK_LENGTH - CHUNK_EDGE_MARGIN):
		rows.append(z)
		z -= gap
	return rows


## Breathing room. Not empty, though: a chunk with literally nothing in it is
## where a runner stops being a game for two seconds, so an OPEN chunk still
## carries a fish line that crosses a lane boundary and -- once the warm-up is
## over -- usually one shin-high ridge to hop.
func _pattern_open(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var lane_a := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
	var lane_b := lane_a
	if rng.randf() < 0.6:
		lane_b = clampi(lane_a + (1 if rng.randf() < 0.5 else -1), 0, RunnerConfig.LANE_COUNT - 1)
	if lane_b == lane_a:
		_fish_line(chunk, lane_a, -3.0, -RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)
	else:
		_fish_line(chunk, lane_a, -3.0, -RunnerConfig.CHUNK_LENGTH * 0.42, FISH_Y)
		_fish_sweep(chunk, lane_a, lane_b, -RunnerConfig.CHUNK_LENGTH * 0.45,
				-RunnerConfig.CHUNK_LENGTH * 0.62, 4, FISH_Y)
		_fish_line(chunk, lane_b, -RunnerConfig.CHUNK_LENGTH * 0.66,
				-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)
	if chunk.index < WARMUP_CHUNKS:
		return
	if rng.randf() < lerpf(0.6, 0.8, difficulty):
		var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
		var z := -RunnerConfig.CHUNK_LENGTH * rng.randf_range(0.3, 0.66)
		if _add_obstacle(chunk, Kind.LOW, lane, 1, z):
			_fish_arc(chunk, lane, z, 5.0)


## Rows of solid blocks whose open lane moves row to row. The fish deliberately
## mark the survivable lane: at speed the pickup line is a faster read than the
## obstacles themselves, so it doubles as the pattern's signposting.
func _pattern_lane_weave(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	var prev_z := -1.0
	for i: int in rows.size():
		var z := rows[i]
		# Two blocked lanes is a much harder read than one, so it stays a
		# difficulty-gated minority even late in a run.
		var blocked := 2 if rng.randf() < difficulty * 0.55 else 1
		var open_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
		var placed := 0
		for lane: int in RunnerConfig.LANE_COUNT:
			if lane == open_lane or placed >= blocked:
				continue
			_add_obstacle(chunk, Kind.BLOCK, lane, 1, z)
			placed += 1
		_fish_line(chunk, open_lane, prev_z, z - 2.0, FISH_Y)
		prev_z = z + 2.0
	if not rows.is_empty():
		_fish_line(chunk, rng.randi_range(0, RunnerConfig.LANE_COUNT - 1),
				rows[rows.size() - 1] - 3.0, -RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)


## Consecutive ice arches. Fish sit low under each one so the slide is paid for
## rather than merely survived, which is what stops players from sliding early
## and holding it.
func _pattern_slide_gallery(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
	for i: int in rows.size():
		var z := rows[i]
		if not _add_obstacle(chunk, Kind.BAR, 0, RunnerConfig.LANE_COUNT, z):
			continue
		# Low enough that a sliding penguin sweeps them up and a standing one
		# would have hit the arch anyway.
		_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.42, z))
		_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.42, z - 2.4))
		if i + 1 < rows.size():
			_fish_line(chunk, lane, z - 5.0, rows[i + 1] + 3.0, FISH_Y)
		lane = clampi(lane + rng.randi_range(-1, 1), 0, RunnerConfig.LANE_COUNT - 1)


## Staggered shin-high ridges with a fish arc over each: the arc is the timing
## cue, since a ridge low enough to jump is also low enough to lose against
## white snow at distance. The deck chevrons _add_deck_marks() paints in front
## of each one are the other half of that fix.
func _pattern_jump_stutter(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	for i: int in rows.size():
		var z := rows[i]
		var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
		# A wide ridge late in the run removes the "sidestep instead of jump"
		# escape, which is the whole point of the pattern.
		var span := 2 if rng.randf() < difficulty * 0.7 else 1
		if lane + span > RunnerConfig.LANE_COUNT:
			lane = RunnerConfig.LANE_COUNT - span
		if _add_obstacle(chunk, Kind.LOW, lane, span, z):
			_fish_arc(chunk, lane, z, 5.0)
		var free_lane := (lane + span) % RunnerConfig.LANE_COUNT
		if i + 1 < rows.size():
			_fish_line(chunk, free_lane, z - 4.5, rows[i + 1] + 3.0, FISH_Y)


## Reward chunk. A long sweeping fish line that crosses every lane, plus one
## jumpable ridge with an arc over it -- the pacing beat that makes the
## gauntlet chunks feel like gauntlets.
func _pattern_fish_arc(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var lane_a := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
	var lane_b := RunnerConfig.LANE_COUNT - 1 - lane_a
	if lane_a == lane_b:
		lane_b = (lane_a + 1) % RunnerConfig.LANE_COUNT
	var mid := -RunnerConfig.CHUNK_LENGTH * 0.5
	_fish_line(chunk, lane_a, -3.0, mid + 7.0, FISH_Y)
	_fish_sweep(chunk, lane_a, lane_b, mid + 6.0, mid - 6.0, 6, FISH_Y)
	_fish_line(chunk, lane_b, mid - 7.0, -RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)
	if difficulty > 0.15:
		var z := mid - 10.0
		if _add_obstacle(chunk, Kind.LOW, lane_b, 1, z):
			_fish_arc(chunk, lane_b, z, 5.5)


## Block row, arch, ridge row in sequence: the pattern that asks for all three
## verbs inside one chunk. Late-run only, and every placement still goes through
## _can_place(), so the arch is silently dropped when a ridge left the lane
## un-slideable.
func _pattern_mixed_gauntlet(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	for i: int in rows.size():
		var z := rows[i]
		match i % 3:
			0:
				var open_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
				for lane: int in RunnerConfig.LANE_COUNT:
					if lane != open_lane:
						_add_obstacle(chunk, Kind.BLOCK, lane, 1, z)
				_fish_line(chunk, open_lane, z + 2.5, z - 4.0, FISH_Y)
			1:
				if _add_obstacle(chunk, Kind.BAR, 0, RunnerConfig.LANE_COUNT, z):
					var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
					_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.42, z))
			_:
				var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
				if _add_obstacle(chunk, Kind.LOW, lane, 1, z):
					_fish_arc(chunk, lane, z, 5.0)


## Two lanes walled off, one thread of survivable track that shifts under the
## player. The hardest thing the streamer will build, hence the difficulty gate
## on its weight.
func _pattern_pinch(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	var open_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
	var prev_z := -1.0
	for i: int in rows.size():
		var z := rows[i]
		for lane: int in RunnerConfig.LANE_COUNT:
			if lane != open_lane:
				_add_obstacle(chunk, Kind.BLOCK, lane, 1, z)
		_fish_line(chunk, open_lane, prev_z, z - 2.0, FISH_Y)
		prev_z = z + 2.0
		# Never more than one lane of travel between rows: a pinch that jumps
		# from lane 0 to lane 2 is not a reaction test, it is a coin flip.
		open_lane = clampi(open_lane + (1 if rng.randf() < 0.5 else -1),
				0, RunnerConfig.LANE_COUNT - 1)
	_fish_line(chunk, open_lane, prev_z, -RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)


## Seals crossing the deck. The single biggest difference between a runner that
## feels alive and one that feels like a corridor of furniture: a static
## obstacle is a puzzle you solve once at 60 m, a moving one has to be re-read
## the whole way in.
##
## Fair by construction rather than by check: one seal owns one Z band, and a
## band is one seal wide, so however the sweeps line up there are always two
## clear lanes at any point on the track. A "train" is a diagonal of two or
## three seals in consecutive bands with a phase step, which reads as a line of
## animals following each other and asks the player to keep moving one way.
func _pattern_seal_slide(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	var period := lerpf(SEAL_PERIOD_EASY, SEAL_PERIOD_HARD, difficulty)
	var i := 0
	while i < rows.size():
		# A train needs bands to spare, and only turns up once the player has
		# met a single seal a few times.
		var train := 1
		if rows.size() - i >= 2 and rng.randf() < lerpf(0.25, 0.7, difficulty):
			train = mini(rows.size() - i, 2 if rng.randf() < 0.6 else 3)
		var phase := rng.randf() * TAU
		# A train steps its phase so the seals sit on a diagonal instead of
		# swimming in lockstep, which is what makes it read as a line.
		var step := (1.0 if rng.randf() < 0.5 else -1.0) * 0.72
		for t: int in train:
			_add_seal(chunk, rows[i + t] - float(t) * 1.5, phase + float(t) * step, period)
		# Fish behind the train, in the lane the leader is furthest from: the
		# reward for reading the sweep is a clean line through it.
		var safe_lane := 0 if sin(phase) > 0.0 else RunnerConfig.LANE_COUNT - 1
		var z_from := rows[i + train - 1] - 4.0
		var z_to := -RunnerConfig.CHUNK_LENGTH + 3.0
		if i + train < rows.size():
			z_to = rows[i + train] + 3.0
		_fish_line(chunk, safe_lane, z_from, z_to, FISH_Y)
		i += train


## Inside the ice arch tunnel. The roof is dressing -- it never collides -- and
## the gameplay is bars hung under it, because the one thing an enclosed space
## can do that open track cannot is make the ceiling matter.
func _pattern_tunnel(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var rows := _row_positions(difficulty)
	var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
	for i: int in rows.size():
		var z := rows[i]
		# Alternating verbs: an arch you slide, then a ridge you jump. Two
		# slides in a row inside a dim tunnel is where the mode stops being
		# readable, and _can_place() would refuse the pairing anyway.
		if i % 2 == 0:
			if _add_obstacle(chunk, Kind.BAR, 0, RunnerConfig.LANE_COUNT, z):
				_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.42, z))
				_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.42, z - 2.2))
		else:
			if _add_obstacle(chunk, Kind.LOW, lane, 1, z):
				_fish_arc(chunk, lane, z, 4.6)
		if i + 1 < rows.size():
			_fish_line(chunk, lane, z - 5.0, rows[i + 1] + 3.0, FISH_Y)
		lane = clampi(lane + rng.randi_range(-1, 1), 0, RunnerConfig.LANE_COUNT - 1)


## The showpiece. A wedge of packed snow, a fish arc hanging in the air over
## the flight path so the reward is visible before the ramp is even reached,
## and a launch corridor nothing else is allowed to build in.
func _pattern_ramp_run(chunk: RunnerChunk, rng: RandomNumberGenerator, difficulty: float) -> void:
	var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
	var z := -RunnerConfig.CHUNK_LENGTH * rng.randf_range(0.22, 0.38)
	# Fish on the run-in, so the ramp is something the player is already
	# travelling toward rather than something they swerve into.
	_fish_line(chunk, lane, -2.5, z - RAMP_DEPTH * 0.5 - 1.0, FISH_Y)
	if not _add_obstacle(chunk, Kind.RAMP, lane, 1, z):
		# Refused (almost always because another ramp's corridor is still
		# open): fall back to the reward chunk rather than leaving dead track.
		_pattern_fish_arc(chunk, rng, difficulty)
		return
	_ramp_air_fish(chunk, lane, z - RAMP_DEPTH * 0.5, difficulty)
	# The side lanes get a consolation line at run height for anyone who missed
	# the ramp, so not launching is not the same as being punished.
	_fish_line(chunk, (lane + 1) % RunnerConfig.LANE_COUNT, z - RAMP_DEPTH,
			-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)


## --- Obstacles --------------------------------------------------------------

## True when this kind may go in these lanes at this z. Bars demand a slide and
## ridges demand a jump; committing to either takes long enough at speed that
## the other one arriving too soon is unsurvivable however well the player
## plays, so the placement is refused instead.
func _can_place(kind: int, lane: int, span: int, world_z: float, difficulty: float) -> bool:
	if kind == Kind.RAMP:
		# Two ramps whose arcs overlap means being launched out of a launch.
		return world_z > _air_from_z or world_z < _air_to_z
	# Nothing at all inside a launch corridor. A penguin mid-arc has no input
	# that matters, so anything in there is a hit it could not have avoided.
	if _in_air_corridor(world_z):
		return false
	if kind != Kind.BAR and kind != Kind.LOW:
		return true
	var gap := lerpf(KIND_GAP_EASY, KIND_GAP_HARD, difficulty)
	for i: int in span:
		var l := lane + i
		if l < 0 or l >= RunnerConfig.LANE_COUNT:
			continue
		var other := _lane_jump_z[l] if kind == Kind.BAR else _lane_slide_z[l]
		if absf(world_z - other) < gap:
			return false
	return true


func _in_air_corridor(world_z: float) -> bool:
	return world_z <= _air_from_z and world_z >= _air_to_z


func _note_placement(kind: int, lane: int, span: int, world_z: float) -> void:
	for i: int in span:
		var l := lane + i
		if l < 0 or l >= RunnerConfig.LANE_COUNT:
			continue
		if kind == Kind.LOW:
			_lane_jump_z[l] = world_z
		elif kind == Kind.BAR:
			_lane_slide_z[l] = world_z


## Adds one obstacle and returns whether it was actually placed. Callers use the
## result to decide whether to lay the fish that would have signposted it.
##
## Blocks are single-lane by contract -- the "at least one survivable lane"
## guarantee is enforced here rather than trusted to every pattern, by refusing
## a block that would be the last free lane in the row.
func _add_obstacle(chunk: RunnerChunk, kind: int, lane: int, span: int, local_z: float) -> bool:
	if kind == Kind.NONE:
		return false
	span = clampi(span, 1, RunnerConfig.LANE_COUNT)
	lane = clampi(lane, 0, RunnerConfig.LANE_COUNT - span)
	var world_z := chunk.position.z + local_z
	var difficulty := chunk.difficulty
	if not _can_place(kind, lane, span, world_z, difficulty):
		return false
	if kind == Kind.BLOCK and chunk.row_blocked_lanes(local_z) + span >= RunnerConfig.LANE_COUNT:
		return false
	var area := Area3D.new()
	area.collision_layer = HAZARD_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.add_to_group(RunnerConfig.GROUP_HAZARD)
	area.set_meta("kind", KIND_NAMES[kind])
	area.set_meta("lane", lane)
	area.set_meta("span", span)
	var centre_x := (RunnerConfig.lane_x(lane) + RunnerConfig.lane_x(lane + span - 1)) * 0.5
	area.position = Vector3(centre_x, 0.0, local_z)
	var size := Vector3.ZERO
	var centre_y := 0.0
	match kind:
		Kind.BLOCK:
			size = Vector3(BLOCK_WIDTH, BLOCK_HEIGHT, BLOCK_DEPTH)
			centre_y = BLOCK_HEIGHT * 0.5
		Kind.LOW:
			size = Vector3(float(span) * RunnerConfig.LANE_WIDTH - 0.6, LOW_HEIGHT, LOW_DEPTH)
			centre_y = LOW_HEIGHT * 0.5
		Kind.RAMP:
			# Taller than the wedge, so the launch cannot be missed by a
			# penguin that arrives already airborne off an ordinary jump.
			size = Vector3(RAMP_WIDTH, RAMP_HEIGHT + 0.8, RAMP_DEPTH)
			centre_y = (RAMP_HEIGHT + 0.8) * 0.5
		_:
			# The arch always spans the whole deck. A partial bar reads as an
			# arch from 60 m out and only resolves into "slide here, not there"
			# far too late, so the mode never builds one.
			area.position.x = 0.0
			centre_x = 0.0
			size = Vector3(RunnerConfig.DECK_HALF_WIDTH * 2.0, BAR_THICKNESS, BAR_DEPTH)
			centre_y = BAR_CLEARANCE + BAR_THICKNESS * 0.5
	var shape := CollisionShape3D.new()
	shape.shape = _box_shape(size)
	shape.position.y = centre_y
	area.add_child(shape)
	if not _headless:
		var visual := MeshInstance3D.new()
		match kind:
			Kind.BLOCK:
				visual.mesh = _block_mesh()
				visual.rotation.y = fmod(absf(local_z) * 0.7, 0.5) - 0.25
			Kind.LOW:
				visual.mesh = _low_mesh()
				visual.scale.x = size.x
			Kind.RAMP:
				visual.mesh = _ramp_mesh()
			_:
				visual.mesh = _arch_mesh()
		visual.material_override = _prop_material()
		area.add_child(visual)
		# Grounding is not left to the scene's light rig: with no SSAO on
		# gl_compatibility, and no guarantee the runner's sun casts shadows at
		# all, an unshadowed block reads as hovering and its distance becomes
		# unjudgeable. One baked patch per obstacle, all flushed into a single
		# per-chunk MultiMesh.
		if kind != Kind.BAR:
			chunk.contact_patches.append(Transform3D(
					Basis().scaled(Vector3(size.x * 1.6, 1.0, size.z * 2.2)),
					Vector3(centre_x, 0.02, local_z)))
		_add_deck_marks(chunk, kind, centre_x, size.x, local_z)
	chunk.add_child(area)
	chunk.note_row(local_z, kind == Kind.BLOCK, span)
	chunk.note_obstacle(local_z, lane, span)
	_note_placement(kind, lane, span, world_z)
	if kind == Kind.RAMP:
		# Claim the whole flight: airtime times the speed the player will most
		# likely be carrying here, plus a fifth to absorb the error in that
		# estimate. The corridor closing late only costs a few metres of empty
		# track; closing early costs an unavoidable hit.
		var air := 2.0 * RunnerConfig.RAMP_LAUNCH / RunnerConfig.GRAVITY
		_air_from_z = world_z
		_air_to_z = world_z - air * _speed_estimate(difficulty) * 1.2
	return true


## Bright chevrons painted on the deck in front of an obstacle, colour-coded by
## the verb it wants: red-orange dodge, amber jump, cyan slide, green go.
##
## This is the highest-value readability fix in the file. A shin-high ridge is
## genuinely invisible against snow at 50 m, and the obvious answer -- a warning
## post standing over it -- cannot be built, because the jump arc passes
## straight through where the post would be. A decal can be as loud as it likes
## and is never something the player can collide with.
func _add_deck_marks(chunk: RunnerChunk, kind: int, centre_x: float, width: float, local_z: float) -> void:
	# Deep and saturated rather than bright: these are unshaded alpha decals on
	# blown-out snow under an ACES curve, and a "bright" colour comes back out
	# of the tonemapper as pastel. The dark end of each hue is what survives.
	var colour := Color(0.86, 0.13, 0.08)
	match kind:
		Kind.BAR:
			colour = Color(0.06, 0.55, 0.92)
		Kind.LOW:
			colour = Color(0.95, 0.52, 0.02)
		Kind.RAMP:
			colour = Color(0.10, 0.78, 0.26)
		Kind.SEAL:
			colour = Color(0.92, 0.30, 0.03)
	# Capped at a lane and a half. A full-deck bar wants a THRESHOLD, not a
	# carpet: chevrons stretched to the whole 10.8 m deck buried the track under
	# paint and told the player nothing the narrower mark does not.
	var span_x := clampf(width * 0.92, 1.8, 4.6)
	for i: int in 3:
		# Three chevrons fading with distance from the obstacle: a run of them
		# reads as an arrow pointing at the thing and gives the eye a rhythm to
		# time against, where a single mark reads as a stripe that happens to
		# be there. Two was not enough to survive the perspective squash at the
		# 30-60 m range where the read actually has to happen.
		chunk.marks.append(Transform3D(
				Basis().scaled(Vector3(span_x, 1.0, 2.4)),
				Vector3(centre_x, 0.03, local_z + 2.6 + float(i) * 2.9)))
		chunk.mark_colors.append(Color(colour.r, colour.g, colour.b, 0.94 - float(i) * 0.2))


## A hazard that crosses the lanes. Its own node rather than a row entry,
## because it has to keep moving after the chunk is built -- and moving is the
## entire reason it exists.
func _add_seal(chunk: RunnerChunk, local_z: float, phase: float, period: float) -> bool:
	if _in_air_corridor(chunk.position.z + local_z):
		return false
	var seal := RunnerMover.new()
	seal.collision_layer = HAZARD_LAYER
	seal.collision_mask = 0
	seal.monitoring = false
	seal.monitorable = true
	seal.add_to_group(RunnerConfig.GROUP_HAZARD)
	# "seal" rather than "block": the player's autopilot and any future effect
	# code can tell a thing that moves from a thing that does not, and neither
	# a jump nor a slide is the answer here -- stepping aside is.
	seal.set_meta("kind", KIND_NAMES[Kind.SEAL])
	seal.set_meta("lane", 1)
	seal.set_meta("span", 1)
	seal.sweep = SEAL_SWEEP
	seal.phase = phase
	seal.omega = TAU / maxf(period, 0.5)
	seal.position = Vector3(sin(phase) * SEAL_SWEEP, 0.0, local_z)
	var shape := CollisionShape3D.new()
	# Long in X because it travels in X. A seal presented side-on would be a
	# 1 m obstacle sweeping 6 m, which is unreadable at speed.
	shape.shape = _box_shape(Vector3(SEAL_LENGTH * 0.86, SEAL_HEIGHT, SEAL_GIRTH * 2.1))
	shape.position.y = SEAL_HEIGHT * 0.5
	seal.add_child(shape)
	if not _headless:
		var visual := MeshInstance3D.new()
		visual.mesh = _seal_mesh()
		visual.material_override = _prop_material()
		seal.add_child(visual)
		seal.body = visual
		# Its own contact blob: the chunk's shadow MultiMesh is baked at build
		# time, and a seal is never where it was baked.
		var blob := MeshInstance3D.new()
		blob.mesh = VisualLibrary.contact_patch_mesh()
		blob.material_override = VisualLibrary.contact_shadow_material(0.34)
		blob.scale = Vector3(SEAL_LENGTH * 1.25, 1.0, SEAL_GIRTH * 2.6)
		blob.position.y = 0.03
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seal.add_child(blob)
		# The chevrons span the deck rather than the seal: the warning is
		# "something is crossing here", not "it is currently at this x".
		_add_deck_marks(chunk, Kind.SEAL, 0.0, RunnerConfig.DECK_HALF_WIDTH * 1.5, local_z)
	chunk.add_child(seal)
	chunk.note_obstacle(local_z, 0, RunnerConfig.LANE_COUNT)
	return true


## Run speed the player will PROBABLY be carrying at this difficulty.
## Difficulty is distance/DIFFICULTY_DISTANCE and the speed ramp is in TIME, so
## the two are related by integrating the ramp: distance = START*t + RAMP*t^2/2
## until MAX_SPEED. Inverting that quadratic is what lets a ramp's fish arc be
## laid along the trajectory the player will actually fly, instead of one
## authored for a speed they only briefly have.
static func _speed_estimate(difficulty: float) -> float:
	var dist := clampf(difficulty, 0.0, 1.0) * DIFFICULTY_DISTANCE
	var v0 := RunnerConfig.START_SPEED
	var t := (sqrt(v0 * v0 + 2.0 * RunnerConfig.SPEED_RAMP * dist) - v0) / RunnerConfig.SPEED_RAMP
	return RunnerConfig.speed_at(t)


## --- Pickups ----------------------------------------------------------------

func _add_fish(chunk: RunnerChunk, local_pos: Vector3) -> void:
	var fish := RunnerFish.new()
	# Clamped rather than trusted. Sweeps and arcs move fish in X and Y at build
	# time and the magnet does at run time; a fish buried in a kerb wall or sunk
	# into the deck is the defect a player sees before any of the good work here.
	var limit := RunnerConfig.DECK_HALF_WIDTH - FISH_WALL_MARGIN
	fish.position = Vector3(clampf(local_pos.x, -limit, limit),
			maxf(local_pos.y, 0.36), local_pos.z)
	fish.collision_layer = HAZARD_LAYER
	fish.collision_mask = 0
	fish.monitoring = false
	fish.monitorable = true
	fish.add_to_group(RunnerConfig.GROUP_PICKUP)
	var shape := CollisionShape3D.new()
	shape.shape = _sphere_shape(FISH_RADIUS)
	fish.add_child(shape)
	chunk.add_child(fish)
	fish.chunk = chunk
	fish.mm_index = chunk.reserve_fish_slot(fish, fish.position)


## Fish every FISH_SPACING metres down one lane, from z_from toward z_to (both
## local, both negative-going). Silently does nothing when the span is too
## short, so patterns can hand it degenerate gaps without guarding.
func _fish_line(chunk: RunnerChunk, lane: int, z_from: float, z_to: float, y: float) -> void:
	if z_from <= z_to:
		return
	var x := RunnerConfig.lane_x(clampi(lane, 0, RunnerConfig.LANE_COUNT - 1))
	var z := z_from
	while z > z_to:
		_add_fish(chunk, Vector3(x, y, z))
		z -= FISH_SPACING


## Fish following the jump arc over a jumpable obstacle: apex over the ridge,
## tails down to run height either side.
func _fish_arc(chunk: RunnerChunk, lane: int, z_centre: float, half_length: float) -> void:
	var x := RunnerConfig.lane_x(clampi(lane, 0, RunnerConfig.LANE_COUNT - 1))
	for i: int in 5:
		var t := (float(i) / 2.0) - 1.0
		var y := lerpf(FISH_ARC_APEX, FISH_Y, t * t)
		_add_fish(chunk, Vector3(x, y, z_centre - t * half_length))


## Fish hung along the trajectory a RAMP throws the player down. Sampled from
## the real ballistic path rather than drawn as a decorative curve: the whole
## promise of a ramp is "follow the fish and you will fly through every one of
## them", and a curve that merely looks right is a curve the player sails past.
##
## Offset to the capsule centre rather than the feet, because collection tests
## the hitbox -- which sits half a penguin above the position the arc solves for.
func _ramp_air_fish(chunk: RunnerChunk, lane: int, lip_z: float, difficulty: float) -> void:
	var x := RunnerConfig.lane_x(clampi(lane, 0, RunnerConfig.LANE_COUNT - 1))
	var speed := _speed_estimate(difficulty)
	var air := 2.0 * RunnerConfig.RAMP_LAUNCH / RunnerConfig.GRAVITY
	var count := 9
	for i: int in count:
		# Stops at 82% of the flight: the last stretch of the arc comes back
		# down through head height, which is where the next chunk lives.
		var t := air * lerpf(0.06, 0.82, float(i) / float(count - 1))
		var y := RunnerConfig.RAMP_LAUNCH * t - 0.5 * RunnerConfig.GRAVITY * t * t
		_add_fish(chunk, Vector3(x, y + RunnerConfig.STAND_HEIGHT * 0.5, lip_z - speed * t))


## Fish crossing from one lane to another on a smoothstep, so the line curves
## the way the player's lane change actually does instead of stepping sideways.
func _fish_sweep(chunk: RunnerChunk, lane_from: int, lane_to: int, z_from: float,
		z_to: float, count: int, y: float) -> void:
	if count <= 1:
		return
	var x0 := RunnerConfig.lane_x(clampi(lane_from, 0, RunnerConfig.LANE_COUNT - 1))
	var x1 := RunnerConfig.lane_x(clampi(lane_to, 0, RunnerConfig.LANE_COUNT - 1))
	for i: int in count:
		var t := float(i) / float(count - 1)
		_add_fish(chunk, Vector3(lerpf(x0, x1, smoothstep(0.0, 1.0, t)), y, lerpf(z_from, z_to, t)))


## --- Power-ups --------------------------------------------------------------

## Drops a crate when the run has travelled far enough since the last one, in a
## lane and at a z clear of everything this chunk built. Refuses rather than
## compromises: a crate the player has to eat a block to reach is worse than no
## crate at all, and the next chunk is only 36 m away.
func _maybe_add_powerup(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	if _next_powerup_z < chunk.position.z - RunnerConfig.CHUNK_LENGTH:
		return
	var lane_order: Array[int] = [1, 0, 2]
	lane_order.shuffle()
	# Start from where the crate is due and walk down-track from there, so a
	# refusal slides the crate a few metres rather than a few hundred.
	var start := clampf(chunk.position.z - _next_powerup_z, 4.0, RunnerConfig.CHUNK_LENGTH - 10.0)
	for attempt: int in 8:
		var local_z := -fmod(start + float(attempt) * 3.5, RunnerConfig.CHUNK_LENGTH - 8.0) - 4.0
		if _in_air_corridor(chunk.position.z + local_z):
			continue
		for lane: int in lane_order:
			if not chunk.lane_clear(local_z, lane, POWERUP_CLEARANCE):
				continue
			_add_powerup(chunk, lane, local_z, RunnerConfig.POWERUP_IDS[
					_powerup_cursor % RunnerConfig.POWERUP_IDS.size()])
			_powerup_cursor += 1
			_next_powerup_z = chunk.position.z + local_z \
					- rng.randf_range(POWERUP_GAP_MIN, POWERUP_GAP_MAX)
			return


func _add_powerup(chunk: RunnerChunk, lane: int, local_z: float, id: StringName) -> void:
	var crate := RunnerPowerup.new()
	crate.id = id
	crate.collision_layer = HAZARD_LAYER
	crate.collision_mask = 0
	crate.monitoring = false
	crate.monitorable = true
	crate.add_to_group(RunnerConfig.GROUP_POWERUP)
	crate.set_meta("powerup", id)
	crate.position = Vector3(RunnerConfig.lane_x(lane), POWERUP_Y, local_z)
	var shape := CollisionShape3D.new()
	shape.shape = _sphere_shape(POWERUP_RADIUS)
	crate.add_child(shape)
	if not _headless:
		var visual := MeshInstance3D.new()
		visual.mesh = _crate_mesh(id)
		# Emissive rather than vertex-coloured, and one cached material per id:
		# a crate has to be identifiable at 60 m on a white deck under a white
		# sky, where shape is a blur and the colour is doing all the work -- so
		# it has to glow rather than depend on how the sun happens to rake it.
		var tint := _powerup_colour(id)
		visual.material_override = VisualLibrary.emissive_material(tint, tint, 1.5, 0.34)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crate.add_child(visual)
		crate.body = visual
		var blob := MeshInstance3D.new()
		blob.mesh = VisualLibrary.contact_patch_mesh()
		blob.material_override = VisualLibrary.contact_shadow_material(0.3)
		blob.scale = Vector3(2.0, 1.0, 2.0)
		blob.position.y = -POWERUP_Y + 0.03
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crate.add_child(blob)
	chunk.add_child(crate)


static func _powerup_colour(id: StringName) -> Color:
	match id:
		RunnerConfig.POWERUP_SHIELD:
			return Color(0.32, 0.86, 1.0)
		RunnerConfig.POWERUP_DOUBLE:
			return Color(1.0, 0.79, 0.20)
		_:
			return Color(0.78, 0.40, 1.0)


## --- Chunk geometry ---------------------------------------------------------

## Deck, lane seams and the kerb/drop-off verge. Three shared meshes, three
## shared materials, three nodes: this is the entire static cost of a chunk.
## The materials come out of a fixed per-biome palette, so however long the run
## gets the process only ever mints four of each.
func _build_deck(chunk: RunnerChunk, pattern: int) -> void:
	var biome := chunk.biome
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	deck.mesh = _deck_mesh()
	# A tunnel darkens its own floor. This is the cheapest honest "the light
	# changed" available: no extra lights, no environment write, and it is the
	# surface the player is actually looking at.
	var deck_tint := _biome_deck_tint(biome)
	if pattern == Pattern.TUNNEL:
		deck_tint = deck_tint * Color(0.48, 0.56, 0.72, 1.0)
	deck.material_override = VisualLibrary.snow_material(deck_tint, 0.5, -1.0, 1.0)
	deck.position = Vector3(0.0, 0.0, -RunnerConfig.CHUNK_LENGTH * 0.5)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(deck)
	# Lane seams: a flat white deck gives the player nothing to judge a lane
	# change against, and no amount of obstacle readability fixes that. Faintly
	# emissive so they survive both the bright day bands and the aurora night.
	var seams := MeshInstance3D.new()
	seams.name = "Seams"
	seams.mesh = _seam_mesh()
	seams.material_override = VisualLibrary.emissive_material(
			_biome_seam_tint(biome), _biome_seam_glow(biome), 0.45, 0.7)
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(seams)
	var verge := MeshInstance3D.new()
	verge.name = "Verge"
	verge.mesh = _verge_mesh()
	verge.set_surface_override_material(0, VisualLibrary.ice_material(_biome_ice_tint(biome), 0.5))
	verge.set_surface_override_material(1,
			VisualLibrary.snow_material(deck_tint * Color(0.86, 0.9, 1.0, 1.0), 0.3))
	verge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(verge)


## Pushed further apart than "tasteful" would suggest. These tints are the only
## thing carrying a biome change on their own: the sky and the sun belong to
## RunnerGame, and until it follows biome_environment() a gentle tint is
## invisible at 38 m/s. A band the player does not notice is not a band.
static func _biome_deck_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.80, 0.70)
		Biome.CAVE:
			return Color(0.44, 0.62, 0.90)
		Biome.NIGHT:
			return Color(0.44, 0.54, 0.88)
		_:
			return Color(0.94, 0.965, 1.0)


static func _biome_ice_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(0.96, 0.50, 0.54)
		Biome.CAVE:
			return Color(0.22, 0.58, 0.92)
		Biome.NIGHT:
			return Color(0.24, 0.40, 0.84)
		_:
			return Color(0.60, 0.83, 0.98)


static func _biome_seam_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.78, 0.52)
		Biome.CAVE:
			return Color(0.52, 0.90, 1.0)
		Biome.NIGHT:
			return Color(0.46, 1.0, 0.82)
		_:
			return Color(0.62, 0.78, 0.95)


static func _biome_seam_glow(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.55, 0.24)
		Biome.CAVE:
			return Color(0.28, 0.80, 1.0)
		Biome.NIGHT:
			return Color(0.24, 1.0, 0.70)
		_:
			return Color(0.36, 0.62, 0.92)


## Everything beyond the drop-off. All MultiMesh, all shadowless, all distance
## faded: it exists to sell speed in peripheral vision and must never cost more
## than a handful of draw calls per chunk.
##
## Half of it MOVES. Static dressing at 38 m/s reads as wallpaper on a cylinder;
## a banner that flaps and a shard that tumbles cost one instance-transform
## write each per frame and are the difference between a corridor and a place.
func _build_dressing(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var biome := chunk.biome
	var shelf_y := -SHELF_DROP + 0.45
	var drifts: Array[Transform3D] = []
	for i: int in rng.randi_range(3, 6):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(1.6, 3.8)
		drifts.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.45, 0.85), s)),
				Vector3(side * rng.randf_range(RunnerConfig.DECK_HALF_WIDTH + 3.0, SHELF_WIDTH * 0.8),
						shelf_y, -rng.randf() * RunnerConfig.CHUNK_LENGTH)))
	_add_multimesh(chunk, VisualLibrary.snow_drift_mesh(), drifts,
			VisualLibrary.rock_material(_biome_deck_tint(biome), 0.85), "Drifts", 170.0)
	var crystals: Array[Transform3D] = []
	for i: int in rng.randi_range(2, 5):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(1.1, 2.9)
		crystals.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.8, s, s * 0.8)),
				Vector3(side * rng.randf_range(RunnerConfig.DECK_HALF_WIDTH + 1.4, SHELF_WIDTH * 0.6),
						shelf_y - 0.25, -rng.randf() * RunnerConfig.CHUNK_LENGTH)))
	_add_multimesh(chunk, VisualLibrary.ice_crystal_mesh(), crystals,
			VisualLibrary.rock_material(_biome_ice_tint(biome), 0.25), "Crystals", 170.0)
	# Distant bergs only on some chunks, and only ever ONE seeded silhouette per
	# chunk: berg_mesh() caches per seed, so drawing a fresh seed every chunk
	# would grow that cache without bound over a long run.
	if rng.randf() < (0.28 if biome == Biome.NIGHT else 0.55):
		var bergs: Array[Transform3D] = []
		for i: int in rng.randi_range(1, 3):
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var s := rng.randf_range(5.0, 13.0)
			bergs.append(Transform3D(
					Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.5), s)),
					Vector3(side * rng.randf_range(34.0, 84.0), -SHELF_DROP - 1.5,
							-rng.randf() * RunnerConfig.CHUNK_LENGTH)))
		var variant: int = [101, 211, 331, 449][rng.randi_range(0, 3)]
		_add_multimesh(chunk, VisualLibrary.berg_mesh(variant), bergs,
				VisualLibrary.rock_material(_biome_ice_tint(biome).lerp(Color.WHITE, 0.5), 0.6),
				"Bergs", 900.0)
	_build_banners(chunk, rng)
	_build_debris(chunk, rng)
	if biome == Biome.NIGHT or (biome == Biome.DAY and rng.randf() < 0.5):
		_build_birds(chunk, rng)
	if biome == Biome.NIGHT and rng.randf() < 0.35:
		_build_aurora(chunk, rng)


## Pennants on the kerb crown. The strongest speed cue in the whole scene: they
## are the only dressing close enough to the camera to stream past at full
## parallax, and they flap, so peripheral vision reads motion even on a stretch
## where the deck ahead is empty.
func _build_banners(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var banners: Array[Transform3D] = []
	var x := RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS + 0.35
	var spacing := 9.0
	var z := -rng.randf_range(1.0, spacing)
	while z > -RunnerConfig.CHUNK_LENGTH:
		for side: int in 2:
			var sign_x := -1.0 if side == 0 else 1.0
			var s := rng.randf_range(0.9, 1.15)
			banners.append(Transform3D(
					Basis(Vector3.UP, PI * 0.5 * sign_x).scaled(Vector3(s, s, s)),
					Vector3(sign_x * x, WALL_HEIGHT - 0.1, z)))
		z -= spacing
	chunk.register_anim(_add_multimesh(chunk, _banner_mesh(), banners,
			VisualLibrary.rock_material(Color.WHITE, 0.6), "Banners", 180.0),
			banners, RunnerChunk.ANIM_SWAY)


## Ice shards tumbling on the shelf below the kerb. Off the deck, so they can
## never be mistaken for something to dodge, but in the lower third of frame
## where the eye reads ground speed.
func _build_debris(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var shards: Array[Transform3D] = []
	for i: int in rng.randi_range(4, 8):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(0.35, 0.85)
		shards.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)),
				Vector3(side * rng.randf_range(RunnerConfig.DECK_HALF_WIDTH + 1.2, SHELF_WIDTH * 0.5),
						-SHELF_DROP + rng.randf_range(0.5, 1.6),
						-rng.randf() * RunnerConfig.CHUNK_LENGTH)))
	chunk.register_anim(_add_multimesh(chunk, _shard_mesh(), shards,
			VisualLibrary.rock_material(Color(0.86, 0.94, 1.0), 0.3), "Shards", 150.0),
			shards, RunnerChunk.ANIM_TUMBLE)


## Gulls, high and far. Nothing in the game reacts to them; they exist because
## an empty sky over an empty deck is most of what made the first pass read as
## a test level, and a few specks with a wingbeat fix it for one draw call.
func _build_birds(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var birds: Array[Transform3D] = []
	var flock_x := rng.randf_range(-70.0, 70.0)
	var flock_z := -rng.randf() * RunnerConfig.CHUNK_LENGTH
	for i: int in rng.randi_range(4, 7):
		var s := rng.randf_range(1.6, 2.6)
		birds.append(Transform3D(
				Basis(Vector3.UP, rng.randf_range(-0.4, 0.4)).scaled(Vector3(s, s, s)),
				Vector3(flock_x + rng.randf_range(-9.0, 9.0),
						rng.randf_range(17.0, 30.0),
						flock_z - rng.randf_range(0.0, 22.0))))
	chunk.register_anim(_add_multimesh(chunk, _bird_mesh(), birds,
			VisualLibrary.rock_material(Color(0.24, 0.28, 0.36), 0.9), "Birds", 900.0),
			birds, RunnerChunk.ANIM_FLAP)


## Aurora curtain, far out to one side and high. The material is the racing
## game's aurora shader, which the boot warmup already links -- so a night band
## costs one draw call and no first-sight stall.
func _build_aurora(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var curtain := MeshInstance3D.new()
	curtain.name = "Aurora"
	curtain.mesh = _curtain_mesh()
	# Dimmed and widened from the library default. At full strength a curtain
	# this far out resolves to a small, very bright core, and a bright core on a
	# dark sky is a needle rather than a curtain.
	curtain.material_override = VisualLibrary.shader_variant(VisualLibrary.aurora_material(), {
		"max_alpha": 0.30,
		"intensity": 0.85,
		"band_scale": 2.2,
	})
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var here := Vector3(side * rng.randf_range(70.0, 190.0), rng.randf_range(52.0, 92.0),
			-rng.randf() * RunnerConfig.CHUNK_LENGTH - rng.randf_range(240.0, 480.0))
	curtain.position = here
	# AIMED at the track, not scattered. The ribbon is a flat sheet in its own
	# XY plane, so a curtain 180 m off to the side with an arbitrary yaw is seen
	# edge-on -- which is exactly what the first pass shipped: a bright vertical
	# needle in the sky rather than a curtain. Yawing it to face the corridor is
	# the whole fix.
	curtain.rotation.y = atan2(-here.x, -here.z)
	curtain.scale = Vector3(rng.randf_range(2.4, 3.8), rng.randf_range(1.4, 2.2), 1.0)
	curtain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(curtain)


## Ice arch tunnel over the whole chunk: six shared bays through one MultiMesh,
## plus two cold omni lights. The lights are what make it read as a change of
## PLACE rather than a lid, and two is the whole budget, because
## gl_compatibility pays per light per lit object.
func _build_tunnel(chunk: RunnerChunk) -> void:
	var segments: Array[Transform3D] = []
	var count := int(ceil(RunnerConfig.CHUNK_LENGTH / TUNNEL_SEGMENT))
	for i: int in count:
		segments.append(Transform3D(Basis(), Vector3(0.0, 0.0, -float(i) * TUNNEL_SEGMENT)))
	_add_multimesh(chunk, _tunnel_mesh(), segments, _tunnel_material(), "Tunnel", 260.0)
	for i: int in 2:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(0.46, 0.82, 1.0)
		lamp.light_energy = 2.4
		lamp.omni_range = 21.0
		lamp.omni_attenuation = 1.4
		lamp.shadow_enabled = false
		lamp.position = Vector3(0.0, TUNNEL_APEX - 1.1,
				-RunnerConfig.CHUNK_LENGTH * (0.25 + 0.5 * float(i)))
		chunk.add_child(lamp)


func _add_multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D],
		material: Material, name_hint: String, range_base: float) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = name_hint
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	VisualLibrary.apply_dressing_range(instance, range_base)
	parent.add_child(instance)
	return instance


## --- Shared shapes ----------------------------------------------------------
## Physics shapes are resources, so one BoxShape3D can back every block in the
## run. Keyed by size to the centimetre; the handful of distinct sizes the
## patterns ask for is the whole cache.

static func _box_shape(size: Vector3) -> BoxShape3D:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if _box_shapes.has(key):
		return _box_shapes[key]
	var shape := BoxShape3D.new()
	shape.size = size
	_box_shapes[key] = shape
	return shape


static func _sphere_shape(radius: float) -> SphereShape3D:
	var key := "%.2f" % radius
	if _sphere_shapes.has(key):
		return _sphere_shapes[key]
	var shape := SphereShape3D.new()
	shape.radius = radius
	_sphere_shapes[key] = shape
	return shape


## --- Shared art -------------------------------------------------------------
## Every mesh below is built once per process and reused by every chunk. They
## all bake their shading into vertex colours and share ONE material, because
## the alternative -- a material per prop kind -- is a program link each, paid
## the first time that kind streams into view mid-run.

## Built up front by setup() so a chunk that streams in during play only ever
## allocates nodes.
func _prime_art_cache() -> void:
	_deck_mesh()
	_seam_mesh()
	_verge_mesh()
	_block_mesh()
	_low_mesh()
	_arch_mesh()
	_fish_mesh()
	_ramp_mesh()
	_seal_mesh()
	_tunnel_mesh()
	_mark_mesh()
	_tunnel_material()
	_banner_mesh()
	_bird_mesh()
	_shard_mesh()
	_curtain_mesh()
	for id: StringName in RunnerConfig.POWERUP_IDS:
		_crate_mesh(id)


## Shared vertex-colour material for obstacles, fish and props. rock_material
## multiplies baked vertex colours into the tint, which is how one material can
## carry a dark ice block, a hot-orange fin and a pale ice ridge at once.
static func _prop_material() -> StandardMaterial3D:
	return VisualLibrary.rock_material(Color.WHITE, 0.42)


## Unshaded alpha material for the deck chevrons, reading the MultiMesh's
## per-instance colour. ONE material for every mark of every colour in the
## game: the colour is instance data, so a red "dodge" chevron and a cyan
## "slide" chevron are the same draw call and the same program.
static func _mark_material() -> StandardMaterial3D:
	if _mark_material_cache != null:
		return _mark_material_cache
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Lies a few centimetres over the deck and must never punch a hole in
	# whatever is drawn after it.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_material_cache = mat
	return mat


## Tunnel shell material. Its own cached material -- one for the whole game --
## because a vault is the one surface here that the sun never reaches: it is
## the UNDERSIDE of a roof, so under a directional rig it renders at ambient
## only. The first pass used the shared prop material and the shell came out at
## almost exactly the sky colour, which read as no roof at all. A little
## emission decouples it from the light rig entirely, which is also what makes
## an ice cave look like ice rather than like a hole.
static func _tunnel_material() -> StandardMaterial3D:
	if _tunnel_material_cache != null:
		return _tunnel_material_cache
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.90, 0.96, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.42
	mat.emission_enabled = true
	mat.emission = Color(0.34, 0.56, 0.82)
	# Low enough that the dark ribs stay dark: emission is uniform across the
	# mesh, so anything stronger flattens the band rhythm it exists to protect.
	mat.emission_energy_multiplier = 0.42
	# Double-sided. A vault is a single sheet of geometry that the player is
	# always underneath, and one inverted winding anywhere in it is an invisible
	# roof -- a failure mode with no visible warning until someone screenshots
	# a tunnel and finds the sky through it. Six bays of back faces is a price
	# worth paying to make that class of bug impossible.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tunnel_material_cache = mat
	return mat


static func _deck_mesh() -> PlaneMesh:
	if _deck_mesh_cache != null:
		return _deck_mesh_cache
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(RunnerConfig.DECK_HALF_WIDTH * 2.0, RunnerConfig.CHUNK_LENGTH)
	mesh.orientation = PlaneMesh.FACE_Y
	_deck_mesh_cache = mesh
	return _deck_mesh_cache


static func _seam_mesh() -> ArrayMesh:
	if _seam_mesh_cache != null:
		return _seam_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := RunnerConfig.LANE_WIDTH * 0.06
	var col := Color(1.0, 1.0, 1.0)
	for i: int in RunnerConfig.LANE_COUNT - 1:
		var x := (RunnerConfig.lane_x(i) + RunnerConfig.lane_x(i + 1)) * 0.5
		_quad_out(st,
				Vector3(x - half, 0.012, 0.0),
				Vector3(x + half, 0.012, 0.0),
				Vector3(x + half, 0.012, -RunnerConfig.CHUNK_LENGTH),
				Vector3(x - half, 0.012, -RunnerConfig.CHUNK_LENGTH),
				Vector3.UP, col, col, col, col)
	st.generate_normals()
	_seam_mesh_cache = st.commit()
	return _seam_mesh_cache


## Kerb wall, drop-off face and the snowfield below, both sides, in one mesh.
## Surface 0 is the ice (wall + drop face), surface 1 the snow shelf, so the
## two get their proper materials without a second node.
static func _verge_mesh() -> ArrayMesh:
	if _verge_mesh_cache != null:
		return _verge_mesh_cache
	var mesh := ArrayMesh.new()
	var length := RunnerConfig.CHUNK_LENGTH
	var inner := RunnerConfig.DECK_HALF_WIDTH
	var outer := inner + WALL_THICKNESS
	# Glacial ice reads as depth: pale at the wind-polished crown, saturating
	# toward teal where the body of the ice absorbs the light.
	var crown := Color(0.94, 0.98, 1.0)
	var body := Color(0.52, 0.76, 0.92)
	var deep := Color(0.20, 0.44, 0.60)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var xi := sign_x * inner
		var xo := sign_x * outer
		var facing := Vector3(-sign_x, 0.0, 0.0)
		# Inner face, seen from the deck.
		_quad_out(st, Vector3(xi, 0.0, 0.0), Vector3(xi, WALL_HEIGHT, 0.0),
				Vector3(xi, WALL_HEIGHT, -length), Vector3(xi, 0.0, -length),
				facing, body, crown, crown, body)
		# Crown.
		_quad_out(st, Vector3(xi, WALL_HEIGHT, 0.0), Vector3(xo, WALL_HEIGHT, 0.0),
				Vector3(xo, WALL_HEIGHT, -length), Vector3(xi, WALL_HEIGHT, -length),
				Vector3.UP, crown, crown, crown, crown)
		# Outer face falling away to the shelf: this is the surface that makes
		# the deck read as a raised causeway rather than a painted lane.
		_quad_out(st, Vector3(xo, WALL_HEIGHT, 0.0), Vector3(xo, -SHELF_DROP, 0.0),
				Vector3(xo, -SHELF_DROP, -length), Vector3(xo, WALL_HEIGHT, -length),
				-facing, crown, deep, deep, crown)
	st.generate_normals()
	st.commit(mesh)
	var snow_near := Color(0.86, 0.91, 1.0)
	var snow_far := Color(1.0, 1.0, 1.0)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var xo := sign_x * (RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS)
		var xf := sign_x * SHELF_WIDTH
		_quad_out(st, Vector3(xo, -SHELF_DROP, 0.0), Vector3(xf, -SHELF_DROP + 0.9, 0.0),
				Vector3(xf, -SHELF_DROP + 0.9, -length), Vector3(xo, -SHELF_DROP, -length),
				Vector3.UP, snow_near, snow_far, snow_far, snow_near)
	st.generate_normals()
	st.commit(mesh)
	_verge_mesh_cache = mesh
	return _verge_mesh_cache


## Chipped ice boulder filling one lane. Dark at the foot, bright at the crown:
## on a white deck under a white sky, VALUE is the only silhouette cue that
## survives to 60 m, and a pale ice block would have none.
static func _block_mesh() -> ArrayMesh:
	if _block_mesh_cache != null:
		return _block_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := BLOCK_WIDTH * 0.5
	var hz := BLOCK_DEPTH * 0.5
	var foot := Color(0.17, 0.24, 0.36)
	var mid := Color(0.44, 0.62, 0.80)
	var crown := Color(0.90, 0.97, 1.0)
	# Corner-jittered top ring so the block reads as a calved chunk of ice
	# rather than a placeholder cube. Fixed offsets, not random: one mesh is
	# shared by every block in the run, and the per-instance yaw at spawn is
	# what keeps a row of them from looking cloned.
	var jitter: Array[Vector3] = [
		Vector3(-0.18, 0.06, -0.12), Vector3(0.14, -0.09, -0.2),
		Vector3(0.2, 0.11, 0.15), Vector3(-0.12, -0.05, 0.18),
	]
	var base: Array[Vector3] = [
		Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz),
		Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz),
	]
	var top: Array[Vector3] = []
	for i: int in 4:
		top.append(Vector3(base[i].x * 0.86, BLOCK_HEIGHT, base[i].z * 0.86) + jitter[i])
	for i: int in 4:
		var j := (i + 1) % 4
		var outward := (base[i] + base[j]) * 0.5
		outward.y = 0.0
		if outward.length_squared() < 0.0001:
			outward = Vector3.FORWARD
		_quad_out(st, base[i], base[j], top[j], top[i], outward.normalized(),
				foot, foot, crown, crown)
	_quad_out(st, top[0], top[1], top[2], top[3], Vector3.UP, crown, crown, crown, crown)
	# Warning band around the waist, proud of the flanks by a few centimetres so
	# it never z-fights them: value contrast alone can lose against a bright
	# horizon, so the block also carries a chroma cue no other object here uses.
	var band := Color(1.0, 0.36, 0.26)
	var y0 := BLOCK_HEIGHT * 0.52
	var y1 := BLOCK_HEIGHT * 0.68
	for i: int in 4:
		var j := (i + 1) % 4
		var a := Vector3(base[i].x * 0.93, 0.0, base[i].z * 0.93)
		var b := Vector3(base[j].x * 0.93, 0.0, base[j].z * 0.93)
		var outward := (a + b) * 0.5
		outward.y = 0.0
		if outward.length_squared() < 0.0001:
			outward = Vector3.FORWARD
		outward = outward.normalized()
		var push := outward * 0.05
		_quad_out(st,
				Vector3(a.x + push.x, y0, a.z + push.z),
				Vector3(b.x + push.x, y0, b.z + push.z),
				Vector3(b.x + push.x, y1, b.z + push.z),
				Vector3(a.x + push.x, y1, a.z + push.z),
				outward, band, band, mid, mid)
	st.generate_normals()
	_block_mesh_cache = st.commit()
	return _block_mesh_cache


## Shin-high ice ridge, ONE metre wide so a caller can scale it to any span.
## Wedge-shaped with the ramp facing the player: the shape says "hop me", and
## the bright crown line is what the player actually times the jump against.
##
## The cap is SOLID amber, and the hazard stripes are on the front face where
## they cannot hurt it. The first pass striped the cap itself and it was a
## measurable regression: from 40 m the alternating amber and near-black
## averaged out to a flat olive slab, which is worse than either colour alone
## would have been. Fine detail on the surface the camera sees most obliquely
## does not survive the resolve -- so the top gets the loudest single value in
## the scene, and the pattern goes somewhere it can stay separated.
static func _low_mesh() -> ArrayMesh:
	if _low_mesh_cache != null:
		return _low_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := LOW_DEPTH * 0.5
	var foot := Color(0.14, 0.19, 0.28)
	var crown := Color(1.0, 0.74, 0.18)
	var b0 := Vector3(-0.5, 0.0, -hz)
	var b1 := Vector3(0.5, 0.0, -hz)
	var b2 := Vector3(0.5, 0.0, hz)
	var b3 := Vector3(-0.5, 0.0, hz)
	var t0 := Vector3(-0.44, LOW_HEIGHT, -hz * 0.45)
	var t1 := Vector3(0.44, LOW_HEIGHT, -hz * 0.45)
	var t2 := Vector3(0.44, LOW_HEIGHT, hz * 0.45)
	var t3 := Vector3(-0.44, LOW_HEIGHT, hz * 0.45)
	_quad_out(st, b0, b1, t1, t0, Vector3.FORWARD, foot, foot, crown, crown)
	_quad_out(st, b2, b3, t3, t2, Vector3.BACK, foot, foot, crown, crown)
	_quad_out(st, b1, b2, t2, t1, Vector3.RIGHT, foot, foot, crown, crown)
	_quad_out(st, b3, b0, t0, t3, Vector3.LEFT, foot, foot, crown, crown)
	_quad_out(st, t0, t1, t2, t3, Vector3.UP, crown, crown, crown, crown)
	# Hazard blocks on the face the player is running at, three wide bands with
	# amber between them. Wide enough that they are still three things at 50 m
	# rather than one averaged tone.
	var dark := Color(0.07, 0.08, 0.11)
	for i: int in 3:
		var x0 := lerpf(-0.46, 0.46, float(i * 2) / 5.0)
		var x1 := lerpf(-0.46, 0.46, float(i * 2 + 1) / 5.0)
		_quad_out(st,
				Vector3(x0, 0.02, -hz - 0.03),
				Vector3(x1, 0.02, -hz - 0.03),
				Vector3(x1 * 0.9, LOW_HEIGHT - 0.06, -hz * 0.45 - 0.03),
				Vector3(x0 * 0.9, LOW_HEIGHT - 0.06, -hz * 0.45 - 0.03),
				Vector3.FORWARD, dark, dark, dark, dark)
	# Near-black leading edge along the top front lip. One dark line against the
	# amber cap is what actually defines WHERE the top of the ridge is, and the
	# top edge is the thing the player times a jump against.
	_quad_out(st,
			Vector3(-0.46, LOW_HEIGHT + 0.015, -hz * 0.45 - 0.02),
			Vector3(0.46, LOW_HEIGHT + 0.015, -hz * 0.45 - 0.02),
			Vector3(0.46, LOW_HEIGHT + 0.015, -hz * 0.45 + 0.16),
			Vector3(-0.46, LOW_HEIGHT + 0.015, -hz * 0.45 + 0.16),
			Vector3.UP, dark, dark, dark, dark)
	st.generate_normals()
	_low_mesh_cache = st.commit()
	return _low_mesh_cache


## Full-deck ice arch. The legs stand outside the outermost lane (and outside
## the collider), so they can never be the thing that hits a player who read
## the gap correctly -- they exist purely to stop the beam from looking like it
## is floating, which is what made the gap under it unreadable.
static func _arch_mesh() -> ArrayMesh:
	if _arch_mesh_cache != null:
		return _arch_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := RunnerConfig.DECK_HALF_WIDTH
	var foot := Color(0.20, 0.34, 0.48)
	var body := Color(0.58, 0.80, 0.95)
	var crown := Color(0.94, 0.99, 1.0)
	var lip := Color(1.0, 0.42, 0.28)
	var y0 := BAR_CLEARANCE
	var y1 := BAR_CLEARANCE + BAR_THICKNESS
	_box_faces(st, Vector3(-half, y0 + 0.1, -BAR_DEPTH * 0.5),
			Vector3(half, y1, BAR_DEPTH * 0.5), body, crown)
	# Lower lip of the beam in warning orange. This is the single edge the
	# player is judging when they decide to slide, so it gets its own colour.
	_box_faces(st, Vector3(-half, y0, -BAR_DEPTH * 0.5 - 0.06),
			Vector3(half, y0 + 0.12, BAR_DEPTH * 0.5 + 0.06), lip, lip)
	# Icicles hanging off the lip, stopping well short of the slide envelope.
	# Their job is to make the beam read as a thing with an UNDERSIDE from a
	# distance, which a flat bar never does.
	for i: int in 9:
		var x := lerpf(-half + 0.5, half - 0.5, float(i) / 8.0)
		var drop := 0.16 + 0.1 * absf(sin(float(i) * 2.3))
		_tri_out(st, Vector3(x - 0.11, y0, -0.1), Vector3(x + 0.11, y0, -0.1),
				Vector3(x, y0 - drop, 0.0), Vector3.FORWARD, crown, crown, body)
		_tri_out(st, Vector3(x + 0.11, y0, 0.1), Vector3(x - 0.11, y0, 0.1),
				Vector3(x, y0 - drop, 0.0), Vector3.BACK, crown, crown, body)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var cx := sign_x * (half - 0.3)
		_box_faces(st, Vector3(cx - 0.28, 0.0, -0.32), Vector3(cx + 0.28, y1, 0.32), foot, crown)
	st.generate_normals()
	_arch_mesh_cache = st.commit()
	return _arch_mesh_cache


## Launch ramp: a wedge of packed snow with a kicker lip, rising toward -Z so
## the player runs UP it. Chevrons painted up the face in the same "go" green
## the deck marks use, because the one obstacle in the game that must never be
## dodged has to be distinguishable at range, in a glance, from the ones that
## must.
static func _ramp_mesh() -> ArrayMesh:
	if _ramp_mesh_cache != null:
		return _ramp_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := RAMP_WIDTH * 0.5
	var z_near := RAMP_DEPTH * 0.5
	var z_far := -RAMP_DEPTH * 0.5
	# Near-black flanks. The ONLY cue that says "this is a slope, not paint" from
	# a camera that looks along it is the side triangle read against the snow,
	# so the sides get the darkest value in the scene and the top stays pale.
	var flank := Color(0.09, 0.13, 0.22)
	var foot := Color(0.44, 0.58, 0.76)
	var crown := Color(0.98, 1.0, 1.0)
	var go := Color(0.12, 0.86, 0.30)
	var strips := 6
	var profile: PackedFloat32Array = PackedFloat32Array()
	for i: int in strips + 1:
		var u := float(i) / float(strips)
		# Slightly concave, so the take-off is steeper than the run-on: a
		# straight wedge reads as a doorstop, this reads as a kicker.
		profile.append(RAMP_HEIGHT * pow(u, 1.35))
	for i: int in strips:
		var u0 := float(i) / float(strips)
		var u1 := float(i + 1) / float(strips)
		var z0 := lerpf(z_near, z_far, u0)
		var z1 := lerpf(z_near, z_far, u1)
		var y0 := profile[i]
		var y1 := profile[i + 1]
		var top_n := Vector3(0.0, z0 - z1, y1 - y0).normalized()
		var c0 := foot.lerp(crown, u0)
		var c1 := foot.lerp(crown, u1)
		_quad_out(st, Vector3(-hx, y0, z0), Vector3(hx, y0, z0),
				Vector3(hx, y1, z1), Vector3(-hx, y1, z1), top_n, c0, c0, c1, c1)
		if i % 2 == 0:
			# Chevron band, floating 3 cm over the face. Pointed rather than
			# square: a bar across a slope is a rung, an arrow is a direction.
			var mid_z := lerpf(z0, z1, 0.5)
			var mid_y := lerpf(y0, y1, 0.5) + 0.03
			_tri_out(st, Vector3(-hx * 0.82, y0 + 0.03, z0), Vector3(0.0, mid_y, mid_z - 0.55),
					Vector3(hx * 0.82, y0 + 0.03, z0), top_n, go, go, go)
		for s: int in 2:
			var sx := -hx if s == 0 else hx
			var facing := Vector3(-1.0 if s == 0 else 1.0, 0.0, 0.0)
			_quad_out(st, Vector3(sx, 0.0, z0), Vector3(sx, 0.0, z1),
					Vector3(sx, y1, z1), Vector3(sx, y0, z0), facing, flank, flank, flank, flank)
	# The lip: the back face, plus a bright green bar standing proud of the top
	# edge. That bar is the thing the player is actually timing, and it is the
	# only part of the ramp still visible once they are on top of it.
	_quad_out(st, Vector3(-hx, RAMP_HEIGHT, z_far), Vector3(hx, RAMP_HEIGHT, z_far),
			Vector3(hx, 0.0, z_far), Vector3(-hx, 0.0, z_far), Vector3.FORWARD,
			go, go, flank, flank)
	_box_faces(st, Vector3(-hx - 0.06, RAMP_HEIGHT, z_far - 0.02),
			Vector3(hx + 0.06, RAMP_HEIGHT + 0.16, z_far + 0.34), go, crown)
	# Kicker rails running the WHOLE length of both top edges, following the
	# profile. Two posts at the lip read as two posts; a rail reads as a ramp.
	for s: int in 2:
		var sx := (-hx - 0.09) if s == 0 else (hx + 0.09)
		for i: int in strips:
			var z0 := lerpf(z_near, z_far, float(i) / float(strips))
			var z1 := lerpf(z_near, z_far, float(i + 1) / float(strips))
			_box_faces(st, Vector3(sx - 0.09, profile[i], minf(z0, z1)),
					Vector3(sx + 0.09, profile[i + 1] + 0.2, maxf(z0, z1)), flank, go)
	st.generate_normals()
	_ramp_mesh_cache = st.commit()
	return _ramp_mesh_cache


## Sliding seal, laid along X because it travels along X.
##
## Built here rather than instanced from HazardSeal on purpose. That class is a
## racing-game NODE: it types a PathGuide, drives itself off a course path,
## registers on the racing hazard layer, shoves Racers, and draws its body, two
## eyes, two gleams, two nostrils, a whisker fan and a chevron ring as eight
## separate objects across three materials. This is the same silhouette -- fat
## fusiform spindle, blunt muzzle, swept front flippers, rear fan -- folded into
## ONE vertex-coloured surface on the shared prop material, so a deck full of
## seals costs a handful of draws and no new program links.
static func _seal_mesh() -> ArrayMesh:
	if _seal_mesh_cache != null:
		return _seal_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dorsal := Color(0.15, 0.16, 0.20)
	var belly := Color(0.78, 0.79, 0.82)
	var band := Color(1.0, 0.58, 0.10)
	var rings := 11
	var segs := 8
	var centre_y := SEAL_GIRTH * 0.86
	var ring_pts: Array[PackedVector3Array] = []
	var ring_cols: Array[PackedColorArray] = []
	for i: int in rings + 1:
		var t := float(i) / float(rings)
		var x := lerpf(-SEAL_LENGTH * 0.5, SEAL_LENGTH * 0.5, t)
		# Fusiform: widest a third back from the muzzle, tapering to a blunt
		# nose and a thin tail stock.
		var r := maxf(SEAL_GIRTH * pow(maxf(sin(PI * pow(t, 0.74)), 0.0), 0.52), 0.035)
		var pts := PackedVector3Array()
		var cols := PackedColorArray()
		for j: int in segs:
			var a := TAU * float(j) / float(segs)
			var up := cos(a)
			# Squashed vertically and lifted, so the belly lies flat on the ice
			# the way a hauled-out seal actually does.
			pts.append(Vector3(x, centre_y + up * r * 0.82, sin(a) * r * 1.06))
			var tone := belly.lerp(dorsal, smoothstep(0.1, 0.85, (up + 1.0) * 0.5))
			# Hazard band over the shoulders: the one loud thing on an animal
			# that is otherwise a dark shape on white.
			if up > 0.55 and absf(t - 0.42) < 0.075:
				tone = band
			if t < 0.1:
				tone = tone.lerp(Color(0.07, 0.07, 0.09), 0.7)
			cols.append(tone)
		ring_pts.append(pts)
		ring_cols.append(cols)
	for i: int in rings:
		for j: int in segs:
			var jn := (j + 1) % segs
			var a := ring_pts[i][j]
			var b := ring_pts[i][jn]
			var c := ring_pts[i + 1][jn]
			var d := ring_pts[i + 1][j]
			var n := (a + b + c + d) * 0.25 - Vector3(0.0, centre_y, 0.0)
			n.x = 0.0
			if n.length_squared() < 0.0001:
				n = Vector3.UP
			_quad_out(st, a, b, c, d, n.normalized(),
					ring_cols[i][j], ring_cols[i][jn], ring_cols[i + 1][jn], ring_cols[i + 1][j])
	# Front flippers, swept back along the body.
	for s: int in 2:
		var sz := -1.0 if s == 0 else 1.0
		_flat_fin(st,
				Vector3(-SEAL_LENGTH * 0.16, centre_y * 0.5, sz * SEAL_GIRTH * 0.7),
				Vector3(SEAL_LENGTH * 0.12, centre_y * 0.18, sz * SEAL_GIRTH * 1.9),
				Vector3(SEAL_LENGTH * 0.02, centre_y * 0.6, sz * SEAL_GIRTH * 1.5),
				dorsal)
	# Rear fan, both blades.
	_flat_fin(st, Vector3(SEAL_LENGTH * 0.44, centre_y * 0.7, 0.0),
			Vector3(SEAL_LENGTH * 0.66, centre_y * 1.2, -SEAL_GIRTH * 0.95),
			Vector3(SEAL_LENGTH * 0.66, centre_y * 0.25, -SEAL_GIRTH * 0.5), dorsal)
	_flat_fin(st, Vector3(SEAL_LENGTH * 0.44, centre_y * 0.7, 0.0),
			Vector3(SEAL_LENGTH * 0.66, centre_y * 0.25, SEAL_GIRTH * 0.5),
			Vector3(SEAL_LENGTH * 0.66, centre_y * 1.2, SEAL_GIRTH * 0.95), dorsal)
	# Eyes: two pale glints on a dark head, and the thing that turns a spindle
	# into an animal at the distance the player reads it.
	for s: int in 2:
		var sz := -1.0 if s == 0 else 1.0
		var eye := Vector3(-SEAL_LENGTH * 0.32, centre_y + SEAL_GIRTH * 0.32, sz * SEAL_GIRTH * 0.38)
		_flat_fin(st, eye + Vector3(-0.07, 0.05, 0.0), eye + Vector3(0.07, 0.05, 0.02),
				eye + Vector3(0.0, -0.05, 0.01), Color(0.92, 0.94, 1.0))
	st.generate_normals()
	_seal_mesh_cache = st.commit()
	return _seal_mesh_cache


## One 6 m bay of ice-arch tunnel: the vault seen from underneath, a rib at the
## mouth and a light rail down each springing line. Every face points INWARD,
## because the only side of it anyone will ever see is the inside.
static func _tunnel_mesh() -> ArrayMesh:
	if _tunnel_mesh_cache != null:
		return _tunnel_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS
	# Pale ice with DARK ribs, not the other way round. The first pass made the
	# vault navy and the ribs bright, and against a night sky the shell simply
	# vanished -- the tunnel read as a row of floating hoops. Ice lit from
	# inside is bright; the dimming belongs to the deck tint, which already
	# does it, and the ribs are what carry the rhythm.
	# A CEILING, not a sky. The player is inside this thing, so the vault fills
	# the whole upper frame -- which means any pale blue-white palette resolves
	# to something indistinguishable from the sky it replaced, and the tunnel
	# reads as no tunnel at all. (That is not a hypothesis: a magenta test
	# render showed the shell was there the whole time and simply wore the
	# sky's colour.) So the vault is a mid teal-blue, several stops down from
	# the sky, and the RIBS are the bright thing -- lit bands sweeping overhead
	# are the entire reason to build a tunnel in a runner.
	var vault := Color(0.44, 0.62, 0.82)
	var shade := Color(0.20, 0.33, 0.54)
	var rib := Color(0.92, 0.99, 1.0)
	var segments := 12
	var pts: Array[Vector3] = []
	for i: int in segments + 1:
		var u := float(i) / float(segments)
		# Elliptical arch springing from the kerb line and peaking over the
		# middle lane, high enough that a ramp launch (3.38 m of air plus a
		# penguin) passes under it untouched.
		var lift := sqrt(maxf(0.0, 1.0 - pow(2.0 * u - 1.0, 2.0)))
		pts.append(Vector3(lerpf(-outer, outer, u),
				TUNNEL_SPRING + (TUNNEL_APEX - TUNNEL_SPRING) * pow(lift, 0.75), 0.0))
	for i: int in segments:
		var a := pts[i]
		var b := pts[i + 1]
		var inward := -((a + b) * 0.5).normalized()
		var ca := vault.lerp(shade, absf(a.x) / outer)
		var cb := vault.lerp(shade, absf(b.x) / outer)
		_quad_out(st, Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0),
				Vector3(b.x, b.y, -TUNNEL_SEGMENT), Vector3(a.x, a.y, -TUNNEL_SEGMENT),
				inward, ca, cb, cb, ca)
		# Rib at the bay mouth, dropped 26 cm below the vault so it is a visible
		# band and not a texture. This is the strobe that makes speed readable
		# inside a tunnel, where the walls otherwise give you nothing.
		_quad_out(st, Vector3(a.x, a.y - 0.26, -0.05), Vector3(b.x, b.y - 0.26, -0.05),
				Vector3(b.x, b.y - 0.26, -0.55), Vector3(a.x, a.y - 0.26, -0.55),
				inward, rib, rib, rib, rib)
	for s: int in 2:
		var sx := (-outer + 0.35) if s == 0 else (outer - 0.35)
		_box_faces(st, Vector3(sx - 0.1, TUNNEL_SPRING - 0.28, -TUNNEL_SEGMENT),
				Vector3(sx + 0.1, TUNNEL_SPRING - 0.08, 0.0), rib, rib)
	st.generate_normals()
	_tunnel_mesh_cache = st.commit()
	return _tunnel_mesh_cache


## Unit deck chevron: 1 m across, 1 m deep, pointing down-track (-Z), flat.
## White vertex colours, so the MultiMesh instance colour is the whole tint.
static func _mark_mesh() -> ArrayMesh:
	if _mark_mesh_cache != null:
		return _mark_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	var thickness := 0.34
	for s: int in 2:
		var sx := -0.5 if s == 0 else 0.5
		_quad_out(st,
				Vector3(sx, 0.0, 0.16),
				Vector3(0.0, 0.0, -0.5),
				Vector3(0.0, 0.0, -0.5 + thickness),
				Vector3(sx, 0.0, 0.16 + thickness),
				Vector3.UP, w, w, w, w)
	st.generate_normals()
	_mark_mesh_cache = st.commit()
	return _mark_mesh_cache


## Pennants on a short mast, hanging out in +X. Yawing the whole instance a few
## degrees reads as a flap, because the mast is thin enough that nobody can see
## it turn -- which is what lets a whole chunk of banners animate inside one
## MultiMesh instead of costing a node apiece.
static func _banner_mesh() -> ArrayMesh:
	if _banner_mesh_cache != null:
		return _banner_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pole := Color(0.22, 0.26, 0.34)
	var cloth_a := Color(1.0, 0.42, 0.24)
	var cloth_b := Color(1.0, 0.82, 0.30)
	_box_faces(st, Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 2.4, 0.05), pole, pole)
	for i: int in 2:
		var y := 2.3 - float(i) * 0.72
		_flat_fin(st, Vector3(0.05, y, 0.0), Vector3(1.05, y - 0.22, 0.0),
				Vector3(0.05, y - 0.62, 0.0), cloth_a if i == 0 else cloth_b)
	st.generate_normals()
	_banner_mesh_cache = st.commit()
	return _banner_mesh_cache


## Gull: a shallow V of two blades, 1 m wingspan at unit scale. Flapping is a
## non-uniform scale on the instance, which costs one basis multiply.
static func _bird_mesh() -> ArrayMesh:
	if _bird_mesh_cache != null:
		return _bird_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := Color(0.90, 0.92, 0.98)
	var tip := Color(0.24, 0.27, 0.34)
	for s: int in 2:
		var sx := -1.0 if s == 0 else 1.0
		_flat_fin(st, Vector3(0.0, 0.0, -0.1), Vector3(sx * 0.5, 0.16, 0.06),
				Vector3(0.0, 0.0, 0.12), col)
		_flat_fin(st, Vector3(sx * 0.32, 0.1, -0.02), Vector3(sx * 0.5, 0.16, 0.06),
				Vector3(sx * 0.36, 0.11, 0.08), tip)
	st.generate_normals()
	_bird_mesh_cache = st.commit()
	return _bird_mesh_cache


## Small faceted ice shard for the tumbling debris. Ten faces, no ambition.
static func _shard_mesh() -> ArrayMesh:
	if _shard_mesh_cache != null:
		return _shard_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pale := Color(0.94, 0.98, 1.0)
	var deep := Color(0.42, 0.64, 0.84)
	var top := Vector3(0.0, 0.5, 0.0)
	var bottom := Vector3(0.0, -0.42, 0.0)
	var ring: Array[Vector3] = []
	for i: int in 5:
		var a := TAU * float(i) / 5.0
		ring.append(Vector3(cos(a) * 0.36, 0.06 * sin(a * 2.0), sin(a) * 0.32))
	for i: int in 5:
		var j := (i + 1) % 5
		_tri3(st, ring[i], ring[j], top, deep, deep, pale)
		_tri3(st, ring[j], ring[i], bottom, deep, deep, deep)
	st.generate_normals()
	_shard_mesh_cache = st.commit()
	return _shard_mesh_cache


## Aurora ribbon. UV.x runs along the curtain and UV.y down it, which is the
## mapping aurora.gdshader expects; the hem is left ragged in geometry as well
## as in the shader so the bottom edge never reads as a cut sheet.
static func _curtain_mesh() -> ArrayMesh:
	if _curtain_mesh_cache != null:
		return _curtain_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 14
	var width := 150.0
	var height := 44.0
	for i: int in cols:
		var u0 := float(i) / float(cols)
		var u1 := float(i + 1) / float(cols)
		var x0 := (u0 - 0.5) * width
		var x1 := (u1 - 0.5) * width
		# Folds in Z, so the curtain catches the light differently along its
		# length instead of reading as a billboard.
		var z0 := sin(u0 * 7.0) * 9.0
		var z1 := sin(u1 * 7.0) * 9.0
		var drop0 := height * (0.82 + 0.18 * sin(u0 * 11.0))
		var drop1 := height * (0.82 + 0.18 * sin(u1 * 11.0))
		st.set_uv(Vector2(u0, 0.0)); st.set_color(Color.WHITE); st.add_vertex(Vector3(x0, 0.0, z0))
		st.set_uv(Vector2(u1, 0.0)); st.set_color(Color.WHITE); st.add_vertex(Vector3(x1, 0.0, z1))
		st.set_uv(Vector2(u1, 1.0)); st.set_color(Color.WHITE); st.add_vertex(Vector3(x1, -drop1, z1))
		st.set_uv(Vector2(u0, 0.0)); st.set_color(Color.WHITE); st.add_vertex(Vector3(x0, 0.0, z0))
		st.set_uv(Vector2(u1, 1.0)); st.set_color(Color.WHITE); st.add_vertex(Vector3(x1, -drop1, z1))
		st.set_uv(Vector2(u0, 1.0)); st.set_color(Color.WHITE); st.add_vertex(Vector3(x0, -drop0, z0))
	st.generate_normals()
	_curtain_mesh_cache = st.commit()
	return _curtain_mesh_cache


## Power-up crate. Three DIFFERENT SOLIDS, not three tints of one box: colour
## is the first thing to go at distance and the first thing to go for a
## colour-blind player, so the silhouette has to carry the identity on its own.
## Cube = magnet, octahedron = shield, hex drum = double. Each also gets an icon
## in a contrasting value on the faces the player actually sees.
static func _crate_mesh(id: StringName) -> ArrayMesh:
	var key := String(id)
	if _crate_meshes.has(key):
		return _crate_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := Color(1.0, 1.0, 1.0)
	var edge := Color(0.30, 0.32, 0.40)
	var icon := Color(0.06, 0.07, 0.10)
	match id:
		RunnerConfig.POWERUP_SHIELD:
			# Octahedron: reads as a gem, which is what a defensive pickup
			# should feel like.
			var top := Vector3(0.0, 0.72, 0.0)
			var bottom := Vector3(0.0, -0.72, 0.0)
			var ring: Array[Vector3] = []
			for i: int in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				ring.append(Vector3(cos(a) * 0.62, 0.0, sin(a) * 0.62))
			for i: int in 4:
				var j := (i + 1) % 4
				_tri3(st, ring[i], ring[j], top, edge, edge, shell)
				_tri3(st, ring[j], ring[i], bottom, edge, edge, shell)
			_flat_fin(st, Vector3(-0.26, 0.30, -0.44), Vector3(0.26, 0.30, -0.44),
					Vector3(0.0, -0.30, -0.5), icon)
		RunnerConfig.POWERUP_DOUBLE:
			# Hex drum lying on its side, so the "x2" plate faces the player.
			var pts: Array[Vector3] = []
			for i: int in 6:
				var a := TAU * float(i) / 6.0
				pts.append(Vector3(cos(a) * 0.66, sin(a) * 0.66, 0.0))
			for i: int in 6:
				var j := (i + 1) % 6
				_quad_out(st, pts[i] + Vector3(0.0, 0.0, -0.34), pts[j] + Vector3(0.0, 0.0, -0.34),
						pts[j] + Vector3(0.0, 0.0, 0.34), pts[i] + Vector3(0.0, 0.0, 0.34),
						((pts[i] + pts[j]) * 0.5).normalized(), edge, edge, shell, shell)
			for s: int in 2:
				var zz := -0.34 if s == 0 else 0.34
				var facing := Vector3.FORWARD if s == 0 else Vector3.BACK
				for i: int in 6:
					var j := (i + 1) % 6
					_tri_out(st, pts[i] + Vector3(0.0, 0.0, zz), pts[j] + Vector3(0.0, 0.0, zz),
							Vector3(0.0, 0.0, zz), facing, shell, shell, shell)
				# Two bars: an "x2" plate that survives being four pixels tall.
				for b: int in 2:
					var y := 0.16 - float(b) * 0.32
					var pz := zz + facing.z * 0.03
					_quad_out(st, Vector3(-0.34, y - 0.07, pz), Vector3(0.34, y - 0.07, pz),
							Vector3(0.34, y + 0.07, pz), Vector3(-0.34, y + 0.07, pz),
							facing, icon, icon, icon, icon)
		_:
			# Cube: the magnet, and the fallback for any id added later.
			_box_faces(st, Vector3(-0.55, -0.55, -0.55), Vector3(0.55, 0.55, 0.55), edge, shell)
			# Horseshoe on the front and back faces: two prongs and a yoke.
			for s: int in 2:
				var zz := -0.58 if s == 0 else 0.58
				var facing := Vector3.FORWARD if s == 0 else Vector3.BACK
				for p: int in 2:
					var x := -0.28 + float(p) * 0.56
					_quad_out(st, Vector3(x - 0.11, -0.36, zz), Vector3(x + 0.11, -0.36, zz),
							Vector3(x + 0.11, 0.16, zz), Vector3(x - 0.11, 0.16, zz),
							facing, icon, icon, icon, icon)
				_quad_out(st, Vector3(-0.39, 0.16, zz), Vector3(0.39, 0.16, zz),
						Vector3(0.39, 0.38, zz), Vector3(-0.39, 0.38, zz),
						facing, icon, icon, icon, icon)
	st.generate_normals()
	var mesh := st.commit()
	_crate_meshes[key] = mesh
	return mesh


## Runner fish. The racing game's FishPickup is not instanced here on purpose:
## it types a Racer member, wires itself onto the racing collision layers and
## reads the racing accessibility settings, and it draws three surfaces (body,
## fin and eye shaders) per fish -- three draw calls each, where a run can have
## eighty fish in view at once. This is the same silhouette (fusiform body,
## dark dorsal over silver belly, oversized hot-orange tail and dorsal fin)
## folded into ONE vertex-coloured surface, so a whole chunk's fish are a
## single MultiMesh draw.
##
## Sized against FISH_LENGTH rather than authored in absolute units: the first
## pass drew a 0.8 m fish inside a 1.9 m grab sphere, and the result read as a
## salmon lying across the lane.
static func _fish_mesh() -> ArrayMesh:
	if _fish_mesh_cache != null:
		return _fish_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dorsal := Color(0.10, 0.18, 0.28)
	var silver := Color(0.97, 0.96, 0.92)
	var fin := Color(1.0, 0.40, 0.08)
	# The proportions below are authored in units of the original 0.82 m fish;
	# k rescales the whole thing to FISH_LENGTH nose-to-tail in one place.
	var k := FISH_LENGTH / 0.82
	var rings := 7
	var segs := 6
	var ring_pts: Array[PackedVector3Array] = []
	for i: int in rings + 1:
		var t := float(i) / float(rings)
		var x := lerpf(-0.30, 0.26, t) * k
		var r := maxf(0.155 * pow(maxf(sin(PI * pow(t, 0.72)), 0.0), 0.85), 0.005) * k
		var pts := PackedVector3Array()
		for j: int in segs:
			var a := TAU * float(j) / float(segs)
			pts.append(Vector3(x, cos(a) * r, sin(a) * r * 0.6))
		ring_pts.append(pts)
	for i: int in rings:
		for j: int in segs:
			var jn := (j + 1) % segs
			var a := ring_pts[i][j]
			var b := ring_pts[i][jn]
			var c := ring_pts[i + 1][jn]
			var d := ring_pts[i + 1][j]
			# Countershading baked per vertex: the chase camera looks DOWN on a
			# fish lying over white snow, so the dorsal surface is nearly all
			# the player ever sees and it has to be the dark one.
			_quad_out(st, a, b, c, d, ((a + b + c + d) * 0.25 * Vector3(0.0, 1.0, 1.0)).normalized(),
					_fish_tone(a / k, dorsal, silver), _fish_tone(b / k, dorsal, silver),
					_fish_tone(c / k, dorsal, silver), _fish_tone(d / k, dorsal, silver))
	# Forked tail and dorsal fin, emitted both ways round so a flat blade still
	# shows under a single-sided material.
	_flat_fin(st, Vector3(0.22, 0.0, 0.0) * k, Vector3(0.52, 0.26, 0.0) * k,
			Vector3(0.36, 0.04, 0.0) * k, fin)
	_flat_fin(st, Vector3(0.22, 0.0, 0.0) * k, Vector3(0.36, -0.04, 0.0) * k,
			Vector3(0.52, -0.26, 0.0) * k, fin)
	_flat_fin(st, Vector3(-0.08, 0.09, 0.0) * k, Vector3(0.04, 0.34, 0.0) * k,
			Vector3(0.15, 0.09, 0.0) * k, fin)
	st.generate_normals()
	_fish_mesh_cache = st.commit()
	return _fish_mesh_cache


static func _fish_tone(v: Vector3, dorsal: Color, silver: Color) -> Color:
	return silver.lerp(dorsal, smoothstep(-0.06, 0.05, v.y))


static func _flat_fin(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	st.set_color(col); st.add_vertex(a)
	st.set_color(col); st.add_vertex(b)
	st.set_color(col); st.add_vertex(c)
	st.set_color(col); st.add_vertex(a)
	st.set_color(col); st.add_vertex(c)
	st.set_color(col); st.add_vertex(b)


## Axis-aligned box, all six faces, colour ramped bottom to top.
static func _box_faces(st: SurfaceTool, lo: Vector3, hi: Vector3, bottom: Color, top: Color) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	_quad_out(st, p[0], p[1], p[5], p[4], Vector3.FORWARD, bottom, bottom, top, top)
	_quad_out(st, p[2], p[3], p[7], p[6], Vector3.BACK, bottom, bottom, top, top)
	_quad_out(st, p[1], p[2], p[6], p[5], Vector3.RIGHT, bottom, bottom, top, top)
	_quad_out(st, p[3], p[0], p[4], p[7], Vector3.LEFT, bottom, bottom, top, top)
	_quad_out(st, p[4], p[5], p[6], p[7], Vector3.UP, top, top, top, top)
	_quad_out(st, p[3], p[2], p[1], p[0], Vector3.DOWN, bottom, bottom, bottom, bottom)


static func _tri3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca); st.add_vertex(a)
	st.set_color(cb); st.add_vertex(b)
	st.set_color(cc); st.add_vertex(c)


static func _quad_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		outward: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri_out(st, a, b, c, outward, ca, cb, cc)
	_tri_out(st, a, c, d, outward, ca, cc, cd)


## Emits a triangle wound so its front face points along `outward`. Same rule
## the racing game's procedural meshes use: hand-authored winding is the single
## most common way a generated mesh comes out invisible, so the winding is
## derived instead of trusted.
static func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		st.set_color(ca); st.add_vertex(a)
		st.set_color(cc); st.add_vertex(c)
		st.set_color(cb); st.add_vertex(b)
	else:
		st.set_color(ca); st.add_vertex(a)
		st.set_color(cb); st.add_vertex(b)
		st.set_color(cc); st.add_vertex(c)


## --- Chunk ------------------------------------------------------------------

## One streamed piece of track. Owns its own geometry, its obstacles, its fish
## and the bookkeeping the fairness rules need, so recycling a chunk is a single
## queue_free() with nothing left dangling.
class RunnerChunk:
	extends Node3D

	## Animation kinds for the dressing MultiMeshes. A small int rather than a
	## script per prop: the whole animated set for a chunk is one loop over
	## three arrays, and a Node per banner would cost more in tree overhead
	## than the motion is worth.
	const ANIM_SWAY: int = 0
	const ANIM_TUMBLE: int = 1
	const ANIM_FLAP: int = 2

	var index: int = 0
	var difficulty: float = 0.0
	var biome: int = 0
	## Blocked-lane count per obstacle row, keyed by rounded local z. This is
	## what makes "never fill all three lanes" enforceable without every pattern
	## having to reason about it.
	var rows: Dictionary = {}
	## Every obstacle actually built, as (local_z, first_lane, span). Read only
	## by the power-up placer, which has to find somewhere in a finished chunk
	## that a crate can sit without being defended by a block.
	var obstacles: PackedVector3Array = PackedVector3Array()
	var contact_patches: Array[Transform3D] = []
	var marks: Array[Transform3D] = []
	var mark_colors: PackedColorArray = PackedColorArray()
	## Fish are drawn as ONE MultiMesh for the whole chunk; each RunnerFish
	## Area3D knows only its instance index, and collecting collapses that
	## instance to zero scale.
	var fish_base: Array[Transform3D] = []
	var fish_nodes: Array[Node3D] = []
	var fish_alive: PackedByteArray = PackedByteArray()
	var fish_mm: MultiMesh = null
	var _anim_mm: Array[MultiMesh] = []
	var _anim_base: Array = []
	var _anim_kind: PackedInt32Array = PackedInt32Array()
	var _anim_time: float = 0.0

	func note_row(local_z: float, is_block: bool, span: int) -> void:
		if not is_block:
			return
		var key := int(round(local_z))
		rows[key] = int(rows.get(key, 0)) + span

	func row_blocked_lanes(local_z: float) -> int:
		return int(rows.get(int(round(local_z)), 0))

	func note_obstacle(local_z: float, lane: int, span: int) -> void:
		obstacles.append(Vector3(local_z, float(lane), float(span)))

	## True when nothing this chunk built is within `clearance` metres of
	## (local_z, lane). Seals are recorded as spanning every lane, so a crate
	## never lands in a band a seal is sweeping.
	func lane_clear(local_z: float, lane: int, clearance: float) -> bool:
		for entry: Vector3 in obstacles:
			if absf(entry.x - local_z) > clearance:
				continue
			var first := int(entry.y)
			if lane >= first and lane < first + int(entry.z):
				return false
		return true

	## Claims a MultiMesh slot for a fish about to be added and returns its
	## index. Takes the node as a bare Node3D rather than a RunnerFish, so the
	## chunk never has to name the pickup class and the two inner classes stay
	## a one-way dependency -- but it does have to KEEP the reference, because
	## the magnet power-up drags the collider around at run time and the drawn
	## instance has to follow it, or the fish flies away from its own picture.
	func reserve_fish_slot(node: Node3D, pos: Vector3) -> int:
		var slot := fish_base.size()
		# Baked yaw variety: with the whole chunk in one MultiMesh there is no
		# per-fish node to rotate, so the spread comes from the instance index.
		fish_base.append(Transform3D(Basis(Vector3.UP, float(slot) * 1.31), pos))
		fish_nodes.append(node)
		fish_alive.append(1)
		return slot

	func register_anim(mmi: MultiMeshInstance3D, base: Array[Transform3D], kind: int) -> void:
		if mmi == null or mmi.multimesh == null:
			return
		_anim_mm.append(mmi.multimesh)
		_anim_base.append(base)
		_anim_kind.append(kind)

	## Flushes the collected fish, deck chevrons and contact shadows into their
	## MultiMeshes. headless skips every drawn thing; the colliders are built
	## either way, so a sim tests exactly the track a player runs.
	func finish(headless: bool) -> void:
		if not headless:
			_flush_fish()
			_flush_patches()
			_flush_marks()
		set_process(fish_mm != null or not _anim_mm.is_empty())
		contact_patches.clear()
		marks.clear()
		mark_colors.clear()

	func _flush_fish() -> void:
		if fish_base.is_empty():
			return
		fish_mm = MultiMesh.new()
		fish_mm.transform_format = MultiMesh.TRANSFORM_3D
		fish_mm.mesh = RunnerTrack._fish_mesh()
		fish_mm.instance_count = fish_base.size()
		for i: int in fish_base.size():
			fish_mm.set_instance_transform(i, fish_base[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Fish"
		mmi.multimesh = fish_mm
		mmi.material_override = RunnerTrack._prop_material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

	func _flush_patches() -> void:
		if contact_patches.is_empty():
			return
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = VisualLibrary.contact_patch_mesh()
		mm.instance_count = contact_patches.size()
		for i: int in contact_patches.size():
			mm.set_instance_transform(i, contact_patches[i])
		var patches := MultiMeshInstance3D.new()
		patches.name = "Contact"
		patches.multimesh = mm
		patches.material_override = VisualLibrary.contact_shadow_material(0.34)
		patches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(patches)

	func _flush_marks() -> void:
		if marks.is_empty():
			return
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# use_colors has to be set before instance_count: the instance buffer is
		# allocated at that assignment, and turning colours on afterwards leaves
		# them silently unwritable.
		mm.use_colors = true
		mm.mesh = RunnerTrack._mark_mesh()
		mm.instance_count = marks.size()
		for i: int in marks.size():
			mm.set_instance_transform(i, marks[i])
			mm.set_instance_color(i, mark_colors[i])
		var node := MultiMeshInstance3D.new()
		node.name = "Marks"
		node.multimesh = mm
		node.material_override = RunnerTrack._mark_material()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

	func mark_fish_taken(i: int) -> void:
		if i < 0 or i >= fish_alive.size():
			return
		fish_alive[i] = 0
		if fish_mm != null:
			# Degenerate scale rather than a shrinking instance_count: the array
			# is index-addressed by the surviving fish, so instances can only be
			# removed in place.
			fish_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO),
					fish_base[i].origin))

	## Bobs and spins the fish, sways the banners, tumbles the shards and flaps
	## the gulls -- for the whole chunk at once. A few dozen instance-transform
	## writes per chunk per frame is far cheaper than a node and a script
	## callback per prop, and a world that sits perfectly still is the fastest
	## way to make a runner read as a diagram of a runner.
	func _process(delta: float) -> void:
		_anim_time += delta
		if fish_mm != null:
			_animate_fish()
		for a: int in _anim_mm.size():
			var mm: MultiMesh = _anim_mm[a]
			var base: Array = _anim_base[a]
			match _anim_kind[a]:
				ANIM_SWAY:
					for i: int in base.size():
						var t: Transform3D = base[i]
						var ph := float(i) * 0.9 + t.origin.z * 0.11
						mm.set_instance_transform(i, Transform3D(
								t.basis.rotated(Vector3.UP, sin(_anim_time * 3.6 + ph) * 0.34),
								t.origin))
				ANIM_TUMBLE:
					for i: int in base.size():
						var t: Transform3D = base[i]
						var ph := float(i) * 1.7
						mm.set_instance_transform(i, Transform3D(
								t.basis.rotated(Vector3(0.42, 1.0, 0.28).normalized(),
										_anim_time * (0.9 + fmod(ph, 1.3))),
								t.origin + Vector3(0.0, sin(_anim_time * 1.6 + ph) * 0.22, 0.0)))
				ANIM_FLAP:
					for i: int in base.size():
						var t: Transform3D = base[i]
						var ph := float(i) * 1.13
						var flap := sin(_anim_time * 4.4 + ph)
						mm.set_instance_transform(i, Transform3D(
								t.basis.scaled(Vector3(1.0, 1.0 + flap * 0.55, 1.0)),
								t.origin + Vector3(sin(_anim_time * 0.35 + ph) * 1.4,
										flap * 0.28, 0.0)))

	func _animate_fish() -> void:
		for i: int in fish_base.size():
			if fish_alive[i] == 0:
				continue
			var phase := float(i) * 1.31
			# Follow the collider, not the baked slot: the magnet power-up moves
			# the Area3D, and the drawing has to go with it.
			var origin := fish_base[i].origin
			var node := fish_nodes[i]
			if node != null and is_instance_valid(node):
				origin = node.position
			fish_mm.set_instance_transform(i, Transform3D(
					Basis(Vector3.UP, phase + _anim_time * 0.9),
					origin + Vector3(0.0, sin(_anim_time * 2.4 + phase) * 0.13, 0.0)))


## --- Fish -------------------------------------------------------------------

## A single collectable. Deliberately tiny: the visual lives in the chunk's
## MultiMesh, so this is a collider, a value and a one-shot handshake.
class RunnerFish:
	extends Area3D

	var value: int = 1
	var chunk: RunnerChunk = null
	var mm_index: int = -1
	var _collected: bool = false

	## Awards the fish and removes it. Safe to call twice -- the second caller
	## gets 0, because an overlap test can easily report the same pickup on two
	## consecutive frames before the free lands.
	func collect() -> int:
		if _collected:
			return 0
		_collected = true
		hide()
		if is_instance_valid(chunk):
			chunk.mark_fish_taken(mm_index)
		set_deferred("monitorable", false)
		queue_free()
		return value


## --- Movers -----------------------------------------------------------------

## A hazard that crosses the lanes. One sine in X, and the rest is presentation:
## a roll into the direction of travel, a nose swing so the seal faces where it
## is going, and a shoulder lift at the ends of the sweep where it turns round.
##
## Runs on _process rather than _physics_process because the runner player
## resolves its own overlaps in the frame loop -- a hazard that moved on the
## physics tick would be a frame behind the collision test that reads it.
class RunnerMover:
	extends Area3D

	var sweep: float = 3.0
	var phase: float = 0.0
	var omega: float = 1.4
	var body: Node3D = null
	var _time: float = 0.0

	func _process(delta: float) -> void:
		_time += delta
		var a := phase + _time * omega
		position.x = sin(a) * sweep
		if body == null:
			return
		var heading := cos(a)
		# Face travel: the mesh is built nose-toward -X, so a seal going +X has
		# to turn about. Eased rather than snapped, so the turn at the end of a
		# sweep is a visible manoeuvre instead of a pop.
		body.rotation.y = lerp_angle(body.rotation.y, 0.0 if heading < 0.0 else PI,
				minf(1.0, delta * 6.0))
		body.rotation.z = -heading * 0.22
		body.rotation.x = sin(a * 2.0) * 0.07
		body.position.y = absf(sin(a)) * 0.05


## --- Power-ups --------------------------------------------------------------

## A crate. Three of these exist in the whole design, and the difference between
## them is entirely in what the player's code does with the id -- so this class
## is a collider, a StringName and the same one-shot handshake the fish uses.
class RunnerPowerup:
	extends Area3D

	var id: StringName = &""
	var body: Node3D = null
	var _taken: bool = false
	var _time: float = 0.0

	func powerup_id() -> StringName:
		return id

	## Awards the power-up and removes it. Safe to call twice -- the second
	## caller gets &"", for the same reason the fish returns 0.
	func collect() -> StringName:
		if _taken:
			return &""
		_taken = true
		hide()
		set_deferred("monitorable", false)
		queue_free()
		return id

	func _process(delta: float) -> void:
		if body == null:
			return
		_time += delta
		# Tumbling on two axes, not one: a crate spinning about Y alone reads as
		# scenery on a turntable, and a power-up should be the most alive thing
		# on the deck.
		body.rotation.y = _time * 1.9
		body.rotation.x = sin(_time * 1.3) * 0.45
		body.position.y = sin(_time * 2.6) * 0.16
