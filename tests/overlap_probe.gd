extends Node3D
## Scenery-vs-track intersection probe.
##
## Builds a course for real, measures the racing corridor from the ribbon's own
## floor geometry, and then tests every non-track mesh in the course against
## that corridor with exact triangle-vs-oriented-box SAT. Anything that reaches
## inside the deck edge within a racer's headroom band is printed with its
## coordinates, the guide offset it intrudes at, and how deep it goes.
##
## MUST run WITH a window: every course guards its dressing behind
## GameConfig.is_headless(), so a --headless run builds no scenery at all and
## the probe would find nothing by construction.
##
##   godot --path . res://tests/overlap_probe.tscn -- course=aurora
##   godot --path . res://tests/overlap_probe.tscn -- course=glacier above=6 below=1
##
## Args: course=<id> below=<m> above=<m> min_depth=<m> step=<m> keep_all=1

## Spatial-hash cell for corridor samples (XZ metres).
const CELL: float = 24.0
## How far a triangle's AABB is grown when asking the hash for nearby corridor
## samples: must exceed the widest half-width plus the band, or a triangle
## sitting on the deck edge could miss the sample it belongs to.
const QUERY_MARGIN: float = 40.0
## Target spacing when a confirmed-intersecting triangle is sampled to measure
## how deep the intrusion actually goes.
const DEPTH_SPACING: float = 0.2
## An intrusion whose highest point stays below this many metres over the deck
## is a surface decal lying on the ice (aurora reflection strips, moon glints,
## contact-shadow patches), not something a racer can hit. Reported separately.
const DECAL_TOP: float = 0.30

## Subtrees that are deliberate track furniture and are never offenders.
const FURNITURE_CLASSES: PackedStringArray = [
	"HazardIcicle", "HazardGeyser", "HazardSeal", "HazardSnowball",
	"HazardCrackingIce", "HazardPlatform", "HazardWindZone",
	"ItemBox", "FishPickup", "SnowballPickup", "Racer", "SnowDriftField",
]
const FURNITURE_NAME_PREFIXES: PackedStringArray = [
	"FinishLine", "Snowfall", "SnowDrifts", "ContactShadows", "EdgeMarkers",
]

var _course_id: String = "aurora"
var _below: float = 1.0
var _above: float = 6.0
var _min_depth: float = 0.05
var _step_div: int = 1
var _keep_all: bool = false
## shot=<png> arc=<m> [back=<m>] [lift=<m>]: park a racer-eye camera on the deck
## at that arc offset and save one frame instead of scanning, so a measured
## intrusion can also be looked at.
var _shot: String = ""
var _shot_arc: float = 0.0
var _shot_back: float = 22.0
var _shot_lift: float = 3.0
var _shot_guide: int = 0
## hidebig=<m>: before the shot, hide every course mesh whose world AABB is at
## least this many metres across, so a suspected giant silhouette can be proven
## to be the thing that vanishes.
var _hide_big: float = 0.0

# Flat corridor sample table (parallel arrays for speed).
var _s_guide: PackedInt32Array = PackedInt32Array()
var _s_index: PackedInt32Array = PackedInt32Array()
var _s_arc: PackedFloat32Array = PackedFloat32Array()
var _s_origin: PackedVector3Array = PackedVector3Array()
var _s_right: PackedVector3Array = PackedVector3Array()
var _s_up: PackedVector3Array = PackedVector3Array()
var _s_fwd: PackedVector3Array = PackedVector3Array()
var _s_hw_neg: PackedFloat32Array = PackedFloat32Array()
var _s_hw_pos: PackedFloat32Array = PackedFloat32Array()
var _guide_names: PackedStringArray = PackedStringArray()

var _grid: Dictionary = {}
var _half_step: float = 1.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=")
		if parts.size() != 2:
			if arg == "keep_all":
				_keep_all = true
			continue
		match parts[0]:
			"course": _course_id = parts[1]
			"below": _below = float(parts[1])
			"above": _above = float(parts[1])
			"min_depth": _min_depth = float(parts[1])
			"substep": _step_div = maxi(int(parts[1]), 1)
			"keep_all": _keep_all = int(parts[1]) != 0
			"shot": _shot = parts[1]
			"arc": _shot_arc = float(parts[1])
			"back": _shot_back = float(parts[1])
			"lift": _shot_lift = float(parts[1])
			"gi": _shot_guide = int(parts[1])
			"hidebig": _hide_big = float(parts[1])

	print("[probe] display_server=%s headless=%s" % [DisplayServer.get_name(), str(GameConfig.is_headless())])
	print("[probe] course=%s band=[deck-%.2f .. deck+%.2f] min_depth=%.2fm keep_all=%s"
		% [_course_id, _below, _above, _min_depth, str(_keep_all)])

	var info := CoursesDB.get_item(_course_id)
	var script_path := String(info.get("script", ""))
	if script_path == "":
		script_path = "res://scripts/courses/course_%s.gd" % _course_id
	var script: GDScript = load(script_path)
	if script == null:
		push_error("[probe] no course script at %s" % script_path)
		get_tree().quit(1)
		return
	var course := script.new() as Node3D
	course.add_to_group(&"course")
	add_child(course)
	await get_tree().process_frame
	await get_tree().process_frame

	if _shot != "":
		await _take_shot(course)
		get_tree().quit(0)
		return

	var t0 := Time.get_ticks_msec()
	_build_corridor(course)
	if _s_arc.is_empty():
		push_error("[probe] no corridor samples -- course built no ribbon?")
		get_tree().quit(1)
		return
	_scan(course)
	print("[probe] total %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit(0)


## --- Screenshot -------------------------------------------------------------

func _take_shot(course: Node3D) -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var ribbons: Array[Node] = []
	for child: Node in course.get_children():
		if child.has_meta("guide"):
			ribbons.append(child)
	var guide: PathGuide = (ribbons[clampi(_shot_guide, 0, ribbons.size() - 1)] as Node3D).get_meta("guide") as PathGuide
	if _hide_big > 0.0:
		var hidden := 0
		for child: Node in course.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null or mi.has_meta("guide"):
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if maxf(box.size.x, maxf(box.size.y, box.size.z)) >= _hide_big:
				mi.visible = false
				hidden += 1
		print("[probe] hid %d course meshes larger than %.0f m across" % [hidden, _hide_big])
	var xf := guide.transform_at(clampf(_shot_arc, 0.0, guide.length))
	var fwd := -xf.basis.z
	var eye := xf.origin - fwd * _shot_back + Vector3.UP * _shot_lift
	var camera := Camera3D.new()
	camera.fov = 62.0
	camera.far = 4000.0
	camera.position = eye
	add_child(camera)
	camera.look_at(xf.origin + fwd * 40.0 + Vector3.UP * 1.5, Vector3.UP)
	camera.current = true
	print("[probe] shot: guide arc=%.1f deck=(%.2f, %.2f, %.2f) eye=(%.2f, %.2f, %.2f)"
		% [_shot_arc, xf.origin.x, xf.origin.y, xf.origin.z, eye.x, eye.y, eye.z])
	for _i: int in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := _shot.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	image.save_png(_shot)
	print("[probe] saved %s" % _shot)


## --- Corridor ---------------------------------------------------------------

## Measures, per guide sample, how far the racing deck actually reaches either
## side of the centreline -- from the ribbon's own floor triangles, not from
## the authored width numbers, so the corridor is the surface that shipped.
func _build_corridor(course: Node3D) -> void:
	var ribbons: Array[Node] = []
	for child: Node in course.get_children():
		if child.has_meta("guide"):
			ribbons.append(child)
	for r_i: int in ribbons.size():
		var root := ribbons[r_i] as Node3D
		var guide: PathGuide = root.get_meta("guide") as PathGuide
		var gname := String(root.name)
		_guide_names.append(gname)
		var count := guide.points.size()
		var hw_neg := PackedFloat32Array()
		var hw_pos := PackedFloat32Array()
		hw_neg.resize(count)
		hw_pos.resize(count)

		# Frames first: the lateral of a floor vertex is measured in the frame
		# of the guide sample nearest to it.
		var origins := PackedVector3Array()
		var rights := PackedVector3Array()
		var ups := PackedVector3Array()
		var fwds := PackedVector3Array()
		origins.resize(count)
		rights.resize(count)
		ups.resize(count)
		fwds.resize(count)
		for i: int in count:
			var xf := guide.transform_at(float(i) * PathGuide.SAMPLE_SPACING)
			origins[i] = xf.origin
			rights[i] = xf.basis.x
			ups[i] = xf.basis.y
			fwds[i] = -xf.basis.z

		var floor_tris := 0
		for child: Node in root.get_children():
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if not _is_floor_mesh(mi.mesh):
				continue
			var faces := mi.mesh.get_faces()
			var xform := mi.global_transform
			floor_tris += faces.size() / 3
			for v_i: int in faces.size():
				var v: Vector3 = xform * faces[v_i]
				var idx := _nearest_index(origins, v)
				var lat := (v - origins[idx]).dot(rights[idx])
				if lat >= 0.0:
					hw_pos[idx] = maxf(hw_pos[idx], lat)
				else:
					hw_neg[idx] = maxf(hw_neg[idx], -lat)

		# A floor row lands every TrackBuilder.SAMPLE (3 m) while guide samples
		# are every 2 m, and on a tight corner the left and right vertex of one
		# row can bind to different samples -- which leaves some samples with a
		# measured edge on one side only. Widen each side by the neighbouring
		# samples' measurement, then fill any remaining hole from the nearest
		# measured sample, so the corridor is never falsely narrow (or falsely
		# one-sided) at a single index.
		hw_pos = _repair_edges(hw_pos)
		hw_neg = _repair_edges(hw_neg)

		var measured := 0
		var min_hw := INF
		var max_hw := 0.0
		for i: int in count:
			if hw_pos[i] <= 0.0 and hw_neg[i] <= 0.0:
				continue
			measured += 1
			min_hw = minf(min_hw, minf(hw_pos[i], hw_neg[i]))
			max_hw = maxf(max_hw, maxf(hw_pos[i], hw_neg[i]))
			_s_guide.append(r_i)
			_s_index.append(i)
			_s_arc.append(float(i) * PathGuide.SAMPLE_SPACING)
			_s_origin.append(origins[i])
			_s_right.append(rights[i])
			_s_up.append(ups[i])
			_s_fwd.append(fwds[i])
			_s_hw_neg.append(hw_neg[i])
			_s_hw_pos.append(hw_pos[i])
		print("[probe] guide '%s': length=%.1fm samples=%d measured=%d floor_tris=%d half-width %.2f..%.2f m"
			% [gname, guide.length, count, measured, floor_tris, min_hw, max_hw])

	_half_step = PathGuide.SAMPLE_SPACING * 0.5
	for s_i: int in _s_arc.size():
		var o := _s_origin[s_i]
		var key := Vector2i(int(floor(o.x / CELL)), int(floor(o.z / CELL)))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		var bucket: PackedInt32Array = _grid[key]
		bucket.append(s_i)
		_grid[key] = bucket
	print("[probe] corridor: %d samples, %d hash cells" % [_s_arc.size(), _grid.size()])


## Track floor runs are the only ribbon meshes that write UV2 (the ice shader's
## frosted-edge flag). Walls write UV only, the skirt writes vertex colors only.
func _is_floor_mesh(mesh: Mesh) -> bool:
	if mesh.get_surface_count() == 0:
		return false
	var arrays := mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_TEX_UV2:
		return false
	var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
	return uv2 != null and (uv2 as PackedVector2Array).size() > 0


## Window-max over +/-1 sample, then nearest-measured fill for any index still
## at zero. Both steps only ever widen, never narrow, the corridor.
func _repair_edges(src: PackedFloat32Array) -> PackedFloat32Array:
	var n := src.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i: int in n:
		var v := src[i]
		if i > 0:
			v = maxf(v, src[i - 1])
		if i < n - 1:
			v = maxf(v, src[i + 1])
		out[i] = v
	for i: int in n:
		if out[i] > 0.0:
			continue
		var back := -1.0
		var fwd := -1.0
		for j: int in range(i - 1, -1, -1):
			if out[j] > 0.0:
				back = out[j]
				break
		for j: int in range(i + 1, n):
			if out[j] > 0.0:
				fwd = out[j]
				break
		out[i] = maxf(back, fwd)
		if out[i] < 0.0:
			out[i] = 0.0
	return out


func _nearest_index(origins: PackedVector3Array, v: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i: int in origins.size():
		var d := origins[i].distance_squared_to(v)
		if d < best_d:
			best_d = d
			best = i
	return best


## --- Scan -------------------------------------------------------------------

func _scan(course: Node3D) -> void:
	var candidates: Array[Node] = []
	var excluded: Array[String] = []
	_collect(course, candidates, excluded)
	print("[probe] exclusions applied (%d subtrees skipped):" % excluded.size())
	var tally: Dictionary = {}
	for e: String in excluded:
		tally[e] = int(tally.get(e, 0)) + 1
	for k: String in tally.keys():
		print("    %-42s x%d" % [k, int(tally[k])])
	print("[probe] testing %d geometry nodes" % candidates.size())

	var reports: Array[Dictionary] = []
	var decals: Array[Dictionary] = []
	var vfx: Array[Dictionary] = []
	var aabb_only: Array[Dictionary] = []
	for node: Node in candidates:
		var res := _test_node(node as GeometryInstance3D)
		if res.is_empty():
			continue
		if float(res["depth"]) < _min_depth:
			if bool(res["aabb_hit"]):
				aabb_only.append(res)
			continue
		if bool(res["vfx"]):
			vfx.append(res)
		elif float(res["node_h_hi"]) < DECAL_TOP:
			decals.append(res)
		else:
			reports.append(res)

	var by_depth := func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) > float(b["depth"])
	reports.sort_custom(by_depth)
	decals.sort_custom(by_depth)
	vfx.sort_custom(by_depth)

	print("")
	print("========== %s: %d OFFENDERS (triangle-verified, rise above deck+%.2fm) =========="
		% [_course_id.to_upper(), reports.size(), DECAL_TOP])
	for r: Dictionary in reports:
		_print_report(r)
	print("")
	print("---------- %s: %d flat deck decals (whole intrusion under deck+%.2fm; reflections/glints/shadow patches) ----------"
		% [_course_id.to_upper(), decals.size(), DECAL_TOP])
	for r: Dictionary in decals:
		print("  %s  mesh=%s tris=%d aabb_c=(%.1f, %.1f, %.1f) depth=%.2fm  h=%.3f..%.3f above deck  arc %.0f..%.0f"
			% [String(r["path"]), String(r["mesh_class"]), int(r["tris"]),
				(r["aabb_c"] as Vector3).x, (r["aabb_c"] as Vector3).y, (r["aabb_c"] as Vector3).z,
				float(r["depth"]), float(r["node_h_lo"]), float(r["node_h_hi"]),
				float(r["arc_lo"]), float(r["arc_hi"])])
	print("")
	print("---------- %s: %d translucent / additive / billboard VFX (fog wisps, glints, curtains) ----------"
		% [_course_id.to_upper(), vfx.size()])
	for r: Dictionary in vfx:
		print("  %s  mesh=%s depth=%.2fm  h=%.2f..%.2f above deck  arc %.0f..%.0f  [%s]"
			% [String(r["path"]), String(r["mesh_class"]), float(r["depth"]),
				float(r["node_h_lo"]), float(r["node_h_hi"]),
				float(r["arc_lo"]), float(r["arc_hi"]), String(r["material"])])
	print("")
	print("---------- %s: %d AABB-only hits (hollow shapes; no triangle inside the corridor) ----------"
		% [_course_id.to_upper(), aabb_only.size()])
	for r: Dictionary in aabb_only:
		print("  %s  mesh=%s aabb_c=(%.1f, %.1f, %.1f) size=(%.1f, %.1f, %.1f)"
			% [String(r["path"]), String(r["mesh_class"]),
				(r["aabb_c"] as Vector3).x, (r["aabb_c"] as Vector3).y, (r["aabb_c"] as Vector3).z,
				(r["aabb_s"] as Vector3).x, (r["aabb_s"] as Vector3).y, (r["aabb_s"] as Vector3).z])


func _collect(node: Node, out: Array[Node], excluded: Array[String]) -> void:
	for child: Node in node.get_children():
		if not _keep_all:
			var why := _exclusion_reason(child)
			if why != "":
				excluded.append(why)
				continue
		if child is MeshInstance3D or child is MultiMeshInstance3D:
			out.append(child)
		_collect(child, out, excluded)


func _exclusion_reason(node: Node) -> String:
	if node.has_meta("guide"):
		return "track ribbon subtree (deck/walls/skirt/markers)"
	if node is Area3D:
		return "Area3D trigger subtree (boost pad / pickup / finish / wind)"
	if node is RigidBody3D or node is CharacterBody3D:
		return "physics body subtree"
	var s := node.get_script() as Script
	if s != null:
		var gname := s.get_global_name()
		if FURNITURE_CLASSES.has(gname):
			return "hazard/pickup class: %s" % gname
	var n := String(node.name)
	for pre: String in FURNITURE_NAME_PREFIXES:
		if n.begins_with(pre):
			return "named furniture: %s*" % pre
	return ""


func _test_node(node: GeometryInstance3D) -> Dictionary:
	var mesh: Mesh = null
	var instance_xforms: Array[Transform3D] = []
	var mi := node as MeshInstance3D
	if mi != null:
		mesh = mi.mesh
		instance_xforms.append(mi.global_transform)
	else:
		var mm := node as MultiMeshInstance3D
		if mm == null or mm.multimesh == null:
			return {}
		mesh = mm.multimesh.mesh
		for i: int in mm.multimesh.instance_count:
			instance_xforms.append(mm.global_transform * mm.multimesh.get_instance_transform(i))
	if mesh == null:
		return {}

	var world_aabb: AABB = node.global_transform * node.get_aabb()
	var faces := mesh.get_faces()
	if faces.is_empty():
		return {}

	var best_depth := -INF
	var best: Dictionary = {}
	var touched: Dictionary = {}
	var aabb_hit := false
	var node_h_lo := INF
	var node_h_hi := -INF

	var hit_instances: Dictionary = {}
	var best_instance := -1
	for inst_i: int in instance_xforms.size():
		var xform := instance_xforms[inst_i]
		var t_i := 0
		while t_i + 2 < faces.size():
			var a: Vector3 = xform * faces[t_i]
			var b: Vector3 = xform * faces[t_i + 1]
			var c: Vector3 = xform * faces[t_i + 2]
			t_i += 3
			var lo := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
			for s_i: int in _nearby_samples(lo, hi):
				if not _tri_vs_corridor(a, b, c, s_i):
					continue
				aabb_hit = true
				touched[s_i] = true
				hit_instances[inst_i] = true
				var d := _measure_depth(a, b, c, s_i)
				if d.has("h_lo") and float(d["h_lo"]) < INF:
					node_h_lo = minf(node_h_lo, float(d["h_lo"]))
					node_h_hi = maxf(node_h_hi, float(d["h_hi"]))
				if float(d["depth"]) > best_depth:
					best_depth = float(d["depth"])
					best = d
					best["sample"] = s_i
					best_instance = inst_i

	if touched.is_empty():
		return {}

	var arcs: Array[float] = []
	var guides: Dictionary = {}
	for s_i: Variant in touched.keys():
		arcs.append(_s_arc[int(s_i)])
		guides[_guide_names[_s_guide[int(s_i)]]] = true
	arcs.sort()

	var s_best := int(best.get("sample", 0))
	return {
		"path": String(node.get_path()),
		"name": String(node.name),
		"class": node.get_class(),
		"mesh_class": mesh.get_class(),
		"tris": faces.size() / 3,
		"instances": instance_xforms.size(),
		"aabb_c": world_aabb.get_center(),
		"aabb_s": world_aabb.size,
		"aabb_hit": aabb_hit,
		"depth": maxf(best_depth, 0.0),
		"lateral": float(best.get("lateral", 0.0)),
		"h_lo": float(best.get("h_lo", 0.0)),
		"h_hi": float(best.get("h_hi", 0.0)),
		"point": best.get("point", Vector3.ZERO),
		"guide": _guide_names[_s_guide[s_best]],
		"arc": _s_arc[s_best],
		"idx": _s_index[s_best],
		"hw_neg": _s_hw_neg[s_best],
		"hw_pos": _s_hw_pos[s_best],
		"deck": _s_origin[s_best],
		"hit_instances": hit_instances.size(),
		"best_instance": best_instance,
		"best_instance_origin": instance_xforms[maxi(best_instance, 0)].origin,
		# For a MultiMesh the node AABB is the union of every instance, which
		# says nothing about the size of the one piece that is in the way.
		"best_instance_size": (instance_xforms[maxi(best_instance, 0)] * mesh.get_aabb()).size,
		"material": _describe_material(node, mesh),
		"vfx": _is_translucent_vfx(node, mesh),
		"node_h_lo": node_h_lo,
		"node_h_hi": node_h_hi,
		"samples": touched.size(),
		"arc_lo": arcs[0],
		"arc_hi": arcs[arcs.size() - 1],
		"guides": ", ".join(PackedStringArray(guides.keys())),
		"scale": (node as Node3D).global_transform.basis.get_scale(),
	}


func _effective_material(node: GeometryInstance3D, mesh: Mesh) -> Material:
	if node.material_override != null:
		return node.material_override
	var mi := node as MeshInstance3D
	if mi != null and mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
		return mi.get_surface_override_material(0)
	if mesh != null and mesh.get_surface_count() > 0:
		return mesh.surface_get_material(0)
	return null


func _describe_material(node: GeometryInstance3D, mesh: Mesh) -> String:
	var mat := _effective_material(node, mesh)
	if mat == null:
		return "none"
	var std := mat as BaseMaterial3D
	if std == null:
		return mat.get_class()
	return "%s alpha=%.2f transparency=%d blend=%d shading=%d billboard=%d" % [
		std.get_class(), std.albedo_color.a, int(std.transparency),
		int(std.blend_mode), int(std.shading_mode), int(std.billboard_mode)]


## Semi-transparent, additive or camera-facing dressing draws as atmosphere, not
## as an object a racer can be inside of; it is reported apart from solid
## scenery so a fog wisp is never confused with a mountain.
func _is_translucent_vfx(node: GeometryInstance3D, mesh: Mesh) -> bool:
	var std := _effective_material(node, mesh) as BaseMaterial3D
	if std == null:
		return false
	if std.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		return true
	if std.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
		return true
	if std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and std.albedo_color.a < 0.6:
		return true
	return false


func _print_report(r: Dictionary) -> void:
	var c: Vector3 = r["aabb_c"]
	var s: Vector3 = r["aabb_s"]
	var p: Vector3 = r["point"]
	var d: Vector3 = r["deck"]
	var sc: Vector3 = r["scale"]
	print("")
	print("  OFFENDER  %s" % String(r["path"]))
	var bo: Vector3 = r["best_instance_origin"]
	print("    class=%s mesh=%s tris=%d instances=%d (%d intruding, worst #%d at (%.2f, %.2f, %.2f)) scale=(%.2f, %.2f, %.2f)"
		% [String(r["class"]), String(r["mesh_class"]), int(r["tris"]), int(r["instances"]),
			int(r["hit_instances"]), int(r["best_instance"]), bo.x, bo.y, bo.z, sc.x, sc.y, sc.z])
	print("    material: %s" % String(r["material"]))
	var bs: Vector3 = r["best_instance_size"]
	print("    world AABB centre=(%.2f, %.2f, %.2f)  size=(%.2f, %.2f, %.2f)  [offending piece alone: %.2f x %.2f x %.2f m]"
		% [c.x, c.y, c.z, s.x, s.y, s.z, bs.x, bs.y, bs.z])
	print("    worst point=(%.2f, %.2f, %.2f) on guide '%s' arc=%.1fm (sample %d)"
		% [p.x, p.y, p.z, String(r["guide"]), float(r["arc"]), int(r["idx"])])
	print("    deck centre there=(%.2f, %.2f, %.2f)  half-width -%.2f / +%.2f m"
		% [d.x, d.y, d.z, float(r["hw_neg"]), float(r["hw_pos"])])
	print("    lateral=%.2f m  =>  reaches %.2f m INBOARD of the deck edge, at %.2f..%.2f m above deck"
		% [float(r["lateral"]), float(r["depth"]), float(r["h_lo"]), float(r["h_hi"])])
	print("    node-wide intruding geometry occupies %.2f..%.2f m above the deck"
		% [float(r["node_h_lo"]), float(r["node_h_hi"])])
	print("    intrudes over %d corridor samples, arc %.1f..%.1f m (span %.1f m) on guide(s) [%s]"
		% [int(r["samples"]), float(r["arc_lo"]), float(r["arc_hi"]),
			float(r["arc_hi"]) - float(r["arc_lo"]), String(r["guides"])])


## --- Geometry ---------------------------------------------------------------

func _nearby_samples(lo: Vector3, hi: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := int(floor((lo.x - QUERY_MARGIN) / CELL))
	var x1 := int(floor((hi.x + QUERY_MARGIN) / CELL))
	var z0 := int(floor((lo.z - QUERY_MARGIN) / CELL))
	var z1 := int(floor((hi.z + QUERY_MARGIN) / CELL))
	# A world-spanning triangle (ground plane, sky dome) would sweep the entire
	# hash; that is correct but slow, so it is allowed -- the corridor is only a
	# few thousand samples.
	for cx: int in range(x0, x1 + 1):
		for cz: int in range(z0, z1 + 1):
			var key := Vector2i(cx, cz)
			if _grid.has(key):
				out.append_array(_grid[key] as PackedInt32Array)
	return out


## Exact triangle vs oriented corridor box, by separating axis theorem.
func _tri_vs_corridor(a: Vector3, b: Vector3, c: Vector3, s_i: int) -> bool:
	var o := _s_origin[s_i]
	var r := _s_right[s_i]
	var u := _s_up[s_i]
	var f := _s_fwd[s_i]
	var hwn := _s_hw_neg[s_i]
	var hwp := _s_hw_pos[s_i]
	# Box in corridor-local space: x = lateral, y = height over the deck,
	# z = along the guide.
	var centre := Vector3((hwp - hwn) * 0.5, (_above - _below) * 0.5, 0.0)
	var ext := Vector3((hwp + hwn) * 0.5, (_above + _below) * 0.5, _half_step)
	var v0 := _to_local(a, o, r, u, f) - centre
	var v1 := _to_local(b, o, r, u, f) - centre
	var v2 := _to_local(c, o, r, u, f) - centre

	# 3 box face normals.
	for axis: int in 3:
		var mn := minf(v0[axis], minf(v1[axis], v2[axis]))
		var mx := maxf(v0[axis], maxf(v1[axis], v2[axis]))
		if mn > ext[axis] or mx < -ext[axis]:
			return false
	# Triangle normal.
	var n := (v1 - v0).cross(v2 - v0)
	if n.length_squared() > 1e-12:
		var d := n.dot(v0)
		var rad := ext.x * absf(n.x) + ext.y * absf(n.y) + ext.z * absf(n.z)
		if absf(d) > rad:
			return false
	# 9 edge x box-axis cross products.
	var edges: Array[Vector3] = [v1 - v0, v2 - v1, v0 - v2]
	var verts: Array[Vector3] = [v0, v1, v2]
	for e: Vector3 in edges:
		for axis: int in 3:
			var ax := Vector3.ZERO
			ax[axis] = 1.0
			var sep := e.cross(ax)
			if sep.length_squared() < 1e-12:
				continue
			var mn := INF
			var mx := -INF
			for v: Vector3 in verts:
				var pv := sep.dot(v)
				mn = minf(mn, pv)
				mx = maxf(mx, pv)
			var rad2 := ext.x * absf(sep.x) + ext.y * absf(sep.y) + ext.z * absf(sep.z)
			if mn > rad2 or mx < -rad2:
				return false
	return true


## Fine barycentric sampling of a confirmed-intersecting triangle: returns how
## far inboard of the deck edge it actually reaches and the height band it
## occupies there.
func _measure_depth(a: Vector3, b: Vector3, c: Vector3, s_i: int) -> Dictionary:
	var o := _s_origin[s_i]
	var r := _s_right[s_i]
	var u := _s_up[s_i]
	var f := _s_fwd[s_i]
	var hwn := _s_hw_neg[s_i]
	var hwp := _s_hw_pos[s_i]
	var longest := maxf((b - a).length(), maxf((c - b).length(), (a - c).length()))
	var n := clampi(int(ceil(longest / DEPTH_SPACING)), 1, 48)
	var best := -INF
	var best_lat := 0.0
	var best_point := a
	var h_lo := INF
	var h_hi := -INF
	for i: int in n + 1:
		for j: int in n + 1 - i:
			var w0 := float(i) / float(n)
			var w1 := float(j) / float(n)
			var w2 := 1.0 - w0 - w1
			var p := a * w0 + b * w1 + c * w2
			var loc := _to_local(p, o, r, u, f)
			if loc.z < -_half_step or loc.z > _half_step:
				continue
			if loc.y < -_below or loc.y > _above:
				continue
			var edge := hwp if loc.x >= 0.0 else hwn
			var depth := edge - absf(loc.x)
			if depth < 0.0:
				continue
			h_lo = minf(h_lo, loc.y)
			h_hi = maxf(h_hi, loc.y)
			if depth > best:
				best = depth
				best_lat = loc.x
				best_point = p
	if best == -INF:
		# SAT says the triangle clips the box but no barycentric sample landed
		# inside it (a sliver crossing a corner). Report a positive but unknown
		# depth so it is not silently dropped.
		return {"depth": 0.01, "lateral": 0.0, "h_lo": 0.0, "h_hi": 0.0, "point": (a + b + c) / 3.0}
	return {"depth": best, "lateral": best_lat, "h_lo": h_lo, "h_hi": h_hi, "point": best_point}


func _to_local(p: Vector3, o: Vector3, r: Vector3, u: Vector3, f: Vector3) -> Vector3:
	var d := p - o
	return Vector3(d.dot(r), d.dot(u), d.dot(f))
