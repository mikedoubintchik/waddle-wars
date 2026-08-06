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
	var xform := guide.transform_at(offset)
	var from_y := xform.origin.y + GROUND_PROBE_START
	var depth := GROUND_MAX_DROP + GROUND_PROBE_START
	var centre := xform.origin
	if _raw_ground(centre.x, centre.z, from_y, depth) == -INF:
		_edge_cache[key] = fallback
		return fallback
	var dir := xform.basis.x * sign_side
	var lo := 0.0
	var hi := limit
	for _i: int in 7:
		var mid := (lo + hi) * 0.5
		var p := centre + dir * mid
		if _raw_ground(p.x, p.z, from_y, depth) != -INF:
			lo = mid
		else:
			hi = mid
	_edge_cache[key] = lo
	return lo


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
##   shadow_distance (140.0), clouds (bool) + cloud_color, distant_bergs
##   (bool) + berg_color/berg_count/berg_distance/berg_y.
## Atmospheric perspective (all optional): fog_horizon_blend (0..1, default
##   0.35 — shifts the fog hue toward sky_horizon so distance reads as
##   atmosphere, not gray soup), fog_aerial (0..1, default 0.5 — Godot aerial
##   perspective: far geometry blends toward the sky itself), fog_sky_affect
##   (default 0.2), shadow_blur (softer sun shadow edge; defaults 1.0 on the
##   "low" shadow preset, 1.75 otherwise).
## Grade + glow (all optional): glow_intensity (default 0.5), contrast
##   (default 1.07) and saturation (default 1.06) — a mild global grade that
##   sells crisp polar air; ignored by renderers without adjustment support.
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
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Slightly restrained default ambient: shadows keep some depth so the sun
	# actually models form. Courses that tuned ambient_energy are untouched.
	env.ambient_light_energy = float(params.get("ambient_energy", 0.92))
	env.ambient_light_sky_contribution = float(params.get("sky_contribution", 1.0))
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(params.get("exposure", 0.96))
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
		env.adjustment_contrast = float(params.get("contrast", 1.05))
		env.adjustment_saturation = float(params.get("saturation", 1.06))
	if bool(params.get("glow", true)) and SettingsManager.glow_allowed():
		# High HDR threshold: only emissive peaks (boost pads, pickups, aurora)
		# bloom — cheap on Forward Mobile, never a full-screen wash.
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = float(params.get("glow_threshold", 1.1))
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
	if bool(params.get("distant_bergs", false)) and not GameConfig.is_headless():
		_add_distant_bergs(params)


## 3-puff soft billboard cloud clusters spread high along the main line.
## One cached keep-scale billboard material + one shared unit quad for every
## puff (previously: a unique material per course build and a unique QuadMesh
## per puff); per-puff size lives in the node scale instead.
func _add_clouds(color: Color) -> void:
	var cloud_mat := VisualLibrary.billboard_puff_material(color, 64, 0.85, true)
	var puff_mesh := QuadMesh.new()
	puff_mesh.size = Vector2(1.0, 0.55)
	var count := 5
	for i: int in count:
		var anchor := Vector3.ZERO
		if main_guide != null:
			anchor = main_guide.position_at(main_guide.length * (float(i) + 0.5) / float(count))
		var cluster := Node3D.new()
		cluster.name = "Cloud_%d" % i
		cluster.position = anchor + Vector3(
			rng.randf_range(-260.0, 260.0),
			rng.randf_range(110.0, 170.0),
			rng.randf_range(-120.0, 120.0))
		for j: int in 3:
			var puff := MeshInstance3D.new()
			var size := rng.randf_range(55.0, 110.0)
			puff.mesh = puff_mesh
			puff.scale = Vector3(size, size, 1.0)
			puff.material_override = cloud_mat
			# Translucent quads still cast shadows by default — with a low sun
			# they paint huge blue blobs across the track.
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			puff.position = Vector3(
				rng.randf_range(-30.0, 30.0),
				rng.randf_range(-8.0, 8.0),
				rng.randf_range(-18.0, 18.0))
			# Generous range so only genuinely distant clouds fade on medium/low.
			VisualLibrary.apply_dressing_range(puff, 900.0)
			cluster.add_child(puff)
		add_child(cluster)


## Ring of low-poly iceberg silhouettes near the horizon for depth layering.
## The ring stands ON the ice sheet: the old default (lowest track point - 6)
## was a guess that left bergs hanging metres above the plane on any course
## whose track bottoms out well above its ocean level. berg_y still overrides.
func _add_distant_bergs(params: Dictionary) -> void:
	var count := int(params.get("berg_count", 10))
	var distance := float(params.get("berg_distance", 650.0))
	var color: Color = params.get("berg_color", Color(0.78, 0.87, 0.96))
	var center := Vector3.ZERO
	if main_guide != null and main_guide.points.size() > 0:
		var sum := Vector3.ZERO
		for point: Vector3 in main_guide.points:
			sum += point
		center = sum / float(main_guide.points.size())
	var base_y := float(params.get("berg_y", ground_plane_y()))
	var mat := VisualLibrary.rock_material(color)
	for i: int in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.18, 0.18)
		var berg := MeshInstance3D.new()
		berg.mesh = VisualLibrary.berg_mesh(rng.randi())
		berg.material_override = mat
		var s := rng.randf_range(28.0, 70.0)
		berg.scale = Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.55, 0.9), s)
		# berg_mesh starts at local y = 0, so the scaled Y is the berg height:
		# sink a slice of it so the waterline reads planted, not balanced.
		berg.position = Vector3(center.x + cos(angle) * distance,
			base_y - ground_embed(berg.scale.y, 0.06), center.z + sin(angle) * distance)
		berg.rotation.y = rng.randf() * TAU
		# Horizon dressing: only the far side of the berg ring fades on low.
		VisualLibrary.apply_dressing_range(berg, 1200.0)
		add_child(berg)


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
		mat.initial_velocity_max = 5.0
		mat.gravity = Vector3(0, -9, 0)
		mat.scale_min = 0.08
		mat.scale_max = 0.22
		mat.color = color
		var mesh := SphereMesh.new()
		mesh.radius = 0.09
		mesh.height = 0.18
		mesh.radial_segments = 6
		mesh.rings = 4
		var draw_mat := StandardMaterial3D.new()
		draw_mat.albedo_color = color
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = draw_mat
		config = [mat, mesh]
		_burst_configs[key] = config
	particles.process_material = config[0]
	particles.draw_pass_1 = config[1]
	add_child(particles)
	return particles


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
