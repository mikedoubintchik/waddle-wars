class_name PenguinVisual
extends Node3D
## Procedural high-fidelity penguin model with cosmetic attachment points and
## code-driven animation (waddle, slide, swim, stun, celebrate).
## The body is a smooth 48-segment lathe (surface of revolution) with the
## species plumage — dark dorsal, white ventral with a curved side boundary,
## per-species markings (ear patches, gentoo headphone band, chinstrap white
## face) — baked into per-vertex colors, so every variant shares one cheap
## feather ShaderMaterial. Small accessories (eye rings, chin strap, crests) are
## a handful of primitive meshes. Meshes are built once per species+palette
## and cached statically; nothing allocates per frame.
##
## SPECIES holds the eight real-penguin body variants. setup() resolves the
## species from an explicit config "species" id, else from the canonical
## dorsal color (so legacy callers that only forward body_color/belly_color
## still render full species markings), else falls back to Emperor.

enum Pose { RUN, SLIDE, AIR, SWIM, STUN, IDLE, CELEBRATE, DEFEAT }

const BROW_REST: float = -0.1745  # ~-10 deg: relaxed determined slope
## Attacker lunge: short enough to read as a jab, long enough to see at 30 px.
const LUNGE_TIME: float = 0.40
## Victim tumble. Outlasts the racer's own STUMBLE_TIME on purpose -- the
## control lockout ends before the animation does, so the recovery is played
## rather than cut.
const TUMBLE_TIME: float = 1.05
const BODY_SEGS: int = 48         # lathe radial segments (hero-asset smooth)
const FLIPPER_SEGS: int = 16      # blade cross-section segments
const HEAD_Y: float = 0.85        # head-sphere center height (anchor rest)
const FOOT_Y: float = 0.018       # foot rest height
const FOOT_Z: float = 0.014       # foot rest z: heels sit back so they peek past the body from behind
const FOOT_X: float = 0.155       # foot rest half-stance: kicked out past the tapered belly skirt

## The eight playable/AI penguin species. Colors are authored for the
## _tune_dorsal/_saturate pipeline (dark dorsal literals get lifted by scene
## light). "dorsal" values double as the species' canonical lookup key, so
## every entry must keep a unique dorsal color. Optional keys per entry:
##   patch/ear_patch ("emperor"/"king"), chest_wash + chest_wash_amount,
##   eye_ring (bool), headphone (bool), face_white (bool), chinstrap (bool),
##   crest ("rockhopper"/"macaroni") + crest_color, eye_color, foot_color,
##   bill_len/bill_girth/bill_hook/bill_color/mandible_color, scale (Vector3),
##   mantle (Color), ident (Color).
##
## "mantle" is the single most important readability color in this file. Real
## penguins are NOT one dark mass: the head and nape are near-black while the
## back between the shoulders and the rump is a markedly PALER blue-gray. The
## chase camera looks at the dorsal side essentially 100% of the time, so with
## one flat dorsal tone every racer renders as a featureless egg. Baking the
## head/back break in gives three values inside the silhouette -- dark head
## ball, pale back, dark base -- which is what makes it read as a bird at
## 8-30 m. Each species gets its own mantle value AND hue, so the eight racers
## are also distinguishable from each other at that distance.
##
## "ident" is the racer's identity color. It tints the rim light (see
## penguin.gdshader), so who just shoved you is legible from the outline
## alone. Values match PersonalitiesDB accent_color where one exists, so the
## minimap dot and the racer agree.
const SPECIES: Dictionary = {
	"emperor": {
		"name": "Emperor",
		"dorsal": Color(0.13, 0.16, 0.22), "ventral": Color(0.95, 0.94, 0.9),
		"mantle": Color(0.115, 0.135, 0.195), "ident": Color(1.0, 0.84, 0.55),
		"patch": Color(0.98, 0.76, 0.22), "ear_patch": "emperor",
		"chest_wash": Color(1.0, 0.88, 0.55), "chest_wash_amount": 0.20,
		"bill_len": 1.0, "bill_hook": true,
		"bill_color": Color(0.11, 0.11, 0.14),
		"mandible_color": Color(0.96, 0.52, 0.32),  # orange-pink bill stripe
		"scale": Vector3(1.04, 1.06, 1.04),
	},
	"king": {
		"name": "King",
		"dorsal": Color(0.16, 0.18, 0.21), "ventral": Color(0.97, 0.95, 0.90),
		"mantle": Color(0.145, 0.16, 0.20), "ident": Color(0.85, 0.45, 0.85),
		"patch": Color(1.0, 0.50, 0.06), "ear_patch": "king",
		"chest_wash": Color(1.0, 0.62, 0.12), "chest_wash_amount": 0.40,
		"bill_len": 1.0, "bill_hook": true,
		"mandible_color": Color(0.96, 0.55, 0.16),
		"scale": Vector3(0.94, 1.02, 0.94),
	},
	"adelie": {
		"name": "Adelie",
		"dorsal": Color(0.06, 0.06, 0.07), "ventral": Color(0.97, 0.97, 0.96),
		"mantle": Color(0.07, 0.075, 0.105), "ident": Color(0.72, 0.55, 0.30),
		"eye_ring": true,
		"bill_len": 0.62, "bill_girth": 1.12,
		"bill_color": Color(0.13, 0.11, 0.12), "mandible_color": Color(0.16, 0.13, 0.14),
		"foot_color": Color(0.93, 0.74, 0.70),
		"scale": Vector3(0.94, 0.92, 0.94),
	},
	"gentoo": {
		"name": "Gentoo",
		"dorsal": Color(0.10, 0.11, 0.13), "ventral": Color(0.96, 0.96, 0.95),
		"mantle": Color(0.095, 0.125, 0.185), "ident": Color(0.30, 0.62, 0.92),
		"headphone": true,
		"bill_len": 0.85,
		"bill_color": Color(0.95, 0.44, 0.10), "mandible_color": Color(0.85, 0.36, 0.10),
		"foot_color": Color(1.0, 0.58, 0.12),
		"scale": Vector3(0.99, 1.0, 0.99),
	},
	"chinstrap": {
		"name": "Chinstrap",
		"dorsal": Color(0.12, 0.13, 0.15), "ventral": Color(0.97, 0.96, 0.94),
		"mantle": Color(0.13, 0.15, 0.21), "ident": Color(0.94, 0.30, 0.34),
		"face_white": true, "chinstrap": true,
		"bill_len": 0.78,
		"bill_color": Color(0.10, 0.10, 0.12), "mandible_color": Color(0.13, 0.12, 0.14),
		"foot_color": Color(0.93, 0.63, 0.52),
		"scale": Vector3(0.95, 0.94, 0.95),
	},
	"rockhopper": {
		"name": "Rockhopper",
		"dorsal": Color(0.16, 0.14, 0.13), "ventral": Color(0.98, 0.95, 0.86),
		"mantle": Color(0.15, 0.13, 0.115), "ident": Color(0.98, 0.76, 0.20),
		"crest": "rockhopper", "crest_color": Color(0.98, 0.82, 0.2),
		"eye_color": Color(0.50, 0.15, 0.10),
		"bill_len": 0.80, "bill_girth": 1.1,
		"bill_color": Color(0.72, 0.35, 0.18), "mandible_color": Color(0.62, 0.28, 0.15),
		"foot_color": Color(0.95, 0.62, 0.55),
		"scale": Vector3(0.90, 0.85, 0.90),
	},
	"macaroni": {
		"name": "Macaroni",
		"dorsal": Color(0.13, 0.11, 0.10), "ventral": Color(0.97, 0.94, 0.88),
		"mantle": Color(0.115, 0.10, 0.115), "ident": Color(0.32, 0.88, 0.52),
		"crest": "macaroni", "crest_color": Color(0.99, 0.66, 0.10),
		"eye_color": Color(0.55, 0.17, 0.10),
		"bill_len": 0.92, "bill_girth": 1.15,
		"bill_color": Color(0.78, 0.40, 0.18), "mandible_color": Color(0.66, 0.30, 0.15),
		"foot_color": Color(0.95, 0.60, 0.50),
		"scale": Vector3(0.98, 0.95, 0.98),
	},
	"little_blue": {
		"name": "Little Blue",
		"dorsal": Color(0.45, 0.53, 0.62), "ventral": Color(0.96, 0.97, 0.97),
		"mantle": Color(0.30, 0.36, 0.47), "ident": Color(0.40, 0.92, 0.86),
		"bill_len": 0.72,
		"bill_color": Color(0.28, 0.33, 0.40), "mandible_color": Color(0.45, 0.50, 0.56),
		"foot_color": Color(0.90, 0.80, 0.72),
		"scale": Vector3(0.76, 0.73, 0.76),
	},
}

const PLUMAGE_SHADER_PATH: String = "res://assets/shaders/penguin.gdshader"
const IDENT_DEFAULT: Color = Color(0.64, 0.79, 1.0)

static var _material_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _species_by_dorsal: Dictionary = {}  # canonical dorsal html -> id
static var _bill_shader: Shader = null  # shared by all bill materials
static var _plumage_shader: Shader = null  # shared by every plumage material

var pose: Pose = Pose.IDLE
var anim_speed: float = 1.0

var _ident: Color = IDENT_DEFAULT  # per-racer rim identity, resolved in setup()

var _scale_root: Node3D  # static per-species proportions wrapper
var _root: Node3D  # animated body root (bobs / tilts)
var _body: MeshInstance3D
var _flipper_l: Node3D
var _flipper_r: Node3D
var _foot_l: MeshInstance3D
var _foot_r: MeshInstance3D
var _head_anchor: Node3D
var _beak: MeshInstance3D
var _beak_lower: MeshInstance3D
var _eye_l: Node3D
var _eye_r: Node3D
var _brow_l: MeshInstance3D
var _brow_r: MeshInstance3D
var _hat_anchor: Node3D
var _neck_anchor: Node3D
var _face_anchor: Node3D
var _time: float = 0.0
var _pose_blend: float = 0.0
var _current_tilt: Vector3 = Vector3.ZERO
var _base_pos: Vector2 = Vector2.ZERO   # smoothed _root x/y before waddle offsets
var _head_rot: Vector3 = Vector3.ZERO   # smoothed head rotation before waddle counter-terms
var _waddle: float = 0.0                # RUN-gait weight; eases the waddle in/out on pose changes
var _squash: float = 1.0
## Shove impulses. Both are elapsed-time cursors: a trigger sets them to 0.0,
## tick() advances them and drives a one-shot envelope, and they park at -1.0
## when spent. Kept as envelopes layered onto the running pose rather than as
## poses of their own, so a shove never interrupts a slide or a jump.
var _lunge_t: float = -1.0
var _tumble_t: float = -1.0
var _tumble_dir: float = 1.0
# Low-passed applied gait values (~14/s): the waddle oscillators are pure
# sines, but filtering the final applied values guarantees C1-smooth motion
# across pose/speed changes — nothing ever snaps.
var _gait_roll: float = 0.0
var _gait_yaw: float = 0.0
var _gait_sway: float = 0.0
var _gait_bob: float = 0.0
var _head_osc: Vector3 = Vector3.ZERO   # smoothed head counter-osc: x yaw, y roll, z bob
var _lean: float = 0.0                  # smoothed body roll read back off this node (turn lean)
var _foot_pos_l: Vector3 = Vector3(-FOOT_X, FOOT_Y, FOOT_Z)
var _foot_pos_r: Vector3 = Vector3(FOOT_X, FOOT_Y, FOOT_Z)
var _foot_rot_l: Vector2 = Vector2.ZERO  # x: ankle pitch, y: ankle roll
var _foot_rot_r: Vector2 = Vector2.ZERO


## Resolves which species a setup() config describes. Priority: explicit
## "species" id -> canonical dorsal-color match (legacy callers only forward
## body_color/belly_color, and the cosmetics/personalities DBs use the
## canonical palettes) -> legacy crest configs read as Rockhopper -> Emperor.
## Unknown/custom palettes keep their colors but get Emperor markings, which
## matches the pre-species rendering for old saves.
static func resolve_species_id(config: Dictionary) -> String:
	var explicit := String(config.get("species", ""))
	if SPECIES.has(explicit):
		return explicit
	if _species_by_dorsal.is_empty():
		for sid: String in SPECIES.keys():
			_species_by_dorsal[(SPECIES[sid]["dorsal"] as Color).to_html(false)] = sid
	var dorsal := config.get("body_color", SPECIES["emperor"]["dorsal"]) as Color
	var matched := String(_species_by_dorsal.get(dorsal.to_html(false), ""))
	if matched != "":
		return matched
	return "rockhopper" if config.has("crest_color") else "emperor"


static func get_material(color: Color, metallic: float = 0.0, roughness: float = 0.75, emissive: bool = false) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [color.to_html(), metallic, roughness, emissive]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	_material_cache[key] = mat
	return mat


## Body/feather material: a faint rim kiss so the silhouette separates from
## snow without lifting overall value. Rim is kept weak and albedo-tinted —
## strong white rim washed the racers gray under the bright glacier ambient.
## Retained as public API; the penguin's own solid plumage parts now use
## _get_plumage_tinted() instead so they share the body's countershading and
## distance-adaptive rim rather than reading as flat patches beside it.
static func get_body_material(color: Color, roughness: float = 0.68, rim: float = 0.11) -> StandardMaterial3D:
	var key := "body_%s_%s_%s" % [color.to_html(), roughness, rim]
	if _material_cache.has(key):
		return _material_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = roughness
	mat.rim_enabled = true
	mat.rim = rim
	mat.rim_tint = 0.7
	_material_cache[key] = mat
	return mat


## Shared feather material for all vertex-colored penguin meshes (body,
## flippers, feet). The baked vertex colors carry the palette and the head /
## mantle / rump value break, so ONE compiled program covers every variant.
## Cached per identity color, so a full grid of eight racers costs eight
## ShaderMaterials over a single Shader — same program, different uniform
## buffer, so they still batch and the whole treatment is pure fragment ALU.
##
## The shader itself lives in assets/shaders/penguin.gdshader; the reasoning
## for each of its layers (form, dual-polarity edge, feather structure, sheen,
## identity rim) is documented at the top of that file.
static func _get_plumage_material(ident: Color = IDENT_DEFAULT, edge_gain: float = 1.0) -> Material:
	var key := "penguin_plumage_%s_%.2f" % [ident.to_html(false), edge_gain]
	if _material_cache.has(key):
		return _material_cache[key]
	if _plumage_shader == null:
		_plumage_shader = load(PLUMAGE_SHADER_PATH) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _plumage_shader
	mat.set_shader_parameter("ident", ident)
	if not is_equal_approx(edge_gain, 1.0):
		mat.set_shader_parameter("edge_gain", edge_gain)
	_material_cache[key] = mat
	return mat


## Solid-color variant of the plumage material for the parts that carry no
## vertex colors (tail wedge, shoulder mounds, brow ridges, crest quills).
## Same Shader object -> same compiled program -> they batch with the body and
## pick up the identical countershading + rim, so no flat patch breaks the
## form. Cached per color + identity; there are only ~a dozen distinct ones
## across all eight species.
static func _get_plumage_tinted(color: Color, ident: Color = IDENT_DEFAULT, edge_gain: float = 1.0) -> Material:
	var key := "plumage_tint_%s_%s_%.2f" % [color.to_html(false), ident.to_html(false), edge_gain]
	if _material_cache.has(key):
		return _material_cache[key]
	if _plumage_shader == null:
		_plumage_shader = load(PLUMAGE_SHADER_PATH) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _plumage_shader
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("ident", ident)
	if not is_equal_approx(edge_gain, 1.0):
		mat.set_shader_parameter("edge_gain", edge_gain)
	_material_cache[key] = mat
	return mat


## Bill keratin material: glossy sheath with a warm subsurface flush at the
## base where the bill meets the face (light bleeding through thin keratin),
## fading out toward the tip. grad_lo/grad_hi bound the flush in mesh-local Y
## (a CylinderMesh runs -height/2 at the base to +height/2 at the tip).
## Cached per color pair + gradient; the Shader object itself is shared.
static func _get_bill_material(base: Color, warm: Color, grad_lo: float, grad_hi: float, gloss: float) -> Material:
	var key := "bill_%s_%s_%.3f_%.3f_%.2f" % [base.to_html(false), warm.to_html(false), grad_lo, grad_hi, gloss]
	if _material_cache.has(key):
		return _material_cache[key]
	if _bill_shader == null:
		_bill_shader = Shader.new()
		_bill_shader.code = """
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform vec4 warm_color : source_color = vec4(0.9, 0.5, 0.4, 1.0);
uniform float grad_lo = -0.08;
uniform float grad_hi = -0.01;
uniform float gloss = 0.22;

varying float v_y;

void vertex() {
	v_y = VERTEX.y;
}

void fragment() {
	// Subsurface warm flush at the bill base, gone by mid-length.
	float warm = 1.0 - smoothstep(grad_lo, grad_hi, v_y);
	vec3 col = mix(base_color.rgb, warm_color.rgb, warm * 0.55);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 4.0);
	ALBEDO = col;
	// Faint light bleed at the flush + wet keratin edge sheen.
	EMISSION = warm_color.rgb * warm * 0.03 + col * fres * 0.10;
	ROUGHNESS = gloss;
	SPECULAR = 0.62;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _bill_shader
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("warm_color", warm)
	mat.set_shader_parameter("grad_lo", grad_lo)
	mat.set_shader_parameter("grad_hi", grad_hi)
	mat.set_shader_parameter("gloss", gloss)
	_material_cache[key] = mat
	return mat


## Nudges saturation/value up so racer colors pop against the pale course.
## Used for belly / patch / crest accents — NOT for the dorsal base (see
## _tune_dorsal), which needs the opposite treatment.
static func _saturate(color: Color) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(color.s * 1.28, 0.0, 0.95),
		clampf(color.v * 1.05, 0.0, 1.0),
		color.a
	)


## Dorsal base tuning. Config body colors are authored against the soft
## customize-preview light; on course the bright glacier ambient + ACES
## tonemap lift the same values toward gray, and warm iceberg light turns
## them muddy brown-olive. Drop value hard (classic navy lands near-black,
## ~Color(0.05, 0.07, 0.11)) so scene lighting raises it back to the
## intended tone, and push saturation so the hue identity survives warm
## light instead of desaturating to mud. Hue is never shifted.
static func _tune_dorsal(color: Color) -> Color:
	return Color.from_hsv(
		color.h,
		clampf(color.s * 1.45, 0.0, 0.95),
		clampf(color.v * 0.46, 0.035, 0.28),
		color.a
	)


## The paler back tone that sits between the near-black head/nape and the
## darker rump. Takes the species' authored mantle VALUE (that spread is the
## per-racer field mark that makes eight racers distinguishable at 20 m) but
## re-hues it toward whatever dorsal the config actually asked for, so custom
## and legacy palettes keep their own color instead of snapping to the
## species'. See the SPECIES doc comment for why this exists at all.
static func _mantle_for(dorsal: Color, sp: Dictionary) -> Color:
	var m := sp.get("mantle", Color(0.20, 0.24, 0.32)) as Color
	return Color.from_hsv(
		dorsal.h,
		clampf(m.s * 0.65 + dorsal.s * 0.30, 0.0, 0.78),
		m.v,
		1.0
	)


## Per-racer identity color, used to tint the silhouette rim. Explicit config
## accent wins (nothing forwards one today, but the plumbing costs nothing),
## then the species entry, then a neutral skylight blue.
static func _ident_for(config: Dictionary, sp: Dictionary) -> Color:
	var c := config.get("accent_color", sp.get("ident", IDENT_DEFAULT)) as Color
	# Rim tints must stay bright or they read as dirt on the edge rather than
	# light; saturation is capped so no racer gets a neon outline.
	return Color.from_hsv(c.h, clampf(c.s, 0.0, 0.85), clampf(c.v, 0.55, 1.0), 1.0)


func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, mat: Material = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat if mat != null else get_material(color)
	instance.position = pos
	instance.rotation = rot
	instance.scale = scl
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(instance)
	return instance


## _mesh variant for tiny detail props (eye parts, catchlights, crest quills):
## their shadows are invisible at gameplay scale, so casting is disabled to
## keep the shadow pass cheap across 8 racers.
func _prop(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, mat: Material = null) -> MeshInstance3D:
	var instance := _mesh(parent, mesh, color, pos, rot, scl, mat)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## --- Procedural mesh construction -------------------------------------------

## Catmull-Rom point on the segment p1..p2.
static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return (p1 * 2.0 + (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) * 0.5


## Samples a smooth curve through the control points (subdiv points per span).
static func _sample_profile(ctrl: Array[Vector2], subdiv: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in ctrl.size() - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
		for s: int in subdiv:
			out.append(_catmull(p0, p1, p2, p3, float(s) / float(subdiv)))
	out.append(ctrl[ctrl.size() - 1])
	return out


## Stitches equal-length vertex rings into a smooth-shaded tube. Rings must
## advance along the surface; each ring loop must run clockwise when viewed
## from the direction the rings advance toward (Godot front faces wind CW).
## Shared grid vertices carry identical color, so generate_normals() averages
## them into smooth normals.
static func _grid_mesh(rings: Array[PackedVector3Array], colors: Array[PackedColorArray]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var n := rings[0].size()
	for j: int in rings.size() - 1:
		var ra := rings[j]
		var rb := rings[j + 1]
		var ca := colors[j]
		var cb := colors[j + 1]
		for i: int in n:
			var i2 := (i + 1) % n
			# Quad (a=low i, b=low i+1, c=high i+1, d=high i), CW from outside.
			st.set_color(ca[i]); st.add_vertex(ra[i])
			st.set_color(ca[i2]); st.add_vertex(ra[i2])
			st.set_color(cb[i2]); st.add_vertex(rb[i2])
			st.set_color(ca[i]); st.add_vertex(ra[i])
			st.set_color(cb[i2]); st.add_vertex(rb[i2])
			st.set_color(cb[i]); st.add_vertex(rb[i])
	st.generate_normals()
	st.index()
	return st.commit()


## Deterministic feather-grain jitter (+-1% value) for material richness.
## Kept faint on purpose: invisible beyond ~5 m, a subtle texture up close —
## the previous +-3.5% read as gray speckle on distant racers.
static func _grain(col: Color, pos: Vector3) -> Color:
	var n := sin(pos.x * 47.0 + pos.y * 89.0 + pos.z * 61.0) * 0.5 \
		+ sin(pos.y * 173.0 + pos.x * 31.0 - pos.z * 23.0) * 0.5
	var k := 1.0 + n * 0.010
	return Color(clampf(col.r * k, 0.0, 1.0), clampf(col.g * k, 0.0, 1.0), clampf(col.b * k, 0.0, 1.0), 1.0)


## Plumage color at a lathe vertex. theta_deg: 0 at the front (-Z), 180 back.
## sp is a SPECIES entry: it selects the ventral boundary curve and which
## vertex-color markings (ear patch, chest wash, headphone band) are baked.
static func _plumage_at(y: float, theta_deg: float, pos: Vector3, dorsal: Color, ventral: Color, patch: Color, mantle: Color, sp: Dictionary) -> Color:
	# MANTLE BREAK — the load-bearing readability feature of the whole model.
	# A real penguin's back is a distinctly paler blue-gray than its near-black
	# head and nape; the rump darkens off again toward the tail. Baking that in
	# gives three values stacked up the silhouette (dark head ball / pale back /
	# dark base) instead of the single flat tone that made every racer render as
	# a featureless egg from the chase camera. It is also where per-racer color
	# identity lives: each species carries its own mantle hue and value, so you
	# can tell the eight of them apart at 20 m.
	# Mantle closes at the shoulder (0.58..0.74, was 0.62..0.86): the old window
	# let the paler back tone climb the nape, which put a grey halo behind the
	# ear patch. A real emperor's head and nape are solid black down past the
	# patch; the pale back starts below the shoulders.
	var mant := smoothstep(0.14, 0.38, y) * (1.0 - smoothstep(0.58, 0.74, y))
	var dors := dorsal.lerp(mantle, mant)
	# Along-length countershading, cut to a third of its old strength. The old
	# 0.40 lift baked a pale wash into the upper back -- painted light, and the
	# single biggest reason the bird read as a powder-blue toy instead of a
	# black-backed penguin. The satin specular in the shader now carries the
	# top-light; the albedo stays feather-dark.
	var sheen := clampf((y - 0.28) / 0.72, 0.0, 1.0) * 0.13
	dors = dors.lerp(dors.lightened(0.06), sheen)
	# Structural-color hint: head/neck feathers pick up a faint cool
	# green-blue cast where the surface grazes the light (the sides) — a
	# cheap baked stand-in for feather iridescence. Kept subtle so the head
	# still reads dark at race distance.
	var irid := clampf((y - 0.70) / 0.25, 0.0, 1.0) \
		* pow(sin(deg_to_rad(clampf(theta_deg, 0.0, 180.0))), 2.0)
	if irid > 0.0:
		var cool := Color(
			clampf(dors.r * 0.92, 0.0, 1.0),
			clampf(dors.g * 1.06 + 0.008, 0.0, 1.0),
			clampf(dors.b * 1.22 + 0.015, 0.0, 1.0),
			1.0)
		dors = dors.lerp(cool, irid * 0.45)
	# Ventral half-angle: wide across the belly, narrowing up the neck. The
	# default closes above the chin so the head reads fully dark; chinstrap
	# ("face_white") instead keeps a white face and cheeks with a dark cap
	# and nape, which is where its strap accessory reads against white.
	#
	# The belly limit runs to 84 deg rather than the anatomically tidier 76,
	# which widens the white front on three-quarter views (overtakes, the grid,
	# results) without touching the silhouette. It was tried at 96 to get a
	# white sliver visible from DIRECTLY behind, and that does not work at any
	# value: near the silhouette the lathe is foreshortened so hard that the
	# last several degrees of arc are under a pixel wide. Read from directly
	# behind has to come from the head/mantle/rump value stack and the limbs,
	# not from the belly.
	var limit: float
	if bool(sp.get("face_white", false)):
		if y < 0.50:
			limit = 84.0
		elif y < 0.68:
			limit = lerpf(84.0, 98.0, (y - 0.50) / 0.18)
		elif y < 0.90:
			limit = lerpf(100.0, 118.0, (y - 0.68) / 0.22)
		elif y < 0.955:
			limit = lerpf(118.0, 8.0, (y - 0.90) / 0.055)
		else:
			limit = -1.0
	else:
		if y < 0.50:
			limit = 84.0
		elif y < 0.72:
			limit = lerpf(84.0, 52.0, (y - 0.50) / 0.22)
		elif y < 0.815:
			limit = lerpf(52.0, 12.0, (y - 0.72) / 0.095)
		else:
			limit = -1.0
	var col := dors
	if limit > 0.0:
		# Irregular feather edge: the boundary meanders a couple of degrees
		# with height so it reads as overlapping feather rows, not a painted
		# stripe, and the blend band is widened into a soft ~1-2 cm feather
		# transition instead of a hard color seam.
		# Tightened from +-8 deg to +-3.5: the flank line on a real penguin is
		# razor-crisp -- the wide soft blend read as an airbrushed gradient and
		# was half of the "blob" complaint. The meander is slightly stronger so
		# the crisp line still scallops like overlapping feather rows.
		var edge := limit + sin(y * 57.0) * 2.2 + sin(y * 23.0) * 1.4
		var w := 1.0 - smoothstep(edge - 3.5, edge + 3.5, theta_deg)
		# The white shades faintly cooler where it wraps toward the sides.
		# Halved from 0.16: with the countershading band narrowed in the
		# shader, the old darkening left the whole flank of the belly grey.
		var vent := ventral.lerp(ventral.darkened(0.08), clampf(theta_deg / 90.0, 0.0, 1.0))
		col = dors.lerp(vent, w)
		var wash_amount := float(sp.get("chest_wash_amount", 0.0))
		if wash_amount > 0.0:
			# Warm wash on the upper chest (emperor subtle, king vivid).
			var chest := clampf((y - 0.58) / 0.22, 0.0, 1.0) * w
			col = col.lerp(sp.get("chest_wash", Color(1.0, 0.88, 0.55)) as Color, chest * wash_amount)
	match String(sp.get("ear_patch", "")):
		"emperor":
			# Auricular patch: ONE tilted golden teardrop behind the eye,
			# swept down-and-forward toward the throat. Built in a rotated
			# ellipse frame rather than as two stacked gaussians -- the
			# two-lobe version printed as a pair of yellow dots with a gap,
			# which no emperor has ever worn.
			var pu := (theta_deg - 112.0) / 22.0
			var pv := (y - 0.798) / 0.085
			# ~34 deg tilt: patch long axis runs down toward the gape.
			var ru := pu * 0.83 - pv * 0.56
			var rv := pu * 0.56 + pv * 0.83
			# Teardrop: fatter at the top (behind the eye), tapering along the
			# swept axis toward the throat.
			var d := sqrt(ru * ru * (1.0 + maxf(-rv, 0.0) * 1.6) + rv * rv * 0.55)
			var pm := 1.0 - smoothstep(0.58, 0.92, d)
			if pm > 0.0:
				col = col.lerp(patch, pm * 0.96)
				# Hot saturated core so the patch glows against the cap.
				var core := 1.0 - smoothstep(0.0, 0.50, d)
				col = col.lerp(patch.lightened(0.18), core * 0.45)
		"king":
			# Slimmer teardrop: tight ellipse behind the eye tapering forward
			# and down toward the throat, more saturated than emperor.
			var du := (theta_deg - 106.0) / 20.0
			var dv := (y - 0.85) / 0.055
			var pm := 1.0 - smoothstep(0.30, 1.0, sqrt(du * du + dv * dv))
			var du2 := (theta_deg - 80.0) / 13.0
			var dv2 := (y - 0.78) / 0.05
			pm = maxf(pm, (1.0 - smoothstep(0.15, 1.0, sqrt(du2 * du2 + dv2 * dv2))) * 0.85)
			if pm > 0.0:
				col = col.lerp(patch, pm * 0.95)
			# Real kings carry a crisp near-black hairline separating the
			# orange patch from the surrounding plumage — invisible against
			# the dark cap, a sharp defining line where it meets the throat.
			var d_edge := sqrt(du * du + dv * dv)
			var border := smoothstep(0.82, 1.04, d_edge) * (1.0 - smoothstep(1.04, 1.38, d_edge))
			if border > 0.0:
				col = col.lerp(Color(0.05, 0.05, 0.07), border * 0.5)
	if bool(sp.get("headphone", false)):
		# Gentoo: white band from above each eye bridging over the crown.
		# The theta window widens with height so the two side patches merge
		# across the top while the forehead and nape stay dark.
		var k := smoothstep(0.895, 0.960, y)
		var lo := lerpf(56.0, 28.0, k)
		var hi := lerpf(114.0, 152.0, k)
		var wy := smoothstep(0.845, 0.882, y) * (1.0 - smoothstep(0.958, 0.992, y))
		var wt := smoothstep(lo - 8.0, lo + 6.0, theta_deg) * (1.0 - smoothstep(hi - 6.0, hi + 8.0, theta_deg))
		var band := wy * wt
		if band > 0.0:
			col = col.lerp(ventral, band)
		# Crown speckling: sparse white flecks scattered over the dark crown
		# above the band — the gentoo's second field mark after the patch.
		if y > 0.90 and band < 0.35:
			var spk := clampf((sin(pos.x * 210.0 + pos.z * 170.0) \
				* sin(pos.z * 190.0 - pos.x * 140.0 + y * 90.0) - 0.82) / 0.18, 0.0, 1.0)
			col = col.lerp(ventral.darkened(0.08), spk * 0.55)
	# Baked ambient-occlusion fakes. These are the cheapest readability tool
	# there is (zero runtime cost, they ship inside the cached mesh) and they
	# do most of the work of turning the silhouette into separate parts:
	#   * flipper-root / shoulder crease (theta ~92 deg, y ~0.585 matches the
	#     pivot at x 0.24 / y 0.60),
	#   * a neck crease at y ~0.75 — the single most valuable one, because
	#     from the chase camera it is what separates the head ball from the
	#     body mass instead of one continuous dark egg,
	#   * a grounding gradient under the belly skirt, deepened so the body
	#     sits INTO the snow with contact weight instead of floating on it.
	# Applied before grain so the darkening stays feathered.
	var du_f := (theta_deg - 92.0) / 26.0
	var dv_f := (y - 0.585) / 0.10
	var ao := exp(-(du_f * du_f + dv_f * dv_f)) * 0.22
	var dn := (y - 0.755) / 0.058
	ao += exp(-dn * dn) * 0.24
	ao += (1.0 - smoothstep(0.03, 0.22, y)) * 0.26
	if ao > 0.003:
		col = col.darkened(minf(ao, 0.46))
	return _grain(col, pos)


## Body + head as one continuous 48-segment lathe: rounded head, slight neck
## taper, plump teardrop torso widest below middle. The head rings shift
## forward slightly for posture. Cached per species + palette.
static func _build_body_mesh(species_id: String, dorsal: Color, ventral: Color, patch: Color, mantle: Color) -> ArrayMesh:
	var key := "pbody_%s_%s_%s_%s_%s" % [species_id, dorsal.to_html(false), ventral.to_html(false), patch.to_html(false), mantle.to_html(false)]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var sp: Dictionary = SPECIES[species_id]
	# Fusiform, not egg. The old profile was widest at y 0.28 and ballooned to
	# 0.358, which is a bowling pin; a real emperor is a streamlined spindle --
	# fullest through the lower chest, carrying its width up through the breast,
	# with a longer, shallower neck into a slightly smaller head. The chase
	# camera still needs the neck pinch (it is what separates head from body at
	# 40 m), so it stays, just longer and less abrupt.
	var ctrl: Array[Vector2] = [
		Vector2(0.000, 0.030),
		Vector2(0.015, 0.092),
		Vector2(0.050, 0.168),
		Vector2(0.110, 0.242),
		Vector2(0.190, 0.300),
		Vector2(0.290, 0.336),  # widest: lower chest, not the skirt
		Vector2(0.400, 0.330),
		Vector2(0.500, 0.313),  # breast stays full through the middle
		Vector2(0.600, 0.281),
		Vector2(0.680, 0.241),
		Vector2(0.740, 0.202),
		Vector2(0.783, 0.184),  # neck pinch: longer and shallower
		Vector2(0.822, 0.196),
		Vector2(0.865, 0.212),
		Vector2(0.910, 0.198),
		Vector2(0.945, 0.162),
		Vector2(0.972, 0.115),
		Vector2(0.990, 0.060),
		Vector2(1.000, 0.006),  # crown
	]
	var profile := _sample_profile(ctrl, 2)
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	for p: Vector2 in profile:
		var y := p.x
		var r := maxf(p.y, 0.004)
		var cz := -maxf(0.0, y - 0.66) * 0.20  # head carried forward of the chest line
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		for i: int in BODY_SEGS:
			var ang := TAU * float(i) / float(BODY_SEGS)
			var pos := Vector3(sin(ang) * r, y, cz - cos(ang) * r)
			ring.append(pos)
			var theta := absf(rad_to_deg(wrapf(ang, -PI, PI)))
			col.append(_plumage_at(y, theta, pos, dorsal, ventral, patch, mantle, sp))
		rings.append(ring)
		colors.append(col)
	var mesh := _grid_mesh(rings, colors)
	_mesh_cache[key] = mesh
	return mesh


## Flat tapered flipper blade: elliptical cross-section tube along -Y with a
## dark outer face (+X), white inner face, a darkened leading edge and a pale
## trailing-edge border (the signature white rim of real penguin flippers).
## The left side reuses this mesh rotated PI around Y; that yaw swaps the Z
## edges, so flip mirrors the edge tinting (geometry stays Z-symmetric).
static func _build_flipper_mesh(dorsal: Color, ventral: Color, flip: float = 1.0) -> ArrayMesh:
	var key := "pflip_%s_%s_%d" % [dorsal.to_html(false), ventral.to_html(false), int(signf(flip))]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var rows := 14
	# Longer, slimmer blade: real emperor flippers reach past the mid-thigh.
	# The stubby 0.46 paddle read as a decorative flap; the extra length also
	# gives the swing animation a real arc to sell.
	var length := 0.56
	var inner := ventral.darkened(0.05)
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	for j: int in rows + 1:
		var t := float(j) / float(rows)
		var y := 0.03 - (length + 0.03) * t  # root buried in the shoulder
		var half_w: float
		if t < 0.35:
			half_w = lerpf(0.060, 0.084, t / 0.35)
		else:
			half_w = lerpf(0.084, 0.012, pow((t - 0.35) / 0.65, 1.25))
		var half_th := lerpf(0.036, 0.010, t)
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		for i: int in FLIPPER_SEGS:
			var phi := TAU * float(i) / float(FLIPPER_SEGS)
			var pos := Vector3(cos(phi) * half_th, y, -sin(phi) * half_w)
			ring.append(pos)
			var facing := cos(phi)  # +1 outer face, -1 inner face
			var c := inner.lerp(dorsal, smoothstep(-0.45, 0.45, facing))
			var edge_k := 1.0 - absf(facing)
			# lead > 0 is the forward (-Z world) edge once flip mirrors the
			# left blade: dark leading edge, pale trailing-edge border.
			var lead := sin(phi) * flip
			if lead > 0.0:
				c = c.lerp(dorsal.darkened(0.25), edge_k * 0.45)
			else:
				c = c.lerp(ventral, edge_k * 0.30)
			col.append(_grain(c, pos + Vector3(0.7, 0.0, 0.0)))
		rings.append(ring)
		colors.append(col)
	# Rounded tip: collapse to a point just past the last ring.
	var tip := PackedVector3Array()
	var tip_col := PackedColorArray()
	for i: int in FLIPPER_SEGS:
		tip.append(Vector3(0.0, 0.03 - length - 0.045, 0.0))
		tip_col.append(dorsal)
	rings.append(tip)
	colors.append(tip_col)
	var mesh := _grid_mesh(rings, colors)
	_mesh_cache[key] = mesh
	return mesh


## Webbed foot: a closed low tube from a heel point to a scalloped front edge
## with three toe ridges on top and darkened webbing between them. Shared by
## both feet (mirrored placement handled by yaw only; the mesh is symmetric).
## base tints per species (gentoo bright orange, little blue pale flesh).
static func _build_foot_mesh(base: Color) -> ArrayMesh:
	var key := "pfoot_" + base.to_html(false)
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cols_across := 9
	var rows := 8
	var sole := base.darkened(0.32)
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	# Heel: collapsed starting ring.
	var heel_ring := PackedVector3Array()
	var heel_col := PackedColorArray()
	for i: int in cols_across * 2:
		heel_ring.append(Vector3(0.0, 0.014, 0.065))
		heel_col.append(base.darkened(0.12))
	rings.append(heel_ring)
	colors.append(heel_col)
	for j: int in rows + 1:
		var t := float(j) / float(rows)
		var w := 0.022 + 0.062 * smoothstep(0.0, 1.0, t)
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		# Top surface: s runs +1 -> -1 (CW loop viewed from the toes).
		for c: int in cols_across:
			var s := 1.0 - 2.0 * float(c) / float(cols_across - 1)
			var toe := 0.5 + 0.5 * cos(3.0 * PI * s)  # peaks at the 3 toes
			var ext := 0.045 * toe * clampf((t - 0.65) / 0.35, 0.0, 1.0)
			var pos := Vector3(
				s * w,
				0.008 + 0.022 * (1.0 - t) * (1.0 - t) + 0.014 * toe * clampf(t * 1.3, 0.0, 1.0),
				0.06 - 0.16 * t - ext
			)
			ring.append(pos)
			var c_top := base.darkened(0.2 * (1.0 - toe) * t)  # web valleys
			col.append(_grain(c_top, pos * 6.0))
		# Sole: s runs -1 -> +1 to close the loop.
		for c: int in cols_across:
			var s := -1.0 + 2.0 * float(c) / float(cols_across - 1)
			var toe := 0.5 + 0.5 * cos(3.0 * PI * s)
			var ext := 0.045 * toe * clampf((t - 0.65) / 0.35, 0.0, 1.0)
			var pos := Vector3(s * w, 0.003, 0.06 - 0.16 * t - ext)
			ring.append(pos)
			col.append(sole)
		rings.append(ring)
		colors.append(col)
	# Front edge: pinch top to sole slightly ahead of the last row so the
	# webbed rim closes as a thin forward bevel instead of a vertical wall.
	var edge_ring := PackedVector3Array()
	var edge_col := PackedColorArray()
	for c: int in cols_across:
		var s := 1.0 - 2.0 * float(c) / float(cols_across - 1)
		var toe := 0.5 + 0.5 * cos(3.0 * PI * s)
		edge_ring.append(Vector3(s * 0.084, 0.005, 0.06 - 0.168 - 0.045 * toe))
		edge_col.append(base.darkened(0.1))
	for c: int in cols_across:
		var s := -1.0 + 2.0 * float(c) / float(cols_across - 1)
		var toe := 0.5 + 0.5 * cos(3.0 * PI * s)
		edge_ring.append(Vector3(s * 0.084, 0.005, 0.06 - 0.168 - 0.045 * toe))
		edge_col.append(base.darkened(0.1))
	rings.append(edge_ring)
	colors.append(edge_col)
	var mesh := _grid_mesh(rings, colors)
	_mesh_cache[key] = mesh
	return mesh


## --- Assembly ----------------------------------------------------------------

## config keys: species (optional SPECIES id), body_color, belly_color,
## accent_color (optional), crest_color (optional override), patch_color
## (optional override), hat, scarf, goggles (cosmetic ids or "").
## Backward compatible: configs without a species id resolve via the
## canonical dorsal color, and unknown/legacy palettes fall back to Emperor
## markings while keeping their authored colors.
func setup(config: Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	var species_id := resolve_species_id(config)
	var sp: Dictionary = SPECIES[species_id]
	# Dorsal goes through _tune_dorsal (dark, saturated base that scene light
	# lifts to tone); belly stays crisp bright white via _saturate.
	var body_color := _tune_dorsal(config.get("body_color", sp["dorsal"]) as Color)
	var belly_color := _saturate(config.get("belly_color", sp["ventral"]) as Color)
	var patch_color := _saturate(config.get("patch_color", sp.get("patch", Color(0.98, 0.76, 0.22))) as Color)
	# Paler back tone (see _mantle_for / the SPECIES doc comment) and the
	# racer's identity color, which tints the silhouette rim.
	var mantle_color := _mantle_for(body_color, sp)
	_ident = _ident_for(config, sp)
	var plumage := _get_plumage_material(_ident)

	# Species proportions live on a wrapper node: tick() animates _root's
	# position/rotation/scale (squash), so the static species scale must sit
	# above it. All anchors are under _root, so cosmetics (hats, scarves,
	# goggles) scale consistently with the body — Little Blue's small head
	# gets a matching small beanie.
	_scale_root = Node3D.new()
	_scale_root.scale = sp.get("scale", Vector3.ONE) as Vector3
	add_child(_scale_root)
	_root = Node3D.new()
	_scale_root.add_child(_root)
	# Fresh nodes start at identity; reset the smoothed-animation state that
	# fed the old nodes so a re-setup (customize preview) doesn't inherit a
	# stale offset.
	_base_pos = Vector2.ZERO
	_head_rot = Vector3.ZERO
	_waddle = 0.0
	_gait_roll = 0.0
	_gait_yaw = 0.0
	_gait_sway = 0.0
	_gait_bob = 0.0
	_lean = 0.0
	_head_osc = Vector3.ZERO
	_foot_pos_l = Vector3(-FOOT_X, FOOT_Y, FOOT_Z)
	_foot_pos_r = Vector3(FOOT_X, FOOT_Y, FOOT_Z)
	_foot_rot_l = Vector2.ZERO
	_foot_rot_r = Vector2.ZERO

	# Body + head: one continuous smooth lathe with baked plumage.
	_body = _mesh(_root, _build_body_mesh(species_id, body_color, belly_color, patch_color, mantle_color), body_color, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, plumage)

	# Tail: a flat wedge that HUGS the rump rather than sticking out of it.
	# Verified with a debug-tinted build: from the chase camera a protruding
	# tail projects onto the lower back, its camera-facing end points away and
	# down (so countershading drops it to the darkest part of the ramp) and its
	# silhouette edge picks up the rim — the net read was a black elliptical
	# hole punched in the middle of every racer, which is exactly where the eye
	# lands. Tucked flat with a matched tint it merges into the rump and only
	# lifts the profile, and in the SLIDE pose (body pitched -80 deg) it swings
	# up to read as a proper tail against the sky. Shadow casting off (_prop):
	# it also used to throw a hard ellipse onto its own back, and skipping it
	# drops a shadow-pass draw on every racer.
	var tail_mesh := SphereMesh.new()
	tail_mesh.radius = 0.13
	tail_mesh.height = 0.26
	tail_mesh.radial_segments = 20
	tail_mesh.rings = 12
	# The rump it hugs is now part-way into the mantle (y 0.268 sits on the
	# ramp), so the tail is tinted to match that blend and NOT the near-black
	# base dorsal, or the old "black ellipse punched into the back" returns —
	# this time against a pale back, where it would be twice as loud.
	# Two fixes over the old tuck, both driven by race captures:
	#   * the tilt is +10 deg, not -22. Tilted the old way the plate's rear face
	#     pointed down-AND-back, so the only surface the chase camera could see
	#     was one the sun never reaches: it rendered as a near-black horizontal
	#     slit across the lower back (measured srgb 8 against a body at ~110 on
	#     glacier), and with the flipper stubs above it the racer read as a face
	#     with a mouth.
	#   * edge_gain 0.15: a small flat plate is nearly all grazing angle, so at
	#     full strength the ink+rim treatment outlined it and it read as a
	#     separate object stuck onto the back.
	#   * it is pulled forward to z 0.246 so it barely clears the rump. Every
	#     intermediate tuck still resolved, at 8 m, as a dark ellipse sitting ON
	#     the back rather than as part of it — a ~10 px feature has no room to
	#     read as anything but a blemish. Tucked, it lifts the profile and
	#     swings clear in the SLIDE pose, which is all it was ever for.
	var tail_color := body_color.lerp(mantle_color, 0.75)
	_prop(_root, tail_mesh, tail_color, Vector3(0, 0.258, 0.246), Vector3(deg_to_rad(10), 0, 0), Vector3(0.82, 0.24, 0.98), _get_plumage_tinted(tail_color, _ident, 0.15))

	# Head anchor at the head-sphere center (the lathe's upper bulge).
	_head_anchor = Node3D.new()
	_head_anchor.position = Vector3(0, HEAD_Y, -0.02)
	_root.add_child(_head_anchor)

	_face_anchor = Node3D.new()
	_face_anchor.position = Vector3(0, 0, -0.20)
	_head_anchor.add_child(_face_anchor)

	# Eyes, set beside the bill and each yawed outward along the head surface.
	# The whole assembly runs ~18% over real-penguin proportions, which is
	# deliberate for a racer: at true scale the eye is a 2 px dark dot on a
	# near-black head by 12 m. 18% is where it stops: a 30% build plus a pale
	# orbital rim was tried and, verified in the dressing room, it turned every
	# species googly — big enough to read at distance is not worth a face that
	# is wrong in every close-up, podium and results shot. What actually
	# carries the eye at distance is the emissive catchlight, not the size.
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.035
	eye_mesh.height = 0.070
	eye_mesh.radial_segments = 16
	eye_mesh.rings = 10
	var catchlight := SphereMesh.new()
	catchlight.radius = 0.0105
	catchlight.height = 0.021
	catchlight.radial_segments = 8
	catchlight.rings = 4
	# Cornea bulge: a glossy near-black pupil sphere proud of the iris ball,
	# rimmed by a thin dark limbal ring — up close the eye reads as a wet
	# dome instead of a painted dot.
	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = 0.0225
	pupil_mesh.height = 0.045
	pupil_mesh.radial_segments = 14
	pupil_mesh.rings = 8
	var limbal_mesh := TorusMesh.new()
	limbal_mesh.inner_radius = 0.0165
	limbal_mesh.outer_radius = 0.0248
	limbal_mesh.rings = 16
	limbal_mesh.ring_segments = 8
	# Iris color is per species (rockhopper/macaroni have red-brown eyes).
	var eye_color := sp.get("eye_color", Color(0.10, 0.07, 0.06)) as Color
	var eye_mat := get_material(eye_color, 0.0, 0.07)
	var gleam_mat := get_material(Color(1.0, 1.0, 1.0), 0.0, 0.2, true)
	var pupil_mat := get_material(Color(0.02, 0.016, 0.014), 0.0, 0.04)
	var limbal_mat := get_material(Color(0.05, 0.035, 0.025), 0.0, 0.30)
	var glint_mat := get_material(Color(0.85, 0.90, 0.98), 0.0, 0.08)
	# Eye sockets: flattened matte feather patches behind each eyeball so the
	# eyes sit recessed in the head instead of reading as stickers. Dark-faced
	# species get a near-black surround; the chinstrap's white face gets a
	# soft gray shadow so the socket reads as depth, not a spot.
	var socket_mesh := SphereMesh.new()
	socket_mesh.radius = 0.055
	socket_mesh.height = 0.110
	socket_mesh.radial_segments = 14
	socket_mesh.rings = 8
	var socket_color := Color(0.05, 0.05, 0.06)
	if bool(sp.get("face_white", false)):
		socket_color = Color(0.76, 0.76, 0.78)
	var socket_mat := get_material(socket_color, 0.0, 0.88)
	# Adelie: distinctive white sclera ring around each eye. Adelie only — a
	# pale orbital rim was tried on every species to keep the eye locatable on
	# a near-black head, and in the dressing room it read as an enormous grey
	# sclera on all seven of them. Adelie is the one species that genuinely
	# has the field mark.
	var ring_mesh: TorusMesh = null
	var ring_mat: StandardMaterial3D = null
	if bool(sp.get("eye_ring", false)):
		ring_mesh = TorusMesh.new()
		ring_mesh.inner_radius = 0.036
		ring_mesh.outer_radius = 0.050
		ring_mat = get_material(Color(0.96, 0.96, 0.97), 0.0, 0.6)
	# Eyes sit ~6 mm deeper than the old sticker placement (z 0.015 -> 0.021)
	# so the socket patch shades their rim and they read as set into the head.
	_eye_l = Node3D.new()
	_eye_l.position = Vector3(-0.115, 0.018, 0.021)
	_eye_l.rotation.y = deg_to_rad(32.0)
	_face_anchor.add_child(_eye_l)
	_eye_r = Node3D.new()
	_eye_r.position = Vector3(0.115, 0.018, 0.021)
	_eye_r.rotation.y = deg_to_rad(-32.0)
	_face_anchor.add_child(_eye_r)
	for eye: Node3D in [_eye_l, _eye_r]:
		_mesh(eye, socket_mesh, socket_color, Vector3(0, 0, 0.006), Vector3.ZERO, Vector3(1.15, 1.0, 0.5), socket_mat)
		_prop(eye, eye_mesh, Color.BLACK, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, eye_mat)
		_prop(eye, pupil_mesh, Color.BLACK, Vector3(0, 0.0024, -0.0165), Vector3.ZERO, Vector3.ONE, pupil_mat)
		_prop(eye, limbal_mesh, Color.BLACK, Vector3(0, 0.0024, -0.031), Vector3(deg_to_rad(90), 0, 0), Vector3.ONE, limbal_mat)
		_prop(eye, catchlight, Color.WHITE, Vector3(0.0095, 0.0118, -0.028), Vector3.ZERO, Vector3.ONE, gleam_mat)
		# Secondary soft glint opposite the main catchlight sells the wet dome.
		_prop(eye, catchlight, Color.WHITE, Vector3(-0.0106, -0.0083, -0.0266), Vector3.ZERO, Vector3(0.55, 0.55, 0.55), glint_mat)
		if ring_mesh != null:
			# Torus axis is +Y; pitch it 90 deg so the ring faces along the
			# eye's outward -Z and hugs the head surface around the eyeball.
			_mesh(eye, ring_mesh, Color.WHITE, Vector3(0, 0, -0.009), Vector3(deg_to_rad(90), 0, 0), Vector3.ONE, ring_mat)

	# Brow ridges: slim feather ridges, slightly lighter than the crown so the
	# expression reads on a dark head; tilted for emotion in tick().
	var brow_mesh := SphereMesh.new()
	brow_mesh.radius = 0.034
	brow_mesh.height = 0.068
	brow_mesh.radial_segments = 12
	brow_mesh.rings = 6
	# Lifted further off the crown than before (0.18 -> 0.30): the head is now
	# the DARKEST part of the body, so a brow that only just clears the base
	# dorsal has no expression left at race distance.
	var brow_color := body_color.lerp(belly_color, 0.30)
	var brow_mat := _get_plumage_tinted(brow_color, _ident)
	_brow_l = _mesh(_face_anchor, brow_mesh, brow_color, Vector3(-0.112, 0.058, 0.020), Vector3(0, 0, BROW_REST), Vector3(1.3, 0.30, 0.55), brow_mat)
	_brow_r = _mesh(_face_anchor, brow_mesh, brow_color, Vector3(0.112, 0.058, 0.020), Vector3(0, 0, -BROW_REST), Vector3(1.3, 0.30, 0.55), brow_mat)

	# Bill: two-tone tapered bill pitched slightly down. Length, girth and
	# colors are per species: emperor/king keep the long hooked bill with a
	# colored lower mandible; adelie is stubby and all-dark; gentoo is bright
	# orange; little blue is small and blue-gray. The base stays buried in
	# the face while the tip position follows the length.
	var bill_len := float(sp.get("bill_len", 1.0))
	var bill_girth := float(sp.get("bill_girth", 1.0))
	var bill_dark := sp.get("bill_color", Color(0.14, 0.13, 0.16)) as Color
	var bill_pink := sp.get("mandible_color", Color(0.93, 0.45, 0.38)) as Color
	# Glossy keratin with a warm subsurface flush at the base (derived from
	# the mandible color, so dark-billed adelies stay near-black while
	# orange-billed species pick up a live salmon glow at the gape).
	# Longer and slimmer than the old stub: an emperor's bill is a rapier, and
	# the short fat cone was a duck's. Species factors still scale it.
	var bill_h := 0.235 * bill_len
	var mand_h := 0.170 * bill_len
	var bill_warm := bill_pink.lerp(Color(0.92, 0.55, 0.42), 0.35)
	var bill_mat := _get_bill_material(bill_dark, bill_warm, -0.35 * bill_h, -0.05 * bill_h, 0.20)
	var hook_mat := get_material(bill_dark, 0.0, 0.22)
	var mandible_mat := _get_bill_material(bill_pink, bill_pink.lerp(Color(0.85, 0.38, 0.30), 0.5), -0.35 * mand_h, -0.05 * mand_h, 0.24)
	var bill_mesh := CylinderMesh.new()
	bill_mesh.top_radius = 0.004
	bill_mesh.bottom_radius = 0.049 * bill_girth
	bill_mesh.height = bill_h
	bill_mesh.radial_segments = 24
	# Slimmer in plan (1.1 -> 1.0) and slightly deeper in profile (0.62 ->
	# 0.68), pitched a touch further down: reads as a decurved rapier from the
	# side instead of a party-hat cone.
	_beak = _mesh(_face_anchor, bill_mesh, bill_dark, Vector3(0, -0.005, -0.058 + 0.10 * (1.0 - bill_len)), Vector3(deg_to_rad(-97), 0, 0), Vector3(1.0, 1.0, 0.68), bill_mat)
	if bool(sp.get("bill_hook", false)):
		var hook_mesh := CylinderMesh.new()
		hook_mesh.top_radius = 0.0018
		hook_mesh.bottom_radius = 0.015
		hook_mesh.height = 0.058
		hook_mesh.radial_segments = 12
		# Follows the longer bill out: tip droop starts further from the face.
		_mesh(_face_anchor, hook_mesh, bill_dark, Vector3(0, -0.026, -0.170 + 0.22 * (1.0 - bill_len)), Vector3(deg_to_rad(-121), 0, 0), Vector3(0.8, 1.0, 0.7), hook_mat)
	var mandible_mesh := CylinderMesh.new()
	mandible_mesh.top_radius = 0.004
	mandible_mesh.bottom_radius = 0.040 * bill_girth
	mandible_mesh.height = mand_h
	mandible_mesh.radial_segments = 20
	_beak_lower = _mesh(_face_anchor, mandible_mesh, bill_pink, Vector3(0, -0.035, -0.045 + 0.075 * (1.0 - bill_len)), Vector3(deg_to_rad(-102), 0, 0), Vector3(0.86, 1.0, 0.52), mandible_mat)

	# Chinstrap: thin black band tilted so its front arc dips under the chin
	# across the white throat and cheeks. The rear arc crosses the nape where
	# the plumage is already dark, so only the namesake strap reads.
	if bool(sp.get("chinstrap", false)):
		var strap_mesh := TorusMesh.new()
		strap_mesh.inner_radius = 0.217
		strap_mesh.outer_radius = 0.233
		var strap_mat := get_material(Color(0.06, 0.06, 0.08), 0.0, 0.62)
		_mesh(_head_anchor, strap_mesh, Color.BLACK, Vector3(0, -0.012, 0), Vector3(deg_to_rad(-20.0), 0, 0), Vector3.ONE, strap_mat)

	# Flippers: flat tapered blades hugging the body, dark out / white in.
	# Blades stay closer to the near-black base dorsal than the pale mantle
	# behind them, so from directly behind the two limbs read as separate dark
	# shapes crossing a light back instead of vanishing into it.
	var flipper_color := body_color.lerp(mantle_color, 0.62)
	_flipper_l = _make_flipper(flipper_color, belly_color, mantle_color, -1.0)
	_flipper_r = _make_flipper(flipper_color, belly_color, mantle_color, 1.0)

	# Feet: webbed wedges with three toe ridges, toed out; tint per species.
	# Scaled up 25% and planted wider / further back than the old tucked
	# stance (with the tapered lower skirt) so heels and toes stay visible
	# from the chase camera behind and above.
	var foot_mesh := _build_foot_mesh(sp.get("foot_color", Color(0.93, 0.52, 0.33)) as Color)
	var foot_scale := Vector3(1.26, 1.26, 1.26)
	_foot_l = _mesh(_root, foot_mesh, Color.WHITE, Vector3(-FOOT_X, FOOT_Y, FOOT_Z), Vector3(0, deg_to_rad(14), 0), foot_scale, plumage)
	_foot_r = _mesh(_root, foot_mesh, Color.WHITE, Vector3(FOOT_X, FOOT_Y, FOOT_Z), Vector3(0, deg_to_rad(-14), 0), foot_scale, plumage)

	# Crested species: quill fans built from tapered cylinders. Two quill
	# gauges + a shadowed color variant make the fans read as layered feather
	# strands instead of three matched spikes; quill shadows are off (_prop) —
	# invisible at gameplay scale, and they cost a shadow-pass draw each.
	var crest_style := String(sp.get("crest", ""))
	if crest_style != "":
		var crest_color := _saturate(config.get("crest_color", sp.get("crest_color", Color(0.98, 0.82, 0.2))) as Color)
		var crest_mat := _get_plumage_tinted(crest_color, _ident)
		var crest_deep := _get_plumage_tinted(crest_color.darkened(0.22), _ident)
		var quill := CylinderMesh.new()
		quill.top_radius = 0.0
		quill.bottom_radius = 0.016
		quill.height = 0.18
		quill.radial_segments = 8
		var quill_fine := CylinderMesh.new()
		quill_fine.top_radius = 0.0
		quill_fine.bottom_radius = 0.009
		quill_fine.height = 0.16
		quill_fine.radial_segments = 6
		match crest_style:
			"rockhopper":
				# Spiky yellow fans flaring up-and-out above each brow, backed
				# by finer shadowed strands, plus the rockhopper's short black
				# occipital crest spiking off the crown (hidden under hats).
				var crown_mat := _get_plumage_tinted(body_color, _ident)
				for side: float in [-1.0, 1.0]:
					_prop(_head_anchor, quill, crest_color, Vector3(0.105 * side, 0.095, -0.045), Vector3(deg_to_rad(-14), 0, deg_to_rad(46.0 * side)), Vector3(1.0, 1.0, 1.0), crest_mat)
					_prop(_head_anchor, quill, crest_color, Vector3(0.115 * side, 0.085, -0.02), Vector3(deg_to_rad(2), 0, deg_to_rad(58.0 * side)), Vector3(0.9, 0.85, 0.9), crest_mat)
					_prop(_head_anchor, quill, crest_color, Vector3(0.095 * side, 0.105, -0.062), Vector3(deg_to_rad(-30), 0, deg_to_rad(34.0 * side)), Vector3(0.8, 0.8, 0.8), crest_mat)
					_prop(_head_anchor, quill_fine, crest_color, Vector3(0.120 * side, 0.075, -0.005), Vector3(deg_to_rad(12), 0, deg_to_rad(66.0 * side)), Vector3(1.0, 0.9, 1.0), crest_deep)
					_prop(_head_anchor, quill_fine, crest_color, Vector3(0.088 * side, 0.112, -0.075), Vector3(deg_to_rad(-40), 0, deg_to_rad(26.0 * side)), Vector3(1.0, 0.85, 1.0), crest_mat)
					_prop(_head_anchor, quill_fine, crest_color, Vector3(0.108 * side, 0.098, -0.035), Vector3(deg_to_rad(-6), 0, deg_to_rad(52.0 * side)), Vector3(1.0, 1.05, 1.0), crest_deep)
					_prop(_head_anchor, quill_fine, body_color, Vector3(0.045 * side, 0.128, -0.030), Vector3(deg_to_rad(-14), 0, deg_to_rad(14.0 * side)), Vector3(1.0, 0.75, 1.0), crown_mat)
				_prop(_head_anchor, quill_fine, body_color, Vector3(0.0, 0.135, -0.020), Vector3(deg_to_rad(-8), 0, 0), Vector3(1.0, 0.8, 1.0), crown_mat)
			"macaroni":
				# Orange-gold quills meeting at the center forehead and
				# drooping outward past horizontal over each eye, with finer
				# shadowed strands filling the droop.
				for side: float in [-1.0, 1.0]:
					_prop(_head_anchor, quill, crest_color, Vector3(0.020 * side, 0.115, -0.130), Vector3(deg_to_rad(-30), 0, deg_to_rad(50.0 * side)), Vector3(0.8, 0.85, 0.8), crest_mat)
					_prop(_head_anchor, quill, crest_color, Vector3(0.032 * side, 0.105, -0.112), Vector3(deg_to_rad(-20), 0, deg_to_rad(70.0 * side)), Vector3(0.9, 1.1, 0.9), crest_mat)
					_prop(_head_anchor, quill, crest_color, Vector3(0.055 * side, 0.095, -0.092), Vector3(deg_to_rad(-8), 0, deg_to_rad(84.0 * side)), Vector3(1.0, 1.15, 1.0), crest_mat)
					_prop(_head_anchor, quill, crest_color, Vector3(0.080 * side, 0.085, -0.070), Vector3(deg_to_rad(4), 0, deg_to_rad(96.0 * side)), Vector3(0.95, 1.0, 0.95), crest_mat)
					_prop(_head_anchor, quill_fine, crest_color, Vector3(0.068 * side, 0.088, -0.082), Vector3(deg_to_rad(-2), 0, deg_to_rad(104.0 * side)), Vector3(1.0, 1.1, 1.0), crest_deep)
					_prop(_head_anchor, quill_fine, crest_color, Vector3(0.042 * side, 0.100, -0.100), Vector3(deg_to_rad(-14), 0, deg_to_rad(88.0 * side)), Vector3(1.0, 1.2, 1.0), crest_deep)

	_hat_anchor = Node3D.new()
	_hat_anchor.position = Vector3(0, 0.13, -0.005)
	_head_anchor.add_child(_hat_anchor)
	_neck_anchor = Node3D.new()
	_neck_anchor.position = Vector3(0, 0.72, 0)
	_root.add_child(_neck_anchor)

	_apply_cosmetic(String(config.get("hat", "")))
	_apply_cosmetic(String(config.get("scarf", "")))
	_apply_cosmetic(String(config.get("goggles", "")))


func _make_flipper(body_color: Color, belly_color: Color, mantle_color: Color, side: float) -> Node3D:
	# Pivot sits INSIDE the torso (side radius ~0.27 at shoulder height) so the
	# blade root stays embedded in every pose. tick() drives pivot rotation.
	var pivot := Node3D.new()
	pivot.position = Vector3(0.24 * side, 0.60, -0.01)
	_root.add_child(pivot)
	# Shoulder mound bridges torso -> blade so no seam shows at extreme swings.
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 0.07
	shoulder_mesh.height = 0.14
	shoulder_mesh.radial_segments = 16
	shoulder_mesh.rings = 8
	# Shoulder height (y 0.60) is squarely inside the mantle band, so the mound
	# takes the mantle tone; tinted with the flipper's darker base it read as a
	# pair of black lumps bolted onto a pale back.
	_mesh(pivot, shoulder_mesh, mantle_color, Vector3(0.015 * side, -0.015, 0), Vector3.ZERO, Vector3(0.75, 0.95, 0.9), _get_plumage_tinted(mantle_color, _ident))
	# Blade: shared two-tone mesh; the left side is the same mesh yawed PI so
	# its dark face points outward (the cross-section is Z-symmetric; the
	# per-side flip keeps the pale trailing-edge border facing backward).
	var blade := _mesh(pivot, _build_flipper_mesh(body_color, belly_color, side), Color.WHITE, Vector3(0.012 * side, -0.02, 0), Vector3.ZERO, Vector3.ONE, _get_plumage_material(_ident, 0.45))
	# The blade is a flat plate whose faces point sideways, so from the chase
	# camera — dead astern — you see it edge-on: a 4 px vertical wire on either
	# side of the body, which is how the limbs read as insect legs rather than
	# flippers. Yawing each blade 30 deg turns its face partly aft and roughly
	# doubles the apparent width without moving the tip or the pivot, so the
	# silhouette keeps its proportions and the limb finally reads as a limb.
	# The blade also takes a reduced edge_gain (0.45): a thin plate is nearly all
	# grazing angle, so at full strength the rim lit its whole area and the
	# swept-back slide pose grew two white ski poles.
	blade.rotation.y = (PI if side < 0.0 else 0.0) - deg_to_rad(24.0) * side
	# Match tick()'s rest targets (l: -26, r: +26) so static frames (previews,
	# first frame before tick) already show the correct outward-flared rest.
	# 26 deg (was 21, before that 16): with the blade yawed to show its face
	# aft, the extra flare is what lifts the limb clear of the body from dead
	# astern — at 21 the two blades still resolved as a pair of dark beads at
	# the shoulders rather than as flippers.
	pivot.rotation.z = deg_to_rad(26.0 * side)
	return pivot


## Attaches one cosmetic item by id (also used to preview AI accessories).
## Offsets are tuned to the lathe head: center (0, 0.85, -0.02), radius 0.216.
func _apply_cosmetic(id: String) -> void:
	if id == "":
		return
	var info := CosmeticsDB.get_item(id)
	var color: Color = info.get("color", Color.WHITE)
	match id:
		"hat_beanie":
			var dome := SphereMesh.new()
			dome.radius = 0.24
			dome.height = 0.26
			_mesh(_hat_anchor, dome, color, Vector3(0, 0.03, 0))
			var pom := SphereMesh.new()
			pom.radius = 0.07
			pom.height = 0.14
			_mesh(_hat_anchor, pom, Color(0.97, 0.97, 0.97), Vector3(0, 0.19, 0))
		"hat_earwarmers":
			var band := TorusMesh.new()
			band.inner_radius = 0.20
			band.outer_radius = 0.235
			_mesh(_hat_anchor, band, Color(0.4, 0.4, 0.45), Vector3(0, -0.10, 0), Vector3(deg_to_rad(14), 0, 0))
			var muff := SphereMesh.new()
			muff.radius = 0.09
			muff.height = 0.18
			_mesh(_hat_anchor, muff, color, Vector3(-0.215, -0.13, 0.005))
			_mesh(_hat_anchor, muff, color, Vector3(0.215, -0.13, 0.005))
		"hat_headset":
			var band := TorusMesh.new()
			band.inner_radius = 0.21
			band.outer_radius = 0.24
			_mesh(_hat_anchor, band, Color(0.2, 0.2, 0.24), Vector3(0, -0.08, 0), Vector3(deg_to_rad(10), 0, 0))
			var can := CylinderMesh.new()
			can.top_radius = 0.075
			can.bottom_radius = 0.075
			can.height = 0.05
			_mesh(_hat_anchor, can, color, Vector3(-0.205, -0.13, 0.005), Vector3(0, 0, deg_to_rad(90)))
			_mesh(_hat_anchor, can, color, Vector3(0.205, -0.13, 0.005), Vector3(0, 0, deg_to_rad(90)))
			var mic := CylinderMesh.new()
			mic.top_radius = 0.015
			mic.bottom_radius = 0.015
			mic.height = 0.2
			_mesh(_hat_anchor, mic, Color(0.2, 0.2, 0.24), Vector3(-0.14, -0.20, -0.12), Vector3(deg_to_rad(55), deg_to_rad(25), 0))
		"hat_crown":
			var ring := CylinderMesh.new()
			ring.top_radius = 0.15
			ring.bottom_radius = 0.125
			ring.height = 0.11
			_mesh(_hat_anchor, ring, color, Vector3(0, 0.03, 0))
			var spike := CylinderMesh.new()
			spike.top_radius = 0.0
			spike.bottom_radius = 0.04
			spike.height = 0.11
			for i: int in 5:
				var angle := TAU * float(i) / 5.0
				_mesh(_hat_anchor, spike, color, Vector3(sin(angle) * 0.125, 0.12, cos(angle) * 0.125))
		"scarf_red", "scarf_rainbow":
			var scarf := TorusMesh.new()
			scarf.inner_radius = 0.17
			scarf.outer_radius = 0.30
			_mesh(_neck_anchor, scarf, color, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.3, 1))
			var tail_mesh := BoxMesh.new()
			tail_mesh.size = Vector3(0.12, 0.3, 0.05)
			_mesh(_neck_anchor, tail_mesh, color, Vector3(0.10, -0.16, -0.24), Vector3(deg_to_rad(-8), 0, deg_to_rad(-8)))
			if id == "scarf_rainbow":
				var stripe := BoxMesh.new()
				stripe.size = Vector3(0.12, 0.1, 0.06)
				_mesh(_neck_anchor, stripe, Color(0.3, 0.75, 0.95), Vector3(0.10, -0.08, -0.24))
				_mesh(_neck_anchor, stripe, Color(0.45, 0.85, 0.4), Vector3(0.10, -0.24, -0.235))
		"scarf_bowtie":
			var knot := BoxMesh.new()
			knot.size = Vector3(0.07, 0.07, 0.05)
			_mesh(_neck_anchor, knot, color, Vector3(0, -0.06, -0.245))
			var wing := BoxMesh.new()
			wing.size = Vector3(0.14, 0.1, 0.04)
			_mesh(_neck_anchor, wing, color, Vector3(-0.10, -0.06, -0.24), Vector3(0, 0, deg_to_rad(12)))
			_mesh(_neck_anchor, wing, color, Vector3(0.10, -0.06, -0.24), Vector3(0, 0, deg_to_rad(-12)))
		"goggles_ski":
			var lens := BoxMesh.new()
			lens.size = Vector3(0.26, 0.10, 0.05)
			var lens_instance := _mesh(_face_anchor, lens, color, Vector3(0, 0.045, -0.02))
			lens_instance.material_override = get_material(color, 0.2, 0.15)
			var strap := TorusMesh.new()
			strap.inner_radius = 0.20
			strap.outer_radius = 0.225
			_mesh(_head_anchor, strap, Color(0.25, 0.25, 0.3), Vector3(0, 0.045, 0), Vector3(deg_to_rad(80), 0, 0))
		"goggles_aviator":
			var lens := SphereMesh.new()
			lens.radius = 0.055
			lens.height = 0.11
			var l := _mesh(_face_anchor, lens, color, Vector3(-0.095, 0.03, -0.01))
			var r := _mesh(_face_anchor, lens, color, Vector3(0.095, 0.03, -0.01))
			l.material_override = get_material(color, 0.6, 0.2)
			r.material_override = get_material(color, 0.6, 0.2)
			var bridge := BoxMesh.new()
			bridge.size = Vector3(0.09, 0.018, 0.018)
			_mesh(_face_anchor, bridge, Color(0.55, 0.42, 0.2), Vector3(0, 0.035, -0.055))
		_:
			pass


func set_pose(new_pose: Pose) -> void:
	if pose == new_pose:
		return
	pose = new_pose
	_pose_blend = 0.0


func trigger_squash(amount: float = 0.72) -> void:
	_squash = amount


## Attacker's shove: a whole-body lunge with both flippers thrust forward.
##
## The shove used to be a sound and nothing else on the attacking side, which
## on a behind-the-back chase camera meant the player's own throw was invisible
## -- you pressed the button and the world simply changed. This is the swing.
func trigger_lunge() -> void:
	_lunge_t = 0.0


## Victim's shove: spun off balance, flippers flung wide, head snapped back.
## `dir` is the side it came from (-1 / +1); the spin goes with the push.
##
## Layered over the running pose rather than replacing it, because a shove does
## not stop the victim -- they keep waddling, badly, which is the joke.
func trigger_tumble(dir: float) -> void:
	_tumble_t = 0.0
	_tumble_dir = 1.0 if dir >= 0.0 else -1.0


## Drives all animation. speed_ratio: 0..1.5 of normal speed.
func tick(delta: float, speed_ratio: float) -> void:
	if _root == null:
		return
	_time += delta * (0.6 + anim_speed)
	_pose_blend = minf(_pose_blend + delta * 5.0, 1.0)

	# Shove envelopes, evaluated before the pose so their offsets can be folded
	# into the pose's own targets instead of fighting the low-pass filters that
	# apply them.
	var lunge := 0.0
	if _lunge_t >= 0.0:
		_lunge_t += delta
		if _lunge_t >= LUNGE_TIME:
			_lunge_t = -1.0
		else:
			# Thrust out fast, draw back slower: pow() skews the half-sine so the
			# peak lands early, which is what makes it read as a strike rather
			# than a stretch.
			lunge = sin(pow(_lunge_t / LUNGE_TIME, 0.45) * PI)
	var tumble := 0.0
	if _tumble_t >= 0.0:
		_tumble_t += delta
		if _tumble_t >= TUMBLE_TIME:
			_tumble_t = -1.0
		else:
			# Full deflection on the first frame -- an impact IS a snap, and the
			# existing squash already behaves this way -- then an unwinding
			# wobble as balance comes back.
			var v := _tumble_t / TUMBLE_TIME
			tumble = pow(1.0 - v, 1.7) * cos(v * 6.5)

	var target_tilt := Vector3.ZERO
	var target_y := 0.0
	var target_x := 0.0
	# Gait phase. _time already advances at (0.6 + anim_speed) x real time,
	# so this rate lands the step cadence around ~2-3 steps/s across the
	# speed range — a real penguin waddle — instead of the old ~6 Hz buzz.
	var wave := _time * (3.2 + 2.8 * speed_ratio)
	var flipper_l_target := deg_to_rad(-26.0)
	var flipper_r_target := deg_to_rad(26.0)
	var flipper_swing := 0.0
	var brow_target := BROW_REST
	var step_lift := 0.0
	var breath := 0.0
	var head_pitch := 0.0
	var head_yaw := 0.0
	var head_roll := 0.0
	_head_anchor.position.y = HEAD_Y

	match pose:
		Pose.RUN:
			# The waddle rock itself (body roll, hip sway, midstance rise,
			# head counter-rotation and bob) lives in the _waddle block after
			# this match: eased in/out by _waddle and low-passed on apply so
			# the gait fades smoothly across pose changes and never snaps.
			target_tilt.x = deg_to_rad(-6.0) * speed_ratio  # slight forward hustle lean
			# Flippers counter-swing against the stance side, trailing the
			# body rock by ~0.6 rad so they read as loose mass flung by the
			# waddle rather than metronome levers.
			flipper_swing = sin(wave - 0.6) * deg_to_rad(33.0) * clampf(speed_ratio, 0.3, 1.0)
			brow_target = deg_to_rad(-12.0)
			step_lift = 0.10 * clampf(speed_ratio, 0.0, 1.0)
		Pose.IDLE:
			target_tilt.z = sin(_time * 1.6) * deg_to_rad(2.0)
			target_y = sin(_time * 2.2) * 0.01
			flipper_swing = sin(_time * 1.8) * deg_to_rad(4.0)
			brow_target = deg_to_rad(-6.0)
			# Breathing: ~1.2% chest swell at a calm resting rate.
			breath = sin(_time * 1.4) * 0.012
			# Occasional glance: two incommensurate slow waves only sum past
			# the threshold now and then, so the penguin holds a look aside
			# every ten-odd seconds and drifts back, instead of scanning.
			var glance := sin(_time * 0.23) + sin(_time * 0.361)
			head_yaw = deg_to_rad(28.0) * (smoothstep(1.5, 1.85, glance) - smoothstep(1.5, 1.85, -glance))
		Pose.SLIDE:
			# Negative X pitch = head toward -Z (forward); positive read as
			# lying on the back in-game.
			target_tilt.x = deg_to_rad(-80.0)
			# Lathe body pivots at foot level (old egg pivoted mid-body): the
			# -0.28 drop buried the head — lift so the belly skims the snow.
			# The belly-press squash thins the prone body (local Z, see the
			# scale block), so drop slightly with speed to keep it skimming.
			target_y = 0.14 - 0.012 * clampf(speed_ratio, 0.0, 1.0)
			# Flippers sweep back along the body and paddle-flutter faster with
			# speed. From directly behind a prone penguin is a flat oval with
			# nothing moving on it, and the flutter plus the carve terms further
			# down are what keep the slide reading as travel, not a still frame.
			flipper_l_target = deg_to_rad(-58.0)
			flipper_r_target = deg_to_rad(58.0)
			flipper_swing = sin(_time * (5.0 + 4.0 * speed_ratio)) * deg_to_rad(7.0) * clampf(speed_ratio, 0.25, 1.0)
			brow_target = deg_to_rad(-14.0)
			# Head-up alertness: crane the head out of the prone line, more
			# at speed, so the slide reads alive rather than ragdoll.
			head_pitch = deg_to_rad(30.0) * clampf(speed_ratio, 0.3, 1.0)
		Pose.AIR:
			target_tilt.x = deg_to_rad(-12.0)
			flipper_l_target = deg_to_rad(-70.0)
			flipper_r_target = deg_to_rad(70.0)
			brow_target = deg_to_rad(-4.0)
		Pose.SWIM:
			target_tilt.x = deg_to_rad(-72.0)
			target_y = -0.2
			flipper_swing = sin(_time * 9.0) * deg_to_rad(30.0)
			flipper_l_target = deg_to_rad(-40.0)
			flipper_r_target = deg_to_rad(40.0)
			brow_target = deg_to_rad(-12.0)
		Pose.STUN:
			target_tilt.z = sin(_time * 14.0) * deg_to_rad(14.0)
			target_tilt.x = deg_to_rad(-8.0)
			flipper_swing = sin(_time * 16.0) * deg_to_rad(35.0)
			brow_target = deg_to_rad(15.0)
		Pose.CELEBRATE:
			target_y = absf(sin(_time * 6.0)) * 0.18
			flipper_l_target = deg_to_rad(-150.0) + sin(_time * 10.0) * deg_to_rad(15.0)
			flipper_r_target = deg_to_rad(150.0) - sin(_time * 10.0) * deg_to_rad(15.0)
			brow_target = deg_to_rad(2.0)
		Pose.DEFEAT:
			target_tilt.x = deg_to_rad(18.0)
			target_y = -0.06
			_head_anchor.position.y = HEAD_Y - 0.05
			brow_target = deg_to_rad(18.0)

	# Shove offsets, folded into the pose's targets so the existing low-pass
	# filters carry them instead of being fought by them.
	if lunge > 0.001:
		# Both flippers swing forward together (rotation.x), and the blades open
		# outward -- the left pivot rests negative and the right positive, so
		# the signed pair widens the stance into a shove rather than a hug.
		flipper_l_target -= deg_to_rad(34.0) * lunge
		flipper_r_target += deg_to_rad(34.0) * lunge
		flipper_swing += deg_to_rad(52.0) * lunge
		# Chest drives into it and the brow sets: this is effort, not a stumble.
		target_tilt.x -= deg_to_rad(24.0) * lunge
		target_y -= 0.03 * lunge
		brow_target = deg_to_rad(-24.0) * lunge + brow_target * (1.0 - lunge)
		head_pitch -= deg_to_rad(14.0) * lunge
	if absf(tumble) > 0.001:
		# Flippers fly up and wide, the head whips back, and the brow goes up in
		# alarm -- all the things a body does when something hits it.
		flipper_l_target -= deg_to_rad(62.0) * absf(tumble)
		flipper_r_target += deg_to_rad(62.0) * absf(tumble)
		target_tilt.x += deg_to_rad(26.0) * absf(tumble)
		head_pitch += deg_to_rad(22.0) * absf(tumble)
		head_yaw += deg_to_rad(30.0) * tumble * _tumble_dir
		brow_target = deg_to_rad(20.0) * absf(tumble) + brow_target * (1.0 - absf(tumble))

	# Waddle core: sin(wave) > 0 lifts the LEFT foot, so the body rolls and
	# the hips translate onto the planted right (+X) foot — an inverted
	# pendulum vaulting over the stance leg, rising slightly at each
	# midstance. Every term is a pure sine/cosine of the gait phase (C1
	# continuous — no abs()/floor() kinks in position or rotation), scaled
	# by _waddle so the gait eases in on RUN entry and decays over ~0.3 s
	# on exit instead of snapping.
	_waddle = lerpf(_waddle, 1.0 if pose == Pose.RUN else 0.0, minf(delta * 6.0, 1.0))
	var rock_roll := 0.0
	var rock_yaw := 0.0
	var sway_x := 0.0
	var bob_y := 0.0
	var head_yaw_osc := 0.0
	var head_roll_osc := 0.0
	var head_bob_osc := 0.0
	if _waddle > 0.001:
		var sway := clampf(speed_ratio, 0.2, 1.0) * _waddle
		var rock := sin(wave)
		# Amplitudes are set by what survives the chase camera, not by what
		# looks right in a close-up: at 8-30 m and 30 px tall, the previous
		# 9 deg roll / 4 cm sway was a shimmer. Roll and sway are up ~25% and
		# a torso YAW twist is added — from directly behind, a twist alternately
		# shows each flank and is far more legible than roll alone, which mostly
		# just rocks a symmetric silhouette in place.
		rock_roll = -rock * deg_to_rad(14.0) * sway  # ~11 deg applied after the low-pass
		rock_yaw = rock * deg_to_rad(7.0) * sway     # torso counter-twist over the stance foot
		sway_x = rock * 0.053 * sway                 # hips shift over the stance foot
		bob_y = rock * rock * 0.062 * speed_ratio * _waddle  # sin^2 midstance rise (smooth)
		# Gaze stabilization: the head counter-rolls most of the body rock
		# away at the neck and counter-yaws slightly, so the face holds
		# near-steady while the body metronomes under it — real penguins
		# stabilize their gaze exactly this way.
		head_roll_osc = -rock_roll * 0.75
		head_yaw_osc = rock * deg_to_rad(5.0) * sway - rock_yaw * 0.8
		head_bob_osc = sin(wave * 2.0) * 0.012 * sway
	# Low-pass everything the gait applies (~14/s): the oscillators above
	# are already smooth at the ~2-3 steps/s cadence, and filtering the
	# final applied values guarantees nothing snaps on pose or speed
	# changes and rounds off any residual high-frequency energy.
	var smooth_k := minf(delta * 14.0, 1.0)
	_gait_roll = lerpf(_gait_roll, rock_roll, smooth_k)
	_gait_yaw = lerpf(_gait_yaw, rock_yaw, smooth_k)
	_gait_sway = lerpf(_gait_sway, sway_x, smooth_k)
	_gait_bob = lerpf(_gait_bob, bob_y, smooth_k)
	_head_osc = _head_osc.lerp(Vector3(head_yaw_osc, head_roll_osc, head_bob_osc), smooth_k)

	# LEAN INTO TURNS. Racer drives this node's own rotation.z (steering bank +
	# surface conform) before calling tick(), so the body roll is readable from
	# right here without reaching back into the racer. Two responses hang off
	# it, and both are things a real bird does under roll:
	#   * the head partially LEVELS against the roll and turns into the corner,
	#     which is the difference between a penguin leaning through a turn and
	#     a rigid model being rotated by the game,
	#   * the flippers set asymmetrically — outer one up and out, inner one
	#     tucked down — which from behind is the clearest single frame-by-frame
	#     signal that the racer is cornering at all.
	# Low-passed so surface chatter never twitches the head.
	_lean = lerpf(_lean, clampf(rotation.z, -0.55, 0.55), minf(delta * 6.0, 1.0))
	var lean_head_roll := -_lean * 0.45
	var lean_head_yaw := _lean * 0.40
	var lean_flipper := _lean * 0.55

	_current_tilt = _current_tilt.lerp(target_tilt, minf(delta * 8.0, 1.0))
	_root.rotation = _current_tilt
	_root.rotation.z += _gait_roll
	_root.rotation.y += _gait_yaw
	# The spin goes on straight rather than through _current_tilt's lerp: the
	# whole point of the tumble is that the silhouette swings the instant the
	# hit lands. Roll leans away from the push, yaw whips with it.
	if absf(tumble) > 0.001:
		_root.rotation.y += deg_to_rad(58.0) * tumble * _tumble_dir
		_root.rotation.z += deg_to_rad(30.0) * tumble * -_tumble_dir
	# The lunge shifts the body forward on its feet, not just rotates it.
	# Assigned unconditionally (not +=) because nothing else writes position.z,
	# so a conditional offset would never be taken back off.
	_root.position.z = -0.10 * lunge
	_base_pos.y = lerpf(_base_pos.y, target_y, minf(delta * 8.0, 1.0))
	_base_pos.x = lerpf(_base_pos.x, target_x, minf(delta * 8.0, 1.0))
	_root.position.y = _base_pos.y + _gait_bob
	_root.position.x = _base_pos.x + _gait_sway
	# Squash & stretch: impact squash (trigger_squash) combines with the
	# slide's belly press — compression along local Z, the chest-to-back axis
	# while prone, widening the shoulders — and idle breathing swells the
	# chest laterally by ~1%.
	var press := 1.0
	if pose == Pose.SLIDE:
		press = 0.965 - 0.025 * clampf(speed_ratio, 0.0, 1.0)
	var sxz := (1.0 + breath) / sqrt(_squash)
	_root.scale = Vector3(
		lerpf(_root.scale.x, sxz * (1.0 + (1.0 - press) * 0.6), minf(delta * 12.0, 1.0)),
		lerpf(_root.scale.y, _squash, minf(delta * 12.0, 1.0)),
		lerpf(_root.scale.z, sxz * press, minf(delta * 12.0, 1.0))
	)
	_squash = lerpf(_squash, 1.0, minf(delta * 6.0, 1.0))

	# Head secondary motion: pitch cranes up during slides, yaw is the idle
	# glance (the slow yaw lerp turns it into a deliberate look, not a
	# twitch). The smoothed base lives in _head_rot; the waddle's
	# counter-rotation and bob terms (low-passed with the rest of the gait
	# in _head_osc) are added on top so the head reads stable and smooth
	# through the waddle.
	_head_rot.x = lerpf(_head_rot.x, head_pitch, minf(delta * 5.0, 1.0))
	_head_rot.y = lerpf(_head_rot.y, head_yaw, minf(delta * 2.2, 1.0))
	_head_rot.z = lerpf(_head_rot.z, head_roll, minf(delta * 8.0, 1.0))
	_head_anchor.rotation.x = _head_rot.x
	_head_anchor.rotation.y = _head_rot.y + _head_osc.x + lean_head_yaw
	_head_anchor.rotation.z = _head_rot.z + _head_osc.y + lean_head_roll
	_head_anchor.position.y += _head_osc.z

	if _flipper_l != null:
		# Both targets take +lean_flipper, not a mirrored pair: the left pivot
		# rests at a NEGATIVE angle and the right at a positive one, so a single
		# signed offset opens the outer blade and tucks the inner one.
		_flipper_l.rotation.z = lerpf(_flipper_l.rotation.z, flipper_l_target + flipper_swing + lean_flipper, minf(delta * 10.0, 1.0))
		_flipper_r.rotation.z = lerpf(_flipper_r.rotation.z, flipper_r_target - flipper_swing + lean_flipper, minf(delta * 10.0, 1.0))
		_flipper_l.rotation.x = flipper_swing * 0.5
		_flipper_r.rotation.x = -flipper_swing * 0.5

	if _brow_l != null:
		_brow_l.rotation.z = lerpf(_brow_l.rotation.z, brow_target, minf(delta * 6.0, 1.0))
		_brow_r.rotation.z = -_brow_l.rotation.z

	if _foot_l != null:
		# Alternating step cycle: each foot hops through a SQUARED half-sine
		# window during its swing half-cycle (sin > 0 is the left swing) —
		# zero slope at liftoff and touchdown, so the hop blends into the
		# plant with no velocity kink and the foot dwells planted slightly
		# longer than it swings. Targets are computed every frame (rest pose
		# when _waddle has decayed) and the applied values are low-passed at
		# smooth_k, so steps grow in on RUN entry and ease out on exit —
		# never snapping to rest. The wider swing (stride) keeps the moving
		# foot visible past the body from the chase camera.
		var swing_l := maxf(0.0, sin(wave))
		var swing_r := maxf(0.0, -sin(wave))
		var hop_l := swing_l * swing_l * _waddle
		var hop_r := swing_r * swing_r * _waddle
		var stride := 0.135 * clampf(speed_ratio, 0.25, 1.0) * _waddle
		var t_pos_l := Vector3(
			-FOOT_X - hop_l * 0.018,
			FOOT_Y + hop_l * step_lift,
			FOOT_Z + sin(wave) * stride)
		var t_pos_r := Vector3(
			FOOT_X + hop_r * 0.018,
			FOOT_Y + hop_r * step_lift,
			FOOT_Z - sin(wave) * stride)
		# Ankle flex: the planted sole counter-rolls the applied body roll
		# so it stays flat on the snow (also grounds IDLE/STUN sway); the
		# swing foot pitches toes-down through its hop like a push-off.
		var t_rot_l := Vector2(hop_l * deg_to_rad(-22.0), -_root.rotation.z * (1.0 - hop_l))
		var t_rot_r := Vector2(hop_r * deg_to_rad(-22.0), -_root.rotation.z * (1.0 - hop_r))
		_foot_pos_l = _foot_pos_l.lerp(t_pos_l, smooth_k)
		_foot_pos_r = _foot_pos_r.lerp(t_pos_r, smooth_k)
		_foot_rot_l = _foot_rot_l.lerp(t_rot_l, smooth_k)
		_foot_rot_r = _foot_rot_r.lerp(t_rot_r, smooth_k)
		_foot_l.position = _foot_pos_l
		_foot_r.position = _foot_pos_r
		_foot_l.rotation.x = _foot_rot_l.x
		_foot_l.rotation.z = _foot_rot_l.y
		_foot_r.rotation.x = _foot_rot_r.x
		_foot_r.rotation.z = _foot_rot_r.y
