extends "res://scripts/shop_room.gd"

var kind := "rooms"
var _hanging_samples: Array[Node3D] = []


func build() -> void:
	if kind == "rooms":
		for index in 3:
			var x := (index - 1) * 14.4
			var floor_node := _group("Floor%d" % index, Vector3(x, 0, 0))
			_box(floor_node, "BareFloor", Vector3(14.35, .10, 6.5), Vector3(0, -.01, .55), Color("d8d5c6"), 2)
			var walls := _group("UnfinishedBox%d" % index, Vector3(x, 0, -2.65))
			var plaster: Color = [Color("e0d4cc"), Color("d0dad0"), Color("cdd8dc")][index]
			_box(walls, "PlasterBelow", Vector3(14.4, 2.0, .12), Vector3(0, 1.0, 0), plaster)
			_box(walls, "PlasterAbove", Vector3(14.4, .95, .12), Vector3(0, 4.275, 0), plaster)
			for side in [-1, 1]:
				_box(walls, "PlasterSide", Vector3(5.6, 1.8, .12), Vector3(side * 4.4, 2.9, 0), plaster)
			for side in [-1, 1]:
				_box(walls, "Stud", Vector3(.16, 4.75, .22), Vector3(side * 7.1, 2.375, .08), Color("b8a28c"))
			for h in [.2, 4.6]:
				_box(walls, "Batten", Vector3(14.2, .12, .20), Vector3(0, h, .10), Color("b8a28c"))
			for side in [-1, 1]:
				_box(walls, "WindowJamb", Vector3(.15, 1.85, .20), Vector3(side * 1.6, 2.9, .08), WHITE)
			_glazing(walls, "Window", Vector2(3.0, 1.8), Vector3(0, 2.9, .07))
			_box(walls, "WindowSill", Vector3(3.5, .12, .45), Vector3(0, 1.99, .16), WHITE)
			var roof := preload("res://scripts/shop_roof.gd").new()
			roof.position.x = x
			add_child(roof)
			var supplies := _group("FoldedRenovationSupplies%d" % index, Vector3(x - 5, 0, -.6))
			for i in 3:
				_box(supplies, "Board", Vector3(1.4, .10, .7), Vector3(i * .08, .1 + i * .12, 0), MINT)
			for i in 2:
				_cylinder(supplies, "PaintPot", .30, .48, Vector3(2.0 + i * .8, .25, 0), [PINK, BLUE][i])
			var drying := _group("MaterialSampleRail%d" % index, Vector3(x - 1.3, 0, 1.5))
			for side in [-1, 1]:
				_box(drying, "Post", Vector3(.07, 3.45, .07), Vector3(side * 1.3, 1.725, 0), GREEN)
			_box(drying, "Rail", Vector3(2.7, .06, .06), Vector3(0, 3.45, 0), GREEN)
			for sample in 3:
				var hinge := _group("SampleHinge%d" % sample, Vector3((sample-1)*.85, 3.4, 0), drying)
				_box(hinge, "HangingCloth", Vector3(.65, 1.15, .025), Vector3(0, -.575, 0), [MINT, PINK, BLUE][sample], 1)
				_hanging_samples.append(hinge)
	else:
		var floor_node := _group("FloorLane", Vector3.ZERO)
		_box(floor_node, "Lane", Vector3(43.2, .07, 7.4), Vector3(0, -.01, 3.1), Color("b5c4bd"), 2)
		for index in 7:
			var facade := _group("BackstreetHouse%d" % index, Vector3(-18 + index * 6, 0, -.6))
			var model: Node3D = load("res://assets/street_vendor/paper_textile_shop.glb").instantiate()
			model.name = "FoldedCardShopfront"
			facade.add_child(model)
			var sign := Label3D.new()
			sign.name = "PrintedShopSign"
			sign.text = ["布 庄", "纸 墨", "针 线", "织 物", "茶 铺", "花 房", "染 坊"][index]
			# Label3D is not a fold shader mesh: apply the rear-page presentation offset.
			sign.position = Vector3(0,4.10,16.255)
			sign.font_size = 64
			sign.pixel_size = .007
			sign.modulate = Color("eee2b6")
			sign.outline_size = 0
			facade.add_child(sign)
		for row in 8:
			for col in 37:
				var paver := _box(floor_node,"Stone",Vector3(1.08,.045,.68),Vector3(-20.9+col*1.15+(.5 if row%2 else 0),.045,.4+row*.74),[Color("b9b7a5"),Color("c6c3b1"),Color("aeb3a5")][(row+col)%3])
				paver.rotation.y = sin(float(row*37+col))*.018
		for i in 9:
			var plant := _group("PaperShrub%d" % i, Vector3(-20 + i * 5, 0, 1.2))
			_box(plant, "Planter", Vector3(1.6, .65, 1), Vector3(0, .325, 0), Color("ab7d79"))
			_shape(plant, "Leaves", Art.circle_points(Vector2(0, 1.3), .90, 11, 1.4), Vector3(0, 0, 0), Color("719980"))
		var line := _group("LaundryLine", Vector3(7, 0, .8))
		for x in [-4, 4]:
			_box(line, "Post", Vector3(.10, 3.3, .10), Vector3(x, 1.65, 0), GREEN)
		_box(line, "String", Vector3(8.1, .025, .025), Vector3(0, 3.1, 0), PLUM)
		for i in 6:
			_box(line, "Linen", Vector3(.95, 1.35, .035), Vector3(-3.2 + i * 1.25, 2.35, 0), [WHITE, BLUE, PINK][i % 3], 1)


func animate_samples(seconds: float) -> void:
	for index in _hanging_samples.size():
		_hanging_samples[index].rotation.x = sin(seconds * 1.25 + index * .8) * .10
