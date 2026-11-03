extends "res://scripts/shop_room.gd"

const DOOR_Z := 3.76
const APPROACH := Vector3(0,0,5.8)
const INSIDE := Vector3(0,0,3.25)
const ROAD_Z := 7.4
var facades: Node3D
var door_pivot: Node3D
var _facade_materials: Array[ShaderMaterial] = []
var _door_open := 0.0
var _door_wait := 0.0
var exterior_amount := 0.0
var _reflection_door: Node3D
var _shop_sign: Label3D
var _sign_pivot: Node3D
var _sign_target := 0.0
var _sign_angle := 0.0
var sign_is_open := true

func _glazing(parent: Node, title: String, size: Vector2, at: Vector3) -> MeshInstance3D:
	var pane := super._glazing(parent,title,size,at)
	var reflection := preload("res://scripts/street_glass_reflection.gd").new()
	reflection.name = "StreetGlassReflection"
	reflection.pane = pane
	reflection.mirror_size = size
	pane.add_child(reflection)
	return pane


func build() -> void:
	_paving()
	facades = _group("StreetFacades",Vector3.ZERO)
	for i in 3:
		_facade((i-1)*14.4,i)
	# Facade materials are independent of the street and room materials.
	var copies := {}
	for mesh in facades.find_children("*","MeshInstance3D",true,false):
		var original: ShaderMaterial = mesh.material_override
		if not copies.has(original):
			copies[original] = original.duplicate()
			_facade_materials.append(copies[original])
		mesh.material_override = copies[original]
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_entrance_mat()
	_reflection_interior()
	set_exterior(0.0)


func _reflection_interior() -> void:
	# Cutaway presentation removes the front wall from the player's view, not
	# from the enclosed room seen in a mirror. Share its geometry on a mirror-only layer.
	var shell := _group("ReflectionInteriorShell", Vector3.ZERO)
	for index in facades.get_child_count():
		var source: Node3D = facades.get_child(index)
		var interior := source.duplicate(Node.DUPLICATE_GROUPS) as Node3D
		for reflection in interior.find_children("StreetGlassReflection","Node3D",true,false):
			reflection.free()
		shell.add_child(interior)
		for label in interior.find_children("*", "Label3D", true, false):
			label.layers = 8
		for mesh in interior.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 8
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := mesh.material_override.duplicate() as ShaderMaterial
			if mesh.is_in_group("shop_window_panels"):
				mesh.remove_from_group("shop_window_panels")
				mat = ShaderMaterial.new()
				mat.shader = GLASS
			mat.set_shader_parameter("fold_enabled", false)
			if str(mesh.name) in ["UpperWall", "SillWall", "InnerPier", "OuterPier", "FrontGable"]:
				mat.set_shader_parameter("pigment", [MINT, PINK, Color("dedabf")][index])
			mesh.material_override = mat
		if index == 1:
			_reflection_door = interior.get_node("EntranceDoor")


func _paving() -> void:
	var ground := _group("BluestoneStreet",Vector3.ZERO)
	_box(ground,"StoneBed",Vector3(43.2,.15,9),Vector3(0,-.13,8.15),Color("879b9a"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8217
	var palette := [Color("9eafad"),Color("a9b8b4"),Color("8da4a5"),Color("b5c1ba"),Color("99a8aa")]
	for color in 5:
		var transforms: Array[Transform3D] = []
		for row in 9:
			for col in 28:
				if posmod(hash(Vector2i(col,row)),5) != color:
					continue
				var at := Vector3(-20.6+col*1.5+(row%2)*.25,-.022,4.15+row*.96)
				var basis := Basis(Vector3.UP,rng.randf_range(-.012,.012)).scaled(Vector3(rng.randf_range(.96,1.0),1,rng.randf_range(.96,1.0)))
				transforms.append(Transform3D(basis,at))
		var batch := MultiMeshInstance3D.new()
		batch.name = "WornStoneBatch%d"%color
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _stone_mesh()
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i,transforms[i])
		batch.multimesh = multi
		batch.material_override = _material(palette[color])
		# The bevel receives light; sub-pixel stone self-shadows cause jagged black seams.
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground.add_child(batch)
	for i in 28:
		_box(ground,"Curb",Vector3(1.45,.12,.30),Vector3(-20.25+i*1.5,-.02,4.05),Color("bcc8bf"))


func _stone_mesh() -> ArrayMesh:
	var outline := PackedVector2Array([Vector2(-.66,-.455),Vector2(.66,-.455),Vector2(.73,-.385),Vector2(.73,.385),Vector2(.66,.455),Vector2(-.66,.455),Vector2(-.73,.385),Vector2(-.73,-.385)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inset := PackedVector2Array()
	for point in outline:
		inset.append(point * Vector2(.94,.90))
	for index in Geometry2D.triangulate_polygon(inset):
		var point := inset[index]
		surface.set_normal(Vector3.UP)
		surface.set_uv(point)
		surface.add_vertex(Vector3(point.x,.025,point.y))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var c := inset[(i+1)%outline.size()]
		var d := inset[i]
		var normal := Vector3(b.y-a.y,0,a.x-b.x).normalized()
		var rings := [
			[Vector3(a.x,-.065,a.y),Vector3(b.x,-.065,b.y),Vector3(b.x,-.012,b.y),Vector3(a.x,-.012,a.y)],
			[Vector3(a.x,-.012,a.y),Vector3(b.x,-.012,b.y),Vector3(c.x,.025,c.y),Vector3(d.x,.025,d.y)],
		]
		for ring in 2:
			for j in [0,1,2,0,2,3]:
				var point: Vector3 = rings[ring][j]
				surface.set_normal(normal if ring == 0 else (normal*.65+Vector3.UP).normalized())
				surface.set_uv(Vector2(point.x,point.z))
				surface.add_vertex(point)
	return surface.commit()


func _facade(x: float, kind: int) -> void:
	var front := _group("Facade%d"%kind,Vector3(x,0,DOOR_Z),facades)
	var colors := [Color("b8ccc0"),Color("dfa6a4"),Color("dedabf")]
	var frames := [Color("668c88"),Color("a75561"),Color("7f8496")]
	var color: Color = colors[kind]
	var frame: Color = frames[kind]
	_shape(front,"FrontGable",PackedVector2Array([Vector2(-7.2,4.72),Vector2(0,6.62),Vector2(7.2,4.72)]),Vector3(0,0,-.02),color)
	_box(front,"UpperWall",Vector3(14.4,1.48,.14),Vector3(0,4.01,0),color)
	for side in [-1,1]:
		_box(front,"SillWall",Vector3(6.08,.84,.14),Vector3(side*4.16,.42,0),color)
		_box(front,"InnerPier",Vector3(.90,2.42,.14),Vector3(side*1.6,2.05,0),color)
		_box(front,"OuterPier",Vector3(1.42,2.42,.14),Vector3(side*6.49,2.05,0),color)
		var win := _group("DisplayWindow",Vector3(side*3.92,2.04,.12),front)
		var glass := _glazing(win,"Glass",Vector2(3.82,2.37),Vector3.ZERO)
		glass.add_to_group("shop_window_panels")
		for vx in [-1.95,0,1.95]:
			_box(win,"Mullion",Vector3(.09,2.46,.12),Vector3(vx,0,.05),frame)
		for vy in [-1.23,1.23]:
			_box(win,"Rail",Vector3(4,.09,.18),Vector3(0,vy,.05),frame)
		_box(win,"Sill",Vector3(4.1,.10,.38),Vector3(0,-1.28,.09),frame)
		for j in 3:
			var palette := [GREEN,GOLD,BLUE,RED,PLUM]
			_shape(win,"FabricDisplay",PackedVector2Array([Vector2(-.23,.63),Vector2(.23,.63),Vector2(.40,-.66),Vector2(-.4,-.66)]),Vector3(-1.15+j*1.12,-.03,-.16),palette[(j+kind)%5],1)
		_box(front,"Plinth",Vector3(6.08,.25,.20),Vector3(side*4.16,.125,.04),frame)
	for dx in [-1.12,1.12]:
		_box(front,"DoorPost",Vector3(.12,3.3,.24),Vector3(dx,1.65,.08),frame)
	_box(front,"DoorLintel",Vector3(2.36,.15,.26),Vector3(0,3.33,.08),frame)
	_box(front,"DoorTransom",Vector3(2.08,.14,.06),Vector3(0,3.20,.09),Color("b7d3cc"))
	_box(front,"Cornice",Vector3(14.4,.17,.29),Vector3(0,4.70,.03),frame)
	var door := _group("EntranceDoor",Vector3(-1.04,0,.09),front)
	_box(door,"LeafBottom",Vector3(2.08,1.01,.09),Vector3(1.04,.505,0),frame)
	_box(door,"LeafTop",Vector3(2.08,.13,.09),Vector3(1.04,3.055,0),frame)
	for stile_x in [.095, 1.985]:
		_box(door,"LeafStile",Vector3(.19,1.98,.09),Vector3(stile_x,2.0,0),frame)
	var door_glass := _glazing(door,"DoorGlass",Vector2(1.70,1.98),Vector3(1.04,2.0,.02))
	door_glass.add_to_group("shop_window_panels")
	_box(door,"LowerPanel",Vector3(1.72,.66,.035),Vector3(1.04,.44,.065),color)
	_box(door,"Handle",Vector3(.075,.26,.065),Vector3(1.86,1.2,.115),GOLD)
	if kind == 1:
		door_pivot = door
		# Fixed beside the entrance, within a standing character's reach.
		var hanger := _group("BusinessSignHanger", Vector3(1.58, 1.92, .20), front)
		for cord_x in [-.36, .36]:
			_box(hanger, "Cord", Vector3(.018,.32,.018), Vector3(cord_x,.28,0), Color("705846"))
		_sign_pivot = _group("BusinessSignPivot", Vector3.ZERO, hanger)
		_box(_sign_pivot, "WoodenBoard", Vector3(1.08,.49,.055), Vector3.ZERO, Color("78533b"), 1)
		for y in [-.20,.20]:
			_box(_sign_pivot, "PaintedBorder", Vector3(.98,.018,.008), Vector3(0,y,.032), GOLD)
			_box(_sign_pivot, "BackBorder", Vector3(.98,.018,.008), Vector3(0,y,-.032), GOLD)
		_shop_sign = Label3D.new()
		_shop_sign.name = "OpenClosedSign"
		_shop_sign.text = "OPEN"
		_shop_sign.font_size = 56
		_shop_sign.pixel_size = .003
		_shop_sign.modulate = Color("f3df9d")
		_shop_sign.outline_size = 3
		_shop_sign.outline_modulate = Color("633f45")
		_shop_sign.position = Vector3(0, 0, .036)
		_sign_pivot.add_child(_shop_sign)
		var back := _shop_sign.duplicate() as Label3D
		back.name = "ClosedSignFace"
		back.text = "CLOSED"
		back.font_size = 45
		back.position.z = -.036
		back.rotation.y = PI
		_sign_pivot.add_child(back)


func _entrance_mat() -> void:
	var mat := _group("ShopEntranceMat",Vector3(0,.066,2.84))
	_box(mat,"WovenBase",Vector3(2.0,.035,1.12),Vector3.ZERO,Color("b35864"),1)
	for x in [-.85,.85]:
		_box(mat,"EdgeStripe",Vector3(.06,.009,1.04),Vector3(x,.022,0),GOLD)
	for i in 5:
		var diamond := _box(mat,"WovenDiamond",Vector3(.20,.008,.20),Vector3(-.58+i*.29,.024,0),WHITE)
		diamond.rotation.y = PI*.25
	for side in [-1,1]:
		for j in 12:
			_box(mat,"Fringe",Vector3(.055,.01,.14),Vector3(-.90+j*.163,.0,side*.59),GOLD)
	_box(self,"EntryThreshold",Vector3(2.16,.055,.28),Vector3(0,.025,DOOR_Z),Color("c8cabc"))


func set_exterior(amount: float) -> void:
	exterior_amount = amount
	facades.visible = amount > .001
	for mat in _facade_materials:
		mat.set_shader_parameter("visibility",amount)


func set_shop_open(value: bool) -> void:
	sign_is_open = value
	_sign_target = 0.0 if value else PI


func update_door(delta: float, people: Array) -> void:
	_sign_angle = move_toward(_sign_angle, _sign_target, delta * PI)
	for pivot in find_children("BusinessSignPivot", "Node3D", true, false):
		pivot.rotation.y = _sign_angle
	var nearby := false
	for person in people:
		if is_instance_valid(person) and person.visible and absf(person.global_position.x) < 1.35 and absf(person.global_position.z-DOOR_Z) < 1.7:
			nearby = true
	if nearby:
		_door_wait = .9
	else:
		_door_wait = maxf(0,_door_wait-delta)
	_door_open = move_toward(_door_open,1.0 if _door_wait > 0 else 0.0,delta*3.6)
	door_pivot.rotation.y = -deg_to_rad(95)*smoothstep(0,1,_door_open)
	if is_instance_valid(_reflection_door):
		_reflection_door.rotation = door_pivot.rotation


func customer_path(from: Vector3, to: Vector3, shop: Node3D) -> PackedVector3Array:
	var outside_from := from.z > 3.4
	var outside_to := to.z > 3.4
	if outside_from and outside_to:
		return PackedVector3Array([Vector3(to.x,0,from.z),to])
	if not outside_from and not outside_to:
		return shop.route(from,to)
	var result := PackedVector3Array()
	if outside_from:
		var interior: PackedVector3Array = shop.route(shop.to_local(INSIDE), shop.to_local(to))
		if interior.is_empty():
			return result
		if absf(from.x) > 1.0:
			result.append(Vector3(0,0,from.z))
		result.append(APPROACH)
		result.append(Vector3(0,0,DOOR_Z))
		result.append(INSIDE)
		for point in interior:
			result.append(shop.to_global(point))
	else:
		var interior: PackedVector3Array = shop.route(shop.to_local(from), shop.to_local(INSIDE))
		if interior.is_empty():
			return result
		for point in interior:
			result.append(shop.to_global(point))
		result.append(Vector3(0,0,DOOR_Z))
		result.append(APPROACH)
		result.append(Vector3(0,0,to.z))
		result.append(to)
	return result
