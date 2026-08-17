class_name SnowTrail
extends MultiMeshInstance3D
## Carved track behind a racer: the groove a moving body actually leaves in
## snow. One MultiMesh of soft ground streaks per racer, laid as a ring buffer
## while the racer touches a snow surface and fading as it ages.
##
## This exists because a snow world that does not respond to the racers reads
## as painted scenery no matter how good its shader is: the single loudest
## realism cue in any snow game is the line you carve. A decal ribbon is the
## whole effect -- no physics, no texture writes, no per-frame mesh rebuilds:
##   * dropping a segment writes ONE instance transform + color,
##   * aging is a color update across live instances, run only on drop ticks,
##   * the buffer wraps and the oldest streak is simply overwritten.
## gl_compatibility-safe: MultiMesh with per-instance color, one soft-edged
## streak texture, alpha blend, no shader of its own.

## Streaks kept per racer. At one streak every DROP_SPACING metres this holds
## roughly the last 55 m of travel, which from the chase camera is the whole
## visible history of the racer's line.
const SEGMENTS: int = 96
## Metres of travel between streaks. Short enough to overlap into a continuous
## groove at the streak lengths below.
const DROP_SPACING: float = 0.58
## Seconds before a streak has fully faded. Long enough that a following racer
## sees the leader's line ahead of them, which is a genuine racing read.
const LIFETIME: float = 9.0
## Base tint of compressed snow: darker and bluer than the surface it cuts
## into, the way pressed crystals read against fresh crust.
const TINT: Color = Color(0.42, 0.52, 0.70)

var _last_drop: Vector3 = Vector3.INF
var _head: int = 0
var _live: int = 0
## Spawn time (seconds) per slot, for aging on drop ticks.
var _ages: PackedFloat64Array = PackedFloat64Array()

static var _streak_texture: GradientTexture2D = null
static var _streak_material: StandardMaterial3D = null
static var _streak_mesh: QuadMesh = null


func setup() -> void:
	_ages.resize(SEGMENTS)
	_ages.fill(-1.0)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _get_streak_mesh()
	multimesh.instance_count = SEGMENTS
	# Park every instance invisible until it is dropped.
	for i: int in SEGMENTS:
		multimesh.set_instance_color(i, Color(1, 1, 1, 0))
	material_override = _get_streak_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The trail lives in world space, parented to the racer: it must STAY
	# WHERE IT WAS CARVED while the racer drives away from it.
	top_level = true
	position = Vector3.ZERO
	# Explicit whole-course bounds. The automatic AABB is computed while every
	# instance is parked at the origin, and the streaks then scatter across a
	# kilometre of track that the stale bounds do not cover -- the renderer
	# frustum-culls the entire trail the moment the origin leaves the view,
	# which on a forward-facing chase camera is always. Symptom: no trail,
	# ever, with every instance perfectly valid.
	custom_aabb = AABB(Vector3(-2000, -300, -2000), Vector3(4000, 600, 4000))


static func _get_streak_mesh() -> QuadMesh:
	if _streak_mesh == null:
		_streak_mesh = QuadMesh.new()
		_streak_mesh.size = Vector2(1.0, 1.0)
		# Lie flat on the ground (QuadMesh faces +Z by default).
		_streak_mesh.orientation = PlaneMesh.FACE_Y
	return _streak_mesh


static func _get_streak_material() -> StandardMaterial3D:
	if _streak_material == null:
		if _streak_texture == null:
			# Soft-edged elliptical streak: radial gradient, stretched by each
			# instance's transform into a groove segment.
			var gradient := Gradient.new()
			gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
			gradient.colors = PackedColorArray([
				Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
			_streak_texture = GradientTexture2D.new()
			_streak_texture.gradient = gradient
			_streak_texture.width = 64
			_streak_texture.height = 64
			_streak_texture.fill = GradientTexture2D.FILL_RADIAL
			_streak_texture.fill_from = Vector2(0.5, 0.5)
			_streak_texture.fill_to = Vector2(0.5, 0.0)
		_streak_material = StandardMaterial3D.new()
		_streak_material.albedo_color = TINT
		_streak_material.albedo_texture = _streak_texture
		_streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# LIT, matte, no specular: the streak's darkening then scales with the
		# scene's own light. Unshaded was tried first and read perfectly on
		# glacier -- and then would have GLOWED on the aurora course, where an
		# unshaded 0.5-value decal is brighter than the moonlit deck it lies on.
		_streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_streak_material.roughness = 1.0
		_streak_material.metallic_specular = 0.0
		_streak_material.vertex_color_use_as_albedo = true
		_streak_material.disable_receive_shadows = true
		# Belt and braces with the basis fix: a ground decal has no meaningful
		# back face, and on a banked corner the camera can catch one edge-on.
		_streak_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Hug the floor without z-fighting it.
		_streak_material.render_priority = -1
	return _streak_material


## Called by the racer every physics tick with everything the trail needs.
## Deliberately knows NOTHING about Racer -- a typed back-reference here and a
## typed _snow_trail on the racer is a class_name cycle, and Godot's parser
## refuses the pair outright.
##
## on_snow: touching a groove-taking surface this tick. Ice takes no groove;
## the trail simply pauses across it, which also breaks the ribbon exactly
## where the surface visibly changes.
func tick(pos: Vector3, floor_n: Vector3, on_snow: bool, sliding: bool, speed: float) -> void:
	if not on_snow or speed < 2.0:
		return
	if _last_drop != Vector3.INF and pos.distance_squared_to(_last_drop) < DROP_SPACING * DROP_SPACING:
		return
	var heading := pos - _last_drop if _last_drop != Vector3.INF else Vector3.FORWARD
	_last_drop = pos
	_drop(pos, heading, floor_n, sliding)


func _drop(pos: Vector3, heading: Vector3, floor_n: Vector3, sliding: bool) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	# Streak footprint: the belly slide presses a wide trough, the waddle a
	# narrower one. Slight overlap along the travel axis fuses the streaks
	# into a continuous carved line.
	var width := 0.62 if sliding else 0.40
	var length := DROP_SPACING * 1.9
	if floor_n.length_squared() < 0.5:
		floor_n = Vector3.UP
	# floor_n cross heading, NOT the other way around: the other order builds a
	# negative-determinant basis, which mirrors the quad's winding -- the streak
	# then faces INTO the snow and back-face culling removes it. Symptom: every
	# instance valid in the probe, nothing on screen, in any scene.
	var side := floor_n.cross(heading).normalized()
	var basis := Basis(side * width, floor_n, heading * length)
	# 4 cm above the contact point: under the deck's own bump relief but above
	# its surface, so the streak neither floats nor z-fights.
	var xform := Transform3D(basis, pos + floor_n * 0.04)
	multimesh.set_instance_transform(_head, xform)
	_ages[_head] = now
	_head = (_head + 1) % SEGMENTS
	_live = mini(_live + 1, SEGMENTS)
	# Age every live streak. Run here rather than in _process: drops happen
	# 20-40 times a second at race speed, which is more than enough temporal
	# resolution for a 9-second fade, and a parked racer stops paying at all.
	for i: int in SEGMENTS:
		if _ages[i] < 0.0:
			continue
		var age := now - _ages[i]
		if age >= LIFETIME:
			_ages[i] = -1.0
			multimesh.set_instance_color(i, Color(1, 1, 1, 0))
			continue
		# Quick press-in, long melt-out: fresh streaks are sharp, old ones
		# soften away the way wind actually reclaims a track.
		var k := 1.0 - age / LIFETIME
		multimesh.set_instance_color(i, Color(1, 1, 1, 0.55 * k * k + 0.10 * k))
