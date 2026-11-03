extends Node3D

const CLOTH = preload("res://shaders/upholstery.gdshader")


func build(size: Vector3, color: Color, ink: Color, floral := false) -> void:
	var material := ShaderMaterial.new()
	material.shader = CLOTH
	material.set_shader_parameter("pigment",color)
	material.set_shader_parameter("ink",ink)
	material.set_shader_parameter("cloth_size",Vector2(size.x,size.z))
	material.set_shader_parameter("floral",1.0 if floral else 0.0)
	var body := MeshInstance3D.new()
	body.name = "TailoredCushion"
	body.mesh = rounded_mesh(size,minf(size.y*.43,.075),.022)
	body.material_override = material
	add_child(body)
	# A continuous sewn welt follows the padded edge, rather than raised decorative bars.
	var section := PackedVector3Array()
	var radius := .065
	for corner in 4:
		var center := Vector2((size.x*.5-radius)*(-1 if corner in [0,3] else 1),(size.z*.5-radius)*(-1 if corner in [0,1] else 1))
		for sample in 9:
			var angle := PI+corner*PI*.5+sample*PI/16.0
			section.append(Vector3(center.x+cos(angle)*radius,0,center.y+sin(angle)*radius))
	section.append(section[0])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in section.size()-1:
		for side in 6:
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var at: int = index+corner.x
				var direction := (section[mini(at+1,section.size()-1)]-section[maxi(at-1,0)]).normalized()
				var outward := direction.cross(Vector3.UP).normalized()
				var angle: float = (side+corner.y)*TAU/6.0
				var normal := outward*cos(angle)+Vector3.UP*sin(angle)
				tool.set_normal(normal)
				tool.add_vertex(section[at]+normal*.008)
	var welt := MeshInstance3D.new()
	welt.name = "SewnWelt"
	welt.mesh = tool.commit()
	var trim := material.duplicate()
	trim.set_shader_parameter("pigment",ink.lightened(.25))
	trim.set_shader_parameter("ink",ink.lightened(.25))
	welt.material_override = trim
	add_child(welt)


static func rounded_mesh(size: Vector3, radius: float, loft := 0.0) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size*.5
	var inner := half-Vector3.ONE*radius
	var steps := 20 if loft > 0.0 else 6
	for axis in 3:
		var u_axis := (axis+1)%3
		var v_axis := (axis+2)%3
		for sign_value in [-1.0,1.0]:
			for row in steps:
				for column in steps:
					var corners := [Vector2i(0,0),Vector2i(0,1),Vector2i(1,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]
					if sign_value < 0.0: corners.reverse()
					for corner in corners:
						var p := Vector3.ZERO
						p[axis] = half[axis]*sign_value
						p[u_axis] = (float(column+corner.x)/steps*2.0-1.0)*half[u_axis]
						p[v_axis] = (float(row+corner.y)/steps*2.0-1.0)*half[v_axis]
						var nearest := p.clamp(-inner,inner)
						var normal := (p-nearest).normalized()
						p = nearest+normal*radius
						var bulge := (1.0-pow(p.x/half.x,2))*(1.0-pow(p.z/half.z,2))*loft
						p.y += normal.y*bulge
						tool.set_normal(normal)
						tool.set_uv(Vector2(p.x/size.x+.5,p.z/size.z+.5))
						tool.add_vertex(p)
	return tool.commit()
