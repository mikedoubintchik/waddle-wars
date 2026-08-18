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
## Fairness is a BUILD-TIME invariant here, not a runtime hope:
##   * no obstacle row ever fills all three lanes with solid blocks;
##   * a jump-required obstacle is never placed within a jump's worth of
##     travel of a slide-required one in the same lane (see _can_place());
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
## Knee-high, so a jump clears it with ~0.9 m to spare and a slide does not.
const LOW_HEIGHT: float = 0.72
const LOW_DEPTH: float = 1.15
## Overhead bar clearance: the midpoint between the sliding and standing probe
## heights. Derived from the config rather than typed as a number so the bar
## keeps its meaning if the movement tuning moves -- it must always sit above
## SLIDE_HEIGHT (a slide fits) and below STAND_HEIGHT (running upright does
## not), and the midpoint is the placement with the most margin on both sides.
const BAR_CLEARANCE: float = (RunnerConfig.SLIDE_HEIGHT + RunnerConfig.STAND_HEIGHT) * 0.5
const BAR_THICKNESS: float = 1.05
const BAR_DEPTH: float = 1.3

## --- Pickups ----------------------------------------------------------------
## Chest height on a standing penguin, with a generous grab sphere: a fish the
## player has clearly run through must never fail to register at 38 m/s.
const FISH_Y: float = 1.05
const FISH_RADIUS: float = 0.95
const FISH_SPACING: float = 3.6
## Apex of a fish arc laid over a jumpable obstacle -- inside the 1.64 m jump
## so the arc is collectable, above the 0.72 m obstacle so it is not free.
const FISH_ARC_APEX: float = 1.5

## --- Pacing -----------------------------------------------------------------
## Chunks at the very start of a run that are guaranteed empty.
const WARMUP_CHUNKS: int = 3
## Keeps obstacle rows off the chunk seams, so two chunks authored independently
## cannot butt two rows up against each other.
const CHUNK_EDGE_MARGIN: float = 5.5
## Spacing between obstacle rows. In TIME (which is what a player actually
## experiences) these are ~0.85 s apart at the start speed and ~0.30 s apart at
## MAX_SPEED, which is where an endless runner should end up.
const ROW_GAP_EASY: float = 17.0
const ROW_GAP_HARD: float = 11.5
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

## Obstacle kinds. The index doubles as the lookup into KIND_NAMES, which is
## what lands in the "kind" metadata the runner player reads.
enum Kind {
	NONE,
	BLOCK,
	BAR,
	LOW,
}

const KIND_NAMES: Array[String] = ["", "block", "bar", "low"]

## Chunk archetypes. Named because a run should be recognisable in the replay
## of the player's memory ("the slide gallery got me") rather than a uniform
## sprinkle of hazards.
enum Pattern {
	OPEN,           ## Breathing room: no obstacles, one flowing fish line.
	LANE_WEAVE,     ## Rows of solid blocks; the survivable lane moves.
	SLIDE_GALLERY,  ## Consecutive ice arches with fish laid low underneath.
	JUMP_STUTTER,   ## Staggered knee-high ridges, fish arcs over them.
	FISH_ARC,       ## Reward chunk: a sweeping fish line across the lanes.
	MIXED_GAUNTLET, ## Block row, arch, ridge row in sequence. Late-run only.
	PINCH,          ## Two lanes blocked; one thread of survivable track.
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
## World z of the most recent jump-required and slide-required obstacle in each
## lane. Kept on the streamer rather than per chunk so the fairness rule holds
## across a chunk seam, where two independently-authored patterns meet.
var _lane_jump_z: PackedFloat32Array = PackedFloat32Array()
var _lane_slide_z: PackedFloat32Array = PackedFloat32Array()


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


## --- Streaming --------------------------------------------------------------

## Chunk containing a world z. Chunk i owns z in (-(i+1)*L, -i*L].
func _chunk_index_at(z: float) -> int:
	return int(floor(-z / RunnerConfig.CHUNK_LENGTH))


func _clear() -> void:
	for chunk: RunnerChunk in _chunks:
		_free_chunk(chunk)
	_chunks.clear()
	_first_index = 0
	_next_index = 0
	_last_pattern = -1
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
	chunk.position = Vector3(0.0, 0.0, -float(index) * RunnerConfig.CHUNK_LENGTH)
	add_child(chunk)
	# Seeded from (run seed, chunk index) rather than from a rolling stream, so
	# a chunk is identical however the streaming happened to be scheduled --
	# which is what makes a seeded run reproducible in a test.
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 1000003 + index * 7919 + 11
	if not _headless:
		_build_deck(chunk)
		_build_dressing(chunk, rng)
	var pattern := _pick_pattern(rng, difficulty, index)
	_run_pattern(pattern, chunk, rng, difficulty)
	_last_pattern = pattern
	chunk.finish(
		_fish_mesh() if not _headless else null,
		_prop_material() if not _headless else null,
		VisualLibrary.contact_patch_mesh() if not _headless else null,
		VisualLibrary.contact_shadow_material(0.34) if not _headless else null)
	_chunks.append(chunk)
	_next_index = index + 1


## --- Patterns ---------------------------------------------------------------

func _pick_pattern(rng: RandomNumberGenerator, difficulty: float, index: int) -> int:
	if index < WARMUP_CHUNKS:
		return Pattern.OPEN
	# Indexed by Pattern value. Weights that start negative stay clamped at
	# zero until difficulty crosses their gate, which is how MIXED_GAUNTLET and
	# PINCH stay out of the first minute of a run entirely.
	var weights := PackedFloat32Array()
	weights.append(lerpf(3.4, 0.6, difficulty))          # OPEN
	weights.append(lerpf(2.2, 2.8, difficulty))          # LANE_WEAVE
	weights.append(maxf(0.0, lerpf(0.4, 2.4, difficulty)))  # SLIDE_GALLERY
	weights.append(lerpf(1.3, 2.2, difficulty))          # JUMP_STUTTER
	weights.append(lerpf(1.8, 0.9, difficulty))          # FISH_ARC
	weights.append(maxf(0.0, lerpf(-1.4, 2.8, difficulty)))  # MIXED_GAUNTLET
	weights.append(maxf(0.0, lerpf(-1.1, 2.2, difficulty)))  # PINCH
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


## No obstacles: a single fish line that drifts across a lane boundary, so even
## the calm chunks ask the player to steer rather than hold one lane.
func _pattern_open(chunk: RunnerChunk, rng: RandomNumberGenerator, _difficulty: float) -> void:
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
		_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.4, z))
		_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.4, z - 2.4))
		if i + 1 < rows.size():
			_fish_line(chunk, lane, z - 5.0, rows[i + 1] + 3.0, FISH_Y)
		lane = clampi(lane + rng.randi_range(-1, 1), 0, RunnerConfig.LANE_COUNT - 1)


## Staggered knee-high ridges with a fish arc over each: the arc is the timing
## cue, since a ridge low enough to jump is also low enough to lose against
## white snow at distance.
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


## Reward chunk. One jumpable ridge with an arc over it and a long sweeping
## fish line that crosses every lane -- the pacing beat that makes the gauntlet
## chunks feel like gauntlets.
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
					_add_fish(chunk, Vector3(RunnerConfig.lane_x(lane), 0.4, z))
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


## --- Obstacles --------------------------------------------------------------

## True when this kind may go in these lanes at this z. Bars demand a slide and
## ridges demand a jump; committing to either takes long enough at speed that
## the other one arriving too soon is unsurvivable however well the player
## plays, so the placement is refused instead.
func _can_place(kind: int, lane: int, span: int, world_z: float, difficulty: float) -> bool:
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
		_:
			# The arch always spans the whole deck. A partial bar reads as an
			# arch from 60 m out and only resolves into "slide here, not there"
			# far too late, so the mode never builds one.
			area.position.x = 0.0
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
	chunk.add_child(area)
	chunk.note_row(local_z, kind == Kind.BLOCK, span)
	_note_placement(kind, lane, span, world_z)
	return true


## --- Pickups ----------------------------------------------------------------

func _add_fish(chunk: RunnerChunk, local_pos: Vector3) -> void:
	var fish := RunnerFish.new()
	fish.position = local_pos
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
	fish.mm_index = chunk.reserve_fish_slot(local_pos)


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


## --- Chunk geometry ---------------------------------------------------------

## Deck, lane seams and the kerb/drop-off verge. Three shared meshes, three
## shared materials, three nodes: this is the entire static cost of a chunk.
func _build_deck(chunk: RunnerChunk) -> void:
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	deck.mesh = _deck_mesh()
	deck.material_override = VisualLibrary.snow_material(Color(0.94, 0.965, 1.0), 0.5, -1.0, 1.0)
	deck.position = Vector3(0.0, 0.0, -RunnerConfig.CHUNK_LENGTH * 0.5)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(deck)
	# Lane seams: a flat white deck gives the player nothing to judge a lane
	# change against, and no amount of obstacle readability fixes that. Faintly
	# emissive so they survive both the bright day courses and a night sky.
	var seams := MeshInstance3D.new()
	seams.name = "Seams"
	seams.mesh = _seam_mesh()
	seams.material_override = VisualLibrary.emissive_material(
			Color(0.62, 0.78, 0.95), Color(0.36, 0.62, 0.92), 0.45, 0.7)
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(seams)
	var verge := MeshInstance3D.new()
	verge.name = "Verge"
	verge.mesh = _verge_mesh()
	verge.set_surface_override_material(0, VisualLibrary.ice_material(Color(0.60, 0.83, 0.98), 0.5))
	verge.set_surface_override_material(1, VisualLibrary.snow_material(Color(0.78, 0.85, 0.97), 0.3))
	verge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(verge)


## Everything beyond the drop-off. All MultiMesh, all shadowless, all distance
## faded: it exists to sell speed in peripheral vision and must never cost more
## than a handful of draw calls per chunk.
func _build_dressing(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
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
			VisualLibrary.rock_material(Color.WHITE, 0.85), "Drifts", 170.0)
	var crystals: Array[Transform3D] = []
	for i: int in rng.randi_range(2, 5):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(1.1, 2.9)
		crystals.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.8, s, s * 0.8)),
				Vector3(side * rng.randf_range(RunnerConfig.DECK_HALF_WIDTH + 1.4, SHELF_WIDTH * 0.6),
						shelf_y - 0.25, -rng.randf() * RunnerConfig.CHUNK_LENGTH)))
	_add_multimesh(chunk, VisualLibrary.ice_crystal_mesh(), crystals,
			VisualLibrary.rock_material(Color.WHITE, 0.25), "Crystals", 170.0)
	# Distant bergs only on some chunks, and only ever ONE seeded silhouette per
	# chunk: berg_mesh() caches per seed, so drawing a fresh seed every chunk
	# would grow that cache without bound over a long run.
	if rng.randf() < 0.55:
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
				VisualLibrary.rock_material(Color.WHITE, 0.6), "Bergs", 900.0)


func _add_multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D],
		material: Material, name_hint: String, range_base: float) -> void:
	if transforms.is_empty():
		return
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


## Shared vertex-colour material for obstacles, fish and props. rock_material
## multiplies baked vertex colours into the tint, which is how one material can
## carry a dark ice block, a hot-orange fin and a pale ice ridge at once.
static func _prop_material() -> StandardMaterial3D:
	return VisualLibrary.rock_material(Color.WHITE, 0.42)


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


## Knee-high ice ridge, ONE metre wide so a caller can scale it to any span.
## Wedge-shaped with the ramp facing the player: the shape says "hop me", and
## the bright crown line is what the player actually times the jump against.
static func _low_mesh() -> ArrayMesh:
	if _low_mesh_cache != null:
		return _low_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hz := LOW_DEPTH * 0.5
	var foot := Color(0.18, 0.26, 0.38)
	var crown := Color(0.96, 0.72, 0.26)
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
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var cx := sign_x * (half - 0.3)
		_box_faces(st, Vector3(cx - 0.28, 0.0, -0.32), Vector3(cx + 0.28, y1, 0.32), foot, crown)
	st.generate_normals()
	_arch_mesh_cache = st.commit()
	return _arch_mesh_cache


## Runner fish. The racing game's FishPickup is not instanced here on purpose:
## it types a Racer member, wires itself onto the racing collision layers and
## reads the racing accessibility settings, and it draws three surfaces (body,
## fin and eye shaders) per fish -- three draw calls each, where a run can have
## eighty fish in view at once. This is the same silhouette (fusiform body,
## dark dorsal over silver belly, oversized hot-orange tail and dorsal fin)
## folded into ONE vertex-coloured surface, so a whole chunk's fish are a
## single MultiMesh draw.
static func _fish_mesh() -> ArrayMesh:
	if _fish_mesh_cache != null:
		return _fish_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dorsal := Color(0.10, 0.18, 0.28)
	var silver := Color(0.97, 0.96, 0.92)
	var fin := Color(1.0, 0.40, 0.08)
	var rings := 7
	var segs := 6
	var ring_pts: Array[PackedVector3Array] = []
	for i: int in rings + 1:
		var t := float(i) / float(rings)
		var x := lerpf(-0.30, 0.26, t)
		var r := maxf(0.155 * pow(maxf(sin(PI * pow(t, 0.72)), 0.0), 0.85), 0.005)
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
					_fish_tone(a, dorsal, silver), _fish_tone(b, dorsal, silver),
					_fish_tone(c, dorsal, silver), _fish_tone(d, dorsal, silver))
	# Forked tail and dorsal fin, emitted both ways round so a flat blade still
	# shows under a single-sided material.
	_flat_fin(st, Vector3(0.22, 0.0, 0.0), Vector3(0.52, 0.26, 0.0), Vector3(0.36, 0.04, 0.0), fin)
	_flat_fin(st, Vector3(0.22, 0.0, 0.0), Vector3(0.36, -0.04, 0.0), Vector3(0.52, -0.26, 0.0), fin)
	_flat_fin(st, Vector3(-0.08, 0.09, 0.0), Vector3(0.04, 0.34, 0.0), Vector3(0.15, 0.09, 0.0), fin)
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

	var index: int = 0
	var difficulty: float = 0.0
	## Blocked-lane count per obstacle row, keyed by rounded local z. This is
	## what makes "never fill all three lanes" enforceable without every pattern
	## having to reason about it.
	var rows: Dictionary = {}
	var contact_patches: Array[Transform3D] = []
	## Fish are drawn as ONE MultiMesh for the whole chunk; each RunnerFish
	## Area3D knows only its instance index, and collecting collapses that
	## instance to zero scale.
	var fish_base: Array[Transform3D] = []
	var fish_alive: PackedByteArray = PackedByteArray()
	var fish_mm: MultiMesh = null
	var _anim_time: float = 0.0

	func note_row(local_z: float, is_block: bool, span: int) -> void:
		if not is_block:
			return
		var key := int(round(local_z))
		rows[key] = int(rows.get(key, 0)) + span

	func row_blocked_lanes(local_z: float) -> int:
		return int(rows.get(int(round(local_z)), 0))

	## Claims a MultiMesh slot for a fish about to be added and returns its
	## index. Deliberately takes a position rather than the fish node, so the
	## chunk never has to name the pickup class and the two inner classes stay
	## a one-way dependency.
	func reserve_fish_slot(pos: Vector3) -> int:
		var slot := fish_base.size()
		# Baked yaw variety: with the whole chunk in one MultiMesh there is no
		# per-fish node to rotate, so the spread comes from the instance index.
		fish_base.append(Transform3D(Basis(Vector3.UP, float(slot) * 1.31), pos))
		fish_alive.append(1)
		return slot

	## Flushes the collected fish and contact-shadow instances into their
	## MultiMeshes. Called once, after the chunk's pattern has run; null meshes
	## mean headless, where the colliders still exist but nothing is drawn.
	func finish(fish_mesh: Mesh, fish_material: Material, patch_mesh: Mesh, patch_material: Material) -> void:
		if fish_mesh != null and not fish_base.is_empty():
			fish_mm = MultiMesh.new()
			fish_mm.transform_format = MultiMesh.TRANSFORM_3D
			fish_mm.mesh = fish_mesh
			fish_mm.instance_count = fish_base.size()
			for i: int in fish_base.size():
				fish_mm.set_instance_transform(i, fish_base[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Fish"
			mmi.multimesh = fish_mm
			mmi.material_override = fish_material
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
		set_process(fish_mm != null)
		if patch_mesh != null and not contact_patches.is_empty():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = patch_mesh
			mm.instance_count = contact_patches.size()
			for i: int in contact_patches.size():
				mm.set_instance_transform(i, contact_patches[i])
			var patches := MultiMeshInstance3D.new()
			patches.name = "Contact"
			patches.multimesh = mm
			patches.material_override = patch_material
			patches.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(patches)
		contact_patches.clear()

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

	## Bob and spin, driven for the whole chunk at once. A dozen instance-
	## transform writes per chunk per frame is far cheaper than a node and a
	## script callback per fish, and a collectable that sits perfectly still is
	## the fastest way to make a pickup read as scenery.
	func _process(delta: float) -> void:
		if fish_mm == null:
			return
		_anim_time += delta
		for i: int in fish_base.size():
			if fish_alive[i] == 0:
				continue
			var base := fish_base[i]
			var phase := float(i) * 1.31
			var bob := sin(_anim_time * 2.4 + phase) * 0.13
			fish_mm.set_instance_transform(i, Transform3D(
					Basis(Vector3.UP, phase + _anim_time * 0.9),
					base.origin + Vector3(0.0, bob, 0.0)))


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
