class_name EndlessManager
extends RaceManager
## Endless Expedition: same racing core, but a blizzard storm front chases
## the field. Score = distance + fish + near misses + rivals outlasted.
## The run ends when the storm catches the player (or the course somehow
## runs out, which grants a completion bonus).

const STORM_START_GAP: float = 90.0
const STORM_BASE_SPEED: float = 9.0
const STORM_ACCEL: float = 0.045  # storm speed grows over time

var hud: RaceHUD = null
var storm_offset: float = -STORM_START_GAP
var near_misses: int = 0
var _eliminated: Dictionary = {}
var _storm_visual: Node3D = null
var _near_miss_cooldown: float = 0.0
var _ended: bool = false


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not started or _ended:
		return
	var storm_speed := STORM_BASE_SPEED + race_time * STORM_ACCEL
	storm_offset += storm_speed * delta
	_near_miss_cooldown = maxf(0.0, _near_miss_cooldown - delta)

	if player != null and is_instance_valid(player):
		_check_near_miss()
		_update_storm_visual()
		if hud != null:
			hud.set_endless_status(current_score(), player.progress, storm_gap())
		if player.progress < storm_offset:
			_end_run()
		elif player.progress > course.finish_offset - 30.0:
			near_misses += 4  # completion bonus folded into score
			_end_run()

	for racer: Racer in racers:
		if racer.is_player or _eliminated.has(racer.racer_key):
			continue
		if racer.progress < storm_offset - 10.0:
			_eliminated[racer.racer_key] = true
			racer.visible = false
			racer.set_physics_process(false)


func storm_gap() -> float:
	if player == null:
		return 0.0
	return maxf(player.progress - storm_offset, 0.0)


func current_score() -> int:
	if player == null:
		return 0
	var rivals_outlasted := _eliminated.size()
	return int(player.progress) + player.fish_count * 15 + near_misses * 25 + rivals_outlasted * 100


func _check_near_miss() -> void:
	if _near_miss_cooldown > 0.0 or player.is_stunned_or_recovering():
		return
	for node: Node in get_tree().get_nodes_in_group(&"hazards"):
		if node is Node3D:
			var distance := (node as Node3D).global_position.distance_to(player.global_position)
			if distance < 3.2 and distance > 1.2:
				near_misses += 1
				_near_miss_cooldown = 2.0
				if hud != null:
					hud.show_message("Near Miss! +25")
				return


func _update_storm_visual() -> void:
	if GameConfig.is_headless():
		return
	if _storm_visual == null:
		_storm_visual = Node3D.new()
		var wall := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(80.0, 40.0, 6.0)
		wall.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.82, 0.92, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wall.material_override = mat
		_storm_visual.add_child(wall)
		var particles := GPUParticles3D.new()
		var pmat := ParticleProcessMaterial.new()
		pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pmat.emission_box_extents = Vector3(40.0, 18.0, 3.0)
		pmat.direction = Vector3(0, 0, -1)
		pmat.initial_velocity_min = 6.0
		pmat.initial_velocity_max = 12.0
		pmat.gravity = Vector3.ZERO
		pmat.scale_min = 0.2
		pmat.scale_max = 0.6
		pmat.color = Color(0.9, 0.94, 1.0, 0.6)
		particles.process_material = pmat
		var puff := SphereMesh.new()
		puff.radius = 0.4
		puff.height = 0.8
		puff.radial_segments = 6
		puff.rings = 4
		var draw_mat := StandardMaterial3D.new()
		draw_mat.albedo_color = Color(0.92, 0.95, 1.0, 0.5)
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material = draw_mat
		particles.draw_pass_1 = puff
		particles.amount = 120
		particles.lifetime = 2.0
		_storm_visual.add_child(particles)
		course.add_child(_storm_visual)
	var clamped := clampf(storm_offset, 0.0, course.main_guide.length - 1.0)
	var xform := course.main_guide.transform_at(clamped)
	_storm_visual.global_transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 10.0)


func _end_run() -> void:
	if _ended:
		return
	_ended = true
	AudioManager.play_sfx("sfx_finish")
	Game.finish_endless(current_score(), player.progress, player.fish_count)


## Endless never resolves via the finish line.
func _on_finish_crossed(_racer: Racer) -> void:
	pass


func _complete_race() -> void:
	pass
