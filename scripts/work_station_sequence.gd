class_name WorkStationSequence
extends RefCounted

## Unified Workshop Simulation State Machine Protocol ("Lego Brick" station driver).
##
## Standardizes:
## 1. Travel vs. stationary phases and arrival-action transitions
## 2. Multi-anchor blocked-navigation fallback (no teleportation)
## 3. Per-phase readiness gate (`action_ready`) reset on phase transition
## 4. Safe interruption / parking vs. immediate suspension
## 5. Idempotent single-debit transaction guard (`commit_once`)
## 6. Live station snapshot & manual player craft assist (`nudge_step`)

signal phase_changed(station_id: String, old_phase: String, new_phase: String)
signal transaction_committed(station_id: String, transaction_key: String)

var station_id := ""
var phase_labels: Dictionary = {}
var travel_phases: Array[String] = []
var arrival_actions: Dictionary = {}
var suspend_immediate: Array[String] = []
var phase_durations: Dictionary = {}
var committed_keys: Dictionary = {}


func _init(id: String = "station", config: Dictionary = {}) -> void:
	station_id = id
	configure(config)


func configure(config: Dictionary) -> void:
	if config.has("labels"):
		phase_labels = (config["labels"] as Dictionary).duplicate()
	if config.has("travel_phases"):
		travel_phases.clear()
		for p in config["travel_phases"]:
			travel_phases.append(String(p))
	if config.has("arrival_actions"):
		arrival_actions = (config["arrival_actions"] as Dictionary).duplicate()
	if config.has("suspend_immediate"):
		suspend_immediate.clear()
		for p in config["suspend_immediate"]:
			suspend_immediate.append(String(p))
	if config.has("durations"):
		phase_durations = (config["durations"] as Dictionary).duplicate()


func is_travel_phase(phase: String) -> bool:
	return phase in travel_phases


func arrival_action_for(phase: String) -> String:
	return String(arrival_actions.get(phase, ""))


func can_suspend_immediately(phase: String) -> bool:
	return phase in suspend_immediate


func label_for(phase: String) -> String:
	return String(phase_labels.get(phase, phase))


func duration_for(phase: String, fallback: float = 1.25) -> float:
	return maxf(0.05, float(phase_durations.get(phase, fallback)))


func notify_phase_entered(old_phase: String, new_phase: String) -> void:
	if new_phase == "idle":
		committed_keys.clear()
	if old_phase != new_phase:
		phase_changed.emit(station_id, old_phase, new_phase)


## Guards material/dye/ledger debits so a phase or order never double-debits
## even if a worker is interrupted and resumed around the commit boundary.
func commit_once(order: Dictionary, key: String, callback: Callable) -> bool:
	var order_id := String(order.get("id", "active"))
	var full_key := "%s:%s" % [order_id, key]
	if committed_keys.get(full_key, false) or bool(order.get("committed_" + key, false)):
		return false
	var ok := true
	if callback.is_valid():
		var result: Variant = callback.call()
		if typeof(result) == TYPE_BOOL:
			ok = bool(result)
	if ok:
		committed_keys[full_key] = true
		order["committed_" + key] = true
		transaction_committed.emit(station_id, full_key)
	return ok


func build_snapshot(host: Node, extra: Dictionary = {}) -> Dictionary:
	var current_phase := String(host.get("phase")) if host != null and host.get("phase") != null else "idle"
	var current_elapsed := float(host.get("elapsed")) if host != null and host.get("elapsed") != null else 0.0
	var dur := duration_for(current_phase, 1.25)
	var worker: Node3D = host.get("actor") if host != null else null
	var snapshot := {
		"station_id": station_id,
		"phase": current_phase,
		"label": label_for(current_phase),
		"is_travel": is_travel_phase(current_phase),
		"elapsed": current_elapsed,
		"duration": dur,
		"progress": 0.0 if current_phase == "idle" or is_travel_phase(current_phase) else clampf(current_elapsed / dur, 0.0, 1.0),
		"actor_valid": is_instance_valid(worker),
		"actor_name": String(worker.get("doll_name")) if is_instance_valid(worker) and worker.get("doll_name") != null else "",
		"can_manual_assist": current_phase != "idle" and not is_travel_phase(current_phase) and is_instance_valid(worker),
	}
	for k in extra:
		snapshot[k] = extra[k]
	return snapshot
