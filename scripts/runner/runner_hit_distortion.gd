extends CanvasLayer
## Fifteen seconds of active gameplay after a lost life. The owner supplies the
## clock; pause/countdown/loading/death never spend it. One temporary screen
## read and two cached snow quads, no blur pyramid, particles, timers, RNG or
## retained frame textures. Snow enters from behind at the lower corners.

const DURATION := 15.0
const EFFECT_SHADER := preload("res://assets/shaders/runner_hit_distortion.gdshader")
const ART = preload("res://scripts/ui/runner_hud_art.gd")
var seconds_left := 0.0
var lost_lives := 0
var active_seconds := 0.0
var strength := 0.0
var motion_scale := 1.0
var _entry_strength := 0.0
# Read-only presentation measurements for the live Chrome diagnostics.
var haze_opacity := 0.0
var rear_snow_alpha := 0.0
var rear_crest := 1.0
var _surface: ColorRect
var _effect_material: ShaderMaterial
var _rear_surround: TextureRect
var _rear_front: TextureRect
var _surround_portrait: Texture2D
var _surround_desktop: Texture2D

func setup() -> void:
	layer = 0 # World only; live HUD is layer1 and is never distorted.
	if _surface != null:
		return
	_surface = ColorRect.new()
	_surface.name = "AvalanchePressureEdges"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_material = ShaderMaterial.new()
	_effect_material.shader = EFFECT_SHADER
	_surface.material = _effect_material
	add_child(_surface)
	# Chaser already warmed these same resources while the loading cover was
	# up. Life loss never decodes an image, allocates a node or starts a timer.
	_surround_portrait = ART.catch_surround(true)
	_surround_desktop = ART.catch_surround(false)
	_rear_surround = _snow_quad("RearAvalancheBanks")
	_rear_front = _snow_quad("RearAvalancheLip")
	_rear_front.texture = load(ART.POWDER) as Texture2D
	_present_snow()
	# The loading stage draws this zero-strength pass once to warm its shader.
	# finish_warmup removes it from normal play until an actual unshielded hit.
	_effect_material.set_shader_parameter("strength", 0.0)

func finish_warmup() -> void:
	visible = false

func lost_life(hits_left: int) -> void:
	if hits_left <= 0:
		reset() # Fatal catch owns its separate snow presentation.
		return
	lost_lives = clampi(RunnerConfig.MAX_HITS - hits_left, 1, 2)
	_entry_strength = strength
	seconds_left = DURATION
	active_seconds = 0.0
	_refresh()

func advance(delta: float, active_play: bool, reduced_motion: bool, shake_mode: String) -> void:
	motion_scale = 0.0 if reduced_motion or shake_mode == "off" else (0.35 if shake_mode == "reduced" else 1.0)
	if active_play and seconds_left > 0.0:
		var spent := minf(maxf(delta, 0.0), seconds_left)
		seconds_left = maxf(0.0, seconds_left - spent)
		if seconds_left < 0.000001:
			seconds_left = 0.0
		active_seconds += spent
	_refresh()

func _refresh() -> void:
	# Gentle entry and final three-second fade. Both atmosphere and rear snow
	# share this envelope, so nothing remains when active-play time expires.
	var peak := 0.65 + 0.325 * float(lost_lives - 1)
	strength = 0.0 if seconds_left <= 0.0 else lerpf(_entry_strength, peak,
		smoothstep(0.0, 0.35, active_seconds)) * smoothstep(0.0, 3.0, seconds_left)
	visible = seconds_left > 0.0
	# A faint blue tint disappeared against the already bright ice on phones.
	# Partial whiteout now removes roughly a third/half of world contrast after
	# the first/second loss. HUD remains on its own unaffected CanvasLayer.
	haze_opacity = strength * 0.48
	rear_snow_alpha = strength * 0.90
	_present_snow()
	if _effect_material == null:
		return
	_effect_material.set_shader_parameter("strength", strength)
	_effect_material.set_shader_parameter("haze_opacity", haze_opacity)
	_effect_material.set_shader_parameter("motion_scale", motion_scale)
	_effect_material.set_shader_parameter("effect_clock", active_seconds if motion_scale > 0.0 else 0.0)

func _snow_quad(node_name: String) -> TextureRect:
	var quad := TextureRect.new()
	quad.name = node_name
	quad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	quad.stretch_mode = TextureRect.STRETCH_SCALE
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.modulate.a = 0.0
	add_child(quad)
	return quad

func _present_snow() -> void:
	var peak := 0.65 + 0.325 * float(maxi(1, lost_lives) - 1)
	var envelope := strength / peak
	rear_crest = lerpf(1.0, 0.86 if lost_lives < 2 else 0.82, envelope)
	if _rear_surround == null:
		return
	var view := get_viewport().get_visible_rect().size
	var portrait := view.y >= view.x
	_rear_surround.texture = _surround_portrait if portrait else _surround_desktop
	# Full lower edges extend beyond the viewport. Their upper painted banks
	# curl in from the sides; the transparent center leaves the hero and route
	# decisions readable. No rectangular texture underside can appear on ice.
	# The painted texture's upper half is transparent. Position the *visible*
	# banks beside the near course, rather than keeping nearly all snow below
	# the bottom gauge. The center stays open through the decision corridor.
	var bank_top := lerpf(0.65, 0.18 if lost_lives < 2 else 0.12, envelope)
	var drift := sin(active_seconds * 1.3) * 0.005 * strength * motion_scale
	_rear_surround.size = Vector2(view.x * 1.08, view.y * 0.96)
	_rear_surround.position = Vector2(view.x * (-0.04 + drift), view.y * bank_top)
	_rear_surround.modulate.a = rear_snow_alpha
	var snow_height := view.y * 0.65
	var snow_width := maxf(view.x * 1.12, snow_height * _rear_front.texture.get_width() / _rear_front.texture.get_height())
	_rear_front.size = Vector2(snow_width, snow_height)
	_rear_front.position = Vector2((view.x - snow_width) * 0.5 - view.x * drift,
		view.y * rear_crest - snow_height * ART.POWDER_CREST)
	_rear_front.modulate.a = strength * 0.75

func reset() -> void:
	seconds_left = 0.0
	lost_lives = 0
	active_seconds = 0.0
	strength = 0.0
	_entry_strength = 0.0
	haze_opacity = 0.0
	rear_snow_alpha = 0.0
	_present_snow()
	visible = false
	if _effect_material != null:
		_effect_material.set_shader_parameter("strength", 0.0)
		_effect_material.set_shader_parameter("haze_opacity", 0.0)
