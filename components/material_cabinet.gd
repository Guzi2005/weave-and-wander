@tool
extends Node3D
## Every material mount holds one ledger package; no decorative stock.
const PAPER = preload("res://shaders/room_paper.gdshader")
const LOWER_BOOKS := [0,1,2,3,5,6,7,8,9]
const UPPER_BOOKS := [10,11,12,13]
const FOLDED_BOOKS := [14,15,16,17]
const ROLLS := [4,18,19,20]
var fabric_mounts: Array[Marker3D] = []
var thread_mounts: Array[Marker3D] = []
var yarn_mounts: Array[Marker3D] = []
var access: Marker3D
var output: Marker3D

func _ready() -> void:
	build()

func _box(label: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = PAPER
	mat.set_shader_parameter("pigment",color)
	part.material_override = mat
	part.position = at
	add_child(part)
	return part

func _mount(label: String, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = label
	marker.position = at
	add_child(marker)
	return marker

func build() -> void:
	for child in get_children(): child.free()
	fabric_mounts.clear()
	thread_mounts.clear()
	yarn_mounts.clear()
	var wood := Color("668b80")
	var cream := Color("e9dfc5")
	_box("Back",Vector3(2.88,2.55,.055),Vector3(0,1.325,-.59),wood)
	for x in [-1.44,1.44]:
		_box("Side",Vector3(.065,2.55,1.22),Vector3(x,1.325,0),wood)
	for y in [.12,2.58]:
		_box("Shelf",Vector3(2.94,.065,1.24),Vector3(0,y,0),cream)
	_box("Cornice",Vector3(3.02,.09,1.28),Vector3(0,2.65,0),wood)
	_box("Divider",Vector3(.055,2.43,1.15),Vector3(.43,1.35,0),wood)
	for y in [.56,1.48,2.42]:
		_box("FabricShelf",Vector3(1.83,.05,1.17),Vector3(-.50,y,0),cream)
	# Spools stand closely together; the shallow support stays behind the stock.
	for row in 5:
		var y := 1.18+row*.275
		_box("ThreadShelf",Vector3(.95,.025,.50),Vector3(.94,y,.18),cream)
		for col in 4:
			thread_mounts.append(_mount("Thread%d" % (row*4+col),Vector3(.595+col*.224,y+.015,.29)))
	# Six cubbies, each containing three individual balls in a small triangular pile.
	for row in 3:
		var y := .15+row*.34
		if row > 0: _box("YarnShelf",Vector3(.95,.022,.55),Vector3(.94,y-.012,.18),cream)
		_box("YarnDivider",Vector3(.022,.32,.53),Vector3(.94,y+.15,.18),cream)
		for col in 2:
			for ball in 3:
				var x: float = .70+col*.47+[-.103,.103,0.0][ball]
				var height := y+(.15 if ball == 2 else 0.0)
				var mount := _mount("Yarn%d" % yarn_mounts.size(),Vector3(x,height,.31))
				mount.rotation.y = (ball-1)*.28
				yarn_mounts.append(mount)
	for index in 21: fabric_mounts.append(_mount("Fabric%d" % index,Vector3.ZERO))
	for index in ROLLS.size():
		var mount := fabric_mounts[ROLLS[index]]
		mount.position = Vector3(-1.15+index*.42,.17,.0)
		mount.rotation.y = PI*.5
	access = _mount("Access",Vector3(1.94,0,1.12))
	output = _mount("Output",Vector3(1.94,1.14,.10))
	_box("ReceivingTable",Vector3(.88,.06,.82),output.position-Vector3(0,.04,0),cream)
	_box("ReceivingLowShelf",Vector3(.78,.04,.74),Vector3(1.94,.25,.10),cream)
	for x in [1.57,2.31]:
		for z in [-.22,.42]:
			_box("ReceivingLeg",Vector3(.055,1.06,.055),Vector3(x,.53,z),wood)
	set_meta("storage_forms",PackedStringArray(["book","roll","spool","yarn"]))
	set_meta("fabric_capacity",21)
	set_meta("thread_capacity",20)

func arrange_fabrics(packages: Dictionary, mounts: Dictionary) -> void:
	# Repack on intake/return, never while the worker extracts a bolt.
	_arrange_row(LOWER_BOOKS,.59,packages,mounts)
	_arrange_row(UPPER_BOOKS,1.51,packages,mounts)
	var y := 1.51
	for index in FOLDED_BOOKS:
		var node := _package_at(fabric_mounts[index],packages,mounts)
		if node == null: continue
		var bounds: AABB = node.display_bounds()
		var basis := Basis(Vector3.BACK,PI*.5)
		var rotated: AABB = Transform3D(basis,Vector3.ZERO)*bounds
		fabric_mounts[index].transform = Transform3D(basis,Vector3(-.53,y,.29)-Vector3(rotated.position.x,rotated.position.y,rotated.get_center().z))
		y += rotated.size.y+.009

func _arrange_row(indices: Array, floor_y: float, packages: Dictionary, mounts: Dictionary) -> void:
	var x := -1.385
	for i in indices.size():
		var mount := fabric_mounts[indices[i]]
		var node := _package_at(mount,packages,mounts)
		if node == null: continue
		var bounds: AABB = node.display_bounds()
		var angle := .19 if i == indices.size()-1 else 0.0
		var basis := Basis(Vector3.BACK,angle)
		var rotated: AABB = Transform3D(basis,Vector3.ZERO)*bounds
		mount.transform = Transform3D(basis,Vector3(x,floor_y,.29)-Vector3(rotated.position.x,rotated.position.y,rotated.get_center().z))
		x += rotated.size.x+.009

func _package_at(mount: Marker3D, packages: Dictionary, mounts: Dictionary) -> Node3D:
	for id in mounts:
		if mounts[id] == mount: return packages[id]
	return null

func fabric_mount(index: int) -> Marker3D:
	return fabric_mounts[index] if index >= 0 and index < fabric_mounts.size() else null

func thread_mount(index: int) -> Marker3D:
	return thread_mounts[index] if index >= 0 and index < thread_mounts.size() else null
