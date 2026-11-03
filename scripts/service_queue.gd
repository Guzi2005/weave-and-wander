extends Node3D

var queue: Array[WeakRef] = []
var _spots: Dictionary = {}
var _offsets: Array[Vector3] = []
var _origin := Vector3.ZERO


func configure(origin: Vector3, offsets: Array) -> void:
	_origin = to_local(origin)
	_offsets.assign(offsets)


func join(customer: Node3D) -> Marker3D:
	_cleanup()
	var id := customer.get_instance_id()
	if _spots.has(id):
		return _spots[id].marker
	var used: Array = _spots.values().map(func(entry: Dictionary) -> int: return entry.index)
	for index in _offsets.size():
		if index in used:
			continue
		var marker := Marker3D.new()
		marker.name = "Waiting_%d" % id
		add_child(marker)
		marker.position = _origin + _offsets[index]
		_spots[id] = {"actor": weakref(customer), "marker": marker, "index": index}
		queue.append(weakref(customer))
		return marker
	return null


func is_first(customer: Node3D) -> bool:
	_cleanup()
	return not queue.is_empty() and queue[0].get_ref() == customer


func leave(customer: Node3D) -> void:
	var id := customer.get_instance_id()
	if _spots.has(id):
		_spots[id].marker.queue_free()
		_spots.erase(id)
	queue = queue.filter(func(entry: WeakRef) -> bool: return is_instance_valid(entry.get_ref()) and entry.get_ref() != customer)


func _cleanup() -> void:
	queue = queue.filter(func(entry: WeakRef) -> bool: return is_instance_valid(entry.get_ref()))
	for id in _spots.keys():
		if not is_instance_valid(_spots[id].actor.get_ref()):
			_spots[id].marker.queue_free()
			_spots.erase(id)
