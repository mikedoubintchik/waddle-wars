extends Node
## Count actual production sky assignments in a test-only subclass. Native
## ProceduralSkyMaterial setters expose no change signal/counter, so inject
## counters immediately before those four statements without rewriting their
## conditions or blend math. No renderer or production instrumentation needed.
## Run: godot --headless --path . res://tests/runner_sky_uniform_test.tscn

const SKY_PROPERTIES = [
	"sky_top_color", "sky_horizon_color", "ground_horizon_color", "ground_bottom_color",
]
const TARGET_KEYS = ["sky_top", "sky_horizon", "ground_horizon", "ground_bottom"]
const SETTLED_FRAMES: int = 32
const EXPECTED_BODY_CHECKS: int = 105
const PRESERVED_ENV_PROPERTIES = [
	"sky", "ambient_light_source", "ambient_light_color", "ambient_light_energy",
	"ambient_light_sky_contribution", "fog_enabled", "fog_light_color", "fog_density",
	"fog_aerial_perspective", "fog_sky_affect", "tonemap_mode", "tonemap_exposure",
	"tonemap_white",
]


class ExitCleanupProbe:
	extends RunnerGame

	func _ready() -> void:
		# Enter/exit lifecycle only. Never build geometry or submit warmup work.
		set_process(false)
		set_process_unhandled_input(false)

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_run()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[runner_sky_uniform] FAIL " + label)


func _run() -> void:
	var probe_script := _instrumented_script()
	if probe_script != null:
		for fps: int in [30, 60]:
			_test_blend(probe_script, fps)
	_test_covered_warmup_policy()
	_test_covered_warmup_guards()
	for reflection: int in [Environment.REFLECTION_SOURCE_BG, Environment.REFLECTION_SOURCE_SKY]:
		_test_covered_warmup_restore(reflection)
	_test_covered_warmup_exit()
	_check(_checks == EXPECTED_BODY_CHECKS,
			"all %d body checks completed (observed %d)" % [EXPECTED_BODY_CHECKS, _checks])
	print("[runner_sky_uniform] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _instrumented_script() -> GDScript:
	var source := FileAccess.get_file_as_string("res://scripts/runner/runner_game.gd")
	var start := source.find("func _blend_biome(delta: float) -> void:")
	_check(start >= 0, "production blend function found")
	if start < 0:
		return null
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start if end >= 0 else -1)
	var instrumented := ""
	var assignments := 0
	for line: String in body.split("\n"):
		for property: String in SKY_PROPERTIES:
			if line.strip_edges().begins_with("sky_mat.%s =" % property):
				instrumented += line.substr(0, line.find("sky_mat.")) \
						+ "sky_write_count += 1\n"
				assignments += 1
		instrumented += line + "\n"
	_check(assignments == 4, "exactly four native sky setters instrumented")
	if assignments != 4:
		return null
	var script := GDScript.new()
	script.source_code = "extends \"res://scripts/runner/runner_game.gd\"\n" \
			+ "var sky_write_count: int = 0\n\n" + instrumented
	var error := script.reload()
	_check(error == OK, "instrumented production function compiles")
	return script if error == OK else null


func _test_blend(probe_script: GDScript, fps: int) -> void:
	# Leave the fixture outside SceneTree so RunnerGame._ready() cannot create
	# a course, warmup, camera or GPU effects. Call only the real blend function.
	var game := probe_script.new() as RunnerGame
	game.track = RunnerTrack.new()
	game.add_child(game.track)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game._world_env = WorldEnvironment.new()
	game.add_child(game._world_env)
	var env := Environment.new()
	game._world_env.environment = env
	env.sky = Sky.new()
	var actual := ProceduralSkyMaterial.new()
	env.sky.sky_material = actual
	var reference := ProceduralSkyMaterial.new()
	var target := game._runner_environment(RunnerTrack.Biome.DAY)
	for i: int in SKY_PROPERTIES.size():
		actual.set(SKY_PROPERTIES[i], target[TARGET_KEYS[i]])
		reference.set(SKY_PROPERTIES[i], target[TARGET_KEYS[i]])
	var delta := 1.0 / float(fps)
	for _frame: int in fps * 2:
		game._blend_biome(delta)
	_check(int(game.get("sky_write_count")) == 0, "%d FPS stationary DAY writes zero" % fps)
	_check(_same_colors(actual, reference), "%d FPS stationary DAY colors unchanged" % fps)

	# Follow every transition, including return to DAY, until the original
	# float-color lerp reaches its unchanged representable value. Exact equality,
	# not a tolerance or a newly introduced snap-to-target threshold.
	for biome: int in [RunnerTrack.Biome.DUSK, RunnerTrack.Biome.CAVE,
			RunnerTrack.Biome.NIGHT, RunnerTrack.Biome.DAY]:
		game.player.position.z = -(float(biome) * RunnerTrack.BIOME_LENGTH + 72.0)
		target = game._runner_environment(game.track.biome_at_z(game.player.position.z))
		var label := "%d FPS %s" % [fps, RunnerGame.BIOME_IDS[biome]]
		game.set("sky_write_count", 0)
		var expected_writes := 0
		var settled := 0
		var first_mismatch := -1
		for frame: int in fps * 40:
			var changed := _advance_reference(reference, target, delta)
			expected_writes += changed
			game._blend_biome(delta)
			if first_mismatch < 0 and not _same_colors(actual, reference):
				first_mismatch = frame
			settled = settled + 1 if changed == 0 else 0
			if settled >= SETTLED_FRAMES:
				break
		_check(first_mismatch < 0, label + " exact old lerp sequence (first mismatch %d)" % first_mismatch)
		_check(expected_writes > 0, label + " transition changes colors")
		_check(int(game.get("sky_write_count")) == expected_writes,
				label + " writes only colors changed by original lerp")
		_check(settled >= SETTLED_FRAMES, label + " reaches original float arrival")
		game.set("sky_write_count", 0)
		for _frame: int in fps:
			_advance_reference(reference, target, delta)
			game._blend_biome(delta)
		_check(int(game.get("sky_write_count")) == 0, label + " settled tail writes zero")
		_check(_same_colors(actual, reference), label + " settled tail remains exact")

	# k=0 also leaves an in-flight transition completely unchanged.
	game.player.position.z = -(RunnerTrack.BIOME_LENGTH + 72.0)
	game.set("sky_write_count", 0)
	game._blend_biome(0.0)
	_check(int(game.get("sky_write_count")) == 0, "%d FPS zero-delta writes zero" % fps)
	_check(_same_colors(actual, reference), "%d FPS zero-delta colors unchanged" % fps)
	game.free()


func _test_covered_warmup_policy() -> void:
	for case: Array in [
		[true, "gl_compatibility", true], [false, "gl_compatibility", false],
		[true, "mobile", false], [true, "forward_plus", false],
		[true, "", false], [true, "GL_COMPATIBILITY", false],
	]:
		_check(RunnerGame.use_covered_background_warmup(case[0], case[1]) == case[2],
			"covered warmup platform=%s renderer=%s" % [case[0], case[1]])


func _test_covered_warmup_guards() -> void:
	var game := RunnerGame.new()
	_check(not game._defer_warmup_background(null) and game._covered_warmup_environment == null,
		"null detached environment rejected without arming restore")
	var env := _covered_environment()
	var sky := env.sky
	env.sky = null
	_check(not game._defer_warmup_background(env) and game._covered_warmup_environment == null,
		"detached environment without sky rejected")
	env.sky = sky
	for background: int in [Environment.BG_COLOR, Environment.BG_KEEP]:
		env.background_mode = background
		_check(not game._defer_warmup_background(env)
			and env.background_mode == background
			and env.reflected_light_source == Environment.REFLECTION_SOURCE_BG
			and game._covered_warmup_environment == null,
			"non-sky background %d rejected unchanged" % background)
	env.background_mode = Environment.BG_SKY
	for ambient: int in [Environment.AMBIENT_SOURCE_COLOR, Environment.AMBIENT_SOURCE_BG]:
		env.ambient_light_source = ambient
		_check(not game._defer_warmup_background(env)
			and env.ambient_light_source == ambient and env.background_mode == Environment.BG_SKY
			and game._covered_warmup_environment == null,
			"non-explicit-sky ambient %d rejected unchanged" % ambient)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_check(not game._defer_warmup_background(env)
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED
		and env.background_mode == Environment.BG_SKY and game._covered_warmup_environment == null,
		"disabled reflections rejected unchanged")
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	game._restore_covered_warmup_background()
	_check(env.background_mode == Environment.BG_SKY
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_BG
		and game._covered_warmup_environment == null,
		"restore without an active environment is harmless")
	game._world_env = WorldEnvironment.new()
	game._world_env.environment = env
	game.add_child(game._world_env)
	var snapshot := _covered_environment_snapshot(env)
	_check(not game._begin_covered_background_warmup()
		and env.background_mode == Environment.BG_SKY
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_BG
		and game._covered_warmup_environment == null and _covered_environment_matches(env, snapshot),
		"headless/direct detached production entry skips covered work")
	game.free()


func _test_covered_warmup_restore(reflection: int) -> void:
	var game := RunnerGame.new()
	var env := _covered_environment()
	env.reflected_light_source = reflection
	var sky := env.sky
	var material := sky.sky_material
	var snapshot := _covered_environment_snapshot(env)
	var msaa := get_viewport().msaa_3d
	var label := "reflection source %d " % reflection
	_check(game._defer_warmup_background(env), label + "arms covered background")
	_check(game._covered_warmup_environment == env
		and game._covered_background_mode == Environment.BG_SKY
		and game._covered_reflection_source == reflection,
		label + "retains exact original environment and flags")
	_check(env.background_mode == Environment.BG_KEEP
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
		label + "KEEP retains explicit SKY reflections")
	_check(env.sky == sky and env.sky.sky_material == material,
		label + "same sky and material resources retained")
	_check(_covered_environment_matches(env, snapshot),
		label + "sky colors ambient fog and tone mapping unchanged")
	_check(get_viewport().msaa_3d == msaa, label + "viewport MSAA unchanged")
	_check(not game._defer_warmup_background(env)
		and game._covered_reflection_source == reflection and env.background_mode == Environment.BG_KEEP,
		label + "repeated defer cannot overwrite original flags")
	var other := _covered_environment()
	_check(not game._defer_warmup_background(other)
		and game._covered_warmup_environment == env and other.background_mode == Environment.BG_SKY
		and other.reflected_light_source == Environment.REFLECTION_SOURCE_BG,
		label + "second environment rejected while first owns restore")
	game._restore_covered_warmup_background()
	_check(env.background_mode == Environment.BG_SKY and env.reflected_light_source == reflection
		and game._covered_warmup_environment == null,
		label + "restore returns exact original background and reflection")
	_check(_covered_environment_matches(env, snapshot) and get_viewport().msaa_3d == msaa,
		label + "restore preserves every other resource and setting")
	game._restore_covered_warmup_background()
	_check(env.background_mode == Environment.BG_SKY and env.reflected_light_source == reflection
		and _covered_environment_matches(env, snapshot), label + "repeated restore is idempotent")
	_check(game._defer_warmup_background(env) and game._covered_reflection_source == reflection,
		label + "restored environment supports fresh entry")
	game._restore_covered_warmup_background()
	_check(env.background_mode == Environment.BG_SKY and env.reflected_light_source == reflection
		and game._covered_warmup_environment == null and _covered_environment_matches(env, snapshot),
		label + "fresh entry restores original flags again")
	game.free()


func _test_covered_warmup_exit() -> void:
	var game := ExitCleanupProbe.new()
	var env := _covered_environment()
	var snapshot := _covered_environment_snapshot(env)
	var msaa := get_viewport().msaa_3d
	add_child(game)
	_check(game.is_inside_tree() and game.track == null and game._world_env == null,
		"exit probe enters tree without gameplay or render construction")
	_check(game._defer_warmup_background(env), "exit probe arms detached environment")
	_check(env.background_mode == Environment.BG_KEEP
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
		"exit probe has temporary flags before removal")
	remove_child(game)
	_check(env.background_mode == Environment.BG_SKY
		and env.reflected_light_source == Environment.REFLECTION_SOURCE_BG
		and game._covered_warmup_environment == null,
		"production scene exit restores interrupted covered warmup")
	_check(_covered_environment_matches(env, snapshot) and get_viewport().msaa_3d == msaa,
		"scene exit retains sky ambient fog and MSAA")
	game.free()


func _covered_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.ambient_light_color = Color(0.12, 0.23, 0.34)
	env.ambient_light_energy = 0.38
	env.ambient_light_sky_contribution = 0.57
	env.fog_enabled = true
	env.fog_light_color = Color(0.4, 0.76, 0.95)
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.86
	env.tonemap_white = 6.0
	return env


func _covered_environment_snapshot(env: Environment) -> Dictionary:
	var snapshot := {}
	for property: String in PRESERVED_ENV_PROPERTIES:
		snapshot[property] = env.get(property)
	snapshot["sky_radiance_size"] = env.sky.radiance_size
	snapshot["sky_process_mode"] = env.sky.process_mode
	snapshot["sky_material"] = env.sky.sky_material
	for property: String in SKY_PROPERTIES:
		snapshot["material:" + property] = env.sky.sky_material.get(property)
	return snapshot


func _covered_environment_matches(env: Environment, snapshot: Dictionary) -> bool:
	for property: String in PRESERVED_ENV_PROPERTIES:
		if env.get(property) != snapshot[property]:
			return false
	if env.sky.radiance_size != snapshot["sky_radiance_size"] \
			or env.sky.process_mode != snapshot["sky_process_mode"] \
			or env.sky.sky_material != snapshot["sky_material"]:
		return false
	for property: String in SKY_PROPERTIES:
		if env.sky.sky_material.get(property) != snapshot["material:" + property]:
			return false
	return true


func _advance_reference(material: ProceduralSkyMaterial, target: Dictionary,
		delta: float) -> int:
	var changed := 0
	var k := clampf(delta * 0.9, 0.0, 1.0)
	for i: int in SKY_PROPERTIES.size():
		var current: Color = material.get(SKY_PROPERTIES[i])
		var next := current.lerp(target.get(TARGET_KEYS[i], current), k)
		changed += int(next != current)
		# Original production behavior: all four setters, unconditionally.
		material.set(SKY_PROPERTIES[i], next)
	return changed


func _same_colors(actual: ProceduralSkyMaterial, reference: ProceduralSkyMaterial) -> bool:
	for property: String in SKY_PROPERTIES:
		if actual.get(property) != reference.get(property):
			return false
	return true
