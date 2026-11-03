extends SceneTree

const Customer = preload("res://scripts/customer_doll.gd")
const Profile = preload("res://scripts/customer_profile.gd")
const Definition = preload("res://scripts/garment_definition.gd")
var failures: Array[String] = []
var game: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)


func capture(label: String) -> void:
	# Transform notifications are deferred even when the headless renderer skips captures.
	await process_frame
	await process_frame
	if DisplayServer.get_name() == "headless": return
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://captures/%s_%dx%d.png" % [label,root.size.x,root.size.y]))


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	var inventory: Node3D = game._inventory
	check(not game._shop.has_node("SewingWorkbench"), "Sewing table must leave the retail room")
	check(game._rooms.workshop.has_node("SewingWorkbench/SewingMachine/NeedleBar"), "Workshop must contain the detailed sewing machine")
	check(game._shop.get_node("SmallGoodsCabinet").position.distance_to(Vector3(-1.6,0,-.98)) < .01, "Hat stand must occupy the former sewing position")
	for index in inventory.SLOT_COUNT:
		var piece: Node3D = inventory.slots[index][0]
		check(piece.definition.is_hat() == (index >= inventory.CLOTHING_SLOTS), "Wrong display type")
		check(not piece.parts.is_empty(), "Catalog piece has no meshes")
		for part in piece.parts:
			check(Definition.part_slot(part) in piece.definition.slots(), "Single piece accidentally contains another outfit component")
		var fixture: Node3D = inventory.display_fixture(index)
		check(piece.global_transform.is_equal_approx(fixture.get_node("GarmentMount").global_transform), "Garment must be seated on its actual display mount")
		check(piece.scale.is_equal_approx(Vector3.ONE), "Display must not shrink the original garment")
		if index < inventory.CLOTHING_SLOTS:
			check(fixture.occupant_id == piece.item_id, "Hanger occupant must match inventory")
			check(fixture.kind == piece.definition.hanger_profile().kind, "Bottoms need clips and apron straps need pegs")
			check(piece.global_basis.is_equal_approx(fixture.frame.global_basis), "Hanger and clothing must face the same direction")
	var rack: Node3D = game._shop.get_node("GarmentDisplay")
	var rack_original := rack.transform
	rack.position.x += .18
	rack.rotation.y += .12
	await process_frame
	await process_frame
	for index in inventory.CLOTHING_SLOTS:
		check(inventory.slots[index][0].global_transform.is_equal_approx(inventory.slot_transform(index)), "Moving furniture while paused must also move its displayed clothing")
	rack.transform = rack_original
	await process_frame
	for person in game.staff + game.customers: person.hide()
	game.get_node("GameInterface").hide()
	game.camera.position = Vector3(-3.8,3.15,5.8)
	game.camera.look_at(Vector3(-4.8,1.7,-.98))
	game.camera.fov = 35
	await capture("hangers_stocked")
	var actor := Customer.new()
	actor.customer_id = "single_piece_probe"
	actor.configure({"outfit":2,"hair":0,"palette":0})
	game._actors.add_child(actor)
	actor.position = Vector3(0,0,2)
	actor.profile = Profile.new()
	actor.profile.wanted_styles = [2]
	actor.profile.favorite_palette = 1
	actor.profile.budget = 80
	actor.profile.max_pieces = 1
	var before: Array = inventory.slots.duplicate(true)
	var choice: Dictionary = inventory.choose_for(actor,actor.profile)
	check(choice.items.size() == 1 and choice.item.definition.outfit_style == 2, "Customer must be able to buy a waistcoat alone")
	inventory.pick_up(choice.item, actor)
	check(inventory.display_fixture(2).occupant_id.is_empty(), "Taking the garment must leave an empty hanger on the rail")
	check(choice.item.display_mount == null, "Carried garment must detach from the display mount")
	check(inventory.slots[1] == before[1] and inventory.slots[3] == before[3], "Unselected shirt and trousers from the same collection must stay displayed")
	await capture("hangers_one_piece_taken")
	actor.release_item(inventory)
	inventory.advance()
	check(inventory.display_fixture(2).occupant_id == choice.item.item_id, "Returning an untried piece must reoccupy a real hanger")
	for style in Definition.STYLE_NAMES.size():
		var piece: Node3D = inventory.items.filter(func(value: Node3D) -> bool: return value.definition.outfit_style == style)[0]
		piece.reserve(actor)
		check(inventory.pick_up(piece,actor), "Single-piece pickup failed")
		check(actor.put_on(piece), "Single-piece wear failed")
		if piece.definition.is_hat():
			check(actor.rig.meshes.any(func(part: MeshInstance3D) -> bool: return Definition.part_slot(part)=="top" and part.visible), "Trying a hat must not remove the shirt")
		actor.position.x += .13
		actor.rotation.y += .23
		actor.rig._rotate("Head",Vector3(.08,.3,.1))
		await process_frame
		await process_frame
		check(piece.global_transform.is_equal_approx(actor.body_rig.global_transform), "Paused movement separated clothes from body")
		for bone in actor.rig.skeleton.get_bone_count():
			check(piece.skeleton.get_bone_pose(bone).is_equal_approx(actor.rig.skeleton.get_bone_pose(bone)), "Clothing bone pose detached from actor")
		actor.take_off(piece)
		actor.release_item(inventory,piece)
		inventory.restock_step()
	actor.position = Vector3(0,0,1.7)
	actor.rotation = Vector3.ZERO
	actor.face_for_wardrobe()
	for style in [3,4,2,6]:
		var piece: Node3D = inventory.items.filter(func(value: Node3D) -> bool: return value.definition.outfit_style == style)[0]
		piece.reserve(actor)
		inventory.pick_up(piece,actor)
		actor.put_on(piece)
	check(actor.garments.size() == 4, "A shirt, trousers, waistcoat and hat must coexist")
	for person in game.staff + game.customers:
		person.hide()
	game.get_node("GameInterface").hide()
	game.camera.position = Vector3(1.8,2.7,7.3)
	game.camera.look_at(Vector3(0,1.35,1.7))
	game.camera.fov = 34
	await capture("single_piece_outfit")
	actor.position.x += .65
	actor.rotation.y -= .7
	await capture("single_piece_paused_moved")
	for piece in actor.garments:
		check(piece.global_transform.is_equal_approx(actor.body_rig.global_transform), "Paused multi-piece outfit detached: " + piece.definition.display_name())
	for person in game.staff + game.customers:
		person.show()
	actor.release_item(inventory)
	while not inventory.in_location("basket").is_empty(): inventory.restock_step()
	actor.queue_free()
	await process_frame
	game._view_controls.zoom = 0
	game._view_controls.depth = 1
	game._view_controls.apply_view()
	await capture("single_piece_shop")
	game.camera.position = Vector3(-1.2,3.4,7)
	game.camera.look_at(Vector3(-3.2,1.65,-.8))
	game.camera.fov = 38
	for person in game.staff + game.customers: person.hide()
	await capture("single_piece_displays")
	game.camera.position = Vector3(-12.8,3.1,2.5)
	game.camera.look_at(Vector3(-14.6,1.5,-1.5))
	game.camera.fov = 34
	await capture("sewing_machine_workshop")
	print("SINGLE_PIECE_TEST types=",Definition.STYLE_NAMES.size()," failures=",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
