extends SceneTree

var failures: Array[String] = []
var checked_vertices := 0
var intersections := 0
var contact_rows := {}
var poses := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _run() -> void:
	var doll := load("res://scripts/postal_doll.gd").new() as VolumeDoll
	root.add_child(doll)
	doll.configure({"outfit":0,"hair":1})
	var coat: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/skirt/PostalCoatSkirt")
	var shell: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/garment/TailoredShell")
	var head: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/head/Head")
	_check(shell.material_override.shader == VolumeDoll.VOLUME_SHADER, "Coat lost the character print material")
	_check(head.material_override.shader == VolumeDoll.VOLUME_SHADER, "Face no longer shares the character print treatment")
	for label in ["CoatPlacket","MailbagStrap"]:
		var layer: MeshInstance3D = doll.find_children(label,"MeshInstance3D",true,false)[0]
		_check(layer.get_meta("skin_layer_unmapped",-1) == 0,"Postal clothing layer has unbound vertices: "+label)
	var band: MeshInstance3D = doll.find_children("CapBand","MeshInstance3D",true,false)[0]
	var cap_points: PackedVector3Array = band.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var back_bottom := INF
	var front_bottom := INF
	for point in cap_points:
		if point.z < -.25:
			back_bottom = minf(back_bottom,point.y)
		if point.z > .25:
			front_bottom = minf(front_bottom,point.y)
	_check(back_bottom < 2.24 and front_bottom-back_bottom > .20,"Cap does not wrap down the back of the head")
	var arrays: Array = coat.mesh.surface_get_arrays(0)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for i in range(0,weights.size(),4):
		_check(absf(weights[i]+weights[i+1]+weights[i+2]+weights[i+3]-1.0) < .0001,"Unnormalized coat skin weights")
	var rest := _surface_samples(arrays[Mesh.ARRAY_VERTEX],arrays[Mesh.ARRAY_INDEX])
	for mode in ["walk","ride","dismount0","mount0","dismount1","mount1","dismount2","mount2","dismount3","mount3"]:
		for frame in 24:
			var wave := TAU*frame/24.0
			if mode.begins_with("mount") or mode.begins_with("dismount"):
				var mounting: bool = mode.begins_with("mount")
				if frame == 0:
					doll.riding = not mounting
					doll.position.y = 0 if mounting else .16
					doll.pedal_phase = int(mode.right(1))*PI*.5
					doll._update_puppet_motion(1.0)
					doll.begin_mount(mounting)
				var t := frame/23.0
				doll.mount_blend = t
				doll.position.y = .16*(smoothstep(0,1,t) if mounting else 1.0-smoothstep(0,1,t))
				doll._update_puppet_motion(1.0/60.0)
			elif mode == "ride":
				doll.riding = true
				doll.pedal_phase = wave
				doll.position.y = .16
				doll._update_puppet_motion(1.0/60.0)
			else:
				doll.position.y = 0
				doll.rig.animate(wave,1.0,"idle",0)
			poses += 1
			for suffix in ["L","R"]:
				var sole: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/shoe%s/FlatSole"%suffix)
				for point in doll.rig.deformed_vertices(sole):
					_check(point.y+doll.position.y >= -.001,"Postal shoe sinks into the road during a transition")
			var points := _surface_samples(doll.rig.deformed_vertices(coat),arrays[Mesh.ARRAY_INDEX])
			for side in ["L","R"]:
				var leg: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/leg%s/Trouser"%side)
				var leg_points: PackedVector3Array = doll.rig.deformed_vertices(leg)
				var indices: PackedInt32Array = leg.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				var bounds := AABB(leg_points[0],Vector3.ZERO)
				for point in leg_points:
					bounds = bounds.expand(point)
				for i in points.size():
					if not bounds.has_point(points[i]):
						continue
					checked_vertices += 1
					if _inside(points[i],leg_points,indices):
						intersections += 1
						var key := "%s %.3f"%[mode,rest[i].y]
						contact_rows[key] = contact_rows.get(key,0)+1
						if intersections <= 6:
							print("COAT_CONTACT mode=",mode," phase=",frame," side=",side," rest=",rest[i]," deformed=",points[i])
	_check(intersections == 0,"Coat vertices penetrate the trousers during walking/cycling")
	print("COAT_CONTACT_ROWS ",contact_rows)
	print("POSTAL_CLOTHING_CHECK poses=",poses," coat_surface_samples=",checked_vertices," intersections=",intersections," failures=",failures.size())
	doll.free()
	quit(0 if failures.is_empty() else 1)


func _surface_samples(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var points := vertices.duplicate()
	for i in range(0,indices.size(),3):
		points.append((vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0)
	return points


func _inside(point: Vector3, vertices: PackedVector3Array, indices: PackedInt32Array) -> bool:
	var hits: Array[float] = []
	for i in range(0,indices.size(),3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		if point.y < minf(a.y,minf(b.y,c.y)) or point.y > maxf(a.y,maxf(b.y,c.y)):
			continue
		if point.z < minf(a.z,minf(b.z,c.z)) or point.z > maxf(a.z,maxf(b.z,c.z)):
			continue
		var hit = Geometry3D.segment_intersects_triangle(point,point+Vector3(3,0,0),a,b,c)
		if hit == null:
			continue
		var duplicate := false
		for x in hits:
			if absf(x-hit.x) < .0001:
				duplicate = true
		if not duplicate:
			hits.append(hit.x)
	return hits.size()%2 == 1
