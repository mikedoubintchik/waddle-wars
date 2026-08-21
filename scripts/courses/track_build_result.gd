class_name TrackBuildResult
extends RefCounted
## Semantic output of TrackBuilder. Keeps gameplay geometry stable while
## authored visuals migrate independently from collision and guide data.

var root: Node3D = null
var guide: PathGuide = null
## Legacy ribbons still share one root. New authored builders may provide
## dedicated children without changing CourseBase or gameplay callers.
var visual_root: Node3D = null
var collision_root: Node3D = null
var surface_runs: Array[Dictionary] = []
var edge_left: PackedVector3Array = PackedVector3Array()
var edge_right: PackedVector3Array = PackedVector3Array()
var uses_split_roots: bool = false


static func from_track_root(track_root: Node3D) -> TrackBuildResult:
	var result := TrackBuildResult.new()
	result.root = track_root
	if track_root == null:
		return result
	result.guide = track_root.get_meta("guide", null) as PathGuide
	result.visual_root = track_root.get_node_or_null("VisualRoot") as Node3D
	result.collision_root = track_root.get_node_or_null("CollisionRoot") as Node3D
	result.uses_split_roots = result.visual_root != null and result.collision_root != null
	if result.visual_root == null:
		result.visual_root = track_root
	if result.collision_root == null:
		result.collision_root = track_root
	var runs: Variant = track_root.get_meta("surface_runs", [])
	if runs is Array:
		result.surface_runs = (runs as Array).duplicate(true)
	var left: Variant = track_root.get_meta("edge_left", PackedVector3Array())
	var right: Variant = track_root.get_meta("edge_right", PackedVector3Array())
	if left is PackedVector3Array:
		result.edge_left = left
	if right is PackedVector3Array:
		result.edge_right = right
	return result


func is_valid() -> bool:
	return root != null and is_instance_valid(root) and guide != null


func attach_to(parent: Node) -> void:
	if parent != null and root != null and root.get_parent() == null:
		parent.add_child(root)


func edge_samples(side: int = 0) -> PackedVector3Array:
	return edge_left if side <= 0 else edge_right


func surface_at_offset(offset: float) -> int:
	for run: Dictionary in surface_runs:
		if offset >= float(run.get("offset_start", 0.0)) \
			and offset <= float(run.get("offset_end", 0.0)):
			return int(run.get("surface", SurfacesDB.Surface.PACKED_SNOW))
	return SurfacesDB.Surface.PACKED_SNOW


func apply_visual_profile(profile: CourseVisualProfile) -> void:
	# Presentation systems can observe profile from either result or root while
	# legacy procedural materials remain active. Authored visual roots consume
	# it during their own scene setup; collision/guide nodes never do.
	if root != null:
		root.set_meta("visual_profile", profile)
