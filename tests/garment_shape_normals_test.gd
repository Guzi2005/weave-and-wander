extends SceneTree

const Fit = preload("res://scripts/accepted_body_fit.gd")
var checks := 0
var failures: Array[String] = []


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	var before := PackedVector3Array([
		Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3.ZERO,
		Vector3.ZERO, Vector3(0, 1, 0), Vector3(1, 0, 0)])
	var normals := PackedVector3Array()
	normals.resize(before.size())
	normals.fill(Vector3.FORWARD)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = before.duplicate()
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 3, 4, 5])
	var fit := Fit.new()
	check(fit._normals(arrays, before) == normals, "Unchanged cloth shading changed")
	arrays[Mesh.ARRAY_VERTEX][0].z = .3
	var result: PackedVector3Array = fit._normals(arrays, before)
	check(result[2].is_equal_approx(result[3]), "Smooth seam normals differ at bottom")
	check(result[1].is_equal_approx(result[4]), "Smooth seam normals differ at top")
	check(not result[2].is_equal_approx(normals[2]), "Changed normal was not recalculated")
	check(result[5] == normals[5], "Unchanged non-seam vertex was modified")
	for n in result: check(n.is_finite() and absf(n.length() - 1) < .00001, "Invalid smooth normal")
	for i in [3, 4, 5]: normals[i] = Vector3.UP
	arrays[Mesh.ARRAY_NORMAL] = normals
	result = fit._normals(arrays, before)
	check(result[3] == Vector3.UP and result[4] == Vector3.UP, "Authored hard edge was smoothed")
	check(not result[2].is_equal_approx(result[3]), "Hard seam normal groups merged")
	print("GARMENT_SHAPE_NORMALS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
