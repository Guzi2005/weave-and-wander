extends SceneTree

const Transfer = preload("res://tests/experiments/native_layer_transfer.gd")
var checks := 0
var failures: Array[String] = []


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func _solve(directions: PackedVector3Array, gaps: PackedFloat32Array, skin := Transform3D.IDENTITY) -> Dictionary:
	var count := directions.size()
	var anchors := PackedVector3Array()
	anchors.resize(count)
	anchors.fill(Vector3(.2, .3, .4))
	var rest := PackedVector3Array()
	rest.resize(count)
	rest.fill(Vector3(.1, .6, .2))
	var posed := anchors.duplicate()
	var normals := PackedVector3Array()
	normals.resize(count)
	var skins: Array[Transform3D] = []
	for i in count: skins.append(skin)
	var transfer := Transfer.new()
	transfer.surface_clearance = .004
	transfer._surface_offsets(anchors, directions, gaps, rest, posed, normals, skins, "test")
	return {"transfer": transfer, "points": posed, "normals": normals, "anchors": anchors}


func _initialize() -> void:
	_test_morph_inheritance()
	var flat := _solve(PackedVector3Array([Vector3.UP, Vector3.UP]), PackedFloat32Array([.004, .004]))
	_check(flat.transfer.failures.is_empty(), "Flat surface failed")
	_check(flat.points[0].distance_to(flat.anchors[0] + Vector3.UP * .004) < .0000001, "Flat thickness changed")
	_check(flat.points[0] == flat.points[1], "Flat seam split")
	var corner := _solve(PackedVector3Array([Vector3.UP, Vector3.RIGHT]), PackedFloat32Array([.004, .008]))
	_check(corner.transfer.failures.is_empty(), "Right-angle seam failed")
	_check(corner.points[0].distance_to(corner.anchors[0] + Vector3(.008, .004, 0)) < .0000001, "Incident plane clearance not retained")
	_check(corner.points[0] == corner.points[1], "Corner seam split")
	_check(corner.transfer.surface_records[0].max_plane_residual < .000002, "Unresolved corner clearance")
	var basis := Basis(Vector3.FORWARD, .6).scaled(Vector3(.8, 1.2, .9))
	var skin := Transform3D(basis, Vector3.ZERO)
	var oblique := _solve(PackedVector3Array([Vector3.UP, Vector3(1, 1, 0).normalized()]), PackedFloat32Array([.004, .006]), skin)
	_check(oblique.transfer.failures.is_empty(), "Oblique seam failed")
	var delta: Vector3 = oblique.points[0] - oblique.anchors[0]
	_check(delta.dot(Vector3.UP) >= .004 - .0000001, "Oblique first constraint violated")
	_check(delta.dot(Vector3(1, 1, 0).normalized()) >= .006 - .0000001, "Oblique second constraint violated")
	_check((basis * oblique.normals[0]).normalized().distance_to(delta.normalized()) < .000001, "Skinned normal differs from target")
	var unrelated := _solve(PackedVector3Array([Vector3.UP]), PackedFloat32Array([-1]))
	_check(unrelated.points == unrelated.anchors, "Unrelated source moved")
	var impossible := _solve(PackedVector3Array([Vector3.UP, Vector3.DOWN]), PackedFloat32Array([.004, .004]))
	_check(not impossible.transfer.failures.is_empty(), "Opposing constraints silently accepted")
	var oversized := _solve(PackedVector3Array([Vector3.UP]), PackedFloat32Array([.08]))
	_check(not oversized.transfer.failures.is_empty(), "Offset beyond geometry guard silently accepted")
	print("NATIVE_LAYER_SURFACE %s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	quit(0 if failures.is_empty() else 1)


func _test_morph_inheritance() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	var targets: Array = []
	for i in 5:
		mesh.add_blend_shape("Pose%d" % i)
		var target := []
		target.resize(Mesh.ARRAY_MAX)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		for j in points.size(): points[j] += Vector3(0, 0, i * .1)
		target[Mesh.ARRAY_VERTEX] = points
		target[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL].duplicate()
		targets.append(target)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, targets)
	var transfer := Transfer.new()
	var shapes := transfer._derived_shapes(mesh, PackedVector3Array([Vector3(.3, .5, .02)]),
		PackedVector3Array([Vector3.BACK]), PackedInt32Array([0, 1, 2]), PackedVector3Array([Vector3(.2, .3, .5)]))
	_check(transfer.failures.is_empty(), "Source morph inheritance failed")
	_check(shapes.size() == 5, "Derived layer dropped source pose channels")
	for i in shapes.size():
		_check(shapes[i][Mesh.ARRAY_VERTEX][0].distance_to(Vector3(.3, .5, .02 + i * .1)) < .000001, "Derived source pose offset changed")
		_check(shapes[i][Mesh.ARRAY_NORMAL][0].distance_to(Vector3.BACK) < .000001, "Derived source pose normal changed")
