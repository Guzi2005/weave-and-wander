extends Node3D

const ROOM_MATERIAL = preload("res://shaders/room_paper.gdshader")
const PAGE_NAMES := ["店面与街道", "前排房间", "后排 · 待装修", "店后街道"]
var controller: Node
var depth := 1.0
var opened := [0.0, 1.0, 0.0, 0.0]
var rear_rooms: Node3D
var back_street: Node3D
var desk: Node3D
var _static_groups: Array[Dictionary] = []
var _actor_groups: Dictionary = {}
var _garment_groups: Dictionary = {}
var _roofs: Array[Node3D] = []
var enclosed := false


func _ready() -> void:
	desk = preload("res://scripts/artisan_desk.gd").new()
	desk.name = "ArtisanWorktable"
	add_child(desk)
	for room in controller._rooms.values():
		_register_room(room, 1)
	for facade in controller._street.facades.get_children():
		# Exterior-to-interior is a single wall leaf: the facade folds down at its foot.
		_static_groups.append(_group(facade, 0, Vector3(facade.global_position.x, 0, 3.76), false, "exterior_wall"))
	_static_groups.append(_group(controller._street.get_node("BluestoneStreet"), 0, Vector3(0, 0, 3.8), true, "front_street"))
	_static_groups.append(_group(controller._street.get_node("ShopEntranceMat"), 1, Vector3.ZERO, true, "front_room_fixed"))
	_static_groups.append(_group(controller._street.get_node("EntryThreshold"), 1, Vector3.ZERO, true, "front_room_fixed"))
	# The room roofs are the only roofs. They remain fixed while the street wall folds.
	rear_rooms = preload("res://scripts/rear_pages.gd").new()
	rear_rooms.name = "UnfinishedRearRooms"
	rear_rooms.kind = "rooms"
	rear_rooms.position.z = -6.5
	add_child(rear_rooms)
	for part in rear_rooms.get_children():
		var structure: bool = part.get_script() == preload("res://scripts/shop_roof.gd") or str(part.name).begins_with("UnfinishedBox")
		_static_groups.append(_group(part, 2, Vector3(part.global_position.x, 0, -9.15), str(part.name).begins_with("Floor"), "rear_architecture" if structure else "rear_room"))
	back_street = preload("res://scripts/rear_pages.gd").new()
	back_street.name = "BackStreet"
	back_street.kind = "street"
	back_street.position.z = -16.0
	add_child(back_street)
	for part in back_street.get_children():
		_static_groups.append(_group(part, 3, Vector3(part.global_position.x, 0, part.global_position.z), str(part.name).begins_with("Floor"), "back_street"))
	apply_depth(1.0)


func _register_room(room: Node3D, page: int) -> void:
	for part in room.get_children():
		if part.name == "ShopInventory":
			continue
		if part.name == "RoomShell":
			for piece in part.get_children():
				var floor_part := str(piece.name).begins_with("Tile_") or piece.name in ["CardboardFoundation", "PaperFloor", "Threshold", "RightThreshold"]
				_static_groups.append(_group(piece, page, Vector3(room.position.x, 0, -2.65), floor_part, "front_room_fixed" if floor_part else "front_architecture"))
		else:
			var origin: Vector3 = part.global_position
			origin.y = 0
			if part.name in ["HingedRoof", "CutPaperWindow", "ClippingsAndPatterns", "WovenWallHanging"] or part.has_meta("roof_anchor_height"):
				origin.z = -2.65
			var architecture := part.name in ["HingedRoof", "CutPaperWindow", "ClippingsAndPatterns", "WovenWallHanging", "DryingRail", "ArchiveClippings"] or part.has_meta("roof_anchor_height")
			if architecture:
				origin.z = -2.65
			_static_groups.append(_group(part, page, origin, false, "front_architecture" if architecture else "front_room_fixed"))


func _copy(source: Material) -> ShaderMaterial:
	if source is ShaderMaterial:
		var copy := source.duplicate() as ShaderMaterial
		# Flat costume parameters must survive a copy during startup, before
		# the renderer has populated the shader's dynamic property list.
		for parameter in ["pigment", "pigment_map", "use_pigment_map", "use_vertex_color", "tooth", "tone_steps", "backface_shade", "pattern", "pattern_scale", "weave_scale", "roughness", "fiber_strength", "use_material_uv", "uv_metres"]:
			var value = source.get_shader_parameter(parameter)
			if value != null:
				copy.set_shader_parameter(parameter,value)
		return copy
	var material := ShaderMaterial.new()
	material.shader = ROOM_MATERIAL
	if source is StandardMaterial3D:
		material.set_shader_parameter("pigment", source.albedo_color)
	return material


func _group(node: Node3D, page: int, origin: Vector3, floor_part := false, role := "") -> Dictionary:
	var copies := {}
	var meshes := node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		meshes.append(node)
	for mesh in meshes:
		var source: Material = mesh.material_override
		if source == null:
			continue
		if not copies.has(source):
			copies[source] = _copy(source)
		mesh.material_override = copies[source]
	return {"root": weakref(node), "page": page, "origin": origin, "floor": floor_part, "role": role, "materials": copies.values(), "meshes": meshes, "last": -1.0, "transform": node.global_transform}


func _pose(group: Dictionary, amount: float, origin: Vector3) -> void:
	# Fully unfolded vertices do not depend on the hinge position.
	if group.last == 1.0 and amount == 1.0:
		return
	if is_equal_approx(group.last, amount) and group.origin.is_equal_approx(origin):
		return
	if (group.last < 1.0) != (amount < 1.0) or group.last < 0.0:
		for mesh in group.get("meshes", []):
			if is_instance_valid(mesh): mesh.extra_cull_margin = 12.0 if amount < 1.0 else 0.0
	group.last = amount
	group.origin = origin
	for material in group.materials:
		material.set_shader_parameter("fold_enabled", true)
		material.set_shader_parameter("fold_amount", amount)
		material.set_shader_parameter("fold_origin", origin)
		material.set_shader_parameter("fold_floor", group.floor)
		material.set_shader_parameter("fold_card", false)
		material.set_shader_parameter("fold_leaf", group.get("role", "") in ["front_street", "street_actor"])


func _group_amount(group: Dictionary) -> float:
	var role: String = group.get("role", "")
	# A followed view stands inside the finished building, not the cutaway page.
	if enclosed and role in ["exterior_wall", "front_architecture", "front_room_fixed", "rear_architecture", "rear_room"]:
		return 1.0
	if role == "exterior_wall":
		# At depth 0 the wall is upright; by the time the interior is exposed it
		# lies flat on the worktable. The room contents never fold in this step.
		return 1.0 - smoothstep(.04, .56, depth)
	if role == "front_street":
		return 1.0 - smoothstep(1.05, 1.65, depth)
	if role == "front_room_fixed":
		if group.get("floor", false):
			return 1.0
		return front_room_amount()
	if role == "front_architecture":
		return 1.0 - smoothstep(1.0, 1.85, depth)
	if role == "rear_room":
		return 1.0
	if role == "rear_architecture":
		return 1.0 - smoothstep(2.0, 2.85, depth)
	if role == "back_street":
		return 1.0
	return opened[group.page]


func front_room_amount() -> float:
	return 1.0 - smoothstep(2.05, 2.65, depth)


func apply_depth(value: float) -> void:
	depth = clampf(value, 0.0, 3.0)
	# Pose and garment attachment must agree even during paused view manipulation.
	controller._inventory.advance()
	for page in 4:
		opened[page] = 1.0 - smoothstep(.16, .55, absf(depth - page))
	for group in _static_groups:
		var node: Node3D = group.root.get_ref()
		if not is_instance_valid(node):
			continue
		var amount: float = _group_amount(group)
		node.visible = amount > .001
		var origin: Vector3 = group.origin
		if not group.transform.is_equal_approx(node.global_transform):
			origin += node.global_position - group.transform.origin
			group.transform = node.global_transform
		_pose(group, amount, origin)
	controller._street.exterior_amount = _group_amount({"role": "exterior_wall"})
	controller._street.facades.visible = controller._street.exterior_amount > .001
	var reflection_shell: Node3D = controller._street.get_node_or_null("ReflectionInteriorShell")
	if reflection_shell != null:
		reflection_shell.visible = not enclosed
	for mirror in get_tree().get_nodes_in_group("shop_mirrors"):
		mirror.reflection_enabled = front_room_amount() > .98
	_sync_actors()
	_sync_garments()
	rear_rooms.animate_samples(controller._day_minutes * 24.0)
	desk.set_page(depth)
	desk.set_time(controller._day_minutes, controller)


func _sync_actors() -> void:
	var people: Array = controller.staff + controller.customers + controller._street_life.pedestrians + [controller._street_life.postman]
	for actor in people:
		if not is_instance_valid(actor):
			continue
		var id: int = actor.get_instance_id()
		if not _actor_groups.has(id) or _actor_groups[id].body != actor.body_rig.get_instance_id():
			_actor_groups[id] = {"body": actor.body_rig.get_instance_id(), "actor": weakref(actor), "group": _group(actor.body_rig, 1, actor.global_position, false, "front_room_fixed")}
		var amount := _actor_amount(actor)
		actor.body_rig.visible = amount > .001 and absf(actor.global_position.x) < 21.5
		actor._stage_base.visible = actor.body_rig.visible and amount > .99
		var outside: bool = actor.global_position.z > 3.4
		_actor_groups[id].group.role = "street_actor" if outside else "front_room_fixed"
		_pose(_actor_groups[id].group, amount, Vector3(0, 0, 3.8) if outside else actor.global_position)
	for id in _actor_groups.keys():
		if not is_instance_valid(_actor_groups[id].actor.get_ref()):
			_actor_groups.erase(id)
	var bicycle: Node3D = controller._street_life.bicycle
	if not bicycle.has_meta("fold_group"):
		bicycle.set_meta("fold_group", _group(bicycle, 0, bicycle.global_position))
	var bike_group: Dictionary = bicycle.get_meta("fold_group")
	bike_group.role = "street_actor"
	var street_amount := _group_amount({"role": "front_street"})
	bicycle.visible = street_amount > .001
	_pose(bike_group, street_amount, Vector3(0, 0, 3.8))


func _actor_amount(actor: Node3D) -> float:
	if depth <= 1.0:
		return 1.0
	return _group_amount({"role": "front_street"}) if actor.global_position.z > 3.4 else front_room_amount()


func _sync_garments() -> void:
	for item in controller._inventory.items:
		if not is_instance_valid(item):
			continue
		var id: int = item.get_instance_id()
		if not _garment_groups.has(id):
			var materials: Array = []
			for list in [item.worn_materials, item.prop_materials]:
				for index in list.size():
					list[index] = _copy(list[index])
					materials.append(list[index])
			item._set_worn_materials(item.location == "worn")
			_garment_groups[id] = {"page": 1, "origin": Vector3.ZERO, "floor": false, "materials": materials, "meshes": item.parts, "last": -1.0}
		var origin: Vector3 = item.global_position
		origin.y = 0
		var amount: float = front_room_amount()
		_garment_groups[id].role = "front_room_fixed"
		if item.holder != null and is_instance_valid(item.holder.get_ref()):
			origin = item.holder.get_ref().global_position
			amount = _actor_amount(item.holder.get_ref())
			if origin.z > 3.4:
				origin = Vector3(0, 0, 3.8)
				_garment_groups[id].role = "street_actor"
		item.visual.visible = amount > .001
		_pose(_garment_groups[id], amount, origin)


func is_front_room() -> bool:
	return absf(depth - 1.0) < .16


func page_name() -> String:
	return PAGE_NAMES[clampi(roundi(depth), 0, 3)]
