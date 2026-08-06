class_name PenguinLoader
extends Control
## Dancing-penguin busy indicator, drawn procedurally in 2D.
##
## Every "loading" state in the game shows this instead of a bare label: a row
## of penguins waddling in place, each offset in the dance cycle so the line
## ripples. Pure _draw (ellipses, arcs and polygons) — no 3D viewport, no
## textures, no per-frame allocation beyond the point buffers _draw needs, so
## it stays cheap on the single-threaded web build where it matters most.
##
## Under reduced motion the penguins hold a gentle two-frame sway instead of
## the full bob-and-flap.

const BODY: Color = Color(0.12, 0.16, 0.26)
const BELLY: Color = Color(0.96, 0.98, 1.0)
const BILL: Color = Color(0.98, 0.72, 0.26)
const FOOT: Color = Color(0.95, 0.62, 0.22)
const EYE: Color = Color(0.05, 0.07, 0.12)
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.22)

## Dance cycle length in seconds and the phase step between neighbours.
const CYCLE: float = 0.9
const PHASE_STEP: float = 0.22

var count: int = 3       ## Penguins in the row.
var penguin_size: float = 46.0  ## Height of one penguin in pixels.

var _time: float = 0.0
var _reduced: bool = false


func _init(p_count: int = 3, p_size: float = 46.0) -> void:
	count = maxi(p_count, 1)
	penguin_size = maxf(p_size, 12.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_reduced = UITheme.reduced_motion()
	custom_minimum_size = Vector2(
		penguin_size * 0.86 * float(count) + penguin_size * 0.3,
		penguin_size * 1.25)
	set_process(not GameConfig.is_headless())


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := penguin_size
	var spacing := s * 0.86
	var total := spacing * float(count)
	var base_x := (size.x - total) * 0.5 + spacing * 0.5
	var base_y := size.y * 0.5 + s * 0.42
	for i: int in count:
		var phase := _time / CYCLE * TAU - float(i) * PHASE_STEP * TAU
		_draw_penguin(Vector2(base_x + spacing * float(i), base_y), s, phase)


## One penguin standing on `feet` (its foot line), `s` tall, at dance `phase`.
func _draw_penguin(feet: Vector2, s: float, phase: float) -> void:
	var amp := 0.35 if _reduced else 1.0
	var bob := sin(phase) * s * 0.07 * amp
	var lean := sin(phase * 0.5) * 0.16 * amp
	var flap := sin(phase + PI * 0.5) * 0.7 * amp
	var step := sin(phase)

	var center := feet + Vector2(0.0, -s * 0.5 + bob)

	# Ground shadow tightens as the penguin lifts — sells the hop.
	var shadow_w := s * (0.34 - bob / s * 0.25)
	draw_circle(feet + Vector2(0.0, s * 0.06), maxf(shadow_w, s * 0.14), SHADOW, true, -1.0, true)

	# Feet: the trailing one lifts on each beat.
	var foot_lift := maxf(step, 0.0) * s * 0.09 * amp
	_draw_foot(feet + Vector2(-s * 0.15, -foot_lift), s)
	_draw_foot(feet + Vector2(s * 0.15, -maxf(-step, 0.0) * s * 0.09 * amp), s)

	# Body: an egg leaning into the dance.
	var body_h := s * 0.62
	var body_w := s * 0.42
	_draw_oval(center, Vector2(body_w, body_h), lean, BODY)
	_draw_oval(center + Vector2(0.0, s * 0.06), Vector2(body_w * 0.62, body_h * 0.66), lean, BELLY)

	# Flippers sweep out of the body edges.
	_draw_flipper(center + Vector2(-body_w * 0.86, 0.0), s, -1.0, flap, lean)
	_draw_flipper(center + Vector2(body_w * 0.86, 0.0), s, 1.0, -flap, lean)

	# Head sits on top, tilting with the lean.
	var head := center + Vector2(sin(lean) * s * 0.1, -body_h * 0.78)
	draw_circle(head, s * 0.2, BODY, true, -1.0, true)
	var eye_dx := s * 0.075
	draw_circle(head + Vector2(-eye_dx, -s * 0.03), s * 0.032, BELLY, true, -1.0, true)
	draw_circle(head + Vector2(eye_dx, -s * 0.03), s * 0.032, BELLY, true, -1.0, true)
	draw_circle(head + Vector2(-eye_dx, -s * 0.03), s * 0.018, EYE, true, -1.0, true)
	draw_circle(head + Vector2(eye_dx, -s * 0.03), s * 0.018, EYE, true, -1.0, true)
	var bill := PackedVector2Array([
		head + Vector2(-s * 0.05, s * 0.04),
		head + Vector2(s * 0.05, s * 0.04),
		head + Vector2(0.0, s * 0.14),
	])
	draw_colored_polygon(bill, BILL)


func _draw_foot(at: Vector2, s: float) -> void:
	var w := s * 0.12
	var h := s * 0.05
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-w, 0.0), at + Vector2(w, 0.0), at + Vector2(w * 0.6, -h),
		at + Vector2(-w * 0.6, -h),
	]), FOOT)


## Rotated filled ellipse — draw_circle cannot squash, so the outline is
## sampled into a polygon (16 points reads smooth at indicator sizes).
func _draw_oval(at: Vector2, radii: Vector2, rot: float, color: Color) -> void:
	var pts := PackedVector2Array()
	pts.resize(16)
	var c := cos(rot)
	var sn := sin(rot)
	for i: int in 16:
		var a := TAU * float(i) / 16.0
		var p := Vector2(cos(a) * radii.x, sin(a) * radii.y)
		pts[i] = at + Vector2(p.x * c - p.y * sn, p.x * sn + p.y * c)
	draw_colored_polygon(pts, color)


func _draw_flipper(root: Vector2, s: float, dir: float, swing: float, lean: float) -> void:
	var angle := lean + dir * (0.5 + swing * 0.6)
	var length := s * 0.3
	var tip := root + Vector2(sin(angle) * length * dir, cos(angle) * length)
	var width := s * 0.075
	var normal := (tip - root).normalized().orthogonal() * width
	draw_colored_polygon(PackedVector2Array([
		root + normal, root - normal, tip - normal * 0.35, tip + normal * 0.35,
	]), BODY)
