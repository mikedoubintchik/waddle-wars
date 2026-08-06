class_name BootWarmup
extends Node
## Links the game's shader programs during the studio splash, a few per frame.
##
## Measured with BootProfiler on a cold GPU cache, the title screen costs ~50 ms
## of CPU to build and ~3.5 s to *draw* its first three frames. The gap is
## first-sight shader program linking: nothing is slow to construct, but every
## material, shadow pass, sky and glow pass has to be compiled and linked before
## the frame it appears in can present. Chrome on macOS reaches WebGL2 through
## ANGLE onto Metal, where a link costs milliseconds instead of the microseconds
## Safari's native GL path charges — which is exactly why the game has always
## played clean in Safari and locked up in Chrome.
##
## The frozen screen users reported as "the splash hangs" was never the splash:
## change_scene_to_file() blocks, so the splash is simply the last frame the
## engine managed to present before the title's first draw stalled the main
## thread. Nothing was hung, and no amount of loading-overlay work could show
## through, because the overlay could not be drawn either.
##
## Re-linking is what is expensive, not linking: building the same diorama a
## second time in one process draws in 197 ms instead of 1320 ms. So the fix is
## to pay the cost somewhere it does not matter. The splash holds for ~2.4 s
## with an almost idle main thread, so this node spends it: one warm job per
## frame, each drawing a throwaway instance into a small offscreen viewport that
## mirrors the title's rendering setup, until every program the game needs is
## linked. The splash keeps animating between jobs, and the title it hands off
## to draws immediately.
##
## This is the boot-time twin of ShaderWarmup, which does the same job for the
## per-course materials that only exist once a race has been built. The two
## share their synthetic feature probes.
##
## What it covers, in the order it warms them:
##   * every VisualLibrary shader factory (snow, ice, water, aurora, sparkle)
##     and its StandardMaterial3D families (rock, emissive, billboard puffs),
##   * every track surface material, so the first race starts warm too,
##   * ShaderWarmup's synthetic BaseMaterial3D feature combinations,
##   * one live PenguinVisual, which owns shaders no factory mints.
##
## The offscreen viewport is never parented to a SubViewportContainer, so it is
## not displayed and its contents cannot reach the screen; it is freed together
## with this node as soon as the queue drains.

## Warm jobs started per frame. Low enough that the splash's wordmark tween
## keeps moving between links even in Chrome, where one can cost tens of
## milliseconds; high enough that the whole set drains inside the hold.
const JOBS_PER_FRAME: int = 2
## Frames to keep rendering after the last job is queued, so the final
## instances actually go through a draw before everything is freed.
const DRAIN_FRAMES: int = 3
## Offscreen render target edge. Small enough to be nearly free per frame; the
## linked programs do not depend on it.
const VIEWPORT_EDGE: int = 64
## Metres in front of the warm camera.
const PROBE_DISTANCE: float = 2.0
## Uniform scale applied to every probe so any mesh stays inside the frustum.
const PROBE_SCALE: float = 0.25

static var _done: bool = false  ## Whole-session guard: the work is idempotent.
## True once every program has been through a draw. The splash waits on this
## rather than a fixed hold, so a slow machine gets the time it needs and a fast
## one is not delayed.
static var _finished: bool = false

var _viewport: SubViewport = null
var _root: Node3D = null
var _queue: Array[Material] = []
var _penguin_queued: bool = false
var _drain: int = DRAIN_FRAMES
var _linked: int = 0


## Starts a warm-up under `host` (the splash). Returns null when the pass is
## skipped: headless runs, and any later boot in the same session.
static func warm(host: Node) -> BootWarmup:
	if host == null or GameConfig.is_headless() or _done:
		return null
	_done = true
	_finished = false
	var node := BootWarmup.new()
	node.name = "BootWarmup"
	host.add_child(node)
	return node


## False only while a pass is actually mid-flight; true when there is nothing
## to wait for, so callers can gate on it unconditionally.
static func is_finished() -> bool:
	return _finished


func _ready() -> void:
	# Ahead of the splash's own script, and immune to a pause arriving mid-boot.
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_viewport()
	_fill_queue()
	BootProfiler.step("warmup queued (%d)" % _queue.size())


func _process(_delta: float) -> void:
	if _root == null:
		return
	for i: int in JOBS_PER_FRAME:
		if _queue.is_empty():
			break
		_spawn(_queue.pop_back())
	if not _queue.is_empty():
		return
	# Queue drained: the penguin goes last because it is the most expensive
	# single job, then a few frames so every spawned instance has been drawn.
	if not _penguin_queued:
		_penguin_queued = true
		_spawn_penguin()
		return
	_drain -= 1
	if _drain <= 0:
		if BootProfiler.enabled():
			print("[boot-profile] warmup linked %d materials" % _linked)
		_finished = true
		queue_free()


func _exit_tree() -> void:
	# A tap can skip the splash mid-pass; whatever is left links at the title.
	_finished = true
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	_root = null


## --- Offscreen stage ---------------------------------------------------------

## Mirrors the title diorama's rendering configuration. The colours are
## irrelevant — a program is keyed by the *feature* set (sky, fog, glow, ACES
## tonemap, shadowed directional light) and by the render target's sample count,
## so MSAA has to match the title's viewport or the links do not carry over.
func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(VIEWPORT_EDGE, VIEWPORT_EDGE)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_2X
	add_child(_viewport)

	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_density = 0.002
	if String(SettingsManager.get_setting("display", "particle_quality")) != "low":
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	# A shadow-casting directional light: the depth pass links its own program
	# per material, and that is a stall of exactly the same kind.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.shadow_enabled = String(SettingsManager.get_setting("display", "shadow_quality")) != "off"
	_viewport.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-42.0, -155.0, 0.0)
	fill.light_energy = 0.35
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.shadow_enabled = false
	_viewport.add_child(fill)

	_root = Node3D.new()
	_viewport.add_child(_root)
	var camera := Camera3D.new()
	_viewport.add_child(camera)
	camera.current = true


## --- Work list ---------------------------------------------------------------

## One material per distinct program the game can ask for. Parameter-keyed
## library materials share a Shader, so a single representative call per factory
## links the program every palette of it will later reuse.
func _fill_queue() -> void:
	_queue.append(VisualLibrary.snow_material(Color(0.94, 0.97, 1.0), 0.7))
	_queue.append(VisualLibrary.ice_material(Color(0.55, 0.78, 0.97), 0.55))
	_queue.append(VisualLibrary.water_material(
		Color(0.05, 0.13, 0.3), Color(0.46, 0.42, 0.66), 0.26, 0.06))
	_queue.append(VisualLibrary.aurora_material())
	_queue.append(VisualLibrary.sparkle_material(Color(0.8, 0.9, 1.0), Color(1.0, 1.0, 0.9)))
	_queue.append(VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)))
	_queue.append(VisualLibrary.emissive_material(Color(1.0, 1.0, 1.0), Color(1.0, 0.9, 0.6)))
	_queue.append(VisualLibrary.billboard_puff_material(Color(1.0, 1.0, 1.0, 0.85), 32, 0.9))
	_queue.append(VisualLibrary.billboard_puff_material(Color(1.0, 1.0, 1.0, 0.6), 32, 0.9, true))
	# Track surfaces resolve into the shader families above plus TrackBuilder's
	# own fallbacks; warming them here means the first race is warm as well.
	for surface: int in SurfacesDB.Surface.values():
		var mat := VisualLibrary.track_surface_material(surface as SurfacesDB.Surface)
		if mat != null and not _queue.has(mat):
			_queue.append(mat)
	for probe: Material in ShaderWarmup.probe_materials():
		_queue.append(probe)


func _spawn(mat: Material) -> void:
	if mat == null or _root == null:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = VisualLibrary.warmup_mesh()
	instance.material_override = mat
	instance.scale = Vector3.ONE * PROBE_SCALE
	instance.position = Vector3(0.0, 0.0, -PROBE_DISTANCE)
	_root.add_child(instance)
	_linked += 1


## The racer body owns shaders no VisualLibrary factory mints, so the only way
## to link them is to build one. It costs ~4 ms of CPU and is freed with the
## rest of the stage.
func _spawn_penguin() -> void:
	if _root == null:
		return
	var penguin := PenguinVisual.new()
	penguin.setup({})
	penguin.position = Vector3(0.0, -0.5, -PROBE_DISTANCE)
	_root.add_child(penguin)
	_linked += 1
