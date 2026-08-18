class_name SunShafts
extends Node3D
## Crepuscular rays around the course's key light.
##
## The renderer is gl_compatibility (WebGL2), which has no volumetrics and no
## screen-space depth reads, so real light shafts are off the table. This is the
## trick every stylised racer uses instead: a fan of soft additive blades pinned
## a long way out along the direction of the sun, facing the camera. Because it
## is real geometry sitting 420 m away, the world occludes it for free — peaks
## and edge walls cut the rays exactly where they should, which is the whole
## reason it reads as light in air rather than as a lens flare stuck to the
## screen.
##
## Two things keep it from looking like a decal:
##   * it only appears when the camera is actually looking toward the sun, and
##     ramps with that angle, so it behaves like glare rather than dressing;
##   * every blade breathes on its own phase, and the whole fan turns very
##     slowly, so the rays drift the way sun through moving air does.
##
## Courses opt in through build_environment ("shafts": true) and colour it with
## their own light; night courses use it for moonlight, Sapphire Hollow for the
## meltwater shaft coming down the crevasse.

## Metres out along the sun direction. Far enough that the mid-distance skyline
## bands (300-1200 m) can occlude it, close enough to stay inside the far plane.
const ANCHOR_DISTANCE: float = 420.0
## Fan radius as a fraction of ANCHOR_DISTANCE.
const SPREAD: float = 0.40
## Cosine window between the camera's forward vector and the direction to the
## sun. Below the first value the fan is invisible; above the second it is at
## full strength.
## Tuned hard: at a wide window the sun sits off-screen while its longest
## blades still cross the frame, and a ray with no visible origin reads as a
## scratch on the lens rather than as light. The fan only lights up once the sun
## itself is near frame.
const FACE_MIN: float = 0.45
const FACE_MAX: float = 0.92

var _to_sun: Vector3 = Vector3(0.35, 0.72, 0.55)
var _strength: float = 1.0
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _spin: float = 0.0


## `light` is the course key light; the fan sits along the direction the light
## comes FROM. `color` is normally the light's own colour, lightened — a shaft
## is the sun seen through haze, not the sun's albedo.
func configure(light: DirectionalLight3D, color: Color, strength: float = 1.0,
		blades: int = 13, seed_value: int = 7) -> void:
	_to_sun = light.global_transform.basis.z.normalized()
	_strength = strength
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "ShaftFan"
	_mesh_instance.mesh = _build_fan(blades, rng)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	_material.albedo_color = color
	# Depth TEST stays on (that is what lets the mountains cut the rays) while
	# depth WRITE is off, so the blades never occlude each other or the sky.
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)


## Alpha profile along a blade, root to tip. Light scattered out of a beam
## thins with distance travelled, so a ray is brightest just off the disc and
## dies out well before its geometric end — a wedge that keeps its brightness
## to the tip is what makes a fan read as a printed starburst.
const BLADE_PROFILE: PackedFloat32Array = [0.0, 0.15, 0.42, 0.72, 1.0]
const BLADE_ALPHA: PackedFloat32Array = [0.55, 1.0, 0.62, 0.24, 0.0]
## Half-width at those same stations, as a fraction of the blade's own width:
## rays flare open away from the disc rather than staying parallel.
const BLADE_WIDTH: PackedFloat32Array = [0.22, 0.55, 0.85, 1.0, 1.0]


## Each blade is a soft-edged strip, not a triangle: a bright centre line with
## zero-alpha edges either side, tapering in both brightness and width along its
## length. Blades also curve slightly, so no two are the same shape.
##
## A wide, low inner glow sits underneath to seat the fan on the sun disc the
## sky material draws, filling the gaps between blade roots.
func _build_fan(blades: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in blades:
		# Angles are jittered off the even spacing: a perfectly regular fan
		# reads as a starburst sticker.
		var base_angle := TAU * float(i) / float(blades) + rng.randf_range(-0.20, 0.20)
		# Wide wedges, not lines: a blade thinner than a few pixels aliases into
		# a crawling white hair, which is the classic tell of a fake god ray.
		var half_w := rng.randf_range(0.045, 0.135)
		var length := rng.randf_range(0.45, 1.0)
		# A slow angular drift along the blade. Real rays are not radii of a
		# perfect circle; a few degrees of curve is the whole difference.
		var curve := rng.randf_range(-0.11, 0.11)
		# Long blades are dimmer: the eye reads a long faint ray as far-
		# travelling light and a short bright one as near glare.
		var peak := rng.randf_range(0.30, 0.72) * (1.0 - length * 0.42)
		var stations: Array[Dictionary] = []
		for s: int in BLADE_PROFILE.size():
			var t := BLADE_PROFILE[s]
			var angle := base_angle + curve * t * t
			var radius := 0.03 + (length - 0.03) * t
			var dir := Vector3(cos(angle), sin(angle), 0.0)
			var perp := Vector3(-dir.y, dir.x, 0.0)
			stations.append({
				"centre": dir * radius,
				"edge": perp * (half_w * BLADE_WIDTH[s] * radius),
				"alpha": BLADE_ALPHA[s] * peak,
			})
		for s: int in stations.size() - 1:
			var a: Dictionary = stations[s]
			var b: Dictionary = stations[s + 1]
			var ca: Color = Color(1.0, 1.0, 1.0, float(a["alpha"]))
			var cb: Color = Color(1.0, 1.0, 1.0, float(b["alpha"]))
			var clear := Color(1.0, 1.0, 1.0, 0.0)
			for side: float in [1.0, -1.0]:
				var a_edge: Vector3 = a["centre"] + (a["edge"] as Vector3) * side
				var b_edge: Vector3 = b["centre"] + (b["edge"] as Vector3) * side
				st.set_color(ca)
				st.add_vertex(a["centre"])
				st.set_color(cb)
				st.add_vertex(b["centre"])
				st.set_color(clear)
				st.add_vertex(b_edge)
				st.set_color(ca)
				st.add_vertex(a["centre"])
				st.set_color(clear)
				st.add_vertex(b_edge)
				st.set_color(clear)
				st.add_vertex(a_edge)
	# Inner glow: two concentric soft discs — a small hot core and a wide faint
	# halo, so the fan sits in atmosphere instead of starting abruptly.
	for ring: Array in [[0.16, 0.42], [0.46, 0.13]]:
		var radius := float(ring[0])
		var alpha := float(ring[1])
		var segments := 28
		for i: int in segments:
			var a0 := TAU * float(i) / float(segments)
			var a1 := TAU * float(i + 1) / float(segments)
			st.set_color(Color(1.0, 1.0, 1.0, alpha))
			st.add_vertex(Vector3.ZERO)
			st.set_color(Color(1.0, 1.0, 1.0, 0.0))
			st.add_vertex(Vector3(cos(a0), sin(a0), 0.0) * radius)
			st.set_color(Color(1.0, 1.0, 1.0, 0.0))
			st.add_vertex(Vector3(cos(a1), sin(a1), 0.0) * radius)
	st.generate_normals()
	return st.commit()


func _process(delta: float) -> void:
	if _material == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_mesh_instance.visible = false
		return
	var camera_pos := camera.global_position
	global_position = camera_pos + _to_sun * ANCHOR_DISTANCE
	# Face the camera, then roll very slowly: air moves, and a fan locked to one
	# roll angle reads as a printed star the moment the camera turns.
	_spin += delta * 0.035
	look_at(camera_pos, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, _spin)
	scale = Vector3.ONE * (ANCHOR_DISTANCE * SPREAD)
	# Glare window: rays exist only when the sun is in or near frame.
	var facing := -camera.global_transform.basis.z.dot(_to_sun)
	var window := smoothstep(FACE_MIN, FACE_MAX, facing)
	_mesh_instance.visible = window > 0.002
	# Slow overall breathing on top of the per-blade alpha baked into the mesh.
	var breathe := 0.86 + 0.14 * sin(Time.get_ticks_msec() * 0.00035)
	_material.albedo_color.a = window * _strength * breathe
