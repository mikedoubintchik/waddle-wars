class_name PenguinLoader
extends Control
## Dancing-penguin busy indicator: the game's real penguin, rendered live.
##
## Every "loading" state shows this instead of a bare label. It builds a tiny
## transparent SubViewport holding one PenguinVisual — the same hero asset the
## racers use, with its full plumage, bill and eye detail — lit by a warm key
## and a cool rim, and dances it: a bouncing hop cycle, a hip sway, a slow
## turn, and a squash on every landing.
##
## Rendering the real penguin here is close to free at the moment it matters:
## the loader only ever exists behind a loading overlay, and touching those
## materials early means the engine compiles their shaders there instead of on
## the first frame of gameplay (the same trick ShaderWarmup uses for course
## materials).
##
## Under reduced motion the dance settles to a gentle idle sway.
##
## The penguin is built the first time the loader is shown, never at startup,
## and the viewport only renders while visible. Both matter: SceneRouter's
## overlay lives for the whole session, and an always-updating SubViewport
## holding a lathe-built penguin cost enough main-thread time on the
## single-threaded web build to stall the boot splash outright.

## Seconds per hop; the sway and turn are derived from it so the whole dance
## reads as one rhythm.
const CYCLE: float = 0.72
const HOP_HEIGHT: float = 0.16
const SWAY_DEG: float = 9.0
const TURN_DEG: float = 26.0

var penguin_size: float = 132.0  ## Rendered square edge in logical pixels.

var _viewport: SubViewport = null
var _penguin: PenguinVisual = null
var _pivot: Node3D = null
var _time: float = 0.0
var _reduced: bool = false
var _last_hop: int = -1


func _init(p_size: float = 132.0) -> void:
	penguin_size = maxf(p_size, 48.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size = Vector2(penguin_size, penguin_size)
	set_process(false)
	if GameConfig.is_headless():
		return
	_reduced = UITheme.reduced_motion()
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


## Builds on first reveal, then parks the viewport whenever it is hidden.
func _on_visibility_changed() -> void:
	var showing := is_visible_in_tree()
	if showing and _viewport == null:
		_build()
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if showing \
			else SubViewport.UPDATE_DISABLED
	set_process(showing and _viewport != null)


func _build() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	UITheme.crisp_subviewport(_viewport, self)

	# Ambient-only environment: no sky, so the penguin floats on the overlay
	# instead of carrying a box of background with it.
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.56, 0.66, 0.86)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.86
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	# Warm key from the front-left, cool rim from behind-right: the same
	# two-light read the customize preview uses, so the penguin looks like it
	# does everywhere else in the game.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, 148.0, 0.0)
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 1.05
	key.shadow_enabled = false
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-14.0, -32.0, 0.0)
	rim.light_color = Color(0.66, 0.82, 1.0)
	rim.light_energy = 0.55
	rim.shadow_enabled = false
	_viewport.add_child(rim)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_penguin = PenguinVisual.new()
	_penguin.setup({})
	_penguin.pose = PenguinVisual.Pose.CELEBRATE
	_pivot.add_child(_penguin)

	var camera := Camera3D.new()
	_viewport.add_child(camera)
	camera.current = true
	camera.fov = 38.0
	# Framed so the hop keeps the whole bird — crown to feet — inside the
	# square at the top of its arc.
	camera.look_at_from_position(Vector3(0.0, 0.86, -2.25), Vector3(0.0, 0.62, 0.0), Vector3.UP)


func _process(delta: float) -> void:
	if _pivot == null:
		return
	_time += delta
	var amp := 0.35 if _reduced else 1.0
	var phase := _time / CYCLE * TAU

	# Hop: |sin| gives a bounce that sits on the floor between beats rather
	# than a sine that spends half its time underground.
	var hop := absf(sin(phase)) * HOP_HEIGHT * amp
	_pivot.position.y = hop
	_pivot.rotation.y = sin(phase * 0.5) * deg_to_rad(TURN_DEG) * amp
	_pivot.rotation.z = sin(phase + PI * 0.25) * deg_to_rad(SWAY_DEG) * amp

	# Squash on each landing (the moment |sin| returns to zero).
	if not _reduced and _penguin != null:
		var beat := int(_time / (CYCLE * 0.5))
		if beat != _last_hop:
			_last_hop = beat
			_penguin.trigger_squash(0.88)
