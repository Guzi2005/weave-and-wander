extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game._set_speed(0)
	# Keep the shopping aisle clear for the initial inspection.
	for actor in game.staff + game.customers:
		var pos: Vector3 = game._shop.to_local(actor.global_position)
		if absf(pos.x+2.4) < 2.6 and pos.z > -1.0:
			actor.global_position = game._shop.to_global(Vector3(pos.x+5.5, pos.y, pos.z))
	var stock = game._inventory
	for pair in [[14,6], [15,4], [16,5]]:
		var index: int = pair[1]
		var occupant = stock.slots[index].pop_back()
		stock._store(occupant)
		stock._sync_slot(index)
		var items: Array = stock.items.filter(func(item): return item.definition.outfit_style == pair[0])
		var item = items[0]
		if not stock.display_item(item, index):
			push_error("Failed to mount " + str(pair))
			quit(1)
			return
		if pair[0] == 14:
			var support: Node3D = stock.display_fixture(index)
			var error: float = item.to_global(item.head_contact).distance_to(support.global_position)
			var beads: MeshInstance3D = item._worn_bead_meshes.keys()[0]
			var box := beads.global_transform * beads.mesh.get_aabb()
			print("HEAD_CONTACT_ERROR ", error, " BEAD_LOW ", box.position.y)
			if error > .001 or box.position.y < .031 or box.position.y > .08:
				push_error("Head or bead floor contact incorrect")
				quit(1)
				return
	var compare_layers := "--compare-hangers" in OS.get_cmdline_user_args()
	if compare_layers:
		# Adjacent examples: single vest, vest over blouse, single blouse.
		var inner = stock._create(15,0)
		stock._store(inner)
		var outer = stock._create(2,1)
		stock._store(outer)
		var trousers = stock.slots[3].pop_back()
		stock._store(trousers)
		stock._sync_slot(3)
		if not stock.display_item(inner,3) or not stock.display_item(outer,3):
			push_error("Cannot build layered comparison")
			quit(1)
			return
	var view = game._view_controls
	view.zoom = -1.0
	view.target_zoom = -1.0
	view.focus_x = game._shop.global_position.x - 2.85
	view.pan_offset = Vector2(0,-1.05) - view.near_offset
	view.pitch = deg_to_rad(10)
	view.near_size = 7.4
	if compare_layers:
		view.focus_x = game._shop.global_position.x - 4.8
		view.pitch = deg_to_rad(9)
		view.near_size = 5.6
	await create_timer(.7).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/hanger_layers_acceptance.png" if compare_layers else "res://captures/mosuo_shelf_acceptance.png")
	print("MOSUO_SHELF_READY")
