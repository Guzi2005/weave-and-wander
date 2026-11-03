extends SceneTree

const Ledger = preload("res://scripts/material_ledger.gd")
const Recipes = preload("res://scripts/garment_recipes.gd")
const Inventory = preload("res://scripts/shop_inventory.gd")

var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value and message not in errors:
		errors.append(message)
		push_error(message)


func _run() -> void:
	test_recipe_table()
	test_apron_amounts_preserved()
	test_style_pattern_matrix()
	test_snapshot_independence()
	test_invalid_recipe()
	test_output_items()
	print("GARMENT_RECIPE_TEST failures=", errors.size())
	quit(0 if errors.is_empty() else 1)


func test_recipe_table() -> void:
	check(Recipes.STYLE_NAMES.size() == 6, "Recipe table does not cover exactly six styles")
	for style in 6:
		check(Recipes.valid(style), "Valid style rejected: %d" % style)
		var recipe: Dictionary = Recipes.recipe(style)
		for key in ["net_fraction", "remnant_fraction", "waste_fraction", "thread_per_size_m"]:
			check(recipe.has(key) and float(recipe[key]) > 0.0, "Style %d missing recipe field %s" % [style, key])
	for invalid in [-1, 6, 7, 100]:
		check(not Recipes.valid(invalid), "Unknown style accepted: %d" % invalid)
		check(Recipes.recipe(invalid).is_empty(), "Unknown style returned a recipe: %d" % invalid)
	for style in 6:
		for other in 6:
			if other == style: continue
			check(Recipes.recipe(style) != Recipes.recipe(other), "Styles %d and %d share one recipe tuple" % [style, other])


func test_apron_amounts_preserved() -> void:
	var recipe: Dictionary = Recipes.recipe(1)
	check(is_equal_approx(float(recipe.net_fraction), 0.9), "Apron net fraction changed")
	check(is_equal_approx(float(recipe.remnant_fraction), 0.18), "Apron remnant fraction changed")
	check(is_equal_approx(float(recipe.waste_fraction), 0.06), "Apron waste fraction changed")
	check(is_equal_approx(float(recipe.thread_per_size_m), 12.0), "Apron thread amount changed")
	var ledger := Ledger.new()
	ledger.bind_fabrics([{"id": "roll", "meters": 10.0}])
	var plan: Dictionary = ledger.estimate("roll")
	check(plan.ok and int(plan.outfit_style) == 1, "Default estimate is not the apron")
	check(is_equal_approx(plan.net_m, 0.9) and is_equal_approx(plan.remnant_m, 0.18), "Default apron estimate amounts changed")
	check(is_equal_approx(plan.waste_m, 0.06) and is_equal_approx(plan.thread_m, 12.0), "Default apron waste/thread changed")
	var sized: Dictionary = ledger.estimate("roll", 2.0, 1)
	check(sized.ok and is_equal_approx(sized.net_m, 1.8) and is_equal_approx(sized.thread_m, 24.0), "Apron size scaling changed")


func test_style_pattern_matrix() -> void:
	var allowances := {"plain": 0.0, "stripe": Ledger.STRIPE_ALLOWANCE_M, "check": Ledger.CHECK_ALLOWANCE_M}
	for style in 6:
		var recipe: Dictionary = Recipes.recipe(style)
		for pattern in ["plain", "stripe", "check"]:
			var label := "style %d %s" % [style, pattern]
			var ledger := Ledger.new()
			ledger.bind_fabrics([{"id": "roll", "meters": 12.0, "pattern": pattern}])
			var plan: Dictionary = ledger.estimate("roll", 1.0, style)
			check(plan.ok, label + " estimate rejected")
			check(int(plan.outfit_style) == style, label + " estimate lost style")
			var allowance: float = allowances[pattern]
			check(is_equal_approx(plan.net_m, float(recipe.net_fraction)), label + " net fabric wrong")
			check(is_equal_approx(plan.remnant_m, float(recipe.remnant_fraction)), label + " remnant wrong")
			check(is_equal_approx(plan.waste_m, float(recipe.waste_fraction) + allowance), label + " waste wrong")
			check(is_equal_approx(plan.thread_m, float(recipe.thread_per_size_m)), label + " thread wrong")
			check(is_equal_approx(plan.cut_m, plan.net_m + plan.remnant_m + plan.waste_m), label + " cut not the sum of parts")
			var job: Dictionary = ledger.reserve("roll", "thread_blue", 1.0, style)
			check(not job.is_empty() and int(job.outfit_style) == style, label + " reservation lost style snapshot")
			check(int(job.estimate.outfit_style) == style and is_equal_approx(float(job.estimate.cut_m), plan.cut_m), label + " job estimate differs from preview")
			check(ledger.cut(job.id), label + " cut failed")
			check(is_equal_approx(float(ledger.fabric("roll").meters), 12.0 - plan.cut_m), label + " fabric deduction wrong")
			check(is_equal_approx(float(job.consumed_fabric_m), plan.cut_m), label + " consumed fabric wrong")
			check(ledger.remnants.size() == 1 and is_equal_approx(float(ledger.remnants[0].meters), plan.remnant_m), label + " remnant deduction wrong")
			check(ledger.advance_sewing(job.id, 1.0), label + " sewing failed")
			check(is_equal_approx(float(ledger.thread("thread_blue").meters), 80.0 - plan.thread_m), label + " thread deduction wrong")
			check(is_equal_approx(float(job.consumed_thread_m), plan.thread_m), label + " consumed thread wrong")
			check(ledger.complete(job.id, "out_%d" % style), label + " completion failed")
			check(ledger.complete(job.id, "out_%d" % style), label + " repeated completion rejected")
			check(not ledger.complete(job.id, "other"), label + " conflicting completion accepted")
	# Pattern matching allowance grows the cut for directional fabrics.
	var plain_ledger := Ledger.new()
	plain_ledger.bind_fabrics([{"id": "plain_roll", "meters": 12.0, "pattern": "plain"}])
	var stripe_ledger := Ledger.new()
	stripe_ledger.bind_fabrics([{"id": "stripe_roll", "meters": 12.0, "pattern": "stripe"}])
	var check_ledger := Ledger.new()
	check_ledger.bind_fabrics([{"id": "check_roll", "meters": 12.0, "pattern": "check"}])
	for style in 6:
		var plain_cut := float(plain_ledger.estimate("plain_roll", 1.0, style).cut_m)
		var stripe_cut := float(stripe_ledger.estimate("stripe_roll", 1.0, style).cut_m)
		var check_cut := float(check_ledger.estimate("check_roll", 1.0, style).cut_m)
		check(is_equal_approx(stripe_cut, plain_cut + Ledger.STRIPE_ALLOWANCE_M), "Style %d stripe allowance wrong" % style)
		check(is_equal_approx(check_cut, plain_cut + Ledger.CHECK_ALLOWANCE_M), "Style %d check allowance wrong" % style)


func test_snapshot_independence() -> void:
	var ledger := Ledger.new()
	ledger.bind_fabrics([{"id": "roll_a", "meters": 12.0}, {"id": "roll_b", "meters": 12.0}])
	ledger.thread_batches.append({"id": "thread_red", "meters": 80.0})
	var shirt: Dictionary = ledger.reserve("roll_a", "thread_blue", 1.0, 3)
	check(not shirt.is_empty() and int(shirt.outfit_style) == 3, "Shirt reservation failed")
	# Later reservations and estimates with other styles must not touch the snapshot.
	var skirt: Dictionary = ledger.reserve("roll_b", "thread_red", 1.0, 5)
	check(not skirt.is_empty() and int(skirt.outfit_style) == 5, "Skirt reservation failed")
	ledger.estimate("roll_b", 2.0, 0)
	check(int(shirt.outfit_style) == 3, "Snapshot style overwritten by a later selection")
	check(is_equal_approx(float(shirt.estimate.thread_m), 14.0), "Snapshot estimate overwritten by a later selection")
	check(is_equal_approx(float(skirt.estimate.thread_m), 13.0), "Second job kept the first style")
	ledger.cut(shirt.id)
	ledger.advance_sewing(shirt.id, 1.0)
	check(is_equal_approx(float(shirt.consumed_thread_m), 14.0), "Sewing used a different style's thread amount")
	check(is_equal_approx(float(ledger.fabric("roll_a").meters), 12.0 - float(shirt.estimate.cut_m)), "Cut used a different style's fabric amount")


func test_invalid_recipe() -> void:
	var ledger := Ledger.new()
	ledger.bind_fabrics([{"id": "roll", "meters": 12.0}])
	for style in [-1, 6, 100]:
		var plan: Dictionary = ledger.estimate("roll", 1.0, style)
		check(not plan.ok and plan.reason == "unknown_style", "Unknown style %d estimated" % style)
		check(not ledger.can_reserve("roll", "thread_blue", 1.0, style), "Unknown style %d passed can_reserve" % style)
		check(ledger.reserve("roll", "thread_blue", 1.0, style).is_empty(), "Unknown style %d reserved" % style)
	check(ledger.jobs.is_empty() and ledger.events.is_empty(), "Rejected styles left jobs or events")
	check(float(ledger.fabric("roll").meters) == 12.0 and float(ledger.thread("thread_blue").meters) == 80.0, "Rejected styles touched stock")
	var inventory: Node3D = Inventory.new()
	root.add_child(inventory)
	var job: Dictionary = inventory.materials.reserve("cream_roll", "thread_blue", 1.0, 1)
	check(not job.is_empty(), "Inventory apron reservation failed")
	inventory.materials.cut(job.id)
	inventory.materials.advance_sewing(job.id, 1.0)
	var bad := job.duplicate(true)
	bad["id"] = "job_invalid_style"
	bad["outfit_style"] = 6
	check(inventory.create_from_work_order(bad) == null, "Inventory accepted an out-of-range snapshot style")
	bad["outfit_style"] = -1
	check(inventory.create_from_work_order(bad) == null, "Inventory accepted a negative snapshot style")
	var legacy := job.duplicate(true)
	legacy.erase("outfit_style")
	legacy["id"] = "job_legacy"
	var legacy_item: Node3D = inventory.create_from_work_order(legacy)
	check(legacy_item != null and legacy_item.definition.outfit_style == 1, "Missing snapshot style did not default to apron")
	inventory.free()


func test_output_items() -> void:
	var inventory: Node3D = Inventory.new()
	root.add_child(inventory)
	var ledger: RefCounted = inventory.materials
	var fabrics := ["rose_check", "gold_stripe", "sage_linen", "opening_cloth", "cream_roll", "sage_linen"]
	var threads := ["thread_rose", "thread_cream", "thread_sage", "thread_blue", "thread_cream", "thread_rose"]
	for style in 6:
		var fabric_id: String = fabrics[style]
		var thread_id: String = threads[style]
		var before_fabric := float(ledger.fabric(fabric_id).meters)
		var before_thread := float(ledger.thread(thread_id).meters)
		var order: Dictionary = ledger.reserve(fabric_id, thread_id, 1.0, style)
		check(not order.is_empty(), "Output reservation failed for style %d" % style)
		if order.is_empty(): continue
		check(ledger.cut(order.id) and ledger.advance_sewing(order.id, 1.0), "Output job stalled for style %d" % style)
		var item: Node3D = inventory.create_from_work_order(order)
		check(item != null, "No garment produced for style %d" % style)
		if item == null: continue
		check(item.definition.outfit_style == style, "Produced garment has the wrong style for %d" % style)
		check(item.definition.design_id == ["long_dress", "apron", "waistcoat", "shirt", "trousers", "skirt"][style], "Produced garment uses the wrong mesh for style %d" % style)
		check(item.definition.material_data.get("pigment") == order.material_snapshot.pigment, "Produced garment lost source material for style %d" % style)
		check(item.definition.compact_apron_folds == (style == 1), "Compact apron folds leaked into style %d" % style)
		check(inventory.create_from_work_order(order) == item, "Duplicate completion created a second garment for style %d" % style)
		check(ledger.complete(order.id, item.item_id), "Ledger completion failed for style %d" % style)
		check(is_equal_approx(before_fabric - float(ledger.fabric(fabric_id).meters), float(order.estimate.cut_m)), "Produced garment fabric debit wrong for style %d" % style)
		check(is_equal_approx(before_thread - float(ledger.thread(thread_id).meters), float(order.estimate.thread_m)), "Produced garment thread debit wrong for style %d" % style)
	check(inventory.produced_orders.size() == 6, "Wrong number of produced garments")
	inventory.free()
