extends Resource
## Shared surface-knit recipe. Height is in the doll's bind-pose coordinates.
@export var enabled := false
@export_range(0.0, 1.0) var length := 0.22
@export var color := Color("efede5")
@export var pattern_color := Color("c4b6a2")
@export_enum("Plain", "Rib", "Stripes", "Dots") var pattern := 1
@export_range(1.0, 64.0) var repeats := 20.0
@export var texture: Texture2D
@export var texture_scale := Vector2(1, 4)

func top_height() -> float:
	# Boat, ankle, knee, thigh, then a continuous waist section for tights.
	return 0.15 + clampf(length, 0.0, 1.0) * 1.19

func build(doll: Node3D) -> void:
	if not enabled:
		return
	# Continue the existing leg surface through the thigh for stockings/tights.
	for leg: Node3D in doll.legs:
		var source := leg.get_node_or_null("CalfMannequin")
		if source == null:
			source = leg.get_node_or_null("Calf")
		if source == null or top_height() <= .70:
			continue
		var thigh := leg.get_node_or_null("ThighMannequin")
		if thigh == null:
			thigh = doll._lathe(leg, "HosieryLeg", [Vector3(-.40,.075,.079), Vector3(-.25,.085,.09), Vector3(-.10,.10,.11), Vector3(.04,.12,.13)], doll.get_skin_color(), 32)
			thigh.position.z = .045
		thigh.visible = true
	if length >= .95:
		doll._lathe(doll.body_rig, "HosieryWaist", [Vector3(1.02,.24,.17), Vector3(1.14,.27,.18), Vector3(1.34,.25,.17)], color, 40)

func apply(doll: Node3D) -> void:
	var hem := INF
	for mesh: MeshInstance3D in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
		if mesh.visible and str(mesh.name) in ["LongSkirt", "UkrUnderskirt"]:
			hem = minf(hem, mesh.mesh.get_aabb().position.y)
	for mesh: MeshInstance3D in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
		var label := str(mesh.name)
		if label not in ["Calf", "CalfMannequin", "ThighMannequin", "MannequinTorso", "WhiteSockInstep", "HosieryLeg", "HosieryWaist"]:
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var uv := PackedVector2Array()
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
			var center := signf(point.x) * .14
			uv.append(Vector2(atan2(point.x-center, point.z-.025)/TAU+.5, point.y))
		arrays[Mesh.ARRAY_TEX_UV2] = uv
		var surface := ArrayMesh.new()
		surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.mesh = surface
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/hosiery.gdshader")
		mat.set_shader_parameter("pigment", doll.get_skin_color())
		mat.set_shader_parameter("sock_color", color)
		mat.set_shader_parameter("pattern_color", pattern_color)
		mat.set_shader_parameter("sock_top", top_height() if enabled else -1.0)
		mat.set_shader_parameter("pattern", pattern)
		mat.set_shader_parameter("repeats", repeats)
		mat.set_shader_parameter("use_texture", texture != null)
		mat.set_shader_parameter("knit_texture", texture)
		mat.set_shader_parameter("texture_scale", texture_scale)
		# Preserve the shoe's existing white liner when hosiery is disabled.
		if label == "WhiteSockInstep":
			mat.set_shader_parameter("pigment", Color("efede5"))
		if label in ["Calf", "CalfMannequin", "ThighMannequin", "HosieryLeg", "HosieryWaist"] and hem != INF:
			mat.set_shader_parameter("covered_above", hem + .045)
		if label in ["HosieryLeg", "HosieryWaist"]:
			mat.set_shader_parameter("surface_only", true)
		mesh.material_override = mat
