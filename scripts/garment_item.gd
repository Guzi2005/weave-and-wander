extends Node3D

const Doll = preload("res://scripts/catalog_doll.gd")
const MosuoDollSource = preload("res://scripts/mosuo_doll.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const ROOM_SHADER = preload("res://shaders/room_paper.gdshader")
const Forms = preload("res://scripts/garment_forms.gd")
const APPEARANCE = preload("res://scripts/material_appearance.gd")
var item_id := ""
var definition: Resource
var location := "rack"
var owner_id := "shop"
var reserved_by := ""
var holder: WeakRef
var display_mount: WeakRef
var stock_parent: Node
var _attachment: WeakRef
var tried_on := false
var paid := false
var slot := -1
var visual: Node3D
var skeleton: Skeleton3D
var parts: Array[MeshInstance3D] = []
var worn_materials: Array[Material] = []
var prop_materials: Array[Material] = []
var head_contact := Vector3.INF
var _worn_bead_meshes := {}
var hang_height := 1.94
var bottom_height := 0.0
var forms: RefCounted
var presentation := "Worn"
var rest_bounds: AABB
var container: WeakRef
@export_range(-1.0, 0.12, 0.005) var folded_thickness_override := -1.0


static func is_clothing(part: MeshInstance3D) -> bool:
	return not Definition.part_slot(part).is_empty()


func _ready() -> void:
	# Attachments are presentation, not simulation: they must also follow while paused.
	process_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	update_attachment()


func build() -> void:
	stock_parent = get_parent()
	# Extract the existing procedural outfit once. These exact meshes travel through every state.
	var photo_set: bool = definition.is_mosuo_photo_set()
	var source = MosuoDollSource.new() if photo_set else Doll.new()
	if folded_thickness_override >= 0.0:
		definition.folded_thickness = folded_thickness_override
	if not photo_set: source.catalog_style = definition.outfit_style
	if definition.outfit_style == 17:
		source.headband_min_width = definition.headband_min_width
		source.headband_max_width = definition.headband_max_width
	var base_style: int = [0, 1, 2, 2, 2, 0, 2, 2, 2][definition.outfit_style] if definition.outfit_style < 9 else 2
	if photo_set: base_style = 0
	if definition.outfit_style == 12: source.set("catalog_skirt_length",definition.skirt_length)
	if definition.outfit_style in [10,11,13]: source.set("catalog_garment_length",definition.garment_length)
	source.configure({"outfit": base_style, "palette": definition.palette_index})
	visual = source.body_rig
	skeleton = source.rig.skeleton
	for part in source.rig.meshes:
		var keep: bool = Definition.part_slot(part) in definition.slots()
		if photo_set: keep = str(part.get_meta("garment_slot", "")) in definition.slots()
		if definition.accessory_kind == "flower":
			keep = Definition.is_flower(part)
		elif Definition.is_flower(part):
			keep = false
		elif definition.outfit_style in [0,5,12] and str(part.get_meta("semantic","")) in ["legL","legR"]:
			keep = false
		elif Definition.is_button(part):
			keep = definition.outfit_style in [0,3,10,11]
		if not keep:
			part.free()
			continue
		if definition.accessory_kind == "flower": part.set_meta("material_role","flower")
		if part.has_meta("head_contact"):
			head_contact = part.get_meta("head_contact")
		if part.has_meta("tassel_origin"):
			_worn_bead_meshes[part] = part.mesh
		parts.append(part)
		worn_materials.append(part.material_override)
		if part.material_override is StandardMaterial3D:
			# PBR textile maps and bead material travel with the garment in every state.
			prop_materials.append(part.material_override)
		elif _binds_surface_detail(part.material_override):
			# Flat-ink materials that sample a pigment map or vertex colours lose both
			# under the pigment-only room material; the full source material stays on the prop.
			prop_materials.append(part.material_override)
		else:
			var material := ShaderMaterial.new()
			material.shader = ROOM_SHADER
			material.set_shader_parameter("pigment", part.material_override.get_shader_parameter("pigment"))
			prop_materials.append(material)
	if definition.outfit_style == 2:
		var geometry = load("res://scripts/garment_geometry.gd")
		var originals := parts.duplicate()
		for part in originals:
			if str(part.name) not in ["OpenWaistcoat","FrontBinding"]: continue
			var prop := MeshInstance3D.new()
			prop.name = str(part.name)+"Display"
			part.get_parent().add_child(prop)
			prop.transform = part.transform
			prop.mesh = geometry.standalone_waistcoat_mesh(part.mesh)
			prop.skin = part.skin
			prop.skeleton = prop.get_path_to(skeleton)
			prop.material_override = part.material_override
			prop.set_meta("presentation_only","prop")
			part.set_meta("presentation_only","worn")
			parts.append(prop)
			worn_materials.append(part.material_override)
			prop_materials.append(prop_materials[parts.find(part)])
	var minimum := INF
	var maximum := -INF
	var first := true
	for part in parts:
		for point in part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			minimum = minf(minimum, point.y)
			maximum = maxf(maximum, point.y)
			rest_bounds = AABB(point,Vector3.ZERO) if first else rest_bounds.expand(point)
			first = false
	hang_height = maximum
	bottom_height = minimum
	forms = Forms.new()
	forms.build(parts,definition,bottom_height,hang_height)
	visual.get_parent().remove_child(visual)
	add_child(visual)
	source.body_rig = null
	source.free()
	if not definition.material_data.is_empty():
		apply_material_data(definition.material_data)
	_set_worn_materials(false)
	set_presentation(presentation)
	set_meta("single_piece", definition.design_id)
	set_meta("collection_id", definition.collection_id)
	set_meta("wiki_record_id", definition.wiki_record_id)
	set_meta("source_record_id", definition.source_record_id)
	set_meta("garment_form_manifest", forms.manifest(definition.design_id, parts))


func place(destination: String, at: Transform3D, rack_slot := -1) -> void:
	assert(not paid)
	if display_mount != null:
		var previous_mount: Node3D = display_mount.get_ref()
		if is_instance_valid(previous_mount) and previous_mount.get_meta("physical_storage_mount",false): previous_mount.queue_free()
	_clear_attachment()
	_reparent_to(stock_parent)
	location = destination
	slot = rack_slot
	owner_id = "shop"
	reserved_by = ""
	holder = null
	display_mount = null
	container = null
	tried_on = tried_on and destination == "basket"
	_set_worn_materials(false)
	set_presentation("Hanging" if destination == "rack" else "Folded")
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	global_transform = at
	visible = destination != "storage"


func apply_material_data(data: Dictionary) -> void:
	# Both worn and folded presentations retain the same selected material.
	definition.material_data = APPEARANCE.describe(data)
	var uv_metres := Vector2(definition.form_profile(bottom_height,hang_height).uv_width*2.0,hang_height-bottom_height)
	for index in parts.size():
		if Definition.is_button(parts[index]): continue
		if parts[index].get_meta("material_role","") == "flower" and definition.accessory_kind != "flower": continue
		# Ties and straps are cut from the same cloth; thread is a seam detail.
		var mat := APPEARANCE.make_material(definition.material_data,true,uv_metres)
		worn_materials[index] = mat
		prop_materials[index] = mat
		parts[index].material_override = mat


func attach_flower(accessory: Node3D) -> bool:
	if definition.accessory_kind != "" or not definition.flower_material_data.is_empty(): return false
	if accessory.definition.accessory_kind != "flower": return false
	definition.flower_material_data = accessory.definition.material_data.duplicate(true)
	for index in accessory.parts.size():
		var part: MeshInstance3D = accessory.parts[index]
		part.reparent(visual,false)
		part.skeleton = part.get_path_to(skeleton)
		# Rebuild folds against the receiving garment's fold lines.
		var arrays := part.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var offset := Vector3.ZERO
		if definition.is_hat(): offset = Vector3(-.16,.88,-.06)
		elif definition.slots() == ["bottom"]: offset = Vector3(.12,-.45,.025)
		for vertex in vertices.size(): vertices[vertex] += offset
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if definition.is_hat():
			var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for vertex in vertices.size():
				for influence in 4:
					ids[vertex*4+influence] = skeleton.find_bone("Head")
					weights[vertex*4+influence] = 1.0 if influence == 0 else 0.0
			arrays[Mesh.ARRAY_BONES] = ids
			arrays[Mesh.ARRAY_WEIGHTS] = weights
		var base := ArrayMesh.new()
		base.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		part.mesh = base
		forms._bind(part)
		var flower_mat: ShaderMaterial = accessory.worn_materials[index]
		flower_mat.set_shader_parameter("uv_metres",Vector2(definition.form_profile(bottom_height,hang_height).uv_width*2.0,hang_height-bottom_height))
		parts.append(part)
		worn_materials.append(accessory.worn_materials[index])
		prop_materials.append(accessory.prop_materials[index])
	accessory.parts.clear()
	accessory.worn_materials.clear()
	accessory.prop_materials.clear()
	set_meta("flower_item_id",accessory.item_id)
	set_presentation(presentation)
	return true


func reserve(customer: Node) -> bool:
	if location != "rack" or not reserved_by.is_empty():
		return false
	reserved_by = customer.customer_id
	return true


func carry(customer: Node) -> bool:
	if reserved_by != customer.customer_id or paid:
		return false
	holder = weakref(customer)
	display_mount = null
	_bind_attachment(customer)
	location = "carried"
	slot = -1
	_set_worn_materials(false)
	set_presentation("Folded")
	skeleton.reset_bone_poses()
	update_attachment()
	return true


func wear(customer: Node) -> bool:
	if reserved_by != customer.customer_id or location != "carried":
		return false
	holder = weakref(customer)
	location = "worn"
	tried_on = true
	_set_worn_materials(true)
	set_presentation("Worn")
	update_attachment()
	return true


func settle(customer: Node) -> bool:
	if paid or reserved_by != customer.customer_id or location not in ["carried", "worn", "packed"]:
		return false
	paid = true
	owner_id = customer.customer_id
	return true


func put_on_counter(customer: Node3D) -> bool:
	if paid or reserved_by != customer.customer_id or location != "carried": return false
	_clear_attachment()
	location = "counter"
	container = null
	customer.refresh_outfit()
	return true


func pack_into(bag: Node3D) -> bool:
	if location != "counter" or paid: return false
	location = "packed"
	container = weakref(bag)
	if self not in bag.contents: bag.contents.append(self)
	bag.contents = preload("res://scripts/garment_stack.gd").ordered(bag.contents)
	set_presentation("Folded")
	update_attachment()
	return true


func resume_carry(customer: Node3D) -> void:
	container = null
	carry(customer)
	customer.refresh_outfit()


func holder_lost() -> bool:
	return holder != null and not is_instance_valid(holder.get_ref())


func collect() -> void:
	_clear_attachment()
	_reparent_to(stock_parent)
	location = "collected"
	holder = null
	container = null
	hide()


func update_attachment() -> void:
	if location in ["rack","storage","accessory"] and display_mount != null:
		var mount: Node3D = display_mount.get_ref()
		if is_instance_valid(mount):
			global_transform = mount.global_transform
		return
	if holder == null:
		return
	var customer: Node = holder.get_ref()
	if not is_instance_valid(customer):
		return
	if location == "worn":
		global_transform = customer.body_rig.global_transform
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone, customer.rig.skeleton.get_bone_pose(bone))
	elif location == "carried":
		global_transform = customer.carry_transform(self)
	elif location == "packed" and container != null and is_instance_valid(container.get_ref()):
		global_transform = container.get_ref().item_transform(self)
	if _attachment != null and is_instance_valid(_attachment.get_ref()):
		var remote: RemoteTransform3D = _attachment.get_ref()
		remote.global_transform = global_transform
	skeleton.force_update_all_bone_transforms()


func _bind_attachment(customer: Node3D) -> void:
	_clear_attachment()
	# Inventory owns the item. Only this transform proxy belongs to the disposable actor.
	var remote := RemoteTransform3D.new()
	remote.name = "Carry_" + item_id
	customer.body_rig.add_child(remote)
	remote.remote_path = remote.get_path_to(self)
	_attachment = weakref(remote)


func _clear_attachment() -> void:
	if _attachment != null and is_instance_valid(_attachment.get_ref()):
		var remote: RemoteTransform3D = _attachment.get_ref()
		remote.remote_path = NodePath()
		remote.queue_free()
	_attachment = null


static func _binds_surface_detail(material: Material) -> bool:
	if not material is ShaderMaterial:
		return false
	var shader_material := material as ShaderMaterial
	if shader_material.get_shader_parameter("pigment_map") != null:
		return true
	if shader_material.get_shader_parameter("use_pigment_map") == true:
		return true
	return shader_material.get_shader_parameter("use_vertex_color") == true


func _set_worn_materials(worn: bool) -> void:
	for i in parts.size():
		parts[i].material_override = worn_materials[i] if worn else prop_materials[i]


func _reparent_to(parent: Node) -> void:
	if parent != null and get_parent() != parent:
		reparent(parent, true)


# Fit only the display morph. Keep the authored mesh for unlayering and wear.
var unlayered_meshes := {}

func reset_hanger_fit() -> void:
	for part in unlayered_meshes:
		part.mesh = unlayered_meshes[part]
	unlayered_meshes.clear()

func fit_hanger_layer(inner: Node3D, clearance: float, depth_scale: float) -> void:
	reset_hanger_fit()
	var envelope := {}
	for part in inner.parts:
		if not part.visible or part.mesh.get_blend_shape_count() == 0: continue
		var vertices: PackedVector3Array = part.mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
		for v in vertices:
			var key := Vector2i(floori(v.y/.025),posmod(roundi(atan2(v.z,v.x)*48/TAU),48))
			envelope[key] = maxf(envelope.get(key,0.0),Vector2(v.x,v.z).length())
	for part in parts:
		if not part.visible or part.mesh.get_blend_shape_count() == 0: continue
		var original: ArrayMesh = part.mesh
		var shapes := original.surface_get_blend_shape_arrays(0)
		var vertices: PackedVector3Array = shapes[0][Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var v := vertices[i]
			var radial := Vector2(v.x,v.z*depth_scale)
			var angle := roundi(atan2(radial.y,radial.x)*48/TAU)
			var height := floori(v.y/.025)
			var limit := 0.0
			for dy in [-1,0,1]:
				for da in [-1,0,1]:
					limit = maxf(limit,envelope.get(Vector2i(height+dy,posmod(angle+da,48)),0.0))
			if limit > 0 and radial.length() < limit+clearance:
				radial = radial.normalized()*(limit+clearance)
				vertices[i] = Vector3(radial.x,v.y,radial.y/depth_scale)
		shapes[0][Mesh.ARRAY_VERTEX] = vertices
		var fitted := ArrayMesh.new()
		fitted.blend_shape_mode = original.blend_shape_mode
		for i in original.get_blend_shape_count(): fitted.add_blend_shape(original.get_blend_shape_name(i))
		fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,original.surface_get_arrays(0),shapes)
		unlayered_meshes[part] = original
		part.mesh = fitted
	forms.set_form(parts,"Hanging")


func set_presentation(form: String) -> void:
	reset_hanger_fit()
	if has_meta("basket_drape"): remove_meta("basket_drape")
	for part in _worn_bead_meshes:
		part.mesh = _worn_bead_meshes[part]
	presentation = "Worn" if definition.is_hat() or definition.accessory_kind == "flower" else form
	forms.set_form(parts,presentation)
	for part in parts:
		var only: String = part.get_meta("presentation_only","")
		if only != "": part.visible = (presentation == "Worn") == (only == "worn")


# Build only when the item is mounted. The bead generator preserves individual
# barrels and their spacing as the available cord goes over the lip and coils.
func drape_on_display(edge_world: Vector3, floor_world: Vector3) -> void:
	if _worn_bead_meshes.is_empty(): return
	var first: MeshInstance3D = _worn_bead_meshes.keys()[0]
	var recipe: Resource = first.get_meta("bead_recipe").duplicate(true)
	var origin: Vector3 = first.get_meta("tassel_origin")
	var edge := to_local(edge_world)
	var floor_point := to_local(floor_world)
	var direction := (edge - origin).slide(Vector3.UP).normalized()
	var route := Curve3D.new()
	route.bake_interval = .01
	route.add_point(origin)
	# The upper cord clears the crown at the side before dropping to the table.
	route.add_point(origin + Vector3(.32, -.055, .045))
	route.add_point(Vector3(origin.x+.34, edge.y+.018, edge.z-direction.z*.12))
	route.add_point(edge)
	route.add_point(floor_point)
	var length: float = first.get_meta("strand_route_length")
	var cursor := floor_point
	var angle := 0.0
	while route.get_baked_length() < length:
		cursor += Vector3(sin(angle), .001, cos(angle)) * .025
		angle += .025 / .13
		route.add_point(cursor)
	# Trim even if a tall stand leaves the tip suspended above the floor.
	var trimmed := Curve3D.new()
	trimmed.bake_interval = .01
	var walked := 0.0
	for i in range(route.point_count - 1):
		var a := route.get_point_position(i)
		var b := route.get_point_position(i+1)
		trimmed.add_point(a)
		if walked + a.distance_to(b) >= length:
			trimmed.add_point(a.move_toward(b, length-walked))
			break
		walked += a.distance_to(b)
	recipe.path = trimmed
	var groups: Array = recipe.build_geometry_groups()
	for i in groups.size():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		var group: Dictionary = groups[i]
		arrays[Mesh.ARRAY_VERTEX] = group.vertices
		arrays[Mesh.ARRAY_NORMAL] = group.normals
		arrays[Mesh.ARRAY_INDEX] = group.indices
		arrays[Mesh.ARRAY_COLOR] = group.colors
		var display_mesh := ArrayMesh.new()
		display_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var part: MeshInstance3D = _worn_bead_meshes.keys()[i]
		part.mesh = display_mesh

func presentation_bounds(form := "") -> AABB:
	if definition.accessory_kind == "flower": return rest_bounds
	return forms.bounds.get(presentation if form.is_empty() else form,rest_bounds)
