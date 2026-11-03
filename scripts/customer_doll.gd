extends "res://scripts/volume_doll.gd"

const Garment = preload("res://scripts/garment_item.gd")
const Definition = preload("res://scripts/garment_definition.gd")
var customer_id := ""
var visit: Node
var profile: RefCounted
var thought := ""
var thought_color := Color.TRANSPARENT
var thought_time := 0.0
var garment: Node3D
var garments: Array[Node3D] = []
var carrying := false
var wearing := false
var _own_visibility: Dictionary = {}
var shopping_bag: Node3D


func _build_volume_body() -> void:
	super()
	# Customers need actual skin underneath short sleeves and open necklines.
	# These meshes belong to the wearer, never to an inventory garment.
	var skin_color: Color = SKIN_TONES[skin_index]
	for index in arms.size():
		var data: Dictionary = preload("res://components/basic_garment.gd").bare_arm(-1.0 if index == 0 else 1.0)
		var part := _mesh(arms[index], "CustomerArmSkin", data.vertices, data.normals, data.indices, skin_color)
		part.set_meta("garment_slot", "")
		part.set_meta("everyday_skin", "top")
		part.hide()
	for leg in legs:
		var calf := _lathe(leg,"CustomerLegSkin",[Vector3(-.95,.053,.060),Vector3(-.86,.057,.065),Vector3(-.65,.074,.081),Vector3(-.49,.081,.085),Vector3(-.40,.075,.079),Vector3(-.28,.088,.092),Vector3(-.12,.092,.098)],skin_color,16)
		calf.position.z = .045
		calf.set_meta("garment_slot", "")
		calf.set_meta("everyday_skin", "bottom")
		calf.hide()


func _keep_covered_legs() -> bool:
	return true


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		for piece in garments:
			if is_instance_valid(piece):
				piece.update_attachment()


func _process(_delta: float) -> void:
	# Keep worn and carried stock attached even when the shop simulation is paused.
	for piece in garments:
		if is_instance_valid(piece):
			piece.update_attachment()


func think(text: String, swatch: Color = Color.TRANSPARENT, seconds := 3.2) -> void:
	thought = text
	thought_color = swatch
	thought_time = seconds


func simulate(delta: float, speed_scale: float) -> void:
	super(delta, speed_scale)
	thought_time = maxf(thought_time - delta * speed_scale, 0.0)


func put_on(item: Node3D) -> bool:
	if not item.wear(self):
		return false
	garment = item
	if item not in garments:
		garments.append(item)
	refresh_outfit()
	return true


func take_off(item: Node3D = null) -> bool:
	var changed := false
	for piece in garments:
		if (item == null or piece == item) and piece.location == "worn":
			changed = piece.carry(self) or changed
	refresh_outfit()
	return changed


func carry_item(item: Node3D) -> bool:
	if not item.carry(self):
		return false
	garment = item
	if item not in garments:
		garments.append(item)
	refresh_outfit()
	return true


func refresh_outfit() -> void:
	if _own_visibility.is_empty():
		for part in rig.meshes:
			if Garment.is_clothing(part):
				_own_visibility[part] = part.visible
	var covered: Array[String] = []
	var bottom: Node3D
	var modern_top := false
	for piece in garments:
		if piece.location == "worn":
			# Sleeveless vest (13) is an outer layer worn over the shirt: the
			# covered top keeps its sleeves, so no bare-skin overlay is needed.
			modern_top = modern_top or piece.definition.outfit_style in [10,11]
			for slot in piece.definition.slots():
				if slot not in covered:
					covered.append(slot)
			if "bottom" in piece.definition.slots():
				bottom = piece
	for part in _own_visibility:
		if is_instance_valid(part):
			part.visible = _own_visibility[part] and Definition.part_slot(part) not in covered
	for part in rig.meshes:
		if part.has_meta("everyday_skin"):
			part.visible = modern_top if part.get_meta("everyday_skin") == "top" else (bottom != null and bottom.definition.outfit_style == 12)
	rig.long_garment = bottom.definition.long_bottom() if bottom != null else _covers_legs()
	wearing = garments.any(func(piece: Node3D) -> bool: return piece.location == "worn")
	carrying = garments.any(func(piece: Node3D) -> bool: return piece.location == "carried")
	garment = garments[0] if not garments.is_empty() else null


func release_item(inventory: Node3D, item: Node3D = null) -> void:
	for piece in garments.duplicate():
		if item == null or piece == item:
			if piece.location == "worn":
				take_off(piece)
			inventory.return_item(piece, self)
			garments.erase(piece)
	refresh_outfit()


func _update_puppet_motion(delta: float) -> void:
	super(delta)
	if carrying:
		for side in [-1.0,1.0]:
			var suffix := "L" if side < 0 else "R"
			rig._rotate("UpperArm"+suffix, Vector3(-.65, 0, -side*.20))
			rig._rotate("Forearm"+suffix, Vector3(-.95, 0, 0))
		rig.skeleton.force_update_all_bone_transforms()
	if is_instance_valid(shopping_bag):
		rig._rest_arm("R",Vector3(.64,1.43,.22),Vector3(.66,1.65,-.08),1.0)
	apply_reaches()
	if is_instance_valid(shopping_bag): shopping_bag.update_attachment()


func carry_transform(item: Node3D = null) -> Transform3D:
	var left: Transform3D = rig.skeleton.get_bone_global_pose(rig.bones["HandL"])
	var right: Transform3D = rig.skeleton.get_bone_global_pose(rig.bones["HandR"])
	var support := (left.origin if hand_targets.has("R") else (left.origin+right.origin)*.5)+Vector3(0,.045,.035)
	if item == null: return body_rig.global_transform * Transform3D(Basis.IDENTITY,support)
	var carried_items := garments.filter(func(piece: Node3D) -> bool: return is_instance_valid(piece) and piece.location == "carried")
	return body_rig.global_transform * preload("res://scripts/garment_stack.gd").placement(item,carried_items,support)
