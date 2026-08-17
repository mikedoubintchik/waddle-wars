extends Node3D
## Renders a SnowTrail with hand-dropped streaks over a plain floor.
## Iterating on the streak look through full race boots took minutes per look;
## this is seconds, and it isolates the MultiMesh render path from everything.
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.7, 0.9)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.85, 0.95)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.25
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	floor_mesh.material_override = VisualLibrary.snow_material(Color(0.93, 0.96, 1.0))
	add_child(floor_mesh)

	var trail := SnowTrail.new()
	add_child(trail)
	trail.setup()
	# Fake a curved run of streaks.
	for i: int in 40:
		var t := float(i) / 39.0
		var pos := Vector3(sin(t * 2.5) * 4.0, 0.0, -12.0 + t * 20.0)
		trail.tick(pos, Vector3.UP, true, i % 2 == 0, 10.0)
		trail._last_drop = Vector3.INF  # force every call to drop

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 6.0, 12.0)
	add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0, -2))
	cam.current = true

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() < 1500:
		return
	set_process(false)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var out := "/private/tmp/claude-502/-Users-ninja-Fun-waddle-wars/0d4331c0-2759-4f25-a5f0-a91b099cdd38/scratchpad/pg/trail_iso.png"
	image.save_png(out)
	print("[trail_shot] saved ", out)
	get_tree().quit()
