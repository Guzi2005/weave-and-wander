extends SceneTree
var errors: Array[String] = []
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)
func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for person in game.staff: game._set_staff_idle(person,100000)
	var flow: Node3D = game._production
	var ledger: RefCounted = flow.ledger
	check(flow.packages.size() == 59,"Expected 21 fabric packages, 20 spools, 18 yarn balls")
	var all_records: Array = ledger.fabric_batches+ledger.thread_batches+ledger.yarn_batches
	var ids := {}
	for record in all_records:
		check(not ids.has(record.id),"Duplicated material identity")
		ids[record.id] = true
		check(flow.packages.has(record.id),"Stock has no physical package: "+str(record.id))
		check(is_equal_approx(flow.packages[record.id].quantity,record.meters),"Visible quantity differs from stock")
	for row in [flow.cabinet.LOWER_BOOKS,flow.cabinet.UPPER_BOOKS]:
		var right := -INF
		for index in row:
			var record: Dictionary = ledger.fabric_batches[index]
			var node: Node3D = flow.packages[record.id]
			var box: AABB = flow.cabinet.global_transform.affine_inverse()*node.global_transform*node.display_bounds()
			check(box.position.x >= right-.002,"Adjacent fabric books overlap")
			check(box.end.x <= .405,"Fabric overflows its compartment")
			right = box.end.x
	var id: String = ledger.fabric_batches[0].id
	var package: Node3D = flow.packages[id]
	var instance_id := package.get_instance_id()
	var initial: float = package.shell.mesh.get_aabb().size.x
	ledger.fabric(id).meters = 2.0
	flow.sync_stock()
	flow.cabinet.arrange_fabrics(flow.packages,flow.mounts)
	check(package.shell.mesh.get_aabb().size.x < initial,"Low stock did not thin")
	check(package.get_instance_id() == instance_id,"Quantity update replaced the physical stock")
	var before: Vector3 = package.global_position
	flow.cabinet.position.x += .25
	check(package.global_position.distance_to(before+Vector3(.25,0,0)) < .001,"Moving cabinet detached stored materials")
	var yarn: Dictionary = ledger.yarn_batches[0]
	var ball: Node3D = flow.packages[yarn.id]
	var radius: float = ball.shell.mesh.radius
	yarn.meters *= .125
	flow.sync_stock()
	check(is_equal_approx(ball.shell.mesh.radius,radius*.5),"Yarn quantity no longer controls volume")
	var catalog = load("res://scripts/material_catalog.gd")
	catalog.extend_opening_stock(ledger.fabric_batches,ledger.thread_batches)
	check(ledger.fabric_batches.size() == 21 and ledger.thread_batches.size() == 20,"Opening stock duplicated")
	var exact = load("res://scripts/material_ledger.gd").new()
	var stock: Array[Dictionary] = [{"id":"test","meters":8.0,"pattern":"check","palette":2}]
	exact.bind_fabrics(stock)
	exact.thread_batches[0].meters = 12.0
	var job: Dictionary = exact.reserve("test","thread_blue")
	check(is_equal_approx(job.estimate.cut_m,job.estimate.net_m+job.estimate.remnant_m+job.estimate.waste_m),"Pattern allowance breaks conservation")
	check(exact.cut(job.id),"Exact-thread test could not cut")
	for step in 225: check(exact.advance_sewing(job.id,float(step+1)/225.0),"Exactly sufficient thread stalled")
	check(exact.thread("thread_blue").meters < .000001,"Exact thread did not exhaust")
	print("MATERIAL_STORAGE_TEST packages=",flow.packages.size()," failures=",errors.size())
	game.free()
	quit(0 if errors.is_empty() else 1)
