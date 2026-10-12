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
## tumble past the verge, gulls drift overhead, the fish bob and spin, powerups
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
## Late stream probes own a bounded namespace; prior races cannot evict them.
## Retry keeps cached resources/registrations rather than clearing any registry.
const SHADER_WARMUP_SCOPE: StringName = &"runner"
const PAINTED_SURFACE_SHADER: Shader = preload("res://assets/art/runner/materials/runner_painted_surface_v1.gdshader")
const PAINTED_ICE_TEXTURE: String = "res://assets/art/runner/textures/runner_crystal_ice_v2.webp"
const PAINTED_SNOW_TEXTURE: String = "res://assets/art/runner/textures/runner_painted_snow_v1.webp"
const ReferenceIce = preload("res://scripts/runner/runner_reference_ice.gd")
const ReferenceWalls = preload("res://scripts/runner/runner_reference_walls.gd")

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
## Two renderer-stable light fixtures per tunnel chunk. They are unshaded
## vertex-colour geometry plus broad floor washes on the already-warm mark
## signature: no dynamic Light3D RIDs, no changing clustered-light count.
const TUNNEL_LIGHT_CUES_PER_CHUNK: int = 2

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
const WARMUP_CHUNKS: int = 4
## First ~25 seconds teach lane choice and reward ramps before mandatory
## jump/slide rows or moving seals enter the pattern pool.
const INTRO_CHUNKS: int = 12
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
const MAX_SPAWNS_PER_UPDATE: int = 1
## Rendered streaming assembles one detached chunk over several frames. Time is
## the primary guard; the unit cap also makes scheduling bounded on very fast
## machines where a millisecond clock may not advance between tiny operations.
## One unit is at most one deck cassette, dressing family, obstacle, seal,
## power-up, or fish collider -- never an entire chunk phase.
const STREAM_BUILD_BUDGET_USEC: int = 4000
const STREAM_BUILD_MAX_UNITS_PER_UPDATE: int = 4
const STREAM_DECK_STAGE_COUNT: int = 5
const STREAM_DRESSING_STAGE_COUNT: int = 11
## A spent chunk exits collision/groups atomically, but releasing all of its
## MultiMesh buffers and branches together needlessly concentrates destruction
## in one browser callback. Dispose only a few already-detached branches on
## later quiet updates. The indivisible branch can exceed this time budget.
const STREAM_DISPOSE_BUDGET_USEC: int = 4000
const STREAM_DISPOSE_MAX_BRANCHES_PER_UPDATE: int = 4
## Medium/low keep all gameplay colliders but stop submitting geometry beyond
## their authored far-chunk budgets. Both remain well past the 70 m decision
## horizon; high stays uncapped.
const MEDIUM_VISUAL_RANGE: float = RunnerConfig.CHUNK_LENGTH * 5.5
const LOW_VISUAL_RANGE: float = RunnerConfig.CHUNK_LENGTH * 4.5
## Distance over which RunnerGame ramps difficulty from 0 to 1. Mirrored here
## rather than imported because the streamer has to answer "how fast will the
## player be going when they reach this chunk" while building it -- see
## _speed_estimate(), which is what lets a ramp's fish arc be laid along the
## trajectory the player will actually fly.
const DIFFICULTY_DISTANCE: float = 2600.0

## --- Biomes -----------------------------------------------------------------
## Metres of running per biome band. Long enough to settle into (25-40 seconds
## depending on speed), short enough that a five-minute run sees all four.
const BIOME_LENGTH: float = RunnerConfig.BIOME_LENGTH
const BIOME_COUNT: int = 4
## Internal showcase: ten authored pattern chunks, exactly 360 metres, all DAY.
## It is entered only through setup_golden_slice(); normal streaming never sees
## this list or its test RNG stream.
const GOLDEN_SLICE_CHUNKS: int = 10
const GOLDEN_SLICE_LENGTH: float = GOLDEN_SLICE_CHUNKS * RunnerConfig.CHUNK_LENGTH

## Authored DAY vertical-slice roles. IDs remain data-owned through RunnerArtSet;
## constants are lookup keys only, never direct resource paths. Missing catalog
## entries fall back per role, so one bad import cannot blank gameplay.
const DAY_DECK_ASSET: String = "runner_day_deck_kerb_v1"
const DAY_DECK_B_ASSET: String = "runner_day_deck_kerb_b_v1"
const DAY_DECK_C_ASSET: String = "runner_day_deck_kerb_c_v1"
const DAY_DECK_ASSETS: PackedStringArray = [
	DAY_DECK_ASSET, DAY_DECK_B_ASSET, DAY_DECK_C_ASSET,
]
const DAY_GANTRY_ASSET: String = "runner_day_gantry_v1"
const DAY_LAB_ASSET: String = "runner_day_research_lab_v1"
const DAY_PYLON_ASSET: String = "runner_day_signal_pylon_v1"
const DAY_SNOWCAT_ASSET: String = "runner_day_snowcat_v1"
const DAY_CARGO_ASSET: String = "runner_day_cargo_stack_v1"
const DAY_RAMP_ASSET: String = "runner_day_ramp_v1"
const DAY_BARRIER_ASSET: String = "runner_day_barrier_v1"
const DAY_TUNNEL_ASSET: String = "runner_day_tunnel_shell_v1"
const DAY_ICEBERG_ASSET: String = "runner_day_iceberg_cluster_v1"
const DAY_RADAR_ASSET: String = "runner_day_radar_landmark_v1"
const DAY_HUB_ASSET: String = "runner_day_research_hub_landmark_v1"
const DAY_ICEBREAKER_ASSET: String = "runner_day_icebreaker_landmark_v1"
const DAY_SURFACE_MATERIAL_ASSET: String = "runner_day_surface_material_v1"
const DAY_SHELL_MATERIAL_ASSET: String = "runner_day_shell_material_v1"
## Source deck top is z=0.245 m before glTF axis conversion. Runtime lowers it
## to gameplay y=0; modeled cap then lands at 1.305 m, where near props sit.
const AUTHORED_DAY_DECK_Y: float = -0.245
const AUTHORED_DAY_KERB_TOP: float = 1.305
const DAY_KIT_ASSETS: PackedStringArray = [
	DAY_DECK_ASSET, DAY_DECK_B_ASSET, DAY_DECK_C_ASSET,
	DAY_GANTRY_ASSET, DAY_LAB_ASSET, DAY_PYLON_ASSET,
	DAY_SNOWCAT_ASSET, DAY_CARGO_ASSET, DAY_RAMP_ASSET, DAY_BARRIER_ASSET,
	DAY_TUNNEL_ASSET, DAY_ICEBERG_ASSET,
	DAY_RADAR_ASSET, DAY_HUB_ASSET, DAY_ICEBREAKER_ASSET,
]
## Runner-scoped warmup probes are bounded and survive scene changes. Late/far
## DAY buffers precede opening decks; every known pair fits the independent
## 32-entry runner budget even after another mode fills its legacy registry.
const DAY_WARMUP_ASSETS: PackedStringArray = [
	DAY_HUB_ASSET, DAY_ICEBREAKER_ASSET, DAY_RADAR_ASSET,
	DAY_TUNNEL_ASSET, DAY_ICEBERG_ASSET,
	DAY_GANTRY_ASSET, DAY_SNOWCAT_ASSET, DAY_BARRIER_ASSET, DAY_RAMP_ASSET,
	DAY_LAB_ASSET, DAY_PYLON_ASSET, DAY_CARGO_ASSET,
	DAY_DECK_ASSET, DAY_DECK_B_ASSET, DAY_DECK_C_ASSET,
]

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

const PERF_PATTERN_NAMES: PackedStringArray = [
	"open", "lane_weave", "slide_gallery", "jump_stutter", "fish_arc",
	"mixed_gauntlet", "pinch", "seal_slide", "tunnel", "ramp_run",
]
const PERF_BIOME_NAMES: PackedStringArray = ["day", "dusk", "cave", "night"]
## Opt-in diagnostics only. Census enables this before runner construction;
## normal gameplay takes one predictable false branch per streamed chunk.
static var perf_trace_enabled: bool = false
const PERF_TRACE_MAX_EVENTS: int = 256

## --- Static art cache -------------------------------------------------------
## One instance of each, shared by every chunk of every run in the process.
static var _deck_mesh_cache: PlaneMesh = null
static var _seam_mesh_cache: ArrayMesh = null
static var _verge_mesh_cache: ArrayMesh = null
static var _authored_day_shelf_mesh_cache: ArrayMesh = null
static var _low_mesh_cache: ArrayMesh = null
static var _arch_mesh_cache: ArrayMesh = null
static var _fish_mesh_cache: ArrayMesh = null
static var _ramp_mesh_cache: ArrayMesh = null
static var _seal_mesh_cache: ArrayMesh = null
static var _tunnel_mesh_cache: ArrayMesh = null
static var _tunnel_light_cue_mesh_cache: ArrayMesh = null
static var _mark_mesh_cache: ArrayMesh = null
static var _banner_mesh_cache: ArrayMesh = null
static var _bird_mesh_cache: ArrayMesh = null
static var _shard_mesh_cache: ArrayMesh = null
static var _curtain_mesh_cache: ArrayMesh = null
static var _port_prop_mesh_cache: ArrayMesh = null
static var _research_module_mesh_cache: ArrayMesh = null
static var _radar_landmark_mesh_cache: ArrayMesh = null
static var _crane_landmark_mesh_cache: ArrayMesh = null
static var _icebreaker_landmark_mesh_cache: ArrayMesh = null
static var _powerup_ring_mesh_cache: TorusMesh = null
static var _crate_meshes: Dictionary = {}
static var _powerup_materials: Dictionary = {}
static var _fish_material_cache: StandardMaterial3D = null
static var _mark_material_cache: StandardMaterial3D = null
static var _painted_surface_cache: Dictionary = {}
static var _painted_texture_cache: Dictionary = {}
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
var _golden_slice: bool = false
var _dressing_density: float = 1.0
var _dressing_range_scale: float = 0.0
var _runner_art_set: RunnerArtSet = null
var _art_catalog: ArtCatalog = null
var _authored_day_meshes: Dictionary = {}
var _authored_day_surface_material: Material = null
var _authored_day_shell_material: Material = null
var _perf_trace_events: Array[Dictionary] = []
var _perf_last_tunnel_lights: int = -1
var _stream_job: StreamBuildJob = null
var _retiring_chunks: Array[RunnerChunk] = []
var _live_range_pending: Array[RunnerChunk] = []


enum StreamBuildPhase {
	DECK,
	DRESSING,
	TUNNEL,
	PATTERN,
	POWERUP,
	FINISH,
	RANGE,
	COMMIT,
}


## Detached build state. Only one exists, so the track's cross-chunk fairness
## cursors advance in exactly the same order as synchronous generation.
class StreamBuildJob:
	extends RefCounted
	var chunk: RunnerChunk = null
	var index: int = 0
	var difficulty: float = 0.0
	var pattern: int = 0
	var rng: RandomNumberGenerator = null
	var art_rng: RandomNumberGenerator = null
	var phase: int = 0
	var step: int = 0
	var pattern_work: Dictionary = {}
	var stage_cpu_us: Dictionary = {}
	var started_usec: int = 0
	var frames: int = 0
	var units: int = 0
	var max_unit_us: int = 0
	var current_unit: String = "reserved"
	var elapsed_seconds: float = 0.0


## --- Public API -------------------------------------------------------------

func _init() -> void:
	# Streaming enables this only while a detached job exists. Its delta is the
	# same presentation clock moving hazards would have received had the chunk
	# been committed synchronously on reservation.
	set_process(false)


func _process(delta: float) -> void:
	if _stream_job != null:
		_stream_job.elapsed_seconds += delta
	# Changing every resident instance from the settings callback concentrates
	# render-server writes into one frame. One existing chunk per frame keeps
	# adaptation bounded; all ranges use the newest profile if it changes again.
	if not _live_range_pending.is_empty():
		var chunk := _live_range_pending.pop_front() as RunnerChunk
		if is_instance_valid(chunk) and chunk in _chunks:
			chunk.apply_visual_range(_chunk_visual_range(),
					_dressing_density, _dressing_range_scale)
	set_process(_stream_job != null or not _live_range_pending.is_empty())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cancel_stream_chunk()
		_clear_retiring_chunks()

## Builds the opening run of chunks from z = 0 heading toward -Z. Also primes
## the static mesh cache, so the first STREAMED chunk of a run never pays for
## mesh construction mid-frame -- the whole cost lands here, during the load.
func setup(seed_value: int, dressing_density: float = 1.0,
		visuals_override: int = -1) -> void:
	if perf_trace_enabled:
		_perf_trace_events.clear()
		_perf_last_tunnel_lights = -1
	_headless = GameConfig.is_headless() if visuals_override < 0 else visuals_override == 0
	_seed = seed_value
	_golden_slice = false
	_dressing_density = clampf(dressing_density, 0.0, 1.0)
	_dressing_range_scale = VisualLibrary.dressing_range_scale()
	_clear()
	_resolve_art_context()
	if not _headless:
		_prime_art_cache()
	for i: int in RunnerConfig.CHUNKS_AHEAD:
		_spawn_chunk(i, 0.0)
	if not _headless:
		_build_start_apron()
	if perf_trace_enabled:
		_trace_tunnel_light_state(0)


## Frees every live chunk and rebuilds from z = 0. Used by "retry" so a restart
## costs a couple of milliseconds instead of a scene reload.
func reset(seed_value: int, dressing_density: float = -1.0) -> void:
	setup(seed_value, _dressing_density if dressing_density < 0.0 else dressing_density)


## A quality change affects the current run without rebuilding any gameplay.
## Reserved chunks retain their art-density snapshot; their final submission
## ranges still use the latest profile when committed. Existing geometry only
## changes its authored visibility ranges, never meshes, materials or colliders.
func set_dressing_density(dressing_density: float) -> void:
	var density := clampf(dressing_density, 0.0, 1.0)
	var range_scale := VisualLibrary.dressing_range_scale()
	if density == _dressing_density and range_scale == _dressing_range_scale:
		return
	_dressing_density = density
	_dressing_range_scale = range_scale
	if _headless:
		return
	_live_range_pending.assign(_chunks)
	set_process(not _live_range_pending.is_empty() or _stream_job != null)
	# The range phase may have run before a setting change in this frame. Apply
	# the latest profile again at commit; do not touch the detached build job.


## Injection seam used by isolated art-gallery/contract tests. Runtime obtains
## the same objects from RunnerGame after its staged ArtCatalog preload.
func configure_art(art_set: RunnerArtSet, catalog: ArtCatalog) -> void:
	_runner_art_set = art_set
	_art_catalog = catalog
	_authored_day_meshes.clear()
	_authored_day_surface_material = null
	_authored_day_shell_material = null


## Deterministic full-vocabulary showcase used by capture and regression tests.
## `visuals_override`: -1 follows runtime, 0 logic-only, 1 builds rendered art.
## Separate test/art RNGs guarantee dressing can never perturb gameplay layout.
func setup_golden_slice(seed_value: int = 20260818, visuals_override: int = -1) -> void:
	_headless = GameConfig.is_headless() if visuals_override < 0 else visuals_override == 0
	_seed = seed_value
	_golden_slice = true
	_dressing_density = 1.0
	_dressing_range_scale = VisualLibrary.dressing_range_scale()
	_clear()
	_resolve_art_context()
	if not _headless:
		_prime_art_cache()
	var patterns: Array[int] = [
		Pattern.OPEN,
		Pattern.LANE_WEAVE,
		Pattern.SLIDE_GALLERY,
		Pattern.JUMP_STUTTER,
		Pattern.FISH_ARC,
		Pattern.MIXED_GAUNTLET,
		Pattern.PINCH,
		Pattern.SEAL_SLIDE,
		Pattern.TUNNEL,
		Pattern.RAMP_RUN,
	]
	for index: int in GOLDEN_SLICE_CHUNKS:
		_spawn_golden_chunk(index, patterns[index], 0.72)


## Keeps CHUNKS_AHEAD chunks in front of the player and drops what is spent.
## difficulty is 0 at the start of a run and approaches 1 as it gets long; it
## raises obstacle density, unlocks the nastier patterns and tightens spacing.
func update_stream(player_z: float, difficulty: float) -> void:
	if _golden_slice:
		return
	var trace := perf_trace_enabled
	var stream_started := Time.get_ticks_usec() if trace or not _headless else 0
	var diff := clampf(difficulty, 0.0, 1.0)
	var current := _chunk_index_at(player_z)
	var spawned := 0
	var spawned_indices: Variant = PackedInt32Array() if trace else null
	if _headless:
		# Simulations and setup fixtures keep the original synchronous contract.
		while _next_index < current + RunnerConfig.CHUNKS_AHEAD \
				and spawned < MAX_SPAWNS_PER_UPDATE:
			if trace:
				spawned_indices.append(_next_index)
			_spawn_chunk(_next_index, diff)
			spawned += 1
	else:
		if _stream_job == null \
				and _next_index < current + RunnerConfig.CHUNKS_AHEAD:
			_reserve_stream_chunk(_next_index, diff)
		if _stream_job != null:
			var committed_index := _advance_stream_chunk()
			if committed_index >= 0:
				spawned = 1
				if trace:
					spawned_indices.append(committed_index)
	var cull_before := current - RunnerConfig.CHUNKS_BEHIND
	var retired := 0
	var retired_indices: Variant = PackedInt32Array() if trace else null
	while not _chunks.is_empty() and _first_index < cull_before:
		var spent: RunnerChunk = _chunks.pop_front()
		if trace:
			retired_indices.append(spent.index)
		if _headless:
			_free_chunk(spent)
		else:
			_retire_stream_chunk(spent)
		_first_index += 1
		retired += 1
	# Commit and detachment keep their exact atomic lifetime contract. Buffer
	# destruction gets a separate update rather than joining either tree change.
	if not _headless and spawned == 0 and retired == 0:
		var remaining_usec := STREAM_BUILD_BUDGET_USEC \
				- (Time.get_ticks_usec() - stream_started)
		if remaining_usec > 0:
			_advance_stream_disposal(mini(remaining_usec, STREAM_DISPOSE_BUDGET_USEC))
	var stream_changed := spawned > 0 or retired > 0
	if trace and stream_changed:
		_push_perf_trace({
			"kind": "stream",
			"current_chunk": current,
			"current_biome": _biome_for(current),
			"spawned": spawned,
			"spawned_indices": spawned_indices,
			"retired": retired,
			"retired_indices": retired_indices,
			"live_chunks": _chunks.size(),
			"next_chunk": _next_index,
			"cpu_us": Time.get_ticks_usec() - stream_started,
		})
		_trace_tunnel_light_state(current)


## Drained by material_census. Events stay bounded if a diagnostic consumer
## disappears mid-run, and never exist in production unless explicitly armed.
func drain_perf_trace_events() -> Array[Dictionary]:
	var events := _perf_trace_events.duplicate(true)
	_perf_trace_events.clear()
	return events


func perf_trace_snapshot(player_z: float) -> Dictionary:
	var current := _chunk_index_at(player_z)
	var tunnel_chunks := 0
	for chunk: RunnerChunk in _chunks:
		if chunk.pattern == Pattern.TUNNEL:
			tunnel_chunks += 1
	var pending := _stream_job != null
	return {
		"current_chunk": current,
		"current_biome": _biome_for(current),
		"live_chunks": _chunks.size(),
		"first_chunk": _first_index,
		"next_chunk": _next_index,
		"tunnel_chunks": tunnel_chunks,
		"tunnel_lights": 0,
		"tunnel_light_cues": tunnel_chunks * TUNNEL_LIGHT_CUES_PER_CHUNK,
		"stream_build_pending": pending,
		"stream_build_chunk": _stream_job.index if pending else -1,
		"stream_build_phase": _stream_job.current_unit if pending else "",
		"stream_build_units": _stream_job.units if pending else 0,
		"stream_dispose_pending_chunks": _retiring_chunks.size(),
	}


func _push_perf_trace(event: Dictionary) -> void:
	if not perf_trace_enabled:
		return
	event["frame"] = Engine.get_process_frames()
	_perf_trace_events.append(event)
	if _perf_trace_events.size() > PERF_TRACE_MAX_EVENTS:
		_perf_trace_events.pop_front()


func _trace_tunnel_light_state(current_chunk: int) -> void:
	var resident_tunnel_chunks := 0
	for chunk: RunnerChunk in _chunks:
		if chunk.pattern == Pattern.TUNNEL:
			resident_tunnel_chunks += 1
	var cue_count := resident_tunnel_chunks * TUNNEL_LIGHT_CUES_PER_CHUNK
	if cue_count == _perf_last_tunnel_lights:
		return
	_perf_last_tunnel_lights = cue_count
	_push_perf_trace({
		"kind": "tunnel_static_cues",
		"current_chunk": current_chunk,
		"resident_tunnel_chunks": resident_tunnel_chunks,
		"active_tunnel_lights": 0,
		"static_light_cues": cue_count,
	})


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
##
## The numbers obey the same three-value law the deck palette does (see the
## PALETTE block further down). Two consequences worth stating, because both
## look like mistakes until you see them rendered:
##   * ambient remains below the original flat 0.74 fill, but DAY now carries
##     more fill and a softer sun than the V5 geometry proof. Its hard 1.55 sun
##     crushed cream portal undersides and orange snowcats into navy silhouettes
##     before the atlas response could read. The 1.08/0.56 balance plus the
##     opposing cool fill preserves modeled seams while keeping shadow-side
##     paint inside the medium tier.
##   * ground_horizon is DARKER than sky_horizon. The sky's ground half was
##     previously assigned the horizon colour, which dissolved the horizon
##     line -- and a runner with no horizon line has no vanishing point to
##     read speed against.
## Keys past "ambient" are advisory: whoever owns the WorldEnvironment can read
## them or ignore them, and nothing here breaks if it only consumes the six the
## original dictionary carried.
static func biome_environment(biome: int) -> Dictionary:
	match biome:
		Biome.DUSK:
			return {
				"sky_top": Color(0.20, 0.09, 0.44),
				"sky_horizon": Color(1.0, 0.46, 0.24),
				"ground_horizon": Color(0.72, 0.28, 0.26),
				"ground_bottom": Color(0.26, 0.10, 0.24),
				"sun": Color(1.0, 0.60, 0.32),
				"sun_energy": 1.30,
				"fog": Color(1.0, 0.46, 0.24),
				"fog_density": 0.0020,
				"ambient": 0.34,
				"shaft": Color(1.0, 0.72, 0.42),
			}
		Biome.CAVE:
			return {
				"sky_top": Color(0.01, 0.05, 0.12),
				"sky_horizon": Color(0.06, 0.30, 0.46),
				"ground_horizon": Color(0.04, 0.18, 0.30),
				"ground_bottom": Color(0.01, 0.06, 0.14),
				"sun": Color(0.55, 0.82, 1.0),
				"sun_energy": 0.55,
				"fog": Color(0.04, 0.18, 0.32),
				"fog_density": 0.0030,
				"ambient": 0.26,
				"shaft": Color(0.40, 0.86, 1.0),
			}
		Biome.NIGHT:
			return {
				"sky_top": Color(0.01, 0.02, 0.10),
				"sky_horizon": Color(0.05, 0.12, 0.34),
				"ground_horizon": Color(0.03, 0.08, 0.24),
				"ground_bottom": Color(0.01, 0.02, 0.12),
				"sun": Color(0.62, 0.76, 1.0),
				"sun_energy": 0.42,
				"fog": Color(0.04, 0.10, 0.28),
				"fog_density": 0.0024,
				"ambient": 0.24,
				"shaft": Color(0.42, 1.0, 0.74),
			}
		_:
			return {
				"sky_top": Color(0.02, 0.42, 1.0),
				"sky_horizon": Color(0.18, 0.70, 1.0),
				"ground_horizon": Color(0.10, 0.43, 0.72),
				"ground_bottom": Color(0.025, 0.22, 0.47),
				"sun": Color(1.0, 0.98, 0.92),
				"sun_energy": 0.25,
				"fog": Color(0.34, 0.72, 0.96),
				"fog_density": 0.0020,
				"ambient": 0.56,
				"shaft": Color(0.96, 0.94, 0.86),
			}


## RunnerGame owns staged loading; RunnerTrack consumes its resolved contract.
## Keeping discovery here avoids a new gameplay dependency or scene rewrite.
func _resolve_art_context() -> void:
	if _runner_art_set != null and _art_catalog != null:
		return
	var owner := get_parent()
	if owner == null or not owner.has_method("_initialize_art_foundation"):
		return
	var art_set_value: Variant = owner.get("_runner_art_set")
	var catalog_value: Variant = owner.get("_art_catalog")
	if art_set_value is RunnerArtSet:
		_runner_art_set = art_set_value as RunnerArtSet
	if catalog_value is ArtCatalog:
		_art_catalog = catalog_value as ArtCatalog


func _prime_authored_day_cache() -> void:
	if _runner_art_set == null or _art_catalog == null:
		return
	if _authored_day_meshes.size() == DAY_KIT_ASSETS.size() \
			and _authored_day_surface_material != null \
			and _authored_day_shell_material != null:
		return
	var declared := _runner_art_set.collect_preload_ids("day")
	for asset_id: String in DAY_WARMUP_ASSETS:
		if asset_id not in declared or not _art_catalog.has_asset(asset_id):
			continue
		var resource := _art_catalog.loaded_resource(asset_id)
		if resource == null:
			resource = _art_catalog.load_now(asset_id)
		var packed := resource as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate()
		var mesh := _first_scene_mesh(instance)
		instance.free()
		if mesh != null:
			_authored_day_meshes[asset_id] = mesh
	_authored_day_surface_material = _catalog_material(DAY_SURFACE_MATERIAL_ASSET)
	_authored_day_shell_material = _catalog_material(DAY_SHELL_MATERIAL_ASSET)


func _catalog_material(asset_id: String) -> Material:
	if _art_catalog == null or not _art_catalog.has_asset(asset_id):
		return null
	var resource := _art_catalog.loaded_resource(asset_id)
	if resource == null:
		resource = _art_catalog.load_now(asset_id)
	return resource as Material


static func _first_scene_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var direct := (node as MeshInstance3D).mesh
		if direct != null:
			return direct
	for child: Node in node.get_children():
		var found := _first_scene_mesh(child)
		if found != null:
			return found
	return null


func _authored_day_mesh(asset_id: String) -> Mesh:
	var source := _authored_day_meshes.get(asset_id, null) as Mesh
	if source != null and asset_id in DAY_DECK_ASSETS:
		return ReferenceWalls.deck_mesh(source)
	return source


func _authored_day_draw_material(asset_id: String) -> Material:
	return ReferenceWalls.material() if asset_id in DAY_DECK_ASSETS else _authored_day_material()


func _authored_day_material(shell: bool = false) -> Material:
	if shell and _authored_day_shell_material != null:
		return _authored_day_shell_material
	if _authored_day_surface_material != null:
		return _authored_day_surface_material
	return _tunnel_material() if shell else _prop_material()


## Focused tests and capture harnesses can prove exact seam coverage without
## depending on rendered pixels or private cache layout.
func authored_day_kit_status() -> Dictionary:
	var ids := PackedStringArray()
	for value: Variant in _authored_day_meshes.keys():
		ids.append(String(value))
	ids.sort()
	var materials_ready := _authored_day_surface_material != null \
			and _authored_day_shell_material != null
	return {
		"active": ids.size() == DAY_KIT_ASSETS.size() and materials_ready,
		"biome_scope": "day",
		"loaded": ids.size(),
		"expected": DAY_KIT_ASSETS.size(),
		"asset_ids": ids,
		"surface_material": _authored_day_surface_material != null,
		"shell_material": _authored_day_shell_material != null,
	}


## --- Streaming --------------------------------------------------------------

## Chunk containing a world z. Chunk i owns z in (-(i+1)*L, -i*L].
func _chunk_index_at(z: float) -> int:
	return int(floor(-z / RunnerConfig.CHUNK_LENGTH))


func _biome_for(index: int) -> int:
	var band := int(floor(float(index) * RunnerConfig.CHUNK_LENGTH / BIOME_LENGTH))
	return posmod(band, BIOME_COUNT)


func _clear() -> void:
	var old_apron := get_node_or_null("StartApron")
	if old_apron != null:
		remove_child(old_apron)
		old_apron.queue_free()
	_live_range_pending.clear()
	_cancel_stream_chunk()
	set_process(false)
	_clear_retiring_chunks()
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


func _retire_stream_chunk(chunk: RunnerChunk) -> void:
	if not is_instance_valid(chunk):
		return
	if chunk.get_parent() == self:
		remove_child(chunk)
	_retiring_chunks.append(chunk)


## Detached children are not visible, collidable, grouped or processing. Free
## direct branches rather than the whole subtree so each update releases at
## most a handful of render/physics resources. No new resource is allocated.
func _advance_stream_disposal(budget_usec: int = STREAM_DISPOSE_BUDGET_USEC) -> void:
	if _retiring_chunks.is_empty():
		return
	var started := Time.get_ticks_usec()
	var branches := 0
	var completed := 0
	var disposed_indices: Variant = PackedInt32Array() if perf_trace_enabled else null
	while not _retiring_chunks.is_empty() \
			and branches < STREAM_DISPOSE_MAX_BRANCHES_PER_UPDATE:
		var chunk: RunnerChunk = _retiring_chunks[0]
		if not is_instance_valid(chunk):
			_retiring_chunks.pop_front()
			continue
		# Node-owned references now control buffer lifetime individually. These
		# two animation references otherwise keep every MultiMesh until the last
		# branch, recreating the resource release burst at the end of disposal.
		chunk.fish_mm = null
		chunk._anim_mm.clear()
		if chunk.get_child_count() > 0:
			chunk.get_child(chunk.get_child_count() - 1).free()
			branches += 1
		else:
			# An already-empty root still consumes one bounded lifetime unit.
			branches += 1
		if chunk.get_child_count() == 0:
			if perf_trace_enabled:
				disposed_indices.append(chunk.index)
			_retiring_chunks.pop_front()
			chunk.free()
			completed += 1
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	if perf_trace_enabled:
		_push_perf_trace({
			"kind": "dispose",
			"branches": branches,
			"completed": completed,
			"disposed_indices": disposed_indices,
			"pending_chunks": _retiring_chunks.size(),
			"cpu_us": Time.get_ticks_usec() - started,
		})


func _clear_retiring_chunks() -> void:
	for chunk: RunnerChunk in _retiring_chunks:
		if is_instance_valid(chunk):
			chunk.free()
	_retiring_chunks.clear()


func _cancel_stream_chunk() -> void:
	if _stream_job == null:
		return
	var detached := _stream_job.chunk
	_stream_job = null
	set_process(not _live_range_pending.is_empty())
	if not is_instance_valid(detached):
		return
	if detached.get_parent() != null:
		detached.get_parent().remove_child(detached)
	# This job is sole owner and no external reference can observe an
	# uncommitted chunk, so immediate destruction makes cancellation measurable.
	detached.free()


func _reserve_stream_chunk(index: int, difficulty: float) -> void:
	assert(_stream_job == null)
	assert(index == _next_index)
	var job := StreamBuildJob.new()
	job.started_usec = Time.get_ticks_usec()
	job.index = index
	job.difficulty = difficulty
	job.chunk = RunnerChunk.new()
	job.chunk.name = "Chunk%d" % index
	job.chunk.index = index
	job.chunk.difficulty = difficulty
	job.chunk.dressing_density = _dressing_density
	job.chunk.dressing_range_scale = _dressing_range_scale
	job.chunk.biome = _biome_for(index)
	job.chunk.position = Vector3(0.0, 0.0, -float(index) * RunnerConfig.CHUNK_LENGTH)
	job.rng = _chunk_rng(index, 11)
	job.art_rng = _chunk_rng(index, 60493)
	# Reservation owns the same first RNG/state mutation as _spawn_chunk(). No
	# later chunk can reserve until this one commits.
	job.pattern = _pick_pattern(job.rng, difficulty, index)
	job.chunk.pattern = job.pattern
	job.stage_cpu_us = {
		"select_us": Time.get_ticks_usec() - job.started_usec,
		"deck_us": 0,
		"dressing_us": 0,
		"tunnel_us": 0,
		"pattern_us": 0,
		"powerup_us": 0,
		"finish_us": 0,
		"range_us": 0,
		"commit_us": 0,
	}
	_stream_job = job
	set_process(true)
	if perf_trace_enabled:
		_push_perf_trace({
			"kind": "stream_stage",
			"chunk": index,
			"stage": "reserve",
			"cpu_us": int(job.stage_cpu_us["select_us"]),
		})


## Advances bounded small units and returns committed chunk index, or -1.
func _advance_stream_chunk() -> int:
	if _stream_job == null:
		return -1
	var job := _stream_job
	job.frames += 1
	var frame_started := Time.get_ticks_usec()
	var frame_units := 0
	while _stream_job == job and frame_units < STREAM_BUILD_MAX_UNITS_PER_UPDATE:
		var unit_started := Time.get_ticks_usec()
		var unit := _advance_stream_unit(job)
		var unit_us := Time.get_ticks_usec() - unit_started
		job.units += 1
		frame_units += 1
		job.max_unit_us = maxi(job.max_unit_us, unit_us)
		job.current_unit = String(unit["name"])
		var bucket := String(unit["bucket"])
		job.stage_cpu_us[bucket] = int(job.stage_cpu_us.get(bucket, 0)) + unit_us
		if perf_trace_enabled:
			_push_perf_trace({
				"kind": "stream_stage",
				"chunk": job.index,
				"stage": job.current_unit,
				"unit": job.units,
				"cpu_us": unit_us,
				"committed": bool(unit["committed"]),
			})
		if bool(unit["committed"]):
			if perf_trace_enabled:
				_push_staged_spawn_trace(job)
			_stream_job = null
			set_process(not _live_range_pending.is_empty())
			return job.index
		if Time.get_ticks_usec() - frame_started >= STREAM_BUILD_BUDGET_USEC:
			break
	return -1


func _advance_stream_unit(job: StreamBuildJob) -> Dictionary:
	match job.phase:
		StreamBuildPhase.DECK:
			var deck_step := job.step
			_build_deck_stage(job.chunk, job.pattern, deck_step)
			job.step += 1
			if job.step >= STREAM_DECK_STAGE_COUNT:
				job.phase = StreamBuildPhase.DRESSING
				job.step = 0
			return _stream_unit("deck_%d" % deck_step, "deck_us")
		StreamBuildPhase.DRESSING:
			var dressing_step := job.step
			_build_dressing_stage(job.chunk, job.art_rng, dressing_step)
			job.step += 1
			if job.step >= STREAM_DRESSING_STAGE_COUNT:
				job.phase = StreamBuildPhase.TUNNEL
				job.step = 0
			return _stream_unit("dressing_%d" % dressing_step, "dressing_us")
		StreamBuildPhase.TUNNEL:
			if job.pattern == Pattern.TUNNEL:
				_build_tunnel(job.chunk)
			job.phase = StreamBuildPhase.PATTERN
			return _stream_unit("tunnel", "tunnel_us")
		StreamBuildPhase.PATTERN:
			if job.pattern_work.is_empty():
				job.pattern_work = _create_pattern_work(
						job.pattern, job.chunk, job.rng, job.difficulty)
			var action_name := _pattern_work_unit_name(job.pattern_work)
			if _advance_pattern_work(job.pattern_work):
				_last_pattern = job.pattern
				job.phase = StreamBuildPhase.POWERUP
			return _stream_unit("pattern_%s" % action_name, "pattern_us")
		StreamBuildPhase.POWERUP:
			if job.index >= WARMUP_CHUNKS:
				_maybe_add_powerup(job.chunk, job.rng)
			job.phase = StreamBuildPhase.FINISH
			return _stream_unit("powerup", "powerup_us")
		StreamBuildPhase.FINISH:
			job.chunk.finish(false)
			job.phase = StreamBuildPhase.RANGE
			return _stream_unit("finish", "finish_us")
		StreamBuildPhase.RANGE:
			job.chunk.apply_visual_range(_chunk_visual_range(),
					_dressing_density, _dressing_range_scale)
			job.phase = StreamBuildPhase.COMMIT
			return _stream_unit("visual_range", "range_us")
		_:
			job.chunk.apply_visual_range(_chunk_visual_range(),
					_dressing_density, _dressing_range_scale)
			_prime_staged_movers(job.chunk, job.elapsed_seconds)
			add_child(job.chunk)
			_chunks.append(job.chunk)
			_next_index = job.index + 1
			return _stream_unit("commit", "commit_us", true)


static func _stream_unit(name_value: String, bucket: String,
		committed: bool = false) -> Dictionary:
	return {"name": name_value, "bucket": bucket, "committed": committed}


func _push_staged_spawn_trace(job: StreamBuildJob) -> void:
	var cpu_total := 0
	for key: String in ["select_us", "deck_us", "dressing_us", "tunnel_us",
			"pattern_us", "powerup_us", "finish_us", "range_us", "commit_us"]:
		cpu_total += int(job.stage_cpu_us.get(key, 0))
	_push_perf_trace({
		"kind": "spawn",
		"chunk": job.index,
		"biome": job.chunk.biome,
		"biome_name": PERF_BIOME_NAMES[job.chunk.biome],
		"pattern": job.pattern,
		"pattern_name": PERF_PATTERN_NAMES[job.pattern],
		"select_us": int(job.stage_cpu_us["select_us"]),
		"deck_us": int(job.stage_cpu_us["deck_us"]),
		"dressing_us": int(job.stage_cpu_us["dressing_us"]),
		"tunnel_us": int(job.stage_cpu_us["tunnel_us"]),
		"pattern_us": int(job.stage_cpu_us["pattern_us"]),
		"powerup_us": int(job.stage_cpu_us["powerup_us"]),
		"finish_us": int(job.stage_cpu_us["finish_us"]),
		"range_us": int(job.stage_cpu_us["range_us"]),
		"commit_us": int(job.stage_cpu_us["commit_us"]),
		"total_us": cpu_total,
		"staged_frames": job.frames,
		"work_units": job.units,
		"max_unit_us": job.max_unit_us,
	})


func _prime_staged_movers(node: Node, elapsed: float) -> void:
	if node is RunnerMover:
		(node as RunnerMover).prime_elapsed(elapsed)
	for child: Node in node.get_children():
		_prime_staged_movers(child, elapsed)


func _spawn_chunk(index: int, difficulty: float) -> void:
	var trace := perf_trace_enabled
	var total_started := Time.get_ticks_usec() if trace else 0
	var select_started := total_started
	var chunk := RunnerChunk.new()
	chunk.name = "Chunk%d" % index
	chunk.index = index
	chunk.difficulty = difficulty
	chunk.dressing_density = _dressing_density
	chunk.dressing_range_scale = _dressing_range_scale
	chunk.biome = _biome_for(index)
	chunk.position = Vector3(0.0, 0.0, -float(index) * RunnerConfig.CHUNK_LENGTH)
	add_child(chunk)
	# Seeded from (run seed, chunk index) rather than from a rolling stream, so
	# a chunk is identical however the streaming happened to be scheduled --
	# which is what makes a seeded run reproducible in a test.
	var rng := _chunk_rng(index, 11)
	var art_rng := _chunk_rng(index, 60493)
	# The pattern is chosen before the geometry because the deck and the roof
	# depend on it: a tunnel darkens its own floor.
	var pattern := _pick_pattern(rng, difficulty, index)
	chunk.pattern = pattern
	var select_us := Time.get_ticks_usec() - select_started if trace else 0
	var deck_us := 0
	var dressing_us := 0
	var tunnel_us := 0
	if not _headless:
		var stage_started := Time.get_ticks_usec() if trace else 0
		_build_deck(chunk, pattern)
		deck_us = Time.get_ticks_usec() - stage_started if trace else 0
		stage_started = Time.get_ticks_usec() if trace else 0
		_build_dressing(chunk, art_rng)
		dressing_us = Time.get_ticks_usec() - stage_started if trace else 0
		if pattern == Pattern.TUNNEL:
			stage_started = Time.get_ticks_usec() if trace else 0
			_build_tunnel(chunk)
			tunnel_us = Time.get_ticks_usec() - stage_started if trace else 0
	var pattern_started := Time.get_ticks_usec() if trace else 0
	_run_pattern(pattern, chunk, rng, difficulty)
	var pattern_us := Time.get_ticks_usec() - pattern_started if trace else 0
	_last_pattern = pattern
	# Crates go in last, so the placement can see every obstacle the pattern
	# actually managed to build rather than the ones it asked for.
	var powerup_started := Time.get_ticks_usec() if trace else 0
	if index >= WARMUP_CHUNKS:
		_maybe_add_powerup(chunk, rng)
	var powerup_us := Time.get_ticks_usec() - powerup_started if trace else 0
	var finish_started := Time.get_ticks_usec() if trace else 0
	chunk.finish(_headless)
	var finish_us := Time.get_ticks_usec() - finish_started if trace else 0
	var range_started := Time.get_ticks_usec() if trace else 0
	if not _headless:
		chunk.apply_visual_range(_chunk_visual_range(),
				_dressing_density, _dressing_range_scale)
	var range_us := Time.get_ticks_usec() - range_started if trace else 0
	_chunks.append(chunk)
	_next_index = index + 1
	if trace:
		_push_perf_trace({
			"kind": "spawn",
			"chunk": index,
			"biome": chunk.biome,
			"biome_name": PERF_BIOME_NAMES[chunk.biome],
			"pattern": pattern,
			"pattern_name": PERF_PATTERN_NAMES[pattern],
			"select_us": select_us,
			"deck_us": deck_us,
			"dressing_us": dressing_us,
			"tunnel_us": tunnel_us,
			"pattern_us": pattern_us,
			"powerup_us": powerup_us,
			"finish_us": finish_us,
			"range_us": range_us,
			"total_us": Time.get_ticks_usec() - total_started,
		})


func _chunk_rng(index: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed * 1000003 + index * 7919 + salt
	return rng


func _chunk_visual_range() -> float:
	if _dressing_density >= 0.99:
		return 0.0
	return MEDIUM_VISUAL_RANGE if _dressing_density >= 0.5 else LOW_VISUAL_RANGE


func _spawn_golden_chunk(index: int, pattern: int, difficulty: float) -> void:
	var chunk := RunnerChunk.new()
	chunk.name = "GoldenChunk%d" % index
	chunk.index = index
	chunk.difficulty = difficulty
	chunk.dressing_density = _dressing_density
	chunk.dressing_range_scale = _dressing_range_scale
	chunk.biome = Biome.DAY
	chunk.pattern = pattern
	chunk.set_meta("golden_pattern", pattern)
	chunk.position = Vector3(0.0, 0.0, -float(index) * RunnerConfig.CHUNK_LENGTH)
	add_child(chunk)
	var test_rng := _chunk_rng(index, 310019)
	var art_rng := _chunk_rng(index, 790043)
	if not _headless:
		_build_deck(chunk, pattern)
		_build_dressing(chunk, art_rng)
		if pattern == Pattern.TUNNEL:
			_build_tunnel(chunk)
	_run_pattern(pattern, chunk, test_rng, difficulty)
	if index == 0:
		_add_golden_powerup(chunk, RunnerConfig.POWERUP_MAGNET)
	elif index == 4:
		_add_golden_powerup(chunk, RunnerConfig.POWERUP_SHIELD)
	elif index == 8:
		_add_golden_powerup(chunk, RunnerConfig.POWERUP_DOUBLE)
	chunk.finish(_headless)
	_chunks.append(chunk)
	_next_index = index + 1
	_last_pattern = pattern


func _add_golden_powerup(chunk: RunnerChunk, id: StringName) -> void:
	for local_z: float in [-6.0, -15.0, -24.0, -31.0]:
		for lane: int in [1, 0, 2]:
			if chunk.lane_clear(local_z, lane, POWERUP_CLEARANCE):
				_add_powerup(chunk, lane, local_z, id)
				return


## --- Patterns ---------------------------------------------------------------

func _pick_pattern(rng: RandomNumberGenerator, difficulty: float, index: int) -> int:
	if index < WARMUP_CHUNKS:
		return Pattern.OPEN
	if index < INTRO_CHUNKS:
		# Same seeded art/gameplay RNG contract as the rest of the stream. Each
		# early chunk offers a safe route; no compulsory reflex verb yet.
		var introductory: Array[int] = [Pattern.FISH_ARC, Pattern.LANE_WEAVE,
			Pattern.OPEN, Pattern.RAMP_RUN]
		return introductory[rng.randi_range(0, introductory.size() - 1)]
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
	var work := _create_pattern_work(pattern, chunk, rng, difficulty)
	while not _advance_pattern_work(work):
		pass


## Pattern actions are deliberately lazy. RNG is consumed only when the
## corresponding original branch is reached; a refused obstacle can therefore
## still suppress a later conditional roll exactly as the synchronous builder
## did. Node-producing actions add one obstacle/seal/fish at most.
func _create_pattern_work(pattern: int, chunk: RunnerChunk,
		rng: RandomNumberGenerator, difficulty: float) -> Dictionary:
	var op := "open_init"
	match pattern:
		Pattern.LANE_WEAVE: op = "lane_weave_init"
		Pattern.SLIDE_GALLERY: op = "slide_init"
		Pattern.JUMP_STUTTER: op = "jump_init"
		Pattern.FISH_ARC: op = "fish_arc_init"
		Pattern.MIXED_GAUNTLET: op = "mixed_init"
		Pattern.PINCH: op = "pinch_init"
		Pattern.SEAL_SLIDE: op = "seal_init"
		Pattern.TUNNEL: op = "tunnel_init"
		Pattern.RAMP_RUN: op = "ramp_init"
	return {
		"chunk": chunk,
		"rng": rng,
		"difficulty": difficulty,
		"actions": [{"op": op}],
		"cursor": 0,
	}


func _pattern_work_unit_name(work: Dictionary) -> String:
	var cursor := int(work.get("cursor", 0))
	var actions: Array = work.get("actions", [])
	if cursor < 0 or cursor >= actions.size():
		return "done"
	var action: Dictionary = actions[cursor]
	return String(action.get("op", "unknown"))


func _advance_pattern_work(work: Dictionary) -> bool:
	var actions: Array = work["actions"]
	var cursor := int(work["cursor"])
	if cursor >= actions.size():
		return true
	var action: Dictionary = actions[cursor]
	var done := _execute_pattern_action(work, action)
	# Action may have inserted successors into work's queue.
	actions = work["actions"]
	actions[cursor] = action
	work["actions"] = actions
	if done:
		work["cursor"] = cursor + 1
	return int(work["cursor"]) >= actions.size()


func _pattern_insert_after(work: Dictionary, additions: Array) -> void:
	if additions.is_empty():
		return
	var actions: Array = work["actions"]
	var at := int(work["cursor"]) + 1
	for addition: Dictionary in additions:
		actions.insert(at, addition)
		at += 1
	work["actions"] = actions


static func _fish_line_action(lane: int, z_from: float, z_to: float, y: float) -> Dictionary:
	return {"op": "fish_line", "lane": lane, "z": z_from, "to": z_to, "y": y}


static func _fish_arc_action(lane: int, z: float, half_length: float) -> Dictionary:
	return {"op": "fish_arc", "lane": lane, "z": z,
		"half_length": half_length, "i": 0}


static func _fish_sweep_action(lane_from: int, lane_to: int, z_from: float,
		z_to: float, count: int, y: float) -> Dictionary:
	return {"op": "fish_sweep", "lane_from": lane_from, "lane_to": lane_to,
		"z_from": z_from, "z_to": z_to, "count": count, "y": y, "i": 0}


static func _fish_point_action(position: Vector3) -> Dictionary:
	return {"op": "fish_point", "position": position}


static func _obstacle_action(kind: int, lane: int, span: int, z: float,
		success: Array = []) -> Dictionary:
	return {"op": "obstacle", "kind": kind, "lane": lane, "span": span,
		"z": z, "success": success}


func _execute_pattern_action(work: Dictionary, action: Dictionary) -> bool:
	var chunk: RunnerChunk = work["chunk"]
	var rng: RandomNumberGenerator = work["rng"]
	var difficulty := float(work["difficulty"])
	var op := String(action["op"])
	match op:
		"fish_line":
			var z := float(action["z"])
			if z <= float(action["to"]):
				return true
			_add_fish(chunk, Vector3(RunnerConfig.lane_x(clampi(int(action["lane"]), 0,
					RunnerConfig.LANE_COUNT - 1)), float(action["y"]), z))
			action["z"] = z - FISH_SPACING
			return float(action["z"]) <= float(action["to"])
		"fish_arc":
			var arc_i := int(action["i"])
			if arc_i >= 5:
				return true
			var arc_t := (float(arc_i) / 2.0) - 1.0
			var arc_y := lerpf(FISH_ARC_APEX, FISH_Y, arc_t * arc_t)
			var arc_x := RunnerConfig.lane_x(clampi(int(action["lane"]), 0,
					RunnerConfig.LANE_COUNT - 1))
			_add_fish(chunk, Vector3(arc_x, arc_y,
					float(action["z"]) - arc_t * float(action["half_length"])))
			action["i"] = arc_i + 1
			return int(action["i"]) >= 5
		"fish_sweep":
			var count := int(action["count"])
			var sweep_i := int(action["i"])
			if count <= 1 or sweep_i >= count:
				return true
			var sweep_t := float(sweep_i) / float(count - 1)
			var x0 := RunnerConfig.lane_x(clampi(int(action["lane_from"]), 0,
					RunnerConfig.LANE_COUNT - 1))
			var x1 := RunnerConfig.lane_x(clampi(int(action["lane_to"]), 0,
					RunnerConfig.LANE_COUNT - 1))
			_add_fish(chunk, Vector3(lerpf(x0, x1, smoothstep(0.0, 1.0, sweep_t)),
					float(action["y"]), lerpf(float(action["z_from"]),
					float(action["z_to"]), sweep_t)))
			action["i"] = sweep_i + 1
			return int(action["i"]) >= count
		"ramp_fish":
			var ramp_i := int(action["i"])
			const RAMP_FISH_COUNT: int = 9
			if ramp_i >= RAMP_FISH_COUNT:
				return true
			var speed := _speed_estimate(difficulty)
			var air := 2.0 * RunnerConfig.RAMP_LAUNCH / RunnerConfig.GRAVITY
			var flight_t := air * lerpf(0.06, 0.82,
					float(ramp_i) / float(RAMP_FISH_COUNT - 1))
			var flight_y := RunnerConfig.RAMP_LAUNCH * flight_t \
					- 0.5 * RunnerConfig.GRAVITY * flight_t * flight_t
			_add_fish(chunk, Vector3(RunnerConfig.lane_x(clampi(int(action["lane"]), 0,
					RunnerConfig.LANE_COUNT - 1)),
					flight_y + RunnerConfig.STAND_HEIGHT * 0.5,
					float(action["lip_z"]) - speed * flight_t))
			action["i"] = ramp_i + 1
			return int(action["i"]) >= RAMP_FISH_COUNT
		"fish_point":
			_add_fish(chunk, action["position"])
			return true
		"obstacle":
			var placed := _add_obstacle(chunk, int(action["kind"]), int(action["lane"]),
					int(action["span"]), float(action["z"]))
			if placed:
				var success: Array = action.get("success", [])
				_pattern_insert_after(work, success)
			return true
		"seal_one":
			_add_seal(chunk, float(action["z"]), float(action["phase"]),
					float(action["period"]))
			return true
		"open_init":
			var lane_a := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
			var lane_b := lane_a
			if rng.randf() < 0.6:
				lane_b = clampi(lane_a + (1 if rng.randf() < 0.5 else -1), 0,
						RunnerConfig.LANE_COUNT - 1)
			var open_actions: Array = []
			if lane_b == lane_a:
				open_actions.append(_fish_line_action(lane_a, -3.0,
						-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y))
			else:
				open_actions.append(_fish_line_action(lane_a, -3.0,
						-RunnerConfig.CHUNK_LENGTH * 0.42, FISH_Y))
				open_actions.append(_fish_sweep_action(lane_a, lane_b,
						-RunnerConfig.CHUNK_LENGTH * 0.45,
						-RunnerConfig.CHUNK_LENGTH * 0.62, 4, FISH_Y))
				open_actions.append(_fish_line_action(lane_b,
						-RunnerConfig.CHUNK_LENGTH * 0.66,
						-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y))
			if chunk.index >= WARMUP_CHUNKS:
				open_actions.append({"op": "open_hazard"})
			_pattern_insert_after(work, open_actions)
			return true
		"open_hazard":
			if rng.randf() < lerpf(0.6, 0.8, difficulty):
				var lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
				var obstacle_z := -RunnerConfig.CHUNK_LENGTH * rng.randf_range(0.3, 0.66)
				if _add_obstacle(chunk, Kind.LOW, lane, 1, obstacle_z):
					_pattern_insert_after(work, [_fish_arc_action(lane, obstacle_z, 5.0)])
			return true
		"lane_weave_init":
			_pattern_insert_after(work, [{"op": "lane_weave_row",
					"rows": _row_positions(difficulty), "i": 0, "prev_z": -1.0}])
			return true
		"lane_weave_row":
			var weave_rows: PackedFloat32Array = action["rows"]
			var weave_i := int(action["i"])
			if weave_i >= weave_rows.size():
				if not weave_rows.is_empty():
					_pattern_insert_after(work, [_fish_line_action(
							rng.randi_range(0, RunnerConfig.LANE_COUNT - 1),
							weave_rows[weave_rows.size() - 1] - 3.0,
							-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)])
				return true
			var weave_z := weave_rows[weave_i]
			var blocked := 2 if rng.randf() < difficulty * 0.55 else 1
			var open_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
			var weave_actions: Array = []
			var requested := 0
			for lane: int in RunnerConfig.LANE_COUNT:
				if lane == open_lane or requested >= blocked:
					continue
				weave_actions.append(_obstacle_action(Kind.BLOCK, lane, 1, weave_z))
				requested += 1
			weave_actions.append(_fish_line_action(open_lane, float(action["prev_z"]),
					weave_z - 2.0, FISH_Y))
			weave_actions.append({"op": "lane_weave_row", "rows": weave_rows,
					"i": weave_i + 1, "prev_z": weave_z + 2.0})
			_pattern_insert_after(work, weave_actions)
			return true
		"slide_init":
			_pattern_insert_after(work, [{"op": "slide_row",
					"rows": _row_positions(difficulty), "i": 0,
					"lane": rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)}])
			return true
		"slide_row":
			var slide_rows: PackedFloat32Array = action["rows"]
			var slide_i := int(action["i"])
			if slide_i >= slide_rows.size():
				return true
			var slide_z := slide_rows[slide_i]
			var slide_lane := int(action["lane"])
			_pattern_insert_after(work, [{"op": "slide_bar", "z": slide_z,
					"lane": slide_lane, "rows": slide_rows, "i": slide_i}])
			return true
		"slide_bar":
			if _add_obstacle(chunk, Kind.BAR, 0, RunnerConfig.LANE_COUNT,
					float(action["z"])):
				var fish_x := RunnerConfig.lane_x(int(action["lane"]))
				var slide_success: Array = [
					_fish_point_action(Vector3(fish_x, 0.42, float(action["z"]))),
					_fish_point_action(Vector3(fish_x, 0.42, float(action["z"]) - 2.4)),
				]
				var slide_rows: PackedFloat32Array = action["rows"]
				var slide_i := int(action["i"])
				if slide_i + 1 < slide_rows.size():
					slide_success.append(_fish_line_action(int(action["lane"]),
							float(action["z"]) - 5.0,
							slide_rows[slide_i + 1] + 3.0, FISH_Y))
				slide_success.append({"op": "slide_next", "rows": slide_rows,
						"i": slide_i, "lane": action["lane"]})
				_pattern_insert_after(work, slide_success)
			else:
				# Original `continue` keeps lane unchanged and consumes no lane roll.
				_pattern_insert_after(work, [{"op": "slide_row", "rows": action["rows"],
						"i": int(action["i"]) + 1, "lane": action["lane"]}])
			return true
		"slide_next":
			var next_slide_lane := clampi(int(action["lane"]) + rng.randi_range(-1, 1),
					0, RunnerConfig.LANE_COUNT - 1)
			_pattern_insert_after(work, [{"op": "slide_row", "rows": action["rows"],
					"i": int(action["i"]) + 1, "lane": next_slide_lane}])
			return true
		"jump_init":
			_pattern_insert_after(work, [{"op": "jump_row",
					"rows": _row_positions(difficulty), "i": 0}])
			return true
		"jump_row":
			var jump_rows: PackedFloat32Array = action["rows"]
			var jump_i := int(action["i"])
			if jump_i >= jump_rows.size():
				return true
			var jump_z := jump_rows[jump_i]
			var jump_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
			var jump_span := 2 if rng.randf() < difficulty * 0.7 else 1
			if jump_lane + jump_span > RunnerConfig.LANE_COUNT:
				jump_lane = RunnerConfig.LANE_COUNT - jump_span
			var jump_actions: Array = [_obstacle_action(Kind.LOW, jump_lane, jump_span,
					jump_z, [_fish_arc_action(jump_lane, jump_z, 5.0)])]
			var free_lane := (jump_lane + jump_span) % RunnerConfig.LANE_COUNT
			if jump_i + 1 < jump_rows.size():
				jump_actions.append(_fish_line_action(free_lane, jump_z - 4.5,
						jump_rows[jump_i + 1] + 3.0, FISH_Y))
			jump_actions.append({"op": "jump_row", "rows": jump_rows, "i": jump_i + 1})
			_pattern_insert_after(work, jump_actions)
			return true
		"fish_arc_init":
			var fish_lane_a := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
			var fish_lane_b := RunnerConfig.LANE_COUNT - 1 - fish_lane_a
			if fish_lane_a == fish_lane_b:
				fish_lane_b = (fish_lane_a + 1) % RunnerConfig.LANE_COUNT
			var mid := -RunnerConfig.CHUNK_LENGTH * 0.5
			var reward_actions: Array = [
				_fish_line_action(fish_lane_a, -3.0, mid + 7.0, FISH_Y),
				_fish_sweep_action(fish_lane_a, fish_lane_b, mid + 6.0, mid - 6.0, 6, FISH_Y),
				_fish_line_action(fish_lane_b, mid - 7.0,
						-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y),
			]
			if difficulty > 0.15:
				var low_z := mid - 10.0
				reward_actions.append(_obstacle_action(Kind.LOW, fish_lane_b, 1,
						low_z, [_fish_arc_action(fish_lane_b, low_z, 5.5)]))
			_pattern_insert_after(work, reward_actions)
			return true
		"mixed_init":
			_pattern_insert_after(work, [{"op": "mixed_row",
					"rows": _row_positions(difficulty), "i": 0}])
			return true
		"mixed_row":
			var mixed_rows: PackedFloat32Array = action["rows"]
			var mixed_i := int(action["i"])
			if mixed_i >= mixed_rows.size():
				return true
			var mixed_z := mixed_rows[mixed_i]
			var mixed_actions: Array = []
			match mixed_i % 3:
				0:
					var mixed_open := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
					for lane: int in RunnerConfig.LANE_COUNT:
						if lane != mixed_open:
							mixed_actions.append(_obstacle_action(
									Kind.BLOCK, lane, 1, mixed_z))
					mixed_actions.append(_fish_line_action(mixed_open,
							mixed_z + 2.5, mixed_z - 4.0, FISH_Y))
				1:
					mixed_actions.append({"op": "mixed_bar", "z": mixed_z})
				_:
					var mixed_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
					mixed_actions.append(_obstacle_action(Kind.LOW, mixed_lane, 1,
							mixed_z, [_fish_arc_action(mixed_lane, mixed_z, 5.0)]))
			mixed_actions.append({"op": "mixed_row", "rows": mixed_rows,
					"i": mixed_i + 1})
			_pattern_insert_after(work, mixed_actions)
			return true
		"mixed_bar":
			if _add_obstacle(chunk, Kind.BAR, 0, RunnerConfig.LANE_COUNT,
					float(action["z"])):
				var mixed_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
				_pattern_insert_after(work, [_fish_point_action(Vector3(
						RunnerConfig.lane_x(mixed_lane), 0.42, float(action["z"])))])
			return true
		"pinch_init":
			_pattern_insert_after(work, [{"op": "pinch_row",
					"rows": _row_positions(difficulty), "i": 0, "prev_z": -1.0,
					"open_lane": rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)}])
			return true
		"pinch_row":
			var pinch_rows: PackedFloat32Array = action["rows"]
			var pinch_i := int(action["i"])
			if pinch_i >= pinch_rows.size():
				return true
			var pinch_z := pinch_rows[pinch_i]
			var pinch_open := int(action["open_lane"])
			var pinch_actions: Array = []
			for lane: int in RunnerConfig.LANE_COUNT:
				if lane != pinch_open:
					pinch_actions.append(_obstacle_action(Kind.BLOCK, lane, 1, pinch_z))
			pinch_actions.append(_fish_line_action(pinch_open, float(action["prev_z"]),
					pinch_z - 2.0, FISH_Y))
			pinch_actions.append({"op": "pinch_shift", "rows": pinch_rows,
					"i": pinch_i, "z": pinch_z, "open_lane": pinch_open})
			_pattern_insert_after(work, pinch_actions)
			return true
		"pinch_shift":
			var shifted := clampi(int(action["open_lane"])
					+ (1 if rng.randf() < 0.5 else -1), 0, RunnerConfig.LANE_COUNT - 1)
			var pinch_rows: PackedFloat32Array = action["rows"]
			var next_i := int(action["i"]) + 1
			if next_i < pinch_rows.size():
				_pattern_insert_after(work, [{"op": "pinch_row", "rows": pinch_rows,
						"i": next_i, "prev_z": float(action["z"]) + 2.0,
						"open_lane": shifted}])
			else:
				_pattern_insert_after(work, [_fish_line_action(shifted,
						float(action["z"]) + 2.0,
						-RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y)])
			return true
		"seal_init":
			_pattern_insert_after(work, [{"op": "seal_group",
					"rows": _row_positions(difficulty), "i": 0,
					"period": lerpf(SEAL_PERIOD_EASY, SEAL_PERIOD_HARD, difficulty)}])
			return true
		"seal_group":
			var seal_rows: PackedFloat32Array = action["rows"]
			var seal_i := int(action["i"])
			if seal_i >= seal_rows.size():
				return true
			var train := 1
			if seal_rows.size() - seal_i >= 2 \
					and rng.randf() < lerpf(0.25, 0.7, difficulty):
				train = mini(seal_rows.size() - seal_i, 2 if rng.randf() < 0.6 else 3)
			var phase := rng.randf() * TAU
			var phase_step := (1.0 if rng.randf() < 0.5 else -1.0) * 0.72
			var seal_actions: Array = []
			for train_i: int in train:
				seal_actions.append({"op": "seal_one",
						"z": seal_rows[seal_i + train_i] - float(train_i) * 1.5,
						"phase": phase + float(train_i) * phase_step,
						"period": float(action["period"])})
			var safe_lane := 0 if sin(phase) > 0.0 else RunnerConfig.LANE_COUNT - 1
			var z_to := -RunnerConfig.CHUNK_LENGTH + 3.0
			if seal_i + train < seal_rows.size():
				z_to = seal_rows[seal_i + train] + 3.0
			seal_actions.append(_fish_line_action(safe_lane,
					seal_rows[seal_i + train - 1] - 4.0, z_to, FISH_Y))
			seal_actions.append({"op": "seal_group", "rows": seal_rows,
					"i": seal_i + train, "period": action["period"]})
			_pattern_insert_after(work, seal_actions)
			return true
		"tunnel_init":
			_pattern_insert_after(work, [{"op": "tunnel_row",
					"rows": _row_positions(difficulty), "i": 0,
					"lane": rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)}])
			return true
		"tunnel_row":
			var tunnel_rows: PackedFloat32Array = action["rows"]
			var tunnel_i := int(action["i"])
			if tunnel_i >= tunnel_rows.size():
				return true
			var tunnel_z := tunnel_rows[tunnel_i]
			var tunnel_lane := int(action["lane"])
			var tunnel_actions: Array = [{"op": "tunnel_obstacle", "i": tunnel_i,
					"z": tunnel_z, "lane": tunnel_lane}]
			if tunnel_i + 1 < tunnel_rows.size():
				tunnel_actions.append(_fish_line_action(tunnel_lane, tunnel_z - 5.0,
						tunnel_rows[tunnel_i + 1] + 3.0, FISH_Y))
			tunnel_actions.append({"op": "tunnel_next", "rows": tunnel_rows,
					"i": tunnel_i, "lane": tunnel_lane})
			_pattern_insert_after(work, tunnel_actions)
			return true
		"tunnel_obstacle":
			var tunnel_lane := int(action["lane"])
			var tunnel_z := float(action["z"])
			if int(action["i"]) % 2 == 0:
				if _add_obstacle(chunk, Kind.BAR, 0, RunnerConfig.LANE_COUNT, tunnel_z):
					var tunnel_x := RunnerConfig.lane_x(tunnel_lane)
					_pattern_insert_after(work, [
						_fish_point_action(Vector3(tunnel_x, 0.42, tunnel_z)),
						_fish_point_action(Vector3(tunnel_x, 0.42, tunnel_z - 2.2)),
					])
			elif _add_obstacle(chunk, Kind.LOW, tunnel_lane, 1, tunnel_z):
				_pattern_insert_after(work, [_fish_arc_action(
						tunnel_lane, tunnel_z, 4.6)])
			return true
		"tunnel_next":
			var next_tunnel_lane := clampi(int(action["lane"]) + rng.randi_range(-1, 1),
					0, RunnerConfig.LANE_COUNT - 1)
			_pattern_insert_after(work, [{"op": "tunnel_row", "rows": action["rows"],
					"i": int(action["i"]) + 1, "lane": next_tunnel_lane}])
			return true
		"ramp_init":
			var ramp_lane := rng.randi_range(0, RunnerConfig.LANE_COUNT - 1)
			var ramp_z := -RunnerConfig.CHUNK_LENGTH * rng.randf_range(0.22, 0.38)
			_pattern_insert_after(work, [
				_fish_line_action(ramp_lane, -2.5, ramp_z - RAMP_DEPTH * 0.5 - 1.0, FISH_Y),
				{"op": "ramp_obstacle", "lane": ramp_lane, "z": ramp_z},
			])
			return true
		"ramp_obstacle":
			var ramp_lane := int(action["lane"])
			var ramp_z := float(action["z"])
			if not _add_obstacle(chunk, Kind.RAMP, ramp_lane, 1, ramp_z):
				_pattern_insert_after(work, [{"op": "fish_arc_init"}])
			else:
				_pattern_insert_after(work, [
					{"op": "ramp_fish", "lane": ramp_lane,
							"lip_z": ramp_z - RAMP_DEPTH * 0.5, "i": 0},
					_fish_line_action((ramp_lane + 1) % RunnerConfig.LANE_COUNT,
							ramp_z - RAMP_DEPTH, -RunnerConfig.CHUNK_LENGTH + 3.0, FISH_Y),
				])
			return true
	return true


## Local z of each obstacle row in a chunk, front (nearest the player) first.
func _row_positions(difficulty: float) -> PackedFloat32Array:
	var gap := lerpf(ROW_GAP_EASY, ROW_GAP_HARD, difficulty)
	var rows := PackedFloat32Array()
	var z := -CHUNK_EDGE_MARGIN
	while z > -(RunnerConfig.CHUNK_LENGTH - CHUNK_EDGE_MARGIN):
		rows.append(z)
		z -= gap
	return rows


## Monolithic pattern helpers below remain temporarily as an independent source
## oracle while the staged action executor proves byte-for-byte parity. Runtime
## and synchronous setup both call `_run_pattern()` above; these are not called.

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
		var authored_asset_id := ""
		if _runner_art_set != null:
			authored_asset_id = _runner_art_set.obstacle_asset_id(KIND_NAMES[kind])
		# RunnerArtSet obstacle roles are shared across biome profiles. DAY owns
		# this kit; every other band keeps its existing shell until its own art
		# set lands instead of inheriting a research-port prop by accident.
		# Full-height dodge hazards are ice boulders in every biome. Retain the
		# imported service arch; block, jump and ramp use shared reference meshes.
		var authored_mesh := _authored_day_mesh(authored_asset_id) \
			if chunk.biome == Biome.DAY and kind == Kind.BAR else null
		if authored_mesh != null:
			visual.mesh = authored_mesh
			visual.set_meta("authored_asset_id", authored_asset_id)
			# Authored obstacles use pooled contact patches below. Their real-time
			# forward-cast shadows crossed whole lanes and crushed cream/cyan paint
			# into black bars in both portrait and compact chase views.
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			match kind:
				Kind.BLOCK:
					visual.scale = Vector3(BLOCK_WIDTH / 2.44, BLOCK_HEIGHT / 2.275,
							BLOCK_DEPTH / 1.82)
					visual.rotation.y = fmod(absf(local_z) * 0.7, 0.32) - 0.16
				Kind.LOW:
					# Match the collider envelope on all axes. At maximum speed a
					# 30 cm depth mismatch is half a frame of invisible contact.
					visual.scale = Vector3(size.x / 2.75, LOW_HEIGHT / 0.915,
							LOW_DEPTH / 0.853)
				Kind.RAMP:
					visual.scale = Vector3(RAMP_WIDTH / 2.72, RAMP_HEIGHT / 1.733,
							RAMP_DEPTH / 4.117)
					# Imported source's high lip is at +Z (player side).
					# Turn only the visual so its low approach faces +Z and
					# the takeoff lip faces gameplay forward (-Z).
					visual.rotation.y = PI
				Kind.BAR:
					# Same collider/silhouette, alternating authored face. Cyan inlay,
					# lamps and access panels no longer repeat in one flat procession.
					visual.rotation.y = PI if posmod(roundi(absf(world_z)), 2) == 1 else 0.0
			visual.material_override = _authored_day_material()
		else:
			match kind:
				Kind.BLOCK:
					visual.mesh = _block_mesh()
					visual.set_meta("reference_ice_block", true)
					# Keep the silhouette aligned with the unchanged collision box.
				Kind.LOW:
					visual.mesh = _low_mesh()
					visual.scale.x = size.x
				Kind.RAMP:
					visual.mesh = _ramp_mesh()
					visual.set_meta("ice_ramp", true)
				_:
					visual.mesh = _arch_mesh()
			if kind == Kind.LOW or kind == Kind.BLOCK:
				visual.material_override = ReferenceIce.material()
			else:
				visual.material_override = _prop_material()
		area.add_child(visual)
		# Grounding is not left to the scene's light rig: with no SSAO on
		# gl_compatibility, and no guarantee the runner's sun casts shadows at
		# all, an unshadowed obstacle reads as hovering and its distance becomes
		# unjudgeable. Baked foot patches all flush into one per-chunk MultiMesh.
		if kind == Kind.BAR:
			# Two small foot patches ground the portal without painting one giant
			# dark rectangle across all three lanes. They flush through the same
			# per-chunk MultiMesh as every other obstacle contact patch.
			for side: float in [-1.0, 1.0]:
				chunk.contact_patches.append(Transform3D(
						Basis().scaled(Vector3(1.55, 1.0, size.z * 1.45)),
						Vector3(side * (RunnerConfig.DECK_HALF_WIDTH - 0.42),
								0.02, local_z)))
		else:
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
	# Deep and saturated rather than bright, and authored in LINEAR: these are
	# unshaded alpha decals on blown-out snow under an ACES curve, so a colour
	# that looks right as an editor swatch arrives on screen a full stop lighter
	# and a long way toward pastel. Each of these is roughly the linear
	# pre-image of the colour actually wanted on the deck.
	var colour := Color(0.94, 0.18, 0.006)
	match kind:
		Kind.BAR:
			colour = Color(0.02, 0.26, 0.76)
		Kind.LOW:
			colour = Color(0.94, 0.18, 0.006)
		Kind.RAMP:
			colour = Color(0.02, 0.55, 0.10)
		Kind.SEAL:
			colour = Color(0.96, 0.20, 0.006)
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
		chunk.mark_colors.append(Color(colour.r, colour.g, colour.b, 0.95 - float(i) * 0.13))


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
	# Array.shuffle() uses the process-global RNG and made identical run seeds
	# disagree. Fisher-Yates stays on the chunk's gameplay stream.
	for i: int in range(lane_order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := lane_order[i]
		lane_order[i] = lane_order[j]
		lane_order[j] = swap
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
		var body := Node3D.new()
		body.name = "Presentation"
		crate.add_child(body)
		var visual := MeshInstance3D.new()
		visual.mesh = _crate_mesh(id)
		# Vertex colour carries the dark edge and icon. The old full-emissive
		# override discarded that data and collapsed the magnet into a pink cube.
		visual.material_override = _powerup_shell_material(id)
		body.add_child(visual)
		var halo := MeshInstance3D.new()
		halo.name = "Halo"
		halo.mesh = _powerup_ring_mesh()
		var tint := _powerup_colour(id)
		halo.material_override = VisualLibrary.emissive_material(tint * 0.42, tint, 1.8, 0.2)
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(halo)
		crate.body = body
		var blob := MeshInstance3D.new()
		blob.mesh = VisualLibrary.contact_patch_mesh()
		blob.material_override = VisualLibrary.contact_shadow_material(0.3)
		blob.scale = Vector3(2.0, 1.0, 2.0)
		blob.position.y = -POWERUP_Y + 0.03
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		crate.add_child(blob)
	chunk.add_child(crate)


static func _powerup_colour(_id: StringName) -> Color:
	# Violet is the mode-wide power-up envelope. Identity comes from the three
	# silhouettes (horseshoe / gem / hex drum), never from stealing cyan's
	# "duck" meaning or gold's "collect" meaning at gameplay distance.
	return Color(0.70, 0.24, 0.92)


## Lit vertex-colour shell plus a restrained emissive lift. A dedicated cached
## material per ID preserves silhouette facets and face icons while the shared
## halo supplies the long-range colour read.
static func _powerup_shell_material(id: StringName) -> StandardMaterial3D:
	var key := String(id)
	if _powerup_materials.has(key):
		return _powerup_materials[key]
	var tint := _powerup_colour(id)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.24
	mat.roughness = 0.28
	mat.rim_enabled = true
	mat.rim = 0.38
	mat.rim_tint = 0.72
	_powerup_materials[key] = mat
	return mat


static func _powerup_ring_mesh() -> TorusMesh:
	if _powerup_ring_mesh_cache != null:
		return _powerup_ring_mesh_cache
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.70
	mesh.outer_radius = 0.79
	mesh.rings = 18
	mesh.ring_segments = 8
	_powerup_ring_mesh_cache = mesh
	return mesh


## --- Chunk geometry ---------------------------------------------------------

## Deck, lane seams and kerb/drop-off verge. Procedural biomes keep original
## shared surfaces. Authored DAY uses three topology variants plus one snow
## shelf, all MultiMesh/shared-material draws; gameplay floor stays unchanged.
func _build_deck(chunk: RunnerChunk, pattern: int) -> void:
	for stage: int in STREAM_DECK_STAGE_COUNT:
		_build_deck_stage(chunk, pattern, stage)


## One cassette/draw family per stage. Synchronous setup loops these stages;
## rendered streaming schedules them across frames with identical child order.
func _build_deck_stage(chunk: RunnerChunk, pattern: int, stage: int) -> void:
	var biome := chunk.biome
	# A tunnel darkens its own floor. This is the cheapest honest "the light
	# changed" available: no extra lights, no environment write, and it is the
	# surface the player is actually looking at.
	var tunnel := pattern == Pattern.TUNNEL
	var authored_decks: Array[Mesh] = []
	for asset_id: String in DAY_DECK_ASSETS:
		var deck_mesh := _authored_day_mesh(asset_id)
		if deck_mesh != null:
			authored_decks.append(deck_mesh)
	var authored_day := biome == Biome.DAY \
			and authored_decks.size() == DAY_DECK_ASSETS.size()
	if authored_day:
		# Three topology-distinct six-metre cassettes. Grouping transforms by
		# mesh keeps each variant one MultiMesh draw per chunk while eliminating
		# the copied-board procession that survived 180-degree rotations.
		if stage < DAY_DECK_ASSETS.size():
			var variant := stage
			var modules: Array[Transform3D] = []
			var module_tints := PackedColorArray()
			for module_index: int in 6:
				if posmod(module_index + chunk.index, DAY_DECK_ASSETS.size()) != variant:
					continue
				var yaw := PI if posmod(module_index + chunk.index * 2, 2) == 1 else 0.0
				modules.append(Transform3D(
						# Unit X keeps modeled wall at canonical x=5.40..5.95,
						# exactly covering snow-shelf drop. Prior 0.985 scale left an
						# open slit beneath cap and revived floating-board read.
						Basis(Vector3.UP, yaw),
						Vector3(0.0, AUTHORED_DAY_DECK_Y,
								-3.0 - float(module_index) * 6.0)))
				# Ice skin now owns road colour. Tinting the whole authored cassette
				# with road blue also darkened its coral inserts and ivory snowcaps.
				var variation: Color = [
						Color(1.0, 1.0, 1.0, 1.0),
						Color(0.95, 0.995, 1.0, 1.0),
						Color(1.0, 0.975, 0.93, 1.0),
				][posmod(module_index + chunk.index * 2, 3)]
				module_tints.append(variation)
			var authored_instance := _add_multimesh(chunk, authored_decks[variant], modules,
					_authored_day_draw_material(DAY_DECK_ASSETS[variant]), "AuthoredDeckKerb%d" % variant,
					220.0, module_tints, true)
			if authored_instance != null:
				authored_instance.set_meta("authored_asset_id", DAY_DECK_ASSETS[variant])
				# Dummy/headless RenderingServer does not round-trip MultiMesh
				# transforms. Keep the tiny authored placement set available to
				# debug contracts; release builds retain only the GPU buffer.
				if OS.is_debug_build():
					authored_instance.set_meta("authored_source_transforms", modules.duplicate())
	elif stage == 0:
		var deck := MeshInstance3D.new()
		deck.name = "Deck"
		deck.mesh = _deck_mesh()
		deck.material_override = _deck_material(biome, tunnel)
		deck.position = Vector3(0.0, 0.0, -RunnerConfig.CHUNK_LENGTH * 0.5)
		deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(deck)
		# Lane seams: a flat white deck gives the player nothing to judge a lane
		# change against, and no amount of obstacle readability fixes that.
		var seams := MeshInstance3D.new()
		seams.name = "Seams"
		seams.mesh = _seam_mesh()
		seams.material_override = _seam_material(biome)
		seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(seams)
	# Four surfaces, not two, and this is the load-bearing part of the repaint.
	# The kerb previously wore ONE ice material over a mesh whose crown/body/
	# deep vertex gradient the ice shader never reads -- so the whole wall was a
	# single flat pale value, which is most of why the corridor had no depth
	# staging. Splitting it lets the crown be BRIGHT, the body MID and the
	# drop-off face DARK, which is the three-value law expressed in the one
	# object that touches all three tiers. Two extra draw calls per chunk.
	if stage == 3 and authored_day:
		# A continuous polished-ice skin hides the cassette panel grid on the
		# playable strip. The authored deck still supplies rounded kerbs and
		# snowbank relief; collision stays at y=0. This is one shared ice draw
		# per visible chunk, not another material/mesh family per cassette.
		var ice_skin := MeshInstance3D.new()
		ice_skin.name = "GlacialIceSkin"
		ice_skin.mesh = _deck_mesh()
		ice_skin.material_override = _deck_material(biome, tunnel)
		# Authored hatches and repair plates peak at y=0.018 after cassette
		# placement. At 0.015 they poked through as square steel patches;
		# 0.022 covers them while keeping gameplay decals at y=0.024/0.030.
		ice_skin.position = Vector3(0.0, 0.022, -RunnerConfig.CHUNK_LENGTH * 0.5)
		ice_skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(ice_skin)
		# Authored cassettes include their own rounded kerb. Keep only snow shelf
		# from procedural verge; drawing both walls produced floating black boards
		# over every carefully-painted module.
		var shelf := MeshInstance3D.new()
		shelf.name = "AuthoredDaySnowShelf"
		shelf.mesh = _authored_day_shelf_mesh()
		shelf.material_override = _verge_snow_material(biome, tunnel)
		shelf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(shelf)
	elif stage == 3:
		var verge := MeshInstance3D.new()
		verge.name = "Verge"
		verge.mesh = _verge_mesh()
		verge.set_surface_override_material(0, _kerb_body_material(biome))
		verge.set_surface_override_material(1, _kerb_crown_material(biome))
		verge.set_surface_override_material(2, _kerb_deep_material(biome))
		verge.set_surface_override_material(3, _verge_snow_material(biome, tunnel))
		verge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunk.add_child(verge)
	if stage == 4:
		_build_deck_decals(chunk, biome)


## Quiet edge inlays give an empty chunk a countable ground rhythm. They share
## the obstacle-mark MultiMesh, stay outside the three decision lanes, and use
## the biome seam colour at low alpha so they cannot be mistaken for a verb.
## Their transforms are fixed from the chunk index; no gameplay RNG is touched.
func _build_deck_decals(chunk: RunnerChunk, biome: int) -> void:
	var edge_x := RunnerConfig.DECK_HALF_WIDTH - 0.42
	var tint := _biome_seam_tint(biome).lerp(_biome_deck_tint(biome), 0.56)
	for i: int in 6:
		var local_z := -3.5 - float(i) * 5.8
		# Alternate the slightly stronger edge so the repeated motif feels
		# authored without becoming a central lane instruction.
		for side: int in 2:
			var sign_x := -1.0 if side == 0 else 1.0
			var alpha := 0.20 if (i + side + chunk.index) % 2 == 0 else 0.13
			chunk.marks.append(Transform3D(
					Basis().scaled(Vector3(0.62, 1.0, 1.15)),
					Vector3(sign_x * edge_x, 0.024, local_z)))
			chunk.mark_colors.append(Color(tint.r, tint.g, tint.b, alpha))


## Deck tint for a biome, darkened when the chunk is roofed. Split out so the
## load-time primer below and the per-chunk builder ask for the SAME material
## key -- a primer that misses by one colour component primes nothing.
static func _deck_tint(biome: int, tunnel: bool) -> Color:
	var tint := _biome_deck_tint(biome)
	if tunnel:
		# Was 0.48/0.56/0.72, which was correct against a near-white deck and
		# is mud against a MID one -- a roofed chunk came out black. The change
		# of place inside a tunnel is carried by the ribs and the two bay lamps
		# instead, which is what the note beside _tunnel_mesh() argues for and
		# is the right division of labour anyway.
		return tint * Color(0.66, 0.72, 0.86, 1.0)
	return tint


static func _deck_material(biome: int, tunnel: bool) -> ShaderMaterial:
	return _painted_surface_material(biome, tunnel, false)


## The shelf keeps its own BRIGHT tint rather than inheriting the deck's, so
## darkening the play strip cannot darken the frame around it.
static func _verge_snow_material(biome: int, tunnel: bool) -> ShaderMaterial:
	return _painted_surface_material(biome, tunnel, true)


## One cached material for each biome/tunnel/surface combination. Primed before
## GO and reused by the start apron and every chunk; no runtime texture readback,
## per-cassette materials, extra geometry or gameplay RNG.
static func _painted_surface_material(biome: int, tunnel: bool, snow: bool) -> ShaderMaterial:
	var key := "%d_%d_%d" % [biome, int(tunnel), int(snow)]
	if _painted_surface_cache.has(key):
		return _painted_surface_cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = PAINTED_SURFACE_SHADER
	var tint := _biome_shelf_tint(biome) if snow else _deck_tint(biome, tunnel)
	if snow and tunnel:
		tint *= Color(0.82, 0.86, 0.96, 1.0)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("paint_reference", Color(0.8957, 0.9330, 0.9884) if snow else Color(0.381, 0.775, 0.946))
	mat.set_shader_parameter("tile_metres", 7.0 if snow else 10.0)
	mat.set_shader_parameter("paint_strength", 0.78 if snow else 1.0)
	mat.set_shader_parameter("roughness_base", 0.86 if snow else 0.44)
	mat.set_shader_parameter("specular_amount", 0.15 if snow else 0.26)
	mat.set_shader_parameter("emission_lift", 0.085 if biome == Biome.CAVE or biome == Biome.NIGHT else 0.055)
	# Headless logic tests retain palette/material identity without loading GPU
	# textures. Missing optional paint keeps a readable solid-colour fallback.
	if not GameConfig.is_headless():
		var path := PAINTED_SNOW_TEXTURE if snow else PAINTED_ICE_TEXTURE
		if not _painted_texture_cache.has(path):
			_painted_texture_cache[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
		var texture := _painted_texture_cache[path] as Texture2D
		if texture != null:
			mat.set_shader_parameter("painted_albedo", texture)
			mat.set_shader_parameter("painted_enabled", true)
	_painted_surface_cache[key] = mat
	return mat


static func _seam_material(biome: int) -> StandardMaterial3D:
	return VisualLibrary.emissive_material(_biome_seam_tint(biome),
			_biome_seam_glow(biome), _biome_seam_energy(biome), 0.7)


## Recessed blue wall bays use one opaque vertex-paint material in both the
## authored DAY deck and fallback bands. Biome light still changes their value.
static func _kerb_body_material(_biome: int) -> StandardMaterial3D:
	return ReferenceWalls.material()


## Kerb crown. Emissive, at zero-ish energy in the lit bands and hard in the
## dark ones: in the cave and at night the glowing ice edge is the light in the
## scene and the brightest thing in frame.
static func _kerb_crown_material(biome: int) -> StandardMaterial3D:
	var crown := _biome_kerb_crown(biome)
	return VisualLibrary.emissive_material(crown, crown, _biome_crown_energy(biome), 0.35)


## Drop-off face. Vertex-coloured so one shared mesh can ramp from the wall
## value at the top to near-black at the shelf line, tinted per band here.
static func _kerb_deep_material(biome: int) -> StandardMaterial3D:
	return VisualLibrary.rock_material(_biome_kerb_deep(biome), 0.9)


## --- PALETTE ----------------------------------------------------------------
##
## THE THREE-VALUE LAW. Every surface in the corridor belongs to exactly one of
## three separated luminance tiers, and no two of the three ever meet at the
## same value:
##
##   BRIGHT 0.78-1.00   sky, the snow shelf outside the kerb, wall crowns,
##                      collectibles
##   MID    0.30-0.55   THE RUNNING DECK, the kerb wall body, mid-ground
##                      silhouettes
##   DARK   0.02-0.15   obstacle bodies, the drop-off face
##
## The first pass had all of it in one tier: deck 0.92, verge 0.95, crown 0.94,
## horizon 0.85. That is why it read as a test level -- there was no figure and
## no ground, so nothing could be staged against anything else, and no particle
## or pickup or obstacle had anything to be bright AGAINST.
##
## The move that fixes it is polar-fiction-safe rather than a stylisation: the
## play strip is POLISHED GLACIAL ICE, which is genuinely a deep saturated
## cyan-blue, while the wind-packed snow shelf beyond the kerb stays white. So
## the player runs down a dark saturated ribbon inside a bright frame. Every
## downstream complaint -- obstacle contrast, character contrast, "no colour
## anywhere", the horizon dissolving into the deck -- is the same defect, and
## this is the same fix for all of them.
##
## Hot accents (chroma > 0.7) ride the DARK tier only, and only on things the
## player must act on. The hue language is FIXED and global, because a hue that
## means two things means nothing:
##   orange-red = will hurt you, dodge      cyan  = go under, duck
##   green      = go, ramp, launch          gold  = collect
##   violet     = power-up
## _biome_accent() below is therefore decorative only -- banners, gantry lamps,
## crystal glow. Obstacle liveries take their colour from _verb_* instead, and
## do NOT drift per biome: an orange band has to mean "dodge" in all four.
##
## Everything is authored as it is typed, i.e. sRGB, because these feed material
## tints (albedo and shader `source_color` uniforms convert for us). Vertex
## colours are the exception -- see _vc() -- and getting that backwards is what
## once turned an authored amber into gold on screen.

## The running deck: MID tier, saturated. The single most consequential eight
## constants in the file.
static func _biome_deck_tint(biome: int) -> Color:
	# Keep the route in a comparable albedo band across the run. Later skies
	# and key lights already darken the scene; near-black road paint compounds
	# that loss and leaves only emissive seams visible. Hue carries the biome.
	match biome:
		Biome.DUSK:
			return Color(0.60, 0.44, 0.52)
		Biome.CAVE:
			return Color(0.35, 0.47, 0.66)
		Biome.NIGHT:
			return Color(0.37, 0.46, 0.67)
		_:
			# Day is glacial ice, not painted steel. Keep enough blue value
			# separation for orange hazards and gold fish above the floor.
			return Color(0.15, 0.57, 0.84)


## The snow shelf beyond the drop-off: BRIGHT tier, and deliberately NOT
## derived from the deck any more. It is the frame around the play space, and a
## frame that darkens with its picture frames nothing. Cave and night retain
## cool snow with enough reflected light to frame the whole lane, not just
## the narrow emissive seams.
static func _biome_shelf_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.80, 0.72)
		Biome.CAVE:
			return Color(0.64, 0.82, 0.94)
		Biome.NIGHT:
			return Color(0.69, 0.78, 0.96)
		_:
			return Color(0.99, 0.985, 0.97)


## Wind-polished top of the kerb wall: BRIGHT, and in the two dark bands it is
## a light SOURCE (see _biome_crown_energy) rather than a lit surface.
static func _biome_kerb_crown(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.74, 0.60)
		Biome.CAVE:
			return Color(0.40, 0.92, 1.0)
		Biome.NIGHT:
			return Color(0.62, 0.92, 1.0)
		_:
			return Color(0.92, 0.99, 1.0)


## Emission energy on the crown. Zero in the lit bands (the sun does the work);
## in the cave and at night the ice IS the lighting, which is what makes those
## two bands read as places rather than as the day band with the lamp off.
static func _biome_crown_energy(biome: int) -> float:
	match biome:
		Biome.CAVE:
			return 0.35
		Biome.NIGHT:
			return 0.30
		Biome.DUSK:
			return 0.10
		_:
			return 0.06


## Body of the kerb wall: MID, saturated, the same tier as the deck but a
## different hue so the two never merge into one mass.
static func _biome_kerb_body(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(0.86, 0.30, 0.32)
		Biome.CAVE:
			return Color(0.23, 0.46, 0.65)
		Biome.NIGHT:
			return Color(0.30, 0.43, 0.69)
		_:
			return Color(0.20, 0.52, 0.76)


## The drop-off face below the kerb: DARK. This band is what separates the MID
## deck from the BRIGHT shelf; without it the two touch and the causeway stops
## reading as raised.
static func _biome_kerb_deep(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(0.28, 0.06, 0.18)
		Biome.CAVE:
			return Color(0.02, 0.07, 0.16)
		Biome.NIGHT:
			return Color(0.02, 0.03, 0.14)
		_:
			return Color(0.04, 0.18, 0.36)


## Free-standing ice: crystals, bergs, the mid-ground silhouettes' highlights.
static func _biome_ice_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(0.96, 0.52, 0.52)
		Biome.CAVE:
			return Color(0.25, 0.78, 0.98)
		Biome.NIGHT:
			return Color(0.30, 0.50, 0.95)
		_:
			return Color(0.52, 0.80, 0.98)


## Mid-ground and far silhouettes. Always a couple of stops under the band's
## sky, because their entire job is to put a dark edge in front of a bright
## horizon: an ice pillar the same value as the sky behind it is not a
## silhouette, it is a smudge.
static func _biome_far_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(0.52, 0.20, 0.30)
		Biome.CAVE:
			return Color(0.05, 0.20, 0.34)
		Biome.NIGHT:
			return Color(0.04, 0.09, 0.26)
		_:
			return Color(0.26, 0.52, 0.78)


## Warm complement on cold ice, cold complement on warm ice. The dusk band
## already proved this works before anything else in the corridor did.
static func _biome_seam_tint(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.88, 0.42)
		Biome.CAVE:
			return Color(0.62, 1.0, 0.95)
		Biome.NIGHT:
			return Color(0.58, 1.0, 0.82)
		_:
			return Color(1.0, 0.97, 0.86)


static func _biome_seam_glow(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.58, 0.08)
		Biome.CAVE:
			return Color(0.10, 1.0, 0.86)
		Biome.NIGHT:
			return Color(0.10, 1.0, 0.60)
		_:
			return Color(1.0, 0.84, 0.30)


## Seam emission energy. The two dark bands lean on the seams for their BRIGHT
## tier, so they burn considerably harder there.
static func _biome_seam_energy(biome: int) -> float:
	match biome:
		Biome.DUSK:
			return 0.85
		Biome.CAVE:
			return 1.10
		Biome.NIGHT:
			return 1.25
		_:
			return 0.75


## DECORATIVE hot accent for a band -- banners, gantry lamps, crystal glow.
## Never used for a verb: see the hue language at the top of this block.
static func _biome_accent(biome: int) -> Color:
	match biome:
		Biome.DUSK:
			return Color(1.0, 0.42, 0.12)
		Biome.CAVE:
			return Color(0.20, 0.95, 1.0)
		Biome.NIGHT:
			return Color(0.86, 0.30, 1.0)
		_:
			return Color(1.0, 0.62, 0.14)


## --- Verb colours -----------------------------------------------------------
## Fixed across every band. These are the only saturated colours allowed on an
## obstacle, and each one means exactly one thing everywhere in the mode.

## "This will hurt you -- go around it." Blocks, ridges, seals.
static func _verb_dodge() -> Color:
	return Color(1.0, 0.52, 0.045)


## "Go under it." The arch, and nothing else.
static func _verb_duck() -> Color:
	return Color(0.16, 0.95, 1.0)


## "Take it." The launch ramp, and nothing else.
static func _verb_go() -> Color:
	return Color(0.22, 1.0, 0.36)


## sRGB -> linear, for a colour destined for a VERTEX buffer rather than a
## material property.
##
## This conversion is not optional and it is not a nicety. Material albedo and
## shader `source_color` uniforms are converted for us on upload; vertex colours
## are not -- StandardMaterial3D consumes ARRAY_COLOR as linear. So a value that
## looks correct as an editor swatch arrives on screen a full stop lighter and a
## long way toward pastel, which is exactly how an authored amber once shipped
## as gold and an authored warm ridge shipped as olive. Author every mesh colour
## in the same sRGB space as the palette above and put it through here.
static func _vc(c: Color) -> Color:
	return c.srgb_to_linear()


## Height of the authored snow shelf at a world-space absolute X. Must stay in
## lockstep with surface 3 in _verge_mesh(): dressing placed at a constant Y
## visibly hovered over the rising shelf or disappeared into it.
static func _shelf_y_at(abs_x: float) -> float:
	var inner_edge := RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS
	var t := clampf((absf(abs_x) - inner_edge) / (SHELF_WIDTH - inner_edge), 0.0, 1.0)
	return -SHELF_DROP + t * 0.9


## Everything beyond the drop-off. All MultiMesh, all shadowless, all distance
## faded: it exists to sell speed in peripheral vision and must never cost more
## than a handful of draw calls per chunk.
##
## Half of it MOVES. Static dressing at 38 m/s reads as wallpaper on a cylinder;
## a banner that flaps and a shard that tumbles cost one instance-transform
## write each per frame and are the difference between a corridor and a place.
func _build_dressing(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	for stage: int in STREAM_DRESSING_STAGE_COUNT:
		_build_dressing_stage(chunk, rng, stage)


## Preserve original family and art-RNG order while bounding each streamed
## submission to one visual family.
func _build_dressing_stage(chunk: RunnerChunk, rng: RandomNumberGenerator,
		stage: int) -> void:
	var biome := chunk.biome
	match stage:
		0:
			_build_drifts(chunk, rng, biome)
		1:
			_build_crystals(chunk, rng, biome)
		2:
			_build_bergs(chunk, rng, biome)
		3:
			if biome == Biome.DAY:
				_build_day_port_near(chunk, rng)
		4:
			if biome == Biome.DAY:
				_build_day_port_modules(chunk, rng)
		5:
			if biome == Biome.DAY:
				_build_day_port_cargo(chunk, rng)
		6:
			if biome == Biome.DAY:
				_build_day_port_landmark(chunk, rng)
		7:
			# DAY's sensor sleds own the near-parallax band. Alternate pennants
			# there; other biomes keep banners every chunk.
			if biome != Biome.DAY or posmod(chunk.index, 2) == 0:
				_build_banners(chunk, rng)
		8:
			_build_debris(chunk, rng)
		9:
			# Spell out short-circuit order: DAY consumes one chance roll, NIGHT
			# consumes none here, and DUSK/CAVE consume none.
			if biome == Biome.NIGHT:
				_build_birds(chunk, rng)
			elif biome == Biome.DAY and rng.randf() < 0.5:
				_build_birds(chunk, rng)
		10:
			if biome == Biome.NIGHT and rng.randf() < 0.35:
				_build_aurora(chunk, rng)


func _build_drifts(chunk: RunnerChunk, rng: RandomNumberGenerator, biome: int) -> void:
	var drifts: Array[Transform3D] = []
	for i: int in rng.randi_range(3, 6):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(1.6, 3.8)
		var drift_x := rng.randf_range(RunnerConfig.DECK_HALF_WIDTH + 3.0, SHELF_WIDTH * 0.8)
		drifts.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.45, 0.85), s)),
				Vector3(side * drift_x, _shelf_y_at(drift_x),
						-rng.randf() * RunnerConfig.CHUNK_LENGTH)))
	if not _supporting_family_enabled(chunk.index, 0, chunk.dressing_density):
		return
	_add_multimesh(chunk, VisualLibrary.snow_drift_mesh(), drifts,
			VisualLibrary.rock_material(_biome_shelf_tint(biome), 0.88), "Drifts", 170.0)


func _build_crystals(chunk: RunnerChunk, rng: RandomNumberGenerator, biome: int) -> void:
	var crystals: Array[Transform3D] = []
	for i: int in rng.randi_range(2, 5):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var s := rng.randf_range(1.1, 2.9)
		var crystal_x := rng.randf_range(RunnerConfig.DECK_HALF_WIDTH + 1.4, SHELF_WIDTH * 0.6)
		crystals.append(Transform3D(
				Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 0.8, s, s * 0.8)),
				Vector3(side * crystal_x, _shelf_y_at(crystal_x),
						-rng.randf() * RunnerConfig.CHUNK_LENGTH)))
	# Thin whole presentation families on lower tiers; reducing instance count
	# inside a MultiMesh does not reduce its draw call. RNG was still consumed,
	# so later authored placement stays stable across quality changes.
	if not _decorative_family_enabled(chunk.index, 0, chunk.dressing_density):
		return
	_add_multimesh(chunk, VisualLibrary.ice_crystal_mesh(), crystals,
			VisualLibrary.rock_material(_biome_ice_tint(biome), 0.25), "Crystals", 170.0)


func _build_bergs(chunk: RunnerChunk, rng: RandomNumberGenerator, biome: int) -> void:
	# DAY uses one authored five-mass family through the same seeded placement
	# seam. Other bands retain four bounded procedural silhouettes. Presentation
	# consumes art_rng only; gameplay generation and replay order remain untouched.
	var authored: Mesh = _authored_day_mesh(DAY_ICEBERG_ASSET) \
			if biome == Biome.DAY else null
	# One authored five-mass cluster every third DAY chunk forms an intentional
	# skyline beat. V7 stamped two-to-four copies in every chunk, turning strong
	# geometry into iceberg wallpaper. Off-beat chance remains sparse and seeded.
	var authored_beat := authored != null and posmod(chunk.index, 3) == 1
	var berg_chance := (1.0 if authored_beat else 0.08) if authored != null \
			else (0.88 if biome == Biome.DAY else (0.28 if biome == Biome.NIGHT else 0.55))
	if rng.randf() < berg_chance:
		var bergs: Array[Transform3D] = []
		var berg_count := 1
		if authored == null:
			berg_count = rng.randi_range(2, 4) if biome == Biome.DAY \
					else rng.randi_range(1, 3)
		for i: int in berg_count:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var s := rng.randf_range(0.72, 1.26) if authored != null \
					else (rng.randf_range(8.0, 18.0) if biome == Biome.DAY \
					else rng.randf_range(5.0, 13.0))
			var yaw := rng.randf() * TAU
			var vertical_ratio := rng.randf_range(0.90, 1.08) if authored != null \
					else rng.randf_range(0.7, 1.5)
			bergs.append(Transform3D(
					Basis(Vector3.UP, yaw).scaled(
							Vector3(s, s * vertical_ratio, s)),
					Vector3(side * (rng.randf_range(42.0, 72.0) if authored != null \
							else rng.randf_range(34.0, 84.0)), -SHELF_DROP - 1.5,
							-rng.randf() * RunnerConfig.CHUNK_LENGTH)))
		var variant: int = [101, 211, 331, 449][rng.randi_range(0, 3)]
		if not _supporting_family_enabled(chunk.index, 1, chunk.dressing_density):
			return
		var berg_mesh: Mesh = ReferenceIce.sea_mesh(authored) if authored != null \
				else VisualLibrary.berg_mesh(variant)
		var berg_material: Material = ReferenceIce.material() if authored != null \
				else VisualLibrary.rock_material(_biome_far_tint(biome), 0.72)
		var instance := _add_multimesh(chunk, berg_mesh, bergs, berg_material,
				"AuthoredIcebergClusters" if authored != null else "Bergs", 900.0)
		if instance != null and authored != null:
			instance.set_meta("authored_asset_id", DAY_ICEBERG_ASSET)
			instance.set_meta("reference_ice_derivative", true)


## DAY is an active polar research port, staged in three depth bands: sensor
## sleds on the near kerb, modular labs on the shelf, and one of three large
## skyline landmarks in the far field. Every repeated set is one MultiMesh;
## landmark meshes share the obstacle material/program and recur slowly.
func _build_day_port_near(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var near_props: Array[Transform3D] = []
	var near_tints := PackedColorArray()
	var authored := _authored_day_mesh(DAY_PYLON_ASSET)
	var kerb_top := AUTHORED_DAY_KERB_TOP if authored != null else WALL_HEIGHT
	# Sensor sleds form irregular two/three-piece service clusters rather than a
	# stamped fence. They stay beyond the kerb, so extra instances strengthen
	# near parallax without touching the 55--70 m lane-decision silhouette.
	var prop_count := maxi(1, roundi(float(rng.randi_range(2, 4)) * chunk.dressing_density))
	for i: int in prop_count:
		var side := -1.0 if (i + chunk.index) % 2 == 0 else 1.0
		var sx := rng.randf_range(0.76, 1.04)
		var sy := sx * rng.randf_range(0.92, 1.10)
		var sz := sx * rng.randf_range(0.90, 1.08)
		near_props.append(Transform3D(
				Basis(Vector3.UP, -side * PI * 0.5 + rng.randf_range(-0.12, 0.12))
						.scaled(Vector3(sx, sy, sz)),
				Vector3(side * (RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS * 0.5),
						kerb_top, -(RunnerConfig.CHUNK_LENGTH / float(prop_count))
								* (float(i) + rng.randf_range(0.28, 0.72)))))
		near_tints.append([
				Color(1.0, 1.0, 1.0, 1.0),
				Color(0.94, 1.0, 1.0, 1.0),
				Color(1.0, 0.97, 0.91, 1.0),
		][posmod(chunk.index + i, 3)])
	# Cluster / breathing-space rhythm. Seeded transforms are still consumed so
	# this remains presentation-only and later art families keep deterministic.
	if posmod(chunk.index, 3) == 2 \
			or (chunk.dressing_density < 0.99 and posmod(chunk.index, 4) == 3):
		return
	var mesh: Mesh = authored if authored != null else _port_prop_mesh()
	var instance := _add_multimesh(chunk, mesh, near_props,
			_authored_day_material() if authored != null else _prop_material(),
			"AuthoredSignalPylons" if authored != null else "PortSensors", 210.0,
			near_tints if authored != null else PackedColorArray())
	if instance != null and authored != null:
		instance.set_meta("authored_asset_id", DAY_PYLON_ASSET)
		if OS.is_debug_build():
			instance.set_meta("authored_source_transforms", near_props.duplicate())


func _build_day_port_modules(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var modules: Array[Transform3D] = []
	var module_tints := PackedColorArray()
	var module_count := maxi(1, roundi(float(rng.randi_range(2, 3)) * chunk.dressing_density))
	var cluster_side := -1.0 if rng.randf() < 0.5 else 1.0
	for i: int in module_count:
		var side := cluster_side if i < 2 else -cluster_side
		var sx := rng.randf_range(0.82, 1.10)
		var sy := sx * rng.randf_range(0.88, 1.14)
		var sz := sx * rng.randf_range(0.92, 1.08)
		var module_x := rng.randf_range(9.2, 15.8)
		modules.append(Transform3D(
				Basis(Vector3.UP, -side * PI * 0.5 + rng.randf_range(-0.18, 0.18))
						.scaled(Vector3(sx, sy, sz)),
				Vector3(side * module_x, _shelf_y_at(module_x),
						-(RunnerConfig.CHUNK_LENGTH / float(module_count))
								* (float(i) + rng.randf_range(0.30, 0.68)))))
		module_tints.append([
				Color(1.0, 1.0, 1.0, 1.0),
				Color(0.91, 0.98, 1.0, 1.0),
				Color(1.0, 0.96, 0.88, 1.0),
		][posmod(chunk.index * 2 + i, 3)])
	# Leave authored negative-space chunks even on high. Equipment clusters now
	# frame destination landmarks instead of forming two continuous lab walls.
	if posmod(chunk.index, 4) == 2 \
			or (chunk.dressing_density < 0.99 and posmod(chunk.index, 5) == 3):
		return
	if not _supporting_family_enabled(chunk.index, 2, chunk.dressing_density):
		return
	var authored := _authored_day_mesh(DAY_LAB_ASSET)
	var mesh: Mesh = authored if authored != null else _research_module_mesh()
	var instance := _add_multimesh(chunk, mesh, modules,
			_authored_day_material() if authored != null else _prop_material(),
			"AuthoredResearchLabs" if authored != null else "ResearchModules", 420.0,
			module_tints if authored != null else PackedColorArray())
	if instance != null and authored != null:
		instance.set_meta("authored_asset_id", DAY_LAB_ASSET)


## Seeded cargo clusters create a second near/mid rhythm without occupying a
## gameplay lane. Placement consumes only art_rng and therefore cannot affect
## obstacle generation, replay order, or score determinism.
func _build_day_port_cargo(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var authored := _authored_day_mesh(DAY_CARGO_ASSET)
	if authored == null or not _supporting_family_enabled(chunk.index, 1, chunk.dressing_density):
		return
	var stacks: Array[Transform3D] = []
	var cargo_tints := PackedColorArray()
	var count := maxi(1, roundi(float(rng.randi_range(2, 4)) * chunk.dressing_density))
	for index: int in count:
		var side := -1.0 if (chunk.index + index) % 2 == 0 else 1.0
		var x := rng.randf_range(7.2, 11.4)
		var scale_value := rng.randf_range(0.72, 0.98)
		stacks.append(Transform3D(
				Basis(Vector3.UP, rng.randf_range(-0.42, 0.42))
						.scaled(Vector3(scale_value,
								scale_value * rng.randf_range(0.90, 1.12),
								scale_value * rng.randf_range(0.92, 1.06))),
				Vector3(side * x, _shelf_y_at(x),
						-(RunnerConfig.CHUNK_LENGTH / float(count))
								* (float(index) + rng.randf_range(0.28, 0.72)))))
		cargo_tints.append([
				Color(1.0, 1.0, 1.0, 1.0),
				Color(0.90, 0.98, 1.0, 1.0),
				Color(1.0, 0.92, 0.83, 1.0),
		][posmod(chunk.index + index, 3)])
	if posmod(chunk.index, 4) == 1 \
			or (chunk.dressing_density < 0.99 and posmod(chunk.index, 4) == 3):
		return
	var instance := _add_multimesh(chunk, authored, stacks, _authored_day_material(),
			"AuthoredCargoStacks", 280.0, cargo_tints)
	if instance != null:
		instance.set_meta("authored_asset_id", DAY_CARGO_ASSET)


func _build_day_port_landmark(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var landmark_mesh: Mesh = null
	var landmark_name := ""
	var landmark_asset_id := ""
	var landmark_x := 0.0
	var landmark_y := -SHELF_DROP
	var landmark_z := -RunnerConfig.CHUNK_LENGTH * 0.60
	var landmark_yaw := 0.0
	var landmark_scale := 1.0
	# Three hero destinations across twelve chunks. Each gets four chunks of
	# visual ownership; V7 repeated five huge landmarks inside the 360 m slice.
	match posmod(chunk.index, 12):
		0:
			landmark_asset_id = DAY_RADAR_ASSET
			landmark_mesh = _authored_day_mesh(landmark_asset_id)
			if landmark_mesh == null:
				landmark_mesh = _radar_landmark_mesh()
			landmark_name = "RadarLandmark"
			var side := -1.0 if posmod(floori(float(chunk.index) / 12.0), 2) == 0 else 1.0
			landmark_x = side * rng.randf_range(18.0, 23.0)
			landmark_yaw = -side * PI * 0.5
			landmark_scale = rng.randf_range(1.34, 1.62)
		4:
			landmark_asset_id = DAY_HUB_ASSET
			landmark_mesh = _authored_day_mesh(landmark_asset_id)
			if landmark_mesh == null:
				landmark_mesh = _crane_landmark_mesh()
			landmark_name = "ResearchHubLandmark"
			var side := 1.0 if posmod(floori(float(chunk.index) / 12.0), 2) == 0 else -1.0
			landmark_x = side * rng.randf_range(22.0, 28.0)
			landmark_z = -RunnerConfig.CHUNK_LENGTH * 0.72
			landmark_yaw = -side * PI * 0.5
			landmark_scale = rng.randf_range(1.04, 1.20) \
					if _authored_day_mesh(landmark_asset_id) != null \
					else rng.randf_range(0.95, 1.18)
		8:
			landmark_asset_id = DAY_ICEBREAKER_ASSET
			landmark_mesh = _authored_day_mesh(landmark_asset_id)
			if landmark_mesh == null:
				landmark_mesh = _icebreaker_landmark_mesh()
			landmark_name = "IcebreakerLandmark"
			var side := -1.0 if posmod(floori(float(chunk.index) / 12.0), 2) == 0 else 1.0
			landmark_x = side * rng.randf_range(28.0, 36.0)
			landmark_y = -SHELF_DROP - 1.8
			landmark_z = -RunnerConfig.CHUNK_LENGTH * 0.92
			landmark_yaw = rng.randf_range(-0.22, 0.22)
			landmark_scale = rng.randf_range(1.84, 2.12)
	# High keeps the full authored landmark cadence. Lower presets retain the
	# same three landmark families but thin instances without changing meshes.
	if landmark_mesh != null and rng.randf() > chunk.dressing_density:
		landmark_mesh = null
	if landmark_mesh != null:
		if landmark_name != "IcebreakerLandmark":
			landmark_y = _shelf_y_at(absf(landmark_x))
		var transform := Transform3D(
				Basis(Vector3.UP, landmark_yaw).scaled(Vector3.ONE * landmark_scale),
				Vector3(landmark_x, landmark_y, landmark_z))
		var authored := not landmark_asset_id.is_empty() \
				and _authored_day_mesh(landmark_asset_id) != null
		var instance := _add_multimesh(chunk, landmark_mesh, [transform],
				_authored_day_material() if authored else _prop_material(),
				"Authored%s" % landmark_name if authored else landmark_name, 900.0)
		if instance != null and authored:
			instance.set_meta("authored_asset_id", landmark_asset_id)


## Pennants on the kerb crown. The strongest speed cue in the whole scene: they
## are the only dressing close enough to the camera to stream past at full
## parallax, and they flap, so peripheral vision reads motion even on a stretch
## where the deck ahead is empty.
func _build_banners(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var banners: Array[Transform3D] = []
	var x := RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS * 0.5
	var spacing := 7.5
	var z := -rng.randf_range(1.0, spacing)
	var bay := 0
	while z > -RunnerConfig.CHUNK_LENGTH:
		# Alternate sides instead of mirroring every pennant. This keeps the near
		# speed rhythm while making the port feel placed rather than stamped.
		var sign_x := -1.0 if (bay + chunk.index) % 2 == 0 else 1.0
		var s := rng.randf_range(0.9, 1.15)
		banners.append(Transform3D(
				Basis(Vector3.UP, PI * 0.5 * sign_x).scaled(Vector3(s, s, s)),
				Vector3(sign_x * x, WALL_HEIGHT, z)))
		z -= spacing
		bay += 1
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
	if not _decorative_family_enabled(chunk.index, 1, chunk.dressing_density):
		return
	chunk.register_anim(_add_multimesh(chunk, _shard_mesh(), shards,
			VisualLibrary.rock_material(Color(0.86, 0.94, 1.0), 0.3), "Shards", 150.0),
			shards, RunnerChunk.ANIM_TUMBLE)


## High always draws every family. Medium carries each family every third
## chunk; low uses a four-chunk cadence. Drifts, port architecture, silhouettes
## and all gameplay cues remain present, so this removes repeated draws rather
## than flattening the scene.
func _decorative_family_enabled(chunk_index: int, phase: int, density: float) -> bool:
	if density >= 0.99:
		return true
	var cadence := 3 if density >= 0.5 else 4
	return posmod(chunk_index + phase, cadence) == 0


## Larger supporting forms stay denser than small garnish: medium keeps two of
## every three placements and low keeps alternating placements. Phases keep a
## chunk from losing every depth band at once.
func _supporting_family_enabled(chunk_index: int, phase: int, density: float) -> bool:
	if density >= 0.99:
		return true
	var cadence := 3 if density >= 0.5 else 2
	return posmod(chunk_index + phase, cadence) != 0


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
## game's aurora shader; the runner's scene-specific ShaderWarmup probe links
## it and uploads this exact mesh before countdown, so a night band costs one
## draw call and no first-sight stall.
func _build_aurora(chunk: RunnerChunk, rng: RandomNumberGenerator) -> void:
	var curtain := MeshInstance3D.new()
	curtain.name = "Aurora"
	curtain.mesh = _curtain_mesh()
	# Dimmed and widened from the library default. At full strength a curtain
	# this far out resolves to a small, very bright core, and a bright core on a
	# dark sky is a needle rather than a curtain.
	curtain.material_override = _aurora_material()
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
## plus two static fixture/wash cues. Compatibility took 3.1 seconds to render
## a representative three-omni frame even behind loading; dynamic tunnel lights
## therefore cannot meet either loading or runtime pacing. These cues preserve
## the two-lamp rhythm with vertex colour on an existing shader signature.
func _build_tunnel(chunk: RunnerChunk) -> void:
	var segments: Array[Transform3D] = []
	var count := int(ceil(RunnerConfig.CHUNK_LENGTH / TUNNEL_SEGMENT))
	for i: int in count:
		segments.append(Transform3D(Basis(), Vector3(0.0, 0.0, -float(i) * TUNNEL_SEGMENT)))
	var authored := _authored_day_mesh(DAY_TUNNEL_ASSET) if chunk.biome == Biome.DAY else null
	var mesh: Mesh = authored if authored != null else _tunnel_mesh()
	var instance := _add_multimesh(chunk, mesh, segments,
			_authored_day_material(false) if authored != null else _prop_material(),
			"AuthoredTunnel" if authored != null else "Tunnel", 260.0)
	if instance != null and authored != null:
		instance.set_meta("authored_asset_id", DAY_TUNNEL_ASSET)
	var cue_transforms: Array[Transform3D] = []
	for i: int in TUNNEL_LIGHT_CUES_PER_CHUNK:
		cue_transforms.append(Transform3D(Basis(), Vector3(0.0, 0.0,
				-RunnerConfig.CHUNK_LENGTH * (0.25 + 0.5 * float(i)))))
	var cues := _add_multimesh(chunk, _tunnel_light_cue_mesh(), cue_transforms,
			_mark_material(), "TunnelLightCues", 260.0)
	if cues != null:
		cues.set_meta("static_light_cues", TUNNEL_LIGHT_CUES_PER_CHUNK)


## Dimmed and widened from the library default. At full strength a curtain this
## far out resolves to a small, very bright core, and a bright core on a dark
## sky is a needle rather than a curtain.
static func _aurora_material() -> ShaderMaterial:
	return VisualLibrary.shader_variant(VisualLibrary.aurora_material(), {
		"max_alpha": 0.30,
		"intensity": 0.85,
		"band_scale": 2.2,
	})


func _add_multimesh(parent: Node3D, mesh: Mesh, transforms: Array[Transform3D],
		material: Material, name_hint: String, range_base: float,
		colors: PackedColorArray = PackedColorArray(),
		gameplay_surface: bool = false) -> MultiMeshInstance3D:
	if transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# use_colors has to be set BEFORE instance_count: the instance buffer is
	# allocated at that assignment, and turning colours on afterwards leaves
	# them silently unwritable. (Same trap _flush_marks() documents.)
	if not colors.is_empty():
		mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if not colors.is_empty():
			mm.set_instance_color(i, colors[i % colors.size()])
	var instance := MultiMeshInstance3D.new()
	instance.name = name_hint
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Instance density alone does not reduce draw calls: one remaining prop still
	# costs its whole MultiMesh draw. Lower tiers therefore shorten only the
	# presentation range as well. High stays bit-for-bit uncapped because
	# VisualLibrary treats its range scale as zero; medium still retains its
	# strongest near/mid cues through the 70 m gameplay horizon.
	instance.set_meta("runner_dressing_base_range", range_base)
	if gameplay_surface:
		instance.set_meta("runner_gameplay_surface", true)
	var chunk := parent as RunnerChunk
	if chunk != null:
		chunk.apply_dressing_range(instance, chunk.dressing_density, chunk.dressing_range_scale)
	else:
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
	_prime_authored_day_cache()
	_deck_mesh()
	_seam_mesh()
	_verge_mesh()
	_authored_day_shelf_mesh()
	_block_mesh()
	_low_mesh()
	ReferenceIce.material()
	_arch_mesh()
	_fish_mesh()
	_ramp_mesh()
	_seal_mesh()
	_tunnel_mesh()
	_tunnel_light_cue_mesh()
	_mark_mesh()
	_banner_mesh()
	_port_prop_mesh()
	_research_module_mesh()
	_radar_landmark_mesh()
	_crane_landmark_mesh()
	_icebreaker_landmark_mesh()
	_bird_mesh()
	_shard_mesh()
	_curtain_mesh()
	_powerup_ring_mesh()
	_fish_material()
	for id: StringName in RunnerConfig.POWERUP_IDS:
		_crate_mesh(id)
	_prime_dressing_cache()
	_register_shader_warmup_probes()


## ShaderWarmup can only discover nodes present in the opening chunks. These
## exact pairs cover gameplay verbs and biome art which may first stream in
## minutes later; their real vertex buffers and pipelines are drawn under the
## runner loading overlay before countdown instead of on first contact.
func _register_shader_warmup_probes() -> void:
	var prop := _prop_material()
	# DAY uses authored atlas decking, so the shared ice program does not enter
	# the live tree until the first procedural DUSK band. Submit that exact
	# streamed mesh/material pair now; constructing the cached material alone
	# never links its Compatibility pipeline.
	_register_runner_warmup_probe(
			_deck_mesh(), _deck_material(Biome.DUSK, false))
	# The authored DAY cassettes also replace the procedural seams and verge.
	# These buffers are private RunnerTrack caches, not VisualLibrary meshes;
	# generic material probes and the opening DAY shelf cannot submit them.
	# Keep the verge's four actual surface overrides on one exact mesh instance:
	# together with seams this uses the two remaining fresh-runner probe slots.
	_register_runner_warmup_probe(_seam_mesh(), _seam_material(Biome.DUSK))
	_register_runner_warmup_probe(_verge_mesh(), null, [
		_kerb_body_material(Biome.DUSK), _kerb_crown_material(Biome.DUSK),
		_kerb_deep_material(Biome.DUSK), _verge_snow_material(Biome.DUSK, false),
	])
	_register_runner_warmup_probe(_block_mesh(), ReferenceIce.material())
	_register_runner_warmup_probe(_low_mesh(), ReferenceIce.material())
	_register_runner_warmup_probe(_arch_mesh(), prop)
	_register_runner_warmup_probe(_ramp_mesh(), prop)
	_register_runner_warmup_probe(_seal_mesh(), prop)
	# Procedural tunnel faces are wound inward, so the shared prop material is
	# sufficient from inside and avoids a late cull-disabled shader signature.
	_register_runner_warmup_probe(_tunnel_mesh(), _prop_material())
	_register_runner_warmup_probe(_tunnel_light_cue_mesh(), _mark_material())
	_register_runner_warmup_probe(_fish_mesh(), _fish_material())
	_register_runner_warmup_probe(_mark_mesh(), _mark_material())
	for id: StringName in RunnerConfig.POWERUP_IDS:
		_register_runner_warmup_probe(_crate_mesh(id), _powerup_shell_material(id))
	var powerup_tint := _powerup_colour(RunnerConfig.POWERUP_MAGNET)
	_register_runner_warmup_probe(_powerup_ring_mesh(),
			VisualLibrary.emissive_material(powerup_tint * 0.42, powerup_tint, 1.8, 0.2))
	_register_runner_warmup_probe(_curtain_mesh(), _aurora_material())
	# DAY GLBs use one external atlas material family. Draw exact imported
	# buffers behind loading overlay; no first-sight upload during capture/run.
	for asset_id: String in DAY_WARMUP_ASSETS:
		var mesh := _authored_day_mesh(asset_id)
		if mesh != null:
			if asset_id == DAY_ICEBERG_ASSET:
				_register_runner_warmup_probe(ReferenceIce.sea_mesh(mesh), ReferenceIce.material())
			else:
				_register_runner_warmup_probe(mesh, _authored_day_draw_material(asset_id))


func _register_runner_warmup_probe(mesh: Mesh, material: Material,
		surface_materials: Array[Material] = []) -> void:
	ShaderWarmup.register_external_probe(mesh, material, surface_materials,
			SHADER_WARMUP_SCOPE)


## Everything a STREAMED chunk could otherwise build for the first time
## mid-run. Without this the first chunk of each biome, and the first chunk to
## roll a berg silhouette the run has not used yet, pay for a mesh build or a
## material construction inside update_stream() -- measured at 9 ms against a
## 0.5 ms average, which is a visible hitch in a mode whose entire job is
## smooth forward motion.
func _prime_dressing_cache() -> void:
	VisualLibrary.snow_drift_mesh()
	VisualLibrary.ice_crystal_mesh()
	VisualLibrary.contact_patch_mesh()
	VisualLibrary.contact_shadow_material(0.22)
	VisualLibrary.contact_shadow_material(0.34)
	VisualLibrary.contact_shadow_material(0.3)
	VisualLibrary.rock_material(Color.WHITE, 0.6)
	VisualLibrary.rock_material(Color(0.86, 0.94, 1.0), 0.3)
	VisualLibrary.rock_material(Color(0.24, 0.28, 0.36), 0.9)
	_prop_material()
	_mark_material()
	_aurora_material()
	_curtain_mesh()
	# berg_mesh() builds a fresh seeded silhouette per variant; _build_dressing
	# draws from exactly these four, so this is the whole set.
	for variant: int in [101, 211, 331, 449]:
		VisualLibrary.berg_mesh(variant)
	for biome: int in BIOME_COUNT:
		var ice := _biome_ice_tint(biome)
		VisualLibrary.ice_material(ice, 0.5)
		_seam_material(biome)
		_kerb_body_material(biome)
		_kerb_crown_material(biome)
		_kerb_deep_material(biome)
		VisualLibrary.rock_material(_biome_shelf_tint(biome), 0.88)
		VisualLibrary.rock_material(ice, 0.25)
		VisualLibrary.rock_material(_biome_far_tint(biome), 0.72)
		for tunnel: int in 2:
			_deck_material(biome, tunnel == 1)
			_verge_snow_material(biome, tunnel == 1)
	for id: StringName in RunnerConfig.POWERUP_IDS:
		var tint := _powerup_colour(id)
		_powerup_shell_material(id)
		VisualLibrary.emissive_material(tint * 0.42, tint, 1.8, 0.2)


## Shared vertex-colour material for obstacles, fish and props. rock_material
## multiplies baked vertex colours into the tint, which is how one material can
## carry a dark ice block, a hot-orange fin and a pale ice ridge at once.
static func _prop_material() -> StandardMaterial3D:
	# Softer painted hardware keeps the established vertex-colour verb liveries.
	return VisualLibrary.rock_material(Color(1.0, 0.985, 0.965), 0.62)


## Collectibles share one glossy material distinct from matte scenery. Vertex
## colours carry the blue counter-shading, so every fish in a chunk remains one
## MultiMesh draw while catching a clean highlight at speed.
static func _fish_material() -> StandardMaterial3D:
	if _fish_material_cache == null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.WHITE
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.24
		mat.metallic = 0.12
		# Low lift keeps the shared blue fish cue visible in shadow without turning
		# each MultiMesh fish into an unshaded lamp.
		mat.emission_enabled = true
		mat.emission = Color(0.03, 0.42, 0.80)
		mat.emission_energy_multiplier = 0.16
		_fish_material_cache = mat
	return _fish_material_cache


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


## Compatibility facade retained for focused tests and older callers. Tunnel
## faces are authored with inward front-face winding, so the existing shared
## prop signature renders the interior without a separate cull-disabled shader.
static func _tunnel_material() -> StandardMaterial3D:
	return _prop_material()


static func _deck_mesh() -> PlaneMesh:
	if _deck_mesh_cache != null:
		return _deck_mesh_cache
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(RunnerConfig.DECK_HALF_WIDTH * 2.0, RunnerConfig.CHUNK_LENGTH)
	mesh.orientation = PlaneMesh.FACE_Y
	_deck_mesh_cache = mesh
	return _deck_mesh_cache


## Purely visual runway behind z=0. The real first chunk begins at the hero,
## which otherwise leaves a hard rectangular cutoff across the opening shot.
## This uses an already-warm deck mesh/material and never touches collisions,
## patterns, RNG, or obstacle spacing.
func _build_start_apron() -> void:
	var opening_ice: MeshInstance3D = null
	if not _chunks.is_empty():
		opening_ice = _chunks[0].get_node_or_null("GlacialIceSkin") as MeshInstance3D
		if opening_ice == null:
			opening_ice = _chunks[0].get_node_or_null("Deck") as MeshInstance3D
	var apron := Node3D.new()
	apron.name = "StartApron"
	add_child(apron)
	var ice := MeshInstance3D.new()
	ice.name = "StartIce"
	ice.mesh = _deck_mesh()
	ice.material_override = opening_ice.material_override if opening_ice != null \
			else _deck_material(Biome.DAY, false)
	# Meet the actual opening surface exactly. A separate 0.018 m apron sat
	# below authored ice (0.022 m) and above procedural ice (0.0 m), leaving a
	# full-width raster seam through the penguin's feet during the countdown.
	ice.position = Vector3(0.0, opening_ice.position.y if opening_ice != null else 0.0,
			RunnerConfig.CHUNK_LENGTH * 0.5)
	ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ice.visibility_range_end = 65.0
	apron.add_child(ice)
	# Continue both snow shoulders too. Extending only the centre ice left a
	# conspicuous transverse world edge outside the kerbs in the opening shot.
	var shelf := MeshInstance3D.new()
	shelf.name = "StartSnowShoulders"
	shelf.mesh = _authored_day_shelf_mesh()
	shelf.material_override = _verge_snow_material(Biome.DAY, false)
	shelf.position.z = RunnerConfig.CHUNK_LENGTH
	shelf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shelf.visibility_range_end = 65.0
	apron.add_child(shelf)


static func _seam_mesh() -> ArrayMesh:
	if _seam_mesh_cache != null:
		return _seam_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := RunnerConfig.LANE_WIDTH * 0.025
	var col := Color(1.0, 1.0, 1.0)
	for i: int in RunnerConfig.LANE_COUNT - 1:
		var x := (RunnerConfig.lane_x(i) + RunnerConfig.lane_x(i + 1)) * 0.5
		# Short inlaid bars read as constructed deck hardware and give speed a
		# countable cadence. One cached mesh/surface: no draw-call increase.
		var z := -0.8
		while z > -RunnerConfig.CHUNK_LENGTH:
			var z_end := maxf(z - 3.8, -RunnerConfig.CHUNK_LENGTH)
			_quad_out(st,
					Vector3(x - half, 0.012, z),
					Vector3(x + half, 0.012, z),
					Vector3(x + half, 0.012, z_end),
					Vector3(x - half, 0.012, z_end),
					Vector3.UP, col, col, col, col)
			z -= 5.6
	st.generate_normals()
	_seam_mesh_cache = st.commit()
	return _seam_mesh_cache


## Snowfield-only companion for authored DAY cassettes. Their modeled kerbs
## replace verge surfaces 0-2; reusing just this shelf avoids overlapping dark
## walls while preserving same near/mid dressing ground and horizon shape.
static func _authored_day_shelf_mesh() -> ArrayMesh:
	if _authored_day_shelf_mesh_cache != null:
		return _authored_day_shelf_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := RunnerConfig.CHUNK_LENGTH
	var inner := RunnerConfig.DECK_HALF_WIDTH + WALL_THICKNESS
	var white := Color.WHITE
	for side: int in 2:
		var sign_x := -1.0 if side == 0 else 1.0
		var edge := sign_x * RunnerConfig.DECK_HALF_WIDTH
		var xi := sign_x * inner
		var xf := sign_x * SHELF_WIDTH
		var facing := Vector3(sign_x, 0.0, 0.0)
		_quad_out(st, Vector3(edge, AUTHORED_DAY_DECK_Y, 0.0),
				Vector3(xi, -SHELF_DROP, 0.0),
				Vector3(xi, -SHELF_DROP, -length),
				Vector3(edge, AUTHORED_DAY_DECK_Y, -length),
				facing, white, white, white, white)
		_quad_out(st, Vector3(xi, -SHELF_DROP, 0.0),
				Vector3(xf, -SHELF_DROP + 0.9, 0.0),
				Vector3(xf, -SHELF_DROP + 0.9, -length),
				Vector3(xi, -SHELF_DROP, -length),
				Vector3.UP, white, white, white, white)
	st.generate_normals()
	_authored_day_shelf_mesh_cache = st.commit()
	return _authored_day_shelf_mesh_cache


## Kerb wall, drop-off face and the snowfield below, both sides, in one mesh —
## in FOUR surfaces, one per luminance tier the verge has to span:
##   0 wall body   MID    (opaque blue frames and recessed navy inserts)
##   1 crown cap   BRIGHT (emissive; the light source in the dark bands)
##   2 drop face   DARK   (vertex-ramped, tinted per band)
##   3 snow shelf  BRIGHT (snow shader)
##
## One surface with a baked crown-to-deep gradient was the previous design and
## it did nothing at all: neither the ice nor the snow shader reads ARRAY_COLOR,
## so the whole authored ramp was dead data and the wall rendered as one flat
## value. Surface 2 is the only one whose vertex colours survive, and it is on a
## StandardMaterial3D for exactly that reason.
static func _verge_mesh() -> ArrayMesh:
	if _verge_mesh_cache != null:
		return _verge_mesh_cache
	var mesh := ArrayMesh.new()
	var length := RunnerConfig.CHUNK_LENGTH
	var inner := RunnerConfig.DECK_HALF_WIDTH
	var outer := inner + WALL_THICKNESS
	var w := Color.WHITE
	# Surface 0: reference blue frames and real recessed panels. Same canonical
	# wall envelope and six-metre joints as DAY; cap and deep drop stay separate.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ReferenceWalls.append_bays(st, length, WALL_HEIGHT - 0.16, 0.0, WALL_HEIGHT - 1.0)
	st.commit(mesh)
	# Surface 1: the crown cap, plus a 16 cm lip carried down both faces so the
	# bright edge is visible from the deck AND from outside the corridor. This
	# strip is the brightest continuous line in the frame and it runs to the
	# vanishing point, which is most of what gives the corridor its perspective.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var xi := sign_x * inner
		var xo := sign_x * outer
		var facing := Vector3(-sign_x, 0.0, 0.0)
		_quad_out(st, Vector3(xi, WALL_HEIGHT, 0.0), Vector3(xo, WALL_HEIGHT, 0.0),
				Vector3(xo, WALL_HEIGHT, -length), Vector3(xi, WALL_HEIGHT, -length),
				Vector3.UP, w, w, w, w)
		_quad_out(st, Vector3(xi, WALL_HEIGHT - 0.16, 0.0), Vector3(xi, WALL_HEIGHT, 0.0),
				Vector3(xi, WALL_HEIGHT, -length), Vector3(xi, WALL_HEIGHT - 0.16, -length),
				facing, w, w, w, w)
		_quad_out(st, Vector3(xo, WALL_HEIGHT, 0.0), Vector3(xo, WALL_HEIGHT - 0.16, 0.0),
				Vector3(xo, WALL_HEIGHT - 0.16, -length), Vector3(xo, WALL_HEIGHT, -length),
				-facing, w, w, w, w)
	st.generate_normals()
	st.commit(mesh)
	# Surface 2: the drop-off face. Ramped from the wall value at the top to a
	# third of it at the shelf line, so the DARK band that separates the MID
	# deck from the BRIGHT shelf is darkest exactly where the two would
	# otherwise touch.
	var high := Color(1.0, 1.0, 1.0)
	var low := Color(0.34, 0.36, 0.42)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var xo := sign_x * outer
		var facing := Vector3(sign_x, 0.0, 0.0)
		_quad_out(st, Vector3(xo, WALL_HEIGHT - 1.0, 0.0), Vector3(xo, -SHELF_DROP, 0.0),
				Vector3(xo, -SHELF_DROP, -length), Vector3(xo, WALL_HEIGHT - 1.0, -length),
				facing, high, low, low, high)
	st.generate_normals()
	st.commit(mesh)
	# Surface 3: the snow shelf.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var xo := sign_x * outer
		var xf := sign_x * SHELF_WIDTH
		_quad_out(st, Vector3(xo, -SHELF_DROP, 0.0), Vector3(xf, -SHELF_DROP + 0.9, 0.0),
				Vector3(xf, -SHELF_DROP + 0.9, -length), Vector3(xo, -SHELF_DROP, -length),
				Vector3.UP, w, w, w, w)
	st.generate_normals()
	st.commit(mesh)
	_verge_mesh_cache = mesh
	return _verge_mesh_cache


## Full-height snow-crowned ice boulder. Uses the same lane-blocking envelope
## as before; mesh/material changes never consume pattern RNG or affect pickups.
static func _block_mesh() -> ArrayMesh:
	return ReferenceIce.block_mesh()


## Jumpable snow-crowned ridge. Keep the exact original collider envelope;
## the taller reference chunks use BLOCK collision and their own cached mesh.
static func _low_mesh() -> ArrayMesh:
	return ReferenceIce.ridge_mesh()


## Full-deck research-port service gantry. Slim threshold beam plus open truss
## communicates the same full-span slide collider without presenting a metre of
## anonymous wall. Legs remain outside the decision lanes.
static func _arch_mesh() -> ArrayMesh:
	if _arch_mesh_cache != null:
		return _arch_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := RunnerConfig.DECK_HALF_WIDTH
	var foot := _vc(Color(0.025, 0.08, 0.14))
	var body := _vc(Color(0.18, 0.42, 0.56))
	var crown := _vc(Color(0.88, 0.96, 0.98))
	var duck := _vc(_verb_duck())
	var accent := _vc(Color(1.0, 0.42, 0.08))
	var y0 := BAR_CLEARANCE
	var y1 := BAR_CLEARANCE + BAR_THICKNESS
	var depth := BAR_DEPTH * 0.5
	# Thin physical threshold exactly at slide height, with a cyan underside.
	_box_faces(st, Vector3(-half, y0 + 0.08, -depth),
			Vector3(half, y0 + 0.34, depth), body, crown)
	_box_faces(st, Vector3(-half, y0, -depth - 0.05),
			Vector3(half, y0 + 0.10, depth + 0.05), foot, duck)
	# Open upper truss occupies the rest of the collider's visual envelope.
	_box_faces(st, Vector3(-half, y1 - 0.14, -depth * 0.72),
			Vector3(half, y1 + 0.04, depth * 0.72), foot, crown)
	var joints: PackedFloat32Array = PackedFloat32Array([-half + 0.28, -2.65, 0.0, 2.65, half - 0.28])
	for i: int in joints.size() - 1:
		var from_y := y0 + 0.32 if i % 2 == 0 else y1 - 0.12
		var to_y := y1 - 0.12 if i % 2 == 0 else y0 + 0.32
		_flat_beam_xy(st, Vector2(joints[i], from_y), Vector2(joints[i + 1], to_y),
				0.13, depth + 0.035, body)
	for s: int in 2:
		var sign_x := -1.0 if s == 0 else 1.0
		var cx := sign_x * (half - 0.18)
		_box_faces(st, Vector3(cx - 0.18, 0.0, -0.28),
				Vector3(cx + 0.18, y1 + 0.20, 0.28), foot, body)
		_box_faces(st, Vector3(cx - 0.34, 0.0, -0.48),
				Vector3(cx + 0.34, 0.14, 0.48), foot, accent)
	# Centre diamond repeats the duck colour as shape, not just hue.
	var sign_z := depth + 0.06
	for face: int in 2:
		var z := sign_z if face == 0 else -sign_z
		var facing := Vector3.BACK if face == 0 else Vector3.FORWARD
		var centre := Vector3(0.0, y1 - 0.02, z)
		for quadrant: int in 4:
			var a := TAU * float(quadrant) / 4.0
			var b := TAU * float(quadrant + 1) / 4.0
			_tri_out(st, centre,
					centre + Vector3(cos(a) * 0.34, sin(a) * 0.34, 0.0),
					centre + Vector3(cos(b) * 0.34, sin(b) * 0.34, 0.0),
					facing, duck, duck, crown)
	st.generate_normals()
	_arch_mesh_cache = st.commit()
	return _arch_mesh_cache


## Curved ice launch: continuous pale run-up, carved side facets and one small
## green takeoff mark. No dark metal rails or big painted chevrons.
static func _ramp_mesh() -> ArrayMesh:
	if _ramp_mesh_cache != null:
		return _ramp_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := RAMP_WIDTH * 0.5
	var z_near := RAMP_DEPTH * 0.5
	var z_far := -RAMP_DEPTH * 0.5
	var flank := _vc(Color(0.12, 0.34, 0.49))
	var foot := Color(0.38, 0.66, 0.78)
	var crown := Color(0.78, 0.94, 0.98)
	var ice_edge := _vc(Color(0.91, 0.98, 1.0))
	var go := _vc(Color(0.22, 0.94, 0.47))
	var strips := 12
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
		var c0 := _vc(foot.lerp(crown, u0))
		var c1 := _vc(foot.lerp(crown, u1))
		_quad_out(st, Vector3(-hx, y0, z0), Vector3(hx, y0, z0),
				Vector3(hx, y1, z1), Vector3(-hx, y1, z1), top_n, c0, c0, c1, c1)
		# Thin ice lips catch light without changing the collider silhouette.
		for side: float in [-1.0, 1.0]:
			var edge_x := side * (hx - 0.10)
			_quad_out(st, Vector3(edge_x - 0.04, y0 + 0.013, z0),
					Vector3(edge_x + 0.04, y0 + 0.013, z0),
					Vector3(edge_x + 0.04, y1 + 0.013, z1),
					Vector3(edge_x - 0.04, y1 + 0.013, z1),
					top_n, ice_edge, ice_edge, ice_edge, ice_edge)
		if i == 8:
			_tri_out(st, Vector3(-0.28, y0 + 0.018, z0),
					Vector3(0.28, y0 + 0.018, z0),
					Vector3(0.0, y1 + 0.018, z1), top_n, go, go, go)
		for s: int in 2:
			var sx := -hx if s == 0 else hx
			var facing := Vector3(-1.0 if s == 0 else 1.0, 0.0, 0.0)
			_quad_out(st, Vector3(sx, 0.0, z0), Vector3(sx, 0.0, z1),
					Vector3(sx, y1, z1), Vector3(sx, y0, z0), facing, flank, flank, flank, flank)
	# Small luminous inlay at the takeoff edge; blue ice remains dominant.
	_quad_out(st, Vector3(-hx, RAMP_HEIGHT, z_far), Vector3(hx, RAMP_HEIGHT, z_far),
			Vector3(hx, 0.0, z_far), Vector3(-hx, 0.0, z_far), Vector3.FORWARD,
			ice_edge, ice_edge, flank, flank)
	_box_faces(st, Vector3(-hx, RAMP_HEIGHT - 0.02, z_far - 0.06),
			Vector3(hx, RAMP_HEIGHT + 0.08, z_far + 0.13), flank, ice_edge)
	_box_faces(st, Vector3(-0.31, RAMP_HEIGHT + 0.08, z_far - 0.035),
			Vector3(0.31, RAMP_HEIGHT + 0.095, z_far + 0.10), go, go)
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
	# Same linear-space caveat as the ridge: authored warm, this arrives on
	# screen as gold. Pushed red so the shoulder band reads as the hazard
	# marking it is rather than as a highlight.
	var band := Color(0.96, 0.20, 0.006)
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
	# A CEILING, not a sky. The player is inside this thing, so the vault fills
	# the whole upper frame -- which means any pale blue-white palette resolves
	# to something indistinguishable from the sky it replaced and the tunnel
	# reads as no tunnel at all. (Not a hypothesis: a magenta test render showed
	# the shell had been there the whole time, wearing the sky's colour.) So the
	# vault is a deep teal several stops below the sky, and the RIBS are the
	# bright thing -- lit bands sweeping overhead are the entire reason to build
	# a tunnel in a runner.
	var vault := Color(0.42, 0.58, 0.78)
	var shade := Color(0.15, 0.24, 0.42)
	var rib := Color(0.88, 0.97, 1.0)
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
		# Ribs every 1.5 m, dropped 26 cm below the vault so each is a visible
		# band and not a texture. FOUR per bay rather than one at the mouth:
		# this is the strobe that makes speed readable inside a tunnel, where
		# the walls otherwise give the eye nothing to count, and one band every
		# six metres is too slow to register as rhythm at 30 m/s.
		for r: int in 4:
			var rz := -float(r) * TUNNEL_SEGMENT * 0.25
			_quad_out(st, Vector3(a.x, a.y - 0.26, rz - 0.05), Vector3(b.x, b.y - 0.26, rz - 0.05),
					Vector3(b.x, b.y - 0.26, rz - 0.55), Vector3(a.x, a.y - 0.26, rz - 0.55),
					inward, rib, rib, rib, rib)
	for s: int in 2:
		var sx := (-outer + 0.35) if s == 0 else (outer - 0.35)
		_box_faces(st, Vector3(sx - 0.1, TUNNEL_SPRING - 0.28, -TUNNEL_SEGMENT),
				Vector3(sx + 0.1, TUNNEL_SPRING - 0.08, 0.0), rib, rib)
	st.generate_normals()
	_tunnel_mesh_cache = st.commit()
	return _tunnel_mesh_cache


## One visible overhead fixture plus its broad baked floor/ceiling washes.
## Instanced exactly twice per tunnel chunk at the former omni positions. The
## mark material is already used by deck communication, unshaded, alpha-safe,
## two-sided and prewarmed; this adds no shader signature and no light RID.
static func _tunnel_light_cue_mesh() -> ArrayMesh:
	if _tunnel_light_cue_mesh_cache != null:
		return _tunnel_light_cue_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var housing := Color(0.08, 0.22, 0.30, 0.94)
	var lamp := Color(0.48, 0.92, 1.0, 0.96)
	var lamp_core := Color(0.86, 0.99, 1.0, 1.0)
	var fixture_y := TUNNEL_APEX - 1.1
	# Rounded read comes from broad proportions and pale core framed by a much
	# thinner dark housing; from chase distance this remains a clean cyan bar.
	_box_faces(st, Vector3(-2.75, fixture_y - 0.02, -0.24),
			Vector3(2.75, fixture_y + 0.20, 0.24), housing, lamp)
	_box_faces(st, Vector3(-2.35, fixture_y - 0.10, -0.16),
			Vector3(2.35, fixture_y + 0.02, 0.16), lamp, lamp_core)
	# Broad floor wash: transparent radial fan, large enough to reproduce the
	# old 21 m lamps' navigational pools without pretending to light objects.
	var fan_segments := 16
	var floor_center := Color(0.30, 0.78, 0.96, 0.20)
	var floor_edge := Color(0.30, 0.78, 0.96, 0.0)
	for i: int in fan_segments:
		var a0 := TAU * float(i) / float(fan_segments)
		var a1 := TAU * float(i + 1) / float(fan_segments)
		_tri_out(st,
				Vector3(0.0, 0.032, 0.0),
				Vector3(cos(a0) * 4.7, 0.032, sin(a0) * 6.8),
				Vector3(cos(a1) * 4.7, 0.032, sin(a1) * 6.8),
				Vector3.UP, floor_center, floor_edge, floor_edge)
	# Quiet ceiling halo behind the fixture separates it from the dark vault.
	var halo_center := Color(0.42, 0.86, 1.0, 0.15)
	var halo_edge := Color(0.42, 0.86, 1.0, 0.0)
	for i: int in fan_segments:
		var a0 := TAU * float(i) / float(fan_segments)
		var a1 := TAU * float(i + 1) / float(fan_segments)
		_tri_out(st,
				Vector3(0.0, fixture_y + 0.23, 0.0),
				Vector3(cos(a0) * 3.8, fixture_y + 0.23, sin(a0) * 2.8),
				Vector3(cos(a1) * 3.8, fixture_y + 0.23, sin(a1) * 2.8),
				Vector3.DOWN, halo_center, halo_edge, halo_edge)
	st.generate_normals()
	_tunnel_light_cue_mesh_cache = st.commit()
	return _tunnel_light_cue_mesh_cache


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


## Near-field autonomous weather station: orange instrument case on a sled,
## white mast, cyan sensor head. One compact silhouette used as kerb furniture.
static func _port_prop_mesh() -> ArrayMesh:
	if _port_prop_mesh_cache != null:
		return _port_prop_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := _vc(Color(0.025, 0.07, 0.12))
	var steel := _vc(Color(0.34, 0.52, 0.62))
	var shell := _vc(Color(0.88, 0.95, 0.96))
	var orange := _vc(Color(1.0, 0.34, 0.055))
	var cyan := _vc(Color(0.10, 0.78, 0.92))
	for z: float in [-0.54, 0.54]:
		_box_faces(st, Vector3(-0.92, 0.0, z - 0.06),
				Vector3(0.92, 0.10, z + 0.06), dark, steel)
	_box_faces(st, Vector3(-0.72, 0.10, -0.46), Vector3(0.54, 0.92, 0.46),
			orange, _vc(Color(1.0, 0.58, 0.14)))
	for strap_x: float in [-0.42, 0.24]:
		_box_faces(st, Vector3(strap_x - 0.055, 0.08, -0.49),
				Vector3(strap_x + 0.055, 0.98, 0.49), dark, steel)
	_box_faces(st, Vector3(0.48, 0.12, -0.06), Vector3(0.60, 2.30, 0.06),
			dark, shell)
	_box_faces(st, Vector3(0.30, 2.12, -0.22), Vector3(0.78, 2.48, 0.22),
			steel, cyan)
	# Twin anemometer cups make the top read as instrumentation, not a signpost.
	for side: int in 2:
		var x := 0.15 if side == 0 else 0.93
		_box_faces(st, Vector3(x - 0.18, 2.35, -0.08),
				Vector3(x + 0.18, 2.47, 0.08), dark, cyan)
	st.generate_normals()
	_port_prop_mesh_cache = st.commit()
	return _port_prop_mesh_cache


## Mid-field modular polar lab. Stilts, insulated white shell, orange structural
## frame, continuous dark window band, roof solar array and antenna form a
## recognizable research-station kit from either side of the causeway.
static func _research_module_mesh() -> ArrayMesh:
	if _research_module_mesh_cache != null:
		return _research_module_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := _vc(Color(0.02, 0.075, 0.13))
	var glass := _vc(Color(0.025, 0.20, 0.31))
	var steel := _vc(Color(0.26, 0.48, 0.59))
	var shell := _vc(Color(0.84, 0.92, 0.93))
	var white := _vc(Color(0.96, 0.98, 0.96))
	var orange := _vc(Color(1.0, 0.31, 0.045))
	for x: float in [-1.95, 1.95]:
		for z: float in [-0.95, 0.95]:
			_box_faces(st, Vector3(x - 0.12, 0.0, z - 0.12),
					Vector3(x + 0.12, 1.22, z + 0.12), dark, steel)
	_box_faces(st, Vector3(-2.55, 1.05, -1.38), Vector3(2.55, 3.82, 1.38),
			steel, shell)
	# Orange exoskeleton: large edges, not fine trim, so it survives distance.
	for y: float in [1.08, 3.63]:
		_box_faces(st, Vector3(-2.62, y, -1.45), Vector3(2.62, y + 0.18, 1.45),
				dark, orange)
	for x: float in [-2.54, 2.54]:
		_box_faces(st, Vector3(x - 0.10, 1.12, -1.46),
				Vector3(x + 0.10, 3.74, 1.46), dark, orange)
	# Window band on both long faces.
	for face: int in 2:
		var z := 1.405 if face == 0 else -1.405
		var facing := Vector3.BACK if face == 0 else Vector3.FORWARD
		for bay: int in 4:
			var x0 := -2.18 + float(bay) * 1.10
			_quad_out(st, Vector3(x0, 2.18, z), Vector3(x0 + 0.86, 2.18, z),
					Vector3(x0 + 0.86, 3.18, z), Vector3(x0, 3.18, z),
					facing, glass, glass, _vc(Color(0.10, 0.48, 0.60)), glass)
	# Roof and two tilted-looking solar slabs (raised outer edges).
	_box_faces(st, Vector3(-2.35, 3.82, -1.18), Vector3(2.35, 4.02, 1.18),
			steel, white)
	for x: float in [-1.20, 1.20]:
		_box_faces(st, Vector3(x - 0.92, 4.02, -0.88),
				Vector3(x + 0.92, 4.16, 0.88), dark, glass)
	_box_faces(st, Vector3(-0.055, 4.02, -0.055), Vector3(0.055, 5.26, 0.055),
			dark, white)
	_box_faces(st, Vector3(-0.28, 5.12, -0.08), Vector3(0.28, 5.32, 0.08),
			orange, white)
	st.generate_normals()
	_research_module_mesh_cache = st.commit()
	return _research_module_mesh_cache


## Landmark 1/3: elevated radar dish and observation platform.
static func _radar_landmark_mesh() -> ArrayMesh:
	if _radar_landmark_mesh_cache != null:
		return _radar_landmark_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := _vc(Color(0.018, 0.055, 0.10))
	var steel := _vc(Color(0.20, 0.46, 0.58))
	var shell := _vc(Color(0.86, 0.95, 0.97))
	var orange := _vc(Color(1.0, 0.31, 0.04))
	var cyan := _vc(Color(0.18, 0.82, 0.96))
	for x: float in [-1.65, 1.65]:
		for z: float in [-1.10, 1.10]:
			_box_faces(st, Vector3(x - 0.15, 0.0, z - 0.15),
					Vector3(x + 0.15, 5.50, z + 0.15), dark, steel)
	_box_faces(st, Vector3(-2.25, 5.25, -1.70), Vector3(2.25, 5.62, 1.70),
			dark, orange)
	_box_faces(st, Vector3(-1.68, 5.62, -1.18), Vector3(1.68, 6.62, 1.18),
			steel, shell)
	_box_faces(st, Vector3(-0.14, 6.60, -0.14), Vector3(0.14, 9.05, 0.14),
			dark, shell)
	# Solid faceted dish in XY, deliberately oversized as skyline hierarchy.
	var centre := Vector3(0.0, 9.0, 0.24)
	var segments := 16
	for i: int in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var r0 := Vector3(cos(a0) * 2.25, sin(a0) * 2.25, 0.0)
		var r1 := Vector3(cos(a1) * 2.25, sin(a1) * 2.25, 0.0)
		_tri_out(st, centre, centre + r0, centre + r1, Vector3.BACK,
				cyan, shell, shell)
		_tri_out(st, centre + Vector3(0.0, 0.0, -0.12),
				centre + r1 + Vector3(0.0, 0.0, -0.12),
				centre + r0 + Vector3(0.0, 0.0, -0.12), Vector3.FORWARD,
				dark, steel, steel)
	_box_faces(st, Vector3(-0.08, 8.92, 0.18), Vector3(0.08, 11.65, 0.34),
			orange, shell)
	st.generate_normals()
	_radar_landmark_mesh_cache = st.commit()
	return _radar_landmark_mesh_cache


## Landmark 2/3: cargo crane with open truss, operator cab, hanging cable and
## suspended orange container. Large negative spaces make it legible in fog.
static func _crane_landmark_mesh() -> ArrayMesh:
	if _crane_landmark_mesh_cache != null:
		return _crane_landmark_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := _vc(Color(0.018, 0.05, 0.09))
	var steel := _vc(Color(0.18, 0.40, 0.52))
	var shell := _vc(Color(0.82, 0.92, 0.94))
	var orange := _vc(Color(1.0, 0.30, 0.035))
	for x: float in [-2.55, 2.55]:
		_box_faces(st, Vector3(x - 0.22, 0.0, -0.44),
				Vector3(x + 0.22, 8.10, 0.44), dark, steel)
	_box_faces(st, Vector3(-3.15, 7.65, -0.52), Vector3(7.25, 8.28, 0.52),
			dark, orange)
	_flat_beam_xy(st, Vector2(-2.45, 0.30), Vector2(2.45, 7.70), 0.26, 0.48, steel)
	_flat_beam_xy(st, Vector2(2.45, 0.30), Vector2(-2.45, 7.70), 0.26, 0.48, steel)
	_box_faces(st, Vector3(-1.15, 6.55, -0.85), Vector3(0.75, 7.58, 0.85),
			steel, shell)
	# Trolley, cable, hook load.
	_box_faces(st, Vector3(4.45, 7.48, -0.42), Vector3(5.12, 7.82, 0.42),
			dark, shell)
	_box_faces(st, Vector3(4.72, 2.25, -0.055), Vector3(4.84, 7.50, 0.055),
			dark, dark)
	_box_faces(st, Vector3(3.55, 0.95, -0.88), Vector3(5.95, 2.35, 0.88),
			dark, orange)
	for x: float in [3.82, 5.68]:
		_box_faces(st, Vector3(x - 0.06, 0.90, -0.92),
				Vector3(x + 0.06, 2.40, 0.92), dark, shell)
	st.generate_normals()
	_crane_landmark_mesh_cache = st.commit()
	return _crane_landmark_mesh_cache


## Landmark 3/3: distant icebreaker. Dark hull, orange safety belt, pale bridge
## and mast break the ocean horizon with a recognisable destination silhouette.
static func _icebreaker_landmark_mesh() -> ArrayMesh:
	if _icebreaker_landmark_mesh_cache != null:
		return _icebreaker_landmark_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hull := _vc(Color(0.025, 0.09, 0.16))
	var hull_hi := _vc(Color(0.10, 0.29, 0.39))
	var shell := _vc(Color(0.86, 0.93, 0.92))
	var glass := _vc(Color(0.02, 0.17, 0.26))
	var orange := _vc(Color(1.0, 0.27, 0.025))
	# Long central hull plus a pointed bow at -Z.
	_box_faces(st, Vector3(-2.35, -1.25, -5.0), Vector3(2.35, 1.25, 6.4),
			hull, hull_hi)
	for side: int in 2:
		var x := -2.35 if side == 0 else 2.35
		var outward := Vector3.LEFT if side == 0 else Vector3.RIGHT
		_tri_out(st, Vector3(x, -1.25, -5.0), Vector3(x, 1.25, -5.0),
				Vector3(0.0, 0.45, -8.25), outward, hull, orange, hull_hi)
	# Safety belt and superstructure.
	_box_faces(st, Vector3(-2.42, 0.72, -5.12), Vector3(2.42, 1.20, 6.45),
			hull, orange)
	_box_faces(st, Vector3(-1.72, 1.18, -0.80), Vector3(1.72, 4.30, 3.55),
			hull_hi, shell)
	# Bridge window ribbon on both sides.
	for side: int in 2:
		var x := -1.745 if side == 0 else 1.745
		var facing := Vector3.LEFT if side == 0 else Vector3.RIGHT
		_quad_out(st, Vector3(x, 3.15, -0.45), Vector3(x, 3.15, 2.95),
				Vector3(x, 3.88, 2.95), Vector3(x, 3.88, -0.45),
				facing, glass, glass, _vc(Color(0.10, 0.50, 0.62)), glass)
	_box_faces(st, Vector3(-0.62, 4.28, 0.48), Vector3(0.62, 5.55, 1.75),
			hull, orange)
	_box_faces(st, Vector3(-0.09, 5.42, 0.96), Vector3(0.09, 8.05, 1.14),
			hull, shell)
	_box_faces(st, Vector3(-1.30, 7.46, 1.02), Vector3(1.30, 7.62, 1.18),
			orange, shell)
	st.generate_normals()
	_icebreaker_landmark_mesh_cache = st.commit()
	return _icebreaker_landmark_mesh_cache


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
## Horseshoe = magnet, octahedron = shield, hex drum = double. Each also gets
## contrasting-value face detail that survives the lit vertex-colour material.
static func _crate_mesh(id: StringName) -> ArrayMesh:
	var key := String(id)
	if _crate_meshes.has(key):
		return _crate_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shell := _vc(Color(1.0, 1.0, 1.0))
	var edge := _vc(Color(0.30, 0.32, 0.40))
	var icon := _vc(Color(0.06, 0.07, 0.10))
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
			# Actual horseshoe magnet, not an icon painted on a cube. Negative
			# space survives distance and colour-blind rendering; pale pole caps
			# make the two active ends readable during the two-axis tumble.
			_box_faces(st, Vector3(-0.58, -0.54, -0.24),
					Vector3(-0.24, 0.46, 0.24), edge, shell)
			_box_faces(st, Vector3(0.24, -0.54, -0.24),
					Vector3(0.58, 0.46, 0.24), edge, shell)
			_box_faces(st, Vector3(-0.58, -0.58, -0.24),
					Vector3(0.58, -0.20, 0.24), edge, shell)
			_box_faces(st, Vector3(-0.61, 0.40, -0.27),
					Vector3(-0.21, 0.64, 0.27), icon, _vc(Color(0.95, 0.98, 1.0)))
			_box_faces(st, Vector3(0.21, 0.40, -0.27),
					Vector3(0.61, 0.64, 0.27), icon, _vc(Color(1.0, 0.50, 0.22)))
	st.generate_normals()
	var mesh := st.commit()
	_crate_meshes[key] = mesh
	return mesh


## Runner fish. The racing game's FishPickup is not instanced here on purpose:
## it types a Racer member, wires itself onto the racing collision layers and
## reads the racing accessibility settings, and it draws three surfaces (body,
## fin and eye shaders) per fish -- three draw calls each, where a run can have
## eighty fish in view at once. This is the same silhouette (fusiform body,
## navy dorsal over luminous blue belly, oversized blue tail and fin)
## folded into ONE vertex-coloured surface, so a whole chunk's fish are a
## single MultiMesh draw. Saturated blue matches the menu/HUD currency icon;
## a dark dorsal and bright lateral flash keep it readable against the ice.
##
## Sized against FISH_LENGTH rather than authored in absolute units: the first
## pass drew a 0.8 m fish inside a 1.9 m grab sphere, and the result read as a
## salmon lying across the lane.
static func _fish_mesh() -> ArrayMesh:
	if _fish_mesh_cache != null:
		return _fish_mesh_cache
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dorsal := _vc(Color("1265bb"))
	var gold := _vc(Color("65cfff"))
	var fin := _vc(Color("248cdf"))
	var glint := _vc(Color("d4f6ff"))
	var eye := _vc(Color(0.025, 0.028, 0.035))
	# The proportions below are authored in units of the original 0.82 m fish;
	# k rescales the whole thing to FISH_LENGTH nose-to-tail in one place.
	var k := FISH_LENGTH / 0.82
	var rings := 7
	var segs := 12
	var ring_pts: Array[PackedVector3Array] = []
	for i: int in rings + 1:
		var t := float(i) / float(rings)
		var x := lerpf(-0.30, 0.26, t) * k
		var r := maxf(0.215 * pow(maxf(sin(PI * pow(t, 0.72)), 0.0), 0.85), 0.005) * k
		var pts := PackedVector3Array()
		for j: int in segs:
			var a := TAU * float(j) / float(segs)
			pts.append(Vector3(x, cos(a) * r, sin(a) * r * 0.72))
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
					_fish_tone(a / k, dorsal, gold), _fish_tone(b / k, dorsal, gold),
					_fish_tone(c / k, dorsal, gold), _fish_tone(d / k, dorsal, gold))
	# Forked tail and dorsal fin, emitted both ways round so a flat blade still
	# shows under a single-sided material.
	_flat_fin(st, Vector3(0.22, 0.0, 0.0) * k, Vector3(0.52, 0.26, 0.0) * k,
			Vector3(0.36, 0.04, 0.0) * k, fin)
	_flat_fin(st, Vector3(0.22, 0.0, 0.0) * k, Vector3(0.36, -0.04, 0.0) * k,
			Vector3(0.52, -0.26, 0.0) * k, fin)
	_flat_fin(st, Vector3(-0.08, 0.09, 0.0) * k, Vector3(0.04, 0.34, 0.0) * k,
			Vector3(0.15, 0.09, 0.0) * k, fin)
	# Broad lateral flash and eye: tiny geometry up close, one decisive bright
	# mark in motion. Emit both sides because fish alternate their facing.
	for side: int in 2:
		var z := (-0.092 if side == 0 else 0.092) * k
		var facing := Vector3.FORWARD if side == 0 else Vector3.BACK
		_quad_out(st, Vector3(-0.23, -0.015, z), Vector3(0.15, -0.015, z),
				Vector3(0.12, 0.045, z), Vector3(-0.20, 0.045, z), facing,
				glint, gold, gold, glint)
		# Round ivory eye, navy pupil and one catchlight match the HUD fish.
		var eye_z := facing.z * 0.143 * k
		var eye_centre := Vector3(-0.175 * k, 0.058 * k, eye_z)
		for ring: int in 3:
			var radius: float = [0.057, 0.036, 0.011][ring] * k
			var centre := eye_centre + facing * float(ring) * 0.001
			if ring == 2:
				centre += Vector3(-0.014, 0.017, 0.0) * k
			var color := glint if ring != 1 else eye
			for edge: int in 12:
				var a := TAU * float(edge) / 12.0
				var b := TAU * float(edge + 1) / 12.0
				_tri_out(st, centre,
					centre + Vector3(cos(a), sin(a), 0.0) * radius,
					centre + Vector3(cos(b), sin(b), 0.0) * radius,
					facing, color, color, color)
	st.generate_normals()
	_fish_mesh_cache = st.commit()
	return _fish_mesh_cache


static func _fish_tone(v: Vector3, dorsal: Color, silver: Color) -> Color:
	return silver.lerp(dorsal, smoothstep(-0.06, 0.05, v.y))


## Faceted cylinder along X, folded into the caller's vertex-colour surface.
static func _cylinder_x(st: SurfaceTool, centre: Vector3, length: float,
		radius: float, segments: int, low: Color, high: Color) -> void:
	var x0 := centre.x - length * 0.5
	var x1 := centre.x + length * 0.5
	for i: int in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p00 := Vector3(x0, centre.y + cos(a0) * radius, centre.z + sin(a0) * radius)
		var p01 := Vector3(x0, centre.y + cos(a1) * radius, centre.z + sin(a1) * radius)
		var p11 := Vector3(x1, centre.y + cos(a1) * radius, centre.z + sin(a1) * radius)
		var p10 := Vector3(x1, centre.y + cos(a0) * radius, centre.z + sin(a0) * radius)
		var c0 := low.lerp(high, 0.5 + cos(a0) * 0.5)
		var c1 := low.lerp(high, 0.5 + cos(a1) * 0.5)
		var outward := Vector3(0.0, cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
		_quad_out(st, p00, p01, p11, p10, outward, c0, c1, c1, c0)
		_tri_out(st, Vector3(x0, centre.y, centre.z), p01, p00,
				Vector3.LEFT, low, c1, c0)
		_tri_out(st, Vector3(x1, centre.y, centre.z), p10, p11,
				Vector3.RIGHT, low, c0, c1)


## Two-sided flat rectangular brace in the XY plane. Used for open trusses,
## where one diagonal silhouette is worth more than a solid wall of polygons.
static func _flat_beam_xy(st: SurfaceTool, point_a: Vector2, point_b: Vector2,
		width: float, z: float, color: Color) -> void:
	var direction := (point_b - point_a).normalized()
	var normal := Vector2(-direction.y, direction.x) * width * 0.5
	var a := point_a + normal
	var b := point_b + normal
	var c := point_b - normal
	var d := point_a - normal
	_quad_out(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z),
			Vector3(c.x, c.y, z), Vector3(d.x, d.y, z),
			Vector3.BACK, color, color, color, color)
	_quad_out(st, Vector3(d.x, d.y, -z), Vector3(c.x, c.y, -z),
			Vector3(b.x, b.y, -z), Vector3(a.x, a.y, -z),
			Vector3.FORWARD, color, color, color, color)


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
	## Presentation update caps. Near decision-space motion remains 60 Hz;
	## distant garnish is temporally LODed before it occupies meaningful pixels.
	const ANIM_NEAR_INTERVAL: float = 1.0 / 60.0
	const ANIM_MID_INTERVAL: float = 1.0 / 30.0
	const ANIM_FAR_INTERVAL: float = 1.0 / 15.0
	const ANIM_NEAR_DISTANCE: float = 96.0
	const ANIM_MID_DISTANCE: float = 180.0

	var index: int = 0
	var difficulty: float = 0.0
	var biome: int = 0
	var pattern: int = 0  # Pattern.OPEN; kept numeric inside nested class scope.
	## Build-time snapshot, including detached jobs whose assembly spans a live
	## quality change. Presentation range has a separate reversible live profile.
	var dressing_density: float = 1.0
	var dressing_range_scale: float = 0.0
	var _range_profile_applied: bool = false
	var _range_profile_distance: float = -1.0
	var _range_profile_density: float = -1.0
	var _range_profile_scale: float = -1.0
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
	var _anim_accumulator: float = 0.0

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
		# Keep the collectible broadside to the chase camera. Full Y rotation made
		# it periodically collapse to a sliver, then loom end-on in the foreground.
		var yaw := (PI if slot % 2 == 1 else 0.0) + sin(float(slot) * 1.31) * 0.16
		fish_base.append(Transform3D(Basis(Vector3.UP, yaw), pos))
		fish_nodes.append(node)
		fish_alive.append(1)
		return slot

	func register_anim(mmi: MultiMeshInstance3D, base: Array[Transform3D], kind: int) -> void:
		if mmi == null or mmi.multimesh == null:
			return
		_anim_mm.append(mmi.multimesh)
		_anim_base.append(base)
		_anim_kind.append(kind)
		# Streamed dressing may register after finish() already chose whether this
		# chunk needed processing.
		set_process(true)

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

	## Applies quality-tier submission range to presentation only. Collision,
	## fairness rows, AI hints and deterministic generation remain resident.
	func apply_visual_range(max_distance: float, density: float = -1.0,
			range_scale: float = -1.0) -> void:
		var next_density := dressing_density if density < 0.0 else density
		var next_scale := dressing_range_scale if range_scale < 0.0 else range_scale
		if _range_profile_applied and max_distance == _range_profile_distance \
				and next_density == _range_profile_density and next_scale == _range_profile_scale:
			return
		var first_uncapped := not _range_profile_applied and max_distance <= 0.0 \
				and next_density == dressing_density and next_scale == dressing_range_scale
		# Opening high chunks already carry their authored ranges. Avoid adding a
		# tree walk to their normal stream path; defaults are captured lazily when
		# the first live cap is actually applied.
		if not first_uncapped:
			_apply_visual_range_recursive(self, max_distance, next_density, next_scale)
		_range_profile_applied = true
		_range_profile_distance = max_distance
		_range_profile_density = next_density
		_range_profile_scale = next_scale

	func apply_dressing_range(geometry: GeometryInstance3D, density: float,
			range_scale: float) -> void:
		var tier_scale := 1.0 if density >= 0.99 else (0.35 if density >= 0.5 else 0.25)
		# Authored deck cassettes share the instancing path with dressing but are
		# gameplay surfaces. Low's decorative factor would cut their floor to
		# 38.5 m, before the 55--70 m decision horizon. Only decoration is thinned.
		if bool(geometry.get_meta("runner_gameplay_surface", false)):
			tier_scale = 1.0
		var end_distance := float(geometry.get_meta("runner_dressing_base_range", 0.0)) \
				* tier_scale * range_scale
		geometry.visibility_range_end = end_distance
		geometry.visibility_range_end_margin = end_distance * 0.15
		geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF \
				if end_distance > 0.0 else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED

	func _apply_visual_range_recursive(node: Node, max_distance: float,
			density: float, range_scale: float) -> void:
		if node is GeometryInstance3D:
			var geometry := node as GeometryInstance3D
			# Capture once before the first cap; applying min() to the already
			# capped value made recovery irreversibly retain the lowest range.
			if not geometry.has_meta("runner_authored_visibility_range"):
				geometry.set_meta("runner_authored_visibility_range", [
					geometry.visibility_range_end, geometry.visibility_range_end_margin,
					geometry.visibility_range_fade_mode,
				])
			if geometry.has_meta("runner_dressing_base_range"):
				apply_dressing_range(geometry, density, range_scale)
			else:
				var authored: Array = geometry.get_meta("runner_authored_visibility_range")
				geometry.visibility_range_end = float(authored[0])
				geometry.visibility_range_end_margin = float(authored[1])
				geometry.visibility_range_fade_mode = int(authored[2]) \
						as GeometryInstance3D.VisibilityRangeFadeMode
			if max_distance > 0.0:
				geometry.visibility_range_end = max_distance if geometry.visibility_range_end <= 0.0 \
						else minf(geometry.visibility_range_end, max_distance)
				geometry.visibility_range_end_margin = 0.0
				geometry.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for child: Node in node.get_children():
			_apply_visual_range_recursive(child, max_distance, density, range_scale)

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
		mmi.material_override = RunnerTrack._fish_material()
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
		# Soft pooled grounding only. Stronger alpha read as black obstacle-sized
		# slabs once real cast shadows were removed—the opposite of the intent.
		patches.material_override = VisualLibrary.contact_shadow_material(0.22)
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
		_anim_accumulator += delta
		var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
		var interval := ANIM_NEAR_INTERVAL
		if camera != null:
			# Entire chunk already crossed the chase camera. It can remain alive for
			# collision bookkeeping until streamer culls it, but no transform buffer
			# behind the lens needs another upload.
			var forward_end_z := global_position.z - RunnerConfig.CHUNK_LENGTH
			if forward_end_z > camera.global_position.z + 4.0:
				_anim_accumulator = 0.0
				return
			var centre_z := global_position.z - RunnerConfig.CHUNK_LENGTH * 0.5
			var distance := absf(centre_z - camera.global_position.z)
			if distance > ANIM_MID_DISTANCE:
				interval = ANIM_FAR_INTERVAL
			elif distance > ANIM_NEAR_DISTANCE:
				interval = ANIM_MID_INTERVAL
		if _anim_accumulator + 0.00001 < interval:
			return
		_anim_time += _anim_accumulator
		_anim_accumulator = 0.0
		if fish_mm != null:
			_animate_fish(camera)
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

	func _animate_fish(camera: Camera3D) -> void:
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
			var facing := PI if i % 2 == 1 else 0.0
			var yaw := facing + sin(_anim_time * 1.7 + phase) * 0.16
			var roll := sin(_anim_time * 2.4 + phase) * 0.10
			var basis := Basis(Vector3.UP, yaw).rotated(Vector3.RIGHT, roll)
			# A missed pickup can pass between player and chase camera. Shrink only
			# that presentation inside the near plane instead of letting a 62 cm
			# fish become a screen-filling foreground wipe; collider stays untouched.
			if camera != null:
				var camera_distance := camera.global_position.distance_to(to_global(origin))
				var near_scale := smoothstep(5.0, 8.0, camera_distance)
				basis = basis.scaled(Vector3.ONE * near_scale)
			fish_mm.set_instance_transform(i, Transform3D(basis,
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
	var _runner: Node3D = null

	## Detached streamed chunks do not receive process ticks. Restore gameplay
	## phase accumulated from reservation so commit cannot teleport a crossing
	## seal backward relative to the synchronous timeline.
	func prime_elapsed(elapsed: float) -> void:
		if elapsed <= 0.0:
			return
		_time = maxf(0.0, elapsed)
		var a := phase + _time * omega
		position.x = sin(a) * sweep
		if body != null:
			var heading := cos(a)
			body.rotation.y = 0.0 if heading < 0.0 else PI
			body.rotation.z = -heading * 0.22
			body.rotation.x = sin(a * 2.0) * 0.07
			body.position.y = absf(sin(a)) * 0.05

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
		# Once a missed crossing seal slips between player and chase camera it
		# has finished communicating gameplay. Ease its visual into the near
		# plane so the 2.8 m body cannot wipe the next decision from the screen.
		var visual_scale := 1.0
		var viewport := get_viewport()
		var camera := viewport.get_camera_3d() if viewport != null else null
		if camera != null:
			visual_scale = smoothstep(4.8, 8.2,
					camera.global_position.distance_to(global_position))
			# Wide FOV can project a side-on mover enormous at the bottom edge even
			# while its centre remains >8 m from camera. Once the centre drops below
			# the decision window, ease only the shell into the near-plane clip.
			var view_height := viewport.get_visible_rect().size.y
			if view_height > 0.0 and not camera.is_position_behind(global_position):
				var screen_y := camera.unproject_position(
						global_position + Vector3.UP * SEAL_HEIGHT * 0.5).y / view_height
				visual_scale = minf(visual_scale,
						1.0 - smoothstep(0.76, 0.98, screen_y))
		# Distance alone misses a side-on seal near the wide-FOV frame edge. Once
		# the player has passed its Z band, the collision decision is over; fade
		# the shell over the next 2 m so it cannot cover the next obstacle row.
		if not is_instance_valid(_runner):
			var chunk := get_parent()
			var track := chunk.get_parent() if chunk != null else null
			var game := track.get_parent() if track != null else null
			_runner = game.get_node_or_null("RunnerPlayer") as Node3D if game != null else null
		if _runner != null:
			var passed := global_position.z - _runner.global_position.z
			visual_scale = minf(visual_scale, 1.0 - smoothstep(0.15, 2.2, passed))
		body.scale = Vector3.ONE * visual_scale


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
