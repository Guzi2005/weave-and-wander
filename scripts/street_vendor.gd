extends Node3D
## One deterministic daily stock ledger, independent of visibility and menu visits.
signal stock_changed
const OPEN_MINUTE := 480.0
const CLOSE_MINUTE := 1080.0
const ROUTE_SPEED := 1.35
const GOODS := [
	{"id":"cotton", "name":"湖蓝棉布", "batch":"opening_cloth", "kind":"fabric", "amount":2.0, "price":18, "stock":5, "color":"779ab1"},
	{"id":"check", "name":"蔷薇格纹布", "batch":"rose_check", "kind":"fabric", "amount":2.0, "price":22, "stock":3, "color":"bb7986"},
	{"id":"linen", "name":"鼠尾草亚麻", "batch":"sage_linen", "kind":"fabric", "amount":2.0, "price":26, "stock":3, "color":"8ba28a"},
	{"id":"thread", "name":"本色棉线", "batch":"thread_cream", "kind":"thread", "amount":20.0, "price":6, "stock":6, "color":"dcd2b5"},
]
var game: Node
var stock: Dictionary = {}
var stock_day := 0
var phase := "away"
var route_x := -24.0
var receipts: Array[Dictionary] = []
var _receipt_serial := 0
var _last_day := 0
var _last_minutes := 0.0
var _cart: Node3D
var _grandmother: Node3D
var _wheels: Array[Node3D] = []
var _panel: Control
var _host: Node3D

func setup(controller: Node, street: Node3D = null) -> void:
	game = controller
	_host = street
	if street != null:
		var lane := street.get_node_or_null("FloorLane")
		if lane != null and get_parent() != lane:
			if get_parent() != null: reparent(lane, false)
			else: lane.add_child(self)
		_build_visuals()
		if is_instance_valid(game._pop_up) and game._pop_up.has_method("register_dynamic_page"):
			game._pop_up.register_dynamic_page(self,3)
		tick(0.0, game._day_index, game._day_minutes)

func _build_visuals() -> void:
	if _cart != null: return
	if ResourceLoader.exists("res://assets/street_vendor/notions_cart.glb"):
		_cart = load("res://assets/street_vendor/notions_cart.glb").instantiate()
		_cart.name = "NotionsCart"
		add_child(_cart)
		for child in _cart.find_children("Wheel*", "Node3D", true, false):
			if str(child.name).begins_with("WheelFront") or str(child.name).begins_with("WheelBack"): _wheels.append(child)
	_grandmother = preload("res://scripts/vendor_grandmother.gd").new()
	_grandmother.name = "VendorGrandmother"
	add_child(_grandmother)
	_grandmother.configure({"name":"推车奶奶", "role":"vendor", "outfit":0, "hair":1, "skin_color":Color("ffd6c1"), "hair_color":Color("252526"), "speed":ROUTE_SPEED})
	_grandmother.scale = Vector3(1.12, .88, 1.08)
	_grandmother.position = Vector3(2.15,0,0)

func tick(delta: float, day: int, minutes: float) -> void:
	_last_day = day
	_last_minutes = minutes
	if day > stock_day and minutes >= OPEN_MINUTE:
		stock_day = day
		stock.clear()
		for offer in GOODS: stock[offer.id] = offer.stock
		# Advancing the calendar skips the night, including an unfinished departure.
		route_x = -24.0
		phase = "away"
		stock_changed.emit()
	var may_trade := minutes >= OPEN_MINUTE and minutes < CLOSE_MINUTE
	if may_trade and phase == "away":
		# Finishing yesterday's departure after a fast day skip starts a new entrance
		# only while hidden outside the stage, never teleporting an onstage cart.
		if route_x >= 24.0: route_x = -24.0
		phase = "arriving"
	if not may_trade and phase in ["arriving", "trading"]: phase = "leaving"
	var old_x := route_x
	if phase == "arriving":
		route_x = move_toward(route_x, 0.0, maxf(delta,0.0) * ROUTE_SPEED)
		if is_zero_approx(route_x): phase = "trading"
	elif phase == "leaving":
		route_x = move_toward(route_x,24.0,maxf(delta,0.0) * ROUTE_SPEED)
		if route_x >= 24.0: phase = "away"
	position = Vector3(route_x,.06,3.4)
	visible = phase != "away"
	set_meta("presentation_hidden",phase == "away")
	if is_instance_valid(_cart): _cart.visible = visible
	if is_instance_valid(_grandmother): _grandmother.visible = visible
	var distance := route_x-old_x
	for wheel in _wheels: wheel.rotation.z -= distance / .64
	if is_instance_valid(_grandmother):
		var walking := phase in ["arriving","leaving"]
		_grandmother._moving = walking
		_grandmother._heading = Vector3.RIGHT
		_grandmother._travel_distance += absf(distance)
		_grandmother.resting_facing = 0.0
		_grandmother._work_phase += maxf(delta,0.0)
		_grandmother._update_puppet_motion(maxf(delta,0.0))
		if walking:
			_grandmother.reach("L", to_global(Vector3(1.85,1.05,-.36)))
			_grandmother.reach("R", to_global(Vector3(1.85,1.05,.36)))
			_grandmother.apply_reaches()
		else: _grandmother.clear_interaction()

func is_trading() -> bool:
	return phase == "trading" and _last_minutes >= OPEN_MINUTE and _last_minutes < CLOSE_MINUTE

func purchase(offer_id: String, quantity: int = 1) -> Dictionary:
	if not is_trading(): return {"ok":false,"reason":"奶奶正在赶路，清晨到黄昏之间来逛逛吧。"}
	if quantity < 1 or quantity > 20: return {"ok":false,"reason":"数量无效"}
	var offer: Dictionary = {}
	for value in GOODS:
		if value.id == offer_id: offer = value
	if offer.is_empty(): return {"ok":false,"reason":"没有这件货品"}
	if int(stock.get(offer_id,0)) < quantity: return {"ok":false,"reason":"今天卖完了，明早再来吧。"}
	var cost: int = int(offer.price)*quantity
	if game == null or int(game._money) < cost: return {"ok":false,"reason":"零钱不够"}
	var ledger = game._inventory.materials
	var batch: Dictionary = ledger.fabric(offer.batch) if offer.kind == "fabric" else ledger.thread(offer.batch)
	if batch.is_empty(): return {"ok":false,"reason":"材料柜未准备好"}
	if batch.get("pigment",Color(offer.color)) != Color(offer.color):
		return {"ok":false,"reason":"这批材料已经染色，不能把另一颜色混入同一布卷。"}
	# Refill a real compatible batch: the existing package mesh reads these meters.
	var amount: float = float(offer.amount)*quantity
	game._money -= cost
	stock[offer_id] = int(stock[offer_id])-quantity
	batch.meters = float(batch.meters)+amount
	batch.capacity_m = maxf(float(batch.get("capacity_m",batch.meters)),float(batch.meters))
	_receipt_serial += 1
	var receipt := {"id":"vendor_%d" % _receipt_serial,"day":stock_day,"offer":offer_id,"batch":offer.batch,"amount":amount,"cost":cost,"source":"backstreet_vendor"}
	receipts.append(receipt)
	ledger.events.append({"event":"purchased","batch_id":offer.batch,"meters":amount,"cost":cost,"receipt_id":receipt.id})
	stock_changed.emit()
	return {"ok":true,"reason":"已收好 %s，花费 %d" % [offer.name,cost],"receipt":receipt}

func open_shop() -> void:
	if not is_instance_valid(_panel):
		_panel = preload("res://scripts/vendor_panel.gd").new()
		var layer := CanvasLayer.new()
		layer.layer = 35
		game.add_child(layer)
		layer.add_child(_panel)
		_panel.setup(self,game)
	_panel.open()

func export_state() -> Dictionary:
	return {"stock_day":stock_day,"stock":stock.duplicate(true),"phase":phase,"route_x":route_x,"receipts":receipts.duplicate(true),"receipt_serial":_receipt_serial,"day":_last_day,"minutes":_last_minutes}

func import_state(data: Dictionary) -> bool:
	if not data.get("stock") is Dictionary or str(data.get("phase","")) not in ["away","arriving","trading","leaving"]: return false
	if not is_finite(float(data.get("route_x",NAN))) or absf(float(data.route_x)) > 24.0: return false
	for offer in GOODS:
		var amount: int = int(data.stock.get(offer.id,-1))
		if amount < 0 or amount > int(offer.stock): return false
	stock_day = int(data.get("stock_day",0))
	stock = data.stock.duplicate(true)
	phase = str(data.phase)
	route_x = float(data.route_x)
	_receipt_serial = int(data.get("receipt_serial",0))
	receipts.clear()
	for receipt in data.get("receipts",[]):
		if receipt is Dictionary: receipts.append(receipt.duplicate(true))
	_last_day = int(data.get("day",stock_day))
	_last_minutes = float(data.get("minutes",540.0))
	tick(0.0,_last_day,_last_minutes)
	return true
