extends SceneTree
class Shopper extends Node:
	var customer_id := "price_test_customer"

func _initialize() -> void:
	var inventory = load("res://scripts/shop_inventory.gd").new()
	var item = load("res://scripts/garment_item.gd").new()
	item.definition = load("res://scripts/garment_definition.gd").create(0,0)
	item.item_id = "price_test_item"
	item.location = "rack"
	inventory.items.append(item)
	var customer := Shopper.new()
	var profile = load("res://scripts/customer_profile.gd").new()
	profile.wanted_styles = [0]
	profile.budget = 44
	profile.max_pieces = 1
	inventory.price_policy = func(base: int) -> int: return roundi(base * .9)
	var selection: Dictionary = inventory.choose_for(customer,profile)
	assert(selection.item == item, "Discounted price must participate in budget choice")
	assert(inventory.sale_price(item) == 43)
	inventory.price_policy = func(base: int) -> int: return base
	assert(inventory.sale_price(item) == 43, "Reserved quote cannot rise mid-service")
	item.location = "carried"
	inventory.service_authorizer = func() -> bool: return true
	assert(inventory.checkout(item,customer) == 43, "Cashier charges the quoted amount")
	assert(inventory.checkout(item,customer) == 0, "Settlement is idempotent")
	assert(inventory.transactions.size() == 1 and inventory.transactions[0].price == 43)
	item.reserved_by = ""
	assert(inventory.sale_price(item) == 48, "An unreserved item uses current policy")
	item.free()
	customer.free()
	inventory.free()
	print("STRATEGY PRICING: 7 checks passed")
	quit()
