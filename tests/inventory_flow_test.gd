extends SceneTree

const LOCATIONS := ["rack", "storage", "basket", "carried", "worn", "counter", "packed", "collected", "production", "accessory", "attached"]
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _check_invariants(game: Node, inventory: Node3D, start_money: int) -> void:
	for index in inventory.slots.size():
		for held in inventory.slots[index]:
			_check(held.location == "rack" and held.slot == index, "Rack slot %d points at an item that is not hanging there" % index)
	for item in inventory.items:
		_check(is_instance_valid(item), "Inventory item was destroyed with its holder")
		if not is_instance_valid(item): continue
		_check(item.location in LOCATIONS, "Unknown garment location " + item.location)
		match item.location:
			"rack":
				_check(item.visible, "Hanging garment is hidden")
				var claimed: bool = item in inventory.slots[item.slot]
				_check(claimed or not item.reserved_by.is_empty(), "Hanging garment has no slot")
				if claimed:
					_check(item.global_position.distance_to(inventory.slot_transform(item.slot,item).origin) < 0.01, "Garment is not at its rack slot")
			"storage":
				if item.visible:
					_check(item.has_meta("physical_storage"), "Visible stored garment lacks physical_storage metadata")
					_check(item.display_mount != null and is_instance_valid(item.display_mount.get_ref()), "Visible stored garment has no valid display mount")
			"production":
				_check(inventory.materials.jobs.has(str(item.get_meta("work_order_id", ""))), "Production garment does not reference a real work order")
			"carried", "worn", "counter", "packed":
				_check(item.holder != null and is_instance_valid(item.holder.get_ref()), "Garment is held by nobody")
			"collected":
				_check(item.paid and not item.visible, "Collected garment is still on display")
		if item.paid:
			_check(item.location in ["carried", "worn", "packed", "collected"], "Paid garment returned to stock")
	var income := 0
	for sale in inventory.transactions:
		income += int(sale["price"])
	_check(game._money - start_money == income, "Money does not match garment transactions")
	_check(game._sales_count == inventory.transactions.size(), "Sales counter does not match transactions")


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var inventory: Node3D = game._inventory
	var start_money: int = game._money
	_check(inventory.in_location("rack").size() == inventory.SLOT_COUNT, "Opening displays are not full")
	_check(inventory.in_location("storage").size() == inventory.OPENING_STORAGE.size(), "Opening storage is wrong")
	_check(not game._room.has_node("GarmentDisplay/DisplayGarment0"), "Painted display cutouts still hang beside real garments")
	var empty_slot_seen := false
	var thoughts: Dictionary = {}
	# Guarantee a real multi-piece visit rather than relying only on random profiles.
	var first_profile: RefCounted = game.customers[0].profile
	first_profile.wanted_styles = [3]
	first_profile.favorite_palette = 1
	first_profile.budget = 80
	first_profile.max_pieces = 3
	game._set_speed(2.0)
	for tick in 21600:
		game._process(1.0 / 30.0)
		var booth: Node3D = game._shop.fitting_room
		for customer in game.customers:
			if customer.thought_time > 0.0:
				thoughts[customer.thought] = true
			var inside: bool = absf(customer.position.x - game._shop.FITTING.x) < 0.9 and customer.position.z < game._shop.FITTING.z + 0.45
			if inside and booth.occupant != null and booth.occupant.get_ref() != customer:
				_check(false, "A queued customer walked into the occupied fitting booth")
		if inventory.free_slot() >= 0:
			var gap: int = inventory.free_slot()
			var occupied: bool = inventory.items.any(func(item: Node3D) -> bool: return item.visible and item.location != "rack" and item.global_position.distance_to(inventory.slot_transform(gap).origin) < 0.01)
			_check(not occupied, "An empty rack slot still shows a garment")
			empty_slot_seen = true
		if tick % 60 == 0:
			_check_invariants(game, inventory, start_money)
		if tick % 240 == 0:
			await process_frame
	_check_invariants(game, inventory, start_money)
	var counts := {}
	var reasons := {}
	var visits := {}
	for entry in inventory.events:
		counts[entry["event"]] = counts.get(entry["event"], 0) + 1
		if entry["event"] == "decided":
			_check(not str(entry["reason"]).is_empty(), "Decision without a reason")
			reasons[entry["reason"]] = entry["bought"]
			if not visits.has(entry.customer_id): visits[entry.customer_id] = []
			visits[entry.customer_id].append(entry.bought)
	_check(visits.values().any(func(results: Array) -> bool: return results.size() >= 2), "No multi-piece shopping visit completed")
	_check(visits.values().any(func(results: Array) -> bool: return results.has(true) and results.has(false)), "No customer kept some pieces and returned others")
	_check(counts.get("paid", 0) >= 3, "Too few real garment sales")
	_check(reasons.values().has(false), "No customer ever rejected a garment")
	_check(counts.get("returned", 0) >= 1, "No tried garment went to the basket")
	_check(counts.get("restocked", 0) >= 1, "Staff never restocked the rack")
	_check(counts.get("crafted", 0) >= 1, "Crafting never produced stock")
	_check(empty_slot_seen, "Rack never showed an empty slot")
	_check(inventory.transactions.any(func(sale: Dictionary) -> bool: return sale["worn"]), "Nobody left wearing a purchase")
	_check(thoughts.keys().any(func(text: String) -> bool: return text.begins_with("想找")), "Customer wishes were never shown")
	print("INVENTORY_CHECK events=", counts, " reasons=", reasons, " money=", game._money - start_money, " failures=", failures.size())
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
