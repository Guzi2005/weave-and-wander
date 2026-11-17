extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const Bench = preload("res://components/rest_bench.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bench := Bench.new()
	root.add_child(bench)
	bench.set_process(false)
	var doll := Doll.new()
	root.add_child(doll)
	doll.configure({"outfit": 0, "hair": 0, "skin": 0, "palette": 0})
	doll.process_mode = Node.PROCESS_MODE_DISABLED
	bench.reserve(doll, true)
	bench.support_actor(doll)
	doll.nap_pose = 0
	doll._moving = false
	for i in 150: doll.simulate(1.0 / 60.0, 1)
	var seat: MeshInstance3D = bench.get_node("StripedLinenSeat/TailoredCushion")
	var transform: Transform3D = doll.rig.skeleton.global_transform.affine_inverse() * seat.global_transform
	var normal_matrix := transform.basis.inverse().transposed()
	var arrays := seat.mesh.surface_get_arrays(0)
	var vertices: Array = []
	var normals: Array = []
	var bounds := AABB()
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var p: Vector3 = transform * arrays[Mesh.ARRAY_VERTEX][i]
		var n: Vector3 = (normal_matrix * arrays[Mesh.ARRAY_NORMAL][i]).normalized()
		assert(p.is_finite() and n.is_finite())
		vertices.append([p.x, p.y, p.z])
		normals.append([n.x, n.y, n.z])
		bounds = AABB(p, Vector3.ZERO) if i == 0 else bounds.expand(p)
	var indices: Array = Array(arrays[Mesh.ARRAY_INDEX]) if arrays[Mesh.ARRAY_INDEX] != null else []
	if indices.is_empty(): indices = range(vertices.size())
	assert(indices.size() % 3 == 0 and doll._rest_blend > .999)
	var support: Node3D = doll.rest_support.get_ref()
	var hip: Vector3 = doll.rig.skeleton.to_global(doll.rig.global_pose(doll.rig.bones.Hips).origin)
	assert(hip.distance_to(support.global_position) < .005)
	var output := {"schema_version": 1, "scope": "Actual cushion at fully supported nap0; static final-pose support, not transition trajectory",
		"source_sha256": {"res://components/rest_bench.gd": FileAccess.get_sha256("res://components/rest_bench.gd"),
			"res://components/upholstered_pad.gd": FileAccess.get_sha256("res://components/upholstered_pad.gd")},
		"name": "ActualBenchCushion", "vertices": vertices, "normals": normals, "indices": indices,
		"coordinate_space": "Godot skeleton model space; matches wearing simulation final pose"}
	var file := FileAccess.open("res://captures/wearing_bench_support.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output))
	file.flush()
	assert(file.get_error() == OK)
	file.close()
	print("BENCH_CLOTH_SUPPORT PASS vertices=", vertices.size(), " bounds=", bounds)
	doll.free()
	bench.free()
	quit(0)
