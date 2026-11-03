extends RefCounted

## Bounded opening-stock extension catalog.
## extend_opening_stock() appends the workshop's extended fabric books, rolls
## and thread spools onto the existing opening ledger (fabric indices 0..4,
## four thread spools) and returns the matching wool yarn skein stock.
## Every record is a real ledger quantity; appends are idempotent by id lookup
## so repeated calls never duplicate stock.

const BOOK_COUNT := 13
const ROLL_COUNT := 3
const THREAD_COUNT := 16
const YARN_GROUPS := 6
const YARN_PER_GROUP := 3


static func extend_opening_stock(fabrics: Array[Dictionary], threads: Array[Dictionary]) -> Array[Dictionary]:
	var existing := {}
	for record in fabrics:
		existing[String(record.get("id", ""))] = true
	for record in threads:
		existing[String(record.get("id", ""))] = true
	for record in _fabric_records():
		if existing.has(record.id):
			continue
		existing[record.id] = true
		record["index"] = fabrics.size()
		fabrics.append(record)
	for record in _thread_records():
		if existing.has(record.id):
			continue
		existing[record.id] = true
		threads.append(record)
	return _yarn_records()


static func _fabric_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	# Books: indices 5..17 once appended. Plain/stripe/check cycle, soft
	# coordinated hues across rose rust ochre cream sage teal blue lavender.
	var books := [
		["stock_rose_plain", "烟粉素棉布", "plain", 0, "c98a94", "cotton", 5.0],
		["stock_rose_stripe", "绯粉条纹棉布", "stripe", 1, "d9a7ae", "cotton", 6.5],
		["stock_rust_check", "锈红格纹棉布", "check", 2, "b96b4f", "cotton", 5.5],
		["stock_rust_plain", "砖红素亚麻", "plain", 0, "c47e5e", "linen", 7.0],
		["stock_ochre_stripe", "赭石条纹棉布", "stripe", 1, "c9a05c", "cotton", 4.5],
		["stock_ochre_check", "麦芽格纹亚麻", "check", 2, "d4b47a", "linen", 6.0],
		["stock_cream_plain", "月白素棉布", "plain", 0, "ece3d0", "cotton", 7.5],
		["stock_cream_stripe", "米色条纹亚麻", "stripe", 1, "e3d9c2", "linen", 5.0],
		["stock_sage_check", "灰绿格纹棉布", "check", 2, "9aab8f", "cotton", 6.5],
		["stock_sage_plain", "豆绿素亚麻", "plain", 0, "b3bfa4", "linen", 5.5],
		["stock_teal_stripe", "青碧条纹棉布", "stripe", 1, "6f9a94", "cotton", 7.0],
		["stock_blue_check", "雾蓝格纹亚麻", "check", 2, "7f9db5", "linen", 5.0],
		["stock_lavender_plain", "浅紫素棉布", "plain", 0, "a394bd", "cotton", 7.5],
	]
	for entry in books:
		records.append({
			"id": entry[0],
			"name": entry[1],
			"meters": entry[6],
			"capacity_m": 8.0,
			"pattern": entry[2],
			"pattern_code": entry[3],
			"pigment": Color(entry[4]),
			"material": entry[5],
			"width_m": 1.4,
			"thickness_m": 0.001,
			"form": "book",
			"location": "storage",
			"source": "opening",
		})
	# Rolls: indices 18..20 once appended.
	var rolls := [
		["stock_teal_roll", "湖青格纹布卷", "check", 2, "88aca6", "cotton", 9.0],
		["stock_blue_roll", "天蓝素布卷", "plain", 0, "9ab3c6", "linen", 10.5],
		["stock_lavender_roll", "藕荷条纹布卷", "stripe", 1, "b8aacd", "cotton", 11.0],
	]
	for entry in rolls:
		records.append({
			"id": entry[0],
			"name": entry[1],
			"meters": entry[6],
			"capacity_m": 12.0,
			"pattern": entry[2],
			"pattern_code": entry[3],
			"pigment": Color(entry[4]),
			"material": entry[5],
			"width_m": 1.4,
			"thickness_m": 0.001,
			"form": "roll",
			"location": "storage",
			"source": "opening",
		})
	return records


static func _thread_records() -> Array[Dictionary]:
	var spools := [
		["thread_stock_rose", "烟粉棉线", "c98a94", 62.0],
		["thread_stock_rose_light", "绯粉棉线", "d9a7ae", 74.0],
		["thread_stock_rust", "锈红棉线", "b96b4f", 58.0],
		["thread_stock_brick", "砖红棉线", "c47e5e", 66.0],
		["thread_stock_ochre", "赭石棉线", "c9a05c", 70.0],
		["thread_stock_malt", "麦芽棉线", "d4b47a", 55.0],
		["thread_stock_moon", "月白棉线", "ece3d0", 80.0],
		["thread_stock_beige", "米色棉线", "e3d9c2", 60.0],
		["thread_stock_sage_gray", "灰绿棉线", "9aab8f", 68.0],
		["thread_stock_bean", "豆绿棉线", "b3bfa4", 76.0],
		["thread_stock_teal", "青碧棉线", "6f9a94", 57.0],
		["thread_stock_lake", "湖青棉线", "88aca6", 72.0],
		["thread_stock_mist_blue", "雾蓝棉线", "7f9db5", 63.0],
		["thread_stock_sky", "天蓝棉线", "9ab3c6", 78.0],
		["thread_stock_lavender", "浅紫棉线", "a394bd", 59.0],
		["thread_stock_lotus", "藕荷棉线", "b8aacd", 71.0],
	]
	var records: Array[Dictionary] = []
	for entry in spools:
		records.append({
			"id": entry[0],
			"name": entry[1],
			"meters": entry[3],
			"capacity_m": 80.0,
			"pigment": Color(entry[2]),
			"material": "cotton",
			"form": "spool",
			"location": "storage",
			"source": "opening",
		})
	return records


# Six color groups of three matching skeins each; ids yarn_00..yarn_17.
static func _yarn_records() -> Array[Dictionary]:
	var groups := [
		["烟粉", "c98a94", 85.0],
		["锈红", "b96b4f", 80.0],
		["灰绿", "9aab8f", 90.0],
		["青碧", "6f9a94", 75.0],
		["雾蓝", "7f9db5", 88.0],
		["浅紫", "a394bd", 82.0],
	]
	var records: Array[Dictionary] = []
	for group in YARN_GROUPS:
		var label: String = groups[group][0]
		var pigment := Color(groups[group][1])
		var base: float = groups[group][2]
		for skein in YARN_PER_GROUP:
			records.append({
				"id": "yarn_%02d" % records.size(),
				"name": "%s羊毛线%d" % [label, skein + 1],
				"meters": minf(base + skein * 5.0, 100.0),
				"capacity_m": 100.0,
				"pigment": pigment,
				"material": "wool",
				"form": "yarn",
				"location": "storage",
				"source": "opening",
			})
	return records
