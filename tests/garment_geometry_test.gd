extends SceneTree

const Doll = preload("res://scripts/catalog_doll.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const Geometry = preload("res://scripts/garment_geometry.gd")
const WEIGHT_EPSILON := 0.001
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	_check_trousers()
	_check_standalone_waistcoat()
	print("GARMENT_GEOMETRY_TEST failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_trousers() -> void:
	var doll := Doll.new()
	doll.catalog_style = 4
	doll.configure({"outfit": 2, "palette": 0})
	root.add_child(doll)
	var seat: MeshInstance3D
	var legs: Array[MeshInstance3D] = []
	for part in doll.rig.meshes:
		if part.name == "TrouserWaistband":
			seat = part
		elif part.name == "Trouser":
			legs.append(part)
	check(seat != null, "catalog trousers have no seat/waist shell")
	check(legs.size() == 2, "catalog trousers must keep two leg meshes")
	if seat == null or legs.size() != 2:
		doll.free()
		return
	check(seat.get_meta("semantic") == "torso", "trouser seat must follow the torso/Hips semantic")
	check(Definition.part_slot(seat) == "bottom", "trouser seat must stay in the bottom garment slot")
	for leg in legs:
		var side := "L" if leg.get_meta("semantic") == "legL" else "R"
		check(leg.get_meta("semantic") in ["legL", "legR"], "trouser leg lost its leg semantic")
		check(Definition.part_slot(leg) == "bottom", "trouser leg must stay in the bottom garment slot")
		var topology := _topology(leg.mesh)
		check(topology["degenerate"] == 0, "trouser leg has degenerate triangles")
		check(topology["components"] == 1, "trouser leg must be one connected mesh")
		var loops := _boundary_loops(leg.mesh)
		var hem := loops.filter(func(loop: Array) -> bool: return loop[0] < 0.25)
		var top := loops.filter(func(loop: Array) -> bool: return loop[0] > 1.0)
		check(hem.size() == 1, "trouser leg must have exactly one open hem loop")
		check(top.size() == 1, "trouser leg top must stay an open ring inside the seat")
		_check_leg_skinning(doll, leg, side)
	var seat_topology := _topology(seat.mesh)
	check(seat_topology["degenerate"] == 0, "trouser seat has degenerate triangles")
	check(seat_topology["components"] == 1, "trouser seat/crotch/waist must be one connected mesh")
	var seat_loops := _boundary_loops(seat.mesh)
	check(seat_loops.size() == 1, "trouser seat must have a single waist opening, no cracks")
	check(not seat_loops.is_empty() and seat_loops[0][0] > 1.09, "trouser waist opening must sit at the waistband")
	check(seat_loops.is_empty() or seat_loops[0][1] > 24, "trouser waist opening must span the full waist")
	# The legs emerge from inside the seat: their top rings stay within the seat silhouette.
	var seat_vertices: PackedVector3Array = seat.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for leg in legs:
		var leg_vertices: PackedVector3Array = leg.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for point in leg_vertices:
			if point.y < 1.05:
				continue
			var radius_x := 0.0
			var radius_z := 0.0
			for ring_point in seat_vertices:
				if absf(ring_point.y - point.y) < 0.03:
					radius_x = maxf(radius_x, absf(ring_point.x))
					radius_z = maxf(radius_z, absf(ring_point.z))
			check(radius_x > 0.0, "trouser leg top has no seat ring beside it")
			if radius_x > 0.0 and radius_z > 0.0:
				var inside := pow(point.x / radius_x, 2) + pow(point.z / radius_z, 2)
				check(inside < 1.02, "trouser leg top escapes the seat shell")
	# Skinning must survive a full walk cycle without exploding.
	for pose in 8:
		doll.rig.animate(TAU * pose / 8.0, 1.0, "idle", pose * 0.3)
		check(doll.rig.deformed_vertices(seat).is_empty() == false, "seat deformation failed")
		for leg in legs:
			for point in doll.rig.deformed_vertices(leg):
				check(point.is_finite(), "trouser walk pose produced non-finite vertices")
	doll.free()


func _check_leg_skinning(doll: VolumeDoll, leg: MeshInstance3D, side: String) -> void:
	var arrays := leg.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var thigh: int = doll.rig.bones["Thigh" + side]
	var shin: int = doll.rig.bones["Shin" + side]
	for i in vertices.size():
		var total := 0.0
		var thigh_weight := 0.0
		var shin_weight := 0.0
		for slot in 4:
			var weight := weights[i * 4 + slot]
			total += weight
			if bones[i * 4 + slot] == thigh:
				thigh_weight += weight
			elif bones[i * 4 + slot] == shin:
				shin_weight += weight
		check(absf(total - 1.0) < WEIGHT_EPSILON, "trouser skin weights not normalized")
		if vertices[i].y > 0.9:
			check(thigh_weight > 0.95, "trouser top must follow the thigh bone")
		elif vertices[i].y < 0.3:
			check(shin_weight > 0.9, "trouser hem must follow the shin bone")


func _check_standalone_waistcoat() -> void:
	var doll := Doll.new()
	doll.catalog_style = 2
	doll.configure({"outfit": 2, "palette": 1})
	root.add_child(doll)
	var coat: MeshInstance3D
	var binding: MeshInstance3D
	for part in doll.rig.meshes:
		if part.name == "OpenWaistcoat":
			coat = part
		elif part.name == "FrontBinding":
			binding = part
	check(coat != null, "waistcoat part missing")
	if coat == null:
		doll.free()
		return
	var source := coat.mesh
	var result := Geometry.standalone_waistcoat_mesh(source)
	check(result != null and result.get_surface_count() == 1, "standalone waistcoat mesh was not produced")
	if result == null or result.get_surface_count() == 1 == false:
		doll.free()
		return
	var source_count: int = source.surface_get_array_len(0)
	var arrays := result.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(vertices.size() > 0, "standalone waistcoat is empty")
	check(result.get_aabb().size.y > .5, "standalone waistcoat lost its body or shoulders")
	check(result.get_blend_shape_count() == source.get_blend_shape_count(), "standalone waistcoat lost its rest-cloth blend shapes")
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	check(bones.size() == vertices.size() * 4 and weights.size() == vertices.size() * 4, "standalone waistcoat lost its skin channels")
	var bone_count: int = doll.rig.skeleton.get_bone_count()
	for i in vertices.size():
		var total := 0.0
		for slot in 4:
			check(bones[i * 4 + slot] >= 0 and bones[i * 4 + slot] < bone_count, "standalone waistcoat has an out-of-range bone")
			check(weights[i * 4 + slot] >= 0.0, "standalone waistcoat has a negative weight")
			total += weights[i * 4 + slot]
		check(absf(total - 1.0) < WEIGHT_EPSILON, "standalone waistcoat weights not normalized")
		check(Geometry._armhole_clearance(vertices[i]) > -0.0001, "standalone waistcoat still fills the armhole")
	# No degenerate or sliver triangles in the output soup.
	for face in range(0, vertices.size(), 3):
		var a := vertices[face]
		var area := (vertices[face + 1] - a).cross(vertices[face + 2] - a).length()
		check(area > 0.000000005, "standalone waistcoat has degenerate triangles")
	# The cut edge is densely sampled so the armhole reads as a smooth curve.
	var boundary_samples := 0
	for point in vertices:
		if absf(Geometry._armhole_clearance(point)) < 0.012:
			boundary_samples += 1
	check(boundary_samples > 60, "armhole boundary is too coarse to be smooth")
	# Both sides are cut, and the open front survives untouched.
	var cut_left := false
	var cut_right := false
	for point in source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if Geometry._armhole_clearance(point) < 0.0:
			cut_left = cut_left or point.x < 0.0
			cut_right = cut_right or point.x > 0.0
	check(cut_left and cut_right, "armholes must be cut on both sides")
	var front_source := 0
	var front_result := 0
	for point in source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(atan2(point.x, point.z)) < 0.6 and point.y > 1.1 and point.y < 1.6:
			front_source += 1
	for point in vertices:
		if absf(atan2(point.x, point.z)) < 0.6 and point.y > 1.1 and point.y < 1.6:
			front_result += 1
	check(front_source > 0 and front_source == front_result, "standalone waistcoat must preserve the open front")
	if binding != null:
		var border := Geometry.standalone_waistcoat_mesh(binding.mesh)
		var border_arrays := border.surface_get_arrays(0)
		var border_vertices: PackedVector3Array = border_arrays[Mesh.ARRAY_VERTEX]
		var border_weights: PackedFloat32Array = border_arrays[Mesh.ARRAY_WEIGHTS]
		check(border_vertices.size() == binding.mesh.surface_get_array_len(0), "front binding should pass through untouched")
		for i in border_vertices.size():
			var total := 0.0
			for slot in 4:
				total += border_weights[i * 4 + slot]
			check(absf(total - 1.0) < WEIGHT_EPSILON, "front binding weights not normalized")
	doll.free()


# Welds coincident vertices, then reports triangle/component health.
func _topology(mesh: ArrayMesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_indices = arrays[Mesh.ARRAY_INDEX]
	var welded := _weld(vertices)
	var remap: PackedInt32Array = welded[0]
	var degenerate := 0
	var parent: Array[int] = []
	for i in welded[1]:
		parent.append(i)
	var face_count: int = (vertices.size() if raw_indices == null else raw_indices.size()) / 3
	for face in face_count:
		var corners := PackedInt32Array()
		if raw_indices == null:
			corners = PackedInt32Array([face * 3, face * 3 + 1, face * 3 + 2])
		else:
			corners = raw_indices.slice(face * 3, face * 3 + 3)
		var a := remap[corners[0]]
		var b := remap[corners[1]]
		var c := remap[corners[2]]
		if a == b or b == c or a == c:
			degenerate += 1
			continue
		if (vertices[corners[1]] - vertices[corners[0]]).cross(vertices[corners[2]] - vertices[corners[0]]).length() < 0.000001:
			degenerate += 1
			continue
		_union(parent, a, b)
		_union(parent, b, c)
	var components := 0
	for i in parent.size():
		if _find(parent, i) == i:
			components += 1
	return {"degenerate": degenerate, "components": components}


# Boundary loops after welding; each entry is [mean height, edge count].
func _boundary_loops(mesh: ArrayMesh) -> Array:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var raw_indices = arrays[Mesh.ARRAY_INDEX]
	var welded := _weld(vertices)
	var remap: PackedInt32Array = welded[0]
	var use := {}
	var face_count: int = (vertices.size() if raw_indices == null else raw_indices.size()) / 3
	for face in face_count:
		var corners := PackedInt32Array()
		if raw_indices == null:
			corners = PackedInt32Array([face * 3, face * 3 + 1, face * 3 + 2])
		else:
			corners = raw_indices.slice(face * 3, face * 3 + 3)
		for corner in 3:
			var a: int = mini(remap[corners[corner]], remap[corners[(corner + 1) % 3]])
			var b: int = maxi(remap[corners[corner]], remap[corners[(corner + 1) % 3]])
			if a == b:
				continue
			var key := a * 100000 + b
			use[key] = use.get(key, 0) + 1
	var adjacency := {}
	for key in use:
		if use[key] != 1:
			continue
		var a: int = key / 100000
		var b: int = key % 100000
		if not adjacency.has(a):
			adjacency[a] = []
		if not adjacency.has(b):
			adjacency[b] = []
		adjacency[a].append(b)
		adjacency[b].append(a)
	var heights := {}
	for i in remap.size():
		heights[remap[i]] = vertices[i].y
	var loops := []
	var visited := {}
	for start in adjacency:
		if visited.has(start):
			continue
		var size := 0
		var height := 0.0
		var stack := [start]
		while not stack.is_empty():
			var node: int = stack.pop_back()
			if visited.has(node):
				continue
			visited[node] = true
			size += 1
			height += heights[node]
			for next in adjacency[node]:
				if not visited.has(next):
					stack.append(next)
		loops.append([height / size, size])
	return loops


func _weld(vertices: PackedVector3Array) -> Array:
	var slots := {}
	var remap := PackedInt32Array()
	var count := 0
	for point in vertices:
		var key := str(snappedf(point.x, 0.0005)) + "," + str(snappedf(point.y, 0.0005)) + "," + str(snappedf(point.z, 0.0005))
		if not slots.has(key):
			slots[key] = count
			count += 1
		remap.append(slots[key])
	return [remap, count]


func _find(parent: Array[int], index: int) -> int:
	while parent[index] != index:
		parent[index] = parent[parent[index]]
		index = parent[index]
	return index


func _union(parent: Array[int], a: int, b: int) -> void:
	parent[_find(parent, a)] = _find(parent, b)

