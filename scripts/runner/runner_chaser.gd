class_name RunnerChaser
extends Node3D
## The avalanche behind you in Waddle Run.
##
## Every endless runner needs a reason the run cannot be paused-in-place, and a
## visible one beats an abstract timer: the wall is on screen in the rear-view
## of every jump, it lunges when you take a hit, and it eats you when you take
## one too many. It is pure presentation plus a single scalar — the gap — which
## the run's rules own; this node never decides the player's fate, it only
## shows where the fate currently stands.

signal caught

## Metres behind the player. Starts at the base gap and is pulled in by hits.
var gap: float = RunnerConfig.CHASER_BASE_GAP

var _puffs: MultiMeshInstance3D = null
var _face: MeshInstance3D = null
var _caught: bool = false
var _overrunning: bool = false
var _overrun_speed: float = 0.0
var _time: float = 0.0


func setup() -> void:
	if GameConfig.is_headless():
		return
	# Park the wall where it belongs BEFORE the first tick. tick() only runs
	# once the countdown finishes, so a node left at its default position sat
	# at the world origin — which is exactly where the player and the camera
	# start. The mode therefore opened on a wall of white snow filling the
	# screen, with the countdown drawn over it, and cleared only when the run
	# began. On the web build, where those frames last much longer, it was the
	# first thing anyone saw of Waddle Run.
	position = Vector3(0.0, 0.0, RunnerConfig.CHASER_BASE_GAP)
	# A dark, cold slab as the body of the wall, so the silhouette reads even
	# against a white course; the billowing puffs ride in front of it.
	_face = MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(RunnerConfig.DECK_HALF_WIDTH * 2.6, 14.0, 2.0)
	_face.mesh = slab
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.62, 0.70, 0.86)
	slab_mat.roughness = 0.95
	slab_mat.metallic = 0.0
	_face.material_override = slab_mat
	_face.position = Vector3(0.0, 5.0, 0.0)
	_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_face)

	# One MultiMesh of soft puffs for the whole front: an avalanche is a
	# silhouette plus churn, and churn is cheap when it is one draw call.
	var mesh := QuadMesh.new()
	mesh.size = Vector2(7.0, 7.0)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var count := 34
	multi.instance_count = count
	for i: int in count:
		var t := float(i) / float(count - 1)
		var pos := Vector3(
			lerpf(-RunnerConfig.DECK_HALF_WIDTH * 1.5, RunnerConfig.DECK_HALF_WIDTH * 1.5, t)
				+ rng.randf_range(-1.6, 1.6),
			rng.randf_range(0.6, 9.5),
			rng.randf_range(-2.2, 1.4))
		var scale_factor := rng.randf_range(0.7, 1.7)
		multi.set_instance_transform(i, Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * scale_factor), pos))
	_puffs = MultiMeshInstance3D.new()
	_puffs.multimesh = multi
	_puffs.material_override = VisualLibrary.billboard_puff_material(
		Color(0.93, 0.96, 1.0, 0.85), 64, 0.8, true)
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puffs)


## `player_distance` is how far the player has run; `pressure` is 0..1, how
## hard the wall is currently pushing (the run raises it per hit).
func tick(delta: float, player_distance: float, pressure: float) -> void:
	if _overrunning:
		return
	_time += delta
	# The gap recovers toward its base whenever the player is running clean,
	# so a single mistake is survivable and three in quick succession are not.
	var target := RunnerConfig.CHASER_BASE_GAP - pressure * RunnerConfig.CHASER_GAP_PER_HIT
	gap = move_toward(gap, target, RunnerConfig.CHASER_RECOVER * delta)
	global_position = Vector3(0.0, 0.0, -player_distance + gap)
	# Breathing scale: the wall is never still, and a static mesh behind the
	# player is the fastest way to make a chase read as scenery.
	if _puffs != null:
		var pulse := 1.0 + sin(_time * 2.3) * 0.04
		_puffs.scale = Vector3(pulse, 1.0 + sin(_time * 1.7) * 0.05, pulse)
	if gap <= 0.05 and not _caught:
		_caught = true
		caught.emit()


## Death sequence: the wall stops being a distant threat and rolls straight
## over the camera. A run that simply halts reads as the game breaking — the
## most common complaint about this mode was "it just stops" — and the fix is
## not a better panel, it is showing the player the thing that ate them.
func overrun() -> void:
	_overrunning = true


func _process(delta: float) -> void:
	if not _overrunning:
		return
	# Accelerate through the player rather than easing to a stop, so the frame
	# fills with snow and the results panel lands on top of that rather than on
	# a frozen world.
	_overrun_speed = minf(_overrun_speed + delta * 34.0, 26.0)
	global_position.z -= _overrun_speed * delta
	if _puffs != null:
		_puffs.scale = _puffs.scale.lerp(Vector3(1.5, 1.6, 1.5), clampf(delta * 2.4, 0.0, 1.0))


func reset() -> void:
	_caught = false
	_overrunning = false
	_overrun_speed = 0.0
	gap = RunnerConfig.CHASER_BASE_GAP
