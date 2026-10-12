class_name RunnerVfx
extends MultiMeshInstance3D
## Every particle in Waddle Run, in one draw call.
##
## An endless runner lives or dies on the burst that fires when you touch
## something. Before this file the mode's entire feedback vocabulary was a
## floating "+25" label: a fish vanished, a crate vanished, a hit flashed the
## penguin, and nothing in the WORLD acknowledged any of it. That is the single
## largest gap between this mode and the genre it is chasing.
##
## Why one MultiMesh and not a GPUParticles3D per effect:
##   * a pooled emitter per effect is a node per effect, and a runner fires
##     eight kinds of effect at up to a dozen a second — that is node churn in
##     the hot loop, plus a ParticleProcessMaterial each, plus an AABB each;
##   * every distinct ParticleProcessMaterial is another shader program, and on
##     the web build (gl_compatibility) a first-sight program link is a visible
##     hitch — the mode's whole art budget forbids new programs;
##   * a MultiMesh with per-instance colour is ONE draw call and ONE material
##     for all of it, and the per-particle motion a runner needs (spawn, drift,
##     drag, gravity, shrink, fade) is six lines of integration.
##
## The material is deliberately the exact feature combination ShaderWarmup
## already probes as "uabkt+v" — unshaded, alpha, additive, billboard,
## keep-scale, textured, vertex-coloured — so this file adds ZERO shader
## programs to the build. Anything that would need a different combination is
## expressed with colour and scale instead.
##
## Additive rather than alpha on purpose: the deck is a mid-value saturated
## ribbon, and additive sparks read as LIGHT against it at any biome brightness.
## An alpha white puff is invisible on day snow and grey on the night deck; an
## additive one glows in both.

## Live particles. Sized for the worst honest case: a ramp landing (24) into a
## fish line (10 x 8) with slide spray and speed motes already running.
const POOL: int = 288
## CPU-driven MultiMesh updates are capped at 60 Hz. On 120/144 Hz desktops
## this halves RenderingServer buffer writes without changing spawn rate,
## lifetime, or the motion cadence players can resolve at gameplay scale.
const UPDATE_INTERVAL: float = 1.0 / 60.0
## Metres a particle may travel from the emitter before the bounds below are a
## lie. Bursts are short and slow; the streaks are the long ones.
const BOUNDS: float = 26.0

## --- The hue language -------------------------------------------------------
## Fixed global meaning, identical in every biome (the art direction's rule:
## a hue that means two things means nothing). These are FALLBACKS: if the
## palette module lands, its constants win — see _accent().
##   gold    = collect
##   violet  = power-up
##   orange  = will hurt you
##   cyan    = duck / near miss
##   green   = go / ramp / launch
##   white   = snow the penguin kicked up
const FALLBACK_COLLECT: Color = Color(1.00, 0.82, 0.28)
const FALLBACK_POWERUP: Color = Color(0.86, 0.42, 1.00)
const FALLBACK_HAZARD: Color = Color(1.00, 0.30, 0.08)
const FALLBACK_DUCK: Color = Color(0.30, 0.92, 1.00)
const FALLBACK_GO: Color = Color(0.34, 1.00, 0.46)
const FALLBACK_SNOW: Color = Color(0.86, 0.94, 1.00)

## Palette module owned by the lighting pass. Loaded by path rather than by
## class_name so this file parses and runs whether or not it exists yet, and
## picks the authored accents up automatically the moment it does.
const PALETTE_PATH: String = "res://scripts/runner/runner_palette.gd"
static var _palette: GDScript = null
static var _palette_consts: Dictionary = {}
static var _palette_checked: bool = false

static var _fx_mesh: QuadMesh = null
static var _fx_material: StandardMaterial3D = null

## Ring buffer: the oldest particle is overwritten rather than searched for. A
## burst that arrives when the pool is full should cost the same as one that
## arrives when it is empty.
var _head: int = 0
var _alive: int = 0
var _pos: PackedVector3Array = PackedVector3Array()
var _vel: PackedVector3Array = PackedVector3Array()
var _tint: PackedColorArray = PackedColorArray()
var _life: PackedFloat32Array = PackedFloat32Array()
var _span: PackedFloat32Array = PackedFloat32Array()
var _size_a: PackedFloat32Array = PackedFloat32Array()
var _size_b: PackedFloat32Array = PackedFloat32Array()
var _aspect: PackedFloat32Array = PackedFloat32Array()
var _drag: PackedFloat32Array = PackedFloat32Array()
var _grav: PackedFloat32Array = PackedFloat32Array()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Rate limiters for the continuous emitters, so their spawn count is tied to
## time rather than to frame rate.
var _spray_acc: float = 0.0
var _trail_acc: float = 0.0
var _mote_acc: float = 0.0
var _ribbon_acc: float = 0.0
var _tick_accumulator: float = 0.0


func setup() -> void:
	_rng.randomize()
	_pos.resize(POOL)
	_vel.resize(POOL)
	_tint.resize(POOL)
	_life.resize(POOL)
	_span.resize(POOL)
	_size_a.resize(POOL)
	_size_b.resize(POOL)
	_aspect.resize(POOL)
	_drag.resize(POOL)
	_grav.resize(POOL)
	_life.fill(0.0)
	_span.fill(1.0)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _get_mesh()
	multimesh.instance_count = POOL
	var park := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i: int in POOL:
		multimesh.set_instance_transform(i, park)
		multimesh.set_instance_color(i, Color(0, 0, 0, 0))
	material_override = _get_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# World space. A burst belongs to the place it happened, not to the penguin
	# that caused it — a landing puff that travels with the player is a jet
	# pack, not a puff.
	top_level = true
	position = Vector3.ZERO
	# The automatic AABB is computed while every instance is parked at the
	# origin, and the run then travels kilometres down -Z: stale bounds would
	# frustum-cull the whole system permanently. Same trap SnowTrail documents.
	custom_aabb = AABB(Vector3.ONE * -BOUNDS, Vector3.ONE * BOUNDS * 2.0)


## Keeps culling local to the action instead of using a kilometre-scale box.
## Particle travel is bounded by BOUNDS, so old bursts remain covered while an
## endless run can move arbitrarily far from the world origin.
func set_cull_centre(centre: Vector3) -> void:
	custom_aabb = AABB(centre - Vector3.ONE * BOUNDS, Vector3.ONE * BOUNDS * 2.0)


static func _get_mesh() -> QuadMesh:
	if _fx_mesh == null:
		_fx_mesh = QuadMesh.new()
		_fx_mesh.size = Vector2(1.0, 1.0)
	return _fx_mesh


## Exactly ShaderWarmup's "uabkt+v" probe. Do not add a feature here without
## adding the matching probe flags in the same commit.
static func _get_material() -> StandardMaterial3D:
	if _fx_material == null:
		_fx_material = StandardMaterial3D.new()
		_fx_material.albedo_color = Color.WHITE
		_fx_material.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
		_fx_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fx_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fx_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_fx_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		# Keep-scale is what lets ONE unit quad be every particle size: without
		# it the billboard basis discards the instance scale entirely and every
		# particle renders one metre across.
		_fx_material.billboard_keep_scale = true
		_fx_material.vertex_color_use_as_albedo = true
	return _fx_material


## --- Palette ----------------------------------------------------------------

## The art direction's rule is that all colour comes from the palette pass, but
## the palette module is written by another hand and may not exist in a given
## build. Resolve by path once, cache the constant map, fall back to the hue
## language above. Never a hard dependency, never a parse error.
static func _accent(key: String, fallback: Color) -> Color:
	if not _palette_checked:
		_palette_checked = true
		if ResourceLoader.exists(PALETTE_PATH):
			_palette = load(PALETTE_PATH) as GDScript
			if _palette != null:
				_palette_consts = _palette.get_script_constant_map()
	var found: Variant = _palette_consts.get(key, null)
	if found is Color:
		return found
	return fallback


static func collect_color() -> Color:
	return _accent("COLLECT", FALLBACK_COLLECT)


static func powerup_color() -> Color:
	return _accent("POWERUP", FALLBACK_POWERUP)


static func hazard_color() -> Color:
	return _accent("HAZARD", FALLBACK_HAZARD)


static func duck_color() -> Color:
	return _accent("DUCK", FALLBACK_DUCK)


static func go_color() -> Color:
	return _accent("GO", FALLBACK_GO)


static func snow_color() -> Color:
	return _accent("SNOW", FALLBACK_SNOW)


## --- Spawning ---------------------------------------------------------------

func _spawn(at: Vector3, vel: Vector3, tint: Color, size_a: float, size_b: float,
		span: float, drag: float, grav: float, aspect: float = 1.0) -> void:
	var i := _head
	_head = (_head + 1) % POOL
	if _life[i] <= 0.0:
		_alive += 1
	_pos[i] = at
	_vel[i] = vel
	_tint[i] = tint
	_life[i] = span
	_span[i] = maxf(span, 0.001)
	_size_a[i] = size_a
	_size_b[i] = size_b
	_aspect[i] = aspect
	_drag[i] = drag
	_grav[i] = grav


func _cone(up_bias: float, spread: float) -> Vector3:
	var a := _rng.randf_range(0.0, TAU)
	var r := sqrt(_rng.randf()) * spread
	return Vector3(cos(a) * r, up_bias + _rng.randf_range(-0.2, 0.6), sin(a) * r)


## --- Effects: the one-shots -------------------------------------------------

## A fish went in. Gold, fast, upward, gone in a third of a second: a pickup
## burst that lingers reads as a power-up, and the player collects dozens.
func pickup(at: Vector3) -> void:
	var gold := collect_color()
	for i: int in 9:
		_spawn(at, _cone(1.6, 2.6) * _rng.randf_range(0.8, 1.5),
			gold, _rng.randf_range(0.16, 0.30), 0.02,
			_rng.randf_range(0.22, 0.38), 3.4, 5.0)
	# One bright core flash so the moment has a centre.
	_spawn(at, Vector3(0, 1.2, 0), gold.lerp(Color.WHITE, 0.5), 0.34, 0.9, 0.16, 4.0, 0.0)


## A power-up crate. Bigger, slower and ringed, because this one is worth
## looking up for. `tint` lets the caller pass the per-power-up colour while
## keeping the violet family as the fallback.
func powerup(at: Vector3, tint: Color = Color(0, 0, 0, 0)) -> void:
	var hue := tint if tint.a > 0.0 else powerup_color()
	for i: int in 14:
		_spawn(at, _cone(1.0, 3.6) * _rng.randf_range(0.9, 1.8),
			hue, _rng.randf_range(0.20, 0.40), 0.03,
			_rng.randf_range(0.34, 0.62), 2.2, 3.0)
	ring(at, hue.lerp(Color.WHITE, 0.35), 12, 6.4, 0.30, 0.42)
	_spawn(at, Vector3.ZERO, hue.lerp(Color.WHITE, 0.6), 0.5, 1.5, 0.24, 4.0, 0.0)


## Touchdown. White snow, thrown sideways and low: a landing puff that goes UP
## reads as an explosion under the feet. The ring is the contact — it is what
## tells the player, in one frame, exactly where and when they landed.
func land(at: Vector3, strength: float) -> void:
	var snow := snow_color()
	var count := 8 + int(strength * 8.0)
	for i: int in count:
		var a := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(1.6, 4.2) * (0.6 + strength)
		_spawn(at + Vector3(0, 0.06, 0),
			Vector3(cos(a) * speed, _rng.randf_range(0.6, 2.4), sin(a) * speed * 0.7),
			snow, _rng.randf_range(0.22, 0.46), 0.05,
			_rng.randf_range(0.26, 0.46), 3.0, 6.5)
	ring(at, snow, 10, 4.0 + strength * 4.0, 0.26, 0.30)


## A ramp threw the penguin. Green: the hue language says green is launch, and
## this is the one obstacle that is pure reward.
func launch(at: Vector3) -> void:
	var go := go_color()
	for i: int in 16:
		_spawn(at, _cone(2.6, 2.2) * _rng.randf_range(1.0, 2.0),
			go, _rng.randf_range(0.20, 0.44), 0.04,
			_rng.randf_range(0.34, 0.60), 2.0, 2.0)
	ring(at, go, 14, 7.0, 0.32, 0.46)


## Impact. Hot, wide, and thrown FORWARD past the camera so it fills the frame
## for two frames — a hit the player can miss is a hit they will blame on the
## game.
func impact(at: Vector3, shielded: bool = false) -> void:
	var hue := duck_color() if shielded else hazard_color()
	for i: int in 20:
		var dir := _cone(0.9, 3.4) * _rng.randf_range(1.2, 2.6)
		dir.z += _rng.randf_range(1.0, 5.0)
		_spawn(at, dir, hue, _rng.randf_range(0.20, 0.48), 0.04,
			_rng.randf_range(0.26, 0.52), 2.4, 4.0)
	ring(at, hue.lerp(Color.WHITE, 0.3), 14, 8.5, 0.34, 0.34)
	_spawn(at, Vector3(0, 0, 2.0), hue.lerp(Color.WHITE, 0.5), 0.7, 2.0, 0.2, 3.0, 0.0)


## Passed inside touching distance and got away with it. Two vertical wipes
## flicking past on the side the hazard was: the cheapest possible "that was
## close", and it draws the eye to the gap the player just threaded.
func whoosh(at: Vector3, side: float) -> void:
	var cool := duck_color()
	for i: int in 5:
		var lane_side := signf(side) if absf(side) > 0.01 else 1.0
		_spawn(at + Vector3(lane_side * _rng.randf_range(0.5, 1.1),
				_rng.randf_range(0.15, 1.7), _rng.randf_range(-0.4, 0.4)),
			Vector3(lane_side * _rng.randf_range(1.4, 3.2), 0.4,
				_rng.randf_range(9.0, 15.0)),
			cool, _rng.randf_range(0.16, 0.30), 0.04, 0.22, 0.6, 0.0,
			_rng.randf_range(3.5, 7.0))


## Expanding disc of motes. Used as the contact ring for every landing, hit and
## pickup — one shape, one meaning: "something happened HERE, on the ground".
func ring(at: Vector3, tint: Color, count: int, speed: float,
		size: float, span: float) -> void:
	var phase := _rng.randf_range(0.0, TAU)
	for i: int in count:
		var a := phase + TAU * float(i) / float(maxi(count, 1))
		_spawn(at + Vector3(0, 0.08, 0),
			Vector3(cos(a) * speed, 0.35, sin(a) * speed),
			tint, size, 0.02, span, 2.6, 0.4)


## --- Effects: the continuous emitters ---------------------------------------

## Ground contact. Runs whenever the penguin's feet are down, scaled by pace:
## this is the effect that makes 38 m/s feel different from 15 even on an empty
## stretch of deck, and it is the one the mode never had.
func ground_spray(at: Vector3, pace: float, delta: float, sliding: bool) -> void:
	var rate := (26.0 if sliding else 9.0) * (0.45 + pace)
	_spray_acc += rate * delta
	var snow := snow_color()
	while _spray_acc >= 1.0:
		_spray_acc -= 1.0
		var spread := 0.85 if sliding else 0.35
		var back := _rng.randf_range(3.0, 9.0) * (0.5 + pace) * (1.6 if sliding else 1.0)
		_spawn(at + Vector3(_rng.randf_range(-spread, spread), 0.05,
				_rng.randf_range(-0.15, 0.25)),
			Vector3(_rng.randf_range(-1.6, 1.6) * (1.5 if sliding else 1.0),
				_rng.randf_range(0.9, 2.8) * (0.6 if sliding else 1.0), back),
			snow, _rng.randf_range(0.10, 0.26) * (1.5 if sliding else 1.0), 0.02,
			_rng.randf_range(0.20, 0.42), 2.2, 4.5)


## Ramp arc. A ribbon of launch-green streaming off the penguin for the whole
## flight, so the showpiece of the mode is legible as one continuous event
## rather than as a jump that happened to be long.
func launch_trail(at: Vector3, delta: float) -> void:
	_trail_acc += 38.0 * delta
	var go := go_color()
	while _trail_acc >= 1.0:
		_trail_acc -= 1.0
		_spawn(at + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.2, 0.3),
				_rng.randf_range(-0.2, 0.2)),
			Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.4, 0.6),
				_rng.randf_range(1.0, 3.0)),
			go, _rng.randf_range(0.14, 0.30), 0.02, _rng.randf_range(0.24, 0.44),
			1.6, 1.0)


## Two thin ident-coloured ribbons off the flippers while a power-up is live.
## Constant motion attached to the character, which is the thing the chase
## camera stares at and the thing that currently never moves.
func ribbons(left: Vector3, right: Vector3, tint: Color, delta: float) -> void:
	_ribbon_acc += 34.0 * delta
	while _ribbon_acc >= 1.0:
		_ribbon_acc -= 1.0
		var at := left if _rng.randf() < 0.5 else right
		_spawn(at, Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.5),
				_rng.randf_range(1.4, 3.4)),
			tint, _rng.randf_range(0.10, 0.20), 0.02, _rng.randf_range(0.26, 0.44),
			1.4, 0.6)


## Bright motes tearing past the camera once the run is quick. Peripheral only
## — never across the play strip, where they would compete with the obstacles
## the player is reading.
func speed_motes(centre: Vector3, pace: float, delta: float) -> void:
	if pace <= 0.42:
		return
	var intensity := (pace - 0.42) / 0.58
	_mote_acc += 34.0 * intensity * delta
	var snow := snow_color()
	while _mote_acc >= 1.0:
		_mote_acc -= 1.0
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		_spawn(centre + Vector3(side * _rng.randf_range(2.4, 7.5),
				_rng.randf_range(-0.4, 4.2), _rng.randf_range(-6.0, 2.0)),
			Vector3(side * _rng.randf_range(0.5, 2.0), _rng.randf_range(-0.5, 0.5),
				_rng.randf_range(22.0, 34.0)),
			snow, _rng.randf_range(0.09, 0.20), 0.06,
			_rng.randf_range(0.30, 0.55), 0.4, 0.0, _rng.randf_range(2.0, 4.5))


## --- Integration ------------------------------------------------------------

func tick(delta: float) -> void:
	if _alive <= 0 or multimesh == null:
		_tick_accumulator = 0.0
		return
	_tick_accumulator += delta
	if _tick_accumulator + 0.00001 < UPDATE_INTERVAL:
		return
	var step := _tick_accumulator
	_tick_accumulator = 0.0
	var mm := multimesh
	var park := Basis().scaled(Vector3.ZERO)
	var view_camera := get_viewport().get_camera_3d()
	for i: int in POOL:
		var left := _life[i]
		if left <= 0.0:
			continue
		left -= step
		if left <= 0.0:
			_life[i] = 0.0
			_alive -= 1
			# Park at zero scale rather than leaving a transparent quad behind:
			# an additive alpha-0 billboard still costs its fill every frame.
			mm.set_instance_transform(i, Transform3D(park, _pos[i]))
			mm.set_instance_color(i, Color(0, 0, 0, 0))
			continue
		_life[i] = left
		var vel := _vel[i]
		vel.y -= _grav[i] * step
		vel *= 1.0 - minf(_drag[i] * step, 0.9)
		_vel[i] = vel
		var at := _pos[i] + vel * step
		_pos[i] = at
		var age := 1.0 - left / _span[i]
		var size := lerpf(_size_a[i], _size_b[i], age)
		# Snap to full brightness and decay: a particle that fades UP reads as
		# a light turning on somewhere behind the action.
		var fade := pow(1.0 - age, 1.5)
		var width := size
		var height := size * _aspect[i]
		if view_camera != null:
			# Fast streaks intentionally travel toward the lens. Bound their
			# angular size and fade them at the near plane so no billboard can
			# explode into a full-screen white rectangle as it crosses camera Z.
			var camera_distance := at.distance_to(view_camera.global_position)
			width = minf(width, camera_distance * 0.22)
			height = minf(height, camera_distance * 0.30)
			fade *= smoothstep(0.28, 1.6, camera_distance)
		var tint := _tint[i]
		mm.set_instance_color(i, Color(tint.r, tint.g, tint.b, tint.a * fade))
		mm.set_instance_transform(i, Transform3D(
			Basis().scaled(Vector3(width, height, width)), at))


## Wipes every live particle. Called when a run restarts so the previous run's
## last burst does not hang in the new world.
func clear() -> void:
	if multimesh == null:
		return
	var park := Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	for i: int in POOL:
		_life[i] = 0.0
		multimesh.set_instance_transform(i, park)
		multimesh.set_instance_color(i, Color(0, 0, 0, 0))
	_alive = 0
	_head = 0
	_spray_acc = 0.0
	_trail_acc = 0.0
	_mote_acc = 0.0
	_ribbon_acc = 0.0
	_tick_accumulator = 0.0


## Live particle count, for tests.
func live_count() -> int:
	return _alive
