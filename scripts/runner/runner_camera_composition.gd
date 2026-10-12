class_name RunnerCameraComposition
extends RefCounted
## Perspective fit for an upright authored silhouette, not a gameplay collider.
## Two screen-space rays meet the sole and crown of a vertical segment. Using
## the imported height removes the old procedural-character size calibration.

## Approved HUD/jump references place the horizon at 41% on desktop and
## 37.5% on portrait, with grounded soles at 73%/71%. A longer lens preserves
## that framing from above the tunnel roof without looking down on the crown.
## These are presentation targets; collider and gameplay distances stay put.
static func reference_fov(speed_ratio: float) -> float:
	return lerpf(54.0, 62.0, clampf(speed_ratio, 0.0, 1.0))


static func reference_fit(hero_height: float, vertical_fov: float, portrait: bool) -> Vector3:
	var horizon := 0.375 if portrait else 0.41
	var sole := 0.71 if portrait else 0.73
	var fraction := 0.115 if portrait else 0.125
	var pitch := rad_to_deg(atan(2.0 * tan(deg_to_rad(vertical_fov * 0.5))
		* (0.5 - horizon)))
	return with_clearance(hero_height, vertical_fov, fraction, sole, pitch)

static func solve(hero_height: float, vertical_fov: float,
		frame_fraction: float, sole_fraction: float, pitch_degrees: float) -> Vector2:
	var tangent := tan(deg_to_rad(vertical_fov * 0.5))
	var pitch := deg_to_rad(pitch_degrees)
	var sole_angle := pitch + atan(2.0 * tangent * (sole_fraction - 0.5))
	var crown_angle := pitch + atan(2.0 * tangent
		* (sole_fraction - frame_fraction - 0.5))
	var distance := hero_height / maxf(tan(sole_angle) - tan(crown_angle), 0.001)
	return Vector2(distance, distance * tan(sole_angle))


static func with_clearance(hero_height: float, vertical_fov: float,
		frame_fraction: float, sole_fraction: float, pitch_degrees: float) -> Vector3:
	var fit := solve(hero_height, vertical_fov, frame_fraction, sole_fraction, pitch_degrees)
	if fit.y < 2.95:
		# Small species cannot satisfy the reference-size target and tunnel
		# clearance simultaneously. Preserve clearance and sole placement; their
		# smaller projected size remains an explicit art/composition limitation.
		fit.y = 2.95
		var screen_angle := atan(2.0 * tan(deg_to_rad(vertical_fov * 0.5))
			* (sole_fraction - 0.5))
		pitch_degrees = rad_to_deg(atan2(fit.y, fit.x) - screen_angle)
	return Vector3(fit.x, fit.y, pitch_degrees)


static func authored_height(visual: PenguinVisual) -> float:
	if visual == null:
		return 0.0
	var backend: Node3D = null
	if visual.is_reviewed_runner_visible():
		backend = visual.get_node_or_null("ReviewedRunnerPenguin") as Node3D
	elif visual.is_authored_backend_active():
		backend = visual.get_node_or_null("AuthoredHeroPenguin") as Node3D
	if backend == null:
		return 0.0
	var minimum := INF
	var maximum := -INF
	# Called once after setup, never in the frame loop. Only the chosen authored
	# subtree is eligible; hidden procedural meshes cannot inflate this measure.
	for raw: Node in backend.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var relative := visual.global_transform.affine_inverse() * instance.global_transform
		var measured_mesh := instance.mesh
		if measured_mesh is ArrayMesh and measured_mesh.get_blend_shape_count() > 0:
			# Species proportions are already configured. This one loading-time
			# snapshot includes them; it must never move into the per-frame loop.
			measured_mesh = instance.bake_mesh_from_current_blend_shape_mix()
		var bounds := measured_mesh.get_aabb()
		for corner: int in 8:
			var point := relative * bounds.get_endpoint(corner)
			minimum = minf(minimum, point.y)
			maximum = maxf(maximum, point.y)
	return 0.0 if is_inf(minimum) else maximum - minimum
