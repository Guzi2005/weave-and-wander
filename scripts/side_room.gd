@tool
extends "res://scripts/shop_room.gd"

@export_enum("workshop", "archive") var room_kind := "workshop"


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
	var wall := MINT if room_kind == "workshop" else Color("e5d7af")
	var lower := BLUE if room_kind == "workshop" else Color("ae6875")
	_set_back_wall_material(wall)
	get_node("RoomShell/Wainscot").material_override = _material(lower)
	for tile in get_node("RoomShell").get_children():
		if str(tile.name).begins_with("Tile_"):
			var alternate := (int(str(tile.name).get_slice("_",1)) + int(str(tile.name).get_slice("_",2))) % 2 == 0
			tile.material_override = _material(Color("c6d7d9") if alternate else WHITE)
	_window()
	get_node("CutPaperWindow").position = Vector3(.25,3.10,-2.5)
	if room_kind == "workshop":
		_loom()
		_dye_station()
		_cutting_table()
		_workbench()
		_materials_cabinet()
		_pendant(Vector3(-4.25,3.9,-.8),"LoomPendant")
		_pendant(Vector3(-1.05,4.03,-.05),"CuttingPendant")
	else:
		_fabric_shelves()
		_archive_desk()
		_packing_station()
		_rest_bench()
		_pendant(Vector3(-1.05,4.03,-.45),"ArchivePendant")
		_pendant(Vector3(4.9,3.9,-.8),"PackingPendant")
	_setup_interaction_anchors()
	refresh_navigation(true)


func _window_center_x() -> float:
	return .25


func _window_center_y() -> float:
	return 3.10


func _facility_nodes() -> Dictionary:
	return {"loom": "WeavingLoom", "dye": "DyeWorkbench", "cutting": "CuttingTable", "sewing": "SewingWorkbench", "fabric": "FabricLibrary", "clippings": "ClippingDesk", "packing": "PackingBench", "bench": "RestBench"}


func facility_definitions() -> Array:
	if room_kind == "workshop":
		return [
			# The loom paces its own job by picks, not by the shared work timer.
			["loom","织布机",Vector3(-4.35,0,.05),Vector3(-4.35,2.5,-.8),BLUE,"weaving",0.0],
			["dye","染缸与晾架",Vector3(4.8,0,.6),Vector3(4.8,1.9,-.7),RED,"sewing",7.5],
			["cutting","裁剪台",Vector3(.2,0,2.55),Vector3(.2,1.6,.85),GREEN,"sewing",6.0],
			["sewing","缝制台",Vector3(-.35,0,-.42),Vector3(-.35,2.10,-1.50),RED,"sewing",6.2],
		]
	return [
		["fabric","布料架",Vector3(-4.8,0,.25),Vector3(-4.8,2.6,-1.1),BLUE,"stocking",6.0],
		["clippings","剪报工作台",Vector3(-.3,0,1.45),Vector3(-.3,1.6,-.05),GREEN,"sewing",7.0],
		["packing","打包台",Vector3(4.8,0,.55),Vector3(4.8,1.6,-.8),RED,"stocking",5.0],
		["bench","休息长凳",Vector3(-4.0,0,2.48),Vector3(-4.0,2.0,1.2),BLUE,"resting",5.0],
	]


func _rest_bench() -> void:
	var bench := preload("res://components/rest_bench.gd").new()
	bench.name = "RestBench"
	bench.position = Vector3(-4.0,0,1.2)
	add_child(bench)
	_obstacle(Vector2(-4.0,1.2),Vector2(4.08,1.14),bench)


func _loom() -> void:
	var loom := preload("res://components/working_loom.gd").new()
	loom.name = "WeavingLoom"
	loom.position = Vector3(-4.35,0,-1.15)
	add_child(loom)
	_obstacle(Vector2(-4.35,-1.15),Vector2(3.0,1.5),loom)


func _dye_station() -> void:
	var vat := preload("res://components/dye_vat.gd").new()
	vat.name = "DyeWorkbench"
	vat.position = Vector3(4.8,0,-1.03)
	add_child(vat)
	_obstacle(Vector2(4.8,-1.03),Vector2(3.4,1.45),vat)

func _cutting_table() -> void:
	var table := _group("CuttingTable",Vector3(.2,0,.85))
	_table(table,Vector2(3.25,1.40),1.02,GREEN)
	_box(table,"CuttingMat",Vector3(2.80,.018,1.14),Vector3(0,1.08,0),MINT,2)
	_box(table,"LowerShelf",Vector3(2.65,.07,1.14),Vector3(0,.34,0),WHITE)
	_box(table,"Ruler",Vector3(.09,.023,1.08),Vector3(.72,1.13,0),GOLD)
	for i in 10:
		_box(table,"MeasureMark",Vector3(.055,.008,.015),Vector3(.73,1.15,-.44+i*.1),WHITE)
	for angle in [-22,22]:
		_box(table,"ScissorBlade",Vector3(.48,.025,.055),Vector3(1.08,1.13,.25),PLUM).rotation_degrees.y=angle
	_obstacle(Vector2(.2,.85),Vector2(3.40,1.55),table)


func _materials_cabinet() -> void:
	var cabinet := preload("res://components/material_cabinet.gd").new()
	cabinet.name = "MaterialCabinet"
	cabinet.position = Vector3(3.65,0,2.0)
	add_child(cabinet)
	_obstacle(Vector2(3.65,2.0),Vector2(3.05,1.32),cabinet)
	_obstacle(Vector2(5.59,2.10),Vector2(.90,.84),cabinet)


func _fabric_shelves() -> void:
	var shelf := _group("FabricLibrary",Vector3(-4.8,0,-1.7))
	_box(shelf,"Back",Vector3(3.3,3.6,.10),Vector3(0,1.8,-.4),BLUE)
	for x in [-1.62,1.62]:
		_box(shelf,"Side",Vector3(.12,3.6,.95),Vector3(x,1.8,0),BLUE)
	for row in 4:
		var y := .24+row*.85
		_box(shelf,"Shelf",Vector3(3.4,.10,1.05),Vector3(0,y,0),WHITE)
		for col in 5:
			var color: Color = [PINK,GOLD,MINT,BLUE,PLUM][(col+row)%5]
			var at := Vector3(-1.25+col*.63,y+.30,.05)
			var roll := _cylinder(shelf,"FabricRoll",.25,.73,at,color)
			roll.rotation_degrees.x=90
			roll.material_override=_material(color,1)
			var core := _cylinder(shelf,"RollCore",.065,.025,at+Vector3(0,0,.38),WHITE)
			core.rotation_degrees.x=90
			_box(shelf,"StockTag",Vector3(.18,.075,.015),Vector3(at.x,y-.01,.54),GOLD)
	_obstacle(Vector2(-4.8,-1.7),Vector2(3.45,1.1),shelf)


func _archive_desk() -> void:
	var desk := _group("ClippingDesk",Vector3(-.3,0,-.20))
	_table(desk,Vector2(3.05,1.33),1.05,GREEN)
	for i in 2:
		var page := _box(desk,"NotebookPage",Vector3(.64,.03,.86),Vector3(-.35+i*.67,1.12,0),WHITE)
		page.rotation_degrees.z = 4 if i==0 else -4
		for row in 3:
			_box(desk,"Clipping",Vector3(.43,.014,.18),Vector3(-.35+i*.67,1.16,-.25+row*.25),[BLUE,PINK,MINT][(row+i)%3])
	for i in 3:
		_box(desk,"Magazine",Vector3(.50,.09,.74),Vector3(-1.12,1.15+i*.09,0),[PINK,BLUE,GOLD][i]).rotation_degrees.y=i*6
	_cylinder(desk,"PencilCup",.12,.23,Vector3(1.23,1.21,-.32),RED)
	for i in 4:
		_box(desk,"Pencil",Vector3(.028,.43,.028),Vector3(1.16+i*.035,1.45,-.32),[BLUE,GOLD,GREEN,RED][i])
	var board := _group("ArchiveClippings",Vector3(3.90,3.14,-2.49))
	_box(board,"Board",Vector3(4.0,1.90,.06),Vector3.ZERO,Color("ae6875"))
	for i in 5:
		var page := _group("Clipping%d"%i,Vector3(-1.52+i*.75,.16 if i%2 else -.07,.045),board)
		page.rotation_degrees.z=-5+i*2
		_box(page,"Paper",Vector3(.61,1.24,.02),Vector3.ZERO,WHITE)
		_shape(page,"Swatch",PackedVector2Array([Vector2(-.20,.35),Vector2(.20,.35),Vector2(.16,-.10),Vector2(-.16,-.10)]),Vector3(0,0,.017),[BLUE,GOLD,MINT,PINK,GREEN][i],1)
		for row in 3:
			_box(page,"Note",Vector3(.40,.016,.014),Vector3(0,-.25-row*.1,.024),MINT)
	_obstacle(Vector2(-.3,-.2),Vector2(3.20,1.45),desk)


func _packing_station() -> void:
	var table := _group("PackingBench",Vector3(4.8,0,-1.04))
	_table(table,Vector2(2.95,1.30),1.02,RED)
	_parcel(table,Vector3(-.7,1.33,0),Vector3(.80,.53,.83),GOLD)
	_parcel(table,Vector3(.35,1.25,-.1),Vector3(.68,.35,.72),PINK)
	_box(table,"PaperStack",Vector3(.50,.10,.70),Vector3(1.03,1.15,.05),WHITE)
	var crates := _group("StoredParcels",Vector3(4.65,0,2.77))
	for i in 3:
		_parcel(crates,Vector3(-.75+i*.8,.25,0),Vector3(.7,.47,.65),[MINT,PINK,GOLD][i])
	_obstacle(Vector2(4.8,-1.04),Vector2(3.10,1.45),table)
	_obstacle(Vector2(4.65,2.77),Vector2(2.45,.72),crates)

