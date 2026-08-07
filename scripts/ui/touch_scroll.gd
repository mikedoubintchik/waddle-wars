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
## Taps still work: only the drag events are consumed, never the initial touch
## or the release, and a Button only emits on a release inside its own rect --
## which a scrolling finger no longer is. Consuming the drags also means the
## ScrollContainer never sees them, so its own handling cannot double up on
## ours when a drag happens to start on empty space.

## Pixels of movement before a gesture counts as a scroll rather than a tap.
## Below this a slightly unsteady finger still presses the row it landed on.
const DRAG_THRESHOLD: float = 8.0
## Multiplier on finger movement. 1.0 tracks the finger exactly, which is what
## a list is expected to do.
const DRAG_SCALE: float = 1.0

var _scroll: ScrollContainer = null
var _active_index: int = -1
var _travelled: float = 0.0
var _scrolling: bool = false


## Attaches drag-to-scroll to `scroll`. No-op off touch devices and headless,
## where the wheel and keyboard already work and this would only add input
## handling to every frame.
static func attach(scroll: ScrollContainer) -> TouchScroll:
	if scroll == null or GameConfig.is_headless() or not DisplayServer.is_touchscreen_available():
		return null
	var node := TouchScroll.new()
	node.name = "TouchScroll"
	node._scroll = scroll
	scroll.add_child(node)
	return node


func _input(event: InputEvent) -> void:
	if _scroll == null or not is_instance_valid(_scroll) or not _scroll.is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Only claim gestures that begin inside the list.
			if _scroll.get_global_rect().has_point(touch.position):
				_active_index = touch.index
				_travelled = 0.0
				_scrolling = false
		elif touch.index == _active_index:
			_active_index = -1
			_scrolling = false
		return

	if not (event is InputEventScreenDrag):
		return
	var drag := event as InputEventScreenDrag
	if drag.index != _active_index:
		return
	_travelled += absf(drag.relative.y)
	if not _scrolling and _travelled < DRAG_THRESHOLD:
		return
	_scrolling = true
	_scroll.scroll_vertical -= int(drag.relative.y * DRAG_SCALE)
	# Consumed so the row under the finger does not also react, and so the
	# ScrollContainer's own drag handling cannot add a second helping.
	get_viewport().set_input_as_handled()
