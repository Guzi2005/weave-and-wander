@tool
extends Node3D

const PAPER = preload("res://shaders/room_paper.gdshader")
const BLUE = Color("6e9bac")
const CREAM = Color("f5f2e9")
const METAL = Color("777d79")
var _materials := {}
var loaded_fabric_id := ""
var loaded_thread_id := ""

func set_work_materials(fabric: Dictionary, thread: Dictionary) -> void:
	loaded_fabric_id = str(fabric.get("id",""))
	loaded_thread_id = str(thread.get("id",""))
	get_node("FabricUnderFoot").material_override = preload("res://scripts/material_appearance.gd").make_material(fabric)
	for child in get_children():
		if str(child.name).begins_with("ThreadPath"):
			child.material_override = _material(thread.get("pigment",CREAM))
			child.visible = true

func clear_thread() -> void:
	loaded_thread_id = ""
	for child in get_children():
		if str(child.name).begins_with("ThreadPath"): child.hide()


func _ready() -> void:
	build()


func _material(color: Color) -> Material:
	if not _materials.has(color):
		var mat := ShaderMaterial.new()
		mat.shader = PAPER
		mat.set_shader_parameter("pigment", color)
		_materials[color] = mat
	return _materials[color]


func _mesh(label: String, shape: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = shape
	part.material_override = _material(color)
	part.position = at
	add_child(part)
	return part


func _box(label: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _mesh(label, shape, at, color)


func _cylinder(label: String, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 32
	return _mesh(label, shape, at, color)


func _thread(points: Array[Vector3]) -> void:
	for index in points.size() - 1:
		var delta := points[index + 1] - points[index]
		var strand := _cylinder("ThreadPath%d" % index, .006, delta.length(), (points[index] + points[index + 1]) * .5, CREAM)
		strand.quaternion = Quaternion(Vector3.UP, delta.normalized())


func build() -> void:
	for child in get_children():
		child.free()
	_box("Bed", Vector3(1.15,.08,.52), Vector3(0,.04,0), BLUE)
	_box("NeedlePlate", Vector3(.38,.012,.34), Vector3(-.30,.087,.06), METAL)
	for i in 4:
		_box("FeedDog", Vector3(.022,.009,.14), Vector3(-.35+i*.032,.096,.06), CREAM)
	# Extruded, chamfered C-shaped housing leaves the sewing throat genuinely open.
	var profile := PackedVector2Array([Vector2(.17,.08),Vector2(.48,.08),Vector2(.50,.16),Vector2(.50,.71),Vector2(.44,.79),Vector2(-.41,.79),Vector2(-.48,.72),Vector2(-.48,.43),Vector2(-.32,.43),Vector2(-.27,.60),Vector2(.15,.60),Vector2(.17,.55)])
	var triangles := Geometry2D.triangulate_polygon(profile)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for index in range(0,triangles.size(),3):
			var order := [0,1,2] if side > 0 else [2,1,0]
			for corner in order:
				var p := profile[triangles[index+corner]]
				surface.add_vertex(Vector3(p.x,p.y,side*.16))
	for index in profile.size():
		var a := profile[index]
		var b := profile[(index+1)%profile.size()]
		for p in [Vector3(a.x,a.y,-.16),Vector3(b.x,b.y,-.16),Vector3(b.x,b.y,.16),Vector3(a.x,a.y,-.16),Vector3(b.x,b.y,.16),Vector3(a.x,a.y,.16)]:
			surface.add_vertex(p)
	surface.generate_normals()
	_mesh("EnamelHousing",surface.commit(),Vector3.ZERO,BLUE)
	var wheel := _cylinder("Handwheel",.20,.10,Vector3(.57,.59,0),CREAM)
	wheel.rotation.z = PI*.5
	_cylinder("WheelHub",.075,.13,Vector3(.61,.59,0),METAL).rotation.z = PI*.5
	_cylinder("StitchDial",.085,.035,Vector3(.27,.48,.18),CREAM).rotation.x = PI*.5
	for i in 8:
		var a := TAU*i/8.0
		_box("DialMark",Vector3(.01,.026,.008),Vector3(.27+sin(a)*.063,.48+cos(a)*.063,.202),METAL).rotation.z = -a
	_box("ReverseLever",Vector3(.10,.025,.045),Vector3(.27,.32,.18),CREAM)
	_cylinder("NeedleBar",.019,.32,Vector3(-.39,.32,.03),METAL)
	_cylinder("Needle",.007,.12,Vector3(-.39,.13,.03),METAL)
	_box("PresserFoot",Vector3(.11,.025,.13),Vector3(-.36,.11,.05),METAL)
	_cylinder("SpoolPin",.012,.22,Vector3(.18,.88,0),METAL)
	var spool := preload("res://components/thread_spool.gd").new()
	spool.name = "ThreadSpool"
	spool.position = Vector3(.18,.90,0)
	spool.build(.08,.14,Color("b94f60"))
	add_child(spool)
	_cylinder("TensionKnob",.045,.045,Vector3(-.29,.61,.19),METAL).rotation.x = PI*.5
	_thread([Vector3(.18,.95,.08),Vector3(-.20,.80,.19),Vector3(-.29,.61,.22),Vector3(-.39,.43,.20),Vector3(-.39,.13,.03)])
	_box("FabricUnderFoot",Vector3(.28,.008,.40),Vector3(-.38,.099,.19),Color("ddafb2"))
