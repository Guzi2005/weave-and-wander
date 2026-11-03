extends Node3D

const PAPER = preload("res://shaders/room_paper.gdshader")
const Pad = preload("res://components/upholstered_pad.gd")
const WOOD := Color("795441")
const SEAT_HEIGHT := .72
const SEAT_SPACING := 1.22
var reservations: Dictionary = {}


func _ready() -> void:
	build()


func _process(_delta: float) -> void:
	_clean()


func build() -> void:
	_box("SeatFrame",Vector3(4.0,.14,1.12),Vector3(0,.57,0),WOOD)
	for side in [-1.0,1.0]:
		for z in [-.43,.43]:
			var leg := _box("TaperedLeg",Vector3(.13,.61,.14),Vector3(side*1.87,.305,z),WOOD.darkened(.08))
			leg.rotation.z = side*.045
		_box("BackPost",Vector3(.13,1.28,.13),Vector3(side*1.9,1.12,-.49),WOOD)
		_box("ArmPost",Vector3(.11,.52,.11),Vector3(side*1.9,.89,.39),WOOD)
		_box("ArmRest",Vector3(.18,.10,1.06),Vector3(side*1.9,1.15,-.02),WOOD.lightened(.05))
	var outline := PackedVector2Array([Vector2(-1.86,.89),Vector2(1.86,.89),Vector2(1.86,1.53),Vector2(1.55,1.62),
		Vector2(1.1,1.60),Vector2(.6,1.74),Vector2(.18,1.70),Vector2(0,1.76),Vector2(-.35,1.71),Vector2(-.9,1.63),Vector2(-1.5,1.65),Vector2(-1.86,1.54)])
	_profile("ScallopedBack",outline,.105,-.50,WOOD)
	_profile("FrontApron",PackedVector2Array([Vector2(-1.84,.55),Vector2(1.84,.55),Vector2(1.84,.38),Vector2(1.5,.34),
		Vector2(1.25,.39),Vector2(.1,.36),Vector2(-.9,.40),Vector2(-1.5,.35),Vector2(-1.84,.39)]),.08,.49,WOOD.lightened(.03))
	var cushion := Pad.new()
	cushion.name = "StripedLinenSeat"
	add_child(cushion)
	cushion.position.y = SEAT_HEIGHT-.095
	cushion.build(Vector3(3.68,.16,1.01),Color("d4d0bf"),Color("52636e"))
	for index in 3:
		var x := (index-1)*SEAT_SPACING
		_box("Basket",Vector3(1.06,.32,.78),Vector3(x,.20,.05),Color("b5a17d"),1)
		for row in 6:
			_box("BasketWeave",Vector3(1.08,.018,.018),Vector3(x,.065+row*.05,.45),Color("c4b28c"))
		for column in 14:
			_box("BasketUpright",Vector3(.018,.29,.025),Vector3(x-.49+column*.075,.20,.452),Color("a68f6c"))
		_box("BasketHandle",Vector3(.22,.06,.025),Vector3(x,.27,.47),WOOD.darkened(.18))
	for index in 2:
		var pillow := Pad.new()
		pillow.name = "BotanicalPillow" if index == 0 else "LinenPillow"
		add_child(pillow)
		pillow.build(Vector3(.64,.20,.55),Color("8ea6b1") if index == 0 else Color("e4dcc7"),Color("425e69") if index == 0 else Color("b6a68c"),index == 0)
		pillow.position = Vector3(-1.48+index*.65,1.03,-.28)
		pillow.rotation_degrees = Vector3(78,0,-9 if index == 0 else 12)
	set_meta("rest_capacity",3)


func _box(label: String, size: Vector3, at: Vector3, color: Color, pattern := 0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = Pad.rounded_mesh(size,minf(.018,minf(size.x,minf(size.y,size.z))*.22))
	node.position = at
	node.material_override = _material(color,pattern)
	add_child(node)
	return node


func _material(color: Color, pattern := 0) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = PAPER
	result.set_shader_parameter("pigment",color)
	result.set_shader_parameter("pattern",float(pattern))
	return result


func _profile(label: String, points: PackedVector2Array, depth: float, z: float, color: Color) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(points)
	for side in [-1.0,1.0]:
		for index in range(0,triangles.size(),3):
			for corner in ([0,1,2] if side < 0 else [2,1,0]):
				var p := points[triangles[index+corner]]
				tool.add_vertex(Vector3(p.x,p.y,z+side*depth*.5))
	for index in points.size():
		var a := points[index]
		var b := points[(index+1)%points.size()]
		for v in [Vector3(a.x,a.y,z-depth*.5),Vector3(a.x,a.y,z+depth*.5),Vector3(b.x,b.y,z+depth*.5),
			Vector3(a.x,a.y,z-depth*.5),Vector3(b.x,b.y,z+depth*.5),Vector3(b.x,b.y,z-depth*.5)]:
			tool.add_vertex(v)
	tool.generate_normals()
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = tool.commit()
	part.material_override = _material(color)
	add_child(part)


func _clean() -> void:
	for id in reservations.keys():
		var actor: Node3D = reservations[id].actor.get_ref()
		if not is_instance_valid(actor) or (reservations[id].get("departing",false) and actor._rest_blend <= 0.0):
			reservations[id].entry.queue_free()
			reservations[id].support.queue_free()
			reservations.erase(id)


func available_span(wants_nap: bool) -> Array:
	_clean()
	var used: Array = []
	for reservation in reservations.values():
		used.append_array(reservation.seats)
	if wants_nap:
		for index in 2:
			if index not in used and index+1 not in used:
				return [index,index+1]
	for index in 3:
		if index not in used:
			return [index]
	return []


func reserve(actor: Node3D, wants_nap: bool) -> Marker3D:
	var id := actor.get_instance_id()
	_clean()
	if reservations.has(id):
		return reservations[id].entry
	var seats := available_span(wants_nap)
	if seats.is_empty():
		return null
	var x: float = ((seats.front()+seats.back())*.5-1.0)*SEAT_SPACING
	var entry := Marker3D.new()
	entry.name = "RestApproach_%d"%id
	add_child(entry)
	entry.position = Vector3(x,0,1.28)
	var support := Marker3D.new()
	support.name = "RestSupport_%d"%id
	add_child(support)
	support.position = Vector3(x+(.25 if seats.size() == 2 else 0.0),SEAT_HEIGHT+(.32 if seats.size() == 2 else .20),.18 if seats.size() == 2 else .30)
	if seats.size() == 2:
		var pillow := Pad.new()
		pillow.name = "NapPillow"
		support.add_child(pillow)
		pillow.position = Vector3(-1.10,SEAT_HEIGHT+.07-support.position.y,.02)
		pillow.build(Vector3(.64,.17,.52),Color("e4dcc7"),Color("b6a68c"))
	reservations[id] = {"actor":weakref(actor),"seats":seats,"entry":entry,"support":support,"mode":"nap" if seats.size() == 2 else "sit"}
	return entry


func support_actor(actor: Node3D) -> void:
	var reservation: Dictionary = reservations.get(actor.get_instance_id(),{})
	if reservation.is_empty() or actor.rest_departing or reservation.get("departing",false): return
	actor.rest_support = weakref(reservation.support)
	actor.rest_mode = reservation.mode
	actor.set_activity("napping" if reservation.mode == "nap" else "resting")


func release(actor: Node3D) -> void:
	var id := actor.get_instance_id()
	if not reservations.has(id): return
	actor.rest_support = null
	actor.rest_departing = false
	if actor._rest_blend > 0.0:
		reservations[id].departing = true
		return
	reservations[id].entry.queue_free()
	reservations[id].support.queue_free()
	reservations.erase(id)


func mode_for(actor: Node3D) -> String:
	return reservations.get(actor.get_instance_id(),{}).get("mode","")
