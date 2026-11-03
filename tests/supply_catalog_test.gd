extends SceneTree

## Supply catalog + queue test: manual queue while busy, snapshot immutability,
## cancellation/reorder, auto-restock dedup, stock matching, shortage retry,
## dye substitution policy and the real dye -> sew dependency.

var failures: Array[String] = []
var game: Node
var catalog: Node
var ledger: RefCounted
var inventory: Node3D


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)


func add_recipe(fabric_id: String, thread_id: String, style: int, extra: Dictionary = {}) -> Dictionary:
	var fabric: Dictionary = ledger.fabric(fabric_id)
	var data := {
		"style": style,
		"fabric_id": fabric_id,
		"material": str(fabric.get("material", "cotton")),
		"pattern_code": int(fabric.get("pattern_code", 0)),
		"pigment": fabric.get("pigment", Color.WHITE),
		"width_m": float(fabric.get("width_m", 1.4)),
		"thickness_m": float(fabric.get("thickness_m", .001)),
		"thread_id": thread_id,
	}
	data.merge(extra, true)
	return catalog.add_entry(data)


func clear_catalog() -> void:
	if not game._production.order.is_empty():
		ledger.cancel(str(game._production.order.id))
		game._production.order = {}
		game._production.phase = "idle"
	catalog.entries.clear()
	catalog.queue.clear()
	catalog._entries_rev += 1


func make_stock_item(fabric_id: String, thread_id: String, style: int, skirt := .70, garment := .80) -> Node3D:
	var order: Dictionary = ledger.reserve(fabric_id, thread_id, 1.0, style, skirt, garment)
	if order.is_empty():
		return null
	ledger.cut(order.id)
	ledger.advance_sewing(order.id, 1.0)
	var item: Node3D = inventory.create_from_work_order(order)
	ledger.complete(order.id, item.item_id)
	inventory._store(item)
	return item


func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game._production.auto_restock = false
	for person in game.staff:
		game._set_staff_idle(person, 100000)
	if not game._production.order.is_empty():
		game._production.ledger.cancel(str(game._production.order.id))
		game._production.order = {}
	catalog = game._supply_catalog
	inventory = game._inventory
	ledger = inventory.materials
	catalog.save_path = "user://supply_catalog_test.json"
	catalog.entries.clear()
	catalog.queue.clear()
	while inventory.in_location("storage").size() >= inventory.STORAGE_LIMIT - 3:
		inventory.in_location("storage")[0].collect()

	_test_persistence()
	_test_snapshot_and_busy_queue()
	_test_dispatch_and_reservation()
	_test_cancel_reorder()
	_test_auto_dedup_and_stock_matching()
	_test_shortage_retry_and_starvation()
	_test_dye_dependency()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(catalog.save_path))
	print("SUPPLY_CATALOG_TEST failures=", failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)


func _test_persistence() -> void:
	var entry := add_recipe("rose_check", "thread_rose", 1)
	check(not entry.is_empty(), "catalog rejected a valid recipe")
	check(entry.auto_enabled == false, "auto restock must default to disabled")
	check(catalog.update_entry(entry.id, {"auto_enabled": true, "target_stock": 3, "allow_dye": true, "name": "测试·围裙"}), "config update failed")
	catalog.save_catalog()
	var fresh: Node = preload("res://scripts/supply_catalog.gd").new()
	fresh.save_path = catalog.save_path
	check(fresh.load_catalog(), "catalog save did not load")
	check(fresh.entries.size() == catalog.entries.size(), "loaded entry count differs")
	if not fresh.entries.is_empty():
		var loaded: Dictionary = fresh.entries[0]
		check(loaded.pigment == entry.pigment, "colour did not survive JSON roundtrip")
		check(loaded.auto_enabled and loaded.allow_dye and int(loaded.target_stock) == 3, "config fields did not survive JSON roundtrip")
		check(str(loaded.name) == "测试·围裙" and int(loaded.style) == 1, "identity fields did not survive JSON roundtrip")
	var file := FileAccess.open(catalog.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 99, "entries": []}))
	file.close()
	check(not fresh.load_catalog() and fresh.entries.is_empty(), "wrong schema version accepted")
	file = FileAccess.open(catalog.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 2, "entries": [
		{"id": "supply_90", "style": 1, "fabric_id": "rose_check", "thread_id": "thread_rose", "material": "cotton", "pattern_code": 2, "pigment": "not-a-colour", "width_m": 1.4, "thickness_m": .001},
		{"id": "supply_91", "style": 77, "fabric_id": "rose_check", "thread_id": "thread_rose", "material": "cotton", "pattern_code": 2, "pigment": "#bb7986", "width_m": 1.4, "thickness_m": .001},
	]}))
	file.close()
	check(fresh.load_catalog() and fresh.entries.is_empty(), "invalid saved entries were not rejected")
	fresh.free()
	clear_catalog()


func _test_snapshot_and_busy_queue() -> void:
	game._production.order = ledger.reserve("rose_check", "thread_rose", 1.0, 1)
	var busy_id := str(game._production.order.id)
	var entry := add_recipe("sage_linen", "thread_sage", 1)
	var job: Dictionary = catalog.enqueue_manual(entry.id)
	check(not job.is_empty(), "manual one-click order failed while busy")
	catalog.tick(.5)
	check(job.state == "ready", "feasible manual order should be ready while the bench is busy, got " + job.state)
	check(str(game._production.order.id) == busy_id, "queued order replaced the active work order")
	check(not job.snapshot.is_empty() and job.snapshot.has("pigment"), "queue job lost its recipe snapshot")
	# Editing or removing the catalogue entry must not touch the queued snapshot.
	catalog.update_entry(entry.id, {"name": "改名后", "target_stock": 5, "auto_enabled": true})
	catalog.find_entry(entry.id).pigment = Color.RED
	check(job.snapshot.pigment != Color.RED, "queued snapshot mutated with the entry")
	check(str(job.snapshot.name) != "改名后", "queued snapshot renamed with the entry")
	catalog.update_entry(entry.id, {"auto_enabled": false})
	catalog.remove_entry(entry.id)
	check(catalog.find_job(job.id) != {}, "removing a catalogue entry dropped its queued job")
	check(not catalog.entries.any(func(e: Dictionary) -> bool: return str(e.id) == str(job.entry_id)), "entry removal failed")
	clear_catalog()


func _test_dispatch_and_reservation() -> void:
	var entry := add_recipe("sage_linen", "thread_sage", 1)
	var job: Dictionary = catalog.enqueue_manual(entry.id)
	var job_count: int = ledger.jobs.size()
	catalog.tick(.5)
	check(job.state == "producing", "idle bench did not dispatch a ready job: " + job.state)
	check(ledger.jobs.size() == job_count + 1, "reservation did not happen at dispatch")
	check(not game._production.order.is_empty() and str(game._production.order.get("catalog_job_id", "")) == str(job.id), "production order not linked to queue job")
	catalog.tick(.5)
	check(ledger.jobs.size() == job_count + 1, "dispatch reserved material twice")
	check(is_equal_approx(float(ledger.fabric("sage_linen").meters), 5.0), "dispatch debited fabric before cutting")
	ledger.cancel(str(job.work_order_id))
	game._production.order = {}
	game._production.phase = "idle"
	catalog.tick(.5)
	check(catalog.find_job(job.id).is_empty(), "job with a cancelled work order must leave the queue")
	clear_catalog()


func _test_cancel_reorder() -> void:
	var entry := add_recipe("rose_check", "thread_rose", 1)
	var first: Dictionary = catalog.enqueue_manual(entry.id)
	var second: Dictionary = catalog.enqueue_manual(entry.id)
	var third: Dictionary = catalog.enqueue_manual(entry.id)
	check(catalog.move_job(third.id, -1), "move up rejected")
	check(str(catalog.queue[1].id) == str(third.id) and str(catalog.queue[2].id) == str(second.id), "move up did not reorder")
	check(catalog.move_job(third.id, -1) and str(catalog.queue[0].id) == str(third.id), "second move up failed")
	check(not catalog.move_job(third.id, -1), "move past the top accepted")
	check(catalog.move_job(first.id, 1) and str(catalog.queue[2].id) == str(first.id) and str(catalog.queue[1].id) == str(second.id), "move down failed")
	check(catalog.cancel_job(second.id), "pending cancellation rejected")
	check(catalog.queue.size() == 2, "cancelled job still queued")
	check(not catalog.cancel_job(second.id), "double cancellation accepted")
	catalog.queue.clear()
	clear_catalog()


func _test_auto_dedup_and_stock_matching() -> void:
	var entry := add_recipe("rose_check", "thread_rose", 12, {"skirt_length": .70, "auto_enabled": true, "target_stock": 2})
	catalog.tick(.5)
	check(catalog.active_count(entry.id) == 2, "auto restock did not fill the deficit, got %d" % catalog.active_count(entry.id))
	catalog.tick(.5)
	catalog.tick(.5)
	check(catalog.active_count(entry.id) == 2, "auto restock duplicated queued orders")
	var producing := {}
	for job in catalog.queue:
		if job.state == "producing":
			producing = job
	check(not producing.is_empty(), "auto order did not dispatch onto the idle bench")
	if producing.is_empty():
		return
	# Complete the dispatched work order by hand; the queue must count it once.
	var order_id := str(producing.work_order_id)
	ledger.cut(order_id)
	ledger.advance_sewing(order_id, 1.0)
	var item: Node3D = inventory.create_from_work_order(ledger.jobs[order_id])
	check(item != null, "no output item for the auto order")
	inventory._store(item)
	ledger.complete(order_id, item.item_id)
	game._production.order = {}
	game._production.phase = "idle"
	var completed_before: int = catalog.completed_count
	catalog.tick(.5)
	check(producing.state == "completed" and catalog.completed_count == completed_before + 1, "completion not signalled exactly once")
	catalog.tick(.5)
	check(catalog.completed_count == completed_before + 1, "completion counted twice")
	var snapshot: Dictionary = catalog._snapshot(entry)
	check(catalog.stock_count(snapshot) == 1, "finished garment not counted as matching stock")
	catalog.tick(.5)
	check(catalog.active_count(entry.id) == 1, "auto restock overstocked past stock+queue accounting")
	# Stop the still-queued second auto order so its reservation frees the fabric.
	for job in catalog.queue.duplicate():
		if job.state == "producing":
			ledger.cancel(str(job.work_order_id))
			game._production.order = {}
			game._production.phase = "idle"
	catalog.tick(.5)
	# Paid items and differing pigment / pattern / length are not stock.
	item.paid = true
	check(catalog.stock_count(snapshot) == 0, "paid item counted as stock")
	item.paid = false
	item.collect()
	check(catalog.stock_count(snapshot) == 0, "collected item counted as stock")
	var wrong_length := make_stock_item("rose_check", "thread_rose", 12, .45)
	check(wrong_length != null and catalog.stock_count(snapshot) == 0, "different skirt length counted as stock")
	var wrong_pigment := make_stock_item("sage_linen", "thread_sage", 12)
	check(wrong_pigment != null and catalog.stock_count(snapshot) == 0, "different pigment counted as stock")
	var wrong_pattern := make_stock_item("opening_cloth", "thread_blue", 12)
	check(wrong_pattern != null and catalog.stock_count(snapshot) == 0, "different pattern counted as stock")
	for spare in [wrong_length, wrong_pigment, wrong_pattern]:
		if spare != null:
			spare.collect()
	clear_catalog()


func _test_shortage_retry_and_starvation() -> void:
	var entry := add_recipe("gold_stripe", "thread_blue", 1)
	var full := float(ledger.fabric("gold_stripe").meters)
	ledger.fabric("gold_stripe").meters = .05
	var blocked: Dictionary = catalog.enqueue_manual(entry.id)
	catalog.tick(.5)
	check(blocked.state == "waiting-material" and str(blocked.blocked_reason).contains("布料"), "shortage not reported as a material wait: " + str(blocked.blocked_reason))
	# A blocked job must not starve a later feasible one.
	var other := add_recipe("sage_linen", "thread_sage", 1)
	var later: Dictionary = catalog.enqueue_manual(other.id)
	catalog.tick(.5)
	check(blocked.state == "waiting-material", "short job left the wait state early")
	check(later.state == "producing", "blocked job starved a feasible later job")
	ledger.cancel(str(later.work_order_id))
	game._production.order = {}
	game._production.phase = "idle"
	catalog.tick(.5)
	# Material returns: the waiting job retries and dispatches.
	ledger.fabric("gold_stripe").meters = full
	catalog.tick(.5)
	check(blocked.state == "producing", "job did not retry after material returned: " + blocked.state)
	ledger.cancel(str(blocked.work_order_id))
	game._production.order = {}
	game._production.phase = "idle"
	catalog.tick(.5)
	clear_catalog()


func _test_dye_dependency() -> void:
	var sage := Color("8ba28a")
	# No cotton plain batch carries sage: exact stock cannot satisfy this.
	var entry := add_recipe("sage_linen", "thread_blue", 1, {"material": "cotton", "pattern_code": 0, "pigment": sage, "width_m": 1.4})
	var no_dye: Dictionary = catalog.enqueue_manual(entry.id)
	catalog.tick(.5)
	check(no_dye.state == "waiting-material" and str(no_dye.blocked_reason).contains("布料"), "missing fabric should block without dye permission")
	check(game._dye.order.is_empty(), "dye started without allow_dye")
	catalog.cancel_job(no_dye.id)
	catalog.update_entry(entry.id, {"allow_dye": true})
	# A manually started dye must neither be hijacked nor released by the queue.
	check(game._dye.start("cream_roll", 0), "manual dye failed to start")
	var guarded: Dictionary = catalog.enqueue_manual(entry.id)
	catalog.tick(.5)
	check(guarded.state == "waiting-material" and str(guarded.blocked_reason) == "等待染缸空闲", "busy vat not reported, state=" + guarded.state + " reason=" + str(guarded.blocked_reason))
	check(str(game._dye.order.get("fabric_id", "")) == "cream_roll", "catalog hijacked the manual dye order")
	check(catalog.cancel_job(guarded.id), "pending job behind a busy vat should cancel")
	check(not game._dye.order.is_empty() and str(ledger.fabric("cream_roll").get("dye_job", "")) != "", "pending cancellation released an unrelated active dye")
	ledger.fabric("cream_roll").erase("dye_job")
	game._dye.order = {}
	game._dye.phase = "idle"
	# Real targeted dye -> sew dependency.
	var dyes_before: Array = game._dye.dyes.duplicate()
	var job: Dictionary = catalog.enqueue_manual(entry.id)
	catalog.tick(.5)
	check(job.state == "dyeing", "targeted dye substitution did not start: " + job.state + " " + str(job.blocked_reason))
	if job.state != "dyeing":
		return
	var dyed_id := str(job.dye_fabric_id)
	check(dyed_id != "sage_linen", "dye substitution picked the entry's nominal (mismatched) fabric")
	check(str(ledger.fabric(dyed_id).get("dye_job", "")) != "", "dye did not lock the source batch")
	check(not ledger.can_reserve(dyed_id, "thread_blue", 1.0, 1), "sewing could reserve fabric held by the vat")
	var original_pattern := int(ledger.fabric(dyed_id).get("pattern_code", -1))
	var source_pigment: Color = ledger.fabric(dyed_id).pigment
	var dye_worker: Node3D = game.staff[2]
	var sew_worker: Node3D = game.staff[1]
	dye_worker.global_position = game._dye.production.cabinet.to_global(Vector3(-1.1, 0, 1.35))
	sew_worker.global_position = game._dye.production.cabinet.to_global(Vector3(-1.4, 0, 1.35))
	game._assign_staff(dye_worker, game._facility_index("dye"), true)
	var sewing_assigned := false
	var frames := 0
	while frames < 30000 and job.state != "completed":
		dye_worker.simulate(1.0 / 30.0, 1.0)
		sew_worker.simulate(1.0 / 30.0, 1.0)
		game._dye.advance(1.0 / 30.0)
		game._production.advance(1.0 / 30.0)
		catalog.tick(1.0 / 30.0)
		if not sewing_assigned and job.state == "producing":
			game._assign_staff(sew_worker, game._facility_index("sewing"), true)
			sewing_assigned = is_instance_valid(game._production.actor)
		if frames % 300 == 0:
			await process_frame
		frames += 1
	check(job.state == "completed", "dye->sew chain did not finish, state=%s phase=%s" % [job.state, game._production.phase])
	check(sewing_assigned, "sewing worker never took the dispatched order")
	var batch: Dictionary = ledger.fabric(dyed_id)
	check(batch.pigment == sage, "targeted dye did not achieve the exact catalog colour")
	var approximate := false
	for index in game._dye.COLORS.size():
		if source_pigment.lerp(game._dye.COLORS[index], .8) == sage:
			approximate = true
	check(not approximate, "catalog colour was reachable by plain overdye; targeted API untested")
	check(batch.name.contains("定制染"), "targeted dye output not labelled as custom dye")
	check(int(batch.get("pattern_code", -1)) == original_pattern, "dyeing changed the weave pattern")
	check(str(batch.get("dye_job", "")) == "", "finished dye left the batch locked")
	var dose_spent := false
	for index in dyes_before.size():
		if float(game._dye.dyes[index]) < float(dyes_before[index]):
			dose_spent = true
	check(dose_spent, "targeted dye consumed no dye stock")
	var item: Node3D = inventory.produced_orders.get(str(job.work_order_id))
	check(item != null, "no garment produced from the dyed fabric")
	if item != null:
		check(item.definition.material_data.pigment == sage, "garment lost the targeted dye colour")
		check(catalog.stock_count(catalog._snapshot(entry)) == 1, "dyed garment not counted toward the entry")
	check(catalog.queue.size() == 1, "auto restock overstocked around the finished dye job")
	clear_catalog()
