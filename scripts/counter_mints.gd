extends RefCounted

# Front-counter mint bowl. A finite bowl serves customers and staff; a finite
# tin in the back is the only refill source, so replenishment cannot loop
# forever. Staff gain exactly +ENERGY_BONUS once per serving and only after
# STAFF_COOLDOWN — mints never provide passive rest regeneration.
const STOCK_MAX := 12
const STOCK_START := 8
const LOW_STOCK := 3
const RESERVE_START := 12
const REFILL_BATCH := 6
const ENERGY_BONUS := 0.05
const STAFF_COOLDOWN := 45.0

var game: Node
var stock := STOCK_START
var reserve := RESERVE_START
var servings := 0
var restocks_completed := 0
var _cooldowns: Dictionary = {}
var _restock_phase := "idle" # idle -> waiting -> walking -> reaching -> finishing
var _worker: Node3D
var _elapsed := 0.0
var _retry_in := 0.0
var _bowl: Node3D
var _pieces: Array[Node3D] = []


func setup(controller: Node) -> void:
	game = controller
	_bowl = game._shop.get_node("TeaCorner/MintBowl")
	if _bowl != null:
		for child in _bowl.get_children():
			if str(child.name).begins_with("Mint"):
				_pieces.append(child)
	_sync_bowl()


func cooldown_left(actor: Node3D) -> float:
	return float(_cooldowns.get(actor.get_instance_id(), 0.0))


func can_serve(actor: Node3D) -> bool:
	if stock <= 0:
		return false
	if actor.role == "staff" and (cooldown_left(actor) > 0.0 or actor.energy > 0.95):
		return false
	return true


func serve(actor: Node3D) -> bool:
	if not can_serve(actor):
		return false
	stock -= 1
	servings += 1
	if actor.role == "staff":
		actor.energy = minf(1.0, actor.energy + ENERGY_BONUS)
		_cooldowns[actor.get_instance_id()] = STAFF_COOLDOWN
	_sync_bowl()
	_check_low_stock()
	return true


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for id in _cooldowns.keys():
		_cooldowns[id] = maxf(0.0, float(_cooldowns[id]) - delta)
	_advance_restock(delta)


func bowl_position() -> Vector3:
	if is_instance_valid(_bowl):
		return _bowl.to_global(Vector3(0, .10, 0))
	return game._shop.interaction_anchor("rest").global_position




func _check_low_stock() -> void:
	# One pending replenishment at a time; the phase gate rejects duplicates.
	if stock <= LOW_STOCK and reserve > 0 and _restock_phase == "idle":
		_restock_phase = "waiting"


func _choose_worker() -> Node3D:
	var best: Node3D
	var best_distance := INF
	var target: Vector3 = game._shop.interaction_anchor("rest").global_position
	for worker in game.staff:
		if not is_instance_valid(worker) or not worker.visible:
			continue
		if bool(worker.get_meta("chore_reserved", false)):
			continue
		if bool(worker.get_meta("shift_home", false)) or bool(worker.get_meta("shift_departing", false)):
			continue
		if game._production.actor == worker or game._dye.actor == worker:
			continue
		if worker.energy <= game.StaffBehaviorScript.rest_threshold_for(worker):
			continue
		var job: Dictionary = game._staff_jobs.get(worker.get_instance_id(), {})
		if job.get("phase", "idle") != "idle":
			continue
		var route: PackedVector3Array = game._navigation.route(worker.global_position, target)
		if route.is_empty():
			continue
		var distance := 0.0
		var previous: Vector3 = worker.global_position
		for point in route:
			distance += previous.distance_to(point)
			previous = point
		if distance < best_distance:
			best = worker
			best_distance = distance
	return best


func _release_worker(delay := 0.3) -> void:
	if is_instance_valid(_worker):
		_worker.clear_interaction()
		_worker.set_meta("chore_reserved", false)
		game._set_staff_idle(_worker, delay)
	_worker = null


func _advance_restock(delta: float) -> void:
	if _restock_phase == "idle":
		_check_low_stock()
		return
	if _restock_phase == "waiting":
		_retry_in = maxf(0.0, _retry_in - delta)
		if _retry_in > 0.0: return
		_worker = _choose_worker()
		if _worker == null:
			_retry_in = .5
			return
		_worker.set_meta("chore_reserved", true)
		game._set_staff_idle(_worker, 100000)
		game._staff_jobs[_worker.get_instance_id()].phase = "business_chore"
		_worker.move_to_anchor(game._shop.interaction_anchor("rest"), "stocking")
		_restock_phase = "walking"
		return
	if not is_instance_valid(_worker) or bool(_worker.get_meta("shift_departing", false)):
		_release_worker()
		_restock_phase = "idle"
		return
	if _restock_phase == "walking":
		if _worker.navigation_status == "blocked":
			_release_worker()
			_restock_phase = "waiting"
			return
		if not _worker.has_arrived():
			return
		_worker.resting_facing = atan2(bowl_position().x - _worker.global_position.x, bowl_position().z - _worker.global_position.z)
		_worker.set_activity("stocking")
		_elapsed = 0.0
		_restock_phase = "reaching"
	elif _restock_phase == "reaching":
		_elapsed += delta
		_worker.reach("R", bowl_position())
		_worker.apply_reaches()
		if _elapsed >= .8:
			# Bounded by bowl space and by the finite tin: no infinite refill.
			var moved: int = mini(REFILL_BATCH, mini(STOCK_MAX - stock, reserve))
			if moved > 0:
				stock += moved
				reserve -= moved
				restocks_completed += 1
				game._show_toast("补充柜台薄荷糖 +%d" % moved)
				_sync_bowl()
			_restock_phase = "finishing"
	elif _restock_phase == "finishing":
		_elapsed += delta
		_worker.reach("R", bowl_position())
		_worker.apply_reaches()
		if _elapsed >= 1.6:
			_release_worker()
			_restock_phase = "idle"
			# Still low (or emptied while walking)? Queue the next tin refill once.
			_check_low_stock()


func _sync_bowl() -> void:
	var visible_count := 0 if stock <= 0 else clampi(ceili(float(stock) / STOCK_MAX * _pieces.size()), 1, _pieces.size())
	for index in _pieces.size():
		_pieces[index].visible = index < visible_count
