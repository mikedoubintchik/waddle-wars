class_name RotateOverlay
extends CanvasLayer
## Deprecated compatibility shim.
##
## Portrait is a supported gameplay orientation. Older scene code may still
## instantiate RotateOverlay, so the type remains loadable, but it deliberately
## creates no Control nodes, consumes no input, pauses nothing, and never draws.
## Remove old callers opportunistically; adding this node is always harmless.


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)


## Pure policy seam used by platform tests and any legacy caller deciding
## whether to create a gate. Kept size-shaped so old orientation checks have a
## direct replacement without encoding aspect policy elsewhere.
static func blocks_view_size(_view_size: Vector2) -> bool:
	return false


func is_input_blocking() -> bool:
	return false
