extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message):
		failures.append(message)
		push_error(message)


func _hanging_depth(item: Node3D) -> float:
	var part: MeshInstance3D = item.parts[0]
	var base: PackedVector3Array = part.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var hanging: PackedVector3Array = part.mesh.surface_get_blend_shape_arrays(0)[0][Mesh.ARRAY_VERTEX]
	for index in base.size():
		if absf(base[index].z) > 0.02:
			return hanging[index].z / base[index].z
	return 0.0


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var dress: Node3D
	var shirt: Node3D
	var trousers: Node3D
	for item in game._inventory.items:
		if dress == null and item.definition.outfit_style == 0:
			dress = item
		if shirt == null and item.definition.outfit_style == 3:
			shirt = item
		if trousers == null and item.definition.outfit_style == 4:
			trousers = item
	_check(dress != null and dress.location == "rack" and dress.presentation == "Hanging", "Opening dress is not hanging")
	_check(shirt != null and shirt.presentation == "Hanging", "Opening shirt is not hanging")
	_check(trousers != null and trousers.presentation == "Hanging", "Opening trousers are not hanging")
	if dress != null:
		_check(absf(_hanging_depth(dress) - .55) < 0.001, "Dress hanging depth changed")
	if shirt != null:
		_check(absf(_hanging_depth(shirt) - .48) < 0.001, "Shirt hanging depth changed")
	if trousers != null:
		var forms = trousers.forms
		var top: float = forms.profile.top
		var bottom: float = forms.profile.bottom
		var previous := 0.0
		for step in 21:
			var y := lerpf(top,bottom,step/20.0)
			var result: Array = forms.deform(Vector3(.1,y,.2),Vector3.FORWARD,0)
			var depth: float = result[0].z/.2
			_check(depth >= previous-.0001,"Clip release must increase smoothly toward hem")
			_check(depth >= .119 and depth <= .551,"Clip depth outside bounds")
			previous = depth
		_check(is_equal_approx(previous,.55),"Clip hem remains crushed")
	var stock = game._inventory
	var vest: Node3D = stock.slots[2][0]
	var blouse: Node3D = stock.items.filter(func(i): return i.definition.outfit_style == 15)[0]
	_check(absf(_hanging_depth(vest)-.42) < .001, "Vest does not retain the requested hanging volume")
	_check(stock.display_item(blouse,2), "Cannot add blouse inside vest")
	var outer := vest.presentation_bounds("Hanging") as AABB
	var inside := blouse.presentation_bounds("Hanging") as AABB
	var scale_z := vest.global_basis.get_scale().z
	_check(scale_z > 1 and outer.end.z*scale_z >= inside.end.z+.011 and outer.position.z*scale_z <= inside.position.z-.011, "Vest fails to clear both blouse panels")
	_check(stock.display_item(vest,1), "Cannot transfer vest onto shirt")
	_check(blouse.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Solo blouse retained layer scale")
	_check(stock.display_item(blouse,2), "Cannot refresh solo blouse")
	stock.slots[1].erase(shirt)
	stock._store(shirt)
	stock._sync_slot(1)
	_check(vest.global_basis.get_scale().is_equal_approx(Vector3.ONE), "Vest did not collapse after removing shirt")
	print("DRESS_HANG_CHECK failures=", failures.size())
	game.free()
	quit(0 if failures.is_empty() else 1)
