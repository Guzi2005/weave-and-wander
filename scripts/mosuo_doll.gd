class_name MosuoDoll
extends "res://scripts/volume_doll.gd"

## Photo-derived costume set mosuo_photo_001 (wiki record WW-MOS-001) on the
## shared 22-bone rig: black cord-wrapped headwear with dense purple
## seed-bead strands on the viewer-right side, red patterned short blouse
## with light collar/front trim, and a cyan ankle-length pleated skirt with
## pale flecks and a fine red lower stripe. The generic body is built first
## and the base outfit is replaced before the rig binds, so skinning,
## extraction and the walking gait are the shared ones. The right bystander
## is excluded. The user's identification of the held magenta-edged insole is
## recorded separately; shoes stay the generic culture-neutral low shoe.

const MosuoCostume = preload("res://components/mosuo_costume.gd")
const BeadBundle = preload("res://components/seed_bead_bundle.gd")
const Fabric = preload("res://scripts/mosuo_fabric.gd")
const BlenderParts = preload("res://components/mosuo_blender_parts.gd")
const Braid = preload("res://components/path_braid.gd")
const Flower = preload("res://components/parametric_flower.gd")
const Socket = preload("res://components/accessory_socket.gd")
const FlatMaterial = preload("res://scripts/doll_costume_material.gd")
var bead_parameters: Resource
var braid_parameters: Resource
var flower_parameters: Resource
var flower_mount_position := Vector3(.27,.74,.12)
var flower_mount_rotation := Vector3(0,0,-12)
var bead_mount_offset := Vector3.ZERO
@export var headwear_position := Vector3(0,.055,-.025)
@export var headwear_rotation_degrees := Vector3(-8,0,-4)

const COLOR_HAT := Color("26232b")
const COLOR_CORDS: Array[Color] = [Color("c23a2e"), Color("ddb53c"), Color("4d8a4e"), Color("3d6f9e")]
const COLOR_POMPOM := Color("ce362c")
const COLOR_BEADS := Color("7a4a9c")
const COLOR_BLOUSE := Color("b93530")
const COLOR_TRIM := Color("efe4c6")
const COLOR_MOTIF_A := Color("e6b25c")
const COLOR_MOTIF_B := Color("7d80c3")
const COLOR_MOTIF_C := Color("cf5d8a")
const COLOR_MOTIF_D := Color("748d58")
const COLOR_SKIRT := Color("8ec9d6")
const COLOR_FLECK := Color("e4efe9")
const COLOR_STRIPE := Color("a83a5e")
const COLOR_WAISTBAND := Color("8a2f2b")
const COLOR_SHOE := Color("3a3436")


func _build_appearance() -> void:
	super()
	FlatMaterial.apply_to(body_rig)
	# Skinning bakes the source socket transforms. Keep their live bone-following
	# anchors too, so inspection/export retains where each adornment attaches.
	for socket in body_rig.find_children("*Socket", "Marker3D", true, false):
		if not socket is Socket: continue
		# Garment extraction also constructs a doll outside the SceneTree.
		var rest_transform: Transform3D = socket.transform
		var ancestor := socket.get_parent() as Node3D
		while ancestor != body_rig:
			rest_transform = ancestor.transform * rest_transform
			ancestor = ancestor.get_parent() as Node3D
		var attachment := BoneAttachment3D.new()
		attachment.name = str(socket.name) + "Bone"
		rig.skeleton.add_child(attachment)
		attachment.bone_name = socket.bone_name
		var bone: int = rig.skeleton.find_bone(socket.bone_name)
		socket.reparent(attachment, false)
		socket.transform = rig.skeleton.get_bone_global_rest(bone).affine_inverse() * rest_transform
		attachment.set_meta("source_socket",socket.socket_id)
		attachment.set_meta("mount_editing","Change authoring parameters and rebuild; geometry is skinned to the same bone.")


func _costume_palette() -> Array:
	# The photo set keeps its recorded colors regardless of the daily palette;
	# the remaining generic parts (cuffs, trims) pick up the light edging tone.
	return [COLOR_BLOUSE, COLOR_TRIM, COLOR_SKIRT]


func _build_volume_body() -> void:
	super()
	_strip_base_costume()
	_build_mosuo_top()
	_build_mosuo_skirt()
	var hand_socket := _socket(clothes_root,"InsoleGripSocket",Vector3(.30,1.17,.12),Vector3(0,0,-8),"HandR","手持鞋垫")
	for data in BlenderParts.parts("handcraft"):
		# Handcraft vertices are authored around their own grip origin in Blender.
		var insole := _costume_part(hand_socket,data.name,data,Color.WHITE)
		insole.material_override = BlenderParts.material(data.material)
		insole.set_meta("attachment_bone","HandR")
		insole.set_meta("socket",hand_socket.specification())
		insole.set_meta("wiki_record_id","WW-MOS-001-P01")


func _build_volume_head() -> void:
	super()
	# The reference has black hair under a bound braid cap; the generic twin buns
	# do not belong to this silhouette.
	var hair_slot := head_rig.get_node_or_null("HairSlot")
	if hair_slot != null:
		for part in hair_slot.get_children():
			if part is MeshInstance3D:
				if str(part.name) == "HairCap" or str(part.name) == "HairPart":
					part.material_override = _material(Color("221d25"))
				else: part.free()
	var slot := Node3D.new()
	slot.name = "HeadwearSlot"
	slot.position = headwear_position
	slot.rotation_degrees = headwear_rotation_degrees
	head_rig.add_child(slot)
	_add_blender_parts(slot, "headwear")
	if braid_parameters == null: braid_parameters = Braid.photo_001()
	var braid := _costume_part(slot,"MosuoPathBraid",braid_parameters.build_geometry(),Color.WHITE)
	braid.material_override = braid_parameters.material()
	braid.set_meta("component_schema",braid_parameters.parameters())
	if flower_parameters == null: flower_parameters = load("res://assets/collections/mosuo_flower.tres").duplicate()
	var flower_socket := _socket(slot,"CrownFlowerSocket",flower_mount_position,flower_mount_rotation,"Head","朝上头花")
	var flower := _costume_part(flower_socket,"MosuoParametricFlower",flower_parameters.build_geometry(),Color.WHITE)
	flower.material_override = flower_parameters.material()
	flower.set_meta("component_schema",flower_parameters.parameters())
	flower.set_meta("socket",flower_socket.specification())
	if bead_parameters == null: bead_parameters = BeadBundle.photo_001()
	var draped: Resource = bead_parameters.duplicate(true)
	# Solve the hanging route in upright body space, then return to the tilted
	# headwear frame. Only the upper anchor inherits the entire mount rotation.
	if draped.path != null:
		var mount := slot.transform
		for i in draped.path.get_point_count():
			var p: Vector3 = draped.path.get_point_position(i)
			var follows_hat := 1.0-smoothstep(.0,.5,float(i))
			var fixed: Vector3 = p.lerp(mount*p,follows_hat)
			draped.path.set_point_position(i,mount.affine_inverse()*fixed)
		for i in draped.path.get_point_count():
			var tangent: Vector3 = (draped.path.get_point_position(mini(i+1,draped.path.get_point_count()-1))-draped.path.get_point_position(maxi(0,i-1)))/6.0
			draped.path.set_point_in(i,-tangent)
			draped.path.set_point_out(i,tangent)
	var bead_origin: Vector3 = draped.path.get_point_position(0) if draped.path != null else draped.anchor
	var bead_socket := _socket(slot,"OccipitalTasselSocket",bead_origin+bead_mount_offset,Vector3.ZERO,"Head","后脑珠束收束点")
	# Keep the two physical contacts in the same rest space as the baked skin.
	braid.set_meta("head_contact", head_rig.transform * (HEAD_CENTER + Vector3.UP * HEAD_RADIUS.y))
	var groups: Array = draped.build_geometry_groups()
	for index in groups.size():
		var group: Dictionary = groups[index]
		var local_vertices: PackedVector3Array = group.vertices.duplicate()
		for i in local_vertices.size(): local_vertices[i] -= bead_origin
		group.vertices = local_vertices
		var beads := _costume_part(bead_socket,"MosuoBeadStrands" if index == 0 else "MosuoBeadStrands%d" % index,group,Color.WHITE)
		beads.material_override = bead_parameters.material_for(group.material_preset)
		beads.set_meta("component_schema",bead_parameters.parameters())
		beads.set_meta("socket",bead_socket.specification())
		beads.set_meta("tassel_origin", head_rig.transform * slot.transform * bead_socket.position)
		beads.set_meta("strand_route_length", draped.path.get_baked_length() if draped.path != null else draped.strand_length)
		beads.set_meta("bead_recipe", bead_parameters)


func _socket(parent: Node3D, label: String, offset: Vector3, angles: Vector3, bone: String, purpose: String) -> Socket:
	var socket := Socket.new()
	socket.name = label
	socket.socket_id = label
	socket.bone_name = bone
	socket.purpose = purpose
	parent.add_child(socket)
	socket.position = offset
	socket.rotation_degrees = angles
	return socket


func _strip_base_costume() -> void:
	# Everything removed here belongs to the generic outfit-0 costume; the
	# body, head, hair, arms, calves and shoes stay.
	if _garment != null:
		_garment.free()
		_garment = null
	for label in ["WaistRibbon", "StandingCollar", "ButtonRow", "FlowerCenter"]:
		var node := clothes_root.get_node_or_null(label)
		if node != null:
			node.free()
	for petal in clothes_root.find_children("Petal*", "MeshInstance3D", false, false):
		petal.free()
	if skirt_root != null:
		skirt_root.free()
	_skirt = null
	skirt_root = Node3D.new()
	skirt_root.name = "SkirtAndTrims"
	clothes_root.add_child(skirt_root)
	for arm in arms:
		var wrist := arm.get_node_or_null("WristDetails")
		if wrist == null:
			continue
		# The blouse has its own cuffed sleeves; the base cuff rims belong to
		# the removed long-sleeve shell.
		for cuff in ["CuffBinding", "CuffThickness", "SleeveLining"]:
			var piece := wrist.get_node_or_null(cuff)
			if piece != null:
				piece.free()
	for leg in legs:
		var calf := leg.get_node_or_null("Calf")
		if calf != null:
			calf.set_meta("garment_slot", "")
		var shoe := leg.get_node_or_null("Shoe")
		if shoe != null:
			for piece in shoe.get_children():
				var dark := str(piece.name) == "FlatSole"
				(piece as MeshInstance3D).material_override = _material(COLOR_SHOE.darkened(.18) if dark else COLOR_SHOE)


func _build_mosuo_top() -> void:
	_add_blender_parts(clothes_root, "top")


func _build_mosuo_skirt() -> void:
	_add_blender_parts(skirt_root, "bottom")
	_skirt = skirt_root.get_node("MosuoPleatedSkirt")


func _add_blender_parts(parent: Node3D, slot: String) -> void:
	for data in BlenderParts.parts(slot):
		if data.name == "MosuoCoiledFalseBraids" or data.name.begins_with("MosuoFlowerPetals"): continue
		var part := _costume_part(parent, data.name, data, Color.WHITE)
		part.material_override = Fabric.make(data.material) if data.material in ["blouse","skirt"] else BlenderParts.material(data.material)
		part.set_meta("source_geometry","Blender / mosuo_photo_001.blend")
		part.set_meta("wiki_record_id","WW-MOS-001")


func _costume_part(parent: Node3D, label: String, data: Dictionary, color: Color) -> MeshInstance3D:
	var part := _mesh(parent, label, data.vertices, data.normals, data.indices, color)
	if data.has("uv") or data.has("colors"):
		var arrays := part.mesh.surface_get_arrays(0)
		if data.has("uv"): arrays[Mesh.ARRAY_TEX_UV] = data.uv
		if data.has("colors"): arrays[Mesh.ARRAY_COLOR] = data.colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		part.mesh = mesh
		if data.has("uv"): part.set_meta("preserve_fabric_uv",true)
	part.set_meta("garment_slot", data.slot)
	var arm_weights: PackedFloat32Array = data.arm_weights
	for value in arm_weights:
		if not is_zero_approx(value):
			part.set_meta("garment_arm_weights", arm_weights)
			break
	return part
