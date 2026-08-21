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
## nobody can see. This node builds a deterministic queue, then submits exactly
## one real probe/resource per rendered frame while SceneRouter keeps its opaque
## loading overlay up. Prior probes stay resident through the final draw. This
## is longer than a bulk two-frame sweep, but the loader keeps animating: a
## measured 2.4-second single-frame compile freeze is not an acceptable way to
## hide a later gameplay hitch.
##
## What it walks, in order of value:
##   * exact registered mesh/material pairs for streamed content,
##   * every GeometryInstance3D already in the scene (track ribbons, hazards,
##     racers, particle draw passes) — this catches TrackBuilder and
##     PenguinVisual materials the library never sees,
##   * the VisualLibrary registry and helper meshes, whose GPU resources are
##     uploaded lazily,
##   * on Chrome only, synthetic BaseMaterial3D feature combinations plus the
##     particle process materials, which cover effects that do not exist yet
##     at race start (snowball splats, item-box shards, impact bursts).
##
## Everything it spawns is a few screen pixels across, sits 0.2 m from the
## camera behind a fully opaque overlay, carries no collision, and is gone as
## soon as the queue's final item has drawn — it cannot be seen and cannot be hit.
## Headless runs skip the whole thing, so the sims are untouched.
##
## The warmed programs survive the pass: VisualLibrary holds its materials in
## static dictionaries and the synthetic probes are held in a static array
## here, so nothing is refcounted away and later races start already warm.

## Metres in front of the camera, clamped against its near plane below.
const ANCHOR_DISTANCE: float = 0.2
## Target world size for a warm-up instance, in metres, at ANCHOR_DISTANCE.
## One 1080p pixel spans roughly 0.00025 m there under the chase camera's
## 68 deg FOV. Six pixels guarantee raster submission (the old sub-pixel probes
## could be discarded before creating the pipeline) while remaining fully
## hidden by the opaque loader.
const PROBE_WORLD_SIZE: float = 0.0015
## Model-space displacement budget added to the mesh extent before scaling.
## A vertex shader moves VERTEX before the model matrix runs, so a displacing
## material would otherwise render far larger than its mesh: the water shader
## pushes up to its wave amplitude (~0.6 m on the roughest course preset).
## 1 m of headroom keeps every library shader within the tiny probe footprint.
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
## Scene systems may register exact mesh/material pairs for content which is
## deliberately absent at scene start (for example the runner's first tunnel).
## Keep this bounded so a broken streamer cannot turn the loading overlay into
## an unbounded pre-render pass.
const MAX_EXTERNAL_PROBES: int = 32
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
	# Added with the atmosphere layers. Each of these is a feature combination
	# no other material in the game asks for, so without an entry here its
	# program is linked the first frame the effect is visible -- which on
	# Chrome's ANGLE path is a multi-millisecond stall in the opening seconds
	# of a race, exactly where it is most noticeable.
	"ua+v2",  # SunShafts: additive two-sided vertex-coloured blades
	"uabkt",  # spindrift / near-camera flakes: alpha keep-scale billboards
]

## Kept for the session so the linked programs are never refcounted away.
static var _probes: Array[Material] = []
## Exact late-content pairs retained for the session. Unlike the synthetic
## flag probes, these warm both the real vertex-buffer layout and its material
## pipeline in one draw.
static var _external_probes: Array[Dictionary] = []
static var _external_probe_keys: Dictionary = {}
## Opt-in wall-clock evidence for the material census. Production stays on the
## single false branch; timings are never allocated during ordinary loading.
static var perf_trace_enabled: bool = false
static var _perf_trace_events: Array[Dictionary] = []

var _world: Node = null
var _anchor: Node3D = null
var _extended: bool = false
var _instances: int = 0
var _particle_warmers: int = 0
var _queued_particles: int = 0
var _queue: Array[Dictionary] = []
var _queue_keys: Dictionary = {}
var _queue_cursor: int = 0
var _last_submit_frame: int = -1
var _awaiting_draw: bool = false
var _render_serial: int = 0
var _trace_item_started_usec: int = 0
var _trace_item: Dictionary = {}
var _trace_item_index: int = 0
var _trace_item_submit_frame: int = -1
var _trace_item_submit_render_serial: int = -1


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


## Registers content which a scene will stream only after its opening frame.
## Call during scene construction, before warm(). Registration is idempotent;
## static resource caches may safely call this on every retry.
static func register_external_probe(mesh: Mesh, material: Material) -> void:
	if mesh == null or material == null or _external_probes.size() >= MAX_EXTERNAL_PROBES:
		return
	var key := "%d:%d" % [mesh.get_instance_id(), material.get_instance_id()]
	if _external_probe_keys.has(key):
		return
	_external_probe_keys[key] = true
	_external_probes.append({"mesh": mesh, "material": material, "key": key})


static func external_probe_count() -> int:
	return _external_probes.size()


static func has_external_probe(mesh: Mesh, material: Material) -> bool:
	if mesh == null or material == null:
		return false
	var key := "%d:%d" % [mesh.get_instance_id(), material.get_instance_id()]
	return _external_probe_keys.has(key)


static func clear_perf_trace() -> void:
	_perf_trace_events.clear()


static func drain_perf_trace_events() -> Array[Dictionary]:
	var events := _perf_trace_events.duplicate(true)
	_perf_trace_events.clear()
	return events


func _ready() -> void:
	# Run ahead of gameplay scripts so submission always precedes the frame's
	# draw, and keep ticking through a pause so the queue cannot remain resident.
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_extended = GameConfig.is_web_chrome()
	_anchor = Node3D.new()
	_anchor.name = "ShaderWarmupAnchor"
	add_child(_anchor)
	_build_queue()
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	_submit_next_item()


func _process(_delta: float) -> void:
	# A resource remains the only new submission until renderer confirms its
	# frame completed. Process ticks without a draw (minimized/background window)
	# cannot advance this queue or stack multiple probes into a later frame.
	if _awaiting_draw:
		return
	if _queue_cursor < _queue.size():
		_submit_next_item()
		return
	# Final item reached frame_post_draw before _awaiting_draw was cleared.
	queue_free()


func _on_frame_post_draw() -> void:
	_render_serial += 1
	if not _awaiting_draw:
		return
	_record_trace_item()
	_awaiting_draw = false


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	# The anchor lives under the camera, not under this node, so it has to be
	# released explicitly.
	if _anchor != null and is_instance_valid(_anchor):
		_anchor.queue_free()
	_anchor = null


## --- Deterministic queue -----------------------------------------------------

func _build_queue() -> void:
	_queue.clear()
	_queue_keys.clear()
	_queue_cursor = 0
	_queued_particles = 0
	_last_submit_frame = -1
	_awaiting_draw = false
	# 1. Exact streamed mesh/material pairs. A late buffer+pipeline combination
	# matters more than any generic cache entry and cannot be truncated by cap.
	for probe: Dictionary in _external_probes:
		var mesh := probe.get("mesh") as Mesh
		var material := probe.get("material") as Material
		_enqueue({
			"type": "external",
			"key": "external:%s" % String(probe.get("key", "")),
			"name": "%s + %s" % [_resource_label(mesh), _resource_label(material)],
			"mesh": mesh,
			"material": material,
		})
	# 2. Live scene resources in node/surface order. This catches imported hero,
	# track-builder and HUD-adjacent 3D material instances absent from caches.
	_collect_queue(_world)
	# 3. Shared cached materials and buffers in stable semantic-name order.
	for row: Dictionary in _sorted_resources(VisualLibrary.cached_materials(), "material"):
		_enqueue(row)
	for row: Dictionary in _sorted_resources(VisualLibrary.cached_meshes(), "mesh"):
		_enqueue(row)
	# 4. Chrome-only absent-at-start feature and particle combinations.
	if _extended:
		for material: Material in probe_materials():
			_enqueue_material(material, "synthetic")
		_collect_particle_queue(_world)


func _enqueue(item: Dictionary) -> void:
	if _queue.size() >= MAX_INSTANCES:
		return
	var key := String(item.get("key", ""))
	if key == "" or _queue_keys.has(key):
		return
	_queue_keys[key] = true
	_queue.append(item)


func _enqueue_material(material: Material, source: String = "live") -> void:
	if material == null:
		return
	_enqueue({
		"type": "material",
		"key": "material:%d" % material.get_instance_id(),
		"name": "%s:%s" % [source, _resource_label(material)],
		"material": material,
	})


func _enqueue_mesh(mesh: Mesh, source: String = "live") -> void:
	if mesh == null:
		return
	_enqueue({
		"type": "mesh",
		"key": "mesh:%d" % mesh.get_instance_id(),
		"name": "%s:%s" % [source, _resource_label(mesh)],
		"mesh": mesh,
	})


func _enqueue_particle(particles: GPUParticles3D) -> void:
	if particles == null or particles.process_material == null \
			or _queued_particles >= MAX_PARTICLE_WARMERS:
		return
	var material := particles.process_material
	var before := _queue.size()
	_enqueue({
		"type": "particle",
		"key": "particle:%d" % material.get_instance_id(),
		"name": "particle:%s" % _resource_label(material),
		"source": particles,
	})
	if _queue.size() > before:
		_queued_particles += 1


func _sorted_resources(resources: Array, type: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value: Variant in resources:
		var resource := value as Resource
		if resource == null:
			continue
		var name := _resource_label(resource)
		var row: Dictionary = {
			"type": type,
			"key": "%s:%d" % [type, resource.get_instance_id()],
			"name": "cache:%s" % name,
			"sort": "%s:%020d" % [name, resource.get_instance_id()],
		}
		if type == "material":
			var material := resource as Material
			if material == null:
				continue
			row["material"] = material
		elif type == "mesh":
			var mesh := resource as Mesh
			if mesh == null:
				continue
			row["mesh"] = mesh
		else:
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("sort", "")) < String(b.get("sort", "")))
	for row: Dictionary in rows:
		row.erase("sort")
	return rows


static func _resource_label(resource: Resource) -> String:
	if resource == null:
		return "null"
	if resource.resource_path != "":
		return resource.resource_path
	var prefix: String = resource.get_class()
	if resource.resource_name != "":
		prefix += ":%s" % resource.resource_name
	var standard := resource as StandardMaterial3D
	if standard != null:
		return ("%s[shade=%d transp=%d blend=%d cull=%d vc=%d tex=%d "
				+ "emit=%d shadows=%d]") % [
			prefix, standard.shading_mode, standard.transparency,
			standard.blend_mode, standard.cull_mode,
			int(standard.vertex_color_use_as_albedo),
			int(standard.albedo_texture != null), int(standard.emission_enabled),
			int(not standard.disable_receive_shadows),
		]
	var shader_material := resource as ShaderMaterial
	if shader_material != null:
		var shader_path := "null"
		if shader_material.shader != null:
			shader_path = shader_material.shader.resource_path
			if shader_path == "":
				shader_path = shader_material.shader.resource_name
		return "%s[shader=%s]" % [prefix, shader_path]
	var mesh := resource as Mesh
	if mesh != null:
		var size: Vector3 = mesh.get_aabb().size
		return "%s[surfaces=%d aabb=%.3fx%.3fx%.3f]" % [
			prefix, mesh.get_surface_count(), size.x, size.y, size.z,
		]
	return prefix


func _collect_queue(node: Node) -> void:
	if node == null or node == _anchor or _queue.size() >= MAX_INSTANCES:
		return
	var geometry := node as GeometryInstance3D
	if geometry != null:
		_enqueue_material(geometry.material_override)
		_enqueue_material(geometry.material_overlay)
	var instance := node as MeshInstance3D
	if instance != null and instance.mesh != null:
		_enqueue_mesh(instance.mesh)
		for surface: int in instance.mesh.get_surface_count():
			_enqueue_material(instance.mesh.surface_get_material(surface))
			_enqueue_material(instance.get_surface_override_material(surface))
	var multi := node as MultiMeshInstance3D
	if multi != null and multi.multimesh != null and multi.multimesh.mesh != null:
		_enqueue_mesh(multi.multimesh.mesh)
		for surface: int in multi.multimesh.mesh.get_surface_count():
			_enqueue_material(multi.multimesh.mesh.surface_get_material(surface))
	var gpu := node as GPUParticles3D
	if gpu != null:
		for pass_index: int in mini(gpu.draw_passes, 4):
			var draw_mesh := gpu.get("draw_pass_%d" % (pass_index + 1)) as Mesh
			_enqueue_mesh(draw_mesh)
			_enqueue_surface_materials(draw_mesh)
	var cpu := node as CPUParticles3D
	if cpu != null:
		_enqueue_mesh(cpu.mesh)
		_enqueue_surface_materials(cpu.mesh)
	for child: Node in node.get_children():
		_collect_queue(child)


func _collect_particle_queue(node: Node) -> void:
	if node == null or node == _anchor or _queue.size() >= MAX_INSTANCES:
		return
	if node is GPUParticles3D:
		_enqueue_particle(node as GPUParticles3D)
	for child: Node in node.get_children():
		_collect_particle_queue(child)


func _enqueue_surface_materials(mesh: Mesh) -> void:
	if mesh == null:
		return
	for surface: int in mesh.get_surface_count():
		_enqueue_material(mesh.surface_get_material(surface))


func _submit_next_item(require_placement: bool = true) -> bool:
	if _queue_cursor >= _queue.size() or _awaiting_draw:
		return false
	# _ready() can run while another node is processing. Guarding the engine
	# frame makes the one-new-resource-per-rendered-frame contract explicit even
	# if Godot schedules this node's first _process() in that same frame.
	var frame := Engine.get_process_frames()
	if frame == _last_submit_frame:
		return false
	if require_placement and not _place_anchor():
		return false
	if _anchor == null or not is_instance_valid(_anchor):
		return false
	var item: Dictionary = _queue[_queue_cursor]
	_queue_cursor += 1
	_last_submit_frame = frame
	if perf_trace_enabled:
		_trace_item_started_usec = Time.get_ticks_usec()
		_trace_item = item
		_trace_item_index = _queue_cursor
		_trace_item_submit_frame = frame
		_trace_item_submit_render_serial = _render_serial
	var before := _instances
	_spawn_queue_item(item)
	var submitted := _instances == before + 1
	_awaiting_draw = submitted
	return submitted


func _spawn_queue_item(item: Dictionary) -> void:
	match String(item.get("type", "")):
		"external":
			_spawn_external(item.get("mesh") as Mesh, item.get("material") as Material)
		"material":
			_spawn_material(item.get("material") as Material)
		"mesh":
			_spawn_mesh(item.get("mesh") as Mesh)
		"particle":
			_spawn_particle(item.get("source") as GPUParticles3D)


func _record_trace_item() -> void:
	if not perf_trace_enabled or _trace_item_started_usec <= 0:
		return
	_perf_trace_events.append({
		"submit_frame": _trace_item_submit_frame,
		"following_frame": Engine.get_process_frames(),
		"submit_render_serial": _trace_item_submit_render_serial,
		"following_render_serial": _render_serial,
		"item_index": _trace_item_index,
		"queue_size": _queue.size(),
		"key": String(_trace_item.get("key", "")),
		"type": String(_trace_item.get("type", "")),
		"name": String(_trace_item.get("name", "")),
		"ms": float(Time.get_ticks_usec() - _trace_item_started_usec) / 1000.0,
	})
	_trace_item_started_usec = 0
	_trace_item = {}
	_trace_item_submit_frame = -1
	_trace_item_submit_render_serial = -1


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
## draw call and its program bind still happen at a tiny rasterized footprint —
## that is the part the compile hangs off — while the loader hides it.
static func _fit_scale(mesh: Mesh) -> Vector3:
	var extent := mesh.get_aabb().size.length() + 2.0 * MAX_VERTEX_DISPLACEMENT
	return Vector3.ONE * (PROBE_WORLD_SIZE / maxf(extent, 0.0001))


## --- Spawning ----------------------------------------------------------------

func _spawn_material(mat: Material) -> void:
	if mat == null:
		return
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
func _spawn_mesh(mesh: Mesh) -> void:
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = _fit_scale(mesh)
	instance.material_override = VisualLibrary.rock_material(Color(1.0, 1.0, 1.0))
	_anchor.add_child(instance)
	_instances += 1


## Draws the real late-content mesh with its real material. A separate generic
## material probe cannot guarantee the same vertex-input pipeline, and a
## separate mesh upload leaves the exact material/buffer combination lazy.
func _spawn_external(mesh: Mesh, material: Material) -> void:
	if mesh == null or material == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = _fit_scale(mesh)
	instance.material_override = material
	_anchor.add_child(instance)
	_instances += 1


## Compiles a particle process shader by running one particle for one frame.
## local_coords keeps the simulation inside the anchor's transform, so the
## anchor's tiny scale bounds the motion too and nothing can drift into
## view. Chrome-only: on a native GL driver this is not worth the frame.
func _spawn_particle(source: GPUParticles3D) -> void:
	if source == null:
		return
	var mat := source.process_material
	if mat == null or _particle_warmers >= MAX_PARTICLE_WARMERS:
		return
	_particle_warmers += 1
	_instances += 1
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

## Synthetic fallback for programs whose owners do not exist at scene start.
## BootWarmup intentionally stays Canvas-only; gameplay compilation belongs to
## this scene-specific pass while SceneRouter holds its loading overlay.
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
