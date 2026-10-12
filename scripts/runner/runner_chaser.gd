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

const PREVIEW_BACK_ALPHA: float = 0.18
const PREVIEW_FRONT_ALPHA: float = 0.64
const RUNNING_CREST_FAR: float = 0.96
const RUNNING_CREST_CLOSE: float = 0.92
const CATCH_SURGE_START: float = 0.18
const CATCH_SURGE_END: float = 0.84
static var _surround_blend: ShaderMaterial = null

## Metres behind the player. Starts at the base gap and is pulled in by hits.
var gap: float = RunnerConfig.CHASER_BASE_GAP

var _puffs: MultiMeshInstance3D = null
var _face: MeshInstance3D = null
var _intro_wave: Node3D = null
var _intro_back: Sprite3D = null
var _intro_front: Sprite3D = null
var _caught: bool = false
var _overrunning: bool = false
var _overrun_start_z: float = 0.0
var _overrun_start_gap: float = 0.0
var _overrun_reduced: bool = false
var _catch_start_crest: float = 0.94
var _catch_intro_alpha: Vector2 = Vector2.ZERO
var _catch_canvas: CanvasLayer = null
var _catch_snow: TextureRect = null
var _catch_surround: TextureRect = null
var _catch_mist: ColorRect = null
var _catch_illustration: TextureRect = null
var _catch_title: TextureRect = null
var _time: float = 0.0
var _wave_time: float = 0.0
var _last_pressure: float = 0.0


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
	_build_intro_wave()


## Authored snow front rolls in 3D behind hero during opening beat. The alpha
## texture gives fine powder and irregular layered depth. The rolling lip stays
## visible during play rather than fading away after GO.
func _build_intro_wave() -> void:
	_intro_wave = Node3D.new()
	_intro_wave.name = "OpeningSnowFront"
	# Keep the two sprites eligible for the covered first-draw warmup. Their
	# initial 0.001 alpha and far-behind-camera position prevent a flash.
	_intro_wave.visible = true
	add_child(_intro_wave)
	var texture := load(RunnerHUDArt.POWDER) as Texture2D
	for layer: int in 2:
		var spray := Sprite3D.new()
		spray.name = "PowderDepth" if layer == 0 else "PowderLip"
		spray.texture = texture
		spray.pixel_size = 0.008
		spray.shaded = false
		spray.double_sided = true
		# This camera-placed foreground powder crosses the deck plane. Depth
		# testing sliced it into a straight horizontal line during countdown.
		spray.no_depth_test = true
		spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spray.position = Vector3(0.0, 0.96, -0.45 if layer == 0 else 0.35)
		spray.scale = Vector3(1.0, 0.47, 1.0)
		spray.modulate.a = 0.001
		_intro_wave.add_child(spray)
		if layer == 0:
			_intro_back = spray
		else:
			_intro_front = spray
	_build_catch_spray(texture)


## A foreground continuation of the same authored snow front. The distant
## wall begins behind the chase camera, so moving that wall alone cannot show
## the moment snow swallows the penguin. This lip rises across the world while
## the live HUD stays above it; results appear only after the catch finishes.
func _build_catch_spray(texture: Texture2D) -> void:
	_catch_canvas = CanvasLayer.new()
	_catch_canvas.name = "AvalancheCatch"
	_catch_canvas.layer = 0
	_catch_canvas.visible = false
	add_child(_catch_canvas)
	_catch_snow = TextureRect.new()
	_catch_snow.name = "CatchingSnowFront"
	_catch_snow.texture = texture
	_catch_snow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_catch_snow.stretch_mode = TextureRect.STRETCH_SCALE
	_catch_snow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catch_canvas.add_child(_catch_snow)
	_catch_surround = TextureRect.new()
	_catch_surround.name = "CurlingSnowSurround"
	_catch_surround.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_catch_surround.stretch_mode = TextureRect.STRETCH_SCALE
	_catch_surround.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catch_surround.modulate.a = 0.0
	if _surround_blend == null:
		var blend_shader := Shader.new()
		blend_shader.code = "shader_type canvas_item; void fragment() { COLOR.a *= 1.0 - smoothstep(0.86, 1.0, UV.y); }"
		_surround_blend = ShaderMaterial.new()
		_surround_blend.shader = blend_shader
	# The raised banks feather into the existing full-height powder lip; their
	# lower quad boundary must never become a straight snow stripe on the ice.
	_catch_surround.material = _surround_blend
	_catch_canvas.add_child(_catch_surround)
	_catch_mist = ColorRect.new()
	_catch_mist.name = "PowderMist"
	_catch_mist.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catch_mist.color = Color(0.88, 0.95, 0.98, 0.0)
	_catch_mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catch_canvas.add_child(_catch_mist)
	# Cache both orientations before gameplay. The fatal hit only changes
	# opacity; it never loads or decodes a new scene image in the catch frame.
	RunnerHUDArt.caught_background(true)
	RunnerHUDArt.caught_background(false)
	RunnerHUDArt.catch_surround(true)
	RunnerHUDArt.catch_surround(false)
	_catch_illustration = TextureRect.new()
	_catch_illustration.name = "CaughtInSnowIllustration"
	_catch_illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_catch_illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_catch_illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catch_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catch_illustration.modulate.a = 0.0
	_catch_canvas.add_child(_catch_illustration)
	var end_art := preload("res://scripts/ui/runner_end_art.gd")
	end_art.catch_title(true)
	end_art.catch_title(false)
	_catch_title = TextureRect.new()
	_catch_title.name = "AvalancheHeadline"
	_catch_title.accessibility_name = "AVALANCHE!"
	_catch_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_catch_title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_catch_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catch_canvas.add_child(_catch_title)


func set_intro_preview(strength: float, player_distance: float, delta: float) -> void:
	if _intro_wave == null:
		return
	var amount := clampf(strength, 0.0, 1.0)
	_intro_wave.visible = amount > 0.01
	if not _intro_wave.visible:
		return
	_wave_time += delta
	_intro_back.position.y = 0.88 + sin(_wave_time * 2.4) * 0.10
	_intro_front.position.y = 0.96 + sin(_wave_time * 3.0 + 1.2) * 0.12
	_intro_back.position.x = sin(_wave_time * 0.75) * 0.22
	_intro_front.position.x = sin(_wave_time * 0.95 + 0.7) * 0.15
	_intro_back.scale.y = 0.44 + sin(_wave_time * 2.2) * 0.025
	_intro_front.scale.y = 0.47 + sin(_wave_time * 2.8 + 0.4) * 0.035
	_intro_back.modulate.a = amount * PREVIEW_BACK_ALPHA
	_intro_front.modulate.a = amount * PREVIEW_FRONT_ALPHA
	var wave_y := sin(_wave_time * 2.8) * 0.06
	var preview_gap := 3.2
	var camera := get_viewport().get_camera_3d()
	if _time > 0.0 and camera != null:
		# The camera settles much closer after GO. A fixed world offset then
		# drops the whole powder lip below the frame, even while its node is
		# visible. Place only this near-field spray from the lower camera ray;
		# the wall itself and the gap meter retain the true chase separation.
		var pressure := clampf(1.0 - gap / RunnerConfig.CHASER_BASE_GAP, 0.0, 1.0)
		var viewport_size := get_viewport().get_visible_rect().size
		var lip_pixel := Vector2(viewport_size.x * 0.5,
			viewport_size.y * lerpf(RUNNING_CREST_FAR, RUNNING_CREST_CLOSE, pressure))
		var ray_origin := camera.project_ray_origin(lip_pixel)
		var ray_direction := camera.project_ray_normal(lip_pixel)
		# The PNG's upper rows are transparent. Its solid central crest begins
		# around 34.4% down the image; anchoring the full rectangle put nearly all
		# visible snow below the landscape viewport. Track that painted contour
		# while leaving the hero and the obstacle lanes above the powder.
		var crest_y := wave_y + _intro_front.position.y \
			+ _intro_front.texture.get_height() * _intro_front.pixel_size * _intro_front.scale.y * (0.5 - RunnerHUDArt.POWDER_CREST)
		if ray_direction.y < -0.001:
			var ray_distance := (crest_y - ray_origin.y) / ray_direction.y
			var crest_z := ray_origin.z + ray_direction.z * maxf(0.0, ray_distance)
			preview_gap = clampf(crest_z + player_distance - _intro_front.position.z, 0.35, 5.5)
	_intro_wave.global_position = Vector3(0.0, wave_y, -player_distance + preview_gap)
	if camera != null:
		_extend_powder_below_frame(camera)


## Extend only the lower powder body when the opening camera can see its quad
## edge. Keep each painted crest at exactly the same world position, preserving
## the running lower-frame anchor and the clear space around the penguin.
func _extend_powder_below_frame(camera: Camera3D) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var bottom_pixel := Vector2(viewport_size.x * 0.5, viewport_size.y * 1.04)
	var origin := camera.project_ray_origin(bottom_pixel)
	var ray := camera.project_ray_normal(bottom_pixel)
	if ray.z >= -0.001:
		return
	for spray: Sprite3D in [_intro_back, _intro_front]:
		var pixels_to_world := spray.texture.get_height() * spray.pixel_size
		var height := pixels_to_world * spray.scale.y
		var crest_offset := 0.5 - RunnerHUDArt.POWDER_CREST
		var crest_y := spray.global_position.y + height * crest_offset
		var ray_distance := (spray.global_position.z - origin.z) / ray.z
		if ray_distance <= 0.0:
			continue
		var bottom_y := origin.y + ray.y * ray_distance
		var extended_height := maxf(height, (crest_y - bottom_y) / (1.0 - RunnerHUDArt.POWDER_CREST))
		spray.position.y += (height - extended_height) * crest_offset
		spray.scale.y = extended_height / pixels_to_world


func chase_preview_strength(elapsed: float) -> float:
	# Keep powder low behind the feet, leaving the obstacle horizon readable.
	# Hits tighten its leading edge; the HUD continues to show the true wall gap.
	var pressure := clampf(1.0 - gap / RunnerConfig.CHASER_BASE_GAP, 0.0, 1.0)
	return lerpf(1.0, 0.55 + pressure * 0.20, clampf(elapsed / 3.2, 0.0, 1.0))


## `player_distance` is how far the player has run; `pressure` is 0..1, how
## hard the wall is currently pushing (the run raises it per hit).
func tick(delta: float, player_distance: float, pressure: float) -> void:
	if _overrunning:
		return
	_time += delta
	# The gap recovers toward its base whenever the player is running clean,
	# so a single mistake is survivable and three in quick succession are not.
	if pressure > _last_pressure:
		gap = maxf(0.0, gap - (pressure - _last_pressure) * RunnerConfig.CHASER_GAP_PER_HIT)
	_last_pressure = pressure
	# Slowly advancing, breathing storm pressure makes a clean run still read
	# as a chase. Six metres maximum cannot catch a clean runner or change the
	# three-hit limit. No gameplay RNG consumed.
	var storm := smoothstep(0.0, 1200.0, player_distance) * \
		(4.5 + sin(_time * 0.24) * 1.5)
	var target := maxf(0.0, RunnerConfig.CHASER_BASE_GAP \
		- pressure * RunnerConfig.CHASER_GAP_PER_HIT - storm)
	gap = move_toward(gap, target, RunnerConfig.CHASER_RECOVER * delta)
	global_position = Vector3(0.0, 0.0, -player_distance + gap)
	_update_wall_visibility()
	# Breathing scale: the wall is never still, and a static mesh behind the
	# player is the fastest way to make a chase read as scenery.
	if _puffs != null:
		var pulse := 1.0 + sin(_time * 2.3) * 0.04
		_puffs.scale = Vector3(pulse, 1.0 + sin(_time * 1.7) * 0.05, pulse)
	if gap <= 0.05 and not _caught:
		_caught = true
		caught.emit()


## The rear wall must never intersect the chase camera while the run is live.
## At a tight gap its tall slab/billboards otherwise replace the entire course
## with white. The low powder lip and true gap meter carry the close threat.
func _update_wall_visibility() -> void:
	var camera := get_viewport().get_camera_3d()
	var safely_behind := camera == null or global_position.z >= camera.global_position.z + 4.0
	if _face != null:
		_face.visible = safely_behind and not _overrunning
	if _puffs != null:
		_puffs.visible = safely_behind and not _overrunning


## Death sequence: the wall stops being a distant threat and rolls straight
## over the camera. A run that simply halts reads as the game breaking — the
## most common complaint about this mode was "it just stops" — and the fix is
## not a better panel, it is showing the player the thing that ate them.
func overrun(reduced_motion: bool = false) -> void:
	_overrunning = true
	_update_wall_visibility()
	_overrun_start_z = global_position.z
	_overrun_start_gap = gap
	_overrun_reduced = reduced_motion
	_catch_start_crest = 0.94
	if _intro_wave != null:
		var camera := get_viewport().get_camera_3d()
		if camera != null and _intro_front != null:
			var height := _intro_front.texture.get_height() * _intro_front.pixel_size * _intro_front.scale.y
			var crest := camera.unproject_position(_intro_front.global_position
				+ Vector3.UP * height * (0.5 - RunnerHUDArt.POWDER_CREST))
			_catch_start_crest = clampf(crest.y / maxf(get_viewport().get_visible_rect().size.y, 1.0), 0.90, 0.98)
		_catch_intro_alpha = Vector2(_intro_back.modulate.a, _intro_front.modulate.a)
		# Moving the distant chaser also moves this child. Retire the near 3D
		# preview before that movement can expose its underside as a snow ribbon.
		# Reduced motion keeps it stationary while the fixed catch layer dissolves.
		_intro_wave.visible = _overrun_reduced and _intro_wave.visible
	if _catch_canvas != null:
		_catch_canvas.visible = true
	present_overrun(0.0)


## The run owns the single catch clock, so results cannot beat the snow to the
## camera. No tween/timer survives a restart, and this consumes no route RNG.
func present_overrun(progress: float) -> void:
	if not _overrunning:
		return
	var amount := clampf(progress, 0.0, 1.0)
	# At 2.4 seconds: ~0.43s for the stumble to read, ~1.58s of snow advance,
	# then ~0.38s held inside powder before the result panel arrives.
	var surge := smoothstep(CATCH_SURGE_START, CATCH_SURGE_END, amount)
	# A slower first half leaves the falling hero readable inside the curl;
	# the same end time still fully closes the snow before the caught scene.
	surge *= surge
	gap = lerpf(_overrun_start_gap, 0.0, surge)
	global_position.z = _overrun_start_z if _overrun_reduced \
		else _overrun_start_z - (_overrun_start_gap + 6.0) * surge
	if _puffs != null:
		_puffs.scale = Vector3.ONE if _overrun_reduced \
			else Vector3.ONE.lerp(Vector3(1.5, 1.6, 1.5), surge)
	if _intro_wave != null and _overrun_reduced:
		_intro_back.modulate.a = _catch_intro_alpha.x * (1.0 - surge)
		_intro_front.modulate.a = _catch_intro_alpha.y * (1.0 - surge)
		if surge >= 1.0:
			_intro_wave.visible = false
	if _catch_snow == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	# Keep the image's aspect ratio. A generous crop into the central powder
	# billow gives portrait and landscape equal coverage without stretching it.
	var snow_height := viewport_size.y * 2.3
	var snow_width := maxf(viewport_size.x * 1.2,
		snow_height * _catch_snow.texture.get_width() / _catch_snow.texture.get_height())
	_catch_snow.size = Vector2(snow_width, snow_height)
	# Hold the foreground curl below the prone hero through the 1.8-second
	# catch tableau. Its irregular painted billows rise above the nominal crest.
	# The final sweep still fills the screen before the 2.4-second result beat;
	# the physical gap above remains authoritative and independent of this art.
	var readable_crest := lerpf(_catch_start_crest, 0.82, smoothstep(0.0, 0.70, amount))
	var crest := -0.30 if _overrun_reduced else lerpf(readable_crest, -0.30, smoothstep(0.80, 0.96, amount))
	_catch_snow.position = Vector2((viewport_size.x - snow_width) * 0.5,
		viewport_size.y * crest - snow_height * RunnerHUDArt.POWDER_CREST)
	# Reduced motion uses a steady dissolve, with no translating wall or camera
	# punch. Both paths retain a readable third-hit -> caught -> results beat.
	_catch_snow.modulate.a = surge if _overrun_reduced else 1.0
	if _catch_surround != null:
		var portrait := viewport_size.y >= viewport_size.x
		_catch_surround.texture = RunnerHUDArt.catch_surround(portrait)
		# Authored U-shaped powder banks wrap the live hero instead of lifting a
		# solid wall across its face. Only presentation pixels move; no route RNG.
		var wrap := smoothstep(0.12, 0.68, amount)
		var lift := 0.0 if _overrun_reduced else (1.0 - wrap) * 0.30
		var drift := 0.0 if _overrun_reduced else sin(amount * TAU) * 0.008 * wrap
		_catch_surround.size = Vector2(viewport_size.x * 1.04, viewport_size.y * (0.90 if portrait else 0.80))
		_catch_surround.position = Vector2(viewport_size.x * (-0.02 + drift),
			viewport_size.y * ((0.04 if portrait else 0.15) + lift))
		_catch_surround.modulate.a = wrap * (1.0 - smoothstep(0.86, 1.0, amount))
	_catch_mist.color.a = smoothstep(0.72, 1.0, amount) * 0.58
	if _catch_illustration != null:
		_catch_illustration.texture = RunnerHUDArt.caught_background(viewport_size.y >= viewport_size.x)
		_catch_illustration.modulate.a = smoothstep(0.80, 1.0, amount)
	if _catch_title != null:
		var portrait := viewport_size.y >= viewport_size.x
		_catch_title.texture = preload("res://scripts/ui/runner_end_art.gd").catch_title(portrait)
		_catch_title.size = Vector2(viewport_size.x * (0.62 if portrait else 0.39), viewport_size.y * (0.12 if portrait else 0.12))
		_catch_title.position = Vector2(viewport_size.x * (0.61 if portrait else 0.50) - _catch_title.size.x * 0.5,
			viewport_size.y * (0.18 if portrait else 0.26))
		# The headline belongs to the full catch clock, not the 0.75s HUD toast.
		_catch_title.modulate.a = 1.0 - smoothstep(0.88, 1.0, amount)


func reset() -> void:
	_caught = false
	_overrunning = false
	_overrun_start_z = 0.0
	_overrun_start_gap = 0.0
	_overrun_reduced = false
	_catch_start_crest = 0.94
	_catch_intro_alpha = Vector2.ZERO
	_time = 0.0
	_wave_time = 0.0
	gap = RunnerConfig.CHASER_BASE_GAP
	_last_pressure = 0.0
	position = Vector3(0.0, 0.0, RunnerConfig.CHASER_BASE_GAP)
	if _puffs != null:
		_puffs.scale = Vector3.ONE
		_puffs.visible = true
	if _face != null:
		_face.visible = true
	if _intro_wave != null:
		_intro_wave.visible = false
	if _catch_canvas != null:
		_catch_canvas.visible = false
	if _catch_surround != null:
		_catch_surround.modulate.a = 0.0
	if _catch_illustration != null:
		_catch_illustration.modulate.a = 0.0
	if _catch_title != null:
		_catch_title.modulate.a = 0.0
