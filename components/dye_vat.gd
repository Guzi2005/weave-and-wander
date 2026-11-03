@tool
extends Node3D
## Hollow ceramic vats, rinse vessel and a working drying frame.
const PAPER = preload("res://shaders/room_paper.gdshader")
var bath: MeshInstance3D
var paddle: Node3D
var sheet: MeshInstance3D

func _ready() -> void:
	build()

func build() -> void:
	if get_child_count() > 0: return
	_box("DrainDeck",Vector3(3.2,.10,1.3),Vector3(0,.16,0),Color("8b7761"))
	for i in 2:
		var x := -.78+i*1.5
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		var profile := [Vector2(.38,.22),Vector2(.53,.40),Vector2(.56,1.08),Vector2(.53,1.14),Vector2(.47,1.14),Vector2(.47,.40),Vector2(.34,.30)]
		for row in profile.size()-1:
			for seg in 48:
				for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
					var p: Vector2 = profile[row+corner.y]
					var a: float = (seg+corner.x)*TAU/48.0
					s.add_vertex(Vector3(x+sin(a)*p.x,p.y,cos(a)*p.x))
		s.generate_normals()
		_mesh("DyeVat" if i == 0 else "RinseVat",s.commit(),Vector3.ZERO,Color("b7c5b2") if i == 0 else Color("d5d3bb"))
		var liquid := CylinderMesh.new()
		liquid.top_radius = .465
		liquid.bottom_radius = .465
		liquid.height = .018
		liquid.radial_segments = 48
		var node := _mesh("DyeBath" if i == 0 else "RinseWater",liquid,Vector3(x,.89,0),Color("537e8b") if i == 0 else Color("9eb9b4"))
		if i == 0: bath = node
		for sign_value in [-1,1]:
			_box("VatHandle",Vector3(.17,.12,.15),Vector3(x+sign_value*.57,.96,0),Color("8c9f92"))
	paddle = _box("StirringPaddle",Vector3(.09,1.0,.16),Vector3(-.58,1.24,.05),Color("ac865a"))
	paddle.rotation.z = -.24
	for x in [-1.43,1.43]:
		_box("DryingPost",Vector3(.09,2.72,.10),Vector3(x,1.52,-.57),Color("987957"))
	_box("DryingRail",Vector3(2.95,.08,.10),Vector3(0,2.84,-.57),Color("987957"))
	var cloth := PlaneMesh.new()
	cloth.size = Vector2(1.13,1.05)
	sheet = _mesh("ProcessCloth",cloth,Vector3(-.78,.94,0),Color.WHITE)
	sheet.hide()
	for x in [-.45,.45]:
		_box("DryingClip",Vector3(.055,.14,.06),Vector3(x,2.80,-.52),Color("d5bd85"))

func show_stage(stage: String, progress: float, descriptor: Dictionary, target: Color) -> void:
	bath.material_override.set_shader_parameter("pigment",target.darkened(.2))
	sheet.visible = stage in ["unwind","dye","rinse","dry","rewrap"]
	if not sheet.visible: return
	var data := descriptor.duplicate(true)
	data.pigment = (descriptor.pigment as Color).lerp(target,progress if stage == "dye" else (0.0 if stage == "unwind" else 1.0))
	sheet.material_override = preload("res://scripts/material_appearance.gd").make_material(data,true)
	if stage in ["dry","rewrap"]:
		sheet.rotation = Vector3(PI*.5,0,0)
		sheet.position = Vector3(0,2.27,-.51)
	else:
		sheet.rotation = Vector3(.10*sin(progress*TAU*3),0,.12)
		sheet.position = Vector3(.72 if stage == "rinse" else -.78,.91+.12*sin(progress*TAU*2),0)
	paddle.rotation.z = -.24+.12*sin(progress*TAU*4)

func _mesh(label: String, mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = PAPER
	mat.set_shader_parameter("pigment",color)
	node.material_override = mat
	add_child(node)
	node.position = at
	return node

func _box(label: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(label,mesh,at,color)


