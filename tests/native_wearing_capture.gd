extends "res://tests/layered_cloth_capture.gd"

const PROOF := "res://captures/wearing_simulation_nap0_blender_native.json"
const LayerTransfer = preload("res://tests/experiments/native_layer_transfer.gd")
const ProofPaths = preload("res://tests/experiments/wearing_proof_paths.gd")
const SeamSplit = preload("res://tests/experiments/garment_seam_split.gd")
var input_hashes := {}
var proof_inverse_error := 0.0
var resolved_references: Array = []


func _dependency(recorded: String, owner: String, expected_sha: String) -> String:
	var resolved: Dictionary = ProofPaths.resolve(recorded, owner, expected_sha)
	resolved_references.append(resolved)
	_check(resolved.error.is_empty(), "Proof dependency: %s (%s)" % [resolved.error, recorded])
	return resolved.path if resolved.error.is_empty() else ""


func _read_dictionary(path: String) -> Dictionary:
	if not _check(FileAccess.file_exists(path), "Missing input: " + path): return {}
	var parser := JSON.new()
	if not _check(parser.parse(FileAccess.get_file_as_string(path)) == OK and parser.data is Dictionary, "Invalid input JSON: " + path): return {}
	input_hashes[path] = FileAccess.get_sha256(path)
	return parser.data


func _source_hashes(data: Dictionary) -> void:
	if not _check(data.get("source_sha256") is Dictionary, "Missing source hash manifest"): return
	for path: String in data.source_sha256:
		_check(FileAccess.file_exists(path) and FileAccess.get_sha256(path) == data.source_sha256[path], "Source hash mismatch: " + path)
		input_hashes[path] = data.source_sha256[path]


func _points(values: Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for value in values:
		if not _check(value is Array and value.size() == 3, "Invalid XYZ data"): return result
		var point := Vector3(value[0], value[1], value[2])
		if not _check(point.is_finite(), "Nonfinite input point/normal"): return result
		result.append(point)
	return result


func _vector_hash(vertices: PackedVector3Array) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(vertices.to_byte_array())
	return context.finish().hex_encode()


func _validate_geometry(doll: Node3D, skirt: MeshInstance3D, source: Dictionary, data: Dictionary) -> void:
	var arrays := skirt.mesh.surface_get_arrays(0)
	var original: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(_vector_hash(original) == source.base_skirt.vertex_sha256, "Proof standing vertex hash differs")
	var supplied := _points(source.base_skirt.vertices)
	_check(_vector_hash(supplied) == source.base_skirt.vertex_sha256 and supplied == original, "Source standing vertices differ")
	_check(_points(source.base_skirt.normals) == arrays[Mesh.ARRAY_NORMAL], "Source standing normals differ")
	_check(PackedInt32Array(source.base_skirt.indices) == arrays[Mesh.ARRAY_INDEX], "Source triangle indices differ")
	var body_count := 0
	for entry: Dictionary in source.body_parts:
		var matches := 0
		for part: MeshInstance3D in doll.rig.meshes:
			if str(part.name) != entry.name or part.get_meta("semantic", "") != entry.semantic: continue
			matches += 1
			_check(part.get_meta("is_underbody", false) and part.is_visible_in_tree(), "Source body is not visible accepted body")
			var body_arrays := part.mesh.surface_get_arrays(0)
			_check(_points(entry.rest_vertices) == body_arrays[Mesh.ARRAY_VERTEX], "Source body rest vertices differ: " + entry.semantic)
			_check(_points(entry.normals) == body_arrays[Mesh.ARRAY_NORMAL], "Source body normals differ: " + entry.semantic)
			_check(PackedInt32Array(entry.indices) == body_arrays[Mesh.ARRAY_INDEX], "Source body indices differ: " + entry.semantic)
		_check(matches == 1, "Ambiguous source body part")
		body_count += matches
	_check(body_count == 3 and doll.rig.skeleton.get_bone_count() == 22, "Expected three source body parts and 22 bones")
	var target := _points(data.get("unskinned_vertices", []))
	var normals := _points(data.get("unskinned_normals", []))
	var posed := _points(data.get("posed_vertices", []))
	_check(target.size() == original.size() and normals.size() == original.size() and posed.size() == original.size(), "Proof array counts differ")
	for normal in normals: _check(normal.length_squared() > .5, "Invalid proof normal")
	if not failures.is_empty(): return
	var last: Dictionary = source.frames[-1]
	_check(last.frame == 180 and last.rest_amount == 1.0 and data.get("frame", 0) == 180, "Proof is not final nap0")
	var inverses: Array = last.cloth_inverse_skin_transforms
	if not _check(inverses.size() == target.size(), "Source inverse count differs"): return
	for i in target.size():
		var rows: Array = inverses[i].basis_rows
		if not _check(rows.size() == 3, "Invalid inverse matrix"): return
		var r := _points(rows)
		var origin := _points([inverses[i].origin])
		if r.size() != 3 or origin.size() != 1: return
		var inverse := Transform3D(Basis(r[0], r[1], r[2]).transposed(), origin[0])
		proof_inverse_error = maxf(proof_inverse_error, (inverse * posed[i]).distance_to(target[i]))
	_check(proof_inverse_error < .00002, "Proof posed/unskinned data disagree with source inverses")


func _actor_signature(doll: Node3D) -> int:
	var values: Array = [_body_signature(doll), doll.body_rig.transform]
	for bone in doll.rig.skeleton.get_bone_count(): values.append(doll.rig.skeleton.get_bone_pose(bone))
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.get_meta("is_underbody", false): continue
		var material := part.material_override as ShaderMaterial
		values.append([part.material_override, material.get_shader_parameter("cloth_contact_enabled") if material != null else null])
	return hash(var_to_bytes(values))


func _snapshot(parts: Array[MeshInstance3D]) -> Array:
	var result: Array = []
	for part in parts:
		var weights: Array = []
		for shape in part.mesh.get_blend_shape_count(): weights.append(part.get_blend_shape_value(shape))
		var materials: Array = []
		for surface in part.mesh.get_surface_count(): materials.append(part.get_surface_override_material(surface))
		var metadata := {}
		for key in part.get_meta_list(): metadata[key] = part.get_meta(key)
		result.append({"part": part, "mesh": part.mesh, "material": part.material_override, "weights": weights, "surfaces": materials,
			"metadata": metadata.duplicate(true)})
	return result


func _clothing_signature(parts: Array[MeshInstance3D]) -> String:
	var values: Array = []
	for part in parts:
		values.append([part.transform, part.visible, part.mesh.surface_get_arrays(0), part.mesh.surface_get_blend_shape_arrays(0)])
		for shape in part.mesh.get_blend_shape_count(): values.append([part.mesh.get_blend_shape_name(shape), part.get_blend_shape_value(shape)])
		var keys := part.get_meta_list()
		keys.sort()
		for key in keys: values.append([key, part.get_meta(key)])
		var materials: Array[Material] = [part.material_override]
		for surface in part.mesh.get_surface_count():
			materials.append(part.get_surface_override_material(surface))
			materials.append(part.mesh.surface_get_material(surface))
		for material in materials:
			values.append(material.get_instance_id() if material != null else 0)
			if material is ShaderMaterial:
				for parameter in ["pigment", "tooth", "backface_shade", "cloth_contact_enabled", "cloth_secondary_enabled", "cloth_surface_lift"]:
					values.append(material.get_shader_parameter(parameter))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(values))
	return context.finish().hex_encode()


func _restore(snapshot: Array) -> void:
	for entry: Dictionary in snapshot:
		var part: MeshInstance3D = entry.part
		part.mesh = entry.mesh
		part.material_override = entry.material
		for shape in entry.weights.size(): part.set_blend_shape_value(shape, entry.weights[shape])
		for surface in entry.surfaces.size(): part.set_surface_override_material(surface, entry.surfaces[surface])
		for key in part.get_meta_list():
			if not entry.metadata.has(key): part.remove_meta(key)
		for key in entry.metadata: part.set_meta(key, entry.metadata[key])


func _contact_off(material: Material) -> Material:
	if not material is ShaderMaterial: return material
	var copy := material.duplicate() as ShaderMaterial
	copy.set_shader_parameter("cloth_contact_enabled", false)
	copy.set_shader_parameter("cloth_secondary_enabled", false)
	return copy


func _disable_contact(part: MeshInstance3D) -> void:
	_check(not part.get_meta("is_underbody", false), "Refusing to change body material")
	part.material_override = _contact_off(part.material_override)
	for surface in part.mesh.get_surface_count():
		part.set_surface_override_material(surface, _contact_off(part.get_surface_override_material(surface)))
		part.mesh.surface_set_material(surface, _contact_off(part.mesh.surface_get_material(surface)))
		var material := part.get_active_material(surface) as ShaderMaterial
		if material != null: _check(material.get_shader_parameter("cloth_contact_enabled") == false, "Contact still enabled: " + str(part.name))


func _install_native(skirt: MeshInstance3D, data: Dictionary) -> void:
	var arrays := skirt.mesh.surface_get_arrays(0)
	var shape_id := skirt.find_blend_shape_by_name("RestNap")
	if not _check(shape_id >= 0 and skirt.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED, "Expected normalized skirt RestNap"): return
	var shapes: Array = skirt.mesh.surface_get_blend_shape_arrays(0).duplicate(true)
	shapes[shape_id][Mesh.ARRAY_VERTEX] = _points(data.unskinned_vertices)
	shapes[shape_id][Mesh.ARRAY_NORMAL] = _points(data.unskinned_normals)
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = skirt.mesh.blend_shape_mode
	for i in skirt.mesh.get_blend_shape_count(): mesh.add_blend_shape(skirt.mesh.get_blend_shape_name(i))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	mesh.surface_set_material(0, skirt.mesh.surface_get_material(0))
	skirt.mesh = mesh
	for i in shapes.size(): skirt.set_blend_shape_value(i, 1.0 if i == shape_id else 0.0)


func _geometry_packet(doll: Node3D, parts: Array[MeshInstance3D], bench: Node3D, evaluated_contact := false) -> Dictionary:
	var packet := {"schema_version": 1, "snapshot_only": true,
		"scope": "Actual B capture skinning; contact/secondary disabled on listed cloth; no GPU readback or transition validation",
		"coordinate_space": "Godot skeleton model space", "input_sha256": input_hashes.duplicate(), "parts": []}
	if evaluated_contact:
		packet.scope = "Actual A capture CPU-equivalent shader contact/secondary; no GPU readback or transition validation"
	var selected := parts.duplicate()
	for part: MeshInstance3D in doll.rig.meshes:
		if part.get_meta("is_underbody", false) and part.get_meta("semantic", "") in ["torso", "legL", "legR"]:
			selected.append(part)
	for part: MeshInstance3D in selected:
		_check(part.transform.is_equal_approx(Transform3D.IDENTITY), "Unexpected local transform in geometry export")
		var points: Array = []
		var posed: PackedVector3Array = doll.body_contact.evaluate_vertices(part) if evaluated_contact else doll.rig.deformed_vertices(part)
		for p: Vector3 in posed:
			_check(p.is_finite(), "Nonfinite audit vertex")
			points.append([p.x, p.y, p.z])
		var arrays := part.mesh.surface_get_arrays(0)
		packet.parts.append({"name": str(doll.body_rig.get_path_to(part)),
			"role": "body" if part.get_meta("is_underbody", false) else "cloth",
			"vertices": points, "indices": Array(arrays[Mesh.ARRAY_INDEX])})
	var seat: MeshInstance3D = bench.get_node("StripedLinenSeat/TailoredCushion")
	var transform: Transform3D = doll.rig.skeleton.global_transform.affine_inverse() * seat.global_transform
	var arrays := seat.mesh.surface_get_arrays(0)
	var points: Array = []
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		var p: Vector3 = transform * vertex
		points.append([p.x, p.y, p.z])
	var indices: Array = Array(arrays[Mesh.ARRAY_INDEX]) if arrays[Mesh.ARRAY_INDEX] != null else []
	if indices.is_empty(): indices = range(points.size())
	packet.parts.append({"name": "ActualBenchCushion", "role": "support", "vertices": points, "indices": indices})
	_check(packet.parts.size() == parts.size() + 4, "Expected actual torso, two legs and cushion")
	return packet


func _run() -> void:
	var proof := PROOF
	var layers := false
	var bind_ribbons := false
	var surface_ribbons := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--layers": layers = true
		elif arg == "--bind-ribbons": bind_ribbons = true
		elif arg == "--surface-ribbons": surface_ribbons = true
		elif arg.begins_with("--proof="): proof = arg.trim_prefix("--proof=")
		else: _check(false, "Unknown argument: " + arg)
	_check(not bind_ribbons or layers, "--bind-ribbons requires --layers")
	_check(not surface_ribbons or bind_ribbons, "--surface-ribbons requires --bind-ribbons")
	if not failures.is_empty():
		print("NATIVE_WEARING_CAPTURE FAIL ", failures)
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("NATIVE_WEARING_CAPTURE FAIL: real GPU required")
		quit(1)
		return
	create_timer(120).timeout.connect(func() -> void: quit(1))
	for pipeline in ["res://tests/native_wearing_capture.gd", "res://tests/experiments/native_layer_transfer.gd",
		"res://tests/experiments/wearing_proof_paths.gd"]:
		input_hashes[pipeline] = FileAccess.get_sha256(pipeline)
	var data := _read_dictionary(proof)
	var source_path := _dependency(str(data.get("source", "")), proof, str(data.get("source_sha256", "")))
	if source_path.is_empty():
		print("NATIVE_WEARING_CAPTURE FAIL ", failures)
		quit(1)
		return
	var source := _read_dictionary(source_path)
	_check(not source.is_empty() and data.get("source_sha256", "") == input_hashes.get(source_path, "missing"), "Proof input hash mismatch")
	_source_hashes(source)
	var support_path: String = str(data.get("support_source", "")).strip_edges().replace("\\", "/")
	if not support_path.is_empty():
		support_path = _dependency(support_path, proof, str(data.get("support_sha256", "")))
	var has_support := not support_path.is_empty()
	if has_support:
		var support := _read_dictionary(support_path)
		_check(data.get("support_sha256", "") == input_hashes.get(support_path, "missing"), "Proof support hash mismatch")
		_source_hashes(support)
	_check(source.get("nap_variant", -1) == 0 and source.get("style", -1) == 0, "Capture supports nap0/style0 only")
	if not failures.is_empty():
		print("NATIVE_WEARING_CAPTURE FAIL ", failures)
		quit(1)
		return
	_setup_stage()
	_prepare_rest(true)
	for doll in dolls: doll.nap_pose = 0
	_settle(150)
	_check_supports(true, 0)
	var doll: Node3D = dolls[0]
	var skirt: MeshInstance3D = doll.body_rig.find_child("LongSkirt", true, false)
	var output_name := proof.get_file().get_basename() + ("_layers_proof" if layers else "_proof")
	if bind_ribbons: output_name = proof.get_file().get_basename() + "_bound_layers_proof"
	if surface_ribbons: output_name = proof.get_file().get_basename() + "_surface_layers_proof"
	if not layers:
		for part in doll.rig.meshes:
			if part != skirt and part.get_meta("semantic", "") in ["skirt", "apron"]: part.hide()
	viewport.size = Vector2i(800, 600)
	var actor_before := _actor_signature(doll)
	var clothing: Array[MeshInstance3D] = []
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.get_meta("is_underbody", false): clothing.append(part)
	var original_state := _snapshot(clothing)
	var original_signature := _clothing_signature(clothing)
	var original_restored := false
	var original_sample := _sample(doll, {"name": "native_wearing_A"})
	var bounds: AABB = _bench_bounds(benches[0], original_sample.bounds)
	var transfer_report := {"dependent_count": 0, "transferred_count": 0, "unbound_count": 0, "enabled": layers}
	var modified: Array[MeshInstance3D] = [skirt]
	var original_parts: Array[MeshInstance3D] = [skirt]
	for label in LayerTransfer.RIBBONS:
		var band := doll.body_rig.find_child(label, true, false) as MeshInstance3D
		if band != null: original_parts.append(band)
	var original_packet := _geometry_packet(doll, original_parts, benches[0], true)
	if failures.is_empty():
		if source.has("mesh_seam"):
			var band: MeshInstance3D = doll.body_rig.find_child("WaistRibbon", true, false)
			var lower := INF
			for point: Vector3 in band.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: lower = minf(lower, point.y)
			_check(absf(lower - float(source.mesh_seam.height)) < .000001, "Seam is not the actual waistband boundary")
			var split := SeamSplit.split(skirt.mesh, lower)
			_check(split.error.is_empty(), str(split.error))
			if split.error.is_empty(): skirt.mesh = split.mesh
		_validate_geometry(doll, skirt, source, data)
	if failures.is_empty():
		_install_native(skirt, data)
		if layers:
			var transfer := LayerTransfer.new()
			transfer.surface_follow = surface_ribbons
			if bind_ribbons: transfer.derive_ribbons(doll, skirt)
			transfer_report.merge(transfer.run(doll, skirt), true)
			modified.append_array(transfer.changed)
			for failure: String in transfer.failures: _check(false, failure)
		for part in modified: _disable_contact(part)
		_check(_actor_signature(doll) == actor_before, "Body, bone pose/rest or body material changed")
	var native_state := _snapshot(clothing)
	var audit_packet := _geometry_packet(doll, modified, benches[0])
	var native_sample := _sample(doll, {"name": "native_wearing_B"})
	bounds = bounds.merge(_bench_bounds(benches[0], native_sample.bounds))
	var sheet := Image.create_empty(1600, 1200, false, Image.FORMAT_RGB8)
	var cells: Array = []
	for version in 2:
		if not failures.is_empty(): break
		_restore(original_state if version == 0 else native_state)
		_check(_actor_signature(doll) == actor_before, "Actor invariant changed between panels")
		if version == 0:
			original_restored = _clothing_signature(clothing) == original_signature
			_check(original_restored, "A standing/morph arrays, design metadata or materials changed")
		for row in 2:
			caption.text = ("A: Current contact" if version == 0 else "B: Native cloth experiment") + (" | layers visible" if layers else " | trim excluded")
			_frame(bounds, ["top", "side"][row])
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var rendered := viewport.get_texture().get_image()
			var pixels := _image_stats(rendered)
			rendered.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(rendered, Rect2i(Vector2i.ZERO, viewport.size), Vector2i(version * 800, row * 600))
			cells.append({"variant": "A" if version == 0 else "B", "view": ["top", "side"][row], "pixels": pixels})
	for path: String in input_hashes: _check(FileAccess.get_sha256(path) == input_hashes[path], "Input changed during capture: " + path)
	_check(cells.size() == 4, "Incomplete GPU comparison")
	if failures.is_empty(): _check(sheet.save_png(OUTPUT + output_name + ".png") == OK, "Capture write failed")
	if failures.is_empty(): _write_json(output_name + "_geometry.json", audit_packet)
	if failures.is_empty(): _write_json(output_name + "_original_geometry.json", original_packet)
	_write_json(output_name + "_manifest.json", {"experimental_not_accepted": true,
		"proof": proof, "gpu": RenderingServer.get_video_adapter_name(), "failures": failures,
		"support_input": {"present": has_support, "path": support_path},
		"snapshot_only": true, "snapshot_frame": 180, "transition_validated": false,
		"resolved_references": resolved_references, "project_root": ProjectSettings.globalize_path("res://"),
		"style": 0, "nap_variant": 0, "layers": transfer_report, "bind_ribbons": bind_ribbons, "cells": cells,
		"geometry_for_independent_audit": OUTPUT + output_name + "_geometry.json",
		"original_A_restored_exactly": original_restored,
		"source_vertex_sha256": source.base_skirt.vertex_sha256, "input_sha256": input_hashes,
		"proof_inverse_error": proof_inverse_error, "body_pose_rest_material_unchanged": _actor_signature(doll) == actor_before,
		"shared_camera_bounds": {"position": [bounds.position.x, bounds.position.y, bounds.position.z], "size": [bounds.size.x, bounds.size.y, bounds.size.z]},
		"contact_disabled_in_B": modified.map(func(part: MeshInstance3D): return str(doll.body_rig.get_path_to(part))),
		"scope": "style0/nap0 final-frame snapshot only; frozen supported actor; no runtime integration or transition-success claim; collision/containment NOT validated for transferred or unbound trims",
		"phase_note": "Capture retains settled actor breathing phase; proof inverse validation uses exported frame180 matrices"})
	viewport.free()
	print("NATIVE_WEARING_CAPTURE %s layers=%d unbound=%d output=%s failures=%s" % [
		"PASS" if failures.is_empty() else "FAIL", transfer_report.transferred_count, transfer_report.unbound_count, output_name, str(failures)])
	quit(0 if failures.is_empty() else 1)
