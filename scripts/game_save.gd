extends RefCounted
## Data-only local snapshots. No objects/scripts are deserialized from save files.
const VERSION := 1
const DEFAULT_PATH := "user://weave_game.save"
static var pending_snapshot: Dictionary = {}
const WORLD_FIELDS := ["_day_index","_day_minutes","_money","_business_state","_sales_count","_customer_serial","_electricity_kwh","_electricity_cost","_daily_electricity_cost","_electricity_paid","_electricity_fraction","_room_lights","_closing_sign_done","_workshop_time_started","_shift_departures_started"]
const ACTOR_FIELDS := ["doll_name","energy","hair_style","outfit_style","palette_index","skin_index","hair_color_index","eye_color_index","custom_skin_color","custom_hair_color","custom_eye_color","shoe_style","personality","move_speed","costume_collection"]
const LOOM_FIELDS := ["picks_done","picks_lifetime","produced","elapsed","phase","active_descriptor","batch_settings","active_yarn","picks_per_meter","batch_length_m","seconds_per_pick","weave_pattern","weave_material","preferred_yarn"]

static func stable_reason(game: Node) -> String:
	if game._business_state != "workshop": return "请先打烊，等待顾客离店并进入工坊时间。"
	if not game.customers.is_empty(): return "还有顾客尚未离店。"
	if game._business_chore.phase != "idle": return "请等待收店事务完成。"
	if game._production.phase != "idle" or game._dye.phase != "idle": return "请先完成或取消当前制作、染色，材料归位后再存档。"
	for job in game._supply_catalog.queue:
		if job.get("state","") not in ["completed","cancelled"]: return "生产队列仍有订单；请先完成或取消。"
	if not game._restock.transfers.is_empty(): return "员工正在搬货，请等物品归位。"
	for item in game._inventory.items:
		if not item.reserved_by.is_empty() or item.location not in ["rack","storage","basket","accessory","collected"]: return "有商品尚在服务或搬运途中。"
	return ""

static func _fields(object: Object, names: Array) -> Dictionary:
	var result := {}
	for key in names: result[key] = object.get(key)
	return result

static func _resource_data(resource: Resource) -> Dictionary:
	var result := {}
	if resource is Curve:
		var points := []
		for i in resource.point_count:
			points.append([resource.get_point_position(i),resource.get_point_left_tangent(i),resource.get_point_right_tangent(i),resource.get_point_left_mode(i),resource.get_point_right_mode(i)])
		return {"curve_points":points,"min_value":resource.min_value,"max_value":resource.max_value}
	for prop in resource.get_property_list():
		if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(prop.usage) & PROPERTY_USAGE_STORAGE:
			var value = resource.get(prop.name)
			result[prop.name] = {"nested_resource":_resource_data(value)} if value is Resource else value
	return result

static func _apply_resource(resource: Resource, data: Dictionary) -> void:
	if resource is Curve and data.has("curve_points"):
		resource.clear_points()
		resource.min_value = data.min_value
		resource.max_value = data.max_value
		for point in data.curve_points:
			resource.add_point(point[0],point[1],point[2],point[3],point[4])
		return
	for key in data:
		if data[key] is Dictionary and data[key].has("nested_resource"):
			var child = resource.get(key)
			if child is Resource: _apply_resource(child, data[key].nested_resource)
		else: resource.set(key, data[key])

static func capture(game: Node, state: Node) -> Dictionary:
	var inv = game._inventory
	var items := []
	for item in inv.items:
		var metadata := {}
		for key in ["fabric_sources","work_order_id","thread_source","material_cost"]:
			if item.has_meta(key): metadata[key] = item.get_meta(key)
		items.append({"id":item.item_id,"definition":_resource_data(item.definition),"location":item.location,"slot":item.slot,"owner":item.owner_id,"paid":item.paid,"tried":item.tried_on,"metadata":metadata})
	var actors := []
	for actor in game.staff:
		actors.append({"fields":_fields(actor,ACTOR_FIELDS),"transform":actor.transform,"visible":actor.visible})
	var layouts := {}
	for room_key in game._rooms:
		for footprint in game._rooms[room_key]._footprints:
			layouts[str(game.get_path_to(footprint.node))] = footprint.node.transform
	var looms := {}
	for node in game.find_children("*","Node3D",true,false):
		if node.get_script() == preload("res://components/working_loom.gd"):
			looms[str(game.get_path_to(node))] = _fields(node, LOOM_FIELDS)
	var extras := {}
	if is_instance_valid(game.get("_vendor")):
		extras["street_vendor"] = game._vendor.export_state()
	for child in game.get_children():
		if child.has_method("save_state") and child.has_method("load_state"):
			extras[str(child.name)] = child.save_state()
		elif child.has_method("export_state") and child.has_method("import_state"):
			extras[str(child.name)] = child.export_state()
	return {"world":_fields(game,WORLD_FIELDS),"items":items,"item_serial":inv._serial,"transactions":inv.transactions.duplicate(true),"events":inv.events.duplicate(true),"fabrics":inv.fabric_batches.duplicate(true),"threads":inv.materials.thread_batches.duplicate(true),"yarns":inv.materials.yarn_batches.duplicate(true),"remnants":inv.materials.remnants.duplicate(true),"jobs":inv.materials.jobs.duplicate(true),"material_serials":[inv.materials._job_serial,inv.materials._remnant_serial],"actors":actors,"layouts":layouts,"looms":looms,"catalog":{"entries":game._supply_catalog.entries.duplicate(true),"queue":game._supply_catalog.queue.duplicate(true),"random":game._supply_catalog.random_auto_enabled,"pools":game._supply_catalog.random_pools.duplicate(true),"entry_serial":game._supply_catalog._entry_serial,"job_serial":game._supply_catalog._job_serial},"production":{"auto":game._production.auto_restock,"target":game._production.auto_stock_target,"finished":game._production.finished_count,"fabric":game._production.selected_fabric,"thread":game._production.selected_thread,"style":game._production.selected_style},"dyes":game._dye.dyes.duplicate(),"mints":{"stock":game._mints.stock,"reserve":game._mints.reserve},"progression":state.snapshot(),"extras":extras}

static func _digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func write_snapshot(data: Dictionary, path: String) -> Dictionary:
	var payload := var_to_bytes(data)
	var envelope := {"version":VERSION,"checksum":_digest(payload),"payload":payload}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return {"ok":false,"message":"无法写入存档临时文件"}
	file.store_buffer(var_to_bytes(envelope))
	file.flush()
	file.close()
	var verification := read_snapshot(temporary)
	if not verification.ok: return verification
	if FileAccess.file_exists(path):
		if read_snapshot(path).ok:
			if DirAccess.copy_absolute(path,path+".bak") != OK: return {"ok":false,"message":"备份失败，原存档未更换"}
	var error := DirAccess.rename_absolute(temporary,path)
	if error != OK: return {"ok":false,"message":"替换存档失败，原存档仍保留"}
	return {"ok":true,"message":"已保存；上一份有效进度保留为备份"}

static func read_snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"message":"还没有存档"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 16000000: return {"ok":false,"message":"存档无法读取或大小异常"}
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 8 or (bytes.decode_u32(0) & 0xff) != TYPE_DICTIONARY:
		return {"ok":false,"message":"存档损坏，可尝试读取备份"}
	var envelope = bytes_to_var(bytes)
	if not envelope is Dictionary or envelope.get("version",-1) != VERSION or not envelope.get("payload") is PackedByteArray: return {"ok":false,"message":"存档格式或版本不兼容"}
	if _digest(envelope.payload) != str(envelope.get("checksum","")): return {"ok":false,"message":"存档校验失败，可尝试读取备份"}
	var data = bytes_to_var(envelope.payload)
	if not data is Dictionary: return {"ok":false,"message":"存档内容不完整"}
	return {"ok":true,"data":data,"message":"已读取存档"}

static func validate(data: Dictionary, game: Node) -> String:
	if not _safe_value(data): return "存档含非有限数值或不可恢复的数据类型"
	for key in ["world","catalog","production","progression","layouts","looms","extras","jobs","mints"]:
		if not data.get(key) is Dictionary: return "存档缺少 " + key
	for key in ["items","actors","fabrics","threads","yarns","remnants","transactions","events","dyes","material_serials"]:
		if not data.get(key) is Array: return "存档缺少 " + key
	for key in WORLD_FIELDS:
		if not data.world.has(key): return "营业数据不完整"
	if data.world._business_state != "workshop" or data.actors.size() != game.staff.size(): return "存档不是可恢复的闭店状态"
	if data.material_serials.size() != 2 or data.dyes.size() != 4: return "材料计数异常"
	if not data.get("item_serial") is int or data.item_serial < 0: return "商品计数异常"
	if not data.progression.get("day") is int or not data.progression.get("strategy_nodes") is Array: return "成长日期或经营节点不完整"
	for key in ["entries","queue"]:
		if not data.catalog.get(key) is Array: return "目录记录不完整"
	if not data.catalog.get("pools") is Dictionary or not data.catalog.get("random") is bool: return "目录设置异常"
	for key in ["entry_serial","job_serial"]:
		if not data.catalog.get(key) is int: return "目录计数异常"
	for key in ["auto","target","finished","fabric","thread","style"]:
		if not data.production.has(key): return "生产设置不完整"
	if not data.production.auto is bool or not data.production.target is int or not data.production.finished is int or not data.production.style is int or not data.production.fabric is String or not data.production.thread is String: return "生产设置类型异常"
	if data.production.style not in range(18) or data.production.target not in range(2,10): return "生产设置超出范围"
	for key in ["stock","reserve"]:
		if not data.mints.get(key) is int or data.mints[key] < 0: return "柜台补给记录异常"
	for key in ["_day_index","_money","_sales_count","_customer_serial","_electricity_paid"]:
		if not data.world[key] is int: return "经营数值类型异常"
	if data.world._day_index < 1: return "日期无效"
	for key in ["_day_minutes","_electricity_kwh","_electricity_cost","_daily_electricity_cost","_electricity_fraction"]:
		if not _number(data.world[key]) or data.world[key] < 0: return "经营数值无效"
	for key in ["_closing_sign_done","_workshop_time_started","_shift_departures_started"]:
		if not data.world[key] is bool: return "营业状态无效"
	if not data.world._room_lights is Dictionary: return "灯光状态无效"
	for key in ["knowledge","quiz","people","strategies","journals"]:
		if not data.progression.get(key) is Dictionary: return "成长记录不完整"
	if data.extras.has("street_vendor"):
		var vendor = data.extras.street_vendor
		if not vendor is Dictionary or not vendor.get("stock") is Dictionary or not vendor.get("receipts") is Array: return "摊位存档不完整"
		if vendor.get("phase","") not in ["away","arriving","trading","leaving"] or not _number(vendor.get("route_x")) or absf(vendor.route_x) > 24.0: return "摊位位置无效"
		for field in ["stock_day","day","receipt_serial"]:
			if not vendor.get(field) is int or vendor[field] < 0: return "摊位日期或计数无效"
		if not _number(vendor.get("minutes")): return "摊位时间无效"
		for goods in preload("res://scripts/street_vendor.gd").GOODS:
			if not vendor.stock.get(goods.id) is int or vendor.stock[goods.id] < 0 or vendor.stock[goods.id] > goods.stock: return "摊位库存无效"
		for receipt in vendor.receipts:
			if not receipt is Dictionary: return "采购存根无效"
			for field in ["day","cost"]:
				if not receipt.get(field) is int or receipt[field] < 0: return "采购存根数值无效"
			for field in ["id","offer","batch"]:
				if not receipt.get(field) is String: return "采购存根来源无效"
			if not _number(receipt.get("amount")) or receipt.amount <= 0: return "采购数量无效"
	for key in data.progression.people:
		var person = data.progression.people[key]
		if not person is Dictionary or not person.get("name") is String or not _number(person.get("craft")) or not _number(person.get("service")) or not person.get("learned") is Array: return "个人技能记录无效"
		for learned in person.learned:
			if not preload("res://scripts/progression_state.gd").SKILLS.has(learned): return "未知个人技能"
	for key in data.progression.strategies:
		var strategy = data.progression.strategies[key]
		if not preload("res://scripts/progression_state.gd").STRATEGIES.has(key) or not strategy is Dictionary or not strategy.get("active") is bool or not strategy.get("paid_day") is int: return "经营策略记录无效"
	for key in data.progression.strategy_nodes:
		if not preload("res://scripts/progression_state.gd").STRATEGY_NODES.has(key): return "未知经营节点"
	for key in data.progression.journals:
		var journal = data.progression.journals[key]
		if not journal is Dictionary: return "日账无效"
		for field in ["day","opening_cash","closing_cash","sales","sold","crafted","electricity","other_cash"]:
			if not journal.get(field) is int: return "日账数值不完整"
		if not journal.get("closed") is bool or not journal.get("expenses") is Array: return "日账记录不完整"
	for key in data.progression.quiz:
		var answer = data.progression.quiz[key]
		if not answer is Dictionary or not answer.get("answer") is int or not answer.get("correct") is bool or not answer.get("day") is int: return "竞答记录无效"
	var ids := {}
	for item in data.items:
		if not item is Dictionary or not item.get("definition") is Dictionary: return "商品记录异常"
		var id := str(item.get("id",""))
		if id.is_empty() or ids.has(id): return "商品 ID 重复或丢失"
		ids[id] = true
		for field in ["owner","location"]:
			if not item.get(field) is String: return "商品归属无效"
		if not item.get("paid") is bool or not item.get("tried") is bool or not item.get("metadata") is Dictionary or not item.get("slot") is int: return "商品状态不完整"
		var template = preload("res://scripts/garment_definition.gd").new()
		if not _matches_schema(item.definition,_resource_data(template)): return "商品定义字段不完整"
		if int(item.definition.get("outfit_style",-1)) not in range(18): return "商品款式无效"
		if item.get("location","") not in ["rack","storage","basket","accessory","collected"]: return "商品位置无效"
		if item.location == "rack" and int(item.get("slot",-1)) not in range(9): return "陈列位置无效"
	for key in data.layouts:
		if not game.has_node(key) or not data.layouts[key] is Transform3D: return "家具布局与当前版本不匹配"
	for key in data.looms:
		if not game.has_node(key): return "织机布局不匹配"
		if not data.looms[key] is Dictionary or not _matches_schema(data.looms[key],_fields(game.get_node(key),LOOM_FIELDS)): return "织机状态不完整"
	for actor in data.actors:
		if not actor is Dictionary or not actor.get("fields") is Dictionary or not actor.get("transform") is Transform3D: return "人物记录异常"
		for key in ACTOR_FIELDS:
			if not actor.fields.has(key): return "人物记录不完整"
		if not actor.get("visible") is bool or not _matches_schema(actor.fields,_fields(game.staff[0],ACTOR_FIELDS)): return "人物记录类型无效"
	for collection in [data.fabrics,data.threads,data.yarns]:
		var batch_ids := {}
		for batch in collection:
			if not batch is Dictionary or not batch.get("id") is String or not _number(batch.get("meters")) or batch.meters < 0 or batch_ids.has(batch.id): return "材料批次无效或重复"
			batch_ids[batch.id] = true
	for transaction in data.transactions:
		if not transaction is Dictionary or not transaction.get("price") is int: return "交易记录无效"
	for event in data.events:
		if not event is Dictionary or not event.get("event") is String: return "物品事件无效"
	for job in data.catalog.queue:
		if not job is Dictionary or job.get("state","") not in ["completed","cancelled"]: return "存档含未完成队列"
	for entry in data.catalog.entries:
		if not entry is Dictionary or game._supply_catalog._validated_entry(entry).is_empty(): return "目录配方无效"
	return ""

static func _number(value: Variant) -> bool:
	return value is int or value is float

static func _safe_value(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Transform3D: return value.origin.is_finite() and value.basis.is_finite()
	if value is Vector3: return value.is_finite()
	if value is Vector2: return value.is_finite()
	if value is Color: return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
	if value is Dictionary:
		for key in value:
			if not _safe_value(key) or not _safe_value(value[key]): return false
		return true
	if value is Array:
		for entry in value:
			if not _safe_value(entry): return false
		return true
	return value == null or value is String or value is StringName or value is int or value is bool

static func _matches_schema(data: Dictionary, schema: Dictionary) -> bool:
	if schema.has("curve_points"):
		if not data.get("curve_points") is Array: return false
		for point in data.curve_points:
			if not point is Array or point.size() != 5: return false
			if not point[0] is Vector2 or not _number(point[1]) or not _number(point[2]) or point[3] not in [0,1] or point[4] not in [0,1]: return false
	for key in schema:
		if not data.has(key): return false
		if typeof(data[key]) != typeof(schema[key]) and not (_number(data[key]) and _number(schema[key])): return false
		if schema[key] is Dictionary and schema[key].has("nested_resource"):
			if not data[key].get("nested_resource") is Dictionary or not _matches_schema(data[key].nested_resource,schema[key].nested_resource): return false
	return true

static func save_game(game: Node, state: Node, path := DEFAULT_PATH) -> Dictionary:
	var reason := stable_reason(game)
	if not reason.is_empty(): return {"ok":false,"message":reason}
	var data := capture(game,state)
	reason = validate(data,game)
	if not reason.is_empty(): return {"ok":false,"message":reason}
	return write_snapshot(data,path)

static func load_game(game: Node, state: Node, path := DEFAULT_PATH, replace_current := false) -> Dictionary:
	var loaded := read_snapshot(path)
	if not loaded.ok: return loaded
	var reason := validate(loaded.data,game)
	if not reason.is_empty(): return {"ok":false,"message":reason}
	if not stable_reason(game).is_empty():
		if not replace_current: return {"ok":false,"confirm":true,"message":"当前还有未保存的经营进度。再次点击读取，将舍弃当前进度并重新载入存档。"}
		pending_snapshot = loaded.data
		var error := game.get_tree().reload_current_scene()
		if error != OK:
			pending_snapshot = {}
			return {"ok":false,"message":"重新载入场景失败；当前游戏未恢复"}
		return {"ok":true,"message":"正在重新载入存档…"}
	restore(game,state,loaded.data)
	return {"ok":true,"message":"已恢复闭店进度；可继续下一天"}

static func restore(game: Node, state: Node, data: Dictionary) -> void:
	game._speed = 0.0
	for actor in game.staff:
		game._set_staff_idle(actor,100000.0)
	for key in data.world: game.set(key,data.world[key])
	for path in data.layouts: game.get_node(path).transform = data.layouts[path]
	for room in game._rooms.values(): room.refresh_navigation(true)
	game._navigation.revision += 1
	var inv = game._inventory
	for item in inv.items:
		if item.display_mount != null and is_instance_valid(item.display_mount.get_ref()) and item.display_mount.get_ref().get_meta("physical_storage_mount",false): item.display_mount.get_ref().free()
		item.free()
	inv.items.clear()
	for i in inv.slots.size(): inv.slots[i] = []
	inv.produced_orders.clear()
	inv._serial = int(data.item_serial)
	for entry in data.items:
		var item = preload("res://scripts/garment_item.gd").new()
		item.item_id = str(entry.id)
		item.name = item.item_id
		item.definition = preload("res://scripts/garment_definition.gd").create(int(entry.definition.outfit_style),int(entry.definition.palette_index))
		_apply_resource(item.definition,entry.definition)
		inv.add_child(item)
		item.build()
		inv.items.append(item)
		item.owner_id = entry.owner
		item.paid = entry.paid
		item.tried_on = entry.tried
		for key in entry.metadata: item.set_meta(key,entry.metadata[key])
		if item.has_meta("work_order_id"): inv.produced_orders[item.get_meta("work_order_id")] = item
		match entry.location:
			"rack": inv._place_on_slot(item,int(entry.slot))
			"collected": item.collect()
			"basket": item.place("basket",inv._basket_transform(item))
			_: inv._store(item)
	inv.transactions.assign(data.transactions)
	inv.events.assign(data.events)
	inv.fabric_batches.assign(data.fabrics)
	inv.materials.bind_fabrics(inv.fabric_batches)
	inv.materials.thread_batches.assign(data.threads)
	inv.materials.yarn_batches.assign(data.yarns)
	inv.materials.remnants.assign(data.remnants)
	inv.materials.jobs = data.jobs.duplicate(true)
	inv.materials._job_serial = int(data.material_serials[0])
	inv.materials._remnant_serial = int(data.material_serials[1])
	for package in game._production.packages.values():
		if is_instance_valid(package): package.free()
	game._production.packages.clear()
	game._production.mounts.clear()
	for remnant in game._production._remnant_nodes.values():
		if is_instance_valid(remnant): remnant.free()
	game._production._remnant_nodes.clear()
	game._production.order = {}
	game._production.sync_stock()
	for path in data.looms:
		var loom = game.get_node(path)
		loom.stop()
		for key in data.looms[path]: loom.set(key,data.looms[path][key])
		for mount in loom.output_mounts: mount.free()
		loom.output_mounts.clear()
		for batch in inv.fabric_batches:
			if str(batch.get("source","")) == "loom": loom._register_output(batch)
		loom._update_geometry()
	for i in game.staff.size():
		var actor = game.staff[i]
		for key in data.actors[i].fields: actor.set(key,data.actors[i].fields[key])
		actor._build_appearance()
		actor.transform = data.actors[i].transform
		actor.visible = data.actors[i].visible
		actor.set_meta("shift_home",false)
		actor.set_meta("shift_departing",false)
		actor.set_meta("shift_home_pending",false)
	var cat = game._supply_catalog
	cat.entries.assign(data.catalog.entries)
	cat.queue.assign(data.catalog.queue)
	cat.random_auto_enabled = bool(data.catalog.random)
	cat.random_pools = data.catalog.pools.duplicate(true)
	cat._entry_serial = int(data.catalog.entry_serial)
	cat._job_serial = int(data.catalog.job_serial)
	cat._entries_rev += 1
	game._production.auto_restock = data.production.auto
	game._production.auto_stock_target = data.production.target
	game._production.finished_count = data.production.finished
	game._production.selected_fabric = data.production.fabric
	game._production.selected_thread = data.production.thread
	game._production.selected_style = data.production.style
	game._dye.dyes = data.dyes.duplicate()
	game._mints.stock = data.mints.stock
	game._mints.reserve = data.mints.reserve
	for name in data.extras:
		var child = game.get_node_or_null(name)
		if child != null and child.has_method("load_state"): child.load_state(data.extras[name])
		elif child != null and child.has_method("import_state"): child.import_state(data.extras[name])
	state.restore(data.progression)
	if data.extras.has("street_vendor") and is_instance_valid(game.get("_vendor")):
		game._vendor.import_state(data.extras.street_vendor)
	game._refresh_facilities()
	inv.advance()
	game._street.set_shop_open(false)
