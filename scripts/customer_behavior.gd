class_name CustomerBehavior
extends RefCounted

const BT = preload("res://scripts/behavior_tree.gd")
const CustomerDoll = preload("res://scripts/customer_doll.gd")
const PaperDollBase = preload("res://scripts/paper_doll.gd")

var actor: CustomerDoll
var visit: Node
var tree: BT.BTNode
var stage := "to_browse"
var finished := false
var bought := false
var buy_wearing := false
var reason := ""
var item: Node3D
var selection: Array[Node3D] = []
var accepted: Array[Node3D] = []
var rejected: Array[Node3D] = []
var _pickup_index := 0
var _pickup_started := false
var browse_slot := 0
var _restart := false
var _blocked_message := false
var _rng := RandomNumberGenerator.new()


func _init(customer: CustomerDoll, controller: Node, slot: int) -> void:
	actor = customer
	visit = controller
	browse_slot = slot
	_rng.seed = hash(actor.customer_id)
	tree = BT.BTSequence.new([
		BT.BTAction.new(_move.bind("to_browse", "browse_%d" % browse_slot, "browsing")),
		BT.BTAction.new(_face.bind(PI)),
		BT.BTAction.new(_browse),
		BT.BTWait.new(2.6),
		BT.BTAction.new(_choose),
		BT.BTSelector.new([
			BT.BTSequence.new([
				BT.BTCondition.new(_has_item),
				BT.BTAction.new(_collect_selection),
				BT.BTAction.new(_move.bind("to_fitting", "fitting_queue", "fitting")),
				_change_booth(_put_on),
				BT.BTAction.new(_move.bind("to_mirror", "customer_mirror", "fitting")),
				BT.BTAction.new(_face.bind(PI)),
				BT.BTAction.new(_set_stage.bind("mirror_wait")),
				BT.BTWait.new(2.0),
				BT.BTAction.new(_decide),
				BT.BTSelector.new([
					BT.BTCondition.new(_no_change_needed),
					BT.BTSequence.new([
						BT.BTAction.new(_move.bind("to_fitting_change", "fitting_queue", "fitting")),
						_change_booth(_take_off),
					]),
				]),
				BT.BTSelector.new([
					BT.BTCondition.new(_no_returns),
					BT.BTSequence.new([
						BT.BTAction.new(_move.bind("to_basket", "return_basket", "stocking")),
						BT.BTAction.new(_return_item),
					]),
				]),
				BT.BTSelector.new([
					BT.BTSequence.new([
						BT.BTCondition.new(_will_buy),
						BT.BTAction.new(_move.bind("to_checkout", "customer_checkout", "checkout")),
						BT.BTAction.new(_face.bind(PI)),
						BT.BTAction.new(_checkout),
					]),
					BT.BTSequence.new([
						BT.BTAction.new(_maybe_try_another),
					]),
				]),
			]),
			BT.BTAction.new(_give_up),
		]),
		BT.BTAction.new(_visit_tea),
		BT.BTAction.new(_move.bind("to_exit", actor.get_meta("street_exit"), "leaving")),
		BT.BTAction.new(_finish),
	])


func _visit_tea(_customer: Node, _delta: float, first: bool) -> int:
	if first:
		if visit._mints.stock <= 0 or _rng.randf() > .55:
			return BT.Status.SUCCESS
		stage = "to_tea"
		actor.move_to_anchor(visit._shop.interaction_anchor("rest"), "browsing")
	if actor.navigation_status == "blocked": return BT.Status.SUCCESS
	if not actor.has_arrived(): return BT.Status.RUNNING
	if visit._mints.serve(actor): actor.think("一颗薄荷糖，谢谢！")
	return BT.Status.SUCCESS


func _change_booth(change: Callable) -> BT.BTNode:
	return BT.BTSequence.new([
		BT.BTAction.new(_request_fitting),
		BT.BTAction.new(_move.bind("entering_booth", "fitting", "fitting")),
		BT.BTAction.new(_face.bind(0.0)),
		BT.BTAction.new(_curtain.bind(true)),
		BT.BTAction.new(change),
		BT.BTWait.new(1.8),
		BT.BTAction.new(_curtain.bind(false)),
		BT.BTAction.new(_move.bind("exiting_booth", "fitting_exit", "fitting")),
		BT.BTAction.new(_release_fitting),
	])


func tick(delta: float) -> void:
	if finished or delta <= 0.0:
		return
	var result := tree.tick(actor, delta)
	if _restart:
		_restart = false
		tree.reset()
	elif result == BT.Status.FAILURE:
		# A blocked fixture can be changed by the player; keep the customer in the tree.
		tree.reset()


func close_shop() -> void:
	# Finish fitting, returns and checkout using the normal inventory lifecycle.
	# Closing only prevents another shopping round.
	actor.profile.retries_left = 0
	_restart = false


func _move(_customer: Node, _delta: float, first: bool, next_stage: String, target: Variant, activity: String) -> int:
	stage = next_stage
	if first:
		_blocked_message = false
		if target is Vector3:
			actor.set_destination(target, activity)
		else:
			var key := str(target)
			if key == "pickup":
				key = "pickup_%d" % item.slot
			var anchor: Node3D = visit._shop.interaction_anchor(key)
			if key == "fitting_queue":
				anchor = visit._shop.fitting_room.join(actor)
			elif key == "customer_checkout":
				anchor = visit._shop.checkout_queue.join(actor)
			actor.move_to_anchor(anchor, activity)
	if actor.navigation_status == "blocked" and not _blocked_message:
		actor.think("这里暂时走不过去，等一等")
		_blocked_message = true
	return BT.Status.SUCCESS if actor.has_arrived() else BT.Status.RUNNING


func _set_stage(_customer: Node, _delta: float, _first: bool, value: String) -> int:
	stage = value
	if value == "mirror_wait":
		actor.set_activity("thinking")
	return BT.Status.SUCCESS


func _face(_customer: Node, _delta: float, _first: bool, angle: float) -> int:
	actor.resting_facing = angle
	if actor.destination_anchor != null:
		var marker: Node3D = actor.destination_anchor.get_ref()
		if is_instance_valid(marker):
			actor.resting_facing += marker.global_rotation.y
	return BT.Status.SUCCESS


func _browse(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "browse_wait"
	actor.think(actor.profile.wish_text(), PaperDollBase.OUTFIT_PALETTES[actor.profile.favorite_palette][0])
	return BT.Status.SUCCESS


func _choose(_customer: Node, _delta: float, _first: bool) -> int:
	for piece in selection:
		if piece.location == "rack":
			visit._inventory.return_item(piece, actor)
	var choice: Dictionary = visit._inventory.choose_for(actor, actor.profile)
	item = choice["item"]
	selection.assign(choice.get("items", []))
	accepted.clear()
	rejected.clear()
	_pickup_index = 0
	_pickup_started = false
	reason = choice["reason"]
	if item != null:
		actor.think("试试%s，共%d件" % [item.definition.display_name(), selection.size()], _swatch(item))
	return BT.Status.SUCCESS


func _collect_selection(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "to_pickup"
	if _pickup_index >= selection.size():
		return BT.Status.SUCCESS
	var piece: Node3D = selection[_pickup_index]
	if not _pickup_started:
		actor.move_to_anchor(visit._inventory.pickup_anchor(piece), "browsing")
		_pickup_started = true
	if not actor.has_arrived():
		return BT.Status.RUNNING
	if not visit._inventory.pick_up(piece, actor):
		return BT.Status.FAILURE
	_pickup_index += 1
	_pickup_started = false
	return BT.Status.RUNNING


func _has_item(_customer: Node, _delta: float) -> bool:
	return item != null


func _carry(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "carrying"
	return BT.Status.SUCCESS if visit._inventory.pick_up(item, actor) else BT.Status.FAILURE


func _request_fitting(_customer: Node, _delta: float, first: bool) -> int:
	stage = "fitting_wait"
	var granted: bool = visit._shop.fitting_room.request(actor)
	if not granted and first:
		actor.think("等试衣间空出来")
	return BT.Status.SUCCESS if granted else BT.Status.RUNNING


func _curtain(_customer: Node, _delta: float, first: bool, closed: bool) -> int:
	var room: Node = visit._shop.fitting_room
	if first:
		room.close_for(actor, closed)
	var done: bool = room.is_closed() if closed else room.is_open()
	return BT.Status.SUCCESS if done else BT.Status.RUNNING


func _put_on(_customer: Node, _delta: float, _first: bool) -> int:
	for piece in selection:
		if not actor.put_on(piece):
			return BT.Status.FAILURE
	return BT.Status.SUCCESS


func _take_off(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "changing_back"
	for piece in selection:
		if piece in rejected or not buy_wearing:
			if not actor.take_off(piece):
				return BT.Status.FAILURE
	return BT.Status.SUCCESS


func _release_fitting(_customer: Node, _delta: float, _first: bool) -> int:
	visit._shop.fitting_room.release(actor)
	return BT.Status.SUCCESS


# Fit is only discovered in the mirror; colour and price were already visible on the rack.
func _decide(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "decision"
	var profile: RefCounted = actor.profile
	accepted.clear()
	rejected.clear()
	for piece in selection:
		var definition: Resource = piece.definition
		var colour: float = profile.color_score(definition) * profile.color_weight
		var fit := _rng.randf_range(-0.30, 0.2)
		var value := float(profile.budget - visit._inventory.sale_price(piece)) / float(maxi(1,profile.budget)) * 0.28
		var score := 0.32 + colour + fit + value
		var keep: bool = score >= profile.threshold
		(accepted if keep else rejected).append(piece)
		var item_reason := "合适，留下" if keep else ("颜色不太喜欢" if colour < 0 else "不太合身")
		visit._inventory.record("decided", piece, actor, {"bought": keep, "reason": item_reason, "score": snappedf(score, .01)})
	bought = not accepted.is_empty()
	buy_wearing = bought and _rng.randf() < profile.wear_out_chance
	reason = "留下%d件，退回%d件" % [accepted.size(), rejected.size()] if bought else "不太合适，再看看"
	actor.think(reason, _swatch(item))
	return BT.Status.SUCCESS


func _will_buy(_customer: Node, _delta: float) -> bool:
	return bought


func _no_change_needed(_customer: Node, _delta: float) -> bool:
	return rejected.is_empty() and buy_wearing


func _no_returns(_customer: Node, _delta: float) -> bool:
	return rejected.is_empty()


func _will_buy_wearing(_customer: Node, _delta: float) -> bool:
	return buy_wearing


func _checkout(_customer: Node, delta: float, first: bool) -> int:
	stage = "checkout_wait"
	if first:
		actor.set_meta("checkout_wait", 1.7)
	if not visit._shop.checkout_queue.is_first(actor):
		return BT.Status.RUNNING
	var counter: Marker3D = visit._shop.interaction_anchor("customer_checkout")
	if actor.destination_anchor == null or actor.destination_anchor.get_ref() != counter:
		actor.move_to_anchor(counter, "checkout")
	if not actor.has_arrived():
		return BT.Status.RUNNING
	if not visit._cashier_present():
		visit._shop.checkout_exchange.cancel()
		actor.set_meta("checkout_wait", 1.7)
		if actor.thought_time <= 0:
			actor.think("柜台没人，等一等")
		return BT.Status.RUNNING
	var cashier: Node3D = visit.facilities[visit._facility_index("counter","shop")].staff
	var service_rate := 1.0
	if is_instance_valid(visit.get("_progression")):
		service_rate = visit._progression.service_multiplier(cashier)
	if not visit._shop.checkout_exchange.advance(actor,cashier,delta * service_rate,accepted):
		stage = visit._shop.checkout_exchange.phase
		return BT.Status.RUNNING
	var amount := 0
	for piece in accepted:
		var price: int = visit._inventory.checkout(piece, actor)
		if price > 0:
			amount += price
			visit._sales_count += 1
	if amount <= 0:
		visit._shop.checkout_exchange.cancel()
		return BT.Status.FAILURE
	visit._shop.checkout_exchange.finish()
	visit._money += amount
	visit._shop.checkout_queue.leave(actor)
	visit._show_toast("%s买下了%d件单品  +%d" % [actor.profile.title, accepted.size(), amount])
	return BT.Status.SUCCESS


func _return_item(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "returning_garment"
	for piece in rejected:
		actor.release_item(visit._inventory, piece)
	return BT.Status.SUCCESS


func _maybe_try_another(_customer: Node, _delta: float, _first: bool) -> int:
	if actor.profile.retries_left > 0 and not visit._inventory.on_rack().is_empty():
		actor.profile.retries_left -= 1
		actor.think("再看看别的")
		_restart = true
		return BT.Status.RUNNING
	return BT.Status.SUCCESS


func _give_up(_customer: Node, _delta: float, _first: bool) -> int:
	actor.think(reason if not reason.is_empty() else "下次再来")
	return BT.Status.SUCCESS


func _finish(_customer: Node, _delta: float, _first: bool) -> int:
	stage = "done"
	finished = true
	visit._complete_customer(actor)
	return BT.Status.SUCCESS


func _swatch(garment: Node3D) -> Color:
	return PaperDollBase.OUTFIT_PALETTES[garment.definition.palette_index][0]
