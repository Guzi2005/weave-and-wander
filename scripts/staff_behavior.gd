extends RefCounted

const BT = preload("res://scripts/behavior_tree.gd")
const Personality = preload("res://scripts/personality.gd")
const REST_AT := 0.25
const RESUME_AT := 0.85
const WORK_DRAIN := 0.0022
const WALK_DRAIN := 0.0008
const IDLE_DRAIN := 0.00025
const REST_GAIN := 0.028
const NAP_GAIN := 0.045


static func rest_threshold_for(doll: PaperDoll) -> float:
	return Personality.rest_threshold(doll.personality, REST_AT)


static func recovery_scale_for(doll: PaperDoll) -> float:
	return Personality.recovery_scale(doll.personality)

var actor: PaperDoll
var shop: Node
var tree: BT.BTNode
var recovering := false
var resume_facility := -1
var retry_after := 0.0
var breaks_started := 0
var breaks_completed := 0


func _init(doll: PaperDoll, controller: Node) -> void:
	actor = doll
	shop = controller
	tree = BT.BTSelector.new([
		BT.BTSequence.new([BT.BTCondition.new(_needs_break), BT.BTAction.new(_rest)]),
		BT.BTAction.new(_work),
	])


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var job: Dictionary = shop._staff_jobs.get(actor.get_instance_id(), {})
	var at_rest: bool = _is_rest_job(job) and job.get("phase") == "work" and actor.has_arrived()
	if at_rest:
		var bench: Node3D = shop.facilities[job.facility].get("rest_bench")
		if bench != null:
			bench.support_actor(actor)
		var gain := NAP_GAIN if bench != null and bench.mode_for(actor) == "nap" else REST_GAIN
		actor.energy = minf(1.0, actor.energy + delta * gain * recovery_scale_for(actor))
	else:
		var drain := WALK_DRAIN if actor.is_moving() else (WORK_DRAIN if job.get("phase") in ["work","production","dyeing"] else IDLE_DRAIN)
		actor.energy = maxf(0.0, actor.energy - delta * drain)
	retry_after = maxf(0.0, retry_after - delta)
	tree.tick(actor, delta)


func cancel_break() -> void:
	recovering = false
	resume_facility = -1


func _is_rest_job(job: Dictionary) -> bool:
	var index: int = job.get("facility", -1)
	return index >= 0 and index < shop.facilities.size() and shop.facilities[index].activity == "resting"


func _needs_break(_doll: Node, _delta: float) -> bool:
	# Once closing starts, finish the accepted job before leaving. Starting a
	# break here would park its materials, then the shift scheduler would send
	# the worker home while that order was still unfinished.
	var job: Dictionary = shop._staff_jobs.get(actor.get_instance_id(), {})
	if bool(actor.get_meta("shift_home_pending", false)) and not recovering and not _is_rest_job(job):
		return false
	if not recovering and actor.energy > .15 and Personality.value(actor.personality, "persistence") >= .65 and job.get("phase") in ["work","production","dyeing"] and not _is_rest_job(job):
		return false
	return recovering or actor.energy <= rest_threshold_for(actor) or _is_rest_job(shop._staff_jobs.get(actor.get_instance_id(), {}))


func _rest(_doll: Node, _delta: float, _first: bool) -> int:
	if is_instance_valid(shop._production) and shop._production.actor == actor and shop._production.phase == "park":
		return BT.Status.SUCCESS
	var job: Dictionary = shop._staff_jobs.get(actor.get_instance_id(), {})
	if not recovering:
		recovering = true
		breaks_started += 1
		resume_facility = int(job.get("facility", -1)) if job.get("manual", false) and not _is_rest_job(job) else -1
		if not _is_rest_job(job):
			shop._set_staff_idle(actor, 0.0)
			job = shop._staff_jobs[actor.get_instance_id()]
	if _is_rest_job(job):
		if actor.navigation_status == "blocked":
			shop._set_staff_idle(actor, 0.0)
			retry_after = 1.0
		elif actor.has_arrived() and actor.energy >= RESUME_AT:
			if job.has("facility") and shop.facilities[job.facility].has("rest_bench") and actor._rest_blend > 0.0:
				actor.rest_departing = true
				return BT.Status.SUCCESS
			var previous := resume_facility
			shop._set_staff_idle(actor, 0.0)
			cancel_break()
			breaks_completed += 1
			if previous >= 0 and not is_instance_valid(shop.facilities[previous].staff):
				shop._assign_staff(actor, previous, true)
			else:
				shop._assign_next_autonomous_job(actor)
		return BT.Status.SUCCESS
	actor.set_activity("waiting")
	if retry_after > 0.0:
		return BT.Status.SUCCESS
	retry_after = 1.0
	var best := -1
	var best_distance := INF
	for index in shop.facilities.size():
		var facility: Dictionary = shop.facilities[index]
		if facility.activity != "resting" or is_instance_valid(facility.staff):
			continue
		if shop._navigation.room_at(facility.anchor.global_position) != facility.room:
			continue
		var target: Vector3 = facility.anchor.global_position
		var bench: Node3D = facility.get("rest_bench")
		if bench != null:
			var seats: Array = bench.available_span(actor.energy <= .15)
			if seats.is_empty(): continue
			target = bench.to_global(Vector3(((seats.front()+seats.back())*.5-1.0)*bench.SEAT_SPACING,0,1.28))
		var route: PackedVector3Array = shop._navigation.route(actor.global_position, target)
		if route.is_empty():
			continue
		var distance := 0.0
		var previous := actor.global_position
		for point in route:
			distance += previous.distance_to(point)
			previous = point
		if distance < best_distance:
			best = index
			best_distance = distance
	if best >= 0:
		shop._assign_staff(actor, best, false)
	return BT.Status.SUCCESS


func _work(_doll: Node, delta: float, _first: bool) -> int:
	shop._tick_staff_job(actor, delta)
	return BT.Status.SUCCESS
