class_name ShaderWarmup
extends Node
## One-shot first-sight shader compile pass, run behind the loading overlay.
##
## Cold uploads and pipeline links can stall both native Compatibility and
## browser renderers. This bounded queue submits one new probe per drawn frame
## behind the loader, retaining earlier probes through its final draw. It is
## a preparation aid, not proof of complete pipeline coverage: individual links
## can still stall, queues can reach their caps, and exact skin/instancing and
## lighting variants require real-scene validation. Runner stages its original
## geometry first through InitialVisualWarmup to avoid a bulk cold world draw.
##
## What it walks, in order of value:
##   * exact registered mesh/material pairs for streamed content,
##   * locally visible GeometryInstance3D branches in the scene (ribbons, hazards,
##     racers, particle draw passes) — this catches TrackBuilder and
##     PenguinVisual materials the library never sees,
##   * the VisualLibrary registry and helper meshes, whose GPU resources are
##     uploaded lazily,
##   * on web, synthetic BaseMaterial3D feature combinations plus the
##     particle process materials, which cover effects that do not exist yet
##     at race start (snowball splats, item-box shards, impact bursts).
##
## Material templates span a few pixels at 1080p and sit 0.2 m from the
## camera behind a fully opaque overlay, carries no collision, and is gone as
## soon as the queue's final item has drawn — it cannot be seen and cannot be hit.
## Headless runs skip the whole thing, so the sims are untouched.
##
## The warmed programs survive the pass: VisualLibrary holds its materials in
## static dictionaries and the synthetic probes are held in a static array
## here to retain resource ownership. Driver cache persistence needs profiling.

## Metres in front of the camera, clamped against its near plane below.
const ANCHOR_DISTANCE: float = 0.2
## Target world size for a warm-up instance, in metres, at ANCHOR_DISTANCE.
## One 1080p pixel spans roughly 0.00025 m there under the chase camera's
## 68 deg FOV. Material probes have this actual span, rather than scaling an
## already microscopic helper triangle below a pixel.
const PROBE_WORLD_SIZE: float = 0.0015
## Retained probes occupy separate camera-facing cells. Four spans leave room
## for a material probe's model-space displacement (one span in either
## direction) without covering its neighbour's depth samples.
const PROBE_GRID_COLUMNS: int = 16
const PROBE_GRID_SPACING: float = PROBE_WORLD_SIZE * 4.0
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
## Hard ceiling on spawned instances. Current scenes can reach this ceiling;
## do not interpret queue completion as exhaustive resource coverage.
const MAX_INSTANCES: int = 128
## Keep exact queue coverage, but avoid 128 serial draw frames on native
## Compatibility. Web and opt-in per-item traces retain one probe per draw.
const NATIVE_SUBMISSIONS_PER_DRAW: int = 4
## Ceiling on throwaway particle emitters (web pass only).
const MAX_PARTICLE_WARMERS: int = 12
## Scene systems may register exact mesh/material pairs for content which is
## deliberately absent at scene start (for example the runner's first tunnel).
## Keep this bounded so a broken streamer cannot turn the loading overlay into
## an unbounded pre-render pass.
const MAX_EXTERNAL_PROBES: int = 32
## Reserved for the isolated instanced/light probe. Its temporary point light
## must never reach gameplay geometry (which uses the ordinary render layers).
const INSTANCED_PROBE_LAYER: int = 1 << 19
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
## Full-attribute material probes. Ordinary materials use a unit triangle and
## instance scale; billboards which discard scale need the final size baked
## into their vertices. Retain both buffers across scene changes.
static var _material_probe_mesh: ArrayMesh = null
static var _billboard_probe_mesh: ArrayMesh = null
## Exact late-content pairs retained for the session. Unlike the synthetic
## flag probes, these warm both the real vertex-buffer layout and its material
## pipeline in one draw.
static var _external_probes: Array[Dictionary] = []
static var _external_probe_keys: Dictionary = {}
## Opt-in scene namespaces isolate late-content budgets without clearing the
## session's legacy registry or relying on cached-resource re-registration.
## Each namespace retains the same bounded MAX_EXTERNAL_PROBES allocation.
static var _scoped_external_probes: Dictionary = {}
static var _scoped_external_probe_keys: Dictionary = {}
static var _external_probe_overflows: Dictionary = {}
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
## An external pair already submits its exact mesh buffer. A generic upload
## probe for that same resource cannot upload any additional vertex data.
## Materials, skinning, instances and distinct external pairs remain separate.
var _queued_external_mesh_ids: Dictionary = {}
var _omitted_mesh_keys: Dictionary = {}
var _duplicate_mesh_uploads: int = 0
## Optional complete scene-owned late inventory. Empty retains legacy global
## cache behavior; a malformed inventory also falls back atomically.
var _inventory: Dictionary = {}
var _inventory_scope: String = "global"
var _external_scope: StringName = &""
var _external_registry_status: Dictionary = {}
var _originally_visible_geometry: Dictionary = {}
var _queue_cursor: int = 0
var _completed_queue_cursor: int = 0
var _last_submit_frame: int = -1
var _recovery_suspended: bool = false
var _awaiting_draw: bool = false
var _render_serial: int = 0
var _trace_item_started_usec: int = 0
var _trace_item: Dictionary = {}
var _trace_item_index: int = 0
var _trace_item_submit_frame: int = -1
var _trace_item_submit_render_serial: int = -1


## Starts a warm-up pass over `world`. Call after content is assembled; the
## queue is collected once, so deferred content needs explicit registration.
## Returns the node, or
## null when the pass is skipped (headless, or no world).
static func warm(world: Node, inventory: Dictionary = {},
		external_scope: StringName = &"",
		originally_visible_geometry: Dictionary = {}) -> ShaderWarmup:
	if world == null or GameConfig.is_headless():
		return null
	var warmup := ShaderWarmup.new()
	warmup.name = "ShaderWarmup"
	warmup._world = world
	warmup._inventory = inventory
	warmup._external_scope = external_scope
	warmup._originally_visible_geometry = originally_visible_geometry.duplicate()
	world.add_child(warmup)
	return warmup


## Submits one exact instanced pair with a point light behind the scene loader.
## The ordinary queue decomposes MultiMeshes into non-instanced material/mesh
## probes; it cannot cover this lighting variant. Keep this bounded pass outside
## that queue so a full external registry cannot evict an authored asset pair.
## Currently used for the runner's ground-facing contact-shadow plane only.
static func warm_instanced_pair(world: Node3D, mesh: Mesh, material: Material) -> void:
	if GameConfig.is_headless() or not is_instance_valid(world) \
			or mesh == null or material == null or not world.is_inside_tree():
		return
	var viewport := world.get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return
	var anchor := _create_instanced_pair_probe(mesh, material)
	anchor.position = Vector3(0.0, 0.0, -maxf(ANCHOR_DISTANCE, camera.near * 2.0))
	# Default gameplay cameras include this otherwise unused layer. Respect a
	# narrower mask too, restoring only our temporary bit rather than replacing
	# any unrelated mask changes made while waiting for the draw.
	var layer_was_visible := (camera.cull_mask & INSTANCED_PROBE_LAYER) != 0
	if not layer_was_visible:
		camera.cull_mask |= INSTANCED_PROBE_LAYER
	camera.add_child(anchor)
	await RenderingServer.frame_post_draw
	# Immediate release is deliberate: no probe, light or MultiMesh may survive
	# this method's return and reach the countdown. Camera deletion also owns
	# the anchor, so interrupted scene changes cannot leave an orphan behind.
	if is_instance_valid(anchor):
		anchor.free()
	if is_instance_valid(camera) and not layer_was_visible:
		camera.cull_mask &= ~INSTANCED_PROBE_LAYER


## Detached constructor keeps geometry, light isolation and ownership testable
## without pretending that headless checks prove a driver compiled a program.
static func _create_instanced_pair_probe(mesh: Mesh, material: Material) -> Node3D:
	if mesh == null or material == null:
		return null
	var anchor := Node3D.new()
	anchor.name = "InstancedShaderWarmupAnchor"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, _instanced_pair_transform(mesh))
	var instance := MultiMeshInstance3D.new()
	instance.name = "InstancedPair"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.layers = INSTANCED_PROBE_LAYER
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(instance)
	var light := OmniLight3D.new()
	light.name = "InstancedPairOmni"
	light.light_cull_mask = INSTANCED_PROBE_LAYER
	light.omni_range = 0.05
	light.position = Vector3(0.0, 0.0, 0.01)
	light.shadow_enabled = false
	anchor.add_child(light)
	return anchor


static func _instanced_pair_transform(mesh: Mesh) -> Transform3D:
	# Preserve the actual contact plane's vertex layout and rotate its +Y
	# normal to camera-facing +Z. Center off-origin pivots before shrinking;
	# fitting the largest dimension keeps this real quad several pixels wide.
	var bounds := mesh.get_aabb()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var basis := Basis(Vector3.RIGHT, PI * 0.5).scaled(
			Vector3.ONE * (PROBE_WORLD_SIZE / maxf(extent, 0.0001)))
	return Transform3D(basis, -(basis * bounds.get_center()))


## Registers content which a scene will stream only after its opening frame.
## Call during scene construction, before warm(). Registration is idempotent;
## static resource caches may safely call this on every retry.
## Multi-surface content supplies null material plus one non-null material per
## surface. This preserves the real buffer and material routing in one instance
## without spending one queue slot per surface or using a blanket override.
static func register_external_probe(mesh: Mesh, material: Material,
		surface_materials: Array[Material] = [], scope: StringName = &"") -> void:
	var key := _external_probe_key(mesh, material, surface_materials)
	if key.is_empty():
		return
	if scope != &"" and not _scoped_external_probes.has(scope):
		var scoped_probes: Array[Dictionary] = []
		_scoped_external_probes[scope] = scoped_probes
		_scoped_external_probe_keys[scope] = {}
	var probes: Array[Dictionary] = _external_probes if scope == &"" \
			else _scoped_external_probes[scope]
	var keys: Dictionary = _external_probe_keys if scope == &"" \
			else _scoped_external_probe_keys[scope]
	# Check identity first: a retry of a full, complete registry is not overflow.
	if keys.has(key):
		return
	if probes.size() >= MAX_EXTERNAL_PROBES:
		var omitted: Dictionary = _external_probe_overflows.get(scope, {})
		if not omitted.has(key):
			omitted[key] = true
			_external_probe_overflows[scope] = omitted
			push_warning("ShaderWarmup external scope '%s' limit %d reached; omitted %s" \
					% [String(scope) if scope != &"" else "legacy", MAX_EXTERNAL_PROBES, key])
		return
	keys[key] = true
	probes.append({"mesh": mesh, "material": material, "key": key,
			"surface_materials": surface_materials.duplicate()})


static func external_probe_count(scope: StringName = &"") -> int:
	return _external_probes.size() if scope == &"" \
			else (_scoped_external_probes.get(scope, []) as Array).size()


## Registry diagnostics, not GPU compilation coverage. A full registry with
## zero drops is valid; unknown namespaces and any omitted unique pair are not.
static func external_scope_status(scope: StringName = &"") -> Dictionary:
	var known := scope == &"" or _scoped_external_probes.has(scope)
	var omitted: Dictionary = _external_probe_overflows.get(scope, {})
	return {"scope": String(scope) if scope != &"" else "legacy", "known": known,
			"registered": external_probe_count(scope), "limit": MAX_EXTERNAL_PROBES,
			"dropped": omitted.size(), "registry_complete": known and omitted.is_empty()}


static func has_external_probe(mesh: Mesh, material: Material,
		surface_materials: Array[Material] = [], scope: StringName = &"") -> bool:
	var key := _external_probe_key(mesh, material, surface_materials)
	var keys: Dictionary = _external_probe_keys if scope == &"" \
			else _scoped_external_probe_keys.get(scope, {})
	return not key.is_empty() and keys.has(key)


static func _external_probe_key(mesh: Mesh, material: Material,
		surface_materials: Array[Material]) -> String:
	if mesh == null:
		return ""
	if surface_materials.is_empty():
		return "%d:%d" % [mesh.get_instance_id(), material.get_instance_id()] \
				if material != null else ""
	# A global material override would hide the listed surfaces. Refuse that
	# ambiguous combination and incomplete lists instead of claiming coverage.
	if material != null or surface_materials.size() != mesh.get_surface_count():
		return ""
	var ids := PackedStringArray()
	for surface_material: Material in surface_materials:
		if surface_material == null:
			return ""
		ids.append(str(surface_material.get_instance_id()))
	return "%d:surfaces:%s" % [mesh.get_instance_id(), ",".join(ids)]


static func clear_perf_trace() -> void:
	_perf_trace_events.clear()


static func drain_perf_trace_events() -> Array[Dictionary]:
	var events := _perf_trace_events.duplicate(true)
	_perf_trace_events.clear()
	return events


func _ready() -> void:
	# Run ahead of gameplay scripts so submission always precedes the frame's
	# draw, and keep ticking through ordinary pauses. Terminal loading recovery
	# instead freezes the queue until its world is replaced.
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Safari/mobile WebGL also uploads and links lazily. Browser identity must
	# not leave its absent-at-start effects to first compile during gameplay.
	_extended = use_extended_warmup()
	_anchor = Node3D.new()
	_anchor.name = "ShaderWarmupAnchor"
	add_child(_anchor)
	_build_queue()
	if OS.has_feature("android") and OS.is_debug_build():
		print("[shader_warmup_qa] start items=%d scope=%s" % [
			_queue.size(), _inventory_scope])
	if not RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	SceneRouter.loading_recovery_started.connect(suspend_for_recovery)
	if SceneRouter.is_loading_recovery_active():
		suspend_for_recovery()
	else:
		_submit_next_item()


func suspend_for_recovery() -> void:
	if _recovery_suspended:
		return
	_recovery_suspended = true
	set_process(false)
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	# Retain already-submitted probes/anchor. No new resource or completion can
	# be submitted; the normal scene-exit cleanup releases these nodes.


func _process(_delta: float) -> void:
	# A resource remains the only new submission until renderer confirms its
	# frame completed. Process ticks without a draw (minimized/background window)
	# cannot advance this queue or stack multiple probes into a later frame.
	if _recovery_suspended or _awaiting_draw:
		return
	if _queue_cursor < _queue.size():
		_submit_next_item()
		return
	# Final item reached frame_post_draw before _awaiting_draw was cleared.
	queue_free()


func _on_frame_post_draw() -> void:
	if _recovery_suspended:
		return
	_render_serial += 1
	if not _awaiting_draw:
		return
	_record_trace_item()
	_completed_queue_cursor = _queue_cursor
	_awaiting_draw = false


func _exit_tree() -> void:
	if OS.has_feature("android") and OS.is_debug_build():
		print("[shader_warmup_qa] exit cursor=%d/%d suspended=%s" % [
			_queue_cursor, _queue.size(), str(_recovery_suspended)])
	if is_instance_valid(SceneRouter) \
			and SceneRouter.loading_recovery_started.is_connected(suspend_for_recovery):
		SceneRouter.loading_recovery_started.disconnect(suspend_for_recovery)
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
	_queued_external_mesh_ids.clear()
	_omitted_mesh_keys.clear()
	_duplicate_mesh_uploads = 0
	_queue_cursor = 0
	_completed_queue_cursor = 0
	_queued_particles = 0
	_last_submit_frame = -1
	_awaiting_draw = false
	var owned := not _inventory.is_empty() and _inventory_is_valid()
	_inventory_scope = "owned" if owned else "global"
	_external_registry_status = external_scope_status(_external_scope)
	var external: Array = _inventory["external_probes"] if owned else _external_probes
	if not owned and _external_scope != &"":
		external = _scoped_external_probes.get(_external_scope, [])
		if not bool(_external_registry_status["known"]):
			push_warning("ShaderWarmup unknown external scope '%s'; no late probes selected" \
					% String(_external_scope))
	# 1. Exact streamed mesh/material pairs. A late buffer+pipeline combination
	# matters more than any generic cache entry and cannot be truncated by cap.
	for probe: Dictionary in external:
		var mesh := probe.get("mesh") as Mesh
		var material := probe.get("material") as Material
		var surface_materials: Array[Material] = []
		surface_materials.assign(probe.get("surface_materials", []))
		var material_label := _resource_label(material)
		if not surface_materials.is_empty():
			var labels := PackedStringArray()
			for surface_material: Material in surface_materials:
				labels.append(_resource_label(surface_material))
			material_label = "surfaces[%s]" % "; ".join(labels)
		_enqueue({
			"type": "external",
			"key": "external:%s" % _external_probe_key(mesh, material, surface_materials),
			"name": "%s + %s" % [_resource_label(mesh), material_label],
			"mesh": mesh,
			"material": material,
			"surface_materials": surface_materials,
		})
	# 2. Live scene resources in node/surface order. This catches imported hero,
	# track-builder and HUD-adjacent 3D material instances absent from caches.
	_collect_queue(_world)
	# 3. Shared cached materials and buffers in stable semantic-name order.
	var materials: Array = _inventory["materials"] if owned else VisualLibrary.cached_materials()
	var meshes: Array = _inventory["meshes"] if owned else VisualLibrary.cached_meshes()
	for row: Dictionary in _sorted_resources(materials, "material"):
		_enqueue(row)
	for row: Dictionary in _sorted_resources(meshes, "mesh"):
		_enqueue(row)
	# 4. Web absent-at-start feature and particle combinations.
	if _extended:
		for material: Material in probe_materials():
			_enqueue_material(material, "synthetic")
		_collect_particle_queue(_world)


## Browser-independent policy; deterministic override is for contract tests.
static func use_extended_warmup(web_override: int = -1) -> bool:
	return OS.has_feature("web") if web_override < 0 else web_override == 1


## Supplying an owned inventory promises every late mesh/material is listed.
## Live scene resources, synthetic features and particles are always collected
## as before. Validate before selecting any part, so an invalid sibling cannot
## silently narrow coverage to the remaining valid entries.
func _inventory_is_valid() -> bool:
	for key: String in ["external_probes", "materials", "meshes"]:
		if not _inventory.has(key) or not _inventory[key] is Array:
			return false
	for value: Variant in _inventory["materials"]:
		if not value is Material:
			return false
	for value: Variant in _inventory["meshes"]:
		if not value is Mesh:
			return false
	for value: Variant in _inventory["external_probes"]:
		if not value is Dictionary:
			return false
		var probe: Dictionary = value
		if not probe.get("surface_materials", []) is Array:
			return false
		var surfaces: Array[Material] = []
		for surface: Variant in probe.get("surface_materials", []):
			if not surface is Material:
				return false
			surfaces.append(surface)
		if _external_probe_key(probe.get("mesh") as Mesh,
				probe.get("material") as Material, surfaces).is_empty():
			return false
	return true


## Counts describe queue construction only, not shader compilation or timing.
func inventory_summary() -> Dictionary:
	var counts := {"external": 0, "material": 0, "mesh": 0, "particle": 0}
	for item: Dictionary in _queue:
		var kind := String(item.get("type", ""))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return {"scope": _inventory_scope, "items": _queue.size(),
			"by_type": counts, "duplicate_mesh_uploads_omitted": _duplicate_mesh_uploads,
			"external_registry": _external_registry_status.duplicate()}


func _enqueue(item: Dictionary) -> void:
	var key := String(item.get("key", ""))
	if item.get("type") == "mesh":
		var mesh := item.get("mesh") as Mesh
		if mesh != null and _queued_external_mesh_ids.has(mesh.get_instance_id()):
			if not _omitted_mesh_keys.has(key):
				_omitted_mesh_keys[key] = true
				_duplicate_mesh_uploads += 1
			return
	if _queue.size() >= MAX_INSTANCES:
		return
	if key == "" or _queue_keys.has(key):
		return
	_queue_keys[key] = true
	_queue.append(item)
	if item.get("type") == "external":
		var mesh := item.get("mesh") as Mesh
		if mesh != null:
			_queued_external_mesh_ids[mesh.get_instance_id()] = true


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
	var spatial := node as Node3D
	if spatial != null and not spatial.visible \
			and not (node is GeometryInstance3D \
			and _originally_visible_geometry.has(node.get_instance_id())):
		# Authored penguins retain a hidden procedural fallback subtree. Its
		# unused resources must not consume the bounded live-scene queue. Use
		# local visibility so unparented test fixtures behave like live trees;
		# future content belongs in the separate external-probe registrations.
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
	var spatial := node as Node3D
	if spatial != null and not spatial.visible:
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
	if _recovery_suspended or _queue_cursor >= _queue.size() or _awaiting_draw:
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
	_last_submit_frame = frame
	var batch_limit := NATIVE_SUBMISSIONS_PER_DRAW if OS.has_feature("mobile") \
			and not OS.has_feature("web") and not perf_trace_enabled else 1
	var submitted := false
	for _batch_index: int in batch_limit:
		if _queue_cursor >= _queue.size():
			break
		var item: Dictionary = _queue[_queue_cursor]
		_queue_cursor += 1
		if perf_trace_enabled:
			_trace_item_started_usec = Time.get_ticks_usec()
			_trace_item = item
			_trace_item_index = _queue_cursor
			_trace_item_submit_frame = frame
			_trace_item_submit_render_serial = _render_serial
		var before := _instances
		_spawn_queue_item(item)
		submitted = submitted or _instances == before + 1
	_awaiting_draw = submitted
	return submitted


func _spawn_queue_item(item: Dictionary) -> void:
	match String(item.get("type", "")):
		"external":
			var surface_materials: Array[Material] = []
			surface_materials.assign(item.get("surface_materials", []))
			_spawn_external(item.get("mesh") as Mesh, item.get("material") as Material,
					surface_materials)
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
		# frame_post_draw also fires for Canvas-only frames. An anchor being in
		# the tree does not prove any camera submitted its 3D draw.
		return false
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


static func _probe_cell(index: int) -> Vector3:
	var rows := ceili(float(MAX_INSTANCES) / float(PROBE_GRID_COLUMNS))
	var column := index % PROBE_GRID_COLUMNS
	var row := floori(float(index) / float(PROBE_GRID_COLUMNS))
	return Vector3(
		(float(column) - float(PROBE_GRID_COLUMNS - 1) * 0.5) * PROBE_GRID_SPACING,
		(float(row) - float(rows - 1) * 0.5) * PROBE_GRID_SPACING,
		0.0)


func _place_mesh_probe(instance: MeshInstance3D) -> void:
	# Authored pivots are often at a foot or track entrance. Centre their actual
	# bounds in the cell so a valid off-origin mesh cannot cover another probe.
	instance.position = _probe_cell(_instances) \
			- instance.mesh.get_aabb().get_center() * instance.scale


static func _material_mesh(unscaled_billboard: bool) -> ArrayMesh:
	var cached := _billboard_probe_mesh if unscaled_billboard else _material_probe_mesh
	if cached != null:
		return cached
	var side := PROBE_WORLD_SIZE if unscaled_billboard else 1.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Godot's front face is clockwise. Camera sits on +Z looking down -Z;
	# normals alone do not prevent the opposite winding from being back-culled.
	var corners: Array[Vector3] = [
		Vector3(-0.5, -0.5, 0.0), Vector3(0.0, 0.5, 0.0), Vector3(0.5, -0.5, 0.0),
	]
	var uvs: Array[Vector2] = [Vector2.ZERO, Vector2(0.5, 1.0), Vector2.RIGHT]
	for index: int in corners.size():
		st.set_color(Color.WHITE)
		st.set_normal(Vector3.BACK)
		st.set_tangent(Plane(Vector3.RIGHT, 1.0))
		st.set_uv(uvs[index])
		st.add_vertex(corners[index] * side)
	var mesh := st.commit()
	if unscaled_billboard:
		_billboard_probe_mesh = mesh
	else:
		_material_probe_mesh = mesh
	return mesh


## --- Spawning ----------------------------------------------------------------

func _spawn_material(mat: Material) -> void:
	if mat == null:
		return
	var instance := MeshInstance3D.new()
	var standard := mat as BaseMaterial3D
	var unscaled_billboard := standard != null \
			and standard.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED \
			and not standard.billboard_keep_scale
	instance.mesh = _material_mesh(unscaled_billboard)
	instance.scale = Vector3.ONE * (1.0 if unscaled_billboard else PROBE_WORLD_SIZE)
	# A shader may displace the unit triangle by up to one model-space metre.
	# The resulting maximum span is three cells' base spans (4.5 mm), still
	# smaller than the cell spacing. Keep culling bounds honest as well.
	if mat is ShaderMaterial:
		instance.custom_aabb = instance.mesh.get_aabb().grow(MAX_VERTEX_DISPLACEMENT)
	instance.material_override = mat
	_place_mesh_probe(instance)
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
	_place_mesh_probe(instance)
	_anchor.add_child(instance)
	_instances += 1


## Draws the real late-content mesh with its real material. A separate generic
## material probe cannot guarantee the same vertex-input pipeline, and a
## separate mesh upload leaves the exact material/buffer combination lazy.
func _spawn_external(mesh: Mesh, material: Material,
		surface_materials: Array[Material] = []) -> void:
	if _external_probe_key(mesh, material, surface_materials).is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.scale = _fit_scale(mesh)
	if surface_materials.is_empty():
		instance.material_override = material
	else:
		for surface: int in surface_materials.size():
			instance.set_surface_override_material(surface, surface_materials[surface])
	_place_mesh_probe(instance)
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
	var cell := _probe_cell(_instances)
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
	particles.position = cell
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
