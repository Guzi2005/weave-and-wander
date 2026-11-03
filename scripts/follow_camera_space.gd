extends RefCounted
## Visual meshes are the collision source: the miniature has no physics walls.
const RADIUS := .14
var boxes: Array[AABB] = []
var people: Array[AABB] = []
var elapsed := 1.0

func refresh(game: Node, subject: Node3D, delta: float, force := false) -> void:
	elapsed += delta
	if force or elapsed >= .15:
		elapsed = 0
		boxes.clear()
		for room in game._rooms.values():
			for entry in room._footprints: _collect(entry.node)
			_collect(room.get_node("RoomShell"))
		_collect(game._street.facades)
	people.clear()
	var actors: Array = game.staff + game.customers + game._street_life.pedestrians + [game._street_life.postman]
	for actor in actors:
		if not is_instance_valid(actor) or actor == subject or not actor.is_visible_in_tree(): continue
		people.append(AABB(actor.global_position+Vector3(-.38,.12,-.38),Vector3(.76,2.5,.76)).grow(RADIUS))

func _collect(node: Node) -> void:
	if not is_instance_valid(node): return
	var parts := node.find_children("*","MeshInstance3D",true,false)
	if node is MeshInstance3D: parts.append(node)
	for part in parts:
		if not part.is_visible_in_tree() or part.mesh == null: continue
		if part.is_in_group("shop_glass_panels") or part.is_in_group("shop_window_panels"): continue
		if part.layers == 8 or str(part.name).contains("ReflectiveGlass"): continue
		boxes.append((part.global_transform * part.mesh.get_aabb()).grow(RADIUS))

func clear_point(point: Vector3) -> bool:
	for box in boxes:
		if box.has_point(point): return false
	for box in people:
		if box.has_point(point): return false
	return true

func escape(point: Vector3) -> Vector3:
	# Resolve starting overlap too: ray shortening alone cannot escape a cabinet.
	for attempt in 12:
		var changed := false
		for box in boxes + people:
			if not box.has_point(point): continue
			var distance := INF
			var next := point
			for axis in 3:
				for edge in [box.position[axis]-.015,box.end[axis]+.015]:
					if absf(point[axis]-edge) < distance:
						distance = absf(point[axis]-edge)
						next = point
						next[axis] = edge
			point = next
			changed = true
		if not changed: break
	return point

func clip(origin: Vector3, desired: Vector3) -> Vector3:
	var travel := desired-origin
	var length := travel.length()
	if length < .001: return origin
	var direction := travel/length
	var limit := length
	for box in boxes + people:
		limit = minf(limit,hit_distance(origin,direction,box,length))
	return origin+direction*maxf(0,limit-.025 if limit < length else limit)

static func hit_distance(origin: Vector3, direction: Vector3, box: AABB, limit: float) -> float:
	var low := 0.0
	var high := limit
	for axis in 3:
		if absf(direction[axis]) < .000001:
			if origin[axis] < box.position[axis] or origin[axis] > box.end[axis]: return limit
		else:
			var a: float = (box.position[axis]-origin[axis])/direction[axis]
			var b: float = (box.end[axis]-origin[axis])/direction[axis]
			low = maxf(low,minf(a,b))
			high = minf(high,maxf(a,b))
			if low > high: return limit
	return low

func orbit_position(focus: Vector3, forward: Vector3, second: bool, previous: Vector3) -> Vector3:
	var direction := Vector3(forward.x,0,forward.z).normalized()
	if direction.length_squared() < .1: direction = Vector3.BACK
	if not second: direction = -direction
	var best := focus
	var score := -INF
	for angle in [0.0,.45,-.45,.9,-.9,1.4,-1.4,2.0,-2.0,PI]:
		var ray := direction.rotated(Vector3.UP,angle)*2.7+Vector3.UP*.48
		var candidate := clip(focus,focus+ray)
		var distance := candidate.distance_to(focus)
		if distance < .72 or not clear_point(candidate): continue
		var value := minf(distance,2.2)*2.0-absf(angle)*.65-candidate.distance_to(previous)*.10
		if value > score:
			score = value
			best = candidate
	return best
