extends SceneTree
## Reproducible browser preview baked from the game's actual mesh and pose code.
## godot --headless --path . --script tools/export_skirt_preview_avatar.gd -- --output ABSOLUTE_DIR
## frames.bin: little-endian Float32 positions, normals, cage positions per frame.
## Every offset and frameStride is measured in Float32 elements, not bytes.

class PreviewDoll extends "res://scripts/volume_doll.gd":
	func _build_volume_body() -> void:
		super._build_volume_body()
		# The game tunic extends under its long skirt; use a waist-length top
		# for the fitting preview so that it cannot cover short-skirt designs.
		_garment.waist_height = 1.31
		_garment.rebuild()
		# The game omits thighs hidden by its long skirt. Complete those two
		# surfaces for short-skirt inspection, before the existing rig binds.
		for leg in legs:
			var thigh := _lathe(leg, "PreviewThigh", [Vector3(-.50,.080,.084),
				Vector3(-.40,.075,.079),Vector3(-.20,.102,.108),
				Vector3(.02,.115,.120),Vector3(.10,.105,.110)], SKIN_TONES[skin_index],16)
			thigh.position.z = .045
const EXCLUDED_NAMES := ["WaistRibbon", "ApronStrapL", "ApronStrapR", "ApronTie"]
const CAGE_ROWS := [.20, .24, .30, .48, .70, .99, 1.22, 1.31]
const RECIPE := {"outfit": 0, "hair": 0, "palette": 0, "skin": 0}
# Preview-only bench contract shared with the frontend: a fixed bench offset,
# the seat carrying the pelvis at .82 (hip rest 1.14 lowered by .32), and the
# nap pelvis resting at .98 with the body lying left along the bench.
const REST_FRAMES := 48
const HIP_REST_Y := 1.14
const HIP_DROP := .32
const SEAT_HIP_Y := HIP_REST_Y - HIP_DROP
const NAP_PELVIS := Vector3(0, .60, 0)
const BENCH_OFFSET := Vector3(0, 0, -.30)
const SEAT_Y := .72

var _failed := false


func _initialize() -> void:
	_export.call_deferred()


func _error(message: String) -> void:
	_failed = true
	push_error(message)


func _xyz(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _flatten(points: PackedVector3Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(points.size() * 3)
	for i in points.size():
		result[i * 3] = points[i].x
		result[i * 3 + 1] = points[i].y
		result[i * 3 + 2] = points[i].z
	return result


func _indices(mesh: Mesh) -> PackedInt32Array:
	var arrays: Array = mesh.surface_get_arrays(0)
	var source: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if source.is_empty():
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			source.append(i)
	# Godot uses clockwise fronts; browser vertices remain in the same XYZ axes.
	for i in range(0, source.size(), 3):
		var b := source[i + 1]
		source[i + 1] = source[i + 2]
		source[i + 2] = b
	return source


func _pigment(part: MeshInstance3D) -> Color:
	var material: Material = part.material_override
	if material == null:
		material = part.mesh.surface_get_material(0)
	if material is ShaderMaterial:
		var color: Variant = material.get_shader_parameter("pigment")
		if color is Color:
			return color
	elif material is BaseMaterial3D:
		return material.albedo_color
	_error("Unsupported color material on " + str(part.name))
	return Color.MAGENTA


func _skin_normals(doll: Node3D, part: MeshInstance3D) -> PackedVector3Array:
	var arrays: Array = part.mesh.surface_get_arrays(0)
	var source: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var transforms: Array[Basis] = []
	for bone in doll.rig.skeleton.get_bone_count():
		var skin: Transform3D = doll.rig.global_pose(bone) * doll.rig.skeleton.get_bone_global_rest(bone).affine_inverse()
		transforms.append(skin.basis.inverse().transposed())
	var result := PackedVector3Array()
	for i in source.size():
		var normal := Vector3.ZERO
		for slot in 4:
			normal += transforms[ids[i * 4 + slot]] * source[i] * weights[i * 4 + slot]
		result.append(normal.normalized())
	return result


func _normals(points: PackedVector3Array, indices: PackedInt32Array, fallback: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(points.size())
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var area_normal := (points[b] - points[a]).cross(points[c] - points[a])
		result[a] += area_normal
		result[b] += area_normal
		result[c] += area_normal
	for i in result.size():
		result[i] = result[i].normalized() if result[i].length_squared() > 0.000000000001 else fallback[i]
	return result


func _check_winding(part: MeshInstance3D, indices: PackedInt32Array) -> void:
	var arrays: Array = part.mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := 0
	var inward := 0
	for i in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		var area_normal := (points[b] - points[a]).cross(points[c] - points[a])
		var agreement := area_normal.dot(normals[a] + normals[b] + normals[c])
		if agreement > 0.00000001:
			outward += 1
		elif agreement < -0.00000001:
			inward += 1
	print("WINDING ", part.name, " outward=", outward, " inward=", inward)
	if inward > outward:
		_error("Exported winding disagrees with source normals: " + str(part.name))


func _joints(doll: Node3D) -> Dictionary:
	var result := {}
	var names := {"root": "Root", "hip": "Hips", "head": "Head", "footL": "FootL", "footR": "FootR", "handL": "HandL", "handR": "HandR"}
	for label: String in names:
		var pose: Transform3D = doll.rig.global_pose(doll.rig.bones[names[label]])
		result[label] = _xyz(pose.origin)
	var hip_index: int = doll.rig.bones.Hips
	var hip_skin: Transform3D = doll.rig.global_pose(hip_index) * doll.rig.skeleton.get_bone_global_rest(hip_index).affine_inverse()
	result.waist = _xyz(hip_skin * Vector3(0, 1.31, 0))
	return result


func _pose_rest_frame(doll: Node3D, action: String, factor: float) -> void:
	preload("res://scripts/garment_preview_poses.gd")._pose_rest_frame(doll,action,factor)

func _export() -> void:
	var output := ProjectSettings.globalize_path("res://captures/skirt_avatar_export")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--output" or not args[1].is_absolute_path():
			_error("Usage: -- --output ABSOLUTE_DIRECTORY")
			quit(1)
			return
		output = args[1]
	var doll := PreviewDoll.new()
	root.add_child(doll)
	doll.configure(RECIPE)
	doll.set_process(false)
	doll.rig.animate(0, 0, "idle", 0)
	var parts: Array[MeshInstance3D] = []
	var local_indices: Array[PackedInt32Array] = []
	var part_manifest: Array = []
	var excluded: Array = []
	var all_indices := PackedInt32Array()
	var colors := PackedFloat32Array()
	var vertex_count := 0
	var cage: MeshInstance3D
	for part: MeshInstance3D in doll.rig.meshes:
		var semantic := str(part.get_meta("semantic", ""))
		if str(part.name) == "LongSkirt":
			cage = part
		if semantic in ["skirt", "apron"] or str(part.name) in EXCLUDED_NAMES or not part.is_visible_in_tree():
			excluded.append(str(part.name))
			continue
		if part.mesh.get_surface_count() != 1 or part.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
			_error("Expected one triangle surface on " + str(part.name))
			continue
		var arrays: Array = part.mesh.surface_get_arrays(0)
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		var triangles := _indices(part.mesh)
		_check_winding(part, triangles)
		part_manifest.append({"name": str(part.name), "semantic": semantic, "vertexOffset": vertex_count,
			"vertexCount": count, "indexOffset": all_indices.size(), "indexCount": triangles.size()})
		for index in triangles:
			if index < 0 or index >= count:
				_error("Out of range vertex index on " + str(part.name))
			all_indices.append(index + vertex_count)
		var color := _pigment(part)
		for i in count:
			colors.append_array(PackedFloat32Array([color.r, color.g, color.b]))
		parts.append(part)
		local_indices.append(triangles)
		vertex_count += count
	if cage == null:
		_error("The LongSkirt deformation cage is missing")
	if _failed:
		doll.free()
		quit(1)
		return
	var cage_rest: PackedVector3Array = doll.rig.deformed_vertices(cage)
	var cage_count := cage_rest.size()
	if cage_count != CAGE_ROWS.size() * 41:
		_error("The LongSkirt cage topology changed; update columns/rowsY mapping")
	var frame_stride := vertex_count * 6 + cage_count * 3
	var manifest := {"version": 2, "vertexCount": vertex_count, "indices": all_indices, "colors": colors,
		"frameStride": frame_stride, "binary": {"uri": "frames.bin", "type": "float32-le"},
		"coordinateSystem": "right-handed-y-up", "frontFace": "ccw", "recipe": RECIPE,
		"parts": part_manifest, "excludedParts": excluded, "actions": {},
		"cage": {"vertexCount": cage_count, "indices": _indices(cage.mesh), "columns": 40,
			"rowsY": CAGE_ROWS, "restPositions": _flatten(cage_rest)}}
	var binary := PackedFloat32Array()
	for action: String in ["stand", "walk", "sit", "lie"]:
		var count := 1 if action == "stand" else (24 if action == "walk" else REST_FRAMES)
		var fps := 1 if action == "stand" else 24
		var frames: Array = []
		for frame in count:
			var factor := float(frame) / float(maxi(1, count - 1))
			doll.rig.animate(TAU * frame / count if action == "walk" else 0.0, 1.0 if action == "walk" else 0.0, "idle", 0.0)
			if action in ["sit", "lie"]:
				_pose_rest_frame(doll, action, factor)
			var positions := PackedVector3Array()
			var normals := PackedVector3Array()
			for i in parts.size():
				var points: PackedVector3Array = doll.rig.deformed_vertices(parts[i])
				positions.append_array(points)
				normals.append_array(_normals(points, local_indices[i], _skin_normals(doll, parts[i])))
			var cage_positions: PackedVector3Array = doll.rig.deformed_vertices(cage)
			if positions.size() != vertex_count or cage_positions.size() != cage_count:
				_error("Pose changed mesh topology: " + action)
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			var bound_points := positions.duplicate()
			bound_points.append_array(cage_positions)
			for point in bound_points:
				if not point.is_finite():
					_error("Non-finite position: " + action)
				low = low.min(point)
				high = high.max(point)
			for normal in normals:
				if not normal.is_finite() or absf(normal.length() - 1.0) > .001:
					_error("Invalid unit normal: " + action)
			frames.append({"offset": binary.size(), "joints": _joints(doll), "bounds": {"min": _xyz(low), "max": _xyz(high)}})
			binary.append_array(_flatten(positions))
			binary.append_array(_flatten(normals))
			binary.append_array(_flatten(cage_positions))
		var action_entry := {"fps": fps, "loop": action == "walk", "frames": frames}
		if action in ["sit", "lie"]:
			action_entry["benchOffset"] = _xyz(BENCH_OFFSET)
			action_entry["seatY"] = SEAT_Y
		manifest.actions[action] = action_entry
		print("BAKED ", action, " frames=", frames.size(), " lastBounds=", frames[-1].bounds)
	if _failed:
		doll.free()
		quit(1)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(output)
	if directory_error != OK:
		_error("Cannot create output directory: " + error_string(directory_error))
		quit(1)
		return
	var frame_file := FileAccess.open(output.path_join("frames.bin"), FileAccess.WRITE)
	if frame_file == null:
		_error("Cannot write frames.bin: " + error_string(FileAccess.get_open_error()))
		quit(1)
		return
	frame_file.big_endian = false
	frame_file.store_buffer(binary.to_byte_array())
	frame_file.close()
	var manifest_file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if manifest_file == null:
		_error("Cannot write manifest.json: " + error_string(FileAccess.get_open_error()))
		quit(1)
		return
	manifest_file.store_string(JSON.stringify(manifest))
	manifest_file.close()
	var total_frames := 0
	for action: String in manifest.actions:
		total_frames += manifest.actions[action].frames.size()
	print("SKIRT_AVATAR_EXPORT_PASS vertices=", vertex_count, " triangles=", all_indices.size() / 3,
		" parts=", parts.size(), " cageVertices=", cage_count, " frames=", total_frames, " frameStride=", frame_stride,
		" binaryBytes=", binary.size() * 4, " output=", output)
	doll.free()
	quit()
