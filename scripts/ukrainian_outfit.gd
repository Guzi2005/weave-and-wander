extends RefCounted
## Dresses the shared VolumeDoll in the ukrainian_photo_001 set (WW-UKR-001).
## Body, head, hair, mittens and shoes are the shared rig and stay untouched;
## only the generic outfit-0 clothing is replaced (same convention as MosuoDoll).

const Costume = preload("res://components/ukrainian_costume.gd")
const SHADER = preload("res://shaders/doll_costume.gdshader")
const COLOR_SHOE = Color("684333")
const RELIEF_CLOTH := .34
const RELIEF_TRIM := .18
var doll: Node3D


func apply(target: Node3D) -> void:
	doll = target
	# The wide skirt occupies the default hand position below the high waist.
	doll.body_rig.set_meta("relaxed_arm_angles", Vector2(deg_to_rad(-7.0), deg_to_rad(16.0)))
	_strip_base_costume()
	for label in preload("res://scripts/ukrainian_blender_mesh.gd").names():
		var data := preload("res://scripts/ukrainian_blender_mesh.gd").geometry(label)
		if data.slot == "hair": continue
		var parent: Node3D = doll.skirt_root if data.slot == "bottom" else doll.clothes_root
		_part(parent, label, data, Color.WHITE, RELIEF_CLOTH)


func _strip_base_costume() -> void:
	# Remove only generic outfit-0 clothing; body, head, hair, arms, calves
	# and shoes stay.
	if doll._garment != null:
		doll._garment.free()
		doll._garment = null
	for label in ["WaistRibbon", "StandingCollar", "ButtonRow", "FlowerCenter"]:
		var node = doll.clothes_root.get_node_or_null(label)
		if node != null:
			node.free()
	for petal in doll.clothes_root.find_children("Petal*", "MeshInstance3D", false, false):
		petal.free()
	if doll.skirt_root != null:
		doll.skirt_root.free()
	doll._skirt = null
	doll.skirt_root = Node3D.new()
	doll.skirt_root.name = "SkirtAndTrims"
	doll.clothes_root.add_child(doll.skirt_root)
	for arm in doll.arms:
		var wrist = arm.get_node_or_null("WristDetails")
		if wrist == null:
			continue
		for cuff in ["CuffBinding", "CuffThickness", "SleeveLining"]:
			var piece = wrist.get_node_or_null(cuff)
			if piece != null:
				piece.free()
	for leg in doll.legs:
		var calf = leg.get_node_or_null("Calf")
		if calf != null:
			calf.set_meta("garment_slot", "")
		var shoe = leg.get_node_or_null("Shoe")
		if shoe != null:
			for piece in shoe.get_children():
				if piece.name == "WhiteSockInstep": continue
				var dark = str(piece.name) == "FlatSole"
				(piece as MeshInstance3D).material_override = doll._material(COLOR_SHOE.darkened(.18) if dark else COLOR_SHOE)


func _material(color: Color, relief: float, vertex_colors: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("pigment", color)
	mat.set_shader_parameter("use_vertex_color", vertex_colors)
	mat.set_shader_parameter("relief_strength", relief)
	mat.set_shader_parameter("tone_steps", 6.0)
	mat.set_shader_parameter("use_pigment_map", true)
	mat.set_shader_parameter("pigment_map", preload("res://assets/collections/ukrainian_photo_001/linen_weave.png"))
	return mat


func _part(parent: Node3D, label: String, data: Dictionary, color: Color, relief: float) -> MeshInstance3D:
	var part = doll._mesh(parent, label, data.vertices, data.normals, data.indices, color)
	var arrays = part.mesh.surface_get_arrays(0)
	if data.has("uv"):
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		part.set_meta("preserve_fabric_uv", true)
	if data.has("colors"):
		arrays[Mesh.ARRAY_COLOR] = data.colors
	if data.has("uv") or data.has("colors"):
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		part.mesh = mesh
	part.material_override = _material(color, relief, data.has("colors"))
	part.set_meta("garment_slot", data.slot)
	part.set_meta("source_geometry", "Procedural / ukrainian_photo_001")
	part.set_meta("wiki_record_id", "WW-UKR-001")
	var arm_weights: PackedFloat32Array = data.arm_weights
	for value in arm_weights:
		if not is_zero_approx(value):
			part.set_meta("garment_arm_weights", arm_weights)
			break
	return part
