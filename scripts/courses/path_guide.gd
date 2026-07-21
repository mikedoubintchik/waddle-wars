class_name PathGuide
extends RefCounted
## Precomputed uniform samples along a Curve3D with windowed nearest-point
## queries, so eight racers can track course progress cheaply and reliably
## even on courses that overlap themselves vertically.

const SAMPLE_SPACING: float = 2.0
const WINDOW: int = 45  # samples each side (= 90m) for local search

var curve: Curve3D
var points: PackedVector3Array
var length: float = 0.0


func _init(p_curve: Curve3D) -> void:
	curve = p_curve
	curve.bake_interval = SAMPLE_SPACING
	points = curve.get_baked_points()
	length = curve.get_baked_length()


## Returns {offset, index, distance, position}. hint_index < 0 = global search.
func nearest(point: Vector3, hint_index: int = -1) -> Dictionary:
	var best_index := 0
	var best_dist_sq := INF
	var lo := 0
	var hi := points.size() - 1
	if hint_index >= 0:
		lo = maxi(0, hint_index - WINDOW)
		hi = mini(points.size() - 1, hint_index + WINDOW)
	for i: int in range(lo, hi + 1):
		var d := point.distance_squared_to(points[i])
		if d < best_dist_sq:
			best_dist_sq = d
			best_index = i
	# Retry globally when the windowed result is suspicious: too far away, or
	# pinned to the window edge (the true nearest point lies outside it).
	if hint_index >= 0 and (best_dist_sq > 20.0 * 20.0 or best_index == lo or best_index == hi):
		if not (best_index == hi and hi == points.size() - 1) and not (best_index == lo and lo == 0):
			return nearest(point, -1)
	return {
		"offset": float(best_index) * SAMPLE_SPACING,
		"index": best_index,
		"distance": sqrt(best_dist_sq),
		"position": points[best_index],
	}


func position_at(offset: float) -> Vector3:
	return curve.sample_baked(clampf(offset, 0.0, length))


func tangent_at(offset: float) -> Vector3:
	var ahead := position_at(clampf(offset + 2.0, 0.0, length))
	var behind := position_at(clampf(offset - 2.0, 0.0, length))
	var tangent := ahead - behind
	if tangent.length_squared() < 0.0001:
		return Vector3.FORWARD
	return tangent.normalized()


func yaw_at(offset: float) -> float:
	var t := tangent_at(offset)
	return atan2(-t.x, -t.z)


func transform_at(offset: float) -> Transform3D:
	var origin := position_at(offset)
	var tangent := tangent_at(offset)
	var right := tangent.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var up := right.cross(tangent).normalized()
	return Transform3D(Basis(right, up, -tangent).orthonormalized(), origin)


## Point at offset shifted laterally (positive = right of travel direction).
func point_at(offset: float, lateral: float = 0.0, height: float = 0.0) -> Vector3:
	var xform := transform_at(offset)
	return xform.origin + xform.basis.x * lateral + xform.basis.y * height
