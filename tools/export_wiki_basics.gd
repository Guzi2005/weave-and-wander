extends SceneTree
const Definition = preload("res://scripts/garment_definition.gd")
const WikiPaths = preload("res://tools/wiki_paths.gd")
func _initialize(): run.call_deferred()
func run():
	for style in [0,1,2,3,4,5,6,7,8,9,10,11,12,13,17]:
		var item = preload("res://scripts/garment_item.gd").new()
		item.definition = Definition.create(style,0)
		if style == 9:
			item.definition = Definition.create(0,0)
			item.definition.accessory_kind = "flower"
		root.add_child(item)
		item.build()
		var model := Node3D.new()
		root.add_child(model)
		for source in item.parts:
			var part := MeshInstance3D.new()
			var arrays: Array = source.mesh.surface_get_arrays(0)
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			part.mesh = mesh
			part.name = source.name
			var material := StandardMaterial3D.new()
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			if source.material_override is ShaderMaterial:
				var pigment = source.material_override.get_shader_parameter("pigment")
				if pigment is Color: material.albedo_color = pigment
			part.material_override = material
			model.add_child(part)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_scene(model,state) != OK: quit(1); return
		var path: String = WikiPaths.public_assets_dir().path_join("models").path_join(Definition.DESIGN_IDS[style]+".glb")
		if doc.write_to_filesystem(state,path) != OK: quit(1); return
		print("EXPORTED ",style," ",path)
		model.free()
		item.free()
	quit()

