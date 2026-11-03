extends Node3D

const Stack = preload("res://scripts/garment_stack.gd")
const BASE := .035
const COLLAR_START := .70
var contents: Array[Node3D] = []
var dimensions := Vector3(.56,.56,.44)
var customer: WeakRef
var model: Node3D
var bag_id := ""
var carried := false
var closure := 0.0


func _ready() -> void:
	bag_id = "bag_%d" % get_instance_id()
	model = preload("res://assets/models/shopping_bag.glb").instantiate()
	add_child(model)
	for part in model.find_children("*","MeshInstance3D",true,false):
		for surface in part.mesh.get_surface_count():
			var source: Material = part.mesh.surface_get_material(surface)
			var material := ShaderMaterial.new()
			material.shader = preload("res://shaders/room_paper.gdshader")
			material.set_shader_parameter("pigment",source.albedo_color if source is StandardMaterial3D else Color("c8b993"))
			part.set_surface_override_material(surface,material)
	process_priority = 90


func fit_items(items: Array[Node3D]) -> void:
	dimensions = Vector3(.56,.56,.36)
	var height := BASE
	for item in items:
		var size := Stack.box(item).size
		dimensions.x = maxf(dimensions.x,size.x+.10)
		dimensions.z = maxf(dimensions.z,size.z+.10)
		height += size.y+Stack.GAP
	dimensions.y = maxf(.64,(height+.045)/COLLAR_START)
	height = BASE
	# Reserve clearance against the carried trapezoid, not just the open box.
	for item in Stack.ordered(items):
		var size := Stack.box(item).size
		height += size.y
		var taper := 1.0-height/grip().y
		dimensions.z = maxf(dimensions.z,(size.z+.07)/taper)
		height += Stack.GAP
	_apply_model_scale()


func _apply_model_scale() -> void:
	if not is_instance_valid(model): return
	model.scale = Vector3(dimensions.x/.70,dimensions.y/.64,dimensions.z/.36)


func grip() -> Vector3:
	return Vector3(0,dimensions.y*.88/.64,0)


func item_transform(item: Node3D) -> Transform3D:
	var selection := contents.duplicate()
	if item not in selection: selection.append(item)
	return global_transform*Stack.placement(item,selection,Vector3(0,BASE,0))


func interior_bounds() -> AABB:
	return AABB(Vector3(-dimensions.x*.5+.02,.015,-dimensions.z*.5+.02),Vector3(dimensions.x-.04,dimensions.y*COLLAR_START-.015,dimensions.z-.04))


func contains_item(item: Node3D) -> bool:
	var local := global_transform.affine_inverse()*item_transform(item)
	var bounds: AABB = local*item.presentation_bounds("Folded")
	var half_depth := dimensions.z*.5*(1.0-closure*bounds.end.y/grip().y)-.015
	var half_width := dimensions.x*.5-.02
	return bounds.position.y >= .015 and bounds.end.y < dimensions.y and bounds.position.x > -half_width and bounds.end.x < half_width and bounds.position.z > -half_depth and bounds.end.z < half_depth


func set_closure(value: float) -> void:
	closure = clampf(value,0,1)
	for part in model.find_children("*","MeshInstance3D",true,false):
		var index: int = part.find_blend_shape_by_name("Carried")
		if index >= 0: part.set_blend_shape_value(index,closure)


func hand_over(actor: Node3D) -> void:
	customer = weakref(actor)
	carried = true
	reparent(actor,true)
	actor.shopping_bag = self
	set_closure(1.0)
	update_attachment()


func update_attachment() -> void:
	var actor: Node3D = customer.get_ref() if customer != null else null
	if not is_instance_valid(actor): return
	var hand: Vector3 = actor.rig.skeleton.get_bone_global_pose(actor.rig.bones.HandR).origin
	var sway: float = sin(actor._phase*5.0)*.045 if actor.is_moving() else sin(actor._work_phase)*.009
	var orientation: Basis = actor.body_rig.global_basis.orthonormalized()*Basis(Vector3.FORWARD,sway)
	global_transform = Transform3D(orientation,actor.body_rig.to_global(hand)-orientation*grip())


func _process(_delta: float) -> void:
	update_attachment()
	# Inventory items are independent nodes; update after their carrier moves.
	for item in contents:
		if is_instance_valid(item) and item.location == "packed": item.update_attachment()
