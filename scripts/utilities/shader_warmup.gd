class_name ShaderWarmup
extends Node
## One-shot first-sight shader compile pass, run behind the loading overlay.
##
## Safari reaches WebGL2 through the platform's native GL driver, so linking a
## program costs microseconds and a first-sight material never shows up as a
## dropped frame. Chrome on macOS reaches it through ANGLE, which translates
## GLSL to Metal and links a pipeline per program: the same material costs
## milliseconds, and a race that reveals a dozen of them one prop at a time
## reads as a stutter every few seconds. That is the whole reason the game
## plays clean in Safari and janks in Chrome.
##
## The fix is not fewer materials (the VisualLibrary dedup pass already took a
## course build down to roughly a dozen), it is compiling them all at a moment
## nobody can see. This node draws one sub-pixel MeshInstance3D per unique
## material, parented to the live camera just past its near plane, for two or
## three frames immediately after a course finishes building — while
## SceneRouter still holds its opaque "Loading…" overlay (it waits three
## frame_post_draw signals before starting a 0.35 s fade). Then it frees
## itself, well before the fade completes.
##
## What it walks, in order of value:
##   * the VisualLibrary registry (every shared course/prop material),
##   * every GeometryInstance3D already in the scene (track ribbons, hazards,
##     racers, particle draw passes) — this catches TrackBuilder and
##     PenguinVisual materials the library never sees,
##   * the library's helper meshes, whose vertex buffers are uploaded lazily,
##   * on Chrome only, synthetic BaseMaterial3D feature combinations plus the
##     particle process materials, which cover effects that do not exist yet
##     at race start (snowball splats, item-box shards, impact bursts).
##
## Everything it spawns is about one screen pixel across, sits 0.2 m from the
## camera behind a fully opaque overlay, carries no collision, and is gone in
## under four frames — it cannot be seen and cannot be hit. Headless runs skip
## the whole thing, so the sims are untouched.
##
## The warmed programs survive the pass: VisualLibrary holds its materials in
## static dictionaries and the synthetic probes are held in a static array
## here, so nothing is refcounted away and later races start already warm.

## Passes on a normal browser / desktop: registry + scene sweep, two frames.
const BASE_PASSES: int = 2
## Chrome pays the ANGLE link cost, so it gets one more pass and the extended
## probe set. Still inside the overlay's three-frame hold.
const CHROME_PASSES: int = 3
## Metres in front of the camera, clamped against its near plane below.
const ANCHOR_DISTANCE: float = 0.2
## Target world size for a warm-up instance, in metres, at ANCHOR_DISTANCE.
## One 1080p pixel spans roughly 0.00025 m there under the chase camera's
## 68 deg FOV, so every instance is scaled to land well under half a pixel no
## matter which mesh it happens to wear — a 2 m iceberg included.
const PROBE_WORLD_SIZE: float = 0.0001
## Model-space displacement budget added to the mesh extent before scaling.
## A vertex shader moves VERTEX before the model matrix runs, so a displacing
## material would otherwise render far larger than its mesh: the water shader
## pushes up to its wave amplitude (~0.6 m on the roughest course preset).
## 1 m of headroom keeps every library shader sub-pixel here.
const MAX_VERTEX_DISPLACEMENT: float = 1.0
## Uniform scale for the throwaway particle emitters. Their extent is driven by
## the process material's velocity and gravity rather than by a mesh AABB, so
## it is bounded by hand: the largest burst in the game travels about 0.35 m
## over the lifetime used here.
const PARTICLE_SCALE: float = 0.0002
## Hard ceiling on spawned instances. A course build sits near a dozen; this
## only exists so a pathological scene cannot turn the warm-up into the stall.
const MAX_INSTANCES: int = 128
## Ceiling on throwaway particle emitters (Chrome pass only).
const MAX_PARTICLE_WARMERS: int = 12

## Synthetic BaseMaterial3D feature combinations, one letter per feature:
##   u unshaded, a alpha transparency, + additive blend, b billboard,
##   k billboard keep-scale, 2 two-sided (cull disabled), v vertex colour,
##   t albedo texture, e emission, s receive-shadows disabled.
## BaseMaterial3D compiles one program per feature combination and shares it
## across every material that asks for the same set, so a throwaway material
## with matching flags links the exact program a mid-race effect will need —
## without having to spawn the projectile or pickup that owns it. These mirror
## the combinations used by item_box, snowball, powerup_system, trail_effect,
## the hazards, and the course dressing.
const PROBE_FLAGS: PackedStringArray = [
	"v",  # lit vertex-coloured rock, ice, drift and berg geometry
	"e",  # lit emissive checkpoint posts, beacons, lit windows
	"a2",  # lit two-sided alpha shelves and ribbons
	"at",  # lit textured alpha (icicle stripe bands)
	"uabt",  # unshaded billboard puff (cloud, flake, ambient snow)
	"uabkt+v",  # additive keep-scale vertex-coloured spray (snowball trail)
	"uabkt+s",  # additive keep-scale glints (aurora dust, boost streaks)
	"ua+2",  # additive two-sided shard fan (item box, snowball chunks)
	"ua+",  # additive flat glints and flashes
	"ua2",  # unshaded two-sided alpha
	"ua",  # unshaded flat alpha (splat discs, shadow blobs)
	"uav",  # unshaded vertex-coloured alpha (tutorial arrows, trails)
]

## Kept for the session so the linked programs are never refcounted away.
static var _probes: Array[Material] = []

var _world: Node = null
var _anchor: Node3D = null
var _extended: bool = false
var _passes_left: int = 0
var _instances: int = 0
var _particle_warmers: int = 0
var _last_cache: Vector2i = Vector2i(-1, -1)
var _seen: Dictionary = {}  # resource instance id -> true


## Starts a warm-up pass over `world` (the race root). Call it once, after the
## course, racers, props and HUD have been requested — racers spawn deferred,
## and the later passes exist precisely to catch them. Returns the node, or
## null when the pass is skipped (headless, or no world).
static func warm(world: Node) -> ShaderWarmup:
	if world == null or GameConfig.is_headless():
		return null
	var warmup := ShaderWarmup.new()
	warmup.name = "ShaderWarmup"
	warmup._world = world
	world.add_child(warmup)
	return warmup


func _ready() -> void:
	# Run ahead of gameplay scripts so a pass always precedes the frame's draw,
	# and keep ticking through a pause so the pass can never be left resident.
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_extended = GameConfig.is_web_chrome()
	_passes_left = CHROME_PASSES if _extended else BASE_PASSES
	_anchor = Node3D.new()
	_anchor.name = "ShaderWarmupAnchor"
	_run_pass()


func _process(_delta: float) -> void:
	if _passes_left > 0:
		_run_pass()
		return
	# Every instance spawned by the final pass has now been through a draw.
	queue_free()


func _exit_tree() -> void:
	# The anchor lives under the camera, not under this node, so it has to be
	# released explicitly.
	if _anchor != null and is_instance_valid(_anchor):
		_anchor.queue_free()
	_anchor = null


## --- Passes ------------------------------------------------------------------

func _run_pass() -> void:
	_passes_left -= 1
	if not _place_anchor():
		return
	var before := _instances
	# The registry only grows, so re-listing it is pointless when its size has
	# not moved since the last pass.
	if VisualLibrary.cache_sizes() != _last_cache:
		for mat: Material in VisualLibrary.cached_materials():
			_warm_material(mat)
		for mesh: Mesh in VisualLibrary.cached_meshes():
			_warm_mesh(mesh)
		# Read again: warming mints the probe mesh and its material, so the
		# pre-loop size would never match on the next pass.
		_last_cache = VisualLibrary.cache_sizes()
	if _extended:
		for mat: Material in probe_materials():
			_warm_material(mat)
	_collect(_world)
	if _instances == before and before > 0:
		# A whole pass found nothing new: everything in reach is linked, so
		# give the frame back instead of spending the rest of the budget.
		_passes_left = 0


## Parents the anchor to whatever camera is current, just past its near plane.
## Re-checked every pass: race.gd makes its chase camera current before the
## warm-up starts, but endless and tutorial build theirs on their own schedule.
func _place_anchor() -> bool:
	if _anchor == null or not is_instance_valid(_anchor):
		return false
	var viewport := get_viewport()
	if viewport == null:
		return false
	var camera := viewport.get_camera_3d()
	if camera == null:
		return _anchor.is_inside_tree()
	if _anchor.get_parent() != camera:
		if _anchor.get_parent() != null:
			_anchor.get_parent().remove_child(_anchor)
		camera.add_child(_anchor)
	_anchor.position = Vector3(0.0, 0.0, -maxf(ANCHOR_DISTANCE, camera.near * 2.0))
	_anchor.rotation = Vector3.ZERO
	return true


## Per-instance scale that shrinks any mesh to PROBE_WORLD_SIZE across. The
## draw call and its program bind still happen at sub-pixel coverage — that is
## the part the compile hangs off — while nothing reaches the screen.
static func _fit_scale(mesh: Mesh) -> Vector3:
	var extent := mesh.get_aabb().size.length() + 2.0 * MAX_VERTEX_DISPLACEMENT
	return Vector3.ONE * (PROBE_WORLD_SIZE / maxf(extent, 0.0001))


## Walks the live scene for materials the library never minted: TrackBuilder
## surfaces, PenguinVisual shader materials, hazard props, particle draw passes.
func _collect(node: Node) -> void:
	if node == null or node == _anchor:
		return
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		_warm_material(geometry.material_override)
		_warm_material(geometry.material_overlay)
		if node is MeshInstance3D:
			var instance := node as MeshInstance3D
			_warm_surfaces(instance.mesh)
			if instance.mesh != null:
				for i: int in instance.mesh.get_surface_count():
					_warm_material(instance.get_surface_override_material(i))
		elif node is GPUParticles3D:
			var particles := node as GPUParticles3D
			for pass_index: int in 4:
				_warm_surfaces(particles.get("draw_pass_%d" % (pass_index + 1)) as Mesh)
			if _extended:
				_warm_particle_process(particles)
		elif node is CPUParticles3D:
			_warm_surfaces((node as CPUParticles3D).mesh)
	for child: Node in node.get_children():
		_collect(child)


func _warm_surfaces(mesh: Mesh) -> void:
	if mesh == null:
		return
	for i: int in mesh.get_surface_count():
		_warm_material(mesh.surface_get_material(i))


## --- Spawning ----------------------------------------------------------------

func _warm_material(mat: Material) -> void:
	if mat == null or _instances >= MAX_INSTANCES:
		return
	var id := mat.get_instance_id()
	if _seen.has(id):
		return
	_seen[id] = true
	var instance := MeshInstance3D.new()
	instance.mesh = VisualLibrary.warmup_mesh()
	instance.scale = _fit_scale(instance.mesh)
	instance.material_override = mat
	# Shadow casting stays on: the depth pass links its own program per
	# material, and that is a stall of exactly the same kind.
	_anchor.add_child(instance)
	_instances += 1


## Draws a library mesh once so its vertex buffers reach the GPU here rather
## than on the frame it first enters the frustum. The material is a cached
## library one, so this adds no program of its own.
func _warm_mesh(mesh: Mesh) -> void:
	if mesh == null or _instances >= MAX_INSTANCES:
		return
	var id := mesh.get_instance_id()
	if _seen.has(id):
		return
	_seen[id] = true
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = _fit_scale(mesh)
	instance.material_override = VisualLibrary.rock_material(Color(1.0, 1.0, 1.0))
	_anchor.add_child(instance)
	_instances += 1


## Compiles a particle process shader by running one particle for one frame.
## local_coords keeps the simulation inside the anchor's transform, so the
## anchor's sub-pixel scale bounds the motion too and nothing can drift into
## view. Chrome-only: on a native GL driver this is not worth the frame.
func _warm_particle_process(source: GPUParticles3D) -> void:
	var mat := source.process_material
	if mat == null or _particle_warmers >= MAX_PARTICLE_WARMERS:
		return
	var id := mat.get_instance_id()
	if _seen.has(id):
		return
	_seen[id] = true
	_particle_warmers += 1
	var particles := GPUParticles3D.new()
	particles.process_material = mat
	var draw_mesh := source.draw_pass_1
	particles.draw_pass_1 = draw_mesh if draw_mesh != null else VisualLibrary.warmup_mesh()
	particles.amount = 1
	particles.lifetime = 0.25
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = true
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-1.0, -1.0, -1.0), Vector3(2.0, 2.0, 2.0))
	particles.scale = Vector3.ONE * PARTICLE_SCALE
	particles.emitting = true
	_anchor.add_child(particles)


## --- Synthetic feature probes -------------------------------------------------

## Shared with BootWarmup, which links the same feature combinations during the
## studio splash so the first race and the first menu both start warm.
static func probe_materials() -> Array[Material]:
	if not _probes.is_empty():
		return _probes
	for flags: String in PROBE_FLAGS:
		_probes.append(_build_probe(flags))
	return _probes


static func _build_probe(flags: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var alpha := 0.5 if flags.contains("a") else 1.0
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha)
	if flags.contains("u"):
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if flags.contains("a"):
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if flags.contains("+"):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if flags.contains("b"):
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if flags.contains("k"):
		mat.billboard_keep_scale = true
	if flags.contains("2"):
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if flags.contains("v"):
		mat.vertex_color_use_as_albedo = true
	if flags.contains("t"):
		mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	if flags.contains("e"):
		mat.emission_enabled = true
		mat.emission = Color(1.0, 1.0, 1.0)
	if flags.contains("s"):
		mat.disable_receive_shadows = true
	return mat
