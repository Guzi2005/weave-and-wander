extends SceneTree
const SAVE = preload("res://scripts/game_save.gd")
var failures: Array[String] = []
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._speed = 0
	var state = game._progression
	check(state != null,"progression integrated")
	var money: int = game._money
	check(state.answer_quiz(0).ok,"wrong answer accepted")
	check(game._money == money and state.knowledge.material_identity,"wrong answer teaches without reward")
	check(not state.answer_quiz(1).ok and game._money == money,"repeat answer cannot claim")
	state.quiz_answers.clear()
	check(state.answer_quiz(1).ok and game._money == money+20,"correct grants reward once")
	check(not state.answer_quiz(1).ok and game._money == money+20,"reward idempotent")
	check(not state.learn_skill("staff_0","batch_craft").ok,"skill prerequisite enforced")
	state.people.staff_0.craft = 90.0
	check(state.learn_skill("staff_0","steady_hands").ok,"earned training succeeds")
	check(state.learn_skill("staff_0","batch_craft").ok,"second skill requires first")
	check(not state.learn_skill("staff_0","steady_hands").ok,"skill cannot charge twice")
	check(state.toggle_strategy("atelier").ok,"strategy unlocked")
	check(state.unlock_strategy_node("batch_orders").ok,"branch node unlocks")
	var before: int = game._money
	state.toggle_strategy("atelier")
	state.toggle_strategy("atelier")
	check(game._money == before,"same-day resume no double charge")
	game._day_index += 1
	state.tick(0)
	check(game._money == before-18,"next day operating cost")
	before = game._money
	state.toggle_strategy("atelier")
	state.toggle_strategy("atelier")
	check(game._money == before,"paid_day updated after daily charge")
	check(state.toggle_strategy("neighborhood").ok,"second strategy can coexist")
	check(state.unlock_strategy_node("neighbor_discount").ok,"discount branch unlocks")
	check(state.sale_price(20) == 18,"sale price discount actual")
	state.toggle_strategy("neighborhood")
	check(state.sale_price(20) == 20,"paused branch stops discount")
	check(not SAVE.save_game(game,state,"user://progression_test.save").ok,"active trading save rejected")
	for customer in game.customers.duplicate(): game._complete_customer(customer)
	game._business_state = "workshop"
	game._business_chore.phase = "idle"
	game._production.auto_restock = false
	game._supply_catalog.random_auto_enabled = false
	game._supply_catalog.queue.clear()
	await process_frame
	check(SAVE.stable_reason(game).is_empty(),"fixture stable")
	var snapshot := SAVE.capture(game,state)
	check(snapshot.extras.has("street_vendor"),"nested vendor state included")
	var saved_stock: Dictionary = game._vendor.stock.duplicate()
	var reason := SAVE.validate(snapshot,game)
	check(reason.is_empty(),"captured snapshot valid: " + reason)
	var item_id: String = game._inventory.items[0].item_id
	var item_price: int = game._inventory.items[0].definition.price
	var cloth: float = game._inventory.fabric_batches[0].meters
	var saved_money: int = game._money
	check(SAVE.save_game(game,state,"user://progression_test.save").ok,"write snapshot")
	game._money = -50
	game._inventory.fabric_batches[0].meters = 0
	game._inventory.items[0].definition.price = 999
	game._vendor.stock.cotton = 0
	var loaded := SAVE.load_game(game,state,"user://progression_test.save")
	check(loaded.ok,"restore: " + loaded.message)
	check(game._money == saved_money,"money restored")
	check(game._inventory.items[0].item_id == item_id and game._inventory.items[0].definition.price == item_price,"identity and price restored")
	check(is_equal_approx(game._inventory.fabric_batches[0].meters,cloth),"material balance restored")
	check(state.quiz_answers.has(state.ISSUE_ID),"quiz reward stays claimed")
	check(game._vendor.stock == saved_stock,"vendor stock restored without refresh")
	check(SAVE.save_game(game,state,"user://progression_test.save").ok,"second save keeps backup")
	check(SAVE.read_snapshot("user://progression_test.save.bak").ok,"backup valid")
	var invalid := snapshot.duplicate(true)
	invalid.items[0].definition.erase("price")
	check(not SAVE.validate(invalid,game).is_empty(),"missing item definition rejected")
	invalid = snapshot.duplicate(true)
	invalid.items.append(invalid.items[0].duplicate(true))
	check(not SAVE.validate(invalid,game).is_empty(),"duplicate item identity rejected")
	invalid = snapshot.duplicate(true)
	invalid.world._day_minutes = NAN
	check(not SAVE.validate(invalid,game).is_empty(),"non-finite values rejected")
	var file := FileAccess.open("user://progression_test.save",FileAccess.WRITE)
	file.store_string("damaged")
	file.close()
	before = game._money
	check(not SAVE.load_game(game,state,"user://progression_test.save").ok and game._money == before,"corruption leaves game untouched")
	check(SAVE.load_game(game,state,"user://progression_test.save.bak").ok,"backup recovery")
	for kind in ["magazine","catalog","skills","strategy","ledger","save"]:
		game._progression_panel.open_page(kind)
		check(game._progression_panel.opened and game._speed == 0,"page pauses: " + kind)
	game._progression_panel.close_page()
	print("PROGRESSION_CHECKS ",checks," FAILURES ",failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
