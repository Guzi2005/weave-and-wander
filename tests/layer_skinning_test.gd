extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
# ArrayMesh stores each of the four weights with 16-bit precision.
const WEIGHT_EPSILON := 4.0 / 65535.0
var failures: Array[String] = []
var checked_vertices := 0
var checked_poses := 0
var minimum_gap := INF
var maximum_gap_change := 0.0
var current_pose := 0
var posed_cache := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	for outfit in [1, 2]:
		var doll := Doll.new()
		doll.configure({"outfit": outfit})
		root.add_child(doll)
		var layers: Array[MeshInstance3D] = []
		for instance in doll.rig.meshes:
			if instance.has_meta("skin_layer_sources"):
				layers.append(instance)
		# Validate required parts, not a historical total that excluded new buttons.
		var names: Array[String] = []
		for layer in layers: names.append(str(layer.name))
		var required := ["Apron", "Pocket", "ApronStrapCrossL", "ApronStrapCrossR", "ApronTie"] if outfit == 1 else ["OpenWaistcoat"]
		for label in required:
			_check(label in names, "Missing clothing surface binding: " + label)
		for layer in layers:
			_check(layer.get_meta("skin_layer_unmapped") == 0, "A clothing layer has unbound vertices.")
			_check_weights(layer)
		for pose in 128:
			current_pose = pose
			doll.rig.animate(TAU * pose / 24.0, 1.0 if pose < 24 else 0.0,
				"idle" if pose < 24 else "sewing", pose * 0.2)
			if pose >= 32:
				doll.rig._rotate("Spine", Vector3(0.1, (pose - 33.5) * 0.04, 0.025))
				doll.rig.skeleton.force_update_all_bone_transforms()
			if pose >= 36:
				var weights := Vector4(1,0,0,0)
				if pose >= 48:
					var pair := (pose-48)/5
					var start := int(pair)/4
					var target := int(pair)%4
					var amount := smoothstep(0,1,float((pose-48)%5)/4.0)
					weights = Vector4.ZERO
					weights[start] = 1.0-amount
					weights[target] += amount
				doll.rig.pose_rest("sit" if pose < 48 else "nap",1.0,pose*.7,weights)
			checked_poses += 1
			doll.body_contact.update()
			posed_cache.clear()
			for layer in layers:
				_check_layer_pose(doll, layer)
		doll.free()
	print("LAYER_SKIN_CHECK poses=", checked_poses, " vertices=", checked_vertices,
		" min_gap=", minimum_gap, " max_gap_change=", maximum_gap_change, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_weights(layer: MeshInstance3D) -> void:
	var arrays := layer.mesh.surface_get_arrays(0)
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var triangles: PackedInt32Array = layer.get_meta("skin_layer_triangles")
	var barycentric: PackedVector3Array = layer.get_meta("skin_layer_barycentric")
	var source_ids: PackedInt32Array = layer.get_meta("skin_layer_source_index")
	var sources: Array = []
	for path in layer.get_meta("skin_layer_sources"):
		sources.append(layer.get_node(NodePath(path)).mesh.surface_get_arrays(0))
	for i in barycentric.size():
		var expected: Dictionary = {}
		var source: Array = sources[source_ids[i]]
		for corner in 3:
			for slot in 4:
				var index := triangles[i * 3 + corner] * 4 + slot
				var bone: int = source[Mesh.ARRAY_BONES][index]
				expected[bone] = expected.get(bone, 0.0) + source[Mesh.ARRAY_WEIGHTS][index] * barycentric[i][corner]
		var actual: Dictionary = {}
		var total := 0.0
		for slot in 4:
			var value := weights[i * 4 + slot]
			var bone := ids[i * 4 + slot]
			actual[bone] = actual.get(bone, 0.0) + value
			total += value
			_check(value >= 0 and is_finite(value), "Invalid clothing skin weight.")
		_check(absf(total - 1.0) < WEIGHT_EPSILON, "Clothing weights are not normalized.")
		for bone in expected:
			_check(absf(expected[bone] - actual.get(bone, 0.0)) < WEIGHT_EPSILON, "Layer weights differ from the actual underlying surface.")


func _check_layer_pose(doll: VolumeDoll, layer: MeshInstance3D) -> void:
	var rest: PackedVector3Array = layer.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var posed := _evaluated(doll, layer)
	var triangles: PackedInt32Array = layer.get_meta("skin_layer_triangles")
	var barycentric: PackedVector3Array = layer.get_meta("skin_layer_barycentric")
	var source_ids: PackedInt32Array = layer.get_meta("skin_layer_source_index")
	var sources: Array = []
	for path in layer.get_meta("skin_layer_sources"):
		var source := layer.get_node(NodePath(path)) as MeshInstance3D
		sources.append([source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], _evaluated(doll, source)])
	var contact_material := layer.material_override as ShaderMaterial
	var fabric: bool = contact_material != null and contact_material.get_shader_parameter("cloth_contact_enabled") == true
	for i in rest.size():
		var source: Array = sources[source_ids[i]]
		var contact := Vector3.ZERO
		var rest_contact := Vector3.ZERO
		for corner in 3:
			var index := triangles[i * 3 + corner]
			contact += source[1][index] * barycentric[i][corner]
			rest_contact += source[0][index] * barycentric[i][corner]
		var a: Vector3 = source[1][triangles[i * 3]]
		var b: Vector3 = source[1][triangles[i * 3 + 1]]
		var c: Vector3 = source[1][triangles[i * 3 + 2]]
		var normal := (c - a).cross(b - a).normalized()
		var gap := (posed[i] - contact).dot(normal)
		if fabric and gap < -.001 and not failures.has("A clothing layer crossed its underlying surface: " + str(layer.name)):
			print("LAYER_CONTACT pose=",current_pose," layer=",layer.name," vertex=",i," gap=",gap," rest=",rest[i])
		minimum_gap = minf(minimum_gap, gap)
		maximum_gap_change = maxf(maximum_gap_change, absf(posed[i].distance_to(contact) - rest[i].distance_to(rest_contact)))
		_check(posed[i].is_finite(), "Layer animation produced non-finite vertices.")
		# Rigid button undersides intentionally anchor into cloth; they are not fabric.
		if fabric: _check(gap > -0.001, "A clothing layer crossed its underlying surface: " + str(layer.name))
		checked_vertices += 1


func _evaluated(doll: Node3D, part: MeshInstance3D) -> PackedVector3Array:
	if not posed_cache.has(part): posed_cache[part] = doll.body_contact.evaluate_vertices(part)
	return posed_cache[part]
