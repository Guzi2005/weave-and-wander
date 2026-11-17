extends Node
## Persistent player progression. Observes committed game events, never invents sales.
signal changed

const ISSUE_ID := "workshop_01"
const SKILLS := {
	"steady_hands": {"name":"稳稳下针", "track":"craft", "xp":20.0, "cost":25, "requires":"", "description":"缝制与裁剪动作效率 +10%"},
	"batch_craft": {"name":"熟练工序", "track":"craft", "xp":70.0, "cost":60, "requires":"steady_hands", "description":"缝制与裁剪动作效率再 +15%"},
	"warm_service": {"name":"从容交付", "track":"service", "xp":15.0, "cost":20, "requires":"", "description":"收银与打包动作效率 +10%"},
	"careful_packing": {"name":"熟悉柜台", "track":"service", "xp":60.0, "cost":50, "requires":"warm_service", "description":"收银与打包动作效率再 +15%"},
}
const STRATEGIES := {
	"atelier": {"name":"手作工坊", "cost":90, "daily":18, "description":"投入工序组织：制作动作加快 20%，每日支出 18。资金同时也要留给材料。"},
	"neighborhood": {"name":"邻里服务", "cost":75, "daily":12, "description":"投入柜台服务：收银打包加快 20%，每日支出 12。可与手作工坊同时经营。"},
}
const STRATEGY_NODES := {
	"batch_orders":{"branch":"atelier","name":"小批量订单簿","cost":45,"description":"按已保存配方一次安排三件，由真实员工与材料完成。"},
	"neighbor_discount":{"branch":"neighborhood","name":"邻里九折日","cost":35,"description":"营业中的邻里服务统一九折；顾客预算与实际收款使用同一价格。"},
}
var game: Node
var knowledge: Dictionary = {}
var quiz_answers: Dictionary = {}
var people: Dictionary = {}
var strategies: Dictionary = {}
var strategy_nodes: Array = []
var journals: Dictionary = {}
var _day := 1
var _transaction_cursor := 0
var _event_cursor := 0
var _cash_last := 0
var _electricity_last := 0

func setup(controller: Node) -> void:
	game = controller
	_day = game._day_index
	_transaction_cursor = game._inventory.transactions.size()
	_event_cursor = game._inventory.events.size()
	_cash_last = game._money
	_electricity_last = game._electricity_paid
	_ensure_day(_day)
	for i in game.staff.size():
		game.staff[i].set_meta("progression_id", "staff_%d" % i)
		_person(game.staff[i])
	if not preload("res://scripts/game_save.gd").pending_snapshot.is_empty():
		_restore_pending.call_deferred()

func _restore_pending() -> void:
	var save = preload("res://scripts/game_save.gd")
	var snapshot: Dictionary = save.pending_snapshot
	save.pending_snapshot = {}
	for customer in game.customers.duplicate(): game._complete_customer(customer)
	save.restore(game,self,snapshot)
	game._show_toast("已恢复存档，当前为闭店工坊时间")

func _ensure_day(day: int) -> Dictionary:
	var key := str(day)
	if not journals.has(key):
		journals[key] = {"day":day,"opening_cash":game._money,"closing_cash":game._money,"sales":0,"sold":0,"crafted":0,"electricity":0,"other_cash":0,"expenses":[],"closed":false}
	return journals[key]

func _person(actor: Node) -> Dictionary:
	var key := str(actor.get_meta("progression_id", actor.name))
	if not people.has(key):
		people[key] = {"name":actor.doll_name,"craft":0.0,"service":0.0,"learned":[]}
	return people[key]

func tick(delta: float) -> void:
	if game == null: return
	if _day != game._day_index:
		_ensure_day(_day).closed = true
		_day = game._day_index
		_ensure_day(_day)
		_electricity_last = 0
		for key in strategies:
			if strategies[key].active:
				var fee := int(STRATEGIES[key].daily)
				if game._money >= fee:
					game._money -= fee
					strategies[key].paid_day = game._day_index
					_ensure_day(_day).expenses.append({"label":STRATEGIES[key].name,"amount":fee})
				else:
					strategies[key].active = false
					game._show_toast(STRATEGIES[key].name + "：余额不足，业务暂歇")
	var day: Dictionary = _ensure_day(_day)
	day["purchases"] = 0
	if is_instance_valid(game.get("_vendor")):
		for receipt in game._vendor.receipts:
			if int(receipt.day) == _day: day.purchases += int(receipt.cost)
	var new_sales := 0
	while _transaction_cursor < game._inventory.transactions.size():
		var transaction: Dictionary = game._inventory.transactions[_transaction_cursor]
		new_sales += int(transaction.price)
		day.sold += 1
		_transaction_cursor += 1
	day.sales += new_sales
	while _event_cursor < game._inventory.events.size():
		var event: Dictionary = game._inventory.events[_event_cursor]
		if event.event in ["crafted","sewn"]: day.crafted += 1
		_event_cursor += 1
	var electricity := maxi(0, int(game._electricity_paid) - _electricity_last)
	day.electricity += electricity
	day.other_cash += int(game._money) - _cash_last - new_sales + electricity
	day.closing_cash = game._money
	day.closed = game._business_state == "workshop"
	_cash_last = game._money
	_electricity_last = game._electricity_paid
	if delta > 0.0:
		for actor in game.staff:
			var job: Dictionary = game._staff_jobs.get(actor.get_instance_id(), {})
			if not actor.has_arrived() or job.get("phase","") not in ["work","production","dyeing"]: continue
			var person: Dictionary = _person(actor)
			if actor == game._production.actor and game._production.phase in ["cut","sew"]:
				person.craft += delta
			elif game._shop.checkout_exchange.active and job.get("facility",-1) == game._facility_index("counter","shop"):
				person.service += delta

func answer_quiz(answer: int) -> Dictionary:
	if answer < 0 or answer > 2: return {"ok":false,"message":"请选择一个答案"}
	if quiz_answers.has(ISSUE_ID): return {"ok":false,"message":"本期已经作答；知识与结果已记在册中"}
	var correct := answer == 1
	quiz_answers[ISSUE_ID] = {"answer":answer,"correct":correct,"day":game._day_index}
	knowledge["material_identity"] = true
	if correct: game._money += 20
	tick(0)
	changed.emit()
	return {"ok":true,"correct":correct,"message":"答对了，获得 20 枚工坊奖励。" if correct else "已记下本期知识；本次没有奖金。"}

func learn_skill(person_id: String, key: String) -> Dictionary:
	if not people.has(person_id) or not SKILLS.has(key): return {"ok":false,"message":"未找到角色或技能"}
	var person: Dictionary = people[person_id]
	var spec: Dictionary = SKILLS[key]
	if key in person.learned: return {"ok":false,"message":"已经掌握"}
	if not str(spec.requires).is_empty() and spec.requires not in person.learned: return {"ok":false,"message":"先掌握前置技能"}
	if float(person[spec.track]) < float(spec.xp): return {"ok":false,"message":"还需要实际工作经验"}
	if game._money < int(spec.cost): return {"ok":false,"message":"培训预算不足"}
	game._money -= int(spec.cost)
	person.learned.append(key)
	tick(0)
	changed.emit()
	return {"ok":true,"message":person.name + "掌握了“" + spec.name + "”"}

func toggle_strategy(key: String) -> Dictionary:
	if not STRATEGIES.has(key): return {"ok":false,"message":"未知经营方向"}
	if not strategies.has(key):
		var cost := int(STRATEGIES[key].cost) + int(STRATEGIES[key].daily)
		if game._money < cost: return {"ok":false,"message":"需要解锁费与首日运营预算，共 %d" % cost}
		game._money -= cost
		strategies[key] = {"active":true,"paid_day":game._day_index}
	elif bool(strategies[key].active):
		strategies[key].active = false
	else:
		if int(strategies[key].paid_day) != game._day_index:
			var fee := int(STRATEGIES[key].daily)
			if game._money < fee: return {"ok":false,"message":"当日运营预算不足"}
			game._money -= fee
			strategies[key].paid_day = game._day_index
		strategies[key].active = true
	tick(0)
	changed.emit()
	return {"ok":true,"message":"经营方针已更新；已学知识和技能保留"}

func unlock_strategy_node(key: String) -> Dictionary:
	if not STRATEGY_NODES.has(key): return {"ok":false,"message":"未知经营节点"}
	if key in strategy_nodes: return {"ok":false,"message":"已经解锁"}
	var spec: Dictionary = STRATEGY_NODES[key]
	if not strategies.has(spec.branch): return {"ok":false,"message":"先开辟对应业务"}
	if game._money < int(spec.cost): return {"ok":false,"message":"投入预算不足"}
	game._money -= int(spec.cost)
	strategy_nodes.append(key)
	tick(0)
	changed.emit()
	return {"ok":true,"message":spec.name + "已解锁"}

func enqueue_batch(entry_id: String) -> Dictionary:
	if "batch_orders" not in strategy_nodes or not strategies.get("atelier",{}).get("active",false): return {"ok":false,"message":"先启用手作工坊并解锁小批量订单簿"}
	if game._supply_catalog.find_entry(entry_id).is_empty(): return {"ok":false,"message":"请先在制作面板保存一份配方"}
	for i in 3: game._supply_catalog.enqueue_manual(entry_id)
	return {"ok":true,"message":"三件订单已排入生产队列；缺料时等待，不凭空产出"}

func sale_price(base: int) -> int:
	return maxi(1,roundi(base*.9)) if "neighbor_discount" in strategy_nodes and strategies.get("neighborhood",{}).get("active",false) else base

func production_multiplier(actor: Node) -> float:
	if actor == null or game._production.phase not in ["cut","sew"]: return 1.0
	var learned: Array = _person(actor).learned
	return 1.0 + (.10 if "steady_hands" in learned else 0.0) + (.15 if "batch_craft" in learned else 0.0) + (.20 if strategies.get("atelier",{}).get("active",false) else 0.0)

func service_multiplier(actor: Node) -> float:
	if actor == null: return 1.0
	var learned: Array = _person(actor).learned
	return 1.0 + (.10 if "warm_service" in learned else 0.0) + (.15 if "careful_packing" in learned else 0.0) + (.20 if strategies.get("neighborhood",{}).get("active",false) else 0.0)

func snapshot() -> Dictionary:
	tick(0)
	return {"knowledge":knowledge.duplicate(true),"quiz":quiz_answers.duplicate(true),"people":people.duplicate(true),"strategies":strategies.duplicate(true),"strategy_nodes":strategy_nodes.duplicate(),"journals":journals.duplicate(true),"day":_day}

func restore(data: Dictionary) -> void:
	knowledge = data.knowledge.duplicate(true)
	quiz_answers = data.quiz.duplicate(true)
	people = data.people.duplicate(true)
	strategies = data.strategies.duplicate(true)
	strategy_nodes = data.get("strategy_nodes",[]).duplicate()
	journals = data.journals.duplicate(true)
	_day = int(data.day)
	_transaction_cursor = game._inventory.transactions.size()
	_event_cursor = game._inventory.events.size()
	_cash_last = game._money
	_electricity_last = game._electricity_paid
	changed.emit()
