extends Node
## Lighting/palette regression only. Raster readability still needs the four
## real biome captures; these checks do not claim a rendered contrast ratio.

## Stable lower bounds from the original readability pass, before DAY's
## reviewed cyan-ice promotion. A brighter DAY must not silently require new
## CAVE/NIGHT paint (or weaker snow contrast); their existing minimum remains
## 80% of this baseline's linear luminance. These are test fixtures, not new
## runtime colors. Preserve the original tunnel attenuation in the fixture too.
const READABILITY_DAY_BASELINE: Color = Color(0.34, 0.53, 0.69)
const READABILITY_TUNNEL_MULTIPLIER: Color = Color(0.66, 0.72, 0.86, 1.0)

var _checks: int = 0
var _failures: int = 0

class CountingEnvironmentRunner:
	extends RunnerGame
	var target_builds: int = 0

	func _runner_environment(biome: int) -> Dictionary:
		target_builds += 1
		return super._runner_environment(biome)


func _ready() -> void:
	_test_palette()
	_test_environment_blends()
	_test_environment_target_cache()
	print("[runner_biome_readability] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[runner_biome_readability] FAIL ", label)


func _luminance(srgb: Color) -> float:
	var linear := srgb.srgb_to_linear()
	return linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722


func _test_environment_target_cache() -> void:
	var game := CountingEnvironmentRunner.new()
	var reference := RunnerGame.new()
	var expected_builds := 0
	for authored: bool in [false, true, false]:
		game._runner_art_set = load(RunnerGame.RUNNER_ART_SET_PATH) if authored else null
		reference._runner_art_set = game._runner_art_set
		# Adjacent DAY entries deliberately hold the same biome while the art set
		# changes. That transition must invalidate the target too.
		for biome: int in [0, 1, 2, 3, 0]:
			expected_builds += 1
			var expected := reference._runner_environment(biome)
			var matches := true
			for _frame: int in 120:
				matches = matches and game._environment_blend_target(biome) == expected
			_check(matches, "cached target preserves every authored/fallback value")
			_check(game.target_builds == expected_builds,
				"120 steady frames resolve/validate target only once")
	game.free()
	reference.free()


func _test_palette() -> void:
	var minimum_deck := _luminance(READABILITY_DAY_BASELINE) * 0.80
	var day_shelf := _luminance(RunnerTrack._biome_shelf_tint(RunnerTrack.Biome.DAY))
	var minimum_tunnel := _luminance(READABILITY_DAY_BASELINE * READABILITY_TUNNEL_MULTIPLIER) * 0.80
	for biome: int in RunnerTrack.BIOME_COUNT:
		var label := RunnerGame.BIOME_IDS[biome]
		var deck := RunnerTrack._biome_deck_tint(biome)
		var shelf := RunnerTrack._biome_shelf_tint(biome)
		# Later weather already reduces illumination. Do not compound it with
		# road paint below the established readability floor, including tunnels.
		_check(_luminance(deck) >= minimum_deck, label + " road albedo floor")
		_check(_luminance(RunnerTrack._deck_tint(biome, true)) >= minimum_tunnel,
				label + " tunnel road albedo floor")
		_check(_luminance(shelf) >= day_shelf * 0.40, label + " snow albedo floor")
		_check(_luminance(shelf) >= _luminance(deck) * 3.0,
				label + " snow still frames road")
		_check(_luminance(RunnerTrack._biome_kerb_body(biome)) >= _luminance(deck) * 0.8,
				label + " kerb face remains visible")
		_check(_luminance(RunnerTrack._biome_kerb_deep(biome)) < _luminance(deck) * 0.5,
				label + " drop-off stays below route")
		# Check the real cached shader material consumes the palette, so a
		# dormant helper cannot make this regression pass while the road stays dark.
		var material := RunnerTrack._deck_material(biome, false)
		var material_tint: Color = material.get_shader_parameter("tint")
		_check(material_tint.is_equal_approx(deck), label + " actual deck uses palette")
		var snow := RunnerTrack._verge_snow_material(biome, false)
		var snow_tint: Color = snow.get_shader_parameter("tint")
		_check(snow_tint.is_equal_approx(shelf), label + " actual snow uses palette")
		if biome == RunnerTrack.Biome.DUSK:
			_check(deck.r > deck.b and deck.b > deck.g, "dusk retains purple road")
		elif biome == RunnerTrack.Biome.CAVE or biome == RunnerTrack.Biome.NIGHT:
			_check(deck.b > deck.g and deck.g > deck.r, label + " retains blue road")


func _test_environment_blends() -> void:
	# Do not enter the tree: no startup, meshes, physics, audio or save writes.
	# Exercise the production blend against real Godot Environment/light nodes.
	var game := RunnerGame.new()
	game.track = RunnerTrack.new()
	game.player = RunnerPlayer.new()
	game._world_env = WorldEnvironment.new()
	game._sun = DirectionalLight3D.new()
	game._fill = DirectionalLight3D.new()
	game._rim = OmniLight3D.new()
	for child: Node in [game.track, game.player, game._world_env,
			game._sun, game._fill, game._rim]:
		game.add_child(child)
	var env := Environment.new()
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	game._world_env.environment = env
	for authored: bool in [false, true]:
		game._runner_art_set = load(RunnerGame.RUNNER_ART_SET_PATH) if authored else null
		for biome: int in [0, 1, 2, 3, 0]:
			var label := "%s %s" % ["authored" if authored else "fallback", RunnerGame.BIOME_IDS[biome]]
			var want := game._runner_environment(biome)
			var previous_fill := game._fill.light_energy
			game.player.position.z = -(float(biome) * RunnerTrack.BIOME_LENGTH + 180.0)
			game._blend_biome(1.0 / 60.0)
			var target_fill := float(want["fill_energy"])
			_check(game._fill.light_energy >= minf(previous_fill, target_fill) - 0.0001
					and game._fill.light_energy <= maxf(previous_fill, target_fill) + 0.0001,
					label + " transition stays between lighting endpoints")
			game._blend_biome(2.0)
			var sky := env.sky.sky_material as ProceduralSkyMaterial
			var expected_sky: Color = want["sky_top"]
			_check(sky.sky_top_color.is_equal_approx(expected_sky), label + " sky identity preserved")
			_check(is_equal_approx(env.fog_density, float(want["fog_density"])), label + " fog preserved")
			if biome == RunnerTrack.Biome.DAY:
				_check(is_equal_approx(env.ambient_light_sky_contribution, 0.55), label + " reference day sky and white bounce restored")
				_check(is_equal_approx(game._fill.light_energy, 0.40), label + " reference day fill restored")
			else:
				# Explicit bounce remains useful even if the backdrop is black.
				var bounce := _luminance(env.ambient_light_color) * env.ambient_light_energy \
						* (1.0 - env.ambient_light_sky_contribution)
				_check(bounce >= 0.17, label + " independent ambient floor")
				_check(_luminance(game._fill.light_color) * game._fill.light_energy >= 0.24,
						label + " directional fill floor")
				_check(game._rim.light_energy >= 1.1, label + " player edge light floor")
	game.free()
