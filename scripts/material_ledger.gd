extends RefCounted

## Bounded consumable ledger for the garment recipe table.
## Tracks fabric rolls, thread spools, job reservations, recoverable remnants
## and an audit event log. Estimates are a documented bounded heuristic per
## clothing style (see garment_recipes.gd), not a nesting solver.

const PALETTE: Array[Color] = [
	Color("779ab1"), # 0 blue
	Color("c89b5a"), # 1 ochre
	Color("7d9b76"), # 2 green
	Color("a183a6"), # 3 mauve
]
const PATTERN_CODES := {"plain": 0, "stripe": 1, "check": 2}
const PATTERN_NAMES := {0: "plain", 1: "stripe", 2: "check"}

const DEFAULT_WIDTH_M := 1.4
const DEFAULT_THICKNESS_M := 0.001
const DEFAULT_MATERIAL := "cotton"
const MIN_WIDTH_M := 0.5
const MIN_SIZE_FACTOR := 0.05
const MAX_SIZE_FACTOR := 4.0
const BASE_LENGTH_M := 1.4
const STRIPE_ALLOWANCE_M := 0.05
const CHECK_ALLOWANCE_M := 0.08
const DEFAULT_FABRIC_COST_PER_M := 7.0
const DEFAULT_THREAD_COST_PER_M := 0.04

const ACTIVE_STATUSES := ["reserved", "cut", "sewing", "sewn"]

const APPEARANCE := preload("res://scripts/material_appearance.gd")
const RECIPES := preload("res://scripts/garment_recipes.gd")

var fabric_batches: Array[Dictionary] = []
var yarn_batches: Array[Dictionary] = []
var thread_batches: Array[Dictionary] = [
	{"id": "thread_blue", "meters": 80.0, "pigment": Color("779ab1"), "material": "cotton"},
]
var jobs: Dictionary = {}
var remnants: Array[Dictionary] = []
var events: Array[Dictionary] = []

var _job_serial := 0
var _remnant_serial := 0


func bind_fabrics(batches: Array[Dictionary]) -> void:
	fabric_batches = batches


func fabric(id: String) -> Dictionary:
	for record in fabric_batches:
		if String(record.get("id", "")) == id:
			_normalize_material(record, true)
			return record
	return {}


func thread(id: String) -> Dictionary:
	for record in thread_batches:
		if String(record.get("id", "")) == id:
			_normalize_material(record, false)
			return record
	return {}

func yarn(id: String) -> Dictionary:
	for record in yarn_batches:
		if str(record.get("id","")) == id: return record
	return {}


func available_fabric(id: String) -> float:
	var roll := fabric(id)
	if roll.is_empty() or not _finite_nonnegative(roll.get("meters")):
		return 0.0
	if _owner_of(id, "") != "":
		return 0.0
	return float(roll.meters)


func available_thread(id: String) -> float:
	var spool := thread(id)
	if spool.is_empty() or not _finite_nonnegative(spool.get("meters")):
		return 0.0
	if _owner_of("", id) != "":
		return 0.0
	return float(spool.meters)


func can_reserve(fabric_id: String, thread_id: String, size_factor: float = 1.0, outfit_style: int = 1, skirt_length: float = .70, garment_length: float = .80) -> bool:
	var plan := estimate(fabric_id, size_factor, outfit_style, skirt_length, garment_length)
	if not plan.ok:
		return false
	var spool := thread(thread_id)
	if spool.is_empty() or not _finite_nonnegative(spool.get("meters")):
		return false
	if float(spool.meters) < float(plan.thread_m):
		return false
	return _owner_of(fabric_id, thread_id) == ""


func estimate(fabric_id: String, size_factor: float = 1.0, outfit_style: int = 1, skirt_length: float = .70, garment_length: float = .80) -> Dictionary:
	var result := {
		"ok": false,
		"reason": "",
		"cut_m": 0.0,
		"net_m": 0.0,
		"remnant_m": 0.0,
		"waste_m": 0.0,
		"thread_m": 0.0,
		"cost_estimate": 0.0,
		"size_factor": size_factor,
		"outfit_style": outfit_style,
		"skirt_length": skirt_length,
		"garment_length": garment_length,
	}
	if not RECIPES.valid(outfit_style):
		result.reason = "unknown_style"
		return result
	if not is_finite(size_factor) or size_factor < MIN_SIZE_FACTOR or size_factor > MAX_SIZE_FACTOR:
		result.reason = "illegal_size_factor"
		return result
	var roll := fabric(fabric_id)
	if roll.is_empty():
		result.reason = "unknown_fabric"
		return result
	if not _finite_nonnegative(roll.get("meters")):
		result.reason = "invalid_stock"
		return result
	var width := float(roll.width_m) if _finite_nonnegative(roll.get("width_m")) else 0.0
	if width < MIN_WIDTH_M:
		result.reason = "width_too_narrow"
		return result
	var allowance := 0.0
	match int(roll.get("pattern_code", 0)):
		1:
			allowance = STRIPE_ALLOWANCE_M * size_factor
		2:
			allowance = CHECK_ALLOWANCE_M * size_factor
	# Small petals do not require matching the garment's full-width repeat.
	if outfit_style == RECIPES.FLOWER_STYLE: allowance *= .1
	var recipe: Dictionary = RECIPES.recipe(outfit_style)
	if outfit_style == 12:
		if not is_finite(skirt_length) or skirt_length < .35 or skirt_length > 1.05:
			result.reason = "invalid_skirt_length"
			return result
		size_factor *= skirt_length/.70
	if outfit_style in [10, 11, 13]:
		if not is_finite(garment_length) or garment_length < .55 or garment_length > 1.05:
			result.reason = "invalid_garment_length"
			return result
		size_factor *= garment_length/.80
	var net_m := float(recipe.net_fraction) * size_factor * BASE_LENGTH_M / width
	var remnant_m := float(recipe.remnant_fraction) * size_factor
	var waste_m := float(recipe.waste_fraction) * size_factor + allowance
	var cut_m := net_m + remnant_m + waste_m
	if float(roll.meters) < cut_m:
		result.reason = "insufficient_fabric"
		return result
	var thread_m := float(recipe.thread_per_size_m) * size_factor
	var fabric_cost := float(roll.get("cost_per_m", DEFAULT_FABRIC_COST_PER_M))
	result.ok = true
	result.cut_m = cut_m
	result.net_m = net_m
	result.remnant_m = remnant_m
	result.waste_m = waste_m
	result.thread_m = thread_m
	result.cost_estimate = cut_m * fabric_cost + thread_m * DEFAULT_THREAD_COST_PER_M
	return result


func reserve(fabric_id: String, thread_id: String, size_factor: float = 1.0, outfit_style: int = 1, skirt_length: float = .70, garment_length: float = .80) -> Dictionary:
	if not can_reserve(fabric_id, thread_id, size_factor, outfit_style, skirt_length, garment_length):
		return {}
	var roll := fabric(fabric_id)
	var spool := thread(thread_id)
	_job_serial += 1
	var job := {
		"id": "job_%d" % _job_serial,
		"status": "reserved",
		"fabric_id": fabric_id,
		"thread_id": thread_id,
		"outfit_style": outfit_style,
		"skirt_length": skirt_length,
		"garment_length": garment_length,
		"estimate": estimate(fabric_id, size_factor, outfit_style, skirt_length, garment_length),
		"material_snapshot": roll.duplicate(true),
		"thread_snapshot": spool.duplicate(true),
		"sew_progress": 0.0,
		"output_id": "",
		"consumed_fabric_m": 0.0,
		"consumed_thread_m": 0.0,
		"net_cut_m": 0.0,
		"waste_m": 0.0,
		"remnant_m": 0.0,
	}
	jobs[job.id] = job
	events.append({
		"type": "reserve", "job_id": job.id,
		"fabric_id": fabric_id, "thread_id": thread_id, "size_factor": size_factor,
		"outfit_style": outfit_style,
		"skirt_length": skirt_length,
		"garment_length": garment_length,
	})
	return job


func cut(job_id: String) -> bool:
	var job: Dictionary = jobs.get(job_id, {})
	if job.is_empty():
		return false
	if job.status != "reserved":
		return job.status in ["cut", "sewing", "sewn", "completed"]
	var plan: Dictionary = job.estimate
	var cut_m := float(plan.cut_m)
	var roll := fabric(job.fabric_id)
	if roll.is_empty() or not _finite_nonnegative(roll.get("meters")) or float(roll.meters) < cut_m:
		return false
	roll.meters = float(roll.meters) - cut_m
	job.status = "cut"
	job.consumed_fabric_m = cut_m
	job.net_cut_m = plan.net_m
	job.waste_m = plan.waste_m
	job.remnant_m = plan.remnant_m
	remnants.append(_make_remnant("roll_remnant", job.fabric_id, roll, float(plan.remnant_m)))
	events.append({
		"type": "cut", "job_id": job_id, "fabric_id": job.fabric_id,
		"cut_m": cut_m, "net_m": plan.net_m, "waste_m": plan.waste_m, "remnant_m": plan.remnant_m,
	})
	return true


func advance_sewing(job_id: String, progress: float) -> bool:
	var job: Dictionary = jobs.get(job_id, {})
	if job.is_empty() or job.status not in ["cut", "sewing", "sewn"]:
		return false
	if not is_finite(progress) or progress < 0.0 or progress > 1.0:
		return false
	if progress < float(job.sew_progress):
		return false
	if progress == float(job.sew_progress):
		return true
	var spool := thread(job.thread_id)
	var delta := float(job.estimate.thread_m) * (progress - float(job.sew_progress))
	if spool.is_empty() or not _finite_nonnegative(spool.get("meters")) or float(spool.meters)+0.000001 < delta:
		return false
	spool.meters = maxf(0.0,float(spool.meters) - delta)
	job.consumed_thread_m = float(job.consumed_thread_m) + delta
	job.sew_progress = progress
	job.status = "sewn" if progress == 1.0 else "sewing"
	events.append({"type": "sew", "job_id": job_id, "progress": progress, "thread_m": delta})
	return true


func complete(job_id: String, output_id: String) -> bool:
	var job: Dictionary = jobs.get(job_id, {})
	if job.is_empty() or output_id.is_empty():
		return false
	if job.status == "completed":
		return job.output_id == output_id
	if job.status != "sewn" or float(job.sew_progress) != 1.0:
		return false
	job.status = "completed"
	job.output_id = output_id
	events.append({"type": "complete", "job_id": job_id, "output_id": output_id})
	return true


func cancel(job_id: String) -> bool:
	var job: Dictionary = jobs.get(job_id, {})
	if job.is_empty() or job.status == "completed":
		return false
	if job.status == "cancelled":
		return true
	if job.status == "reserved":
		job.status = "cancelled"
		events.append({"type": "cancel", "job_id": job_id, "phase": "reserved"})
		return true
	job.status = "cancelled"
	if float(job.net_cut_m) > 0.0:
		var snapshot: Dictionary = job.material_snapshot
		remnants.append(_make_remnant("cut_piece", job.fabric_id, snapshot, float(job.net_cut_m)))
	events.append({"type": "cancel", "job_id": job_id, "phase": "after_cut"})
	return true


func _make_remnant(kind: String, fabric_id: String, source: Dictionary, length_m: float) -> Dictionary:
	_remnant_serial += 1
	var remnant := {
		"id": "remnant_%d" % _remnant_serial,
		"kind": kind,
		"fabric_id": fabric_id,
		"source_fabric_id": fabric_id,
		"width_m": source.get("width_m", DEFAULT_WIDTH_M),
		"length_m": length_m,
		"meters": length_m,
		"material": source.get("material", DEFAULT_MATERIAL),
		"pigment": source.get("pigment", PALETTE[0]),
		"pattern_code": source.get("pattern_code", 0),
		"location": "table",
	}
	# Appearance and provenance snapshot stay valid even if the source roll is
	# later changed or used up.
	var appearance := APPEARANCE.describe(source)
	remnant["pattern"] = appearance["pattern"]
	remnant["pattern_id"] = appearance["pattern_id"]
	remnant["pattern_scale"] = appearance["pattern_scale"]
	remnant["pattern_revision"] = appearance["pattern_revision"]
	remnant["source_ids"] = appearance["source_ids"]
	return remnant


func _owner_of(fabric_id: String, thread_id: String) -> String:
	for batch in fabric_batches:
		if str(batch.get("id", "")) == fabric_id and not str(batch.get("dye_job", "")).is_empty():
			return str(batch.dye_job)
	for job_id in jobs:
		var job: Dictionary = jobs[job_id]
		if job.status in ACTIVE_STATUSES and (job.fabric_id == fabric_id or job.thread_id == thread_id):
			return job_id
	return ""


func _normalize_material(record: Dictionary, is_fabric: bool) -> void:
	if is_fabric:
		if not record.has("width_m"):
			record.width_m = DEFAULT_WIDTH_M
		if not record.has("thickness_m"):
			record.thickness_m = DEFAULT_THICKNESS_M
		if not record.has("pattern_code"):
			if not record.has("pattern"):
				record.pattern = "plain"
			record.pattern_code = PATTERN_CODES.get(String(record.pattern), 0)
		elif not record.has("pattern"):
			record.pattern = PATTERN_NAMES.get(int(record.pattern_code), "plain")
		# Described appearance/provenance fields only; identity and stock are untouched.
		var appearance := APPEARANCE.describe(record)
		record["pattern"] = appearance["pattern"]
		record["pattern_code"] = appearance["pattern_code"]
		record["pattern_id"] = appearance["pattern_id"]
		record["pattern_scale"] = appearance["pattern_scale"]
		record["pattern_revision"] = appearance["pattern_revision"]
		if not record.has("source_ids"):
			record["source_ids"] = appearance["source_ids"]
	if not record.has("material"):
		record.material = DEFAULT_MATERIAL
	if not record.has("pigment"):
		var index := posmod(int(record.get("palette", record.get("palette_index",0))), PALETTE.size())
		record.pigment = PALETTE[index]
	if not record.has("palette"):
		var pigment: Color = record.pigment
		var closest := 0
		var distance := INF
		for index in PALETTE.size():
			var candidate := Vector3(pigment.r,pigment.g,pigment.b).distance_squared_to(Vector3(PALETTE[index].r,PALETTE[index].g,PALETTE[index].b))
			if candidate < distance:
				distance = candidate
				closest = index
		record.palette = closest
	var meters: Variant = record.get("meters")
	if not _finite_nonnegative(record.get("capacity_m")) or (_finite_nonnegative(meters) and float(record.capacity_m) < float(meters)):
		record.capacity_m = float(meters) if _finite_nonnegative(meters) else 0.0
	if not record.has("location"):
		record.location = "storage"


func _finite_nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(value) and value >= 0

