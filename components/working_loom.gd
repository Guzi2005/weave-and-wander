extends Node3D

## Treadle loom: pick-by-pick weaving with persistent partial progress.
## One seated operator sheds, shuttles, beats and takes up. A batch only
## starts when the ledger's real yarn stock can cover warp + weft, debited
## once up front; interruption never re-debits and never loses picks.
## Every finished bolt is one ledger fabric batch with one physical source
## package registered on the loom, described by material_appearance so the
## on-loom web, the stored bolt and downstream garment production agree.

const APPEARANCE = preload("res://scripts/material_appearance.gd")
const PAPER = preload("res://shaders/room_paper.gdshader")

@export var picks_per_meter := 40.0
@export var batch_length_m := 2.0
@export var seconds_per_pick := 8.0
@export var fabric_width_m := 1.4
@export var warp_ends := 60
@export var warp_allowance_m := 0.6
@export var weave_pattern := "plain"
@export var weave_material := "wool"
@export var preferred_yarn := ""

var picks_done := 0
var picks_lifetime := 0
var produced := 0
var elapsed := 0.0
var phase := "idle"
var inventory: Node3D
var production: Node3D
var operator_ref: WeakRef
var active_descriptor := {}
var batch_settings := {}
var active_yarn: Array[Dictionary] = []
var model: Node3D
var beater: Node3D
var shuttle: Node3D
var roll: Node3D
var takeup_cloth: MeshInstance3D
var cloth: MeshInstance3D
var warp: MeshInstance3D
var cloth_material: ShaderMaterial
var warp_material: ShaderMaterial
var beat_grip: MeshInstance3D
var takeup_lever: MeshInstance3D
var stool: Node3D
var seat_support: Marker3D
var bolt_access: Marker3D
var heddles: Array[Node3D] = []
var treadles: Array[Node3D] = []
var output_mounts: Array[Marker3D] = []


func _process(_delta: float) -> void:
	if operator_ref != null and not is_instance_valid(operator_ref.get_ref()):
		stop()


func _ready() -> void:
	model = load("res://assets/models/interactive_loom.glb").instantiate()
	add_child(model)
	for part in model.find_children("*", "MeshInstance3D", true, false):
		var original: Material = part.mesh.surface_get_material(0)
		var material := ShaderMaterial.new()
		material.shader = PAPER
		material.set_shader_parameter("pigment", original.albedo_color if original is StandardMaterial3D else Color("89664b"))
		part.material_override = material
	beater = model.find_child("BeaterPivot", true, false)
	beat_grip = MeshInstance3D.new()
	beat_grip.name = "SeatedBeaterGrip"
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(.62,.045,.045)
	beat_grip.mesh = grip_mesh
	beat_grip.material_override = _paper(Color("89664b"))
	beater.add_child(beat_grip)
	beat_grip.position = Vector3(0,.06,.63)
	shuttle = model.find_child("ShuttlePivot", true, false)
	roll = model.find_child("ClothRollPivot", true, false)
	for index in 2:
		heddles.append(model.find_child("Heddle%d" % index, true, false))
		treadles.append(model.find_child("Treadle%d" % index, true, false))
	warp_material = APPEARANCE.make_material({"pattern": "plain", "pigment": Color("e4d8bc"), "material": "cotton"})
	warp = MeshInstance3D.new()
	warp.name = "ContinuousWarp"
	warp.material_override = warp_material
	add_child(warp)
	cloth_material = APPEARANCE.make_material({"pattern": "plain", "pigment": Color("e4d8bc"), "material": "cotton"})
	cloth = MeshInstance3D.new()
	cloth.name = "GrowingWovenCloth"
	cloth.material_override = cloth_material
	add_child(cloth)
	takeup_cloth = MeshInstance3D.new()
	takeup_cloth.name = "WovenTakeupRoll"
	takeup_cloth.rotation.z = PI*.5
	takeup_cloth.position = Vector3(0,.75,.78)
	add_child(takeup_cloth)
	# A reachable ratchet lever operates the cloth beam from the seat.
	takeup_lever = MeshInstance3D.new()
	takeup_lever.name = "TakeupLever"
	var handle := BoxMesh.new()
	handle.size = Vector3(.055,.055,.48)
	takeup_lever.mesh = handle
	takeup_lever.material_override = _paper(Color("694b35"))
	takeup_lever.position = Vector3(-.33,1.00,.74)
	add_child(takeup_lever)
	_build_stool()
	_build_output_shelf()
	bolt_access = Marker3D.new()
	bolt_access.name = "BoltAccess"
	bolt_access.position = Vector3(1.85, 0, 1.2)
	add_child(bolt_access)
	_update_geometry()


func _build_output_shelf() -> void:
	var wood := _paper(Color("6d4c36"))
	for index in 5:
		var part := MeshInstance3D.new()
		part.name = "FabricBookShelf%d" % index
		var box := BoxMesh.new()
		box.size = Vector3(1.0,.06,.62) if index == 0 else Vector3(.055,.69,.055)
		part.mesh = box
		part.material_override = wood
		part.position = Vector3(1.85,.69,.45) if index == 0 else Vector3(1.85+(-.44 if index % 2 == 0 else .44),.345,.45+(-.25 if index <= 2 else .25))
		add_child(part)


func _build_stool() -> void:
	stool = Node3D.new()
	stool.name = "WeaverStool"
	stool.position = Vector3(0, 0, 1.02)
	add_child(stool)
	var wood := _paper(Color("6d4c36"))
	var seat := MeshInstance3D.new()
	seat.name = "CanvasSeat"
	var canvas := SurfaceTool.new()
	canvas.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 12:
		for column in 12:
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var u: float = (column+corner.x)/12.0
				var v: float = (row+corner.y)/12.0
				canvas.add_vertex(Vector3((u-.5)*.46,.47-.035*sin(PI*u)*sin(PI*v),(v-.5)*.38))
	canvas.generate_normals()
	seat.mesh = canvas.commit()
	seat.material_override = _paper(Color("996b54"))
	stool.add_child(seat)
	for side in [-1.0,1.0]:
		for slope in [-1.0,1.0]:
			var leg := MeshInstance3D.new()
			var rail := BoxMesh.new()
			rail.size = Vector3(.025,.53,.035)
			leg.mesh = rail
			leg.material_override = wood
			leg.position = Vector3(side*.18+slope*.014,.225,0)
			leg.rotation.x = slope*.55
			stool.add_child(leg)
	seat_support = Marker3D.new()
	seat_support.name = "SeatSupport"
	seat_support.position = Vector3(0, .55, 0)
	seat_support.rotation.y = PI
	stool.add_child(seat_support)


func _paper(pigment: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAPER
	material.set_shader_parameter("pigment", pigment)
	return material


func _ledger() -> RefCounted:
	return inventory.materials if is_instance_valid(inventory) else null


func required_picks() -> int:
	return maxi(1, int(batch_settings.get("picks",round(picks_per_meter * batch_length_m))))


# Real yarn budget of one batch: weft is one fabric width per pick, warp is
# one end per strand plus the loom's unavoidable take-up waste.
func yarn_requirement() -> float:
	return required_picks() * fabric_width_m + warp_ends * (batch_length_m + warp_allowance_m)


func _total_yarn(ledger: RefCounted) -> float:
	var total := 0.0
	for record in ledger.yarn_batches:
		if record.get("meters") is float or record.get("meters") is int:
			total += maxf(0.0, float(record.meters))
	return total


# Idle looms advertise whether a (possibly resumed) batch can actually run,
# so the shop never walks a weaver to a loom that has no yarn.
func _free_output_slot() -> int:
	for index in output_mounts.size():
		var id: String = output_mounts[index].get_meta("fabric_id", "")
		var batch: Dictionary = inventory.materials.fabric(id)
		if not batch.is_empty() and float(batch.meters) <= .00001 and (production.order.is_empty() or production.order.fabric_id != id):
			return index
	return output_mounts.size() if output_mounts.size() < 3 else -1


func work_available() -> bool:
	if _free_output_slot() < 0: return false
	if picks_done > 0 or not active_yarn.is_empty():
		return true
	var ledger := _ledger()
	return ledger != null and not _plan_yarn(ledger,yarn_requirement()).is_empty()


# Plans the single up-front debit: the chosen skein's whole colour lot first,
# then any other lots in stock order. Empty when the stock cannot cover it.
func _plan_yarn(ledger: RefCounted, required: float) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	var chosen: Dictionary = ledger.yarn(preferred_yarn) if not preferred_yarn.is_empty() else {}
	if chosen.is_empty():
		for candidate in ledger.yarn_batches:
			var available := 0.0
			for record in ledger.yarn_batches:
				if record.get("pigment") == candidate.get("pigment") and record.get("material") == candidate.get("material"):
					available += maxf(0,float(record.get("meters",0)))
			if available >= required-.0001:
				chosen = candidate
				break
	if chosen.is_empty():
		return []
	var lot_pigment: Color = chosen.get("pigment", Color.WHITE)
	for record in ledger.yarn_batches:
		if record.get("pigment", Color.WHITE) == lot_pigment and record.get("material","wool") == chosen.get("material","wool") and float(record.get("meters", 0.0)) > 0.0:
			ordered.append(record)
	var plan: Array[Dictionary] = []
	var covered := 0.0
	for record in ordered:
		var take := minf(float(record.meters), required - covered)
		plan.append({"record": record, "take": take})
		covered += take
		if covered >= required - .0001:
			return plan
	return []


func _start_batch() -> bool:
	var ledger := _ledger()
	if ledger == null:
		return false
	var plan := _plan_yarn(ledger, yarn_requirement())
	if plan.is_empty():
		return false
	batch_settings = {"picks":required_picks(),"length":batch_length_m,"width":fabric_width_m,"density":picks_per_meter}
	active_yarn.clear()
	var pigment := Color("e4d8bc")
	var sources: Array = []
	for debit in plan:
		var record: Dictionary = debit.record
		record.meters = float(record.meters) - float(debit.take)
		active_yarn.append({"id": str(record.get("id", "")), "meters": debit.take})
		if sources.is_empty():
			pigment = record.get("pigment", pigment)
		sources.append(str(record.get("id", "")))
	active_descriptor = APPEARANCE.describe({
		"pattern": weave_pattern,
		"pigment": pigment,
		"material": plan[0].record.get("material",weave_material),
		"width_m": fabric_width_m,
		"source_ids": sources,
	})
	cloth_material = APPEARANCE.make_material(active_descriptor)
	cloth.material_override = cloth_material
	var bobbin := shuttle.find_child("ShuttleBobbin", true, false) as MeshInstance3D
	if bobbin != null:
		bobbin.material_override = APPEARANCE.make_material(active_descriptor)
	var warp_data := active_descriptor.duplicate(true)
	warp_data["pattern"] = "plain"
	warp_data["pigment"] = (active_descriptor["pigment"] as Color).lightened(.10)
	warp_material = APPEARANCE.make_material(warp_data)
	warp.material_override = warp_material
	return true


func _finish_batch() -> void:
	produced += 1
	var batch := active_descriptor.duplicate(true)
	batch["id"] = "woven_%d_%d" % [get_instance_id(), produced]
	var pattern_cn: String = {"plain": "素色", "stripe": "条纹", "check": "格纹"}.get(batch.pattern, "素色")
	var material_cn: String = {"wool": "羊毛", "cotton": "棉", "linen": "亚麻", "silk": "丝"}.get(weave_material, weave_material)
	batch["name"] = "手织%s%s布" % [pattern_cn, material_cn]
	batch["meters"] = batch_settings.length
	batch["capacity_m"] = batch_settings.length
	batch["width_m"] = batch_settings.width
	batch["thickness_m"] = .002
	batch["form"] = "book"
	batch["location"] = "storage"
	batch["source"] = "loom"
	batch["picks"] = required_picks()
	picks_done = 0
	active_yarn.clear()
	if is_instance_valid(inventory):
		inventory.receive_fabric(batch)
	_register_output(batch)
	batch_settings.clear()
	if is_instance_valid(production) and production.game != null and production.game.has_method("_show_toast"):
		production.game._show_toast("织好一匹 %.1f 米%s" % [batch_length_m, str(batch["name"])])


# The bolt lives at the loom as the one registered source package; the
# production stock sync then never conjures a cabinet duplicate for it.
func _register_output(batch: Dictionary) -> void:
	if not is_instance_valid(production):
		return
	var index := _free_output_slot()
	if index < 0:
		return
	var mount: Marker3D
	if index == output_mounts.size():
		mount = Marker3D.new()
		mount.name = "BoltMount_%d" % index
		mount.position = Vector3(1.55+index*.30,.72,.45)
		add_child(mount)
		output_mounts.append(mount)
	else:
		mount = output_mounts[index]
		var previous: String = mount.get_meta("fabric_id")
		production.packages[previous].hide()
	mount.set_meta("fabric_id",batch.id)
	production.register_source_package(batch, "book", mount, bolt_access)


# Returns "working", "approaching", "busy" (another operator owns the loom),
# "paused" (zero delta), or "no_yarn" (no start/resume possible). Only
# "no_yarn" ends the staff job; progress otherwise persists on the loom.
func advance(actor: Node3D, delta: float) -> String:
	if delta <= 0.0 or not is_instance_valid(actor):
		return "paused"
	var current: Node3D = operator_ref.get_ref() if operator_ref != null else null
	if is_instance_valid(current) and current != actor:
		return "busy"
	if not actor.has_arrived() or actor.is_moving():
		return "approaching"
	operator_ref = weakref(actor)
	_seat(actor)
	if _free_output_slot() < 0 and active_yarn.is_empty(): return "output_full"
	if picks_done <= 0 and active_yarn.is_empty() and not _start_batch():
		return "no_yarn"
	actor.set_activity("weaving")
	elapsed += delta
	var needed := required_picks()
	while elapsed >= seconds_per_pick:
		elapsed -= seconds_per_pick
		picks_done += 1
		picks_lifetime += 1
		if picks_done >= needed:
			_finish_batch()
			if _free_output_slot() < 0: return "output_full"
			needed = required_picks()
			if not _start_batch():
				_update_geometry()
				_pose_operator(actor)
				return "no_yarn"
	var t := fposmod(elapsed, seconds_per_pick) / seconds_per_pick
	phase = "shed" if t < .20 else ("shuttle" if t < .63 else ("beat" if t < .88 else "take_up"))
	_update_geometry()
	_pose_operator(actor)
	return "working"


func _seat(actor: Node3D) -> void:
	if not ("rest_support" in actor):
		return
	var seated: bool = actor.rest_support != null and actor.rest_support.get_ref() == seat_support
	if not seated:
		actor.rest_support = weakref(seat_support)
		actor.rest_mode = "sit"
	actor.rest_departing = false


func stop() -> void:
	var actor: Node3D = operator_ref.get_ref() if operator_ref != null else null
	if is_instance_valid(actor):
		if "rest_support" in actor and actor.rest_support != null and actor.rest_support.get_ref() == seat_support:
			actor.rest_support = null
		actor.clear_interaction()
	operator_ref = null
	phase = "idle"


func _pose_operator(actor: Node3D) -> void:
	var t := fposmod(elapsed, seconds_per_pick) / seconds_per_pick
	var direction := 1.0 if picks_lifetime % 2 == 0 else -1.0
	var shed := sin(smoothstep(0, .22, t) * PI * .5) * (1.0 - smoothstep(.62, .80, t)) * .10 * direction
	var press := clampf(absf(shed) / .10, 0.0, 1.0)
	var pressed := 0 if direction > 0 else 1
	match phase:
		"shuttle":
			var moving_left: bool = shuttle.position.x < 0
			var shuttle_side := "R" if moving_left else "L"
			actor.reach(shuttle_side, shuttle.to_global(Vector3(0, .05, .02)))
			actor.reach("L" if shuttle_side == "R" else "R", to_global(Vector3((.42 if shuttle_side == "R" else -.42), 1.30, .70)))
			actor.attend(shuttle)
		"beat":
			actor.reach("L", beat_grip.to_global(Vector3(.20,0,0)))
			actor.reach("R", beat_grip.to_global(Vector3(-.20,0,0)))
			actor.attend(beater)
		"take_up":
			actor.reach("L", to_global(Vector3(.32, 1.30, .70)))
			actor.reach("R", takeup_lever.to_global(Vector3(0,0,.20)))
			actor.attend(roll)
		_:
			actor.reach("L", beat_grip.to_global(Vector3(.20,0,0)))
			actor.reach("R", beat_grip.to_global(Vector3(-.20,0,0)))
			actor.attend(heddles[0])
	for side in ["L", "R"]:
		var index := 1 if side == "L" else 0
		var dip := .07 * press if index == pressed else 0.0
		actor.foot_targets[side] = treadles[index].to_global(Vector3(0, .165, .85))


func _update_geometry() -> void:
	var t := fposmod(elapsed, seconds_per_pick) / seconds_per_pick
	var direction := 1.0 if picks_lifetime % 2 == 0 else -1.0
	var shed := sin(smoothstep(0, .22, t) * PI * .5) * (1.0 - smoothstep(.62, .80, t)) * .10 * direction
	for index in 2:
		heddles[index].position.y = 1.39 + shed * (1 if index == 0 else -1)
		treadles[index].rotation.x = shed * (1 if index == 0 else -1) * 1.2
	shuttle.position.x = lerpf(-.88, .88, smoothstep(.20, .62, t)) * direction
	beater.rotation.x = -sin(smoothstep(.64, .90, t) * PI) * .22
	takeup_lever.rotation.x = -.32*sin(smoothstep(.88,1.0,t)*PI)
	roll.rotation.x = -picks_lifetime * .09 - smoothstep(.88, 1.0, t) * .09
	var strands := SurfaceTool.new()
	strands.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 60:
		var x := -.92 + index * .0312
		var middle := 1.37 + shed * (1 if index % 2 == 0 else -1)
		var points := [Vector3(x, 1.44, -.63), Vector3(x, middle, -.20), Vector3(x, 1.29, .40)]
		for segment in 2:
			for corner in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				strands.set_normal(Vector3.UP)
				strands.add_vertex(points[segment + corner.y] + Vector3((corner.x - .5) * .008, 0, 0))
	warp.mesh = strands.commit()
	var width: float = batch_settings.get("width",fabric_width_m)
	var woven: float = float(picks_done)/float(batch_settings.get("density",picks_per_meter))
	var hanging := minf(woven,.66)
	var web := SurfaceTool.new()
	web.begin(Mesh.PRIMITIVE_TRIANGLES)
	var route := [Vector3(0,1.29,.40),Vector3(0,1.29,.71),Vector3(0,1.17,.78),Vector3(0,.75,.78)]
	var remaining := hanging
	for row in route.size()-1:
		if remaining <= .00001: break
		var start: Vector3 = route[row]
		var finish: Vector3 = route[row+1]
		var segment := start.distance_to(finish)
		finish = start.lerp(finish,minf(1,remaining/segment))
		for corner in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
			web.add_vertex((start if corner.y == 0 else finish)+Vector3((corner.x-.5)*width,0,0))
		remaining -= segment
	cloth.visible = hanging > .00001
	if cloth.visible:
		web.generate_normals()
		cloth.mesh = web.commit()
	var rolled := maxf(0,woven-.66)
	takeup_cloth.visible = rolled > 0
	if takeup_cloth.visible:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = sqrt(.045*.045+rolled*.002/PI)
		cylinder.bottom_radius = cylinder.top_radius
		cylinder.height = width
		takeup_cloth.mesh = cylinder
		takeup_cloth.material_override = cloth_material
	cloth.set_meta("woven_length",woven)
	cloth.set_meta("fabric_width_m",width)
	takeup_cloth.set_meta("rolled_length",rolled)
