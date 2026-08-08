class_name CourseBase
extends Node3D
## Base for all courses: main racing line + branch shortcuts, checkpoints,
## finish line, guide queries for racers/AI, environment, and pooled VFX.
## Course geometry lives in world space (course node stays at origin).

signal racer_crossed_finish(racer: Racer)

const CHECKPOINT_INTERVAL: float = 130.0

var course_id: String = ""
var main_guide: PathGuide = null
var branches: Array[Dictionary] = []  # {id, guide, entry, exit, risk}
var checkpoint_transforms: Array[Transform3D] = []
var hints: Array[Dictionary] = []  # {offset, end_offset, type, branch_id}
var kill_y: float = -40.0
var finish_offset: float = 0.0
var rng := RandomNumberGenerator.new()

## Ploughable snow volumes, created on first registration (see SnowDriftField).
var _snow_drifts: SnowDriftField = null
var _puff_pool: Array[GPUParticles3D] = []
var _puff_next: int = 0
var _splash_pool: Array[GPUParticles3D] = []
var _splash_next: int = 0


func _ready() -> void:
	rng.seed = hash(course_id) if course_id != "" else 12345
	build_course()
	_build_vfx_pools()


## Overridden by concrete courses. Must call setup_main(), then optionally
## add_branch(), then finalize().
func build_course() -> void:
	pass


## --- Construction ----------------------------------------------------------

func setup_main(points: Array) -> void:
	var track := TrackBuilder.build_ribbon(points, "MainTrack")
	add_child(track)
	main_guide = track.get_meta("guide") as PathGuide
	finish_offset = main_guide.length - 18.0


func add_branch(points: Array, risk: float = 0.5, id_hint: String = "") -> PathGuide:
	var track := TrackBuilder.build_ribbon(points, "Branch_%s" % id_hint)
	add_child(track)
	var guide := track.get_meta("guide") as PathGuide
	var entry := float(main_guide.nearest(guide.position_at(0.0), -1)["offset"])
	var exit_offset := float(main_guide.nearest(guide.position_at(guide.length), -1)["offset"])
	branches.append({
		"id": branches.size(), "guide": guide,
		"entry": entry, "exit": exit_offset, "risk": risk, "name": id_hint,
		# Precomputed guide_cache key: get_guide/ai_target run per racer per
		# frame, and formatting this string there allocated every call.
		"cache_key": "branch_idx_%d" % branches.size(),
	})
	return guide


func finalize() -> void:
	_build_checkpoints()
	_build_finish_line()
	_build_kill_floor()


## Checkpoints are progress-based (not trigger volumes) so no route — main
## line or any shortcut — can ever miss one. Transforms live on the main line
## for respawns; small visual markers show them to the player.
var checkpoint_offsets: Array[float] = []


func _build_checkpoints() -> void:
	# One shared mesh + one cached material for every post in the game — the
	# per-post StandardMaterial3D.new() here minted a fresh WebGL program per
	# checkpoint per race.
	var post_mesh: CylinderMesh = null
	var post_mat: StandardMaterial3D = null
	if not GameConfig.is_headless():
		post_mesh = CylinderMesh.new()
		post_mesh.top_radius = 0.08
		post_mesh.bottom_radius = 0.12
		post_mesh.height = 2.4
		post_mat = VisualLibrary.emissive_material(Color(0.4, 0.9, 1.0), Color(0.3, 0.8, 1.0), 0.8)
	var offset := 40.0
	while offset < finish_offset - 60.0:
		var xform := main_guide.transform_at(offset)
		checkpoint_offsets.append(offset)
		checkpoint_transforms.append(Transform3D(xform.basis, xform.origin + Vector3.UP * 0.5))
		# Visual: two slim glowing posts just outside the racing floor, planted
		# on whatever surface is under them (a constant 9m lateral straddled the
		# deck edge, so posts hung in mid-air wherever the track narrows).
		if not GameConfig.is_headless() and checkpoint_offsets.size() % 2 == 0:
			for side: float in [-1.0, 1.0]:
				var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + 0.6) * side
				var post := MeshInstance3D.new()
				post.mesh = post_mesh
				post.material_override = post_mat
				post.position = seat_dressing(xform, lateral, 2.4) + Vector3.UP * 1.2
				VisualLibrary.apply_dressing_range(post)
				add_child(post)
		offset += CHECKPOINT_INTERVAL


## Called from get_guide: advances the racer through any checkpoints its
## main-line progress has passed.
func _advance_checkpoints(racer: Racer, progress: float) -> void:
	var next := racer.last_checkpoint_index + 1
	while next < checkpoint_offsets.size() and progress >= checkpoint_offsets[next] + 2.0:
		racer.on_checkpoint(next, checkpoint_transforms[next])
		next += 1


func _build_finish_line() -> void:
	var xform := main_guide.transform_at(finish_offset)
	var area := Area3D.new()
	area.name = "FinishLine"
	area.collision_layer = GameConfig.LAYER_TRIGGERS
	area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 14.0, 3.0)
	shape.shape = box
	area.add_child(shape)
	area.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 5.0)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Racer:
			racer_crossed_finish.emit(body))
	add_child(area)

	# Banner: two posts + crossbar + checkered panels.
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.18
	post_mesh.bottom_radius = 0.22
	post_mesh.height = 7.0
	var post_mat := TrackBuilder.prop_material(Color(0.85, 0.3, 0.3))
	for side: float in [-1.0, 1.0]:
		# Feet just outside the racing floor and planted on it, so the banner
		# never straddles the deck edge with its posts hanging over the drop.
		var lateral := (track_edge_lateral(main_guide, finish_offset, side, 10.0) + 0.9) * side
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = post_mat
		post.position = seat_dressing(xform, lateral, 7.0) + Vector3.UP * 3.5
		add_child(post)
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(22.6, 1.4, 0.4)
	bar.mesh = bar_mesh
	bar.material_override = TrackBuilder.prop_material(Color(0.95, 0.96, 1.0))
	bar.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 6.6)
	add_child(bar)
	var checker_mat := VisualLibrary.rock_material(Color(0.1, 0.1, 0.12), 1.0)
	var square_mesh := BoxMesh.new()
	square_mesh.size = Vector3(2.26, 0.7, 0.42)
	for i: int in 10:
		if i % 2 == 0:
			var square := MeshInstance3D.new()
			square.mesh = square_mesh
			square.material_override = checker_mat
			square.transform = Transform3D(xform.basis,
				xform.origin + xform.basis.x * (-10.2 + float(i) * 2.26) + Vector3.UP * 6.6)
			add_child(square)


func _build_kill_floor() -> void:
	var lowest := INF
	for point: Vector3 in main_guide.points:
		lowest = minf(lowest, point.y)
	kill_y = lowest - 22.0


## --- Build-time ground probing ----------------------------------------------
## BUILD TIME ONLY. Every helper below fires physics raycasts against the
## static course colliders; they belong in build_course/_decorate and must
## never run per frame.
##
## Why it works here: physics is single-threaded, and PhysicsServer3D only
## refuses a space-state query from a NON-main thread, so the main-thread
## _ready -> build_course path may query freely. add_child() propagates
## ENTER_TREE synchronously, so a track's StaticBody3D/CollisionShape3D pair
## is registered in the broadphase the instant setup_main()/add_branch()
## returns — the deck is queryable long before _decorate() runs.
##
## Because that is an engine-behaviour assumption, ground_probe_ready() proves
## it with one control ray straight down through the start of the racing line.
## If the space is not queryable (or the build is headless, where dressing is
## skipped anyway) every helper degrades to "no information" and hands back the
## caller's authored placement, so a course still builds exactly as authored —
## no silent mass-teleport of dressing to the sea floor. If that ever trips in
## practice, the fix is a deferred one-shot re-seat pass after the first
## physics frame, not a per-frame query.

## Metres above the deck a downward probe starts: high enough to clear the
## small DOWN offsets dressing is authored with, low enough to pass under
## overhead bars (clearance 1.05m) and track walls (1.5m tall).
const GROUND_PROBE_START: float = 0.4

## How far back toward the centreline a prop that overhangs the ribbon may be
## re-probed before it counts as standing over open water.
const GROUND_SHOULDER: float = 3.5

## Downward search range for trackside probes. Bounded on purpose: a prop
## beside an upper switchback must not seat itself on the deck 30m below it
## (that would drop dressing onto a racing floor).
const GROUND_MAX_DROP: float = 7.0

## Y of the ocean / ice-sheet plane, set by add_ground_plane(). -INF = unset.
var base_ground_y: float = -INF

var _space_state: PhysicsDirectSpaceState3D = null
var _ray_params: PhysicsRayQueryParameters3D = null
var _probe_state: int = 0  # 0 = untested, 1 = usable, -1 = unavailable
var _edge_cache: Dictionary = {}


## True once the static course geometry can be raycast. Cached after the first
## call; see the block comment above for the failure contract.
func ground_probe_ready() -> bool:
	if _probe_state != 0:
		return _probe_state > 0
	_probe_state = -1
	if GameConfig.is_headless() or main_guide == null or not is_inside_tree():
		return false
	var world := get_world_3d()
	if world == null:
		return false
	var state := world.direct_space_state
	if state == null:
		return false
	_space_state = state
	_ray_params = PhysicsRayQueryParameters3D.new()
	_ray_params.collision_mask = GameConfig.LAYER_WORLD
	_ray_params.collide_with_areas = false
	_ray_params.collide_with_bodies = true
	var probe := main_guide.position_at(minf(20.0, main_guide.length * 0.5))
	if _raw_ground(probe.x, probe.z, probe.y + 1.0, 12.0) == -INF:
		return false
	_probe_state = 1
	return true


## Raw downward cast: world Y of the first UP-facing static surface under
## (x, z) below from_y, or -INF. Hits on near-vertical faces (track walls,
## berm flanks) are skipped and the cast resumes just below them, so a probe
## grazing a wall still reports the floor it guards.
func _raw_ground(x: float, z: float, from_y: float, depth: float) -> float:
	var bottom := from_y - depth
	var start_y := from_y
	for _pass: int in 3:
		_ray_params.from = Vector3(x, start_y, z)
		_ray_params.to = Vector3(x, bottom, z)
		var hit := _space_state.intersect_ray(_ray_params)
		if hit.is_empty():
			return -INF
		var point: Vector3 = hit["position"]
		if absf((hit["normal"] as Vector3).y) > 0.3:
			return point.y
		start_y = point.y - 0.05
		if start_y <= bottom:
			return -INF
	return -INF


## Y of the ocean / ice-sheet plane this course sits over: whatever
## add_ground_plane() laid down, or a sane default below the lowest track
## point when a course ships no plane at all.
func ground_plane_y() -> float:
	if base_ground_y > -INF:
		return base_ground_y
	var low := INF
	if main_guide != null:
		for point: Vector3 in main_guide.points:
			low = minf(low, point.y)
	return (low - 24.0) if low < INF else -24.0


## BUILD TIME ONLY. Y of the static course surface directly beneath world_pos,
## searched downward from just above it. Falls back to the ocean/base plane
## when the point stands over open water, and to the caller's own height when
## probing is unavailable.
func ground_height_at(world_pos: Vector3, probe_up: float = GROUND_PROBE_START, probe_down: float = 1200.0) -> float:
	if not ground_probe_ready():
		return world_pos.y
	var y := _raw_ground(world_pos.x, world_pos.z, world_pos.y + probe_up, probe_down + probe_up)
	return y if y != -INF else ground_plane_y()


## BUILD TIME ONLY. Surface height a trackside prop standing `lateral` metres
## off the centreline of `xform` should rest on. Probes straight down from just
## above the deck; if the prop overhangs the ribbon the probe walks back toward
## the centreline in 1m steps (up to `shoulder`) so edge dressing keeps hugging
## the track instead of dropping into the sea. Anything further out than that
## genuinely is over open water and gets the base plane.
func dressing_ground(xform: Transform3D, lateral: float, shoulder: float = GROUND_SHOULDER,
		max_drop: float = GROUND_MAX_DROP) -> float:
	if not ground_probe_ready():
		return xform.origin.y
	var from_y := xform.origin.y + GROUND_PROBE_START
	var depth := max_drop + GROUND_PROBE_START
	var inward := -1.0 if lateral > 0.0 else 1.0
	var reach := shoulder if not is_zero_approx(lateral) else 0.0
	var step := 0.0
	while step <= reach + 0.001:
		var p := xform.origin + xform.basis.x * (lateral + inward * step)
		var y := _raw_ground(p.x, p.z, from_y, depth)
		if y != -INF:
			return y
		step += 1.0
	return ground_plane_y()


## Sink for a prop `height` metres tall: 5-15% of its height so the silhouette
## reads planted instead of balanced. Capped so a 200m peak buries 2m, not 20.
static func ground_embed(height: float, fraction: float = 0.09) -> float:
	return clampf(absf(height) * fraction, 0.05, 2.0)


## BUILD TIME ONLY. World position for a base-origin dressing mesh (the
## VisualLibrary drift/crystal/berg meshes and every unit mesh in the course
## scripts start at local y = 0) standing `lateral` off the centreline: X/Z
## from the deck frame, Y from the surface under it, sunk ground_embed().
func seat_dressing(xform: Transform3D, lateral: float, height: float,
		shoulder: float = GROUND_SHOULDER, embed_fraction: float = 0.09) -> Vector3:
	var pos := xform.origin + xform.basis.x * lateral
	pos.y = dressing_ground(xform, lateral, shoulder) - ground_embed(height, embed_fraction)
	return pos


## BUILD TIME ONLY. Lateral distance from the centreline of `guide` at `offset`
## to the outer edge of the solid racing floor on `side` (-1 left, +1 right).
## Trackside dressing places itself relative to THIS rather than a constant, so
## props sit just outside the racing floor on every span instead of landing on
## the deck where the track is wide and hanging in thin air where it is narrow.
## Bisection over downward raycasts (8 casts, ~0.2m precision), cached per
## metre of offset. Returns `fallback` when the deck cannot be probed — including
## over gap spans, which have no floor to measure.
func track_edge_lateral(guide: PathGuide, offset: float, side: float,
		fallback: float = 9.0, limit: float = 24.0) -> float:
	if guide == null or not ground_probe_ready():
		return fallback
	var sign_side := 1.0 if side >= 0.0 else -1.0
	var key := "%d_%d_%d" % [guide.get_instance_id(), int(roundf(offset)), int(sign_side)]
	if _edge_cache.has(key):
		return float(_edge_cache[key])
	# Probe from the BANKED deck frame, not the flat guide frame.
	#
	# guide.transform_at() returns the unrolled frame, so on a banked corner the
	# raised outer edge sits ABOVE origin.y + 0.4 and a ray starting there began
	# underneath the deck it was trying to find. The bisection then read "no
	# floor out here", returned a short lateral, and the caller planted its prop
	# that far out -- which is to say, on the racing surface. Measured on aurora:
	# four station poles standing 2.9-5.0 m inboard of the deck edge, right in
	# the driving line, on exactly the three banked corners.
	#
	# Each probe now starts above its OWN expected deck point rather than above
	# the centreline, so the start height rises with the bank instead of needing
	# a blanket raise that would start catching arches and overhead dressing.
	var deck := TrackBuilder.deck_transform_at(guide, offset)
	var depth := GROUND_MAX_DROP + GROUND_PROBE_START
	var centre := deck.origin
	if _raw_ground(centre.x, centre.z, centre.y + GROUND_PROBE_START, depth) == -INF:
		_edge_cache[key] = fallback
		return fallback
	var dir := deck.basis.x * sign_side
	var lo := 0.0
	var hi := limit
	for _i: int in 7:
		var mid := (lo + hi) * 0.5
		var p := centre + dir * mid
		if _raw_ground(p.x, p.z, p.y + GROUND_PROBE_START, depth) != -INF:
			lo = mid
		else:
			hi = mid
	_edge_cache[key] = lo
	return lo


## BUILD TIME ONLY. True when a prop of horizontal radius `radius` may stand at
## `pos` without reaching any racing line -- the main one AND every branch.
##
## Flank dressing is placed by lateral offset from the main guide, which is
## only a statement about the main guide. On a course that folds back on itself
## or carries a shortcut running parallel to the main line, "28 m to the side
## of the main line" can also be "on the branch". Aurora had exactly that: a
## snowdrift mound and a patch of crystal field standing 4 m inboard of the
## ridge-shortcut deck, in the driving line, because nothing in their placement
## had ever heard of the branch.
##
## Distance is measured in 3D on purpose. A prop under a deck is separated by
## height rather than by plan distance, and this course stacks its own legs
## vertically -- a purely horizontal test would reject most of the valley.
func clear_of_track(pos: Vector3, radius: float, margin: float = 2.0) -> bool:
	var need := radius + margin
	if main_guide != null:
		if float(main_guide.nearest(pos, -1)["distance"]) < need + 10.0:
			return false
	for branch: Dictionary in branches:
		var guide: PathGuide = branch.get("guide")
		if guide == null:
			continue
		if float(guide.nearest(pos, -1)["distance"]) < need + 5.0:
			return false
	return true


## --- Racer guide queries ----------------------------------------------------

## Returns {yaw, progress} where progress is main-line-equivalent distance.
## Uses per-racer cache with path hysteresis so branches work automatically
## for both the player and AI.
func get_guide(racer: Racer) -> Dictionary:
	if main_guide == null:
		return {"yaw": 0.0, "progress": 0.0}
	var cache: Dictionary = racer.guide_cache
	var current_path := int(cache.get("path", -1))
	var pos := racer.global_position

	var main_hint := int(cache.get("main_idx", -1))
	var main_res := main_guide.nearest(pos, main_hint)
	var best_path := -1
	var best_res := main_res
	var best_dist := float(main_res["distance"])
	if current_path == -1:
		best_dist -= 2.0  # hysteresis: stick with current path

	var main_progress_estimate := float(main_res["offset"])
	for branch: Dictionary in branches:
		var entry := float(branch["entry"])
		var exit_offset := float(branch["exit"])
		if main_progress_estimate < entry - 40.0 or main_progress_estimate > exit_offset + 40.0:
			continue
		var branch_id := int(branch["id"])
		var guide: PathGuide = branch["guide"]
		var cache_key: String = branch["cache_key"]
		var hint := int(cache.get(cache_key, -1))
		var res := guide.nearest(pos, hint)
		cache[cache_key] = int(res["index"])
		var dist := float(res["distance"])
		if current_path == branch_id:
			dist -= 2.0
		if dist < best_dist:
			best_dist = dist
			best_path = branch_id
			best_res = res

	cache["main_idx"] = int(main_res["index"])
	cache["path"] = best_path
	racer.guide_cache = cache

	# Reused per-racer result dict: this runs for every racer every physics
	# frame, so a fresh Dictionary per call is steady allocation pressure on
	# the single-threaded web build.
	if not cache.has("result"):
		cache["result"] = {"yaw": 0.0, "progress": 0.0}
	var result: Dictionary = cache["result"]
	if best_path == -1:
		result["yaw"] = main_guide.yaw_at(float(main_res["offset"]))
		result["progress"] = float(main_res["offset"])
	else:
		var branch: Dictionary = branches[best_path]
		var guide: PathGuide = branch["guide"]
		var frac := float(best_res["offset"]) / maxf(guide.length, 0.001)
		result["yaw"] = guide.yaw_at(float(best_res["offset"]))
		result["progress"] = lerpf(float(branch["entry"]), float(branch["exit"]), frac)
	_advance_checkpoints(racer, float(result["progress"]))
	return result


## Target point ahead of the racer on its current path, for AI steering.
func ai_target(racer: Racer, lookahead: float, lateral: float = 0.0) -> Vector3:
	var cache: Dictionary = racer.guide_cache
	var path := int(cache.get("path", -1))
	if path >= 0 and path < branches.size():
		var branch: Dictionary = branches[path]
		var guide: PathGuide = branch["guide"]
		var idx := int(cache.get(branch["cache_key"], 0))
		var offset := float(idx) * PathGuide.SAMPLE_SPACING + lookahead
		if offset < guide.length - 2.0:
			return guide.point_at(offset, lateral)
		# Near branch end: aim back onto the main line.
		return main_guide.point_at(float(branch["exit"]) + 12.0, lateral)
	var main_idx := int(cache.get("main_idx", 0))
	return main_guide.point_at(float(main_idx) * PathGuide.SAMPLE_SPACING + lookahead, lateral)


## Branches whose entry lies in [progress + near, progress + far].
func upcoming_branches(progress: float, near: float = 20.0, far: float = 90.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for branch: Dictionary in branches:
		var entry := float(branch["entry"])
		if entry >= progress + near and entry <= progress + far:
			result.append(branch)
	return result


func add_hint(offset: float, type: String, end_offset: float = -1.0, branch_id: int = -1) -> void:
	hints.append({
		"offset": offset, "type": type,
		"end_offset": end_offset if end_offset > 0.0 else offset,
		"branch_id": branch_id,
	})


func hints_in_range(from_offset: float, to_offset: float, branch_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hint: Dictionary in hints:
		if int(hint["branch_id"]) != branch_id:
			continue
		var o := float(hint["offset"])
		if o >= from_offset and o <= to_offset:
			result.append(hint)
	return result


func start_grid_transform(slot: int) -> Transform3D:
	var row := slot / 2
	var col := slot % 2
	var offset := 16.0 - float(row) * 3.2
	var lateral := -2.6 + float(col) * 5.2
	var xform := main_guide.transform_at(maxf(offset, 2.0))
	var origin := xform.origin + xform.basis.x * lateral + Vector3.UP * 0.6
	return Transform3D(xform.basis, origin)


## --- Environment -----------------------------------------------------------

## params: sky_top, sky_horizon, ground_color, sun_angle_deg, sun_energy,
## sun_color, fog_color, fog_density, ambient_energy, snow (bool), stars (bool)
## Optional (all backward compatible, sensible defaults):
##   sun_angle_max (deg, sun disc/halo size, default 15.0), sun_curve (0.08),
##   sky_energy (sky brightness multiplier, 1.0), exposure (tonemap, 1.05),
##   sky_contribution (ambient from sky, 1.0), fog_height + fog_height_density
##   (height fog, off unless fog_height given), glow (bool, default true;
##   auto-off when particle_quality == "low"), glow_threshold (1.1),
##   shadow_distance (140.0), clouds (bool) + cloud_color.
## Atmospheric perspective (all optional): fog_horizon_blend (0..1, default
##   0.35 — shifts the fog hue toward sky_horizon so distance reads as
##   atmosphere, not gray soup), fog_aerial (0..1, default 0.5 — Godot aerial
##   perspective: far geometry blends toward the sky itself), fog_sky_affect
##   (default 0.2), shadow_blur (softer sun shadow edge; defaults 1.0 on the
##   "low" shadow preset, 1.75 otherwise).
## Grade + glow (all optional): glow_intensity (default 0.5), contrast
##   (default 1.09) and saturation (default 1.1) — a mild global grade that
##   sells crisp polar air; ignored by renderers without adjustment support.
## Sky cover (optional): sky_cover_strength (0 disables; defaults 0.34 when
##   clouds is on, 0.14 otherwise) paints a procedural cloud panorama into the
##   sky material itself — no draw calls, no overdraw. cloud_cover (0..1, 0.34)
##   sets how much of the dome the cumulus deck fills, cloud_streaks (0..1,
##   0.5) how strong the high cirrus above it reads.
## Skyline (optional): skyline (bool, default true) stamps three depth bands of
##   baked silhouettes along the racing line — see _build_far_field.
##   skyline_color (ice albedo) and skyline_density (form count, 1.0) tune it;
##   the legacy berg_color and berg_y params still feed it, and the old
##   distant_bergs / berg_count / berg_distance ring params are accepted and
##   ignored — the banded skyline replaced that ring on every course.
## Light rig (optional): fill_energy (default 0.18, 0 disables) + fill_color —
##   a cool unshadowed sky-fill directional from the anti-sun direction, so
##   shadow sides read as blue sky bounce instead of flat ambient (specular
##   zeroed: ice keeps a single sun glint). Skipped on the low quality preset.
##   fog_sun_scatter (default 0.06) warms haze toward the sun for a gentle
##   forward-scatter halo.
## When fog_height is omitted, a default altitude falloff is derived from the
##   lowest point of the main line: thin haze pools below the track instead of
##   tinting the air uniformly at every height.
func build_environment(params: Dictionary) -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = params.get("sky_top", Color(0.25, 0.55, 0.85))
	sky_mat.sky_horizon_color = params.get("sky_horizon", Color(0.75, 0.88, 0.98))
	sky_mat.ground_bottom_color = params.get("ground_color", Color(0.7, 0.8, 0.9))
	sky_mat.ground_horizon_color = params.get("sky_horizon", Color(0.75, 0.88, 0.98))
	sky_mat.sun_angle_max = float(params.get("sun_angle_max", 15.0))
	sky_mat.sun_curve = float(params.get("sun_curve", 0.08))
	sky_mat.sky_energy_multiplier = float(params.get("sky_energy", 1.0))
	# Cloud deck baked into the sky itself: a two-stop gradient with three
	# billboard blobs in front of it is the flattest thing in the frame, and a
	# panorama costs no draw call, no overdraw and no transparency sorting.
	# Courses with clouds on get a full deck; the rest get a faint high veil so
	# even a clear sky has structure. Additive by contract (the sky shader adds
	# cover.rgb * modulate * cover.a), so the tint doubles as the cloud color.
	var cover_strength := float(params.get("sky_cover_strength",
		0.34 if bool(params.get("clouds", false)) else 0.14))
	if cover_strength > 0.0 and not GameConfig.is_headless():
		var cover := _sky_cover_texture(
			hash(course_id) & 0xffff,
			clampf(float(params.get("cloud_cover", 0.34)), 0.0, 1.0),
			clampf(float(params.get("cloud_streaks", 0.5)), 0.0, 1.0))
		if cover != null:
			var cover_tint: Color = params.get("cloud_color",
				(params.get("sky_horizon", Color(0.75, 0.88, 0.98)) as Color).lerp(Color.WHITE, 0.55))
			sky_mat.sky_cover = cover
			sky_mat.sky_cover_modulate = Color(
				cover_tint.r, cover_tint.g, cover_tint.b, cover_strength * cover_tint.a)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Slightly restrained default ambient: shadows keep some depth so the sun
	# actually models form. Courses that tuned ambient_energy are untouched.
	env.ambient_light_energy = float(params.get("ambient_energy", 0.92))
	env.ambient_light_sky_contribution = float(params.get("sky_contribution", 1.0))
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(params.get("exposure", 0.93))
	env.tonemap_white = 6.0
	env.fog_enabled = true
	# Atmospheric perspective: real distance haze drifts toward the horizon/sky
	# color rather than a fixed gray-blue, so far track reads as atmosphere.
	var fog_base: Color = params.get("fog_color", Color(0.75, 0.86, 0.95))
	var horizon_col: Color = params.get("sky_horizon", Color(0.75, 0.88, 0.98))
	env.fog_light_color = fog_base.lerp(horizon_col, clampf(float(params.get("fog_horizon_blend", 0.35)), 0.0, 1.0))
	env.fog_density = float(params.get("fog_density", 0.004))
	# Aerial perspective: distant geometry blends toward the rendered sky
	# (free hue shift with distance). Ignored gracefully by renderers that
	# skip it; no cost when fog is thin.
	env.fog_aerial_perspective = clampf(float(params.get("fog_aerial", 0.5)), 0.0, 1.0)
	env.fog_sky_affect = float(params.get("fog_sky_affect", 0.2))
	# Forward-scatter: haze picks up a whisper of sun color looking sunward,
	# so the air glows warm toward the light instead of one uniform tint.
	env.fog_sun_scatter = float(params.get("fog_sun_scatter", 0.06))
	if params.has("fog_height"):
		env.fog_height = float(params["fog_height"])
		env.fog_height_density = float(params.get("fog_height_density", 0.08))
	elif main_guide != null and main_guide.points.size() > 0:
		# Default altitude falloff: thin haze pooling just below the lowest
		# stretch of track — real fog sits in the valleys, not evenly at every
		# height. Courses that tuned their own height fog are untouched.
		var low := INF
		for point: Vector3 in main_guide.points:
			low = minf(low, point.y)
		env.fog_height = low - 1.5
		env.fog_height_density = 0.025
	# Mild global grade: a touch more contrast and saturation sells crisp
	# polar air (harmlessly ignored where adjustments are unsupported, e.g.
	# older gl_compatibility web builds).
	if not GameConfig.is_headless():
		env.adjustment_enabled = true
		env.adjustment_contrast = float(params.get("contrast", 1.09))
		env.adjustment_saturation = float(params.get("saturation", 1.1))
	if bool(params.get("glow", true)) and SettingsManager.glow_allowed():
		# High HDR threshold: only emissive peaks (boost pads, pickups, aurora)
		# bloom — cheap on Forward Mobile, never a full-screen wash.
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = float(params.get("glow_threshold", 1.45))
		env.glow_intensity = float(params.get("glow_intensity", 0.5))
		env.glow_bloom = 0.0
		# Gentle wide halo: keep the default mid mip levels but add a faint
		# widest-level tail, so emissive peaks (aurora heart, boost pads) bleed
		# a soft atmospheric corona instead of a tight hot ring. Same blur
		# chain either way — no extra cost.
		env.set_glow_level(6, 0.3)
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	# Warmer default key light: low polar sun always carries a golden cast;
	# courses with an authored sun_color (moonlight, sunrise) are untouched.
	sun.light_color = params.get("sun_color", Color(1.0, 0.965, 0.91))
	sun.light_energy = float(params.get("sun_energy", 1.2))
	sun.rotation_degrees = Vector3(float(params.get("sun_angle_deg", -48.0)), float(params.get("sun_yaw_deg", -30.0)), 0.0)
	var shadow_quality := String(SettingsManager.get_setting("display", "shadow_quality"))
	sun.shadow_enabled = shadow_quality != "off" and not GameConfig.is_headless()
	# Shorter shadow range on the lower presets: fewer casters in the maps and
	# sharper texels near the racer for less GPU work. High keeps the authored
	# distance untouched.
	var shadow_distance := float(params.get("shadow_distance", 140.0))
	match String(SettingsManager.get_setting("display", "quality_preset")):
		"low":
			shadow_distance *= 0.55
		"medium":
			shadow_distance *= 0.8
	sun.directional_shadow_max_distance = shadow_distance
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_fade_start = 0.85
	# Softer shadow edge (cheap PCF widening): hard razor edges read as toy
	# plastic; a mild penumbra sells sun through atmosphere. Kept at 1.0 on
	# the "low" preset where the wider kernel is the wrong trade.
	sun.shadow_blur = float(params.get("shadow_blur", 1.0 if shadow_quality == "low" else 1.75))
	match shadow_quality:
		"low":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		"medium":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_blend_splits = true
	add_child(sun)

	# Cool sky-fill from the anti-sun direction: polar shadow sides are lit by
	# blue sky bounce, never black — one unshadowed directional models that
	# for near-zero cost. Specular zeroed so ice and water keep a single sun
	# glint (a second specular sun reads instantly fake). Skipped on the low
	# quality preset where every per-pixel light matters.
	var fill_energy := float(params.get("fill_energy", 0.12))
	var particle_quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if fill_energy > 0.0 and particle_quality != "low" and not GameConfig.is_headless():
		var fill := DirectionalLight3D.new()
		var sky_top: Color = params.get("sky_top", Color(0.25, 0.55, 0.85))
		fill.light_color = params.get("fill_color", sky_top.lerp(Color(0.62, 0.74, 0.95), 0.5))
		fill.light_energy = fill_energy
		fill.light_specular = 0.0
		fill.shadow_enabled = false
		fill.rotation_degrees = Vector3(-36.0, float(params.get("sun_yaw_deg", -30.0)) + 180.0, 0.0)
		add_child(fill)

	if bool(params.get("snow", false)) and not GameConfig.is_headless():
		_add_snowfall()
	if bool(params.get("clouds", false)) and not GameConfig.is_headless():
		_add_clouds(params.get("cloud_color", Color(1.0, 1.0, 1.0, 0.75)))
	# The skyline runs one frame late on purpose: several courses lay their
	# ocean / ice sheet down AFTER build_environment (iceberg does), and every
	# silhouette seats itself on that surface. Deferring means the far field
	# reads the real ground on every course instead of the "lowest track point
	# - 24" fallback, which on iceberg would have sunk the whole skyline 18m
	# under the sea.
	if not GameConfig.is_headless():
		_build_far_field.call_deferred(params)


## Cumulus clusters: a wide flat base of big soft puffs with a smaller domed
## crown above it, instead of three equal blobs in a row. Every puff of a layer
## rides ONE MultiMesh, so the whole sky costs two draw calls (it used to cost
## fifteen MeshInstance3Ds for a fifth of the puffs) and two cached materials.
## The fine structure of the sky is the panorama in the sky material; these are
## the near, parallaxing clouds in front of it.
func _add_clouds(color: Color) -> void:
	var puff_mesh := QuadMesh.new()
	puff_mesh.size = Vector2(1.0, 0.62)
	# Base puffs read cooler and heavier than the sunlit crown: a cumulus with
	# a uniformly bright underside is the classic cartoon-blob tell.
	var shade := Color(color.r * 0.82, color.g * 0.86, color.b * 0.96, color.a * 0.92)
	var crown_mat := VisualLibrary.billboard_puff_material(color, 64, 0.85, true)
	var base_mat := VisualLibrary.billboard_puff_material(shade, 64, 0.8, true)
	var crown: Array[Transform3D] = []
	var base: Array[Transform3D] = []
	var clusters := 7
	for i: int in clusters:
		var anchor := Vector3.ZERO
		if main_guide != null:
			anchor = main_guide.position_at(main_guide.length * (float(i) + 0.5) / float(clusters))
		var spread := rng.randf_range(85.0, 165.0)
		var center := anchor + Vector3(
			rng.randf_range(-340.0, 340.0),
			rng.randf_range(115.0, 225.0),
			rng.randf_range(-260.0, 260.0))
		# Flat base line, domed crown: puff centres are laid out on an ellipse
		# for the base and a tighter, higher ellipse for the crown, with size
		# falling off from the middle of the cluster outward.
		var stretch := rng.randf_range(1.0, 1.8)
		for j: int in 4:
			var t := (float(j) / 3.0 - 0.5) * 2.0
			var size := spread * (1.0 - absf(t) * 0.35) * rng.randf_range(0.85, 1.15)
			base.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(size, size, 1.0)),
				center + Vector3(t * spread * stretch * 0.55,
					rng.randf_range(-4.0, 4.0),
					rng.randf_range(-spread * 0.3, spread * 0.3))))
		for j: int in 5:
			var t := (float(j) / 4.0 - 0.5) * 2.0
			var size := spread * (0.72 - absf(t) * 0.3) * rng.randf_range(0.85, 1.2)
			crown.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(size, size, 1.0)),
				center + Vector3(t * spread * stretch * 0.4,
					spread * rng.randf_range(0.22, 0.5) * (1.0 - absf(t) * 0.5),
					rng.randf_range(-spread * 0.25, spread * 0.25))))
	_add_puff_layer("CloudBase", puff_mesh, base_mat, base)
	_add_puff_layer("CloudCrown", puff_mesh, crown_mat, crown)


func _add_puff_layer(node_name: String, mesh: Mesh, material: Material,
		transforms: Array[Transform3D]) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i: int in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = material
	# Translucent quads still cast shadows by default — with a low sun they
	# paint huge blue blobs across the track.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


## --- Skyline ----------------------------------------------------------------
## Three depth bands of silhouettes stamped along the racing line, so every
## stretch of track has a near ice field, a middle band and a far massif wall
## around it — the empty plate between the racer and the horizon was the single
## biggest "flat backdrop" tell.
##
## Everything in a band is baked into a handful of world-space ArrayMeshes that
## all share ONE cached material (VisualLibrary.rock_material(white), the same
## instance the course mountains already use), so a whole course skyline is
## about a dozen draw calls, ~6k triangles and no new shader program — cheaper
## than the twelve separate berg MeshInstance3Ds it replaced. Silhouette
## variety comes from four generators (massif, tabular berg, pressure ridge,
## snow dome) with per-form profile exponents, column noise, lean, aspect ratio
## and snowline, so no two forms share a shape — which a ring of scaled copies
## of one berg mesh could never do.
##
## Aerial perspective is baked into the vertex colours: each face is tinted by
## how it faces the sun (warm lit / cool shadowed, which also restores the form
## a flat white cutout loses), then lerped toward the sky horizon colour by its
## band's haze. Because forms are placed relative to the guide, a form's band
## distance IS roughly its distance from the camera, so the haze stays honest
## wherever the racer is on the course.

## Environment dressing RNG, kept separate from the course `rng` so retuning
## the skyline never re-rolls a course's own authored dressing.
var _env_rng := RandomNumberGenerator.new()

## Longest a pressure ridge runs, as a multiple of its footprint. Shared by the
## generator and the placement clearance test, which has to know how far a form
## reaches before it decides whether it clears the racing line.
const _RIDGE_SPAN: float = 5.2


func _build_far_field(params: Dictionary) -> void:
	if GameConfig.is_headless() or main_guide == null or not is_inside_tree():
		return
	if not bool(params.get("skyline", true)):
		return
	_env_rng.seed = hash(course_id) * 2654435761 + 12345
	var horizon: Color = params.get("sky_horizon", Color(0.75, 0.88, 0.98))
	# Ice albedo, not screen colour. A hot polar key light (glacier runs 1.85)
	# plus ACES lifts these roughly two stops, so anything authored near white
	# clips to a paper cutout — which is exactly how the old berg ring read.
	var base: Color = params.get("skyline_color",
		params.get("berg_color", Color(0.6, 0.71, 0.86).lerp(horizon, 0.12)))
	var sun_yaw := deg_to_rad(float(params.get("sun_yaw_deg", -30.0)))
	var look := {
		# Horizontal direction the sun is in (the light's -Z, flattened).
		"to_sun": Vector3(sin(sun_yaw), 0.0, cos(sun_yaw)),
		# Both tints stay close to white on purpose: the engine already lights
		# these with the real sun colour, and tinting a second time turned
		# sunrise ice into sand dunes.
		"warm": (params.get("sun_color", Color(1.0, 0.965, 0.91)) as Color).lerp(Color.WHITE, 0.68),
		"cool": ((params.get("sky_top", Color(0.25, 0.55, 0.85)) as Color)
			.lerp(horizon, 0.5)).lerp(Color.WHITE, 0.55),
		# Haze target is an albedo too: the horizon tint at the value distant
		# geometry has to land on once the light hits it.
		"horizon": horizon.lerp(Color.WHITE, 0.45) * 0.62,
		"snow": base.lerp(Color.WHITE, 0.7) * 0.5,
		"rock": base * 0.15,
		"ice": base * 0.42,
		"haze": 0.0,
	}
	var plane_y := float(params.get("berg_y", ground_plane_y()))
	var density := float(params.get("skyline_density", 1.0))
	match String(SettingsManager.get_setting("display", "quality_preset")):
		"low":
			density *= 0.5
		"medium":
			density *= 0.78
	# near / far = lateral distance from the racing line. Heights are tuned so
	# each band subtends a similar slice of sky from the track: the near band
	# is a low broken foreground, the far band a horizon wall.
	# h_min/h_max are metres of rise ABOVE THE RACING LINE, not absolute height.
	var bands: Array[Dictionary] = [
		{"name": "SkylineNear", "near": 150.0, "far": 340.0, "step": 155.0, "per": 2,
			"h_min": 4.0, "h_max": 22.0, "foot": 1.15, "haze": 0.06,
			"mix": ["ridge", "ridge", "dome", "peak", "ridge"], "cull": 620.0},
		{"name": "SkylineMid", "near": 360.0, "far": 530.0, "step": 250.0, "per": 2,
			"h_min": 24.0, "h_max": 78.0, "foot": 1.0, "haze": 0.2,
			"mix": ["peak", "tabular", "tabular", "ridge", "dome"], "cull": 0.0},
		{"name": "SkylineFar", "near": 545.0, "far": 700.0, "step": 330.0, "per": 1,
			"h_min": 100.0, "h_max": 235.0, "foot": 0.85, "haze": 0.46,
			"mix": ["peak", "peak", "peak", "tabular", "dome"], "cull": 0.0},
	]
	for band: Dictionary in bands:
		_build_skyline_band(band, look, plane_y, density)


func _build_skyline_band(band: Dictionary, look: Dictionary, plane_y: float, density: float) -> void:
	var step := maxf(float(band["step"]) / maxf(density, 0.2), 60.0)
	var near_lat := float(band["near"])
	var far_lat := float(band["far"])
	var mix: Array = band["mix"]
	# Stations run past both ends of the line so the view down-track at the
	# start and past the finish is never a bare horizon.
	var start := -step * 2.0
	var end := main_guide.length + step * 2.0
	var station := 0
	var chunk_size := 3  # stations per baked mesh: enough for frustum culling
	var chunks: Dictionary = {}
	var offset := start
	while offset <= end:
		var xform := _extended_frame(offset)
		for side: float in [-1.0, 1.0]:
			for k: int in int(band["per"]):
				if _env_rng.randf() > 0.82:
					continue  # gaps: an unbroken picket fence reads as wallpaper
				var lateral := _env_rng.randf_range(near_lat, far_lat)
				var along := _env_rng.randf_range(-step * 0.45, step * 0.45)
				var pos := xform.origin + xform.basis.x * (lateral * side) - xform.basis.z * along
				pos.y = ground_height_at(Vector3(pos.x, plane_y + 500.0, pos.z), 0.0, 560.0)
				var kind := String(mix[_env_rng.randi() % mix.size()])
				# Heights are authored as RISE ABOVE THE DECK, then grown by
				# however far the surrounding ground sits below the racing line.
				# Courses run their track anywhere from 6m to 40m over their ice
				# sheet, and a fixed height leaves the whole band hidden behind
				# the track shoulder on the tall ones — which is exactly how the
				# dead plate between racer and horizon opened up.
				var height := _env_rng.randf_range(float(band["h_min"]), float(band["h_max"])) \
					+ clampf(xform.origin.y - pos.y, 0.0, 45.0)
				# Aspect ratio is what tells a horn from a tabular berth: one
				# shared width-to-height ratio for every form in a band is the
				# repeated-mesh look with extra steps.
				var shape := 1.0
				match kind:
					"tabular":
						shape = _env_rng.randf_range(0.8, 1.7)
					"dome":
						shape = _env_rng.randf_range(0.9, 1.6)
					"ridge":
						shape = _env_rng.randf_range(0.32, 0.62)
					_:
						# Massifs are broader than they are tall. A footprint
						# under about 0.8x the height gives the spike silhouette
						# that reads as placeholder cone geometry.
						shape = _env_rng.randf_range(0.9, 1.7)
				var footprint := height * shape * float(band["foot"])
				var reach := footprint * (0.5 * _RIDGE_SPAN if kind == "ridge" else 1.0)
				if not _skyline_clear(pos, reach * 1.25 + 30.0):
					continue
				pos.y -= ground_embed(height, 0.03)
				var form: Dictionary = look.duplicate()
				# Per-form value jitter: two neighbours cut from the same tone
				# read as two copies of one prop however different their shape.
				var jitter := _env_rng.randf_range(0.86, 1.14)
				form["ice"] = (look["ice"] as Color) * jitter
				form["snow"] = (look["snow"] as Color) * lerpf(1.0, jitter, 0.6)
				form["rock"] = (look["rock"] as Color) * jitter
				# Depth inside the band: the far edge of a band is a good 40%
				# further away than its near edge, and must read that way.
				form["haze"] = clampf(float(band["haze"])
					+ (lateral - near_lat) / maxf(far_lat - near_lat, 1.0) * 0.13, 0.0, 0.92)
				var key := station / chunk_size
				if not chunks.has(key):
					var fresh := SurfaceTool.new()
					fresh.begin(Mesh.PRIMITIVE_TRIANGLES)
					chunks[key] = fresh
				_bake_form(chunks[key], kind, pos, footprint, height, form, 0)
		station += 1
		offset += step
	# Terrain shader, not a flat rock material.
	#
	# The skyline is the largest mass in most frames and every one of its faces
	# was a single flat value, which is what made it read as folded paper no
	# matter how good the silhouettes were. The terrain shader adds world-Y
	# strata, a slope-gated snow catch on upward faces and its own distance
	# ramp -- the same treatment the cliffs got -- so a face has internal
	# structure instead of one tone. Structure eases off with the band's haze:
	# the far ring should read as atmosphere, not as detail.
	var band_haze := float(band.get("haze", 0.0))
	var material := VisualLibrary.terrain_material(
		Color(1.0, 1.0, 1.0), clampf(1.0 - band_haze * 1.4, 0.15, 1.0), band_haze)
	for key: Variant in chunks:
		var st: SurfaceTool = chunks[key]
		st.generate_normals()
		var instance := MeshInstance3D.new()
		instance.name = "%s_%d" % [band["name"], int(key)]
		instance.mesh = st.commit()
		instance.material_override = material
		# Backdrop only: never let a 200m massif throw a shadow map's worth of
		# resolution away, and never let it shadow the racing line.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if float(band["cull"]) > 0.0:
			VisualLibrary.apply_dressing_range(instance, float(band["cull"]))
		add_child(instance)


## Guide frame extended past both ends of the line: offsets outside [0, length]
## keep the end frame and slide along its tangent, so skyline stations can run
## beyond the start and the finish.
func _extended_frame(offset: float) -> Transform3D:
	var clamped := clampf(offset, 0.0, main_guide.length)
	var xform := main_guide.transform_at(clamped)
	var over := offset - clamped
	if absf(over) > 0.01:
		xform.origin -= xform.basis.z * over
	return xform


## True when nothing of the racing line — main or branch — comes within
## `clearance` of `pos` horizontally. Skyline forms are backdrop: one landing on
## a switchback below or a shortcut beside the camera destroys the depth read.
func _skyline_clear(pos: Vector3, clearance: float) -> bool:
	var flat := Vector3(pos.x, 0.0, pos.z)
	if _flat_distance_to(main_guide, flat) < clearance:
		return false
	for branch: Dictionary in branches:
		if _flat_distance_to(branch["guide"] as PathGuide, flat) < clearance:
			return false
	return true


func _flat_distance_to(guide: PathGuide, flat_pos: Vector3) -> float:
	var best := INF
	for point: Vector3 in guide.points:
		var dx := point.x - flat_pos.x
		var dz := point.z - flat_pos.z
		best = minf(best, dx * dx + dz * dz)
	return sqrt(best)


## --- Skyline form generators -------------------------------------------------
## Every generator writes world-space triangles with baked per-face colour into
## a shared SurfaceTool. `depth` guards the one-level recursion the compound
## forms use (a shoulder peak, a stacked berg tier).

func _bake_form(st: SurfaceTool, kind: String, pos: Vector3, footprint: float,
		height: float, look: Dictionary, depth: int) -> void:
	match kind:
		"tabular":
			_bake_tabular(st, pos, footprint, height, look, depth)
		"ridge":
			_bake_ridge(st, pos, footprint, height, look)
		"dome":
			_bake_dome(st, pos, footprint, height, look)
		_:
			_bake_peak(st, pos, footprint, height, look, depth)


## Craggy massif. Four rings under an apex; a per-form profile exponent decides
## whether it is a broad-shouldered block or a sharp horn, angular noise plus
## per-column spurs run ridges down the flanks, and the ring centres drift with
## altitude so nothing is a symmetric cone. Rock below a per-form snowline,
## dappled through the transition band, white above.
func _bake_peak(st: SurfaceTool, pos: Vector3, footprint: float, height: float,
		look: Dictionary, depth: int) -> void:
	var sides := _env_rng.randi_range(9, 13)
	# Biased concave: a profile of 1.0 is a straight-sided cone, and a field of
	# those is the low-poly-placeholder look. Under 1.0 the flanks flare into
	# shoulders, over it they blunt into mesas — both beat a ruled triangle.
	var profile := _env_rng.randf_range(0.45, 1.35)
	if _env_rng.randf() < 0.6:
		profile = _env_rng.randf_range(0.45, 0.85)
	var ring_t: Array[float] = [0.0, 0.3, 0.58, 0.81]
	var lean := Vector2(_env_rng.randf_range(-0.32, 0.32), _env_rng.randf_range(-0.32, 0.32))
	var phase_a := _env_rng.randf() * TAU
	var phase_b := _env_rng.randf() * TAU
	var amp_a := _env_rng.randf_range(0.09, 0.2)
	var amp_b := _env_rng.randf_range(0.04, 0.1)
	var spurs: Array[float] = []
	var streaks: Array[float] = []
	for i: int in sides:
		spurs.append(_env_rng.randf_range(0.6, 1.42))
		streaks.append(_env_rng.randf_range(0.72, 1.18))
	var rings: Array[PackedVector3Array] = []
	for r: int in ring_t.size():
		var t := ring_t[r]
		var ring := PackedVector3Array()
		for i: int in sides:
			var angle := TAU * float(i) / float(sides)
			var noise := 1.0 + amp_a * sin(angle * 2.0 + phase_a) + amp_b * sin(angle * 5.0 + phase_b)
			# Spurs are strongest at the base and dissolve toward the summit.
			var spur := 1.0 + (spurs[i] - 1.0) * (1.0 - t * 0.55)
			var radius := footprint * pow(1.0 - t, profile) * noise * spur * _env_rng.randf_range(0.93, 1.07)
			var y := t * height + (_env_rng.randf_range(-0.025, 0.03) * height if r > 0 else 0.0)
			ring.append(pos + Vector3(
				cos(angle) * radius + lean.x * t * footprint, y,
				sin(angle) * radius + lean.y * t * footprint))
		rings.append(ring)
	var apex := pos + Vector3(
		lean.x * footprint + _env_rng.randf_range(-0.08, 0.08) * footprint,
		height * _env_rng.randf_range(0.96, 1.08),
		lean.y * footprint + _env_rng.randf_range(-0.08, 0.08) * footprint)
	var snowline := _env_rng.randf_range(0.4, 0.78) * height
	for r: int in ring_t.size() - 1:
		for i: int in sides:
			var j := (i + 1) % sides
			var lo0 := rings[r][i]
			var lo1 := rings[r][j]
			var hi0 := rings[r + 1][i]
			var hi1 := rings[r + 1][j]
			var mid_y := (lo0.y + lo1.y + hi0.y + hi1.y) * 0.25 - pos.y
			_face(st, lo0, hi1, hi0, _peak_color(look, lo0, hi1, hi0, pos, mid_y, snowline, streaks[i]))
			_face(st, lo0, lo1, hi1, _peak_color(look, lo0, lo1, hi1, pos, mid_y, snowline, streaks[i]))
	var top := ring_t.size() - 1
	for i: int in sides:
		var j := (i + 1) % sides
		var mid_y := (rings[top][i].y + rings[top][j].y + apex.y) / 3.0 - pos.y
		_face(st, rings[top][i], rings[top][j], apex,
			_peak_color(look, rings[top][i], rings[top][j], apex, pos, mid_y, snowline, streaks[i]))
	# Compound massifs: a lower shoulder off one flank. Real ranges are ridges
	# with several summits, and a field of single horns reads generated.
	if depth == 0 and _env_rng.randf() < 0.68:
		var angle := _env_rng.randf() * TAU
		var away := footprint * _env_rng.randf_range(0.6, 1.1)
		_bake_peak(st, pos + Vector3(cos(angle) * away, 0.0, sin(angle) * away),
			footprint * _env_rng.randf_range(0.42, 0.78),
			height * _env_rng.randf_range(0.35, 0.82), look, depth + 1)


func _peak_color(look: Dictionary, a: Vector3, b: Vector3, c: Vector3, pos: Vector3,
		mid_y: float, snowline: float, streak: float) -> Color:
	var tone: Color
	var band := maxf(snowline * 0.22, 2.0)
	if mid_y > snowline + band:
		tone = look["snow"]
	elif mid_y > snowline - band:
		# Dappled transition: real snowlines are patchy scatter, not a ruled
		# line, and the odds of holding snow climb through the band.
		var odds := (mid_y - (snowline - band)) / (band * 2.0)
		tone = look["snow"] if _env_rng.randf() < odds else (look["rock"] as Color).lerp(look["snow"], 0.45)
	else:
		var rock: Color = look["rock"]
		# Vertical streaking: blue decays slower than red/green so gullies cool.
		tone = Color(rock.r * streak, rock.g * streak, rock.b * (0.62 + 0.38 * streak))
	return _shade(look, _flat_normal(a, b, c), tone, 1.0)


## Tabular berg / ice cliff: an irregular polygonal slab with fluted vertical
## walls, a darker waterline foot and a slightly tilted snow table. Roughly
## half of them carry a second, smaller tier — the calved, stepped profile that
## makes a berg read as ice rather than as a cone.
func _bake_tabular(st: SurfaceTool, pos: Vector3, footprint: float, height: float,
		look: Dictionary, depth: int) -> void:
	var sides := _env_rng.randi_range(6, 9)
	var tilt_phase := _env_rng.randf() * TAU
	var tilt := _env_rng.randf_range(0.03, 0.13)
	var radii: Array[float] = []
	var flutes: Array[float] = []
	for i: int in sides:
		radii.append(footprint * _env_rng.randf_range(0.68, 1.25))
		flutes.append(_env_rng.randf_range(0.72, 1.12))
	var foot := height * _env_rng.randf_range(0.05, 0.11)
	var base_pts: Array[Vector3] = []
	var foot_pts: Array[Vector3] = []
	var top_pts: Array[Vector3] = []
	for i: int in sides:
		var angle := TAU * float(i) / float(sides) + _env_rng.randf_range(-0.12, 0.12)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var top_y := height * (1.0 + tilt * cos(angle - tilt_phase))
		base_pts.append(pos + dir * radii[i])
		foot_pts.append(pos + dir * radii[i] * 1.03 + Vector3.UP * foot)
		# Walls lean in slightly toward the table: dead-vertical prisms read as
		# untextured boxes.
		top_pts.append(pos + dir * radii[i] * _env_rng.randf_range(0.82, 0.95) + Vector3.UP * top_y)
	var wall: Color = (look["ice"] as Color)
	var wet := Color(wall.r * 0.62, wall.g * 0.74, wall.b * 0.88)
	for i: int in sides:
		var j := (i + 1) % sides
		var normal := _flat_normal(base_pts[i], base_pts[j], top_pts[j])
		_quad(st, base_pts[i], base_pts[j], foot_pts[j], foot_pts[i], _shade(look, normal, wet, 0.9))
		_quad(st, foot_pts[i], foot_pts[j], top_pts[j], top_pts[i],
			_shade(look, normal, wall, flutes[i]))
	# Table: fan from the centroid, bright wind-packed snow.
	var centre := Vector3.ZERO
	for point: Vector3 in top_pts:
		centre += point
	centre /= float(sides)
	var table := _shade(look, Vector3.UP, look["snow"], 1.0)
	for i: int in sides:
		_face(st, top_pts[i], top_pts[(i + 1) % sides], centre, table)
	if depth == 0 and _env_rng.randf() < 0.5:
		var angle := _env_rng.randf() * TAU
		var away := footprint * _env_rng.randf_range(0.1, 0.4)
		_bake_tabular(st, pos + Vector3(cos(angle) * away, 0.0, sin(angle) * away),
			footprint * _env_rng.randf_range(0.4, 0.65),
			height * _env_rng.randf_range(1.25, 1.8), look, depth + 1)


## Pressure ridge: a long jagged wall of upthrust ice. The near band leans on
## these — they fill the dead plate between the track and the horizon without
## walling the view off, which a field of peaks would.
func _bake_ridge(st: SurfaceTool, pos: Vector3, footprint: float, height: float,
		look: Dictionary) -> void:
	var length := footprint * _env_rng.randf_range(_RIDGE_SPAN * 0.6, _RIDGE_SPAN)
	var angle := _env_rng.randf() * TAU
	var dir := Vector3(cos(angle), 0.0, sin(angle))
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var segments := _env_rng.randi_range(5, 9)
	var thick := footprint * _env_rng.randf_range(0.3, 0.55)
	var crest: Array[Vector3] = []
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i: int in segments + 1:
		var t := float(i) / float(segments)
		var along := (t - 0.5) * length
		# Taper toward the ends plus per-tooth jitter: a sawtooth crest, not a
		# smooth extrusion.
		var taper := sin(t * PI)
		var crest_y := height * (0.35 + 0.65 * taper) * _env_rng.randf_range(0.55, 1.15)
		var wander := perp * _env_rng.randf_range(-thick, thick) * 1.4
		var spine := pos + dir * along + wander
		crest.append(spine + Vector3.UP * crest_y)
		var half := thick * _env_rng.randf_range(0.7, 1.35)
		left.append(spine - perp * half)
		right.append(spine + perp * half)
	var snow: Color = look["snow"]
	var ice: Color = look["ice"]
	for i: int in segments:
		var j := i + 1
		var left_n := _flat_normal(left[i], crest[i], crest[j])
		var right_n := _flat_normal(right[j], crest[j], crest[i])
		_quad(st, left[i], left[j], crest[j], crest[i],
			_shade(look, left_n, ice.lerp(snow, _env_rng.randf_range(0.2, 0.8)), 1.0))
		_quad(st, crest[i], crest[j], right[j], right[i],
			_shade(look, right_n, ice.lerp(snow, _env_rng.randf_range(0.2, 0.8)), 1.0))


## Wind-scoured snow dome / hummock. Rounded, all snow, no rock: the quiet form
## that keeps a band of peaks and slabs from reading as a single generator.
func _bake_dome(st: SurfaceTool, pos: Vector3, footprint: float, height: float,
		look: Dictionary) -> void:
	var sides := _env_rng.randi_range(7, 10)
	var rings := 3
	var squash := _env_rng.randf_range(0.75, 1.35)
	var lean := Vector2(_env_rng.randf_range(-0.14, 0.14), _env_rng.randf_range(-0.14, 0.14))
	var wobble: Array[float] = []
	for i: int in sides:
		wobble.append(_env_rng.randf_range(0.8, 1.22))
	var loops: Array[PackedVector3Array] = []
	for r: int in rings:
		var t := float(r) / float(rings)
		var loop := PackedVector3Array()
		for i: int in sides:
			var angle := TAU * float(i) / float(sides)
			var radius := footprint * cos(t * PI * 0.5) * wobble[i] * _env_rng.randf_range(0.94, 1.06)
			loop.append(pos + Vector3(
				cos(angle) * radius + lean.x * t * footprint,
				sin(t * PI * 0.5) * height * squash,
				sin(angle) * radius * squash + lean.y * t * footprint))
		loops.append(loop)
	var cap := pos + Vector3(lean.x * footprint, height * squash * _env_rng.randf_range(0.95, 1.05),
		lean.y * footprint)
	var snow: Color = look["snow"]
	for r: int in rings - 1:
		for i: int in sides:
			var j := (i + 1) % sides
			var normal := _flat_normal(loops[r][i], loops[r][j], loops[r + 1][j])
			var tone := snow.lerp(look["ice"], _env_rng.randf_range(0.0, 0.28))
			_quad(st, loops[r][i], loops[r][j], loops[r + 1][j], loops[r + 1][i],
				_shade(look, normal, tone, 1.0))
	for i: int in sides:
		var j := (i + 1) % sides
		_face(st, loops[rings - 1][i], loops[rings - 1][j], cap,
			_shade(look, _flat_normal(loops[rings - 1][i], loops[rings - 1][j], cap), snow, 1.0))


## --- Skyline shading ---------------------------------------------------------

## Baked aerial perspective + sun modelling for one face. Lit faces run warm and
## bright, averted faces cool and dark (real lighting still runs on top, and
## distant white geometry needs the help — a hazed massif barely registers a
## normal), then the whole thing recedes toward the sky horizon by band haze.
func _shade(look: Dictionary, normal: Vector3, tone: Color, gain: float) -> Color:
	var flat := Vector3(normal.x, 0.0, normal.z)
	var facing := 0.5
	if flat.length_squared() > 0.0001:
		facing = 0.5 + 0.5 * clampf(flat.normalized().dot(look["to_sun"]), -1.0, 1.0)
	# Up-facing snow always reads lit regardless of which way the slope points.
	facing = clampf(lerpf(facing, 1.0, clampf(normal.y, 0.0, 1.0) * 0.4), 0.0, 1.0)
	var tint: Color = (look["cool"] as Color).lerp(look["warm"], facing)
	var lum := lerpf(0.42, 1.06, facing) * gain
	var col := Color(tone.r * tint.r * lum, tone.g * tint.g * lum, tone.b * tint.b * lum)
	return col.lerp(look["horizon"], float(look["haze"]))


static func _flat_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		return Vector3.UP
	return normal.normalized()


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(a)
	st.set_color(color)
	st.add_vertex(b)
	st.set_color(color)
	st.add_vertex(c)


## Quad as two triangles; corners in order around the face.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_face(st, a, b, c, color)
	_face(st, a, c, d, color)


## --- Procedural sky panorama --------------------------------------------------

static var _sky_cover_cache: Dictionary = {}


## Equirectangular cloud panorama for ProceduralSkyMaterial.sky_cover. Two
## perspective-projected decks — a cumulus field and thin cirrus above it — are
## sampled on flat sky planes, so shapes compress and crowd toward the horizon
## the way a real cloud deck does instead of floating as evenly spaced blobs.
## Alpha carries coverage; the sky shader adds rgb * modulate * alpha over the
## gradient, which is why the deck is white here and tinted by the caller.
## Generated once per (seed, look) and shared by every build in the session:
## 320x160, only the sky hemisphere filled, so about 25k pixels of work.
static func _sky_cover_texture(seed_value: int, coverage: float, streaks: float) -> ImageTexture:
	var key := "%d_%.2f_%.2f" % [seed_value, coverage, streaks]
	if _sky_cover_cache.has(key):
		return _sky_cover_cache[key]
	var width := 320
	var height := 160
	var deck := FastNoiseLite.new()
	deck.seed = seed_value
	deck.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	deck.frequency = 0.26
	deck.fractal_type = FastNoiseLite.FRACTAL_FBM
	deck.fractal_octaves = 4
	deck.fractal_gain = 0.52
	deck.fractal_lacunarity = 2.2
	var veil := FastNoiseLite.new()
	veil.seed = seed_value + 977
	veil.noise_type = FastNoiseLite.TYPE_SIMPLEX
	veil.frequency = 0.3
	veil.fractal_type = FastNoiseLite.FRACTAL_FBM
	veil.fractal_octaves = 3
	var data := PackedByteArray()
	data.resize(width * height * 4)
	data.fill(0)
	# Coverage threshold: lower threshold = more sky filled.
	var lo := lerpf(0.62, 0.24, coverage)
	var hi := lo + 0.26
	for y: int in height:
		var elevation := (0.5 - (float(y) + 0.5) / float(height)) * PI
		if elevation <= 0.015:
			continue  # below the horizon the sky material draws its ground half
		# Distance along a flat cloud plane one unit up: the whole reason the
		# deck gains perspective instead of tiling evenly across the dome.
		var distance := clampf(1.0 / tan(elevation), 0.0, 34.0)
		# Dissolve into horizon haze well before the deck compresses into mush,
		# and keep the zenith (where an equirect panorama pinches to a point)
		# clear rather than smeared into one blob overhead.
		var fade := (1.0 - smoothstep(15.0, 31.0, distance)) * smoothstep(0.8, 2.3, distance)
		if fade <= 0.002:
			continue
		for x: int in width:
			var theta := (float(x) + 0.5) / float(width) * TAU
			var px := cos(theta) * distance
			var pz := sin(theta) * distance
			var n := deck.get_noise_2d(px, pz) * 0.5 + 0.5
			var cumulus := smoothstep(lo, hi, n)
			# Cirrus rides a higher plane (halved distance) and is stretched
			# along one axis into wind-drawn streaks.
			var s := veil.get_noise_2d(px * 0.28, pz * 1.7) * 0.5 + 0.5
			var cirrus := smoothstep(0.58, 0.86, s) * streaks
			var alpha := clampf(cumulus + cirrus * (1.0 - cumulus) * 0.55, 0.0, 1.0) * fade
			if alpha <= 0.004:
				continue
			# Thin edges lose a little punch and cool off; cores stay white.
			var body := 0.72 + 0.28 * cumulus
			var index := (y * width + x) * 4
			data[index] = int(255.0 * body)
			data[index + 1] = int(255.0 * (body * 0.995))
			data[index + 2] = int(255.0 * minf(body * 1.02, 1.0))
			data[index + 3] = int(255.0 * alpha)
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	var texture := ImageTexture.create_from_image(image)
	_sky_cover_cache[key] = texture
	return texture


func _add_snowfall() -> void:
	var snow := GPUParticles3D.new()
	snow.name = "Snowfall"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(45.0, 1.0, 45.0)
	mat.direction = Vector3(0, -1, 0)
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0.4, -3.0, 0.2)
	mat.scale_min = 0.04
	mat.scale_max = 0.1
	snow.process_material = mat
	var flake := QuadMesh.new()
	flake.size = Vector2(0.12, 0.12)
	flake.material = VisualLibrary.billboard_puff_material(Color(1, 1, 1, 0.85), 32, 0.9)
	snow.draw_pass_1 = flake
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	snow.amount = 220 if quality == "high" else (120 if quality == "medium" else 50)
	snow.lifetime = 7.0
	snow.preprocess = 4.0
	snow.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	add_child(snow)
	# Follow the active camera so snow always surrounds the player.
	var follower := Timer.new()
	follower.wait_time = 0.25
	follower.autostart = true
	follower.timeout.connect(func() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			snow.global_position = cam.global_position + Vector3.UP * 18.0)
	snow.add_child(follower)


## --- Pooled one-shot VFX ----------------------------------------------------

func _build_vfx_pools() -> void:
	if GameConfig.is_headless():
		return
	# Smaller pools + fewer particles per burst on the low tier; high and
	# medium keep the current look.
	var low := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	for i: int in (4 if low else 8):
		_puff_pool.append(_make_burst(Color(0.98, 0.99, 1.0, 0.9), 8 if low else 14, 0.45))
	for i: int in (3 if low else 6):
		_splash_pool.append(_make_burst(Color(0.55, 0.78, 0.95, 0.9), 12 if low else 20, 0.6))


## Process material + draw mesh per burst config, shared by the whole pool
## across every course and race: identical bursts must not compile one WebGL
## program per pooled emitter.
static var _burst_configs: Dictionary = {}


func _make_burst(color: Color, count: int, life: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.explosiveness = 0.95
	particles.amount = count
	particles.lifetime = life
	var key := "burst_%s" % color.to_html()
	var config: Array = _burst_configs.get(key, [])
	if config.is_empty():
		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3.UP
		mat.spread = 70.0
		mat.initial_velocity_min = 2.0
		mat.initial_velocity_max = 5.5
		mat.gravity = Vector3(0, -9, 0)
		mat.scale_min = 0.10
		mat.scale_max = 0.30
		mat.color = color
		# Air drag: thrown snow loses its speed fast instead of flying on a clean
		# parabola, which is most of what separates a puff of powder from a
		# handful of pellets.
		mat.damping_min = 1.5
		mat.damping_max = 4.0
		# Spin so no two puffs present the same face.
		mat.angular_velocity_min = -220.0
		mat.angular_velocity_max = 220.0
		mat.scale_curve = _burst_scale_curve()
		mat.color_ramp = _burst_fade_ramp()
		# Soft round billboard rather than a lit sphere: a burst of powder has
		# no shading of its own, and the shared puff material is one the boot
		# warm-up has already linked.
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.36, 0.36)
		mesh.material = VisualLibrary.billboard_puff_material(color, 32, 0.85, true)
		config = [mat, mesh]
		_burst_configs[key] = config
	particles.process_material = config[0]
	particles.draw_pass_1 = config[1]
	add_child(particles)
	return particles


## Puffs swell as they are thrown and shrink as they settle, instead of holding
## one size for their whole life the way an untreated emitter does.
static var _burst_scale_curve_cache: CurveTexture = null
static var _burst_fade_ramp_cache: GradientTexture1D = null


static func _burst_scale_curve() -> CurveTexture:
	if _burst_scale_curve_cache != null:
		return _burst_scale_curve_cache
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.22, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	var tex := CurveTexture.new()
	tex.curve = curve
	_burst_scale_curve_cache = tex
	return tex


## Bright at the moment of impact, then fading out rather than popping off.
static func _burst_fade_ramp() -> GradientTexture1D:
	if _burst_fade_ramp_cache != null:
		return _burst_fade_ramp_cache
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.85))
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	_burst_fade_ramp_cache = tex
	return tex


## BUILD TIME ONLY. Gives one drawn snow drift a ploughing volume, using the
## same transform handed to the multimesh that renders it. Courses call this
## alongside appending to their bank transform list, so the thing the player
## sees and the thing that slows them down cannot drift apart.
## Built headless too: drifts are physics, and a sim that cannot feel them is
## not simulating the race the player runs.
func add_snow_drift(xform: Transform3D) -> void:
	if _snow_drifts == null:
		_snow_drifts = SnowDriftField.new()
		_snow_drifts.name = "SnowDrifts"
		add_child(_snow_drifts)
	_snow_drifts.add_drift(xform)


func spawn_land_puff(pos: Vector3) -> void:
	if _puff_pool.is_empty():
		return
	var particles := _puff_pool[_puff_next]
	_puff_next = (_puff_next + 1) % _puff_pool.size()
	particles.global_position = pos
	particles.restart()


func spawn_splash(pos: Vector3) -> void:
	if _splash_pool.is_empty():
		return
	var particles := _splash_pool[_splash_next]
	_splash_next = (_splash_next + 1) % _splash_pool.size()
	particles.global_position = pos
	particles.restart()


## --- Pickup helpers ---------------------------------------------------------

func add_fish_line(offset_start: float, count: int, spacing: float = 4.0, lateral: float = 0.0, arc_height: float = 0.0, guide: PathGuide = null) -> void:
	var g := guide if guide != null else main_guide
	for i: int in count:
		var offset := offset_start + float(i) * spacing
		if offset >= g.length:
			break
		var height := 0.8
		if arc_height > 0.0:
			var t := float(i) / maxf(float(count - 1), 1.0)
			height += sin(t * PI) * arc_height
		var fish := FishPickup.new()
		fish.position = g.point_at(offset, lateral, height)
		add_child(fish)


func add_item_row(offset: float, count: int = 4, guide: PathGuide = null) -> void:
	var g := guide if guide != null else main_guide
	var span := 10.0
	for i: int in count:
		var lateral := -span * 0.5 + span * float(i) / maxf(float(count - 1), 1.0)
		var box := ItemBox.new()
		box.position = g.point_at(offset, lateral, 1.1)
		add_child(box)


## Lateral row of collectible throwable snowballs (see SnowballPickup).
func add_snowball_row(offset: float, count: int = 3, guide: PathGuide = null) -> void:
	var g := guide if guide != null else main_guide
	if g == null or offset >= g.length:
		return
	var span := 7.0
	for i: int in count:
		var lateral := 0.0 if count <= 1 else -span * 0.5 + span * float(i) / float(count - 1)
		var ball := SnowballPickup.new()
		ball.position = g.point_at(offset, lateral, 0.55)
		add_child(ball)


## Big ground plane far below for visual grounding (ocean/ice sheet).
## Optional material overrides the flat color — e.g.
## VisualLibrary.water_material(...) for ocean or snow_material(...) for
## an ice sheet (pass subdivided = true with water so waves displace).
## Also records the plane height as this course's base ground level, which is
## what every far-field dressing helper seats itself on — so call this BEFORE
## _decorate()/build_environment() rather than as the last line of a build.
## Visual only by design: giving the plane a collider would change where
## racers land and what the kill floor means.
func add_ground_plane(y: float, color: Color, size: float = 4000.0, material: Material = null, subdivided: bool = false) -> void:
	base_ground_y = y
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	if subdivided:
		mesh.subdivide_width = 48
		mesh.subdivide_depth = 48
	plane.mesh = mesh
	if material != null:
		plane.material_override = material
	else:
		# Cached; the plane has no vertex colors so it renders plain `color`.
		plane.material_override = VisualLibrary.rock_material(color, 0.6)
	plane.position = Vector3(0, y, 0)
	add_child(plane)
