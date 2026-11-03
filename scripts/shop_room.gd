@tool
extends Node3D

const Art = preload("res://scripts/paper_art.gd")
const PAPER = preload("res://shaders/room_paper.gdshader")
const GLASS = preload("res://shaders/miniature_glass.gdshader")
const INK = Color("4b4855")
const GREEN = Color("528c80")
const MINT = Color("bfd6cc")
const PINK = Color("ddafb2")
const RED = Color("b94f60")
const GOLD = Color("d8ad5f")
const WHITE = Color("f5f2e9")
const BLUE = Color("6e9bac")
const PLUM = Color("77566e")
const ENTRY = Vector3(0, 0.0, 3.25)
const CHECKOUT = Vector3(1.75, 0.0, .65)
const FITTING = Vector3(5.60, 0.0, -1.2)
const FITTING_QUEUE = Vector3(4.85, 0.0, 1.15)
const MIRROR = Vector3(3.65, 0.0, 0.5)
const BROWSE_SPOTS = [Vector3(-5.80,0,1.15), Vector3(-4.75,0,1.15), Vector3(-3.70,0,1.15), Vector3(-5.65,0,2.05)]

var obstacles: Array[Rect2] = []
var _materials: Dictionary = {}
var _grid := AStarGrid2D.new()
var fitting_room: Node3D
var checkout_queue: Node3D
var checkout_exchange: Node3D
var _footprints: Array[Dictionary] = []
var _blocked_polygons: Array[PackedVector2Array] = []
var _anchors: Dictionary = {}
var navigation_revision := 0


func _ready() -> void:
	build()


func build() -> void:
	for child in get_children():
		child.free()
	obstacles.clear()
	_footprints.clear()
	_anchors.clear()
	_architecture()
	var roof := preload("res://scripts/shop_roof.gd").new()
	roof.name = "HingedRoof"
	add_child(roof)
	_window()
	_display()
	_notions()
	_counter()
	_fitting()
	_small_goods()
	_wall_details()
	_rest()
	_setup_interaction_anchors()
	refresh_navigation(true)


func facility_definitions() -> Array:
	return [
		["rack", "成衣陈列", Vector3(-4.35, 0, 0.05), Vector3(-4.35, 2.8, -0.5), GREEN, "stocking", 5.4],
		["hats", "帽饰陈列", Vector3(-1.60, 0, .05), Vector3(-1.60, 2.95, -.8), BLUE, "stocking", 5.0],
		["counter", "收银柜台", Vector3(1.75, 0, -1.42), Vector3(1.75, 1.55, 0.1), GOLD, "checkout", 4.2],
		["mirror", "试衣与照镜", Vector3(5.1, 0, 0.75), Vector3(5.05, 3.3, -0.8), PLUM, "fitting", 4.8],
		["rest", "薄荷糖茶桌", Vector3(5.25, 0, 2.7), Vector3(6.05, 1.25, 2.55), BLUE, "stocking", 1.0],
	]


func _group(title: String, at: Vector3, parent: Node = self) -> Node3D:
	var node := Node3D.new()
	node.name = title
	node.position = at
	parent.add_child(node)
	return node


func _material(color: Color, pattern: int = 0) -> ShaderMaterial:
	var key := color.to_html() + str(pattern)
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = PAPER
		mat.set_shader_parameter("pigment", color)
		mat.set_shader_parameter("pattern", float(pattern))
		_materials[key] = mat
	return _materials[key]


func _box(parent: Node, title: String, size: Vector3, at: Vector3, color: Color, pattern: int = 0) -> MeshInstance3D:
	var node := Art.box(title, size, color, at)
	node.material_override = _material(color, pattern)
	parent.add_child(node)
	return node


func _cylinder(parent: Node, title: String, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var node := Art.cylinder(title, radius, height, color, at, 16)
	node.material_override = _material(color)
	parent.add_child(node)
	return node


func _glazing(parent: Node, title: String, size: Vector2, at: Vector3) -> MeshInstance3D:
	var pane := MeshInstance3D.new()
	pane.name = title
	var mesh := QuadMesh.new()
	mesh.size = size
	pane.mesh = mesh
	pane.position = at
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = GLASS
	pane.material_override = material
	parent.add_child(pane)
	pane.add_to_group("shop_glass_panels")
	return pane


func _shape(parent: Node, title: String, points: PackedVector2Array, at: Vector3, color: Color, pattern: int = 0) -> Node3D:
	var node := Art.flat_shape(title, points, color, 0.0, 0.0)
	node.position = at
	(node.get_node("Paper") as MeshInstance3D).material_override = _material(color, pattern)
	parent.add_child(node)
	return node


func _obstacle(center: Vector2, size: Vector2, fixture: Node3D = null) -> void:
	if fixture == null:
		obstacles.append(Rect2(center - size * 0.5, size))
		return
	var local := fixture.to_local(to_global(Vector3(center.x, 0, center.y)))
	_footprints.append({"node": fixture, "rect": Rect2(Vector2(local.x, local.z) - size * .5, size), "transform": Transform3D()})


func _anchor(key: String, fixture: Node3D, at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = "Interaction_" + key
	fixture.add_child(marker)
	marker.position = fixture.to_local(to_global(at))
	_anchors[key] = marker
	return marker


func interaction_anchor(key: String) -> Marker3D:
	return _anchors.get(key) as Marker3D


func _facility_nodes() -> Dictionary:
	return {"rack": "GarmentDisplay", "hats": "SmallGoodsCabinet", "counter": "CheckoutCounter", "mirror": "StandingMirror", "rest": "TeaCorner"}


func _setup_interaction_anchors() -> void:
	var nodes := _facility_nodes()
	for definition in facility_definitions():
		var fixture := get_node(nodes[definition[0]]) as Node3D
		_anchor(definition[0], fixture, definition[2])
		_anchor(definition[0] + "_label", fixture, definition[3])
	if not has_node("FittingBooth"):
		return
	for index in BROWSE_SPOTS.size():
		_anchor("browse_%d" % index, get_node("GarmentDisplay"), BROWSE_SPOTS[index])
	for index in 6:
		_anchor("pickup_%d" % index, get_node("GarmentDisplay"), Vector3(-6.12 + index * .59, 0, .45))
	for index in 3:
		_anchor("pickup_%d" % (index+6), get_node("SmallGoodsCabinet"), Vector3(-2.1 + index*.5, 0, .45))
	_anchor("fitting", get_node("FittingBooth"), FITTING)
	_anchor("fitting_exit", get_node("FittingBooth"), Vector3(5.6, 0, .85))
	_anchor("fitting_queue", get_node("FittingBooth"), FITTING_QUEUE)
	fitting_room.configure(to_global(FITTING_QUEUE), [Vector3.ZERO, Vector3(0,0,1.15), Vector3(-1.10,0,1.15), Vector3(-2.20,0,1.15)])
	_anchor("customer_mirror", get_node("StandingMirror"), MIRROR)
	_anchor("customer_checkout", get_node("CheckoutCounter"), CHECKOUT)
	checkout_queue = preload("res://scripts/service_queue.gd").new()
	checkout_queue.name = "CheckoutQueue"
	get_node("CheckoutCounter").add_child(checkout_queue)
	checkout_queue.configure(to_global(CHECKOUT+Vector3(-1.1,0,.3)), [Vector3.ZERO, Vector3(-1.1,0,0), Vector3(-2.2,0,0), Vector3(-2.2,0,1.1)])
	_anchor("return_basket", get_node("LaundryBasket"), Vector3(6.4, 0, 1.25))


func refresh_navigation(force := false) -> bool:
	var changed := force
	for footprint in _footprints:
		var fixture: Node3D = footprint.node
		if not is_instance_valid(fixture) or not footprint.transform.is_equal_approx(fixture.global_transform):
			changed = true
	if not changed:
		return false
	_footprints = _footprints.filter(func(entry: Dictionary) -> bool: return is_instance_valid(entry.node))
	_blocked_polygons.clear()
	for footprint in _footprints:
		var fixture: Node3D = footprint.node
		footprint.transform = fixture.global_transform
		var rect: Rect2 = footprint.rect
		var polygon := PackedVector2Array()
		for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			var point := to_local(fixture.to_global(Vector3(corner.x, 0, corner.y)))
			polygon.append(Vector2(point.x, point.z))
		footprint["polygon"] = polygon
		for expanded in Geometry2D.offset_polygon(polygon, .32, Geometry2D.JOIN_MITER):
			_blocked_polygons.append(expanded)
	_build_navigation()
	navigation_revision += 1
	return true


func layout_problem(moved: Node3D) -> String:
	for footprint in _footprints:
		if footprint.node != moved:
			continue
		var polygon: PackedVector2Array = footprint.polygon
		for corner in polygon:
			if absf(corner.x) > 7.0 or corner.y < -2.45 or corner.y > 3.55:
				return "家具超出了房间"
		for other in _footprints:
			if other.node != moved and not Geometry2D.intersect_polygons(polygon, other.polygon).is_empty():
				return "家具不能重叠摆放"
	var entry := Vector3(0, 0, 3.25)
	for doorway in [Vector3(-7.2, 0, 1.75), Vector3(7.2, 0, 1.75)]:
		if route(entry, doorway).is_empty():
			return "需要留出通往门口的通道"
	for key in _anchors:
		if str(key).ends_with("_label"):
			continue
		var marker: Marker3D = _anchors[key]
		if not is_instance_valid(marker) or route(entry, to_local(marker.global_position)).is_empty():
			return "需要留出使用家具的空间"
	return ""


func _architecture() -> void:
	var shell := _group("RoomShell", Vector3.ZERO)
	_box(shell, "CardboardFoundation", Vector3(14.4, 0.22, 6.7), Vector3(0, -0.15, 0.55), PLUM)
	_box(shell, "PaperFloor", Vector3(14.4, 0.06, 6.5), Vector3(0, -0.015, 0.55), WHITE)
	for row in 8:
		for col in 18:
			var color := Color("cfdbd5") if (row + col) % 2 == 0 else Color("e2c8c9")
			_box(shell, "Tile_%d_%d" % [row, col], Vector3(0.79, 0.015, 0.79), Vector3(-6.8 + col * 0.8, 0.025, -2.25 + row * 0.8), color).cast_shadow = 0
	# Keep a real void behind the window. The old full-width wall plus a paper
	# landscape made the window look like a pasted backdrop instead of glazing.
	var back_wall := _group("BackWall", Vector3.ZERO, shell)
	var window_center := _window_center_x()
	var opening_left := window_center - 1.72
	var opening_right := window_center + 1.72
	var bottom := _window_center_y() - 1.12
	var top := _window_center_y() + 1.12
	_box(back_wall, "BackWallLeft", Vector3(opening_left + 7.2, 4.75, .16), Vector3((-7.2 + opening_left) * .5, 2.375, -2.65), PINK)
	_box(back_wall, "BackWallRight", Vector3(7.2 - opening_right, 4.75, .16), Vector3((7.2 + opening_right) * .5, 2.375, -2.65), PINK)
	_box(back_wall, "BackWallBottom", Vector3(3.44, bottom, .16), Vector3(window_center, bottom*.5, -2.65), PINK)
	_box(back_wall, "BackWallTop", Vector3(3.44, 4.75-top, .16), Vector3(window_center, (4.75+top)*.5, -2.65), PINK)
	_box(shell, "Wainscot", Vector3(14.4, 1.22, 0.065), Vector3(0, 0.61, -2.52), GREEN)
	for col in 37:
		_box(shell, "WallFold", Vector3(0.016, 1.08, 0.028), Vector3(-7.0 + col * 0.39, 0.59, -2.474), MINT)
	_box(shell, "DadoRail", Vector3(14.4, 0.08, 0.16), Vector3(0, 1.23, -2.47), WHITE)
	_box(shell, "Skirting", Vector3(14.4, 0.12, 0.18), Vector3(0, 0.10, -2.43), INK)
	_box(shell, "TopPaperEdge", Vector3(14.4, 0.16, 0.26), Vector3(0, 4.78, -2.6), PLUM)
	# The side is cut away in front of the entrance, leaving an actual doorway.
	_box(shell, "LeftReturn", Vector3(0.16, 4.75, 3.1), Vector3(-7.2, 2.375, -1.05), MINT)
	_box(shell, "EntryLintel", Vector3(0.16, 1.5, 2.65), Vector3(-7.2, 4.0, 1.83), MINT)
	_box(shell, "RightReturn", Vector3(0.16, 4.75, 3.15), Vector3(7.2, 2.375, -1.08), MINT)
	_box(shell, "RightCutEdge", Vector3(0.2, 4.82, 0.15), Vector3(7.2, 2.38, 0.48), WHITE)
	_box(shell, "LeftCutEdge", Vector3(0.2, 4.82, 0.15), Vector3(-7.2, 2.38, 0.48), WHITE)
	_box(shell, "DoorHeader", Vector3(0.24, 0.13, 2.3), Vector3(-7.16, 3.2, 1.75), GREEN)
	_box(shell, "Threshold", Vector3(0.8, 0.07, 2.1), Vector3(-7.12, 0.04, 1.75), GREEN)
	_box(shell, "RightDoorHeader", Vector3(.24,.13,2.3),Vector3(7.16,3.2,1.75),GREEN)
	_box(shell, "RightThreshold", Vector3(.5,.07,2.1),Vector3(7.1,.04,1.75),GREEN)
	var door := _group("OpenDoor", Vector3(-7.17, 0, 0.72), shell)
	door.rotation_degrees.y = -36
	_box(door, "DoorLowerPanel", Vector3(.09, 1.205, 1.5), Vector3(0, .6025, -.74), GREEN)
	_box(door, "DoorTopRail", Vector3(.09, .325, 1.5), Vector3(0, 2.9175, -.74), GREEN)
	for z in [-1.39, -.09]:
		_box(door, "DoorStile", Vector3(.09, 1.55, .2), Vector3(0, 1.98, z), GREEN)
	_glazing(door, "WindowInset", Vector2(1.1, 1.55), Vector3(0, 1.98, -.74)).rotation.y = PI*.5
	_box(door, "WindowRail", Vector3(0.13, 0.08, 1.18), Vector3(0, 2.15, -0.75), WHITE)
	_obstacle(Vector2(-7.2, -1.05), Vector2(0.2, 3.1))
	_obstacle(Vector2(7.2, -1.05), Vector2(0.2, 3.1))


func _window() -> void:
	var window := _group("CutPaperWindow", Vector3(-1.30, 2.95, -2.5))
	_glazing(window, "AcrylicGlassPane", Vector2(3.35, 2.25), Vector3(0, 0, .14))
	for x in [-1.62,0.0,1.62]:
		_box(window,"Mullion",Vector3(.09,2.25,.17),Vector3(x,0,.22),WHITE)
	for y in [-1.12,0.20,1.12]:
		_box(window,"Rail",Vector3(3.35,.09,.17),Vector3(0,y,.22),WHITE)
	_box(window,"Sill",Vector3(3.55,.10,.48),Vector3(0,-1.15,.26),GREEN)
	for side in [-1,1]:
		for fold in 4:
			_box(window,"CurtainFold",Vector3(.16,1.93,.06),Vector3(side*(1.37+fold*.10),.09,.34+sin(fold*PI*.5)*.035),WHITE if fold%2==0 else Color("e8dfc6"))


func _window_center_x() -> float:
	return -1.30


func _window_center_y() -> float:
	return 2.95


func _set_back_wall_material(color: Color) -> void:
	var wall := get_node_or_null("RoomShell/BackWall")
	if wall == null:
		return
	for piece in wall.get_children():
		if piece is GeometryInstance3D:
			piece.material_override = _material(color)


func _display() -> void:
	var rack := _group("GarmentDisplay", Vector3(-4.80,0,-0.98))
	_box(rack,"Backboard",Vector3(3.70,3.0,.13),Vector3(0,1.5,-.53),GREEN)
	_box(rack,"TopShelf",Vector3(3.90,.12,.85),Vector3(0,3.04,-.12),INK)
	_box(rack,"LowerShelf",Vector3(3.80,.13,.92),Vector3(0,.25,-.08),GREEN)
	for x in [-1.87,1.87]:
		_box(rack,"SideFold",Vector3(.12,3.08,.82),Vector3(x,1.54,-.12),GREEN)
	_box(rack,"BrassRail",Vector3(3.70,.045,.045),Vector3(0,2.61,.04),GOLD)
	# Garments themselves are ShopInventory items; only the hangers belong to the fixture.
	for index in 6:
		var x := -1.47+index*.59
		var hanger := preload("res://components/garment_hanger.gd").new()
		hanger.name = "Hanger%d" % index
		hanger.position = Vector3(x,2.61,.04)
		rack.add_child(hanger)
	for i in 3:
		_parcel(rack,Vector3(-1.08+i*1.06,3.29,-.10),Vector3(.74,.37,.60),[PINK,BLUE,GOLD][i])
	_obstacle(Vector2(-4.80,-1.04),Vector2(3.90,1.0),rack)


func _workbench(at := Vector3(-.35,0,-1.52)) -> void:
	var table := _group("SewingWorkbench",at)
	_table(table,Vector2(2.25,1.05),1.08,GREEN)
	_box(table,"CuttingMat",Vector3(1.1,.015,.68),Vector3(-.43,1.19,.02),MINT,2)
	var machine := preload("res://components/sewing_machine.gd").new()
	machine.name = "SewingMachine"
	machine.position = Vector3(.40,1.13,-.04)
	table.add_child(machine)
	_box(table,"FootPedal",Vector3(.40,.09,.28),Vector3(.2,.07,.42),INK).rotation_degrees.x = -8
	_box(table,"PowerCable",Vector3(.018,.95,.018),Vector3(.88,.61,-.20),INK)
	_shape(table,"HangingCloth",PackedVector2Array([Vector2(-.96,0),Vector2(-.18,0),Vector2(-.14,-.55),Vector2(-.37,-.67),Vector2(-.92,-.60)]),Vector3(0,1.185,.55),PINK,2)
	for i in 3:
		_spool(table,Vector3(-.88+i*.21,1.36,-.31),[GOLD,PLUM,GREEN][i],.07,.22)
	_box(table,"ScissorsA",Vector3(.34,.018,.04),Vector3(-.44,1.21,.20),INK).rotation_degrees.y = 25
	_box(table,"ScissorsB",Vector3(.34,.019,.04),Vector3(-.44,1.23,.20),INK).rotation_degrees.y = -25
	_obstacle(Vector2(at.x,at.z),Vector2(2.37,1.15),table)


func _notions() -> void:
	var shelf := _group("FabricAndNotions",Vector3(.90,2.8,-2.48))
	_box(shelf,"Back",Vector3(.85,1.82,.10),Vector3.ZERO,GREEN)
	for row in 3:
		_box(shelf,"Shelf",Vector3(.97,.065,.5),Vector3(0,-.85+row*.58,.20),WHITE)
		for col in 3:
			_spool(shelf,Vector3(-.27+col*.27,-.66+row*.58,.20),[RED,GOLD,BLUE,PLUM][(row+col)%4],.085,.28)


func _counter() -> void:
	var counter := _group("CheckoutCounter",Vector3(1.85,0,-.42))
	_box(counter,"Body",Vector3(2.50,1.05,1.10),Vector3(0,.55,0),GREEN)
	_box(counter,"Top",Vector3(2.70,.10,1.28),Vector3(0,1.13,0),WHITE)
	for i in 9:
		_box(counter,"FoldedFront",Vector3(.19,.87,.024),Vector3(-1.12+i*.28,.58,.568),MINT)
	_box(counter,"Plinth",Vector3(2.55,.12,1.16),Vector3(0,.10,0),INK)
	_box(counter,"Till",Vector3(.43,.29,.38),Vector3(.75,1.32,-.09),PLUM)
	_box(counter,"TillKeys",Vector3(.37,.025,.18),Vector3(.75,1.32,.12),GOLD).rotation_degrees.x = -22
	_box(counter,"Ledger",Vector3(.48,.05,.42),Vector3(.76,1.22,-.44),PINK)
	_box(counter,"LedgerPages",Vector3(.42,.015,.37),Vector3(.76,1.253,-.435),WHITE)
	checkout_exchange = preload("res://components/checkout_exchange.gd").new()
	checkout_exchange.name = "CheckoutExchange"
	counter.add_child(checkout_exchange)
	_obstacle(Vector2(1.85,-.42),Vector2(2.7,1.28),counter)


func _fitting() -> void:
	var booth := _group("FittingBooth",Vector3(5.62,0,-1.36))
	_box(booth,"Back",Vector3(2.24,3.36,.10),Vector3(0,1.68,-.88),PLUM)
	for x in [-1.08,1.08]:
		_box(booth,"FoldedSide",Vector3(.09,3.36,1.75),Vector3(x,1.68,-.02),PINK)
	_box(booth,"Cornice",Vector3(2.4,.16,1.94),Vector3(0,3.40,-.02),PLUM)
	_box(booth,"CurtainRail",Vector3(2.18,.04,.05),Vector3(0,3.23,.83),GOLD)
	var curtain: Node3D = preload("res://components/accordion_curtain.gd").new()
	curtain.name = "PleatedCurtain"
	curtain.position = Vector3(0,0,.84)
	booth.add_child(curtain)
	curtain.build(_material(RED))
	fitting_room = preload("res://scripts/fitting_room.gd").new()
	fitting_room.name = "FittingRoom"
	fitting_room.curtain = curtain
	booth.add_child(fitting_room)
	_obstacle(Vector2(5.62,-2.24),Vector2(2.24,.10),booth)
	for x in [4.54,6.70]:
		_obstacle(Vector2(x,-1.38),Vector2(.09,1.75),booth)
	var mirror := _group("StandingMirror",Vector3(3.74,0,-.87))
	mirror.rotation_degrees.y = -10
	var outline := Art.rounded_rect_points(Rect2(-.48,.22,.96,2.71),.26,5)
	_shape(mirror,"Frame",outline,Vector3.ZERO,GOLD)
	var reflection := preload("res://scripts/mirror_reflection.gd").new()
	reflection.name = "ActualMirrorReflection"
	reflection.position = Vector3(0, 1.57, .035)
	mirror.add_child(reflection)
	reflection.configure(Vector2(.80, 2.50))
	_box(mirror,"LeftFoot",Vector3(.10,.2,.6),Vector3(-.34,.10,0),PLUM)
	_box(mirror,"RightFoot",Vector3(.10,.2,.6),Vector3(.34,.10,0),PLUM)
	_obstacle(Vector2(3.74,-.87),Vector2(.98,.6),mirror)
	var basket := _group("LaundryBasket",Vector3(6.40,0,.33))
	_box(basket,"Base",Vector3(.68,.05,.58),Vector3(0,.08,0),GOLD)
	for x in [-.32,.32]:
		_box(basket,"Side",Vector3(.045,.60,.60),Vector3(x,.35,0),GOLD,2)
	for z in [-.28,.28]:
		_box(basket,"Side",Vector3(.68,.60,.045),Vector3(0,.35,z),GOLD,2)
	_obstacle(Vector2(6.40,.33),Vector2(.72,.65),basket)


func _small_goods() -> void:
	var shelf := _group("SmallGoodsCabinet",Vector3(-1.60,0,-.98))
	_table(shelf,Vector2(2.15,.85),.80,BLUE)
	for i in 3:
		var at := Vector3([-.58,.58,0.0][i],[1.21,1.21,2.10][i],0)
		var stand := _group("Stand%d" % i,at,shelf)
		var mount := Marker3D.new()
		mount.name = "GarmentMount"
		stand.add_child(mount)
		_cylinder(stand,"HatSupport",.10,.12,Vector3(0,-.06,0),GOLD)
		_cylinder(shelf,"StandStem",.028,at.y-.8,Vector3(at.x,(at.y+.8)*.5,0),GOLD)
		_cylinder(shelf,"StandBase",.19,.04,Vector3(at.x,.84,0),BLUE)
	_obstacle(Vector2(-1.60,-.98),Vector2(2.27,.95),shelf)
	var bench := _group("ParcelBench",Vector3(-4.8,0,2.95))
	_table(bench,Vector2(1.8,.58),.47,BLUE)
	_parcel(bench,Vector3(-.35,.73,0),Vector3(.65,.35,.46),PINK)
	_box(bench,"FoldedScarf",Vector3(.65,.09,.48),Vector3(.45,.60,0),GOLD,1)
	_obstacle(Vector2(-4.8,2.95),Vector2(1.85,.65),bench)


func _wall_details() -> void:
	var board := _group("ClippingsAndPatterns",Vector3(2.8,3.17,-2.49))
	_box(board,"Pinboard",Vector3(2.3,1.60,.08),Vector3.ZERO,PLUM)
	for i in 4:
		var page := _group("PinnedPage%d"%i,Vector3(-.80+i*.51,.04 if i%2 else -.03,.08+i*.002),board)
		page.rotation_degrees.z = -5+i*3
		_box(page,"Paper",Vector3(.49,1.21,.015),Vector3.ZERO,WHITE)
		_shape(page,"GarmentDrawing",PackedVector2Array([Vector2(-.10,.35),Vector2(.10,.35),Vector2(.19,-.27),Vector2(-.19,-.27)]),Vector3(0,0,.02),[GREEN,BLUE,RED,GOLD][i])
		for line in 3:
			_box(page,"NoteLine",Vector3(.31-line*.04,.013,.01),Vector3(0,-.37-line*.07,.025),MINT)
		_shape(page,"Pin",Art.circle_points(Vector2.ZERO,.033,10),Vector3(0,.57,.03),RED)
	var banner := _group("WovenWallHanging",Vector3(-4.8,3.87,-2.40))
	_box(banner,"Fabric",Vector3(1.8,.84,.025),Vector3.ZERO,WHITE,1)
	for i in 6:
		_shape(banner,"WovenDiamond",PackedVector2Array([Vector2(-.11,0),Vector2(0,.18),Vector2(.11,0),Vector2(0,-.18)]),Vector3(-.65+i*.26,0,.02),RED if i%2 else GREEN)
	for i in 15:
		_box(banner,"Fringe",Vector3(.035,.17,.025),Vector3(-.82+i*.118,-.48,0),WHITE)
	_pendant(Vector3(-1.6, 3.95, -.98), "WorkbenchPendant")
	_pendant(Vector3(1.85, 3.95, -.42), "CounterPendant")


func _pendant(at: Vector3, title: String) -> void:
	var lamp := _group(title, at)
	var roof := get_node("HingedRoof")
	roof.add_lamp_support(at)
	var ceiling: float = roof.RIDGE - (roof.RIDGE - roof.EAVE) * absf(at.x) / roof.HALF_WIDTH - .10
	var cord_length := ceiling - at.y - .15
	_box(lamp,"CeilingMount",Vector3(.22,.05,.18),Vector3(0,ceiling-at.y,0),MINT)
	_box(lamp,"Cord",Vector3(.018,cord_length,.018),Vector3(0,.15+cord_length*.5,0),PLUM)
	var shade := _cylinder(lamp,"FoldedShade",.38,.24,Vector3.ZERO,GOLD)
	(shade.mesh as CylinderMesh).top_radius = .12
	var diffuser := _cylinder(lamp,"Diffuser",.29,.025,Vector3(0,-.13,0),WHITE)
	diffuser.material_override = diffuser.material_override.duplicate()
	var light := SpotLight3D.new()
	light.name = "PendantLight"
	light.position = Vector3(0,-.19,0)
	light.rotation_degrees.x = -90
	light.spot_range = 8
	light.spot_angle = 66
	light.spot_angle_attenuation = .6
	light.spot_attenuation = .65
	light.light_color = Color("ffcf8c")
	light.light_cull_mask = 1 | 8
	light.shadow_caster_mask = 1 | 8
	light.light_energy = .04
	light.shadow_enabled = true
	light.shadow_bias = .02
	light.shadow_normal_bias = .5
	lamp.add_child(light)
	light.add_to_group("shop_lamps")
	lamp.set_meta("roof_anchor_height",ceiling)


func _rest() -> void:
	var tea := _group("TeaCorner",Vector3(6.23,0,2.65))
	_table(tea,Vector2(.87,.85),.72,GREEN)
	_cylinder(tea,"Cup",.10,.16,Vector3(-.17,.92,.03),WHITE)
	_cylinder(tea,"Tea",.075,.012,Vector3(-.17,1.005,.03),PLUM)
	var bowl := Node3D.new()
	bowl.name = "MintBowl"
	tea.add_child(bowl)
	bowl.position = Vector3(.12,.84,-.03)
	_cylinder(bowl,"Dish",.205,.032,Vector3.ZERO,WHITE)
	for i in 12:
		var a := float(i % 8) * TAU / 8.0
		var r := .135 if i < 8 else .065
		_cylinder(bowl,"Mint%d" % i,.048,.032,Vector3(cos(a)*r,.031+float(i/8)*.022,sin(a)*r),Color("a5d8bc") if i%2 else WHITE)
	_obstacle(Vector2(6.23,2.65),Vector2(.92,.9),tea)
	var plant := _group("PaperPlant",Vector3(-6.55,0,3.0))
	_cylinder(plant,"Pot",.28,.46,Vector3(0,.23,0),RED)
	for i in 5:
		var leaf := _shape(plant,"FoldedLeaf",PackedVector2Array([Vector2(0,0),Vector2(-.19,.28),Vector2(-.12,.58),Vector2(0,.77),Vector2(.15,.55),Vector2(.17,.24)]),Vector3(0,.40,0),GREEN if i%2 else MINT)
		leaf.rotation_degrees = Vector3(0,i*62,-48+i*24)
	_obstacle(Vector2(-6.55,3.0),Vector2(.6,.6),plant)


func _table(parent: Node, dimensions: Vector2, height: float, color: Color) -> void:
	_box(parent,"Top",Vector3(dimensions.x+.12,.09,dimensions.y+.10),Vector3(0,height,0),WHITE)
	# Flat folded end panels, rather than four cylindrical furniture legs.
	for x in [-dimensions.x*.42,dimensions.x*.42]:
		_box(parent,"FoldedSupport",Vector3(.07,height,dimensions.y*.85),Vector3(x,height*.5,0),color)
	_box(parent,"CrossBrace",Vector3(dimensions.x*.85,.14,.055),Vector3(0,.26,0),color)


func _spool(parent: Node, at: Vector3, color: Color, radius: float, height: float) -> void:
	var spool := preload("res://components/thread_spool.gd").new()
	spool.name = "ThreadSpool"
	spool.position = at
	spool.build(radius,height,color)
	parent.add_child(spool)


func _parcel(parent: Node, at: Vector3, size: Vector3, color: Color) -> void:
	_box(parent,"Parcel",size,at,color)
	_box(parent,"RibbonAcross",Vector3(size.x+.012,.04,size.z+.012),at+Vector3(0,size.y*.5-.012,0),WHITE)
	_box(parent,"RibbonRound",Vector3(.045,size.y+.012,size.z+.015),at,WHITE)


func _build_navigation() -> void:
	_grid.region = Rect2i(0,0,61,24)
	_grid.cell_size = Vector2(.25,.25)
	_grid.offset = Vector2(-7.5,-2.0)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	for x in 61:
		for y in 24:
			var point := _grid.get_point_position(Vector2i(x,y))
			_grid.set_point_solid(Vector2i(x,y), not is_walkable(point))


func is_walkable(point: Vector2) -> bool:
	if point.y < -2.0 or point.y > 3.4 or absf(point.x) > 7.5:
		return false
	if absf(point.x) > 6.85 and (point.y < 1.1 or point.y > 2.35):
		return false
	for rect in obstacles:
		if rect.grow(.32).has_point(point):
			return false
	for polygon in _blocked_polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return false
	return true


func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var start := Vector2(from.x, from.z)
	var finish := Vector2(to.x, to.z)
	if not is_walkable(start) or not is_walkable(finish):
		return PackedVector3Array()
	if _segment_clear(start, finish):
		return PackedVector3Array([to])
	var from_id := _endpoint_cell(start)
	var to_id := _endpoint_cell(finish)
	if from_id.x < 0 or to_id.x < 0:
		return PackedVector3Array()
	var path := _grid.get_point_path(from_id,to_id)
	var result := PackedVector3Array()
	var previous := start
	for i in path.size():
		if not _segment_clear(previous, path[i]):
			return PackedVector3Array()
		result.append(Vector3(path[i].x,0,path[i].y))
		previous = path[i]
	if not path.is_empty() and _segment_clear(previous, finish):
		result.append(to)
	return result


func _segment_clear(from: Vector2, to: Vector2) -> bool:
	# Sampling alone can miss a very short crossing at a furniture corner.
	for polygon in _blocked_polygons:
		if _crosses_polygon(from,to,polygon):
			return false
	for obstacle in obstacles:
		var rect := obstacle.grow(.32)
		var polygon := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
		if _crosses_polygon(from,to,polygon):
			return false
	var steps := maxi(1, ceili(from.distance_to(to) / .05))
	for i in steps + 1:
		if not is_walkable(from.lerp(to, float(i) / steps)):
			return false
	return true


func _crosses_polygon(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> bool:
	for index in polygon.size():
		if Geometry2D.segment_intersects_segment(from,to,polygon[index],polygon[(index+1)%polygon.size()]) != null:
			return true
	return false


func _endpoint_cell(point: Vector2) -> Vector2i:
	var rounded := Vector2i(((point - _grid.offset) / _grid.cell_size).round())
	var best := Vector2i(-1, -1)
	var distance := INF
	for x in range(-1, 2):
		for y in range(-1, 2):
			var cell := rounded + Vector2i(x, y)
			if not _grid.is_in_boundsv(cell) or _grid.is_point_solid(cell):
				continue
			var center := _grid.get_point_position(cell)
			var candidate := point.distance_squared_to(center)
			if candidate < distance and _segment_clear(point, center):
				distance = candidate
				best = cell
	return best
