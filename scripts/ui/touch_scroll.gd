class_name TouchScroll
extends Node
## Drag-to-scroll for a ScrollContainer whose rows are interactive.
##
## Godot's ScrollContainer implements touch dragging in _gui_input, which only
## receives events its children did not consume. On a settings or leaderboard
## screen every row is a Button, HSlider or OptionButton with the default
## MOUSE_FILTER_STOP, so a finger placed anywhere useful is swallowed and the
## list simply does not scroll. Desktop hides the problem because the mouse
## wheel takes a different path.
##
## This node watches drags in _input, which runs before GUI events are routed to
## controls, so it sees the gesture no matter what is underneath the finger.
##
## Locks to the finger's dominant axis. Nested horizontal carousels and their
## vertical page scroll therefore coexist. The engine's scroll notifications
## cancel pressed child buttons, so releasing a swipe never selects an item.

## Pixels of movement before a gesture counts as a scroll rather than a tap.
## Below this a slightly unsteady finger still presses the row it landed on.
const DRAG_THRESHOLD: float = 8.0
## Multiplier on finger movement. 1.0 tracks the finger exactly, which is what
## a list is expected to do.
const DRAG_SCALE: float = 1.0

var _scroll: ScrollContainer = null
var _active_index: int = -1
var _start_position := Vector2.ZERO
var _scrolling: bool = false
var _axis: int = -1
const GESTURE_GROUP := &"touch_scroll_gestures"


## Attach once on touch devices, including the suite's forced-touch mode.
static func attach(scroll: ScrollContainer) -> TouchScroll:
	if scroll == null or not GameConfig.has_touchscreen():
		return null
	var existing := scroll.get_node_or_null("TouchScroll") as TouchScroll
	if existing != null:
		return existing
	var node := TouchScroll.new()
	node.name = "TouchScroll"
	node._scroll = scroll
	node.add_to_group(GESTURE_GROUP)
	scroll.add_child(node)
	return node


func _input(event: InputEvent) -> void:
	if _scroll == null or not is_instance_valid(_scroll) or not _scroll.is_visible_in_tree():
		_finish_gesture()
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Only claim gestures that begin inside the list.
			if _active_index == -1 and _contains_point(touch.position):
				_active_index = touch.index
				_start_position = touch.position
				_scrolling = false
				_axis = -1
		elif touch.index == _active_index:
			_finish_gesture()
		return

	if not (event is InputEventScreenDrag):
		return
	var drag := event as InputEventScreenDrag
	if drag.index != _active_index:
		return
	if not _scrolling:
		var travel := drag.position - _start_position
		var axis := 0 if absf(travel.x) > absf(travel.y) else 1
		if absf(travel[axis]) < DRAG_THRESHOLD or not _can_scroll_axis(axis):
			return
		# Every candidate saw the initial touch before GUI button handling.
		# Let the deepest list supporting this axis own the entire gesture.
		for candidate: Node in get_tree().get_nodes_in_group(GESTURE_GROUP):
			var inner := candidate as TouchScroll
			if inner != self and inner._active_index == _active_index \
					and is_instance_valid(inner._scroll) \
					and _scroll.is_ancestor_of(inner._scroll) \
					and inner._can_scroll_axis(axis):
				return
		_axis = axis
		_scrolling = true
		_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		_scroll.scroll_started.emit()
	var local_motion := _scroll.get_global_transform_with_canvas().basis_xform_inv(drag.relative)
	var bar: ScrollBar = _scroll.get_h_scroll_bar() if _axis == 0 else _scroll.get_v_scroll_bar()
	bar.value -= local_motion[_axis] * DRAG_SCALE
	# Consumed so the row under the finger does not also react, and so the
	# ScrollContainer's own drag handling cannot add a second helping.
	get_viewport().set_input_as_handled()


func _can_scroll_axis(axis: int) -> bool:
	var mode := _scroll.horizontal_scroll_mode if axis == 0 else _scroll.vertical_scroll_mode
	if mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return false
	var bar: ScrollBar = _scroll.get_h_scroll_bar() if axis == 0 else _scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 1.0


func _contains_point(point: Vector2) -> bool:
	var ancestor: Node = _scroll
	while ancestor != null:
		if ancestor is Control:
			var control := ancestor as Control
			if control == _scroll or control.clip_contents:
				var local := control.get_global_transform_with_canvas().affine_inverse() * point
				if not Rect2(Vector2.ZERO, control.size).has_point(local):
					return false
		ancestor = ancestor.get_parent()
	return true


func _finish_gesture() -> void:
	if _scrolling and is_instance_valid(_scroll):
		_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
		_scroll.scroll_ended.emit()
	_active_index = -1
	_scrolling = false
	_axis = -1
