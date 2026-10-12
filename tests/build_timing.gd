extends Node
## Where does the loading freeze come from?
##
## The web build is single-threaded WASM: any work done inside one frame
## blocks the renderer, so the loading penguin stops dancing for exactly as
## long as the longest synchronous block. This measures the two suspects --
## course construction and the eight procedural penguins -- so the staging
## work can be aimed at whichever actually costs the frames.
##
##   godot --headless res://tests/build_timing.tscn
##
## Headless numbers are a floor, not the web cost: no GPU uploads and no
## shader links happen here, and WASM runs several times slower than native.
## Relative weight between the phases is what this is for.

const COURSES: PackedStringArray = ["glacier", "aurora", "iceberg", "cinder", "hollow"]

## `staged=1` forces the web construction path (CourseBase.stage yields a frame
## whenever its budget is spent) so it can be exercised without an export. The
## report then shows how many frames each course spreads itself over and the
## longest single block inside it — that block IS the visible hitch.
var _staged: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "staged=1":
			_staged = true
	CourseBase.force_staged_build = _staged
	print("[build_timing] --- course construction (staged=%s) ---" % str(_staged))
	var worst := 0.0
	for id: String in COURSES:
		var info := CoursesDB.get_item(id)
		var path := String(info.get("script", ""))
		if path == "":
			print("[build_timing] %-9s no script in CoursesDB" % id)
			continue
		var script: GDScript = load(path)
		var t0 := Time.get_ticks_usec()
		var course := script.new() as CourseBase
		course.course_id = id
		add_child(course)
		var frames := 0
		var longest_block := 0.0
		if not course.build_finished:
			# Staged: measure each frame's slice separately. The worst slice is
			# what a player actually perceives, not the sum.
			var mark := Time.get_ticks_usec()
			while not course.build_finished:
				await get_tree().process_frame
				longest_block = maxf(longest_block, float(Time.get_ticks_usec() - mark) / 1000.0)
				mark = Time.get_ticks_usec()
				frames += 1
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, longest_block if _staged else ms)
		print("[build_timing] %-9s total %7.1f ms  frames %3d  worst frame %6.1f ms  nodes %5d"
			% [id, ms, frames, longest_block if _staged else ms, _count_nodes(course)])
		course.free()

	print("[build_timing] --- racers (PenguinVisual.setup, the deferred spawn burst) ---")
	var configs: Array[Dictionary] = []
	for key: String in PersonalitiesDB.ORDER:
		var p := PersonalitiesDB.get_item(key)
		configs.append({
			"body_color": p.get("body_color", Color(0.13, 0.16, 0.22)),
			"belly_color": p.get("belly_color", Color(0.95, 0.94, 0.9)),
		})
	var t1 := Time.get_ticks_usec()
	var visuals: Array[Node] = []
	for config: Dictionary in configs:
		var v := PenguinVisual.new()
		v.setup(config)
		add_child(v)
		visuals.append(v)
	var burst := float(Time.get_ticks_usec() - t1) / 1000.0
	print("[build_timing] %d penguins %8.1f ms  (%.1f ms each)"
		% [configs.size(), burst, burst / maxf(1.0, float(configs.size()))])
	for v: Node in visuals:
		v.free()
	print("[build_timing] worst blocking slice %.1f ms, spawn burst %.1f ms" % [worst, burst])
	get_tree().quit()


func _count_nodes(root: Node) -> int:
	var total := 1
	for child: Node in root.get_children():
		total += _count_nodes(child)
	return total
