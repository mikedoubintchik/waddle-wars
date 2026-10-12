extends SubViewportContainer
## A single live dressing-room model. Production species proportions and
## attachment sockets are authoritative; no screen-space garment overlays.

const WARDROBE_PENGUIN := preload("res://scripts/ui/wardrobe_penguin_visual.gd")
var penguin: PenguinVisual
var pivot: Node3D
var camera: Camera3D
var trail: TrailEffect
var viewport: SubViewport
var equipped: Dictionary = {}
var _sway_time := 0.0


func _ready() -> void:
	name = "LiveWardrobePreview"
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "WardrobeWorld"
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	UITheme.crisp_subviewport(viewport, self)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.TRANSPARENT
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9deef")
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	_light(Vector3(-32, 150, 0), Color("fff1db"), 1.15)
	_light(Vector3(-18, -135, 0), Color("a2caf3"), 0.48)
	_light(Vector3(-35, 5, 0), Color("ffe2be"), 0.72)
	pivot = Node3D.new()
	pivot.name = "WardrobeTurntable"
	viewport.add_child(pivot)
	penguin = WARDROBE_PENGUIN.new()
	penguin.name = "WardrobePenguin"
	pivot.add_child(penguin)
	camera = Camera3D.new()
	camera.name = "WardrobeCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.62
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0, 0.94, -3.3), Vector3(0, 0.66, 0))
	camera.current = true


func _light(rotation_degrees_value: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rotation_degrees_value
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = false
	viewport.add_child(light)


func show_equipped(value: Dictionary) -> void:
	if equipped == value:
		return
	equipped = value.duplicate()
	if trail != null:
		trail.emitting = false
		trail.queue_free()
		trail = null
	penguin.setup_look(CharacterLook.from_equipped(equipped, CharacterLook.RenderRole.HERO))
	penguin.set_pose(PenguinVisual.Pose.IDLE)
	var trail_id := String(equipped.get("trail", ""))
	if not trail_id.is_empty():
		trail = TrailEffect.create(trail_id)
		if trail != null:
			# Real trail renderer, fanned beside the feet so an idle front view
			# shows its particles instead of hiding them behind the body.
			trail.name = "WardrobeTrail"
			trail.set_meta("cosmetic_id", trail_id)
			penguin.get_socket(&"trail_socket").add_child(trail)
			trail.position = Vector3(-0.25, -0.12, 0)
			trail.local_coords = true
			trail.preprocess = 0.7
			trail.amount = 14
			var material := trail.process_material as ParticleProcessMaterial
			material.direction = Vector3(-1, 0.25, 0.25)
			material.initial_velocity_min = 0.35
			material.initial_velocity_max = 0.65
			material.gravity = Vector3(0, -0.13, 0)
			material.scale_min = 0.45
			material.scale_max = 0.70
			trail.emitting = true


func _process(delta: float) -> void:
	if penguin == null or not is_visible_in_tree():
		return
	_sway_time += delta
	pivot.rotation.y = sin(_sway_time * 0.5) * 0.23
	penguin.tick(delta, 0.0)
