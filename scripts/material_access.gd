extends RefCounted
## Chooses where a worker stands to handle materials on a fixture.
## Fixtures expose several candidate access markers; the worker keeps the
## current spot when the target is already within comfortable reach, otherwise
## walks to the reachable candidate with the shortest room route.

const COMFORT_REACH := 1.05
const WORK_REACH := 1.30
const KEEP_ROUTE_SLACK := 1.18

var room: Node3D


func _init(room_node: Node3D) -> void:
	room = room_node


func within_reach(from: Vector3, target: Vector3) -> bool:
	var flat := Vector2(from.x-target.x,from.z-target.z)
	return flat.length() <= COMFORT_REACH


func route_length(from: Vector3, to: Vector3) -> float:
	if not is_instance_valid(room):
		return from.distance_to(to)
	var path: PackedVector3Array = room.route(room.to_local(from),room.to_local(to))
	if path.is_empty():
		return INF
	var total := 0.0
	var cursor := from
	for point in path:
		var world: Vector3 = room.to_global(point)
		total += cursor.distance_to(world)
		cursor = world
	return total


# Returns the marker to walk to, or null when the worker may stay and turn.
# Unreachable layouts fall back to the closest candidate so the actor's
# navigation reports blocked and the caller can retry the next option.
func choose(from: Vector3, target: Vector3, candidates: Array, current: Marker3D = null) -> Marker3D:
	if within_reach(from,target):
		return null
	var best: Marker3D = null
	var best_length := INF
	var fallback: Marker3D = null
	var fallback_distance := INF
	for marker in candidates:
		if not is_instance_valid(marker):
			continue
		var flat := Vector2(marker.global_position.x-target.x,marker.global_position.z-target.z).length()
		if flat < fallback_distance:
			fallback = marker
			fallback_distance = flat
		if flat > WORK_REACH:
			continue
		var length := route_length(from,marker.global_position)
		if length < best_length:
			best = marker
			best_length = length
	if best == null:
		return fallback
	if is_instance_valid(current) and current != best and current in candidates:
		var kept := route_length(from,current.global_position)
		if kept <= best_length*KEEP_ROUTE_SLACK:
			return current
	return best


# Nearest candidate by route length, ignoring the comfort-reach stay rule.
# Used when the worker must stand at a marker (e.g. resume without a live
# arrival state) even though the target is already close.
func nearest(from: Vector3, candidates: Array) -> Marker3D:
	var best: Marker3D = null
	var best_length := INF
	for marker in candidates:
		if not is_instance_valid(marker):
			continue
		var length := route_length(from,marker.global_position)
		if length < best_length:
			best = marker
			best_length = length
	if best == null and not candidates.is_empty():
		best = candidates[0]
	return best
