extends Node3D

const Package = preload("res://components/material_package.gd")
const CLOTH = preload("res://shaders/material_cloth.gdshader")
const APPEARANCE = preload("res://scripts/material_appearance.gd")
const RECIPES = preload("res://scripts/garment_recipes.gd")
const PAPER = preload("res://shaders/room_paper.gdshader")
const ACCESS = preload("res://scripts/material_access.gd")
const StationProtocol = preload("res://scripts/work_station_sequence.gd")
const PHASE_NAMES := {"idle":"待安排", "to_fabric":"前往取布", "take_fabric":"抽取布料", "to_cut":"搬布到裁剪台", "place_fabric":"放下布料", "unfold":"展开量布", "cut":"裁剪围裙", "rewind":"整理剩布", "to_return":"搬回剩布", "return_fabric":"归还布料", "take_thread":"拿取缝线", "mount_thread":"安装线轴", "to_pieces":"领取裁片", "take_pieces":"叠放裁片", "carry_pieces":"搬运裁片", "place_pieces":"摆好裁片", "sew":"缝制围裙", "finish":"折好成衣", "take_output":"拿起成衣", "to_output":"成衣入库", "store_output":"收好成衣", "unmount":"取下剩线", "return_thread":"归还线轴", "store_thread":"收好线轴", "park":"放下周转物", "recover":"找回周转物", "lift_recovery":"取回周转物", "to_remnant":"回到裁剪台", "load_remnant":"抱起剩布"}
const TRAY_HOME := Vector3(.55,1.14,.33)
const TRAY_STAGE := Vector3(.31,.045,.19)
const PIECES_HOME := Vector3(-.66,1.18,.20)
const SPINDLE_LOCAL := Vector3(.18,.80,0)
var game: Node
var ledger: RefCounted
var cabinet: Node3D
var cutting: Node3D
var sewing: Node3D
var machine: Node3D
var actor: Node3D
var order: Dictionary = {}
var phase := "idle"
var elapsed := 0.0
var selected_fabric := "opening_cloth"
var selected_thread := "thread_blue"
var size_factor := 1.0
var selected_skirt_length := .70
var selected_garment_length := .80
var selected_style := 1
var selected_flower_target := ""
var auto_restock := true
@export_range(2,9,1) var auto_stock_target := 2
var packages: Dictionary = {}
var mounts: Dictionary = {}
var carried: Node3D
var carried_extra: Node3D
var start_transform := Transform3D.IDENTITY
var sheet: MeshInstance3D
var pieces: Node3D
var remnant_bin: Node3D
var output_bin: Node3D
var output_item: Node3D
var cut_access: Marker3D
var cut_left: Marker3D
var cut_right: Marker3D
var machine_access: Marker3D
var sew_left: Marker3D
var sew_right: Marker3D
var recovery_access: Marker3D
var pending_interrupt: Callable
var resume_phase := ""
var parked: Node3D
var parked_next := ""
var finished_count := 0
var phase_history: Array[String] = []
var _machine_rest: Dictionary = {}
var _remnant_nodes: Dictionary = {}
var suspended_action := ""
var suspended_elapsed := 0.0
var unrolled_m := 0.0
var fabric_access: Marker3D
var thread_access: Marker3D
var _access: RefCounted
var _last_anchor: Marker3D
var _arrival_face := Vector3.ZERO
var _travel_options: Array = []
var _travel_index := 0
var _blocked_elapsed := 0.0
var _extra_mode := "atop"
var _extra_manual := false
var _extra_start := Transform3D.IDENTITY
var _action_ready := false
var station_protocol: RefCounted
static var _sheet_mesh_pool: Dictionary = {}
const TRAVEL_PHASES := ["to_fabric","to_thread","to_cut","to_pieces","carry_pieces","resume_sew","to_output","return_tray","to_unmount","to_remnant","to_return","to_machine","return_thread","recover","resume_action"]
const ARRIVAL_ACTION := {"to_fabric":"take_fabric","to_thread":"take_thread","to_cut":"place_fabric","to_pieces":"take_pieces","carry_pieces":"place_pieces","to_machine":"mount_thread","resume_sew":"sew","to_output":"store_output","return_tray":"store_tray","to_unmount":"unmount","to_remnant":"load_remnant","to_return":"return_fabric","return_thread":"store_thread","recover":"lift_recovery"}
# Stationary phases with empty hands can suspend in place; anything else defers
# to the next safe point so a carried load is always parked, never dropped mid-step.
const SUSPEND_IMMEDIATE := ["take_pieces","mount_thread","unmount","rewind"]


func setup(controller: Node) -> void:
	game = controller
	station_protocol = StationProtocol.new("production", {
		"labels": PHASE_NAMES,
		"travel_phases": TRAVEL_PHASES,
		"arrival_actions": ARRIVAL_ACTION,
		"suspend_immediate": SUSPEND_IMMEDIATE,
		"durations": {"unfold": 2.4, "cut": 2.8, "sew": 4.2},
	})
	ledger = game._inventory.materials
	var room: Node3D = game._rooms.workshop
	_access = ACCESS.new(room)
	cabinet = room.get_node("MaterialCabinet")
	cutting = room.get_node("CuttingTable")
	sewing = room.get_node("SewingWorkbench")
	machine = sewing.get_node("SewingMachine")
	machine.position.z = .28
	cut_access = _marker(cutting,"MaterialCutAccess",Vector3(0,0,1.15))
	cut_left = _marker(cutting,"MaterialCutLeftAccess",Vector3(-1.25,0,1.15))
	cut_right = _marker(cutting,"MaterialCutRightAccess",Vector3(1.25,0,1.15))
	machine_access = _marker(sewing,"MaterialSewAccess",Vector3(0,0,1.0))
	sew_left = _marker(sewing,"MaterialSewLeftAccess",Vector3(-.9,0,1.0))
	sew_right = _marker(sewing,"MaterialSewRightAccess",Vector3(.9,0,1.0))
	recovery_access = _marker(self,"RecoveryAccess",Vector3.ZERO)
	fabric_access = _marker(cabinet,"FabricAccess",Vector3(0,0,1.14))
	thread_access = _marker(cabinet,"ThreadAccess",Vector3(.94,0,1.14))
	for child in sewing.get_children():
		if str(child.name).begins_with("ThreadSpool") or child.name == "HangingCloth": child.hide()
	machine.get_node("ThreadSpool").hide()
	machine.clear_thread()
	machine.get_node("FabricUnderFoot").hide()
	for label in ["NeedleBar","Needle","PresserFoot","Handwheel"]:
		_machine_rest[label] = machine.get_node(label).transform
	sheet = MeshInstance3D.new()
	sheet.name = "MeasuredFabric"
	cutting.add_child(sheet)
	sheet.position = Vector3(-.25,1.10,.03)
	sheet.hide()
	pieces = _tray(cutting,"CutPieceTray",TRAY_HOME,Vector2(.82,.60))
	remnant_bin = _tray(cutting,"RemnantBin",Vector3(.57,.39,.15),Vector2(.70,.65))
	output_bin = _marker(cabinet,"FinishedAprons",cabinet.output.position)
	sync_stock()
	cabinet.arrange_fabrics(packages,mounts)


func _marker(parent: Node3D, label: String, at: Vector3) -> Marker3D:
	var node := Marker3D.new()
	node.name = label
	parent.add_child(node)
	node.position = at
	return node


func _box(parent: Node3D, label: String, dimensions: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = PAPER
	mat.set_shader_parameter("pigment",color)
	node.material_override = mat
	parent.add_child(node)
	node.position = at
	return node


func _tray(parent: Node3D, label: String, at: Vector3, size: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	node.position = at
	_box(node,"Base",Vector3(size.x,.04,size.y),Vector3.ZERO,Color("bda57b"))
	for sign_value in [-1.0,1.0]:
		_box(node,"LongEdge",Vector3(size.x,.12,.035),Vector3(0,.07,sign_value*size.y*.5),Color("dfcda2"))
		_box(node,"Handle",Vector3(.045,.15,size.y),Vector3(sign_value*size.x*.5,.08,0),Color("d3b78c"))
	return node


func cloth_material(data: Dictionary) -> ShaderMaterial:
	return APPEARANCE.make_material(data)


func sync_stock() -> void:
	for index in ledger.fabric_batches.size():
		var data: Dictionary = ledger.fabric(str(ledger.fabric_batches[index].id))
		var id := str(data.id)
		if not packages.has(id) and index < cabinet.fabric_mounts.size():
			_add_package(data,str(data.get("form","book")),cabinet.fabric_mount(index))
	for index in ledger.thread_batches.size():
		var data: Dictionary = ledger.thread(str(ledger.thread_batches[index].id))
		if not packages.has(str(data.id)) and index < cabinet.thread_mounts.size():
			_add_package(data,"spool",cabinet.thread_mount(index))
	for index in mini(ledger.yarn_batches.size(),cabinet.yarn_mounts.size()):
		var data: Dictionary = ledger.yarn_batches[index]
		if not packages.has(str(data.id)):
			_add_package(data,"yarn",cabinet.yarn_mounts[index])
			packages[str(data.id)].scale = Vector3.ONE*.64
	for id in packages:
		var data: Dictionary = ledger.fabric(id)
		if data.is_empty(): data = ledger.thread(id)
		if data.is_empty(): data = ledger.yarn(id)
		if not data.is_empty():
			var drawn := unrolled_m if not order.is_empty() and id == order.fabric_id and order.status == "reserved" else 0.0
			packages[id].set_quantity(float(data.meters)-drawn)
	for remnant in ledger.remnants:
		var id := str(remnant.get("id",remnant.get("job_id", "")))
		if _remnant_nodes.has(id): continue
		var node := _box(remnant_bin,"ReusableRemnant",Vector3(.50,.018,.40),Vector3(0,.06+_remnant_nodes.size()*.023,0),Color.WHITE)
		var source: Dictionary = ledger.fabric(str(remnant.get("fabric_id","")))
		if source.is_empty() and not order.is_empty(): source = order.material_snapshot
		node.material_override = cloth_material(source)
		node.set_meta("material_record",remnant)
		_remnant_nodes[id] = node


# A new source (e.g. the loom) can supply the physical bolt at its actual
# output position, without duplicating it into a full cabinet or teleporting it.
func register_source_package(data: Dictionary, form: String, mount: Node3D, access: Marker3D) -> Node3D:
	var id := str(data.id)
	if packages.has(id): return packages[id]
	mount.set_meta("material_access",access)
	_add_package(data,form,mount)
	return packages[id]


func _add_package(data: Dictionary, form: String, mount: Node3D) -> void:
	var node := Package.new()
	node.name = str(data.id)
	mount.add_child(node)
	node.configure(data,form)
	packages[str(data.id)] = node
	mounts[str(data.id)] = mount
	data["location"] = "storage"


func can_start() -> bool:
	var stock_location := "accessory" if selected_style == RECIPES.FLOWER_STYLE else "storage"
	return order.is_empty() and packages.has(selected_fabric) and packages.has(selected_thread) and game._inventory.in_location(stock_location).size() < game._inventory.STORAGE_LIMIT and ledger.can_reserve(selected_fabric,selected_thread,size_factor,selected_style,selected_skirt_length,selected_garment_length)


# Starts an order from a supply-catalog snapshot. Reservation happens here, at
# dispatch time; worker assignment still goes through the normal assign() call.
func begin_order(fabric_id: String, thread_id: String, order_size: float, style: int, skirt: float, garment: float) -> Dictionary:
	if not order.is_empty():
		return {}
	var stock_location := "accessory" if style == RECIPES.FLOWER_STYLE else "storage"
	if not packages.has(fabric_id) or not packages.has(thread_id) or game._inventory.in_location(stock_location).size() >= game._inventory.STORAGE_LIMIT:
		return {}
	order = ledger.reserve(fabric_id, thread_id, order_size, style, skirt, garment)
	if order.is_empty():
		return {}
	output_item = null
	phase = "to_fabric"
	return order


func assign(worker: Node3D) -> bool:
	if is_instance_valid(actor): return actor == worker
	if order.is_empty():
		if not can_start(): return false
		order = ledger.reserve(selected_fabric,selected_thread,size_factor,selected_style,selected_skirt_length,selected_garment_length)
		if order.is_empty(): return false
		if selected_style == RECIPES.FLOWER_STYLE: order["flower_target_id"] = selected_flower_target
		output_item = null
		phase = "to_fabric"
	actor = worker
	actor.set_meta("material_handling",true)
	if is_instance_valid(parked):
		resume_phase = phase
		_move("recover",recovery_access,parked.global_position)
	elif phase == "idle":
		_approach("to_fabric","take_fabric",mounts[order.fabric_id].global_position,_fabric_candidates())
	else:
		_resume()
	return true


func _resume() -> void:
	if not suspended_action.is_empty():
		var cutting_action := suspended_action in ["unfold","cut"]
		_move("resume_action",cut_access if cutting_action else machine_access,sheet.global_position if cutting_action else machine.global_position)
		return
	match phase:
		"to_fabric", "take_fabric": _approach("to_fabric","take_fabric",mounts[order.fabric_id].global_position,_fabric_candidates())
		"to_thread", "take_thread": _approach("to_thread","take_thread",_thread_point(),_thread_candidates())
		"to_cut", "place_fabric", "unfold", "cut", "rewind": _approach("to_cut","place_fabric",sheet.global_position,_cut_candidates())
		"to_pieces", "take_pieces": _approach("to_pieces","take_pieces",pieces.global_position,_cut_candidates())
		"carry_pieces", "place_pieces": _approach("carry_pieces","place_pieces",_bench_point(),_sew_candidates())
		"to_machine", "mount_thread": _approach("to_machine","mount_thread",_spindle_point(),_sew_candidates())
		"resume_sew", "sew", "finish": _approach("resume_sew","sew",machine.global_position,_sew_candidates())
		"take_output", "to_output", "store_output", "unload_output": _approach("to_output","store_output",output_bin.global_position,[cabinet.access])
		"lift_empty_tray", "return_tray", "store_tray": _approach("return_tray","store_tray",cutting.to_global(TRAY_HOME),_cut_candidates())
		"to_unmount", "unmount": _approach("to_unmount","unmount",_spindle_point(),_sew_candidates())
		"to_remnant", "load_remnant": _approach("to_remnant","load_remnant",packages[order.fabric_id].global_position,_cut_candidates())
		"to_return", "return_fabric": _approach("to_return","return_fabric",mounts[order.fabric_id].global_position,_fabric_candidates())
		"return_thread", "store_thread": _approach("return_thread","store_thread",_thread_point(),_thread_candidates())


func request_interrupt(worker: Node3D, callback: Callable) -> bool:
	if actor != worker: return false
	if not is_instance_valid(carried) and not is_instance_valid(carried_extra) and (phase in TRAVEL_PHASES or phase in ["unfold","cut","sew"] or phase in SUSPEND_IMMEDIATE):
		suspend(worker)
		return false
	pending_interrupt = callback
	_flush_interrupt()
	return true


func _flush_interrupt() -> void:
	if not pending_interrupt.is_valid() or phase == "park" or not is_instance_valid(actor): return
	if phase not in TRAVEL_PHASES and phase not in ["unfold","cut","sew"] and phase not in SUSPEND_IMMEDIATE and phase != "place_pieces": return
	if is_instance_valid(carried):
		resume_phase = phase
		actor.stop_navigation()
		recovery_access.global_position = actor.global_position
		parked_next = phase
		_extra_manual = false
		if is_instance_valid(carried_extra): _extra_mode = "atop"
		_set_phase("park")
		start_transform = carried.global_transform
	else:
		suspend(actor)
		var callback := pending_interrupt
		pending_interrupt = Callable()
		callback.call()


func suspend(worker: Node3D) -> void:
	if actor != worker: return
	if phase in ["unfold","cut","sew"]:
		suspended_action = phase
		suspended_elapsed = elapsed
	elif not is_instance_valid(carried):
		# A half-taken package returns to its rest spot so resume picks it up cleanly.
		if phase == "mount_thread" and not order.is_empty():
			var spool: Node3D = packages[order.thread_id]
			if is_instance_valid(spool) and spool.get_parent() == self:
				spool.global_transform = _extra_start
		elif phase in ["take_pieces","unmount"]:
			var node := _pickup_node()
			if is_instance_valid(node) and node.get_parent() == self:
				node.global_transform = start_transform
	_machine_idle()
	actor.clear_interaction()
	actor.set_meta("material_handling",false)
	actor = null


func status_text() -> String:
	var style_name := RECIPES.style_name(int(order.get("outfit_style",selected_style))) if not order.is_empty() else RECIPES.style_name(selected_style)
	if order.is_empty(): return "选择布料与缝线，安排一件%s" % style_name
	var additional := {"to_thread":"前往取线","to_machine":"回到缝制台","unload_output":"放好成衣","lift_empty_tray":"拿起空托盘","return_tray":"送回托盘","store_tray":"放回托盘","to_unmount":"取回剩线","resume_action":"回到工位","resume_sew":"接续缝制"}
	var label := str(PHASE_NAMES.get(phase,additional.get(phase,"工位准备"))).replace("围裙",style_name)
	return ("待接续 · " if not is_instance_valid(actor) else "") + label


func _set_phase(value: String) -> void:
	var previous := phase
	phase = value
	elapsed = 0.0
	_action_ready = false
	phase_history.append(value)
	if is_instance_valid(actor): actor.clear_interaction()
	if is_instance_valid(carried): start_transform = carried.global_transform
	if station_protocol != null:
		station_protocol.notify_phase_entered(previous, value)


func get_station_snapshot() -> Dictionary:
	if station_protocol == null:
		return {"station_id": "production", "phase": phase, "label": status_text(), "busy": not order.is_empty()}
	return station_protocol.build_snapshot(self, {
		"busy": not order.is_empty(),
		"status_text": status_text(),
		"order_id": str(order.get("id", "")),
	})


func nudge_manual_step(seconds: float = 0.45) -> bool:
	if order.is_empty() or phase == "idle" or phase in TRAVEL_PHASES:
		return false
	if phase == "sew":
		order["sew_progress"] = clampf(float(order.get("sew_progress", 0.0)) + seconds / 4.2, 0.0, 1.0)
	elapsed += maxf(0.05, seconds)
	return true


func _thread_point() -> Vector3:
	return mounts[order.thread_id].global_position


func _bench_point() -> Vector3:
	return sewing.to_global(PIECES_HOME)


func _spindle_point() -> Vector3:
	return machine.to_global(SPINDLE_LOCAL)


func _fabric_candidates() -> Array:
	var origin: Node3D = mounts.get(order.fabric_id)
	if is_instance_valid(origin) and origin.has_meta("material_access"):
		var access: Marker3D = origin.get_meta("material_access")
		if is_instance_valid(access): return [access]
	fabric_access.position = Vector3(mounts[order.fabric_id].position.x,0,1.14)
	return [fabric_access,cabinet.access]


func _thread_candidates() -> Array:
	thread_access.position = Vector3(mounts[order.thread_id].position.x,0,1.14)
	return [thread_access,cabinet.access]


func _cut_candidates() -> Array:
	return [cut_access,cut_left,cut_right]


func _sew_candidates() -> Array:
	return [machine_access,sew_left,sew_right]


# Walks toward the best reachable candidate for the target, unless the worker
# already stands within comfortable reach — then it just turns and acts.
func _approach(travel: String, action: String, target: Vector3, candidates: Array) -> void:
	var anchor: Marker3D = _access.choose(actor.global_position,target,candidates,_last_anchor)
	if anchor == null and actor.has_arrived():
		_face_point(target)
		_begin_action(action)
		return
	if anchor == null:
		anchor = _access.nearest(actor.global_position,candidates)
	var options := [anchor]
	for marker in candidates:
		if is_instance_valid(marker) and marker != anchor: options.append(marker)
	_move(travel,anchor,target,options)


func _move(value: String, target: Marker3D, face: Vector3, options: Array = []) -> void:
	_set_phase(value)
	_arrival_face = face
	_blocked_elapsed = 0.0
	_travel_options = options if not options.is_empty() else [target]
	_travel_index = maxi(0,_travel_options.find(target))
	_last_anchor = target
	if is_instance_valid(target): actor.move_to_anchor(target,"stocking")


# Arrival and stay both enter a stationary phase the same way: face the actual
# target and snapshot the pickup's starting transform.
func _begin_action(action: String) -> void:
	_set_phase(action)
	if action in ["take_fabric","take_thread","take_pieces","take_output","unmount","lift_recovery","load_remnant"]:
		var node: Node3D = _pickup_node()
		if is_instance_valid(node): start_transform = node.global_transform


func _face_point(world: Vector3) -> void:
	if not is_instance_valid(actor): return
	var direction := world-actor.global_position
	if Vector2(direction.x,direction.z).length() < .01: return
	actor.resting_facing = atan2(direction.x,direction.z)


func _carry_transform(node: Node3D) -> Transform3D:
	var basis: Basis = actor.body_rig.global_basis
	var center := Vector3.ZERO
	if node.has_method("display_bounds"):
		center = node.display_bounds().get_center()
		if node.form == "book": basis *= Basis(Vector3.FORWARD,PI*.5)
	var held_at := Vector3(0,1.35,.52)
	if node.get("form") == "spool": held_at = Vector3(.30,1.32,.25)
	if node.has_method("display_bounds") and node.form == "roll": held_at = Vector3(0,1.52,.46)
	var origin: Vector3 = actor.body_rig.to_global(held_at)
	return Transform3D(basis,origin-basis*center)


func _ride_mode_for(load: Node3D) -> String:
	return "hand" if is_instance_valid(load) and load.get("form") == "roll" else "atop"


# Where the secondary package rides: stably on top of a flat load, or in the
# free hand when the main load is a roll that needs both grip points.
func _extra_ride_transform() -> Transform3D:
	var root: Node3D = carried if is_instance_valid(carried) else parked
	if _extra_mode == "hand" and is_instance_valid(actor):
		return Transform3D(actor.body_rig.global_basis,actor.body_rig.to_global(Vector3(.42,.98,.34)))
	if not is_instance_valid(root):
		return carried_extra.global_transform
	if root.has_method("display_bounds"):
		var world_box: AABB = root.global_transform*root.display_bounds()
		var at := Vector3(world_box.get_center().x,world_box.end.y+.005,world_box.get_center().z)
		return Transform3D(Basis.IDENTITY,at)
	return Transform3D(Basis.IDENTITY,root.to_global(Vector3.ZERO))


func _follow_extra() -> void:
	if not is_instance_valid(carried_extra) or _extra_manual: return
	carried_extra.global_transform = _extra_ride_transform()


func _grip(node: Node3D) -> void:
	if node.get("form") == "spool":
		actor.hand_targets.erase("L")
		actor.reach("R",node.to_global(node.display_bounds().get_center()))
		actor.apply_reaches()
		return
	var spare_hand := is_instance_valid(carried_extra) and _extra_mode == "hand" and not _extra_manual
	var spool_grip: Vector3 = carried_extra.to_global(Vector3(0,.12,0)) if spare_hand else Vector3.ZERO
	if node.has_method("grip_points"):
		var points: Array = node.grip_points()
		actor.reach("L",points[0])
		actor.reach("R",spool_grip if spare_hand else points[1])
	else:
		actor.reach("L",node.to_global(Vector3(-.4,.09,0)))
		actor.reach("R",spool_grip if spare_hand else node.to_global(Vector3(.4,.09,0)))
	actor.apply_reaches()


func _carry() -> void:
	if is_instance_valid(carried):
		carried.global_transform = _carry_transform(carried)
		_grip(carried)
	_follow_extra()


func _take(node: Node3D, t: float) -> void:
	if elapsed <= .0001: start_transform = node.global_transform
	if node.get_parent() != self: node.reparent(self,true)
	node.global_transform = start_transform.interpolate_with(_carry_transform(node),smoothstep(.25,1,t))
	_grip(node)
	_follow_extra()
	if t >= 1: carried = node


func _place(target: Transform3D, t: float) -> void:
	if not is_instance_valid(carried): return
	carried.global_transform = start_transform.interpolate_with(target,smoothstep(0,1,t))
	_grip(carried)
	_follow_extra()


# The spool leaves its mount and settles into its ride position on the load
# the worker is already holding; one hand tracks it, the other steadies the load.
func _take_extra(t: float) -> void:
	if not is_instance_valid(carried_extra): return
	carried_extra.global_transform = _extra_start.interpolate_with(_extra_ride_transform(),smoothstep(.25,1,t))
	actor.reach("R",carried_extra.to_global(Vector3(0,.12,0)))
	if is_instance_valid(carried):
		if carried.has_method("grip_points"):
			actor.reach("L",carried.grip_points()[0])
		else:
			actor.reach("L",carried.to_global(Vector3(-.4,.09,0)))


func advance(delta: float) -> void:
	if delta <= 0.0: return
	sync_stock()
	if not is_instance_valid(actor): return
	if actor.navigation_status == "blocked" and phase != "park":
		actor.clear_interaction()
		_carry()
		if phase in TRAVEL_PHASES:
			_blocked_elapsed += delta
			if _blocked_elapsed > 1.2 and _travel_index+1 < _travel_options.size():
				_travel_index += 1
				_blocked_elapsed = 0.0
				var fallback: Marker3D = _travel_options[_travel_index]
				if is_instance_valid(fallback):
					_last_anchor = fallback
					actor.move_to_anchor(fallback,"stocking")
		return
	_blocked_elapsed = 0.0
	_flush_interrupt()
	if not is_instance_valid(actor): return
	if phase in TRAVEL_PHASES:
		_carry()
		if not actor.has_arrived(): return
		if phase == "resume_action":
			var cutting_action := suspended_action in ["unfold","cut"]
			_face_point(sheet.global_position if cutting_action else machine.global_position)
			_set_phase(suspended_action)
			elapsed = suspended_elapsed
			suspended_action = ""
			return
		_face_point(_arrival_face)
		_begin_action(ARRIVAL_ACTION[phase])
		return
	if phase != "park" and not actor.has_arrived():
		# The actor follows a moved furniture anchor before continuing the action.
		actor.clear_interaction()
		return
	elapsed += delta
	var t := minf(elapsed/1.25,1.0)
	match phase:
		"take_fabric":
			_take(packages[order.fabric_id],t)
			if t >= 1:
				ledger.fabric(order.fabric_id).location = "carried"
				# The reserved spool is collected in the same cabinet visit.
				_approach("to_thread","take_thread",_thread_point(),_thread_candidates())
		"take_thread":
			var spool: Node3D = packages[order.thread_id]
			if not _action_ready:
				_action_ready = true
				carried_extra = spool
				_extra_mode = _ride_mode_for(carried)
				_extra_start = spool.global_transform
				_extra_manual = true
				if spool.get_parent() != self: spool.reparent(self,true)
			_take_extra(t)
			if t >= 1:
				_extra_manual = false
				ledger.thread(order.thread_id).location = "carried"
				_approach("to_cut","place_fabric",sheet.global_position,_cut_candidates())
		"place_fabric":
			if not is_instance_valid(carried):
				_set_phase("unfold" if order.status == "reserved" else "rewind")
				return
			var target := _fabric_table_transform()
			_place(target,t)
			if is_instance_valid(carried_extra):
				if not _action_ready:
					_action_ready = true
					_extra_start = carried_extra.global_transform
					_extra_manual = true
				var stage := pieces.global_transform*Transform3D(Basis.IDENTITY,TRAY_STAGE)
				carried_extra.global_transform = _extra_start.interpolate_with(stage,smoothstep(.15,1,t))
				actor.reach("R",carried_extra.to_global(Vector3(0,.12,0)))
			if t >= 1:
				carried.reparent(cutting,true)
				ledger.fabric(order.fabric_id).location = "cutting"
				carried = null
				if is_instance_valid(carried_extra):
					# The spool waits on the tray and travels with the cut pieces.
					carried_extra.reparent(pieces,false)
					carried_extra.transform = Transform3D(Basis.IDENTITY,TRAY_STAGE)
					carried_extra = null
					_extra_manual = false
					ledger.thread(order.thread_id).location = "cutting"
				sheet.material_override = cloth_material(order.material_snapshot)
				sheet.show()
				_set_phase("unfold" if order.status == "reserved" else "rewind")
		"unfold":
			var u := minf(elapsed/2.4,1.0)
			packages[order.fabric_id].set_open_amount(smoothstep(0,.35,u))
			_sheet_geometry(u,false)
			# The drawn length is still stock until cutting commits the transfer.
			# Quantize visual wrap updates to 24 buckets during continuous unrolling.
			var q_u := float(roundi(u * 24.0)) / 24.0
			unrolled_m = float(order.estimate.cut_m)*u
			packages[order.fabric_id].set_quantity(float(ledger.fabric(order.fabric_id).meters)-float(order.estimate.cut_m)*q_u)
			_work_hands(u)
			if u >= 1: _set_phase("cut")
		"cut":
			var u := minf(elapsed/2.8,1.0)
			_work_hands(u)
			actor.reach("R",cutting.to_global(Vector3(-.48+u*.55,1.14,.43)))
			if u >= 1 and ledger.cut(order.id):
				unrolled_m = 0.0
				_sheet_geometry(1,true)
				_set_phase("rewind")
		"rewind":
			packages[order.fabric_id].set_open_amount(1-smoothstep(0,1,t))
			_work_hands(1-t)
			if t >= 1:
				_make_cut_pieces()
				sheet.hide()
				# The remnant bolt stays staged on the table; it returns to the
				# cabinet together with the leftover spool after sewing.
				_approach("to_pieces","take_pieces",pieces.global_position,_cut_candidates())
		"take_pieces":
			_take(pieces,t)
			if t >= 1:
				ledger.thread(order.thread_id).location = "carried"
				_approach("carry_pieces","place_pieces",_bench_point(),_sew_candidates())
		"place_pieces":
			if not is_instance_valid(carried):
				_set_phase("mount_thread")
				return
			_place(sewing.global_transform*Transform3D(Basis.IDENTITY,PIECES_HOME),t)
			if t >= 1:
				carried.reparent(sewing,true)
				carried = null
				ledger.thread(order.thread_id).location = "sewing"
				_set_phase("mount_thread")
		"mount_thread":
			var spool: Node3D = packages[order.thread_id]
			if not _action_ready:
				_action_ready = true
				_extra_start = spool.global_transform
				if spool.get_parent() != self: spool.reparent(self,true)
			var target := machine.global_transform*Transform3D(Basis.IDENTITY,SPINDLE_LOCAL)
			spool.global_transform = _extra_start.interpolate_with(target,smoothstep(0,1,t))
			actor.reach("R",spool.to_global(Vector3(0,.12,0)))
			actor.reach("L",pieces.to_global(Vector3(-.30,.12,0)))
			if t >= 1:
				spool.reparent(machine,true)
				ledger.thread(order.thread_id).location = "sewing"
				machine.set_work_materials(order.material_snapshot,order.thread_snapshot)
				_set_phase("sew")
		"sew":
			actor.set_activity("sewing")
			var progress := minf(float(order.sew_progress)+delta/7.5,1.0)
			if not ledger.advance_sewing(order.id,progress): return
			_animate_sewing(progress)
			if progress >= 1:
				_machine_idle()
				_set_phase("finish")
		"finish":
			if not is_instance_valid(output_item):
				output_item = game._inventory.create_from_work_order(order)
				if output_item == null: return
				output_item.place("production",_folded_transform(output_item,pieces),-1)
				output_item.visible = true
				var cut_piece := pieces.get_node_or_null("CutPieces")
				if cut_piece != null: cut_piece.hide()
			_grip(pieces)
			if t >= 1:
				output_item.reparent(pieces,true)
				_set_phase("take_output")
				start_transform = pieces.global_transform
		"take_output":
			_take(pieces,t)
			if t >= 1: _move("to_output",cabinet.access,output_bin.global_position)
		"store_output":
			_place(output_bin.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,.025,0)),t)
			if t >= 1:
				output_item.reparent(game._inventory,true)
				carried = null
				_set_phase("unload_output")
				start_transform = output_item.global_transform
		"unload_output":
			var target: Transform3D = output_bin.global_transform*game._inventory.stored_transform(output_item)
			output_item.global_transform = start_transform.interpolate_with(target,t)
			var bounds: AABB = output_item.presentation_bounds("Folded")
			var center: Vector3 = output_item.to_global(bounds.get_center())
			actor.reach("L",center+Vector3(-.2,0,0))
			actor.reach("R",center+Vector3(.2,0,0))
			if t >= 1:
				game._inventory.store_produced(output_item,output_bin)
				_set_phase("lift_empty_tray")
				start_transform = pieces.global_transform
		"lift_empty_tray":
			_take(pieces,t)
			if t >= 1: _approach("return_tray","store_tray",cutting.to_global(TRAY_HOME),_cut_candidates())
		"store_tray":
			if not is_instance_valid(carried):
				_approach("to_unmount","unmount",_spindle_point(),_sew_candidates())
				return
			_place(cutting.global_transform*Transform3D(Basis.IDENTITY,TRAY_HOME),t)
			if t >= 1:
				carried.reparent(cutting,true)
				carried = null
				_approach("to_unmount","unmount",_spindle_point(),_sew_candidates())
		"unmount":
			machine.clear_thread()
			_take(packages[order.thread_id],t)
			if t >= 1:
				ledger.thread(order.thread_id).location = "carried"
				_approach("to_remnant","load_remnant",packages[order.fabric_id].global_position,_cut_candidates())
		"load_remnant":
			var bolt: Node3D = packages[order.fabric_id]
			if not _action_ready:
				_action_ready = true
				# The spool moves onto the bolt so both leftovers return in one trip.
				if carried == packages[order.thread_id]:
					carried_extra = carried
					_extra_mode = _ride_mode_for(bolt)
					_extra_manual = false
				carried = bolt
				start_transform = bolt.global_transform
			_take(bolt,t)
			if t >= 1:
				ledger.fabric(order.fabric_id).location = "carried"
				_approach("to_return","return_fabric",mounts[order.fabric_id].global_position,_fabric_candidates())
		"return_fabric":
			if not is_instance_valid(carried):
				_approach("return_thread","store_thread",_thread_point(),_thread_candidates())
				return
			_place(mounts[order.fabric_id].global_transform,t)
			if t >= 1:
				carried.reparent(mounts[order.fabric_id],true)
				carried.transform = Transform3D.IDENTITY
				ledger.fabric(order.fabric_id).location = "storage"
				carried = null
				cabinet.arrange_fabrics(packages,mounts)
				if is_instance_valid(carried_extra):
					carried = carried_extra
					carried_extra = null
					_extra_manual = false
				_approach("return_thread","store_thread",_thread_point(),_thread_candidates())
		"store_thread":
			var spool: Node3D = packages[order.thread_id]
			if not is_instance_valid(carried):
				carried = spool
				start_transform = spool.global_transform
				if spool.get_parent() != self: spool.reparent(self,true)
			_place(mounts[order.thread_id].global_transform,t)
			if t >= 1:
				carried.reparent(mounts[order.thread_id],true)
				carried.transform = Transform3D.IDENTITY
				ledger.thread(order.thread_id).location = "storage"
				carried = null
				if ledger.complete(order.id,output_item.item_id):
					if int(order.get("outfit_style",1)) == RECIPES.FLOWER_STYLE and not str(order.get("flower_target_id","")).is_empty():
						if not game._inventory.attach_flower_to(output_item,str(order.flower_target_id)):
							game._show_toast("目标成衣暂不可装饰，胸花已单独入库")
					finished_count += 1
					game._show_toast("%s完成%s，剩布与线轴已归位" % [actor.doll_name,RECIPES.style_name(int(order.get("outfit_style",1)))])
					var worker := actor
					var after_finish := pending_interrupt
					pending_interrupt = Callable()
					suspended_action = ""
					actor.clear_interaction()
					actor.set_meta("material_handling",false)
					actor = null
					order = {}
					_set_phase("idle")
					game._set_staff_idle(worker,1.5)
					if after_finish.is_valid(): after_finish.call()
		"park":
			var target := start_transform
			target.origin.y = .18
			_place(target,t)
			if t >= 1:
				parked = carried
				carried = null
				phase = resume_phase
				suspend(actor)
				var callback := pending_interrupt
				pending_interrupt = Callable()
				if callback.is_valid(): callback.call()
		"lift_recovery":
			_take(parked,t)
			if t >= 1:
				parked = null
				if is_instance_valid(carried_extra): _extra_mode = _ride_mode_for(carried)
				phase = parked_next
				_resume()
	if is_instance_valid(actor): actor.apply_reaches()


func _pickup_node() -> Node3D:
	match phase:
		"take_fabric", "load_remnant": return packages[order.fabric_id]
		"take_thread", "unmount": return packages[order.thread_id]
		"lift_recovery": return parked
	return pieces


func _fabric_table_transform() -> Transform3D:
	var package: Node3D = packages[order.fabric_id]
	var basis := Basis(Vector3.FORWARD,PI*.5) if package.form == "book" else Basis.IDENTITY
	var bounds: AABB = package.display_bounds()
	return cutting.global_transform*Transform3D(basis,Vector3(-1.04,1.26,.12)-basis*bounds.get_center())


func _sheet_geometry(amount: float, shaped: bool) -> void:
	var bucket := roundi(clampf(amount, 0.0, 1.0) * 24.0)
	var q_amount := float(bucket) / 24.0
	var key := "%d:%d" % [bucket, 1 if shaped else 0]
	if _sheet_mesh_pool.has(key):
		sheet.mesh = _sheet_mesh_pool[key]
		return
	var points := PackedVector2Array([Vector2(-.38,-.46),Vector2(.38,-.46),Vector2(.38,.46),Vector2(-.38,.46)])
	if shaped:
		points = PackedVector2Array([Vector2(-.19,-.46),Vector2(.19,-.46),Vector2(.19,-.18),Vector2(.36,.02),Vector2(.36,.46),Vector2(-.36,.46),Vector2(-.36,.02),Vector2(-.19,-.18)])
	var indices := Geometry2D.triangulate_polygon(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var p := points[index]
		surface.set_normal(Vector3.UP)
		surface.set_uv(p)
		surface.add_vertex(Vector3(p.x,pow(1-q_amount,2)*.12, -.46+(p.y+.46)*maxf(.04,q_amount)))
	var built := surface.commit()
	_sheet_mesh_pool[key] = built
	sheet.mesh = built


func _work_hands(amount: float) -> void:
	actor.set_activity("sewing")
	actor.reach("L",cutting.to_global(Vector3(-.55,1.13,.53)))
	actor.reach("R",cutting.to_global(Vector3(.18,1.13,.53-.12*sin(amount*PI))))
	actor.attend(sheet)


func _make_cut_pieces() -> void:
	var previous := pieces.get_node_or_null("CutPieces")
	if previous != null: previous.free()
	# The same tray stays on the table, then travels with the worker.
	var cloth := _box(pieces,"CutPieces",Vector3(.60,.065,.44),Vector3(-.08,.065,-.02),Color.WHITE)
	cloth.material_override = cloth_material(order.material_snapshot)
	cloth.set_meta("work_order_id",order.id)
	cloth.set_meta("net_m",order.estimate.net_m)


func _animate_sewing(progress: float) -> void:
	var cycle := elapsed*TAU*4.0
	for label in ["NeedleBar","Needle"]:
		var node: Node3D = machine.get_node(label)
		node.transform = _machine_rest[label]
		node.position.y += sin(cycle)*.034
	machine.get_node("Handwheel").rotation.x = -cycle
	var cloth: Node3D = pieces.get_node_or_null("CutPieces")
	if cloth != null:
		cloth.position.z = -.06+progress*.15
	var plate := machine.to_global(Vector3(-.39,.105,.06))
	actor.reach("L",plate+sewing.global_basis*Vector3(-.18,.02,.10))
	actor.reach("R",plate+sewing.global_basis*Vector3(.23,.02,.14))
	actor.foot_targets["R"] = sewing.to_global(Vector3(.20,.15,.63))
	actor.attend(machine)
	var feed: MeshInstance3D = machine.get_node("FabricUnderFoot")
	feed.show()
	if machine.loaded_fabric_id != str(order.fabric_id) or machine.loaded_thread_id != str(order.thread_id):
		machine.set_work_materials(order.material_snapshot,order.thread_snapshot)
	feed.position.z = .18-progress*.12


func _machine_idle() -> void:
	for label in _machine_rest:
		machine.get_node(label).transform = _machine_rest[label]
	if order.is_empty() or float(order.get("sew_progress",0)) >= 1:
		machine.get_node("FabricUnderFoot").hide()


func _folded_transform(item: Node3D, support: Node3D) -> Transform3D:
	var bounds: AABB = item.presentation_bounds("Folded")
	var basis := Basis(Vector3.RIGHT,-PI*.5)
	var center: Vector3 = basis*bounds.get_center()
	return support.global_transform*Transform3D(basis,Vector3(0,.14+bounds.size.z*.5,0)-center)
