extends RefCounted

# Furniture owns footprints and interaction markers. This service joins room paths
# through real doorways; actors never need a room-transfer teleport.
const ROOM_ORDER := ["workshop", "shop", "archive"]
var rooms: Dictionary
var street: Node3D
var revision := 0


func _init(room_nodes: Dictionary, street_node: Node3D) -> void:
	rooms = room_nodes
	street = street_node


func refresh() -> bool:
	var changed := false
	for room in rooms.values():
		changed = room.refresh_navigation() or changed
	if changed:
		revision += 1
	return changed


func version() -> int:
	return revision


func room_at(point: Vector3) -> String:
	for id in ROOM_ORDER:
		var local: Vector3 = rooms[id].to_local(point)
		if absf(local.x) <= 7.2001 and local.z <= 3.4 and local.z >= -2.05:
			return id
	return "street"


func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var origin := room_at(from)
	var destination := room_at(to)
	if origin == "street" and destination == "street":
		return street.customer_path(from, to, rooms["shop"])
	if origin == "street":
		var entry: Vector3 = rooms["shop"].to_global(street.INSIDE)
		var interior := _indoors(entry, to, "shop", destination)
		if interior.is_empty():
			return PackedVector3Array()
		var result: PackedVector3Array = street.customer_path(from, entry, rooms["shop"])
		result.append_array(interior)
		return result
	if destination == "street":
		var entry: Vector3 = rooms["shop"].to_global(street.INSIDE)
		var result := _indoors(from, entry, origin, "shop")
		if result.is_empty():
			return result
		result.append_array(street.customer_path(entry, to, rooms["shop"]))
		return result
	return _indoors(from, to, origin, destination)


func _indoors(from: Vector3, to: Vector3, origin: String, destination: String) -> PackedVector3Array:
	var result := PackedVector3Array()
	var current := ROOM_ORDER.find(origin)
	var target := ROOM_ORDER.find(destination)
	var cursor := from
	while current != target:
		var direction := 1 if target > current else -1
		var room: Node3D = rooms[ROOM_ORDER[current]]
		var exit_point := room.to_global(Vector3(direction * 7.2, 0, 1.75))
		var segment := _room_path(room, cursor, exit_point)
		if segment.is_empty():
			return PackedVector3Array()
		result.append_array(segment)
		cursor = exit_point
		current += direction
	var last := _room_path(rooms[destination], cursor, to)
	if last.is_empty():
		return PackedVector3Array()
	result.append_array(last)
	return result


func _room_path(room: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in room.route(room.to_local(from), room.to_local(to)):
		result.append(room.to_global(point))
	return result
