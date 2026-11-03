extends RefCounted

const SHAPES := ["RestSit", "RestNap", "RestCurled", "RestLoose", "RestDraped"]
const GRAVITY_DRAPE = preload("res://assets/rest_cloth/nap_gravity.tres")


static func point(p: Vector3, nap: bool, variant := 0, gravity_enabled := true) -> Vector3:
	if p.y >= 1.30:
		return p
	var d := 1.30-p.y
	var angle := minf(d/.38,1.0)*PI*.5
	var center := Vector2(1.30-.242*sin(angle),.242*(1.0-cos(angle)))
	if d > .38:
		center.y += minf(d-.38,.22)
	if d > .60:
		angle = (1.0-minf((d-.60)/.24,1.0))*PI*.5
		center = Vector2(1.058-.153*(1.0-sin(angle)),.462+.153*cos(angle))
	if d > .84:
		center.x -= (d-.84)*(1.0 if not nap else .9)
		center.y -= (d-.84)*(.25 if nap else 0.0)
	var radial := p.z if p.z >= 0 else p.z*lerpf(1,.48 if nap else .24,smoothstep(0,.38,d))
	var result := Vector3(p.x*lerpf(1,.93 if nap else 1.0,smoothstep(0,.45,d)),center.x+radial*sin(angle),center.y+radial*cos(angle))
	if not nap:
		# Seated work keeps the cloth over knees, with room for pedal flexion.
		var knee_cover := smoothstep(.20,.48,d)*(1.0-smoothstep(.85,1.10,d))
		result.x *= 1.0+.08*knee_cover
		result.z += .075*knee_cover
		result.y += .035*knee_cover*maxf(0,p.z)/.32
	if nap:
		# Correct the existing skirt around the same knees; do not replace its mesh.
		var knee := smoothstep(.15,.65,d)
		var hem := smoothstep(.65,1.10,d)
		if variant == 1:
			result.y += .13*knee
			result.z += .045*knee-.08*hem
		elif variant == 2:
			result.y -= .06*knee+.06*hem
			result.z -= .025*knee-.035*hem
		# Preserve a readable skirt volume around the tucked legs. The hem may
		# drape toward the cushion, but it must not collapse onto the shin.
		result.z -= .07*hem+maxf(p.z,0.0)*.10*hem
		result.y += (.18*maxf(p.x,0.0)-.08)*hem
		result.x *= 1.0+.04*hem
		# Only the cushion-facing side compresses; the upper skirt keeps its ease.
		result.x = maxf(result.x,-.29)
		# Root turns the doll onto its side: local X is world up. Apply the
		# Blender contact solve along gravity only, retaining the authored ease.
		if gravity_enabled:
			result.x += GRAVITY_DRAPE.sample(p,variant)
			result.x = maxf(result.x,-.32)
	return result


static func install(part: MeshInstance3D, gravity_enabled := true) -> void:
	var arrays := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var shapes: Array[Array] = []
	for mode in SHAPES.size():
		var nap := mode > 0
		var variant := maxi(0,mode-1)
		var shaped := PackedVector3Array()
		var directions := PackedVector3Array()
		for index in vertices.size():
			var p := vertices[index]
			var n := normals[index]
			var tangent := n.cross(Vector3.UP).normalized()
			if tangent.length_squared() < .1: tangent = Vector3.RIGHT
			var across := n.cross(tangent).normalized()
			var origin := point(p,nap,variant,gravity_enabled)
			var direction := (point(p+tangent*.001,nap,variant,gravity_enabled)-origin).cross(point(p+across*.001,nap,variant,gravity_enabled)-origin).normalized()
			shaped.append(origin)
			directions.append(direction if direction.length_squared() > .1 else n)
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = shaped
		shape[Mesh.ARRAY_NORMAL] = directions
		shapes.append(shape)
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for label in SHAPES:
		mesh.add_blend_shape(label)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,shapes)
	part.mesh = mesh
	part.set_meta("rest_cloth",true)


static func fit_layer(rig: RefCounted, part: MeshInstance3D, mode: int) -> void:
	var arrays: Array = part.mesh.surface_get_arrays(0)
	var triangles: PackedInt32Array = part.get_meta("skin_layer_triangles")
	var barycentric: PackedVector3Array = part.get_meta("skin_layer_barycentric")
	var source_ids: PackedInt32Array = part.get_meta("skin_layer_source_index")
	var sources: Array = []
	for path in part.get_meta("skin_layer_sources"):
		var source := part.get_node(NodePath(path)) as MeshInstance3D
		sources.append([source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],rig.deformed_vertices(source)])
	var transforms: Array[Transform3D] = []
	for index in rig.skeleton.get_bone_count():
		transforms.append(rig.global_pose(index)*rig.skeleton.get_bone_global_rest(index).affine_inverse())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var contacts := PackedVector3Array()
	var world_normals := PackedVector3Array()
	var clearances := PackedFloat32Array()
	var skin_transforms: Array[Transform3D] = []
	for i in barycentric.size():
		var source: Array = sources[source_ids[i]]
		var contact := Vector3.ZERO
		var original := Vector3.ZERO
		for corner in 3:
			contact += source[1][triangles[i*3+corner]]*barycentric[i][corner]
			original += source[0][triangles[i*3+corner]]*barycentric[i][corner]
		var a: Vector3 = source[1][triangles[i*3]]
		var normal: Vector3 = (source[1][triangles[i*3+2]]-a).cross(source[1][triangles[i*3+1]]-a).normalized()
		var minimum_gap := .022 if str(part.name) == "OpenWaistcoat" else .012
		var gap: float = maxf(minimum_gap,arrays[Mesh.ARRAY_VERTEX][i].distance_to(original))
		var weighted := Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
		for slot in 4:
			var transform := transforms[arrays[Mesh.ARRAY_BONES][i*4+slot]]
			var weight: float = arrays[Mesh.ARRAY_WEIGHTS][i*4+slot]
			weighted.basis.x += transform.basis.x*weight
			weighted.basis.y += transform.basis.y*weight
			weighted.basis.z += transform.basis.z*weight
			weighted.origin += transform.origin*weight
		vertices.append(weighted.affine_inverse()*(contact+normal*gap))
		normals.append((weighted.basis.transposed()*normal).normalized())
		contacts.append(contact)
		world_normals.append(normal)
		clearances.append(gap)
		skin_transforms.append(weighted)
	var shapes: Array = part.mesh.surface_get_blend_shape_arrays(0)
	# Clipped triangles duplicate edge vertices. Weld their corrective positions so
	# normal offsets cannot open visible cracks between adjacent triangles.
	var shared: Dictionary = {}
	for i in vertices.size():
		var key := Vector3i((arrays[Mesh.ARRAY_VERTEX][i]*100000.0).round())
		if not shared.has(key): shared[key] = []
		shared[key].append(i)
	for indices in shared.values():
		var center := Vector3.ZERO
		var normal := Vector3.ZERO
		for i in indices:
			center += contacts[i]+world_normals[i]*clearances[i]
			normal += world_normals[i]
		center /= indices.size()
		for iteration in 12:
			for i in indices:
				var deficit: float = clearances[i]-(center-contacts[i]).dot(world_normals[i])
				if deficit > 0: center += world_normals[i]*deficit
		for i in indices:
			vertices[i] = skin_transforms[i].affine_inverse()*center
			normals[i] = (skin_transforms[i].basis.transposed()*normal).normalized()
	shapes[mode][Mesh.ARRAY_VERTEX] = vertices
	shapes[mode][Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for label in SHAPES:
		mesh.add_blend_shape(label)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,shapes)
	part.mesh = mesh
	part.set_blend_shape_value(mode,1.0)
