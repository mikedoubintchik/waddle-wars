class_name ItemBox
extends Area3D
## Floating power-up box: a gilded ice crate — six frosted ice panels held in
## a chunky flat-faceted gold frame, with a bold '?' medallion floating inside
## and a warm prize light blooming out of every panel. It tumbles and bobs,
## grants a position-weighted random item, then respawns after a short delay
## (simple pooling: hide + reactivate).
##
## Readability is the whole design. The crate has to be the most eye-catching
## thing on the track from far away, on BOTH bright snow and a night sky, with
## environment glow disabled (SettingsManager.glow_allowed() is off on web at
## medium/low quality), so it carries two opposed contrasts at once:
##   * a warm GOLD frame + gold '?' — mid-value and high-chroma, so it separates
##     from near-white snow where anything pale disappears;
##   * BRIGHT ice panels with a world-space sky-up value ramp and a warm core
##     glow — so it separates from a dark night sky where anything dark
##     disappears.
## The chamfered mesh is flat-shaded (set_smooth_group(-1)) into hard facets
## with big value steps, matching the low-poly icebergs, instead of the smooth
## translucent bubble it used to be.
##
## Rendering notes: the crate is ONE shared ArrayMesh with two surfaces —
## surface 0 (six panels) uses an inline ice shader, surface 1 (twelve edge
## bevels + eight corner facets) uses a shared opaque gold frame material —
## so a box is 2 draw calls for the solid, plus the '?' billboard and a flat
## ground disc. The ground marker is a 2-triangle soft disc rather than the old
## 288-triangle torus. Respawns shimmer back in with a back-eased scale-up plus
## a soft flash instead of popping into existence. Every mesh/material is built
## once and shared by every box; only burst materials are per-instance (their
## alpha animates). The ring + mote burst layers are skipped entirely on
## display/particle_quality == "low".
##
## Accessibility: the box reads through SHAPE (faceted cube + '?' glyph) +
## PATTERN (glyph, facets, frame) + BRIGHTNESS (panel ramp, ground disc) —
## never hue alone. "accessibility/high_contrast_pickups" swaps the whole
## crate and its ground disc to the same bright-gold emissive language as
## FishPickup.

const RESPAWN_TIME: float = 3.5

## Bold '?' medallion: a heavy near-black backing stroke under a bright warm
## core, over a soft warm halo. The dark backing is what makes it survive on
## sunlit snow; the bright core is what makes it survive against night sky.
## Same Image.load_svg_from_string technique as the HUD fish icon.
const GLYPH_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="31" fill="#ffcf6a" opacity="0.13"/>
<circle cx="32" cy="32" r="22" fill="#ffdd8c" opacity="0.20"/>
<path d="M19 23 C19 10 45 10 45 23 C45 32 32 32.5 32 39 L32 42" fill="none" stroke="#07141f" stroke-width="18" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="32" cy="54" r="9.4" fill="#07141f"/>
<path d="M19 23 C19 10 45 10 45 23 C45 32 32 32.5 32 39 L32 42" fill="none" stroke="#ffe07a" stroke-width="10.5" stroke-linecap="round" stroke-linejoin="round"/>
<circle cx="32" cy="54" r="5.8" fill="#ffe07a"/>
<path d="M22.5 20 C23 13 33 11 38 13" fill="none" stroke="#fff8dc" stroke-width="3.4" stroke-linecap="round"/>
</svg>"""

## Ice panel shader (surface 0 only — the frame is a plain opaque material).
##
## The value ramp is taken from the WORLD-space normal, so the crate always
## reads bright-topped and dark-bellied however it tumbles: the same
## flat-faceted arctic language as the course icebergs, and the reason the
## solid reads as a solid instead of a wireframe. A warm prize core blooms out
## of the middle of every panel, pulsing on a per-box phase derived from the
## instance's world origin (MODEL_MATRIX — no instance uniforms, so one shared
## material still gives every crate its own beat). Frost grain and slow
## suspended-bubble twinkles add texture without the old diagonal caustic
## bands, which read as scratches at race distance. All math, no textures —
## WebGL2/mobile safe.
const BOX_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 top_color : source_color = vec4(0.55, 0.80, 0.97, 1.0);
uniform vec4 side_color : source_color = vec4(0.14, 0.40, 0.72, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.03, 0.11, 0.28, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.74, 0.28, 1.0);

varying vec3 v_obj;
varying vec3 v_nrm_obj;
varying float v_phase;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
	v_nrm_obj = NORMAL;
	v_phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.6);
	// Sky-up value ramp in world space: bright crown, mid flanks, deep belly.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 col = side_color.rgb;
	col = mix(col, top_color.rgb, smoothstep(0.15, 0.85, wn.y));
	col = mix(col, bottom_color.rgb, smoothstep(-0.15, -0.85, wn.y));
	// Frost grain: coarse cells, not fine lines — texture that survives
	// minification instead of aliasing into scratches.
	float grain = hash31(floor(v_obj * 22.0));
	col *= 0.93 + grain * 0.14;
	// Prize core: warm light blooming out of the centre of each panel, on a
	// per-box pulse phase. Radial distance measured IN the panel plane.
	vec3 face_r = v_obj - v_nrm_obj * dot(v_obj, v_nrm_obj);
	float core = 1.0 - smoothstep(0.05, 0.46, length(face_r));
	core *= 0.72 + 0.28 * sin(TIME * 2.3 + v_phase);
	// Suspended bubbles: sparse cells brightening on their own slow phase
	// (well under flashing-safety thresholds).
	float bub = step(0.88, grain) * smoothstep(0.80, 1.0, sin(TIME * 1.1 + grain * 37.7));
	ALBEDO = mix(col, core_color.rgb, core * 0.30);
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	ALPHA = clamp(0.84 + fres * 0.14 + core * 0.08 + bub * 0.08, 0.0, 0.99);
	EMISSION = core_color.rgb * core * 0.55
			+ vec3(0.62, 0.86, 1.0) * fres * 0.45
			+ vec3(0.9, 0.97, 1.0) * bub * 0.5;
}
"""

## Cube half-size and corner bevel width for the chamfered crate mesh. The
## solid is 1.32 across — it now fills the 1.4 pickup box almost exactly, so
## what the player aims at is what they collect.
const CUBE_HALF: float = 0.66
const CUBE_BEVEL: float = 0.2

static var _cube_mesh: ArrayMesh = null
static var _panel_mat: ShaderMaterial = null
static var _frame_mat: StandardMaterial3D = null
static var _box_mat_contrast: StandardMaterial3D = null
static var _glyph_mesh: QuadMesh = null
static var _glyph_mat: StandardMaterial3D = null
static var _burst_base_mat: StandardMaterial3D = null
static var _shard_mesh: ArrayMesh = null
static var _shard_base_mat: StandardMaterial3D = null
static var _flash_mesh: QuadMesh = null
static var _flash_base_mat: StandardMaterial3D = null
static var _halo_mesh: QuadMesh = null
static var _halo_mat: StandardMaterial3D = null
static var _halo_mat_contrast: StandardMaterial3D = null
static var _burst_ring_mesh: TorusMesh = null
static var _ring_burst_base_mat: StandardMaterial3D = null
static var _mote_base_mat: StandardMaterial3D = null

var _visual: MeshInstance3D = null
var _glyph: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _burst: MeshInstance3D = null
var _burst_mat: StandardMaterial3D = null
var _shards: MeshInstance3D = null
var _shard_mat: StandardMaterial3D = null
var _flash: MeshInstance3D = null
var _flash_mat: StandardMaterial3D = null
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _motes: MeshInstance3D = null
var _mote_mat: StandardMaterial3D = null
var _burst_tween: Tween = null
var _respawn_tween: Tween = null
var _active: bool = true
var _spin_time: float = 0.0
var _glow_phase: float = 0.0
var _fx_rich: bool = true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Time Trial promises "No items, pure skill": boxes never spawn there.
	# Physics process is disabled first since it can run once before the
	# deferred free and would touch the never-built _visual.
	if Game.mode == Game.Mode.TIME_TRIAL:
		set_physics_process(false)
		queue_free()
		return
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	_rng.randomize()
	_glow_phase = _rng.randf_range(0.0, TAU)
	_fx_rich = String(SettingsManager.get_setting("display", "particle_quality")) != "low"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.4, 1.4)
	shape.shape = box
	add_child(shape)

	# The crate itself: ice panels (surface 0) + gold frame (surface 1), both
	# materials living on the shared mesh. material_override stays null in
	# normal mode so those per-surface materials show; high-contrast mode
	# gilds the whole solid through the override.
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_cube_mesh()
	_visual.material_override = _get_box_material()
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)

	# Ground marker: a flat warm disc under the crate (attached to self so it
	# does not tumble). Alpha-blended amber rather than an additive bloom, so
	# it tints toward warm on white snow AND lifts out of dark night snow —
	# the lane anchor that says "line up here". Two triangles.
	_halo = MeshInstance3D.new()
	_halo.mesh = _get_halo_mesh()
	_halo.material_override = _get_halo_material()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = -0.62
	add_child(_halo)

	# '?' medallion: billboard quad drawn AFTER the panels (render_priority) so
	# it stays crisp instead of being washed out by the ice in front of it. The
	# panels use depth_draw_opaque (no depth write), so it still reads as
	# suspended inside the crate while remaining correctly occluded by racers
	# and terrain. Parented to self, not the tumbling shell, so it never
	# clips into the frame bevels. Skipped when the SVG module is
	# unavailable (headless).
	var glyph_mat := _get_glyph_material()
	if glyph_mat != null:
		_glyph = MeshInstance3D.new()
		_glyph.mesh = _get_glyph_mesh()
		_glyph.material_override = glyph_mat
		_glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glyph)

	# Pickup burst trio: expanding shell flash + radial ice shards + central
	# billboard flash. Materials are duplicated per box (alpha animates
	# independently); every node is created once here and reused on each
	# pickup — no per-pickup allocation beyond the one-shot tween.
	_burst_mat = _get_burst_base_material().duplicate() as StandardMaterial3D
	_burst = MeshInstance3D.new()
	_burst.mesh = _get_cube_mesh()
	_burst.material_override = _burst_mat
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.visible = false
	add_child(_burst)

	_shard_mat = _get_shard_base_material().duplicate() as StandardMaterial3D
	_shards = MeshInstance3D.new()
	_shards.mesh = _get_shard_mesh()
	_shards.material_override = _shard_mat
	_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards.visible = false
	add_child(_shards)

	_flash_mat = _get_flash_base_material().duplicate() as StandardMaterial3D
	_flash = MeshInstance3D.new()
	_flash.mesh = _get_flash_mesh()
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)

	# Two more pre-built burst layers: a cool horizontal shockwave ring
	# (reuses the halo torus) and a warm gold mote fan counter-rotating
	# against the ice shards — brightness + pattern variety so the burst
	# reads without relying on hue. Skipped on low particle quality (the
	# shell flash + shards + center flash still carry the read).
	if _fx_rich:
		_ring_mat = _get_ring_burst_base_material().duplicate() as StandardMaterial3D
		_ring = MeshInstance3D.new()
		_ring.mesh = _get_burst_ring_mesh()
		_ring.material_override = _ring_mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.visible = false
		add_child(_ring)

		_mote_mat = _get_mote_base_material().duplicate() as StandardMaterial3D
		_motes = MeshInstance3D.new()
		_motes.mesh = _get_shard_mesh()
		_motes.material_override = _mote_mat
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_motes.visible = false
		add_child(_motes)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_spin_time += delta
	# Slow two-axis tumble + gentle bob. The bob is kept small so the tumbling
	# solid stays inside its 1.4 pickup box.
	_visual.rotation.y += delta * 0.9
	_visual.rotation.x += delta * 0.37
	var bob := sin(_spin_time * 2.0) * 0.09
	_visual.position.y = bob
	if _glyph != null:
		# The medallion rides the bob with a small lag of its own, so it floats
		# inside the crate rather than being welded to it. Position only —
		# scale belongs to the respawn tween, and a per-frame scale write here
		# would fight it (the medallion would snap to full size while the crate
		# was still growing back in). The warm pulse lives in the panel shader.
		_glyph.position.y = bob + sin(_spin_time * 2.6 + _glow_phase) * 0.04


func _on_body_entered(body: Node3D) -> void:
	if not _active or not body is Racer:
		return
	var racer := body as Racer
	if racer.held_item != "" or racer.state == Racer.State.FINISHED:
		return
	_active = false
	var item := PowerupsDB.roll(racer.race_position, GameConfig.RACER_COUNT, _rng)
	racer.receive_item(item)
	if racer.is_player:
		AudioManager.play_sfx("sfx_powerup", 1.0, -2.0)
	_visual.visible = false
	_halo.visible = false
	if _glyph != null:
		_glyph.visible = false
	_play_burst()
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			_halo.visible = true
			if _glyph != null:
				_glyph.visible = true
			set_deferred("monitoring", true)
			_play_respawn())


## Respawn shimmer-in: the shell scales back up with a back-eased overshoot
## while the central flash blooms softly — the box condenses out of the air
## instead of popping into existence. Reuses the per-box flash node/material.
func _play_respawn() -> void:
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()
	_visual.scale = Vector3.ONE * 0.15
	_respawn_tween = create_tween()
	_respawn_tween.set_parallel(true)
	_respawn_tween.tween_property(_visual, "scale", Vector3.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glyph != null:
		_glyph.scale = Vector3.ONE * 0.15
		_respawn_tween.tween_property(_glyph, "scale", Vector3.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _flash != null:
		_flash.visible = true
		_flash.scale = Vector3.ONE * 0.4
		_flash_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
		_respawn_tween.tween_property(_flash, "scale", Vector3.ONE * 1.5, 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_respawn_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.35)
		_respawn_tween.chain().tween_callback(func() -> void:
			_flash.visible = false)


## One-shot pickup burst: additive shell flash + spinning radial ice shards
## + a quick central billboard flash + expanding shockwave ring + warm gold
## mote fan counter-rotating against the shards (ring + motes skipped on low
## particle quality). All nodes pre-built in _ready; only the one-shot tween
## is allocated per pickup.
func _play_burst() -> void:
	if _burst == null:
		return
	if _burst_tween != null and _burst_tween.is_valid():
		_burst_tween.kill()
	_burst.visible = true
	_burst.scale = Vector3.ONE * 1.02
	# Kept deliberately faint and short: this layer is the crate's own
	# silhouette blown up additively, so anything stronger reads as a giant
	# white box swallowing the racers rather than as a flash.
	_burst_mat.albedo_color = Color(1.0, 0.80, 0.34, 0.45)
	_shards.visible = true
	_shards.scale = Vector3.ONE * 0.9
	_shards.rotation.y = _rng.randf_range(0.0, TAU)
	_shard_mat.albedo_color = Color(0.88, 0.96, 1.0, 0.95)
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.6
	_flash_mat.albedo_color = Color(1.0, 0.90, 0.62, 0.85)
	if _ring != null:
		_ring.visible = true
		_ring.scale = Vector3.ONE * 0.7
		_ring_mat.albedo_color = Color(1.0, 0.78, 0.32, 0.9)
	if _motes != null:
		_motes.visible = true
		_motes.scale = Vector3.ONE * 0.45
		_motes.rotation.y = -_shards.rotation.y
		_mote_mat.albedo_color = Color(1.0, 0.88, 0.5, 0.95)
	_burst_tween = create_tween()
	_burst_tween.set_parallel(true)
	_burst_tween.tween_property(_burst, "scale", Vector3.ONE * 1.7, 0.20) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_burst_mat, "albedo_color:a", 0.0, 0.20)
	_burst_tween.tween_property(_shards, "scale", Vector3.ONE * 3.0, 0.44) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_shards, "rotation:y", _shards.rotation.y + 1.3, 0.44)
	_burst_tween.tween_property(_shard_mat, "albedo_color:a", 0.0, 0.44)
	_burst_tween.tween_property(_flash, "scale", Vector3.ONE * 3.0, 0.24) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.24)
	if _ring != null:
		_burst_tween.tween_property(_ring, "scale", Vector3.ONE * 3.6, 0.48) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_burst_tween.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.48)
	if _motes != null:
		_burst_tween.tween_property(_motes, "scale", Vector3.ONE * 2.1, 0.52) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_burst_tween.tween_property(_motes, "rotation:y", _motes.rotation.y - 1.7, 0.52)
		_burst_tween.tween_property(_mote_mat, "albedo_color:a", 0.0, 0.52)
	_burst_tween.chain().tween_callback(func() -> void:
		_burst.visible = false
		_shards.visible = false
		_flash.visible = false
		if _ring != null:
			_ring.visible = false
		if _motes != null:
			_motes.visible = false)


## --- Shared visual resources (built once, shared by all boxes) -----------


## Chamfered cube in two surfaces: surface 0 is the six inset ice panels,
## surface 1 is the gilded frame (12 edge bevels + 8 corner facets). Both are
## built with set_smooth_group(-1) so every facet keeps its own hard normal —
## that is what turns the crate into a chunky faceted solid with big value
## steps instead of the smooth translucent bubble it used to be. 44 triangles
## total; built once and shared by every box.
static func _get_cube_mesh() -> ArrayMesh:
	if _cube_mesh != null:
		return _cube_mesh
	var h := CUBE_HALF
	var inner := CUBE_HALF - CUBE_BEVEL
	var mesh := ArrayMesh.new()
	# Surface 0 — 6 main panels (inset squares at each axis extreme).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for axis: int in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for s: float in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(_axes_vec(axis, s * h, u, corner.x * inner, v, corner.y * inner))
			_add_face(st, pts)
	st.generate_normals()
	st.commit(mesh)
	# Surface 1 — the frame: 12 edge bevel quads (one per pair of adjacent
	# faces) + 8 corner triangles.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(0, 2)]:
		var a := pair.x
		var b := pair.y
		var c := 3 - a - b
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var pts: Array[Vector3] = [
					_axes_vec(a, sa * h, b, sb * inner, c, -inner),
					_axes_vec(a, sa * h, b, sb * inner, c, inner),
					_axes_vec(a, sa * inner, b, sb * h, c, inner),
					_axes_vec(a, sa * inner, b, sb * h, c, -inner),
				]
				_add_face(st, pts)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pts: Array[Vector3] = [
					Vector3(sx * h, sy * inner, sz * inner),
					Vector3(sx * inner, sy * h, sz * inner),
					Vector3(sx * inner, sy * inner, sz * h),
				]
				_add_face(st, pts)
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(0, _get_panel_material())
	mesh.surface_set_material(1, _get_frame_material())
	_cube_mesh = mesh
	return _cube_mesh


static func _axes_vec(a: int, av: float, b: int, bv: float, c: int, cv: float) -> Vector3:
	var out := Vector3.ZERO
	out[a] = av
	out[b] = bv
	out[c] = cv
	return out


## Fan-triangulates a convex polygon, auto-orienting to Godot's clockwise
## front-face winding (viewed from outside the origin-centered solid).
static func _add_face(st: SurfaceTool, pts: Array[Vector3]) -> void:
	var centroid := Vector3.ZERO
	for p: Vector3 in pts:
		centroid += p
	centroid /= float(pts.size())
	var normal := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	var ordered := pts
	if normal.dot(centroid) > 0.0:
		ordered = pts.duplicate()
		ordered.reverse()
	for i: int in range(1, ordered.size() - 1):
		st.add_vertex(ordered[0])
		st.add_vertex(ordered[i])
		st.add_vertex(ordered[i + 1])


## Whole-crate override: null in normal mode so the mesh's per-surface panel
## and frame materials show; a bright-gold emissive solid in high-contrast
## mode (same language as FishPickup / SnowballPickup).
static func _get_box_material() -> Material:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if not high_contrast:
		return null
	if _box_mat_contrast == null:
		_box_mat_contrast = StandardMaterial3D.new()
		_box_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
		_box_mat_contrast.emission_enabled = true
		_box_mat_contrast.emission = Color(1.0, 0.7, 0.05)
		_box_mat_contrast.emission_energy_multiplier = 1.8
		# Grow-pass rim: pushing the shell slightly outward along its
		# normals hardens the silhouette edge against any backdrop.
		_box_mat_contrast.grow = true
		_box_mat_contrast.grow_amount = 0.015
	return _box_mat_contrast


## Ice panel material (mesh surface 0): the inline shader above.
static func _get_panel_material() -> ShaderMaterial:
	if _panel_mat == null:
		var shader := Shader.new()
		shader.code = BOX_SHADER_CODE
		_panel_mat = ShaderMaterial.new()
		_panel_mat.shader = shader
	return _panel_mat


## Frame material (mesh surface 1): the twelve bevels and eight corner facets,
## OPAQUE warm gold. This is the crate's silhouette. Opaque matters twice over
## — it writes depth, so the frame edge stays hard against any backdrop, and
## being mid-value warm it is the one part of the crate that separates from
## sunlit snow (where the bright panels wash out) AND from night sky (where a
## dark outline would vanish). Metallic is kept low: gl_compatibility has no
## reflection probes, so a strongly metallic gold just mirrors the sky and
## goes pale.
static func _get_frame_material() -> StandardMaterial3D:
	if _frame_mat == null:
		_frame_mat = StandardMaterial3D.new()
		# Albedo is deliberately a deep amber rather than a bright gold: under
		# the glacier sun a bright gold tonemaps straight to near-white and the
		# frame stops separating from snow, so the sunlit read is carried by a
		# darker, more saturated base and the night read by emission.
		_frame_mat.albedo_color = Color(0.72, 0.40, 0.07)
		_frame_mat.metallic = 0.2
		_frame_mat.metallic_specular = 0.85
		_frame_mat.roughness = 0.3
		_frame_mat.emission_enabled = true
		_frame_mat.emission = Color(1.0, 0.68, 0.24)
		_frame_mat.emission_energy_multiplier = 0.5
		_frame_mat.rim_enabled = true
		_frame_mat.rim = 0.65
		_frame_mat.rim_tint = 0.25
	return _frame_mat


static func _get_glyph_mesh() -> QuadMesh:
	if _glyph_mesh != null:
		return _glyph_mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.78, 0.78)
	_glyph_mesh = mesh
	return _glyph_mesh


## Billboard glyph material; null when the SVG module is unavailable
## (headless), in which case the glyph node is simply skipped.
static func _get_glyph_material() -> StandardMaterial3D:
	if _glyph_mat != null:
		return _glyph_mat
	var tex := UITheme.make_icon(GLYPH_SVG, 2.0)
	if tex == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	# Draw AFTER the ice panels in the transparent pass so the medallion stays
	# crisp; the panels never write depth, so it still sits visually inside the
	# crate while opaque geometry in front of the box occludes it normally.
	mat.render_priority = 3
	_glyph_mat = mat
	return mat


static func _get_burst_base_material() -> StandardMaterial3D:
	if _burst_base_mat != null:
		return _burst_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.80, 0.34, 0.0)
	mat.render_priority = 1
	_burst_base_mat = mat
	return _burst_base_mat


## Radial ice-shard fan for the pickup burst: thin triangles distributed on
## a golden-angle sphere spiral with deterministic length variance.
static func _get_shard_mesh() -> ArrayMesh:
	if _shard_mesh != null:
		return _shard_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 14
	for i: int in count:
		var g := float(i) * 2.39996
		var y := lerpf(-0.75, 0.75, (float(i) + 0.5) / float(count))
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var dir := Vector3(cos(g) * r, y, sin(g) * r)
		var ref_axis := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var tangent := dir.cross(ref_axis).normalized()
		var tip := 0.55 + 0.25 * fmod(float(i) * 0.618, 1.0)
		st.add_vertex(dir * 0.3 + tangent * 0.05)
		st.add_vertex(dir * 0.3 - tangent * 0.05)
		st.add_vertex(dir * tip)
	_shard_mesh = st.commit()
	return _shard_mesh


static func _get_shard_base_material() -> StandardMaterial3D:
	if _shard_base_mat != null:
		return _shard_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.0)
	mat.render_priority = 1
	_shard_base_mat = mat
	return _shard_base_mat


static func _get_flash_mesh() -> QuadMesh:
	if _flash_mesh != null:
		return _flash_mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.1, 1.1)
	_flash_mesh = mesh
	return _flash_mesh


static func _get_flash_base_material() -> StandardMaterial3D:
	if _flash_base_mat != null:
		return _flash_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.85)
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	mat.render_priority = 2
	_flash_base_mat = mat
	return _flash_base_mat


## Ground marker: one horizontal quad with a soft radial falloff. Replaces the
## old 288-triangle torus with 2 triangles for a stronger read.
static func _get_halo_mesh() -> QuadMesh:
	if _halo_mesh == null:
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(1.9, 1.9)
		_halo_mesh.orientation = PlaneMesh.FACE_Y
	return _halo_mesh


## Torus used only by the pickup shockwave ring (the ground marker is a disc).
static func _get_burst_ring_mesh() -> TorusMesh:
	if _burst_ring_mesh == null:
		_burst_ring_mesh = TorusMesh.new()
		_burst_ring_mesh.inner_radius = 0.5
		_burst_ring_mesh.outer_radius = 0.62
		_burst_ring_mesh.rings = 20
		_burst_ring_mesh.ring_segments = 4
	return _burst_ring_mesh


static func _get_ring_burst_base_material() -> StandardMaterial3D:
	if _ring_burst_base_mat != null:
		return _ring_burst_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.0)
	mat.render_priority = 1
	_ring_burst_base_mat = mat
	return _ring_burst_base_mat


static func _get_mote_base_material() -> StandardMaterial3D:
	if _mote_base_mat != null:
		return _mote_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.0)
	mat.render_priority = 1
	_mote_base_mat = mat
	return _mote_base_mat


## Ground marker material: a warm HIGH-key wash, kept light in every channel.
## A saturated amber at this alpha subtracts blue from night snow and the pool
## goes muddy-olive under the crate; keeping all three channels high makes it
## read as a pool of warm light on dark snow and a soft warm tint on bright
## snow. The crate itself now carries the pickup read, so this only has to
## anchor it to the lane.
static func _get_halo_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _halo_mat_contrast == null:
			_halo_mat_contrast = _make_disc_material(Color(1.0, 0.86, 0.35, 0.7))
		return _halo_mat_contrast
	if _halo_mat == null:
		_halo_mat = _make_disc_material(Color(1.0, 0.88, 0.62, 0.42))
	return _halo_mat


static func _make_disc_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -3
	return mat
