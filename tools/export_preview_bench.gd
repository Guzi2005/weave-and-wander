extends SceneTree
const Bench = preload("res://components/rest_bench.gd")
func _initialize() -> void:
	_export.call_deferred()
func _export() -> void:
	var output := ProjectSettings.globalize_path("res://captures/bench_export")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--output" or not args[1].is_absolute_path():
			push_error("Usage: -- --output ABSOLUTE_DIRECTORY")
			quit(1)
			return
		output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var bench := Bench.new()
	root.add_child(bench)
	bench.set_process(false)
	var positions := PackedFloat32Array()
	var normals := PackedFloat32Array()
	var colors := PackedFloat32Array()
	var indices := PackedInt32Array()
	var names: Array = []
	for part: MeshInstance3D in bench.find_children("*", "MeshInstance3D", true, false):
		var transform: Transform3D = bench.global_transform.affine_inverse() * part.global_transform
		var material: Material = part.material_override
		if material == null:
			material = part.mesh.surface_get_material(0)
		var pigment: Color = material.get_shader_parameter("pigment") if material is ShaderMaterial else material.albedo_color
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base := positions.size()/3
			for i in vertices.size():
				var point := transform * vertices[i]
				var normal := (transform.basis.inverse().transposed()*ns[i]).normalized()
				positions.append_array(PackedFloat32Array([point.x,point.y,point.z]))
				normals.append_array(PackedFloat32Array([normal.x,normal.y,normal.z]))
				colors.append_array(PackedFloat32Array([pigment.r,pigment.g,pigment.b]))
			if source.is_empty():
				for i in vertices.size(): source.append(i)
			for i in range(0,source.size(),3):
				indices.append_array(PackedInt32Array([base+source[i],base+source[i+2],base+source[i+1]]))
		names.append(str(part.name))
	var file := FileAccess.open(output.path_join("bench.bin"),FileAccess.WRITE)
	if file == null:
		push_error("Cannot write bench.bin")
		quit(1)
		return
	for buffer in [positions.to_byte_array(), normals.to_byte_array(), colors.to_byte_array(), indices.to_byte_array()]:
		file.store_buffer(buffer)
	file.close()
	file = FileAccess.open(output.path_join("bench.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"source":"components/rest_bench.gd","seatHeight":Bench.SEAT_HEIGHT,"parts":names,"vertexCount":positions.size()/3,"indexCount":indices.size()}))
	file.close()
	print("BENCH_EXPORT parts=",names.size()," vertices=",positions.size()/3)
	bench.free()
	quit()
