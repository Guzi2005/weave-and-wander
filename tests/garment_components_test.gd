extends SceneTree

const Shell = preload("res://components/simple_garment.gd")
const Stud = preload("res://components/button_stud.gd")
const Doll = preload("res://scripts/volume_doll.gd")
const Template = preload("res://components/garment_template.tscn")
const CoatTemplate = preload("res://components/waistcoat_template.tscn")
var failures: Array[String] = []
var deformation_samples := 0
var maximum_stretch := 1.0
var diagnostic_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var shell := Shell.new()
	root.add_child(shell)
	_check_topology(shell.mesh, 6, false, 3)
	var original_width := shell.mesh.get_aabb().size.x
	shell.cuff_width = 1.2
	shell.sleeve_length = 1.1
	await process_frame
	_check(shell.mesh.get_aabb().size.x > original_width, "Cuff parameter did not regenerate the garment.")
	_check_topology(shell.mesh, 6, false, 3)
	shell.free()
	var button := Stud.new()
	root.add_child(button)
	_check_button(button)
	button.width = 0.052
	button.height = 0.07
	button.depth = 0.013
	await process_frame
	_check_button(button)
	_check(absf(button.mesh.get_aabb().size.x - 0.052) < 0.0001, "Button dimensions did not regenerate.")
	button.free()
	var template := Template.instantiate()
	root.add_child(template)
	var row = template.get_node("Buttons")
	_check(row.get_child_count() == 3, "Template button row was not generated.")
	row.count = 5
	row.spacing = 0.06
	await process_frame
	_check(row.get_child_count() == 5, "Button count parameter did not rebuild the row.")
	for child in row.get_children():
		_check(child.has_meta("skin_anchor_local"), "Button did not mount on the actual garment surface.")
		_check(child.position.z > 0.1, "Mounted button is inside the garment.")
	var before: float = row.get_child(0).position.z
	template.get_node("Shell").body_width = 0.86
	await process_frame
	await process_frame
	_check(absf(row.get_child(0).position.z - before) > 0.00001, "Buttons did not remount after the garment changed.")
	template.free()
	var coat_template := CoatTemplate.instantiate()
	root.add_child(coat_template)
	var overlay := coat_template.get_node("Waistcoat") as MeshInstance3D
	_check(overlay.mesh != null and overlay.mesh.get_surface_count() == 1, "Reusable waistcoat did not generate.")
	var coat_before := overlay.mesh
	coat_template.get_node("Shell").body_width = 1.1
	await process_frame
	await process_frame
	_check(overlay.mesh != coat_before, "Waistcoat did not follow a rebuilt garment.")
	coat_template.free()
	for recipe in [{"outfit": 0}, {"outfit": 1}, {"outfit": 2}, {"outfit": 0, "reference": true}]:
		var doll := Doll.new()
		# Production configures some NPCs before adding them to the scene tree.
		doll.configure(recipe)
		root.add_child(doll)
		await process_frame
		var garment: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/garment/TailoredShell")
		_check_topology(garment.mesh, 6, false, 3)
		var arrays := garment.mesh.surface_get_arrays(0)
		var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		doll.rig.animate(0, 0, "idle", 0)
		var idle: PackedVector3Array = doll.rig.deformed_vertices(garment)
		var lower_sleeve_width := 0.0
		var upper_sleeve_width := 0.0
		for point in idle:
			if point.y > 1.59 and point.y < 1.82:
				upper_sleeve_width = maxf(upper_sleeve_width, absf(point.x))
			if point.y < 1.28:
				lower_sleeve_width = maxf(lower_sleeve_width, absf(point.x))
		_check(upper_sleeve_width < 0.35, "Reference silhouette lost: upper arms became too broad.")
		_check(lower_sleeve_width > 0.42 and lower_sleeve_width < 0.49, "Reference silhouette lost: bell sleeve width changed.")
		for pose in 32:
			doll.rig.animate(TAU * pose / 24.0, 1.0 if pose < 24 else 0.0, "idle" if pose < 24 else "sewing", pose * 0.2)
			var deformed: PackedVector3Array = doll.rig.deformed_vertices(garment)
			deformation_samples += 1
			for i in range(0, indices.size(), 3):
				var a := indices[i]
				var b := indices[i + 1]
				var c := indices[i + 2]
				_check(deformed[a].is_finite(), "Garment skinning produced non-finite vertices.")
				_check((deformed[b] - deformed[a]).cross(deformed[c] - deformed[a]).length() > 0.000001, "Garment triangle collapsed during animation.")
				var stretch := deformed[a].distance_to(deformed[b]) / rest[a].distance_to(rest[b])
				maximum_stretch = maxf(maximum_stretch, stretch)
				if stretch > 2.0 and diagnostic_count < 3:
					print("STRETCH_DETAIL pose=", pose, " rest=", rest[a], " to=", rest[b], " posed=", deformed[a], " to=", deformed[b], " ratio=", stretch)
					diagnostic_count += 1
				_check(stretch < 2.0, "Garment stretches excessively across the shoulder.")
			_check_cuffs(doll, garment, deformed)
		for pose in 16:
			var start := pose/4
			var target := pose%4
			for blend in [0.0,.5,1.0]:
				var weights := Vector4.ZERO
				weights[start] = 1.0-blend
				weights[target] += blend
				doll.rig.animate(0,0,"idle",0)
				doll.rig.pose_rest("nap",1,0,weights)
				var deformed: PackedVector3Array = doll.rig.deformed_vertices(garment)
				_check_cuffs(doll,garment,deformed)
				for i in range(0,indices.size(),3):
					var a := deformed[indices[i]]
					var b := deformed[indices[i+1]]
					var c := deformed[indices[i+2]]
					_check((b-a).cross(c-a).length() > .000001,"Sleeve triangle collapsed during nap transition.")
				deformation_samples += 1
		doll.free()
	print("GARMENT_COMPONENTS_CHECK poses=", deformation_samples, " max_stretch=", maximum_stretch,
		" shell_parts=3 shell_boundaries=6 button_back=flat failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_button(button: MeshInstance3D) -> void:
	var arrays := button.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var backing := 0
	for i in vertices.size():
		_check(vertices[i].z >= 0.0, "Button still contains a buried negative-Z hemisphere.")
		if normals[i].z < -0.99:
			_check(absf(vertices[i].z) < 0.000001, "Button back is not planar.")
			backing += 1
	_check(backing == 25, "Button needs a real closed flat backing.")
	_check_topology(button.mesh, 0, true)


func _check_topology(mesh: ArrayMesh, expected_boundaries: int, weld_positions: bool, expected_parts: int = 1) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX].duplicate()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var vertex_count := vertices.size()
	if weld_positions:
		var unique: Dictionary = {}
		var mapping: Dictionary = {}
		for i in vertices.size():
			var key := vertices[i].snapped(Vector3.ONE * 0.000001)
			if not unique.has(key):
				unique[key] = unique.size()
			mapping[i] = unique[key]
		for i in indices.size():
			indices[i] = mapping[indices[i]]
		vertex_count = unique.size()
	var edges: Dictionary = {}
	var adjacency: Dictionary = {}
	for i in range(0, indices.size(), 3):
		for corner in 3:
			var a := indices[i + corner]
			var b := indices[i + (corner + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edges.has(key):
				edges[key] = [0, 0]
			edges[key][0] += 1
			edges[key][1] += 1 if a < b else -1
			if not adjacency.has(a):
				adjacency[a] = []
			adjacency[a].append(b)
			if not adjacency.has(b):
				adjacency[b] = []
			adjacency[b].append(a)
	_check(_components(adjacency) == expected_parts and adjacency.size() == vertex_count, "Unexpected number of garment parts or orphaned vertices.")
	var boundary: Dictionary = {}
	for key in edges:
		var uses: Array = edges[key]
		_check(uses[0] <= 2, "Non-manifold clothing edge.")
		if uses[0] == 2:
			_check(uses[1] == 0, "Adjacent clothing triangles have inconsistent winding.")
		else:
			if not boundary.has(key.x): boundary[key.x] = []
			if not boundary.has(key.y): boundary[key.y] = []
			boundary[key.x].append(key.y)
			boundary[key.y].append(key.x)
	_check(_components(boundary) == expected_boundaries, "Unexpected hole or seam in garment topology.")
	for connections in boundary.values():
		_check(connections.size() == 2, "Clothing boundary has a tear or branch.")
	if not weld_positions:
		for i in range(0, indices.size(), 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			var face := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a]).normalized()
			if face.dot(normals[a] + normals[b] + normals[c]) <= 0 and not failures.has("Garment normals oppose the triangle winding."):
				print("NORMAL_DETAIL ", vertices[a], " ", vertices[b], " ", vertices[c], " normal=", face, " expected=", normals[a], " ", normals[b], " ", normals[c])
			_check(face.dot(normals[a] + normals[b] + normals[c]) > 0.0, "Garment normals oppose the triangle winding.")


func _components(adjacency: Dictionary) -> int:
	var seen: Dictionary = {}
	var count := 0
	for start in adjacency:
		if seen.has(start): continue
		count += 1
		var stack: Array = [start]
		while not stack.is_empty():
			var current = stack.pop_back()
			if seen.has(current): continue
			seen[current] = true
			stack.append_array(adjacency[current])
	return count


func _check_cuffs(doll: VolumeDoll, garment: MeshInstance3D, deformed: PackedVector3Array) -> void:
	var rest: PackedVector3Array = garment.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for suffix in ["L", "R"]:
		var cuff: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/arm" + suffix + "/CuffBinding")
		var cuff_vertices: PackedVector3Array = doll.rig.deformed_vertices(cuff)
		for i in rest.size():
			if absf(rest[i].y - 1.195) > 0.0001 or (rest[i].x < 0) != (suffix == "L"):
				continue
			var closest := INF
			for point in cuff_vertices:
				closest = minf(closest, point.distance_to(deformed[i]))
			_check(closest < 0.026, "Sleeve detached from its cuff during animation.")
