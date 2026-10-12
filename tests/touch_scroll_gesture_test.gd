extends Node
## Real viewport touch routing: horizontal choices, nested vertical pages and
## release cancellation. No network calls or player-save mutations.

var _checks := 0
var _failed := 0
var _pressed := 0
var _started := 0
var _ended := 0
var _viewport: SubViewport


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var previous_touch := GameConfig.force_touch
	var original_window_size := get_window().size
	GameConfig.force_touch = true
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(640, 900)
	_viewport.disable_3d = true
	add_child(_viewport)
	var root := Control.new()
	root.size = Vector2(640, 900)
	_viewport.add_child(root)
	var horizontal := _horizontal(root, Vector2(20, 20))
	horizontal.scroll_started.connect(func() -> void: _started += 1)
	horizontal.scroll_ended.connect(func() -> void: _ended += 1)
	await _frames(4)
	_check(TouchScroll.attach(horizontal) == horizontal.get_node("TouchScroll"), "attachment is idempotent")
	var start := horizontal.global_position + Vector2(110, 45)
	_touch(start, true)
	await _frames(1)
	_drag(start, start - Vector2(80, 2))
	_touch(start - Vector2(80, 2), false)
	await _frames(3)
	_check(horizontal.scroll_horizontal >= 70, "swipe starting on item button scrolls horizontally")
	_check(horizontal.scroll_vertical == 0, "horizontal gesture does not change vertical offset")
	_check(_pressed == 0, "swipe release never activates the dragged item")
	_check(_started == 1 and _ended == 1, "one begin and end signal for entire swipe")
	# Tiny finger jitter still counts as one tap.
	start = horizontal.global_position + Vector2(85, 45)
	_touch(start, true)
	_drag(start, start + Vector2(2, 1))
	_touch(start + Vector2(2, 1), false)
	await _frames(2)
	_check(_pressed == 1, "small movement retains normal tap selection")
	var before := horizontal.scroll_horizontal
	_touch(Vector2(450, 60), true)
	_drag(Vector2(450, 60), Vector2(350, 60))
	_touch(Vector2(350, 60), false)
	await _frames(2)
	_check(horizontal.scroll_horizontal == before, "outside gesture cannot move carousel")
	# A second finger must not take over the first finger's drag.
	start = horizontal.global_position + Vector2(130, 40)
	_touch(start, true, 0)
	_touch(start, true, 1)
	_drag(start, start - Vector2(50, 0), 1)
	_check(horizontal.scroll_horizontal == before, "second finger cannot steal active gesture")
	_drag(start, start - Vector2(45, 0), 0)
	_touch(start - Vector2(45, 0), false, 0, true)
	_touch(start - Vector2(50, 0), false, 1, true)
	await _frames(2)
	_check(horizontal.scroll_horizontal > before, "first finger still controls carousel")
	_check((horizontal.get_node("TouchScroll") as TouchScroll)._active_index == -1,
		"cancelled gesture releases ownership")
	var vertical := ScrollContainer.new()
	vertical.position = Vector2(20, 200)
	vertical.size = Vector2(300, 270)
	vertical.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	root.add_child(vertical)
	TouchScroll.attach(vertical)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size.x = 300
	vertical.add_child(stack)
	var nested := _horizontal(stack, Vector2.ZERO)
	for index: int in 7:
		var row := Button.new()
		row.text = "Vertical row %d" % index
		row.custom_minimum_size = Vector2(280, 85)
		stack.add_child(row)
	await _frames(4)
	start = nested.global_position + Vector2(150, 40)
	_touch(start, true)
	_drag(start, start - Vector2(75, 3))
	_touch(start - Vector2(75, 3), false)
	await _frames(3)
	_check(nested.scroll_horizontal >= 65, "nested carousel owns horizontal gesture")
	_check(vertical.scroll_vertical == 0, "horizontal child does not drag parent page")
	before = nested.scroll_horizontal
	start = nested.global_position + Vector2(150, 50)
	_touch(start, true)
	_drag(start, start - Vector2(2, 60))
	_touch(start - Vector2(2, 60), false)
	await _frames(3)
	_check(vertical.scroll_vertical >= 50, "vertical gesture over carousel scrolls parent page")
	_check(nested.scroll_horizontal == before, "vertical gesture does not nudge carousel")
	# Cards clipped out of their parent cannot claim a new gesture.
	vertical.scroll_vertical = 160
	await _frames(3)
	start = nested.global_position + Vector2(100, 40)
	_touch(start, true)
	_drag(start, start - Vector2(60, 0))
	_touch(start - Vector2(60, 0), false)
	await _frames(2)
	_check(nested.scroll_horizontal == before, "offscreen nested list cannot intercept touches")
	root.queue_free()
	await _frames(3)
	# Godot's headless window defaults to a tiny surface. Wardrobe converts
	# 48 physical-pixel arrow targets into logical canvas units, so model both
	# the real phone window and its stretched canvas, not only a SubViewport.
	get_window().size = Vector2i(430, 932)
	_viewport.size = Vector2i(800, 1734)
	await _frames(4)
	var menu := load("res://scenes/menus/customize.tscn").instantiate() as Control
	_viewport.add_child(menu)
	await _frames(8)
	var equipped_before := Progression.equipped().duplicate(true)
	for category: String in ["body", "hat", "trail"]:
		menu.call("_select_category", category)
		await _frames(8)
		var gallery := menu.find_child("WardrobeGalleryScroll", true, false) as ScrollContainer
		gallery.scroll_horizontal = 0
		await _frames(3)
		var selected_before: String = menu.get("_selected_id")
		start = gallery.global_position + gallery.size * Vector2(0.68, 0.45)
		_touch(start, true)
		await _frames(1)
		_drag(start, start - Vector2(gallery.size.x * 0.40, 0))
		_touch(start - Vector2(gallery.size.x * 0.40, 0), false)
		await _frames(5)
		_check(gallery.scroll_horizontal > 20, "%s actual wardrobe cards accept side swipe" % category)
		_check(menu.get("_selected_id") == selected_before, "%s swipe does not select or reveal touched card" % category)
	_check(Progression.equipped() == equipped_before, "swipes never change equipped or purchased save state")
	menu.queue_free()
	await _frames(3)
	_viewport.queue_free()
	await _frames(3)
	GameConfig.force_touch = previous_touch
	get_window().size = original_window_size
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	print("[touch-scroll-gesture] %d/%d passed" % [_checks - _failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)


func _horizontal(parent: Control, position: Vector2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.position = position
	scroll.size = Vector2(300, 100)
	scroll.custom_minimum_size = Vector2(300, 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	TouchScroll.attach(scroll)
	var row := HBoxContainer.new()
	scroll.add_child(row)
	for index: int in 8:
		var button := Button.new()
		button.text = "Item %d" % index
		button.custom_minimum_size = Vector2(130, 90)
		button.pressed.connect(func() -> void: _pressed += 1)
		row.add_child(button)
	return scroll


func _touch(position: Vector2, pressed: bool, index: int = 0, cancelled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = position
	event.pressed = pressed
	event.index = index
	event.canceled = cancelled
	_viewport.push_input(event, true)


func _drag(from: Vector2, to: Vector2, index: int = 0) -> void:
	var event := InputEventScreenDrag.new()
	event.position = to
	event.relative = to - from
	event.index = index
	_viewport.push_input(event, true)


func _frames(count: int) -> void:
	for _index: int in count: await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("FAIL: " + label)
