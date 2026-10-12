class_name SkyAnchor
extends Node3D
## Holds sky bodies (moon, sun disc, their halos) at a fixed BEARING from the
## camera instead of a fixed point in the world.
##
## A moon parked at a world position is a moon 1 km away: drive 1.5 km of course
## past it and it swings across the sky, ends up behind you, and stops agreeing
## with the direction its own key light comes from. That mismatch is invisible
## until something else is drawn from the light direction — which is exactly
## what SunShafts does, and how this was caught: the rays and the moon were in
## two different places.
##
## Bodies parented here keep the bearing they were authored with, so the light,
## the disc and the rays all agree from anywhere on the course, and the sky
## stops sliding as the racer moves.

var _bearing: Vector3 = Vector3.UP
var _distance: float = 1000.0


## `bearing` is the direction from the camera to the body (need not be
## normalised); `distance` is how far out to hold it. Keep it inside the
## camera's far plane and beyond every piece of course geometry.
func configure(bearing: Vector3, distance: float) -> void:
	_bearing = bearing.normalized()
	_distance = distance
	# Place it once immediately: the first frame is drawn before _process runs,
	# and a sky body that spends that frame at the world origin flashes across
	# the middle of the course.
	global_position = _bearing * _distance


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = camera.global_position + _bearing * _distance
