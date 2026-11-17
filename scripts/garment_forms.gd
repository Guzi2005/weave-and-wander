extends RefCounted

const SHAPES := ["Hanging", "FoldSides", "FoldHalf", "Folded"]
const REST_SHAPES = preload("res://scripts/rest_cloth.gd").SHAPES
var profile: Dictionary
var bounds := {}


func build(parts: Array[MeshInstance3D], definition: Resource, bottom: float, top: float) -> void:
	profile = definition.form_profile(bottom, top)
	if definition.is_hat():
		return
	for part in parts:
		_bind(part)


func _bind(part: MeshInstance3D) -> void:
	var source := part.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var raw_indices = source[Mesh.ARRAY_INDEX]
	var indices: PackedInt32Array = raw_indices if raw_indices != null else PackedInt32Array()
	var raw_bones = source[Mesh.ARRAY_BONES]
	var raw_weights = source[Mesh.ARRAY_WEIGHTS]
	var has_skin := raw_bones != null and raw_weights != null
	var source_bones: PackedInt32Array = raw_bones if has_skin else PackedInt32Array()
	var source_weights: PackedFloat32Array = raw_weights if has_skin else PackedFloat32Array()
	var keep_uv := part.has_meta("preserve_fabric_uv") and source[Mesh.ARRAY_TEX_UV] != null
	var source_uv: PackedVector2Array = source[Mesh.ARRAY_TEX_UV] if keep_uv else PackedVector2Array()
	var keep_uv2 := source[Mesh.ARRAY_TEX_UV2] != null
	var source_uv2: PackedVector2Array = source[Mesh.ARRAY_TEX_UV2] if keep_uv2 else PackedVector2Array()
	var raw_colors = source[Mesh.ARRAY_COLOR]
	var keep_color := raw_colors != null
	var source_colors: PackedColorArray = raw_colors if keep_color else PackedColorArray()
	var rest_names: Array[StringName] = []
	var rest_targets: Array = []
	var source_shapes := part.mesh.surface_get_blend_shape_arrays(0)
	var relative: bool = part.mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
	for i in part.mesh.get_blend_shape_count():
		var name: StringName = part.mesh.get_blend_shape_name(i)
		if name in REST_SHAPES:
			rest_names.append(name)
			rest_targets.append(source_shapes[i])
	if indices.is_empty():
		for i in range(0,vertices.size(),3):
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + 2)
	var cuts: Array[Vector2] = [Vector2(0,-profile.half_width),Vector2(0,profile.half_width),Vector2(1,profile.half_y),Vector2(2,0)]
	if profile.quarter_fold:
		cuts.append(Vector2(1,profile.quarter_y))
		cuts.append(Vector2(1,2.0*profile.half_y-profile.quarter_y))
	var output := SurfaceTool.new()
	output.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shapes: Array[Array] = []
	for target in SHAPES.size() + rest_names.size():
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = PackedVector3Array()
		shape[Mesh.ARRAY_NORMAL] = PackedVector3Array()
		shapes.append(shape)
	# Split at folds and the front/back UV seam before constructing morph targets.
	# Interpolated skin weights keep the same refined topology usable on the actor.
	for face in range(0,indices.size(),3):
		var polygon: Array[Dictionary] = []
		for corner in 3:
			var i := indices[face+corner]
			var rest_p := PackedVector3Array()
			var rest_n := PackedVector3Array()
			for target in rest_targets:
				# Output folds are absolute targets; convert relative sources before clipping.
				rest_p.append(target[Mesh.ARRAY_VERTEX][i] + vertices[i] if relative else target[Mesh.ARRAY_VERTEX][i])
				var target_normals = target[Mesh.ARRAY_NORMAL]
				rest_n.append(normals[i] if target_normals == null else (target_normals[i] + normals[i] if relative else target_normals[i]))
			polygon.append({"p":vertices[i],"n":normals[i],"uv":source_uv[i] if keep_uv else Vector2.ZERO,"uv2":source_uv2[i] if keep_uv2 else Vector2.ZERO,"color":source_colors[i] if keep_color else Color.WHITE,"bones":source_bones.slice(i*4,i*4+4),"weights":source_weights.slice(i*4,i*4+4),"rest_p":rest_p,"rest_n":rest_n})
		var polygons: Array = [polygon]
		for cut in cuts:
			var result: Array = []
			for poly in polygons:
				result.append_array(_split(poly,int(cut.x),cut.y))
			polygons = result
		for poly in polygons:
			var center := Vector3.ZERO
			for sample in poly: center += sample.p
			var back := center.z < 0
			for fan in range(1,poly.size()-1):
				for corner in [0,fan,fan+1]:
					var sample: Dictionary = poly[corner]
					var point: Vector3 = sample.p
					output.set_normal(sample.n)
					if keep_uv2: output.set_uv2(sample.uv2)
					if keep_color:
						output.set_color(sample.color)
					if has_skin:
						output.set_bones(sample.bones)
						output.set_weights(sample.weights)
					var u: float = (point.x/profile.uv_width+.5)*.5
					output.set_uv(sample.uv if keep_uv else Vector2(1.0-u if back else u,(profile.top-point.y)/(profile.top-profile.bottom)))
					output.add_vertex(point)
					for stage in SHAPES.size():
						var deformed := deform(point,sample.n,stage)
						shapes[stage][Mesh.ARRAY_VERTEX].append(deformed[0])
						shapes[stage][Mesh.ARRAY_NORMAL].append(deformed[1])
					for target in rest_names.size():
						shapes[SHAPES.size() + target][Mesh.ARRAY_VERTEX].append(sample.rest_p[target])
						shapes[SHAPES.size() + target][Mesh.ARRAY_NORMAL].append(sample.rest_n[target])
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	for name in SHAPES: mesh.add_blend_shape(name)
	for name in rest_names: mesh.add_blend_shape(name)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,output.commit_to_arrays(),shapes)
	part.mesh = mesh
	part.set_meta("pattern_surface",str(part.name))
	part.set_meta("form_schema","garment-form-v1")
	for stage in SHAPES.size():
		for point in shapes[stage][Mesh.ARRAY_VERTEX]:
			bounds[SHAPES[stage]] = bounds[SHAPES[stage]].expand(point) if bounds.has(SHAPES[stage]) else AABB(point,Vector3.ZERO)


func _split(poly: Array, axis: int, line: float) -> Array:
	var low := false
	var high := false
	for sample in poly:
		low = low or sample.p[axis] < line-.00001
		high = high or sample.p[axis] > line+.00001
	if not low or not high:
		return [poly]
	var halves: Array = []
	for sign_value in [-1.0,1.0]:
		var clipped: Array = []
		for i in poly.size():
			var a: Dictionary = poly[i]
			var b: Dictionary = poly[(i+1)%poly.size()]
			var da: float = (a.p[axis]-line)*sign_value
			var db: float = (b.p[axis]-line)*sign_value
			if da >= 0: clipped.append(a)
			if (da < 0 and db > 0) or (da > 0 and db < 0):
				clipped.append(_interpolate(a,b,da/(da-db)))
		if clipped.size() >= 3: halves.append(clipped)
	return halves


func _interpolate(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var sample := {"p":a.p.lerp(b.p,weight),"n":a.n.lerp(b.n,weight).normalized(),"uv":a.get("uv",Vector2.ZERO).lerp(b.get("uv",Vector2.ZERO),weight),"uv2":a.get("uv2",Vector2.ZERO).lerp(b.get("uv2",Vector2.ZERO),weight),"color":a.get("color",Color.WHITE).lerp(b.get("color",Color.WHITE),weight),"bones":PackedInt32Array(),"weights":PackedFloat32Array(),"rest_p":PackedVector3Array(),"rest_n":PackedVector3Array()}
	for target in a.rest_p.size():
		sample.rest_p.append(a.rest_p[target].lerp(b.rest_p[target], weight))
		sample.rest_n.append(a.rest_n[target].lerp(b.rest_n[target], weight))
	if a.bones.is_empty():
		return sample
	var influences := {}
	for i in 4:
		influences[a.bones[i]] = influences.get(a.bones[i],0.0)+a.weights[i]*(1.0-weight)
		influences[b.bones[i]] = influences.get(b.bones[i],0.0)+b.weights[i]*weight
	var ids: Array = influences.keys()
	ids.sort_custom(func(x: int,y: int) -> bool: return influences[x] > influences[y])
	ids.resize(mini(ids.size(),4))
	var total := 0.0
	for id in ids: total += influences[id]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for i in 4:
		bones.append(ids[i] if i < ids.size() else 0)
		weights.append(influences[ids[i]]/total if i < ids.size() else 0.0)
	sample.bones = bones
	sample.weights = weights
	return sample


func deform(point: Vector3, normal: Vector3, stage: int) -> Array[Vector3]:
	var depth: float = profile.hanging_depth if stage == 0 else profile.pressed_depth
	var slope := 0.0
	if stage == 0 and profile.get("clip_hung",false):
		var length := maxf(.01,(profile.top-profile.bottom)*float(profile.get("clip_release_fraction",.65)))
		var t := clampf((profile.top-point.y)/length,0,1)
		var released := maxf(depth,float(profile.get("clip_release_depth",.55)))
		slope = -(released-depth)*6.0*t*(1.0-t)/length
		depth = lerpf(depth,released,t*t*(3.0-2.0*t))
	var p := Vector3(point.x,point.y,point.z*depth)
	var n := Vector3(normal.x,normal.y-normal.z*point.z*slope/depth,normal.z/depth).normalized()
	if stage >= 1:
		# A small low-poly chamfer keeps folded garments from reading as paper-thin.
		# The exported thickness remains a single numeric control on the definition.
		var bevel := minf(profile.fold_thickness * .55, .028)
		var edge_factor := clampf((absf(point.x)-profile.half_width) / maxf(bevel,.0001), 0.0, 1.0)
		p.z += bevel * .22 * edge_factor
		var side := -1.0 if p.x < -profile.half_width else (1.0 if p.x > profile.half_width else 0.0)
		if side != 0:
			var pivot := Vector3(side*profile.half_width,0,.006 if side < 0 else .016)
			var rotation := Basis(Vector3.UP,-side*PI)
			p = pivot+rotation*(p-pivot)
			n = rotation*n
	if stage >= 2 and p.y < profile.half_y:
		var pivot := Vector3(0,profile.half_y,.045)
		var rotation := Basis(Vector3.RIGHT,-PI)
		p = pivot+rotation*(p-pivot)
		n = rotation*n
	if stage >= 3 and profile.quarter_fold and p.y < profile.quarter_y:
		var pivot := Vector3(0,profile.quarter_y,.105)
		var rotation := Basis(Vector3.RIGHT,-PI)
		p = pivot+rotation*(p-pivot)
		n = rotation*n
	if stage >= 1 and profile.get("compact_apron_folds",false):
		# This thin cotton apron has no padding. Preserve fold layers while
		# bringing the existing thick display folds down to its textile gauge.
		p.z *= .24
		n = Vector3(n.x,n.y,n.z/.24).normalized()
	return [p,n]


func set_form(parts: Array[MeshInstance3D], form: String) -> void:
	var selected := SHAPES.find(form)
	for part in parts:
		for i in part.mesh.get_blend_shape_count():
			part.set_blend_shape_value(i,1.0 if i == selected else 0.0)


func blend_forms(parts: Array[MeshInstance3D], from: String, to: String, weight: float) -> void:
	for part in parts:
		for i in part.mesh.get_blend_shape_count():
			var value := 0.0
			if i < SHAPES.size():
				value = (1.0-weight if SHAPES[i] == from else 0.0)+(weight if SHAPES[i] == to else 0.0)
			part.set_blend_shape_value(i,value)


func manifest(design_id: String, parts: Array[MeshInstance3D]) -> Dictionary:
	var surfaces: Array[Dictionary] = []
	for part in parts:
		surfaces.append({"id":str(part.name),"vertex_count":part.mesh.surface_get_array_len(0),"uv_channel":0})
	return {"schema":"garment-form-v1","design_id":design_id,"units":"godot_meters","profile":profile,
		"uv_panels":{"front":[0,0,.5,1],"back":[.5,0,.5,1]},"surfaces":surfaces,
		"forms":["Worn"]+SHAPES,"topology":"shared_across_forms","pattern_source":"projected_template_not_sewing_pattern",
		"folded_thickness":profile.fold_thickness,"thickness_control":"garment_definition.folded_thickness"}
