extends SceneTree
## Verifies the book-form wrapped fabric: a continuous rounded ArrayMesh wraps
## the board's x-z perimeter, while both exposed ends carry one continuous
## spiral whose pitch and turn count come from cloth gauge and metres left.

const Package := preload("res://components/material_package.gd")
const Wrap := preload("res://components/fabric_wrap_mesh.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var source := {"id": "wrapped", "meters": 8.0, "capacity_m": 10.0, "thickness_m": 0.001, "width_m": 1.4, "pigment": Color("779ab1"), "pattern_code": 1, "material": "cotton"}
	var stock_snapshot := source.duplicate(true)
	var package := Package.new()
	root.add_child(package)
	package.configure(source, "book")

	var board := _board(package)
	check(board != null, "book form keeps a Board core piece")
	check(board != null and board.mesh is BoxMesh, "Board stays a BoxMesh")
	check(board != null and (board.mesh as BoxMesh).size.is_equal_approx(Vector3(0.016, 0.84, 0.46)), "Board stays 0.016 x 0.84 x 0.46")
	check(package.shell != null and package.shell.mesh is ArrayMesh, "wrapped sleeve is an ArrayMesh, not BoxMesh")
	if board == null or not (package.shell.mesh is ArrayMesh):
		_report()
		return

	var board_box := _package_bounds(package, board)
	check(is_equal_approx(board_box.size.y, 0.84), "board height stays 0.84 (got %.4f)" % board_box.size.y)
	var core_geometry := _geometry(package.core)
	var thicknesses: Array[float] = []
	var layer_counts: Array[int] = []
	for amount in [8.0, 4.0, 0.1]:
		package.set_quantity(amount)
		check(package.shell.visible, "sleeve visible at %.1f m" % amount)
		var cloth := _package_bounds(package, package.shell)
		check(cloth.size.x > board_box.size.x + 0.0005, "cloth covers both board x faces at %.1f m (cloth %.4f vs board %.4f)" % [amount, cloth.size.x, board_box.size.x])
		check(cloth.size.z > board_box.size.z + 0.0005, "cloth overhangs both board z edges at %.1f m (cloth %.4f vs board %.4f)" % [amount, cloth.size.z, board_box.size.z])
		check(cloth.size.y < board_box.size.y - 0.0005, "cardboard only exposed at top and bottom at %.1f m (cloth y %.4f vs board y %.4f)" % [amount, cloth.size.y, board_box.size.y])
		check(absf(cloth.get_center().y - 0.42) < 0.02, "sleeve stays centered at y=0.42 (got %.4f) at %.1f m" % [cloth.get_center().y, amount])
		# Front spine: a ray down -z at chest height must strike cloth before board.
		var cloth_front := _nearest_hit(package, package.shell, Vector3(0, 0.42, 1.0), Vector3(0, 0.42, -1.0))
		var board_front := _nearest_hit(package, board, Vector3(0, 0.42, 1.0), Vector3(0, 0.42, -1.0))
		check(cloth_front < board_front, "front spine shows no cardboard at %.1f m (cloth hit %.4f, board hit %.4f)" % [amount, cloth_front, board_front])
		# Both x faces: rays at mid-depth must strike cloth before board.
		for side in [-1.0, 1.0]:
			var cloth_hit := _nearest_hit(package, package.shell, Vector3(side, 0.42, 0.0), Vector3(-side, 0.42, 0.0))
			var board_hit := _nearest_hit(package, board, Vector3(side, 0.42, 0.0), Vector3(-side, 0.42, 0.0))
			check(cloth_hit < board_hit, "x face %+.0f shows no cardboard at %.1f m (cloth hit %.4f, board hit %.4f)" % [side, amount, cloth_hit, board_hit])
		check(_geometry(package.core) == core_geometry, "core geometry unchanged at %.1f m" % amount)
		thicknesses.append(cloth.size.x)
		layer_counts.append(int(package.get_meta("winding_layers", 0)))
	check(thicknesses.size() == 3 and thicknesses[0] > thicknesses[1] and thicknesses[1] > thicknesses[2], "sleeve thickness shrinks monotonically: 8m %.4f > 4m %.4f > 0.1m %.4f" % thicknesses)
	check(layer_counts[0] > layer_counts[1] and layer_counts[1] > layer_counts[2], "layer count drops with quantity: 8m %d > 4m %d > 0.1m %d" % layer_counts)

	package.set_quantity(8.0)
	var expected_pitch := Wrap.layer_pitch(0.001, 1.4)
	check(is_equal_approx(float(package.get_meta("layer_pitch_m", 0.0)), expected_pitch), "pitch follows thickness_m and folded width / .74")
	check(is_equal_approx(float(package.get_meta("cloth_thickness_m", 0.0)), Wrap.wrapped_thickness(8.0, 0.001, 1.4)), "thickness derives from metres and gauge")
	check(int(package.get_meta("winding_layers", 0)) == Wrap.winding_layers(8.0), "layer count derives from metres and wrap length")
	var full_cloth := _package_bounds(package, package.shell)
	var full_layers := int(package.get_meta("winding_layers", 0))
	var full_thickness := float(package.get_meta("cloth_thickness_m", 0.0))
	var ends := _end_meshes(package)
	check(ends.size() == 2, "both exposed ends carry a spiral trace (got %d)" % ends.size())
	for end in ends:
		check(end.mesh is ArrayMesh, "end trace is an ArrayMesh")
		check(bool(end.mesh.get_meta("continuous_spiral", false)), "end trace is marked continuous")
		check(int(end.mesh.get_meta("spiral_turns", 0)) == full_layers, "end spiral turns match the layer count")
		check(end.mesh.get_surface_count() == 1, "end spiral is one continuous surface")
		check(_vertex_count(end.mesh) > 0, "end spiral has vertices")
		_check_mesh_arrays(end.mesh, "end spiral")
		var end_box: AABB = end.mesh.get_aabb()
		check(end_box.size.x > board_box.size.x + 0.0005, "end spiral clears the board x faces")
		check(end_box.size.x <= full_cloth.size.x + 0.001, "end spiral stays within the cloth x bounds")
		check(end_box.size.z > board_box.size.z + 0.0005, "end spiral clears the board z edges")
		check(end_box.size.z <= full_cloth.size.z + 0.001, "end spiral stays within the cloth z bounds")
	check(_triangle_count(package) < 4000, "book wrapping stays within the triangle budget (got %d)" % _triangle_count(package))
	var full_vertices := _vertex_count(ends[0].mesh) if not ends.is_empty() else 0

	package.set_quantity(4.0)
	var half_layers := int(package.get_meta("winding_layers", 0))
	var half_thickness := float(package.get_meta("cloth_thickness_m", 0.0))
	var half_ends := _end_meshes(package)
	var half_vertices := _vertex_count(half_ends[0].mesh) if not half_ends.is_empty() else 0
	check(half_layers < full_layers, "reducing quantity reduces layer count (%d -> %d)" % [full_layers, half_layers])
	check(half_thickness < full_thickness, "reducing quantity reduces thickness (%.4f -> %.4f)" % [full_thickness, half_thickness])
	check(half_vertices < full_vertices, "reducing quantity removes spiral turns (%d -> %d vertices)" % [full_vertices, half_vertices])
	check(_geometry(package.core) == core_geometry, "core geometry unchanged after layer-count reduction")

	package.set_quantity(0.1)
	var tiny_cloth := _package_bounds(package, package.shell)
	check(tiny_cloth.size.x > board_box.size.x and tiny_cloth.size.z > board_box.size.z, "minimal nonempty wrapping still covers the board")
	check(int(package.get_meta("winding_layers", 0)) == 1, "minimal nonempty wrapping keeps one layer")

	package.set_quantity(0.0)
	check(not package.shell.visible, "empty bolt hides the sleeve")
	check(int(package.get_meta("winding_layers", 0)) == 0, "empty bolt has no winding layers")
	check(package.core.visible and board.visible, "cardboard core stays visible when empty")
	check(_geometry(package.core) == core_geometry, "core geometry unchanged when emptied")
	check(_same_stock(package.data, source) and source.meters == 8.0, "presentation never mutates the ledger record")
	source["identity_probe"] = 7
	check(package.data.get("identity_probe", -1) == 7, "package keeps the same dictionary record (identity)")
	source.erase("identity_probe")

	_check_gauge_pair(source)
	_check_sleeve_arrays(package)
	check(_same_stock(source, stock_snapshot), "stock dictionary and its fields stay unmodified")
	package.free()
	_report()


func _report() -> void:
	print("WRAPPED_FABRIC_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_gauge_pair(source: Dictionary) -> void:
	var thin_data := source.duplicate(true)
	thin_data["meters"] = 4.0
	thin_data["capacity_m"] = 8.0
	thin_data["thickness_m"] = 0.0005
	thin_data["width_m"] = 1.4
	var thick_data := thin_data.duplicate(true)
	thick_data["thickness_m"] = 0.0025
	var thin_snapshot := thin_data.duplicate(true)
	var thick_snapshot := thick_data.duplicate(true)
	var thin := Package.new()
	var thick := Package.new()
	root.add_child(thin)
	root.add_child(thick)
	thin.configure(thin_data, "book")
	thick.configure(thick_data, "book")
	thin.set_quantity(4.0)
	thick.set_quantity(4.0)
	var thin_box := _package_bounds(thin, thin.shell)
	var thick_box := _package_bounds(thick, thick.shell)
	check(thick_box.size.x > thin_box.size.x + 0.006, "thick cloth is visibly thicker at the same 4 m (thin %.4f vs thick %.4f)" % [thin_box.size.x, thick_box.size.x])
	check(thin_box.size.x > 0.0165 and thick_box.size.x > 0.0165, "both gauges cover the 0.016 m board")
	var thin_pitch := float(thin.get_meta("layer_pitch_m", 0.0))
	var thick_pitch := float(thick.get_meta("layer_pitch_m", 0.0))
	check(thick_pitch > thin_pitch * 2.0, "thick cloth has a larger layer pitch (%.4f vs %.4f)" % [thin_pitch, thick_pitch])
	check(int(thin.get_meta("winding_layers", 0)) == int(thick.get_meta("winding_layers", 0)), "same metres means the same wrap count regardless of gauge")
	var roomy_data := thin_data.duplicate(true)
	roomy_data["capacity_m"] = 16.0
	var roomy_snapshot := roomy_data.duplicate(true)
	var roomy := Package.new()
	root.add_child(roomy)
	roomy.configure(roomy_data, "book")
	roomy.set_quantity(4.0)
	var roomy_box := _package_bounds(roomy, roomy.shell)
	check(is_equal_approx(roomy_box.size.x, thin_box.size.x), "capacity fraction does not set thickness (8 m vs 16 m capacity)")
	check(int(roomy.get_meta("winding_layers", 0)) == int(thin.get_meta("winding_layers", 0)), "capacity fraction does not set layer count")
	check(_same_stock(roomy_data, roomy_snapshot), "capacity variation leaves its stock dictionary untouched")
	roomy.free()
	var thin_ends := _end_meshes(thin)
	var thick_ends := _end_meshes(thick)
	var thin_end_box: AABB = thin_ends[0].mesh.get_aabb() if not thin_ends.is_empty() else AABB()
	var thick_end_box: AABB = thick_ends[0].mesh.get_aabb() if not thick_ends.is_empty() else AABB()
	check(thick_end_box.size.x > thin_end_box.size.x + 0.006, "thick cloth spiral spans a thicker end stack (thin %.4f vs thick %.4f)" % [thin_end_box.size.x, thick_end_box.size.x])
	check(_same_stock(thin_data, thin_snapshot) and _same_stock(thick_data, thick_snapshot), "gauge/layer wrapping never mutates stock dictionaries")
	thin.free()
	thick.free()


func _board(package: Node3D) -> MeshInstance3D:
	for part in package.core.find_children("*", "MeshInstance3D", true, false):
		if part.name == "Board":
			return part
	return null


func _end_meshes(package: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for part in package.find_children("WoundClothEnd*", "MeshInstance3D", true, false):
		result.append(part as MeshInstance3D)
	return result


func _same_stock(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or typeof(a[key]) != typeof(b[key]):
			return false
		if a[key] != b[key]:
			return false
	return true


func _package_bounds(package: Node3D, part: MeshInstance3D) -> AABB:
	var relative: Transform3D = package.global_transform.affine_inverse() * part.global_transform
	return relative * part.mesh.get_aabb()


func _geometry(node: Node3D) -> Array:
	var result: Array = []
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		result.append([mesh.transform, mesh.mesh.get_aabb()])
	return result


func _vertex_count(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += vertices.size()
	return count


func _triangle_count(node: Node3D) -> int:
	var count := 0
	for part in node.find_children("*", "MeshInstance3D", true, false):
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			count += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
	return count


func _nearest_hit(package: Node3D, part: MeshInstance3D, from: Vector3, to: Vector3) -> float:
	var relative: Transform3D = package.global_transform.affine_inverse() * part.global_transform
	var best := INF
	var mesh := part.mesh
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var triangle_count: int = int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
		for triangle in triangle_count:
			var a: Vector3
			var b: Vector3
			var c: Vector3
			if indices.is_empty():
				a = vertices[triangle * 3]
				b = vertices[triangle * 3 + 1]
				c = vertices[triangle * 3 + 2]
			else:
				a = vertices[indices[triangle * 3]]
				b = vertices[indices[triangle * 3 + 1]]
				c = vertices[indices[triangle * 3 + 2]]
			var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, relative * a, relative * b, relative * c)
			if hit is Vector3:
				best = minf(best, from.distance_to(hit))
	return best


func _check_sleeve_arrays(package: Node3D) -> void:
	_check_mesh_arrays(package.shell.mesh, "sleeve")


func _check_mesh_arrays(mesh: Mesh, label: String) -> void:
	var nan_vertices := 0
	var bad_normals := 0
	var normal_total := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not (is_finite(vertex.x) and is_finite(vertex.y) and is_finite(vertex.z)):
				nan_vertices += 1
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			normal_total += normals.size()
			for normal in normals:
				if not (is_finite(normal.x) and is_finite(normal.y) and is_finite(normal.z)) or absf(normal.length() - 1.0) > 0.01:
					bad_normals += 1
	check(nan_vertices == 0, "%s has %d non-finite vertices" % [label, nan_vertices])
	check(normal_total == 0 or bad_normals == 0, "%s has %d/%d non-finite or non-unit normals" % [label, bad_normals, normal_total])
