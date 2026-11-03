extends Node3D
## A whole-bolt overdye job. The source batch stays locked until physically returned.
const StationProtocol = preload("res://scripts/work_station_sequence.gd")
const COLORS := [Color("496e91"),Color("a65d63"),Color("688b70"),Color("c2a05e")]
const NAMES := ["靛蓝","茜红","草绿","姜黄"]
const CAPACITY_M := 12.0
const DURATIONS := {"take":1.2,"unwind":2.0,"dye":8.0,"rinse":3.0,"dry":6.0,"rewrap":2.0,"store":1.2}
const LABELS := {"idle":"等待染色订单","to_fabric":"前往取布","take":"拿取布匹","to_vat":"搬往染缸","unwind":"退绕布料","dye":"浸染与搅动","rinse":"漂洗","dry":"晾干","rewrap":"绕回纸板","to_return":"送回布柜","store":"归库","recover":"接手周转布料","resume":"回到染缸"}
const TRAVEL_PHASES := ["to_fabric","to_vat","to_return","recover","resume"]
var game: Node
var ledger: RefCounted
var production: Node3D
var vat: Node3D
var actor: Node3D
var package: Node3D
var order: Dictionary = {}
var phase := "idle"
var elapsed := 0.0
var dyes := [20.0,20.0,20.0,20.0]
var completed := 0
var serial := 0
var start_transform: Transform3D
var recovery: Marker3D
var resume_phase := ""
var resume_elapsed := 0.0
var history: Array[String] = []
var station_protocol: RefCounted

func setup(controller: Node) -> void:
	game = controller
	station_protocol = StationProtocol.new("dye", {
		"labels": LABELS,
		"travel_phases": TRAVEL_PHASES,
		"durations": DURATIONS,
	})
	production = game._production
	ledger = game._inventory.materials
	vat = game._rooms.workshop.get_node("DyeWorkbench")
	recovery = Marker3D.new()
	add_child(recovery)

func can_start(id: String, color_index: int) -> bool:
	if not order.is_empty() or color_index < 0 or color_index >= COLORS.size(): return false
	var batch: Dictionary = ledger.fabric(id)
	return not batch.is_empty() and production.packages.has(id) and batch.get("location","") == "storage" and batch.get("material","") in ["cotton","linen","wool"] and ledger.available_fabric(id) > 0 and float(batch.meters) <= CAPACITY_M and dyes[color_index] >= float(batch.meters)*.1

# Picks the vat colour whose standard overdye lands closest to the target.
func nearest_color_index(target: Color, source: Color) -> int:
	var best := 0
	var best_distance := INF
	for index in COLORS.size():
		var mixed: Color = source.lerp(COLORS[index],.8)
		var distance := Vector3(mixed.r,mixed.g,mixed.b).distance_squared_to(Vector3(target.r,target.g,target.b))
		if distance < best_distance:
			best_distance = distance
			best = index
	return best

func can_start_targeted(id: String, target: Color) -> bool:
	var batch: Dictionary = ledger.fabric(id)
	if batch.is_empty(): return false
	return can_start(id,nearest_color_index(target,batch.get("pigment",Color.WHITE)))

# A commissioned swatch-match dye: same vat, capacity, lock and dose rules as a
# manual overdye, but the dyer works to the requested swatch, so the committed
# pigment is exactly the target rather than the approximate lerp output.
func start_targeted(id: String, target: Color, requester := "") -> bool:
	var batch: Dictionary = ledger.fabric(id)
	if batch.is_empty(): return false
	var color_index := nearest_color_index(target,batch.get("pigment",Color.WHITE))
	if not can_start(id,color_index): return false
	serial += 1
	order = {"id":"dye_%d" % serial,"fabric_id":id,"snapshot":batch.duplicate(true),"color":target,"color_index":color_index,"dose":float(batch.meters)*.1,"committed":false,"targeted":true,"requester":requester}
	batch.dye_job = order.id
	package = production.packages[id]
	_set_phase("to_fabric")
	ledger.events.append({"type":"dye_reserve","job_id":order.id,"fabric_id":id,"target":target,"requester":requester})
	return true

func start(id: String, color_index: int) -> bool:
	if not can_start(id,color_index): return false
	serial += 1
	var batch: Dictionary = ledger.fabric(id)
	var target: Color = (batch.pigment as Color).lerp(COLORS[color_index],.8)
	order = {"id":"dye_%d" % serial,"fabric_id":id,"snapshot":batch.duplicate(true),"color":target,"color_index":color_index,"dose":float(batch.meters)*.1,"committed":false}
	batch.dye_job = order.id
	package = production.packages[id]
	_set_phase("to_fabric")
	ledger.events.append({"type":"dye_reserve","job_id":order.id,"fabric_id":id})
	return true

func assign(worker: Node3D) -> bool:
	if order.is_empty(): return false
	if is_instance_valid(actor): return actor == worker
	actor = worker
	actor.set_meta("material_handling",true)
	if not resume_phase.is_empty():
		_move("recover" if package.visible and ledger.fabric(order.fabric_id).location == "carried" else "resume",recovery if ledger.fabric(order.fabric_id).location == "carried" else _access())
	else:
		_move("to_fabric",production.cabinet.access)
	return true

func suspend(worker: Node3D) -> void:
	if actor != worker: return
	resume_phase = phase
	resume_elapsed = elapsed
	recovery.global_position = actor.global_position
	actor.clear_interaction()
	actor.set_meta("material_handling",false)
	actor = null

func _access() -> Node3D:
	return game.facilities[game._facility_index("dye")].anchor

func _set_phase(value: String) -> void:
	var previous := phase
	phase = value
	elapsed = 0.0
	history.append(value)
	if is_instance_valid(package): start_transform = package.global_transform
	if station_protocol != null:
		station_protocol.notify_phase_entered(previous, value)

func get_station_snapshot() -> Dictionary:
	if station_protocol == null:
		return {"station_id": "dye", "phase": phase, "label": str(LABELS.get(phase, phase)), "busy": not order.is_empty()}
	return station_protocol.build_snapshot(self, {
		"busy": not order.is_empty(),
		"order_id": str(order.get("id", "")),
	})

func nudge_manual_step(seconds: float = 0.65) -> bool:
	if order.is_empty() or phase == "idle" or phase in TRAVEL_PHASES:
		return false
	elapsed += maxf(0.05, seconds)
	return true

func _move(value: String, anchor: Node3D) -> void:
	_set_phase(value)
	actor.clear_interaction()
	actor.move_to_anchor(anchor,"stocking")

func _carry_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP,actor.rotation.y),actor.to_global(Vector3(0,.95,.48)))

func _grip() -> void:
	var points: Array = package.grip_points()
	actor.reach("L",points[0])
	actor.reach("R",points[1])
	actor.apply_reaches()

func advance(delta: float) -> void:
	if delta <= 0 or not is_instance_valid(actor) or order.is_empty(): return
	if actor.navigation_status == "blocked": return
	if phase in ["to_vat","to_return"]:
		package.global_transform = _carry_transform()
		_grip()
	if phase in ["to_fabric","to_vat","to_return","recover","resume"]:
		if not actor.has_arrived(): return
		actor.resting_facing = _access().get_parent().global_rotation.y+PI if phase != "to_fabric" else production.cabinet.global_rotation.y+PI
		if phase == "recover":
			var next := "to_return" if resume_phase in ["to_return","store"] else "to_vat"
			resume_phase = ""
			_move(next,production.cabinet.access if next == "to_return" else _access())
		elif phase == "resume":
			var saved := resume_elapsed
			var next := resume_phase
			resume_phase = ""
			if next in ["to_fabric","take"]: _move("to_fabric",production.cabinet.access)
			else:
				_set_phase(next)
				elapsed = saved
		else:
			_set_phase({"to_fabric":"take","to_vat":"unwind","to_return":"store"}[phase])
		return
	if not actor.has_arrived(): return
	elapsed += delta
	var t := minf(elapsed/float(DURATIONS.get(phase,1.0)),1.0)
	match phase:
		"take":
			if package.get_parent() != self: package.reparent(self,true)
			package.global_transform = start_transform.interpolate_with(_carry_transform(),smoothstep(0,1,t))
			_grip()
			if t >= 1:
				ledger.fabric(order.fabric_id).location = "carried"
				_move("to_vat",_access())
		"unwind","dye","rinse","dry","rewrap":
			package.global_transform = vat.global_transform * Transform3D(Basis.IDENTITY,Vector3(-1.18,.23,.32))
			ledger.fabric(order.fabric_id).location = "dye_vat"
			package.visible = phase in ["unwind","rewrap"]
			vat.show_stage(phase,t,order.snapshot,order.color)
			var hand_x := .72 if phase == "rinse" else -.78
			actor.reach("L",vat.to_global(Vector3(hand_x-.27,1.15,.20)))
			actor.reach("R",vat.to_global(Vector3(hand_x+.20,1.20+.1*sin(t*TAU*4),.12)))
			actor.apply_reaches()
			if t >= 1:
				if phase == "dye": _commit_color()
				if phase == "rewrap":
					package.configure(ledger.fabric(order.fabric_id),package.form)
					package.show()
					vat.sheet.hide()
					ledger.fabric(order.fabric_id).location = "carried"
					_move("to_return",production.cabinet.access)
				else: _set_phase({"unwind":"dye","dye":"rinse","rinse":"dry","dry":"rewrap"}[phase])
		"store":
			package.global_transform = start_transform.interpolate_with(production.mounts[order.fabric_id].global_transform,smoothstep(0,1,t))
			_grip()
			if t >= 1: _complete()

func _commit_color() -> void:
	if order.committed: return
	var batch: Dictionary = ledger.fabric(order.fabric_id)
	batch.pigment = order.color
	batch["dye_revision"] = int(batch.get("dye_revision",0))+1
	if bool(order.get("targeted",false)):
		batch["name"] = "%s定制染 · %s" % [NAMES[order.color_index],str(order.snapshot.get("name",batch.id)).get_slice("染 · ",0)]
	else:
		batch["name"] = "%s染 · %s" % [NAMES[order.color_index],str(order.snapshot.get("name",batch.id)).get_slice("染 · ",0)]
	var sources: Array = batch.get("source_ids",[]).duplicate()
	sources.append(order.id)
	batch.source_ids = sources
	dyes[order.color_index] -= float(order.dose)
	order.committed = true
	ledger.events.append({"type":"dye","job_id":order.id,"fabric_id":batch.id,"meters":batch.meters,"dose":order.dose,"before":order.snapshot.pigment,"after":order.color,"targeted":bool(order.get("targeted",false))})

func _complete() -> void:
	var batch: Dictionary = ledger.fabric(order.fabric_id)
	batch.location = "storage"
	batch.erase("dye_job")
	package.reparent(production.mounts[order.fabric_id],true)
	package.transform = Transform3D.IDENTITY
	production.cabinet.arrange_fabrics(production.packages,production.mounts)
	ledger.events.append({"type":"dye_complete","job_id":order.id,"fabric_id":batch.id})
	completed += 1
	var worker := actor
	actor = null
	worker.clear_interaction()
	worker.set_meta("material_handling",false)
	order = {}
	_set_phase("idle")
	game._set_staff_idle(worker,1.0)
	game._show_toast("染色完成，布料已晾干归库，可用于制衣")
