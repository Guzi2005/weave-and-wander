extends SceneTree
class FakeInventory extends Node:
	var materials = preload("res://scripts/material_ledger.gd").new()
class FakeGame extends Node:
	var _money := 100
	var _inventory: Node
var count := 0
func check(value: bool, why: String) -> void:
	count += 1
	if not value:
		push_error(why)
		quit(1)
func _initialize() -> void:
	var game := FakeGame.new()
	game._inventory = FakeInventory.new()
	game._inventory.materials.fabric_batches.append({"id":"opening_cloth","meters":0.0,"capacity_m":8.0})
	var vendor := preload("res://scripts/street_vendor.gd").new()
	vendor.setup(game)
	vendor.tick(0,1,479)
	check(vendor.stock_day == 0 and vendor.phase == "away","must not refresh before morning")
	vendor.tick(0,1,480)
	check(vendor.phase == "arriving" and vendor.stock.cotton == 5,"morning refresh and arrival")
	check(not vendor.purchase("cotton").ok,"no sale while pulling cart")
	vendor.tick(20,1,500)
	check(vendor.is_trading(),"arrival route completes")
	var result: Dictionary = vendor.purchase("cotton",2)
	check(result.ok and game._money == 64,"purchase debits once")
	check(is_equal_approx(float(game._inventory.materials.fabric("opening_cloth").meters),4.0),"actual fabric refilled")
	check(vendor.stock.cotton == 3,"stock decremented")
	vendor.tick(0,1,700)
	check(vendor.stock.cotton == 3,"repeat tick cannot restock")
	check(not vendor.purchase("cotton",4).ok and game._money == 64,"oversell must not debit")
	check(not vendor.purchase("cotton",-1).ok,"invalid quantity rejected")
	game._money = 0
	check(not vendor.purchase("cotton").ok and vendor.stock.cotton == 3,"budget guard")
	var saved: Dictionary = vendor.export_state()
	var restored := preload("res://scripts/street_vendor.gd").new()
	restored.setup(game)
	check(restored.import_state(saved),"snapshot restore")
	check(restored.stock.cotton == 3 and restored.is_trading(),"restore does not refresh")
	var bad := saved.duplicate(true)
	bad.stock.cotton = 500
	check(not restored.import_state(bad) and restored.stock.cotton == 3,"invalid stock rejected without mutation")
	restored.tick(1,1,1080)
	check(restored.phase == "leaving" and not restored.is_trading(),"sunset closes purchases")
	var previous: float = restored.route_x
	restored.tick(0,1,1080)
	check(restored.route_x == previous,"pause freezes route")
	restored.tick(30,1,1080)
	check(restored.phase == "away","walk fully off stage")
	restored.tick(0,2,0)
	check(restored.stock.cotton == 3,"midnight does not refresh")
	restored.tick(0,2,480)
	check(restored.stock.cotton == 5 and restored.phase == "arriving","next morning refresh once")
	restored.tick(20,2,600)
	restored.tick(1,2,1080)
	restored.tick(0,3,540)
	check(restored.phase == "arriving" and restored.route_x == -24.0,"next day handles unfinished prior departure")
	restored.free()
	vendor.free()
	game._inventory.free()
	game.free()
	print("VENDOR STATE: ",count," checks passed")
	quit()
