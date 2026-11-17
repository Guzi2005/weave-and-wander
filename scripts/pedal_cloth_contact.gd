extends RefCounted
## Pose-space collision projection for seated pedal work. The authored sewn
## garment remains the source; only contacting cloth is displaced. This is a
## collision corrective, not a full stretch/bend/gravity cloth integrator.
var copies: Dictionary = {}
var last_update := -1000
var active := false
var leg_materials: Dictionary = {}
var sample_count := 0
var projected_count := 0

static func drape(p: Vector3, hip: Vector3, knee: Vector3, ankle: Vector3) -> Vector3:
	var path := [hip+Vector3(0,.20,0),hip,knee,ankle,ankle+Vector3(0,-.15,0)]
	var at := 0.0
	if p.y>=1.10: at=(1.30-p.y)/.20
	elif p.y>=.60: at=1+(1.10-p.y)/.50
	else: at=2+(.60-p.y)/.45
	at=clampf(at,0,3.95)
	var i := mini(int(at),3)
	var t := at-i
	var a: Vector3 = path[maxi(0,i-1)]
	var b: Vector3 = path[i]
	var c: Vector3 = path[i+1]
	var d: Vector3 = path[mini(i+2,4)]
	var center := .5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
	var tangent := .5*((-a+c)+2*(2*a-5*b+4*c-d)*t+3*(-a+3*b-3*c+d)*t*t)
	var front := Vector3(0,tangent.z,-tangent.y).normalized()
	return center+Vector3(p.x,0,0)+front*p.z

static func project(p: Vector3, a: Vector3, b: Vector3, radius: float) -> Vector3:
	var ab := b-a
	var t := clampf((p-a).dot(ab)/maxf(ab.length_squared(),.000001),0,1)
	var center := a+ab*t
	var d := p-center
	if d.length_squared() >= radius*radius: return p
	var normal := d.normalized() if d.length_squared()>.000001 else Vector3.FORWARD*-1
	return center+normal*radius

func clear() -> void:
	for source in copies:
		if is_instance_valid(source): source.visible = true
		if is_instance_valid(copies[source]): copies[source].hide()
	active = false
	for material in leg_materials:
		material.set_shader_parameter("covered_above",leg_materials[material])
	leg_materials.clear()

func update(rig: RefCounted) -> void:
	var now := Time.get_ticks_msec()
	if active and now-last_update<50: return
	last_update = now
	active = true
	sample_count = 0
	projected_count = 0
	for part in rig.meshes:
		if str(part.name) not in ["Calf","CalfMannequin"]: continue
		var material = part.material_override
		if material is ShaderMaterial and material.shader.resource_path.ends_with("hosiery.gdshader"):
			if not leg_materials.has(material):
				leg_materials[material] = material.get_shader_parameter("covered_above")
			material.set_shader_parameter("covered_above",100.0)
	var segments: Array = []
	var centers := [Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
	for side in ["L","R"]:
		var hip: Vector3 = rig.global_pose(rig.bones["Thigh"+side]).origin
		var knee: Vector3 = rig.global_pose(rig.bones["Shin"+side]).origin
		var ankle: Vector3 = rig.global_pose(rig.bones["Foot"+side]).origin
		segments.append([hip,knee,.160])
		segments.append([knee,ankle,.125])
		centers[0]+=hip*.5; centers[1]+=knee*.5; centers[2]+=ankle*.5
	for source in rig.meshes:
		if source.get_meta("semantic","") not in ["skirt","apron"]: continue
		if not source.get_meta("rest_cloth",false): continue
		if not copies.has(source) and not source.visible: continue
		var arrays: Array = source.mesh.surface_get_arrays(0)
		var rest: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var positions: PackedVector3Array = rig.deformed_vertices(source)
		var clearance := .012 if str(source.name).contains("Apron") else 0.0
		for i in positions.size():
			# Keep waist seam pinned; solve below it and stop at the actual hem.
			if rest[i].y>=1.30: continue
			var p := positions[i]
			var fitted := drape(rest[i],centers[0],centers[1],centers[2])
			p = p.lerp(fitted,1.0-smoothstep(1.12,1.30,rest[i].y))
			sample_count += 1
			for iteration in 3:
				for segment in segments:
					p = project(p,segment[0],segment[1],segment[2]+clearance)
			if p.distance_squared_to(positions[i])>.00000001: projected_count += 1
			positions[i] = p
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		# Recalculate posed normals while keeping the original UVs and colours.
		var normals := PackedVector3Array()
		normals.resize(positions.size())
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var a := indices[i]; var b := indices[i+1]; var c := indices[i+2]
			var n := (positions[c]-positions[a]).cross(positions[b]-positions[a])
			normals[a]+=n; normals[b]+=n; normals[c]+=n
		for i in normals.size(): normals[i]=normals[i].normalized()
		arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		if not copies.has(source):
			var instance := MeshInstance3D.new()
			instance.name = str(source.name)+"PedalContact"
			instance.material_override=source.material_override
			source.get_parent().add_child(instance)
			copies[source]=instance
		copies[source].mesh=mesh
		copies[source].show()
		source.hide()
