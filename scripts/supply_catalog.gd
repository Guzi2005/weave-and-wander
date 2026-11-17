extends Node

## Shop supply catalog: named, editable garment recipes with optional automatic
## restocking, plus a visible production queue. Queue jobs keep an immutable
## snapshot of the recipe at enqueue time; material reservation happens only
## when a job is dispatched onto the real production flow.

const RECIPES = preload("res://scripts/garment_recipes.gd")

const SCHEMA := 2
const MAX_TARGET := 9
const MAX_COMPLETED_KEPT := 12
const PENDING_STATES := ["waiting-material", "ready"]
const STATE_LABELS := {
	"waiting-material": "等待材料",
	"dyeing": "染色中",
	"ready": "备料完成",
	"producing": "缝制中",
	"completed": "已完成",
}
const MATERIAL_NAMES := {"cotton": "棉布", "linen": "亚麻", "wool": "羊毛"}
const PATTERN_NAMES := {0: "平纹", 1: "条纹", 2: "格纹"}

var game: Node
var ledger: RefCounted
var inventory: Node3D
var production: Node3D
var dye: Node3D

var save_path := "user://supply_catalog.json"
var entries: Array[Dictionary] = []
var queue: Array[Dictionary] = []
var completed_count := 0
var random_auto_enabled := false
var random_pools := {"colors": [], "styles": [], "patterns": [], "materials": []}

var _entry_serial := 0
var _job_serial := 0
var _auto_clock := 0.0
var _entries_rev := 0


func setup(controller: Node) -> void:
	game = controller
	inventory = game._inventory
	ledger = inventory.materials
	production = game._production
	dye = game._dye
	load_catalog()


# ---------------------------------------------------------------- entries ---

func add_entry(data: Dictionary) -> Dictionary:
	var entry := _validated_entry(data)
	if entry.is_empty():
		return {}
	_entry_serial += 1
	entry["id"] = str(data.get("id", "")) if str(data.get("id", "")).begins_with("supply_") else "supply_%d" % _entry_serial
	if str(entry.get("name", "")).is_empty():
		var fabric_name := str(entry.get("fabric_name", ""))
		if fabric_name.is_empty() and ledger != null:
			fabric_name = str(ledger.fabric(str(entry.fabric_id)).get("name", entry.fabric_id))
		entry["name"] = "%s·%s" % [fabric_name, RECIPES.style_name(int(entry.style))]
	entries.append(entry)
	_entries_rev += 1
	save_catalog()
	return entry


func capture_current_recipe(save_entry: bool = true) -> Dictionary:
	var fabric: Dictionary = ledger.fabric(production.selected_fabric)
	var thread: Dictionary = ledger.thread(production.selected_thread)
	if fabric.is_empty() or thread.is_empty():
		return {}
	var data := {
		"name": "%s·%s" % [str(fabric.get("name", fabric.id)), RECIPES.style_name(production.selected_style)],
		"style": production.selected_style,
		"fabric_id": str(fabric.id),
		"material": str(fabric.get("material", "cotton")),
		"pattern_code": int(fabric.get("pattern_code", 0)),
		"pigment": fabric.get("pigment", Color.WHITE),
		"width_m": float(fabric.get("width_m", 1.4)),
		"thickness_m": float(fabric.get("thickness_m", .001)),
		"thread_id": str(thread.id),
		"size_factor": production.size_factor,
		"skirt_length": production.selected_skirt_length,
		"garment_length": production.selected_garment_length,
		"flower_target_id": production.selected_flower_target,
	}
	if save_entry:
		return add_entry(data)
	data = _validated_entry(data)
	data["id"] = "manual_draft"
	return data


func enqueue_current_recipe() -> Dictionary:
	var entry := capture_current_recipe(false)
	return {} if entry.is_empty() else _enqueue(entry, true)


func find_entry(entry_id: String) -> Dictionary:
	for entry in entries:
		if str(entry.id) == entry_id:
			return entry
	return {}


func update_entry(entry_id: String, changes: Dictionary) -> bool:
	var entry := find_entry(entry_id)
	if entry.is_empty():
		return false
	for key in ["name", "auto_enabled", "target_stock", "allow_dye"]:
		if not changes.has(key):
			continue
		match key:
			"name": entry.name = str(changes[key])
			"auto_enabled": entry.auto_enabled = bool(changes[key])
			"allow_dye": entry.allow_dye = bool(changes[key])
			"target_stock": entry.target_stock = clampi(int(changes[key]), 0, MAX_TARGET)
	_entries_rev += 1
	save_catalog()
	return true


# Removing a catalogue entry never touches jobs already queued from it.
func remove_entry(entry_id: String) -> bool:
	for index in entries.size():
		if str(entries[index].id) == entry_id:
			entries.remove_at(index)
			_entries_rev += 1
			save_catalog()
			return true
	return false


func _validated_entry(data: Dictionary) -> Dictionary:
	var entry := data.duplicate(true)
	var style: Variant = entry.get("style", -1)
	if typeof(style) not in [TYPE_INT, TYPE_FLOAT] or not RECIPES.valid(int(style)):
		return {}
	entry.style = int(style)
	for key in ["fabric_id", "thread_id", "material"]:
		if str(entry.get(key, "")).is_empty():
			return {}
	if not entry.get("pigment") is Color:
		return {}
	entry["pattern_code"] = int(entry.get("pattern_code", 0))
	if entry.pattern_code < 0 or entry.pattern_code > 2:
		return {}
	entry["width_m"] = float(entry.get("width_m", 0.0))
	entry["thickness_m"] = float(entry.get("thickness_m", 0.0))
	if entry.width_m < .5 or entry.width_m > 3.0 or entry.thickness_m <= 0.0 or entry.thickness_m > .01:
		return {}
	entry["size_factor"] = float(entry.get("size_factor", 1.0))
	if entry.size_factor < .05 or entry.size_factor > 4.0:
		return {}
	entry["skirt_length"] = clampf(float(entry.get("skirt_length", .70)), .35, 1.05)
	entry["garment_length"] = clampf(float(entry.get("garment_length", .80)), .55, 1.05)
	entry["auto_enabled"] = bool(entry.get("auto_enabled", false))
	entry["allow_dye"] = bool(entry.get("allow_dye", false))
	entry["target_stock"] = clampi(int(entry.get("target_stock", 1)), 0, MAX_TARGET)
	return entry


# ------------------------------------------------------------------ queue ---

func enqueue_manual(entry_id: String) -> Dictionary:
	var entry := find_entry(entry_id)
	if entry.is_empty():
		return {}
	return _enqueue(entry, true)


func _enqueue(entry: Dictionary, manual: bool) -> Dictionary:
	_job_serial += 1
	var job := {
		"id": "order_%d" % _job_serial,
		"entry_id": str(entry.id),
		"manual": manual,
		"snapshot": _snapshot(entry),
		"allow_dye": bool(entry.get("allow_dye", false)),
		"state": "waiting-material",
		"blocked_reason": "",
		"work_order_id": "",
		"dye_fabric_id": "",
	}
	queue.append(job)
	return job


func _snapshot(entry: Dictionary) -> Dictionary:
	return {
		"name": str(entry.get("name", "")),
		"style": int(entry.style),
		"fabric_id": str(entry.fabric_id),
		"material": str(entry.material),
		"pattern_code": int(entry.pattern_code),
		"pigment": entry.pigment,
		"width_m": float(entry.width_m),
		"thickness_m": float(entry.thickness_m),
		"thread_id": str(entry.thread_id),
		"size_factor": float(entry.size_factor),
		"skirt_length": float(entry.skirt_length),
		"garment_length": float(entry.garment_length),
		"flower_target_id": str(entry.get("flower_target_id", "")),
	}


func find_job(job_id: String) -> Dictionary:
	for job in queue:
		if str(job.id) == job_id:
			return job
	return {}


# Only pending jobs cancel; an active dye or sewing reservation is never
# released from here.
func cancel_job(job_id: String) -> bool:
	for index in queue.size():
		if str(queue[index].id) == job_id and queue[index].state in PENDING_STATES:
			queue.remove_at(index)
			return true
	return false


func move_job(job_id: String, direction: int) -> bool:
	var index := -1
	for at in queue.size():
		if str(queue[at].id) == job_id:
			index = at
			break
	if index < 0 or queue[index].state not in PENDING_STATES:
		return false
	var step := signi(direction)
	if step == 0:
		return false
	var target := index + step
	while target >= 0 and target < queue.size() and queue[target].state not in PENDING_STATES:
		target += step
	if target < 0 or target >= queue.size():
		return false
	var job: Dictionary = queue[index]
	queue.remove_at(index)
	queue.insert(target, job)
	return true


func active_count(entry_id: String) -> int:
	var total := 0
	for job in queue:
		if str(job.entry_id) == entry_id and job.state != "completed":
			total += 1
	return total


func state_text(job: Dictionary) -> String:
	var label := str(STATE_LABELS.get(str(job.state), str(job.state)))
	match str(job.state):
		"waiting-material":
			if not str(job.blocked_reason).is_empty():
				label += " · " + str(job.blocked_reason)
		"ready":
			label += " · 等待缝制台"
		"producing":
			var record: Dictionary = ledger.jobs.get(str(job.work_order_id), {})
			if not record.is_empty():
				label += " · %d%%" % int(float(record.get("sew_progress", 0.0)) * 100.0)
		"dyeing":
			if not dye.order.is_empty() and str(dye.order.get("fabric_id", "")) == str(job.dye_fabric_id):
				label += " · " + str(dye.LABELS.get(dye.phase, dye.phase))
	return label


# ------------------------------------------------------------------ stock ---

func stock_count(snapshot: Dictionary) -> int:
	var total := 0
	for item in inventory.items:
		if not is_instance_valid(item) or item.paid:
			continue
		if not str(item.reserved_by).is_empty():
			continue
		if item.location not in ["storage", "rack", "basket"]:
			continue
		if _item_matches(item, snapshot):
			total += 1
	return total


func _item_matches(item: Node3D, snapshot: Dictionary) -> bool:
	var definition: Resource = item.definition
	if int(definition.outfit_style) != int(snapshot.style):
		return false
	var expected_accessory := "flower" if int(snapshot.style) == RECIPES.FLOWER_STYLE else ""
	if str(definition.accessory_kind) != expected_accessory:
		return false
	var data: Dictionary = definition.material_data
	if data.is_empty():
		return false
	if str(data.get("material", "")) != str(snapshot.material):
		return false
	if int(data.get("pattern_code", 0)) != int(snapshot.pattern_code):
		return false
	if absf(float(data.get("width_m", 0.0)) - float(snapshot.width_m)) >= .01:
		return false
	if absf(float(data.get("thickness_m", 0.0)) - float(snapshot.thickness_m)) >= .0005:
		return false
	if not _pigment_close(data.get("pigment", Color.BLACK), snapshot.pigment):
		return false
	if str(item.get_meta("thread_source", "")) != str(snapshot.thread_id):
		return false
	if int(snapshot.style) == 12 and absf(float(definition.skirt_length) - float(snapshot.skirt_length)) >= .01:
		return false
	if int(snapshot.style) in [10, 11, 13] and absf(float(definition.garment_length) - float(snapshot.garment_length)) >= .01:
		return false
	return true


func _pigment_close(a: Color, b: Color) -> bool:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b)) < .04


func _spec_matches(batch: Dictionary, snapshot: Dictionary) -> bool:
	return str(batch.get("material", "")) == str(snapshot.material) \
		and int(batch.get("pattern_code", 0)) == int(snapshot.pattern_code) \
		and absf(float(batch.get("width_m", 0.0)) - float(snapshot.width_m)) < .01 \
		and absf(float(batch.get("thickness_m", 0.0)) - float(snapshot.thickness_m)) < .0005


func _usable_batch(batch: Dictionary, snapshot: Dictionary) -> bool:
	var id := str(batch.get("id", ""))
	if not production.packages.has(id):
		return false
	if ledger.available_fabric(id) <= 0.0:
		return false
	return bool(ledger.estimate(id, float(snapshot.size_factor), int(snapshot.style), float(snapshot.skirt_length), float(snapshot.garment_length)).get("ok", false))


func find_exact_fabric(snapshot: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for raw in ledger.fabric_batches:
		var batch: Dictionary = ledger.fabric(str(raw.get("id", "")))
		if batch.is_empty() or not _spec_matches(batch, snapshot):
			continue
		if not _pigment_close(batch.get("pigment", Color.BLACK), snapshot.pigment):
			continue
		if not _usable_batch(batch, snapshot):
			continue
		if best.is_empty() or float(batch.meters) > float(best.meters):
			best = batch
	return best


# Same weave, pattern, width and gauge; only the colour differs. The real dye
# flow re-colours it, preserving pattern and provenance.
func find_dye_candidate(snapshot: Dictionary) -> Dictionary:
	if dye == null:
		return {}
	var best: Dictionary = {}
	var best_distance := INF
	for raw in ledger.fabric_batches:
		var batch: Dictionary = ledger.fabric(str(raw.get("id", "")))
		if batch.is_empty() or not _spec_matches(batch, snapshot):
			continue
		var source: Color = batch.get("pigment", Color.WHITE)
		if _pigment_close(source, snapshot.pigment):
			continue
		if str(batch.get("material", "")) not in ["cotton", "linen", "wool"]:
			continue
		if str(batch.get("location", "")) != "storage":
			continue
		if float(batch.meters) > dye.CAPACITY_M + .0001:
			continue
		if not _usable_batch(batch, snapshot):
			continue
		var color_index: int = dye.nearest_color_index(snapshot.pigment, source)
		if float(dye.dyes[color_index]) < float(batch.meters) * .1:
			continue
		var mixed: Color = source.lerp(dye.COLORS[color_index], .8)
		var distance := Vector3(mixed.r, mixed.g, mixed.b).distance_squared_to(Vector3(snapshot.pigment.r, snapshot.pigment.g, snapshot.pigment.b))
		if distance < best_distance:
			best_distance = distance
			best = batch
	return best


# Returns "" when the snapshot can be dispatched right now, else the reason.
func feasibility(snapshot: Dictionary) -> String:
	var location := "accessory" if int(snapshot.style) == RECIPES.FLOWER_STYLE else "storage"
	if inventory.in_location(location).size() >= inventory.STORAGE_LIMIT:
		return "库房已满，等待上架空间"
	var fabric := find_exact_fabric(snapshot)
	if fabric.is_empty():
		var preferred: Dictionary = ledger.fabric(str(snapshot.fabric_id))
		if not preferred.is_empty() and _spec_matches(preferred, snapshot) and _pigment_close(preferred.get("pigment", Color.BLACK), snapshot.pigment):
			if ledger.available_fabric(str(preferred.id)) <= 0.0:
				return "匹配布料被占用"
			return "匹配布料不足（余 %.2f 米）" % float(preferred.get("meters", 0.0))
		return "缺少匹配布料"
	var spool: Dictionary = ledger.thread(str(snapshot.thread_id))
	if spool.is_empty():
		return "缝线缺失"
	var plan: Dictionary = ledger.estimate(str(fabric.id), float(snapshot.size_factor), int(snapshot.style), float(snapshot.skirt_length), float(snapshot.garment_length))
	if not plan.get("ok", false):
		return "布料幅宽或余量不足"
	if float(spool.get("meters", 0.0)) < float(plan.thread_m):
		return "缝线不足"
	if not ledger.can_reserve(str(fabric.id), str(snapshot.thread_id), float(snapshot.size_factor), int(snapshot.style), float(snapshot.skirt_length), float(snapshot.garment_length)):
		return "材料被占用"
	return ""


# ------------------------------------------------------------------- tick ---

func tick(delta: float) -> void:
	if ledger == null:
		return
	_auto_clock += delta
	if _auto_clock >= .4:
		_auto_clock = 0.0
		_auto_restock()
		_auto_random_order()
	var ordered: Array = []
	ordered.append_array(queue.filter(func(job: Dictionary) -> bool: return bool(job.manual)))
	ordered.append_array(queue.filter(func(job: Dictionary) -> bool: return not bool(job.manual)))
	for job in ordered:
		match str(job.state):
			"producing":
				_update_producing(job)
			"dyeing":
				_update_dyeing(job)
		if job.state == "waiting-material":
			_update_waiting(job)
		if job.state == "ready":
			_update_ready(job)


func set_random_auto_enabled(value: bool) -> void:
	random_auto_enabled = value
	save_catalog()


func set_random_pool(key: String, values: Array) -> void:
	if not random_pools.has(key):
		return
	random_pools[key] = values.duplicate()
	save_catalog()


func random_pool_accepts(key: String, value: String) -> bool:
	return random_pools[key].is_empty() or value in random_pools[key]


func _auto_random_order() -> void:
	if not random_auto_enabled:
		return
	# An active sewing order may have one successor; never accumulate a backlog.
	for job in queue:
		if job.state in PENDING_STATES or job.state == "dyeing":
			return
	var candidates: Array[Dictionary] = []
	var storage_full: bool = inventory.in_location("storage").size() >= inventory.STORAGE_LIMIT
	var accessory_full: bool = inventory.in_location("accessory").size() >= inventory.STORAGE_LIMIT
	for fabric in ledger.fabric_batches:
		if not random_pool_accepts("colors", (fabric.pigment as Color).to_html(false)):
			continue
		if not random_pool_accepts("materials", str(fabric.material)):
			continue
		if not random_pool_accepts("patterns", str(fabric.get("pattern_code", 0))):
			continue
		if not production.packages.has(str(fabric.id)):
			continue
		for thread in ledger.thread_batches:
			if not production.packages.has(str(thread.id)):
				continue
			for style in RECIPES.RECIPES:
				if not random_pool_accepts("styles", str(style)):
					continue
				if accessory_full if style == RECIPES.FLOWER_STYLE else storage_full:
					continue
				if not ledger.can_reserve(str(fabric.id), str(thread.id), production.size_factor, style, .35, .55):
					continue
				var entry := _validated_entry({
					"style": style, "fabric_id": str(fabric.id), "thread_id": str(thread.id),
					"material": fabric.material, "pattern_code": fabric.get("pattern_code", 0),
					"pigment": fabric.pigment, "width_m": fabric.width_m, "thickness_m": fabric.thickness_m,
					"size_factor": production.size_factor, "skirt_length": .35, "garment_length": .55,
				})
				if entry.is_empty():
					continue
				entry["id"] = "random_combination"
				entry["name"] = "%s·%s" % [fabric.get("name", fabric.id), RECIPES.style_name(style)]
				candidates.append(entry)
	if candidates.is_empty():
		return
	var selected: Dictionary = candidates.pick_random().duplicate(true)
	# Try any supported centimetre length; keep the feasible minimum if scarce.
	var varied: Dictionary = selected.duplicate(true)
	varied.skirt_length = randi_range(35, 105) / 100.0
	varied.garment_length = randi_range(55, 105) / 100.0
	if feasibility(_snapshot(varied)).is_empty():
		selected = varied
	var job := _enqueue(selected, false)
	job["random_auto"] = true


func _auto_restock() -> void:
	for entry in entries:
		if not bool(entry.auto_enabled):
			continue
		var have := stock_count(_snapshot(entry)) + active_count(str(entry.id))
		while have < int(entry.target_stock):
			_enqueue(entry, false)
			have += 1


func _update_waiting(job: Dictionary) -> void:
	var reason := feasibility(job.snapshot)
	if reason.is_empty():
		job.state = "ready"
		job.blocked_reason = ""
		return
	job.blocked_reason = reason
	if not bool(job.get("allow_dye", false)) or not reason.contains("布料"):
		return
	var candidate := find_dye_candidate(job.snapshot)
	if candidate.is_empty():
		return
	if not dye.order.is_empty():
		job.blocked_reason = "等待染缸空闲"
		return
	if dye.start_targeted(str(candidate.id), job.snapshot.pigment, str(job.id)):
		job.state = "dyeing"
		job.dye_fabric_id = str(candidate.id)
		job.blocked_reason = ""


func _update_dyeing(job: Dictionary) -> void:
	var fabric_id := str(job.dye_fabric_id)
	if not dye.order.is_empty() and str(dye.order.get("fabric_id", "")) == fabric_id:
		return
	var batch: Dictionary = ledger.fabric(fabric_id)
	if batch.is_empty():
		job.state = "waiting-material"
		job.blocked_reason = "染色布料丢失"
		return
	if not str(batch.get("dye_job", "")).is_empty():
		return
	if _pigment_close(batch.get("pigment", Color.WHITE), job.snapshot.pigment):
		job.state = "ready"
		job.blocked_reason = ""
	else:
		job.state = "waiting-material"
		job.blocked_reason = "染色未完成，重新排队"


func _update_ready(job: Dictionary) -> void:
	if not production.order.is_empty():
		return
	var snapshot: Dictionary = job.snapshot
	# Resolve the source batch at dispatch time: a dye substitution may have
	# re-coloured a different batch into this exact spec since enqueue.
	var fabric := find_exact_fabric(snapshot)
	if fabric.is_empty():
		job.state = "waiting-material"
		job.blocked_reason = feasibility(snapshot)
		return
	var order: Dictionary = production.begin_order(str(fabric.id), str(snapshot.thread_id), float(snapshot.size_factor), int(snapshot.style), float(snapshot.skirt_length), float(snapshot.garment_length))
	if order.is_empty():
		job.state = "waiting-material"
		job.blocked_reason = feasibility(snapshot)
		return
	order["catalog_job_id"] = str(job.id)
	order["flower_target_id"] = str(snapshot.get("flower_target_id", ""))
	job.work_order_id = str(order.id)
	job["resolved_fabric_id"] = str(fabric.id)
	job.state = "producing"
	job.blocked_reason = ""


func _update_producing(job: Dictionary) -> void:
	var record: Dictionary = ledger.jobs.get(str(job.work_order_id), {})
	if record.is_empty():
		return
	match str(record.get("status", "")):
		"completed":
			job.state = "completed"
			completed_count += 1
			_prune_completed()
		"cancelled":
			queue.erase(job)


func _prune_completed() -> void:
	var finished := queue.filter(func(job: Dictionary) -> bool: return job.state == "completed")
	while finished.size() > MAX_COMPLETED_KEPT:
		queue.erase(finished.pop_front())


# ------------------------------------------------------------- persistence ---

func save_catalog() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return
	var data := {"schema": SCHEMA, "entries": [], "random_auto_enabled": random_auto_enabled, "random_pools": random_pools}
	for entry in entries:
		data.entries.append(_entry_to_dict(entry))
	file.store_string(JSON.stringify(data, "  "))


func load_catalog() -> bool:
	entries.clear()
	random_auto_enabled = false
	for key in random_pools:
		random_pools[key] = []
	if not FileAccess.file_exists(save_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("schema", -1)) != SCHEMA:
		return false
	if typeof(parsed.get("entries")) != TYPE_ARRAY:
		return false
	random_auto_enabled = bool(parsed.get("random_auto_enabled", false))
	var saved_pools: Variant = parsed.get("random_pools", {})
	if saved_pools is Dictionary:
		for key in random_pools:
			if saved_pools.get(key) is Array:
				for value in saved_pools[key]:
					if value is String:
						random_pools[key].append(value)
	for raw in parsed.entries:
		var entry := _entry_from_dict(raw)
		if entry.is_empty():
			push_warning("Supply catalog skipped an invalid saved entry.")
			continue
		entries.append(entry)
		var suffix := str(entry.id).trim_prefix("supply_")
		if suffix.is_valid_int():
			_entry_serial = maxi(_entry_serial, int(suffix))
	_entries_rev += 1
	return true


func _entry_to_dict(entry: Dictionary) -> Dictionary:
	return {
		"id": str(entry.id),
		"name": str(entry.get("name", "")),
		"style": int(entry.style),
		"fabric_id": str(entry.fabric_id),
		"material": str(entry.material),
		"pattern_code": int(entry.pattern_code),
		"pigment": "#" + (entry.pigment as Color).to_html(),
		"width_m": float(entry.width_m),
		"thickness_m": float(entry.thickness_m),
		"thread_id": str(entry.thread_id),
		"size_factor": float(entry.size_factor),
		"skirt_length": float(entry.skirt_length),
		"garment_length": float(entry.garment_length),
		"auto_enabled": bool(entry.auto_enabled),
		"target_stock": int(entry.target_stock),
		"allow_dye": bool(entry.allow_dye),
	}


func _entry_from_dict(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var data: Dictionary = raw
	if str(data.get("id", "")).is_empty():
		return {}
	var pigment: Variant = data.get("pigment", "")
	if typeof(pigment) != TYPE_STRING or not Color.html_is_valid(pigment):
		return {}
	data = data.duplicate(true)
	data["pigment"] = Color(pigment)
	var entry := _validated_entry(data)
	if entry.is_empty():
		return {}
	entry["id"] = str(data.id)
	return entry
