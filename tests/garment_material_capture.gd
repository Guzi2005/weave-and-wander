extends SceneTree

const Inventory = preload("res://scripts/shop_inventory.gd")
const Package = preload("res://components/material_package.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1600,1000)
	var studio := Node3D.new()
	root.add_child(studio)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("e7e0cf")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("e6eadf")
	world.environment.ambient_light_energy = .7
	studio.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = .6
	studio.add_child(light)
	var inventory := Inventory.new()
	studio.add_child(inventory)
	var fabrics := ["rose_check","gold_stripe","sage_linen","stock_blue_check","cream_roll","stock_teal_stripe"]
	var threads := ["thread_rose","thread_cream","thread_sage","thread_blue","thread_stock_moon","thread_stock_teal"]
	for style in 6:
		var record: Dictionary = inventory.materials.fabric(fabrics[style])
		# Real stock reservations, cuts and sewing create these game items.
		var order: Dictionary = inventory.materials.reserve(fabrics[style],threads[style],1.0,style)
		assert(not order.is_empty(), "Showcase stock insufficient")
		assert(inventory.materials.cut(order.id))
		assert(inventory.materials.advance_sewing(order.id,1.0))
		var item: Node3D = inventory.create_from_work_order(order)
		assert(item != null)
		assert(inventory.materials.complete(order.id,item.item_id))
		if style == 0:
			var flower_order: Dictionary = inventory.materials.reserve("cream_roll","thread_cream",1.0,9)
			assert(inventory.materials.cut(flower_order.id))
			assert(inventory.materials.advance_sewing(flower_order.id,1.0))
			var flower: Node3D = inventory.create_from_work_order(flower_order)
			assert(inventory.materials.complete(flower_order.id,flower.item_id))
			assert(item.attach_flower(flower))
			flower.hide()
		var x := (style % 3 - 1) * 2.65
		var y := 3.0 if style < 3 else .15
		item.position = Vector3(x,y,0)
		item.set_presentation("Worn")
		if style == 2: item.set_presentation("Hanging")
		item.rotation.y = -.16
		var package := Package.new()
		studio.add_child(package)
		package.configure(record,"book")
		package.position = Vector3(x-.80,y+.65,.0)
		package.rotation.y = -.65
		package.scale = Vector3.ONE*.65
		var label := Label3D.new()
		label.text = item.definition.display_name()
		label.font_size = 34
		label.pixel_size = .004
		label.modulate = Color("445f56")
		label.outline_size = 0
		label.no_depth_test = true
		studio.add_child(label)
		label.position = Vector3(x,y-.12,.3)
	var camera := Camera3D.new()
	studio.add_child(camera)
	camera.position = Vector3(0,3.15,14)
	camera.look_at(Vector3(0,2.7,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.current = true
	for tick in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/garment_material_collection.png"))
	# Inspect the actual prop geometry from the side, where armholes are visible.
	var vest: Node3D
	for candidate in inventory.items:
		if candidate.definition.outfit_style == 2: vest = candidate
	if vest != null:
		camera.position = vest.position+Vector3(2.3,1.8,2.6)
		camera.look_at(vest.position+Vector3(0,1.5,0))
		camera.size = 1.3
		for tick in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/waistcoat_armholes.png"))
	var trousers: Node3D
	for candidate in inventory.items:
		if candidate.definition.outfit_style == 4: trousers = candidate
	if trousers != null:
		camera.position = trousers.position+Vector3(1.5,1.6,3.3)
		camera.look_at(trousers.position+Vector3(0,.72,0))
		camera.size = 1.5
		for tick in 12: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/trouser_geometry.png"))
	print("GARMENT_MATERIAL_CAPTURE saved six real work-order garments")
	studio.free()
	quit()
