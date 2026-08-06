class_name RacerController
extends Node
## Base class for anything that drives a Racer: player input or AI.
## The racer reads these fields every physics tick; edge flags are consumed
## by the racer after use.

var steer: float = 0.0  # -1 (left) .. 1 (right)
var jump_pressed: bool = false  # edge
var jump_held: bool = false
var slide_held: bool = false
var shove_pressed: bool = false  # edge
var item_pressed: bool = false  # edge
## Held while the racer wants to fire behind instead of ahead. Read at the
## moment an item is used, so it is a held state rather than an edge.
var aim_back: bool = false


## Called by the racer each physics tick before movement.
func tick(_delta: float) -> void:
	pass


func consume_jump() -> void:
	jump_pressed = false


func consume_edges() -> void:
	shove_pressed = false
	item_pressed = false
