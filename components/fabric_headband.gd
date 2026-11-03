extends RefCounted

static func build(min_width: float, max_width: float) -> Dictionary:
	var narrow := clampf(min_width,.012,.12)
	var broad := clampf(max_width,narrow,.18)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in 65:
		var t := row/64.0
		var angle := lerpf(-.12,PI+.12,t)
		var width := lerpf(narrow,broad,pow(sin(PI*t),1.2))
		for side in [-1.0,1.0]:
			vertices.append(Vector3(cos(angle)*.285,.29+sin(angle)*.313,side*width*.5-.035))
	for row in 64:
		var a := row*2
		indices.append_array(PackedInt32Array([a,a+2,a+1,a+1,a+2,a+3]))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in indices:
		surface.set_uv(Vector2(float(i/2)/64.0,float(i%2)))
		surface.add_vertex(vertices[i])
	surface.generate_normals()
	var arrays := surface.commit_to_arrays()
	return {"vertices":arrays[Mesh.ARRAY_VERTEX],"normals":arrays[Mesh.ARRAY_NORMAL],"indices":PackedInt32Array(range(arrays[Mesh.ARRAY_VERTEX].size()))}
