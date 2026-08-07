class_name SnowDriftField
extends Area3D
## The soft snow piled beside the track, made real.
##
## Snowbanks and drifts were dressing: a racer that ran wide slid through a
## metre-high wind drift at full speed with no cost at all, which made the
## whole shoulder free real estate and quietly removed the reason to hold a
## racing line. This gives that dressing a physical presence -- run into a
## drift and you plough.
##
## One Area3D per course holds every drift volume as a separate box shape.
## Godot reports body_entered once per body regardless of how many shapes it
## touches, so overlapping drifts cannot double up, and one node keeps the
## broadphase cost proportional to the shape count rather than the node count.
##
## The effect is not a bespoke drag system: a racer inside reports DEEP_SNOW as
## its surface, so ploughing inherits the acceleration, top speed, grip and
## slide behaviour already tuned in SurfacesDB, plus the deep-snow spray and
## audio. One place to tune, one feel.

## Drift boxes are inset from the visual footprint. The mesh's outer ring is a
## soft feathered skirt a few centimetres high; triggering there would make the
## shoulder feel sticky well before the player sees a reason.
const FOOTPRINT_INSET: float = 0.82
## Entering faster than this throws a plume and thuds, so the cost is announced
## rather than merely felt.
const PLOUGH_FEEDBACK_SPEED: float = 8.0

var _shape_count: int = 0


func _ready() -> void:
	# A detector, not a detectable: nothing in the game needs to find drifts.
	collision_layer = 0
	collision_mask = GameConfig.LAYER_RACERS
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## BUILD TIME ONLY. Registers one drift, given the same transform handed to the
## multimesh that draws it. `mesh_radius` / `mesh_height` describe the unit
## drift mesh's extents so the box matches whatever is actually drawn.
func add_drift(xform: Transform3D, mesh_radius: float = 1.0, mesh_height: float = 0.75) -> void:
	var scale := xform.basis.get_scale()
	var half_x := mesh_radius * scale.x * FOOTPRINT_INSET
	var half_z := mesh_radius * scale.z * FOOTPRINT_INSET
	var height := mesh_height * scale.y
	if half_x <= 0.05 or half_z <= 0.05 or height <= 0.05:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(half_x * 2.0, height, half_z * 2.0)
	shape.shape = box
	# The transform's origin sits at the drift's base (dressing is seated on
	# the ground), so the box centre is half its height above that.
	shape.transform = Transform3D(
		xform.basis.orthonormalized(), xform.origin + Vector3.UP * height * 0.5)
	add_child(shape)
	_shape_count += 1


## True once at least one drift has been registered. Courses use this to skip
## adding an empty field to the tree.
func has_drifts() -> bool:
	return _shape_count > 0


func _on_body_entered(body: Node3D) -> void:
	var racer := body as Racer
	if racer == null:
		return
	racer.enter_snow_drift()
	if racer.current_speed < PLOUGH_FEEDBACK_SPEED:
		return
	AudioManager.play_sfx_3d("sfx_land", racer.global_position, 0.72, -9.0)
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_land_puff(racer.global_position)


func _on_body_exited(body: Node3D) -> void:
	var racer := body as Racer
	if racer != null:
		racer.exit_snow_drift()
