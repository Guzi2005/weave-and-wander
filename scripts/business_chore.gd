extends RefCounted

# A real navigation/reach task. Other schedulers must respect chore_reserved.
var game: Node
var actor: Node3D
var phase := "idle"
var kind := ""
var elapsed := 0.0
var destination := Vector3.ZERO
var hand_target := Vector3.ZERO
var completed: Array[String] = []

func _init(controller: Node) -> void:
	game = controller

func start(task: String, stand_at: Vector3, touch_at: Vector3) -> void:
	assert(phase == "idle")
	kind = task
	actor = null
	destination = stand_at
	hand_target = touch_at
	elapsed = 0.0
	phase = "waiting"

func choose_worker() -> Node3D:
	var best: Node3D
	var best_score := INF
	for worker in game.staff:
		if not is_instance_valid(worker) or not worker.visible or bool(worker.get_meta("shift_departing", false)):
			continue
		if game._production.actor == worker or game._dye.actor == worker or worker.energy <= .25:
			continue
		var job: Dictionary = game._staff_jobs.get(worker.get_instance_id(), {})
		if job.get("phase", "idle") != "idle":
			continue
		var route: PackedVector3Array = game._navigation.route(worker.global_position, destination)
		if route.is_empty():
			continue
		var distance := 0.0
		var previous: Vector3 = worker.global_position
		for point in route:
			distance += previous.distance_to(point)
			previous = point
		var score: float = distance + (1.0 - worker.energy) * 4.0
		if score < best_score:
			best = worker
			best_score = score
	return best

func advance(delta: float) -> void:
	if phase == "idle" or delta <= 0:
		return
	if phase == "waiting":
		actor = choose_worker()
		if actor == null:
			return
		actor.set_meta("chore_reserved", true)
		game._set_staff_idle(actor, 100000)
		game._staff_jobs[actor.get_instance_id()].phase = "business_chore"
		actor.set_destination(destination, "stocking")
		phase = "walking"
	if phase == "walking":
		if not actor.has_arrived():
			return
		actor.resting_facing = atan2(hand_target.x-actor.global_position.x, hand_target.z-actor.global_position.z)
		actor.set_activity("stocking")
		phase = "reaching"
	if phase == "reaching":
		elapsed += delta
		actor.reach("R", hand_target)
		actor.apply_reaches()
		if elapsed >= .65:
			game._apply_business_chore(kind)
			phase = "finishing"
	elif phase == "finishing":
		elapsed += delta
		actor.reach("R", hand_target)
		actor.apply_reaches()
		if elapsed >= 1.8:
			actor.clear_interaction()
			actor.set_meta("chore_reserved", false)
			game._set_staff_idle(actor, .3)
			completed.append(kind)
			phase = "idle"
