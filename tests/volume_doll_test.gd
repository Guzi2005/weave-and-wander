extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		if not failures.has(message):
			failures.append(message)
			push_error(message)


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var doll := Doll.new()
	root.add_child(doll)
	var combinations := 0
	for hair in 3:
		for outfit in 3:
			for palette in 4:
				doll.configure({"hair": hair, "outfit": outfit, "palette": palette})
				_check(doll.find_children("VolumeDollRig", "Node3D", false, false).size() == 1, "Old character rig was not released.")
				_check(doll.find_children("CardboardTongue", "", true, false).is_empty(), "3D variant retained a paper handle.")
				_check(doll.body_rig.get_node("SkinnedMeshes/hair").get_child_count() > 0, "Hair slot is empty.")
				_check(not doll.portrait_layers().is_empty(), "Staff card portrait is missing.")
				var head: MeshInstance3D = doll.body_rig.get_node("SkinnedMeshes/head/Head")
				_check(head.mesh.get_aabb().size.z > 0.45, "Head must have real volume.")
				for mesh_value in doll.body_rig.find_children("*", "MeshInstance3D", true, false):
					var instance := mesh_value as MeshInstance3D
					_check(instance.mesh.get_surface_count() == 1, "Empty mesh: " + str(instance.name))
					_check(instance.material_override != null, "Missing character material.")
					_check(instance.skin != null, "Unbound mesh: " + str(instance.name))
					var arrays := instance.mesh.surface_get_arrays(0)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
					_check(weights.size() == vertices.size() * 4, "Missing four-weight skin data.")
					for i in vertices.size():
						_check(absf(weights[i*4] + weights[i*4+1] + weights[i*4+2] + weights[i*4+3] - 1.0) < 0.0001, "Unnormalized weights.")
				combinations += 1
	doll.configure({"reference": true, "outfit": 0})
	_check(doll.body_rig.has_node("SkinnedMeshes/headwear/HoodShell"), "Reference hood is missing.")
	_check(doll.body_rig.get_node("SkinnedMeshes/skirt").get_child_count() > 3, "Robe trim is missing.")
	doll.configure({"reference": false, "outfit": 2})
	doll.set_destination(Vector3(2, 0, 0), "stocking")
	var max_leg_swing := 0.0
	var max_turn := 0.0
	for frame in 300:
		doll.simulate(1.0 / 60.0, 1.0)
		max_leg_swing = maxf(max_leg_swing, absf(doll.rig.skeleton.get_bone_pose_rotation(doll.rig.bones["ThighL"]).get_euler().x))
		max_turn = maxf(max_turn, absf(doll.body_rig.rotation.y))
		if frame == 35:
			doll.set_hair_style(2)
			doll.set_outfit_style(0)
	_check(not doll.is_moving() and doll.position.distance_to(Vector3(2, 0, 0)) < 0.01, "Wardrobe change broke destination.")
	_check(max_leg_swing > 0.2 and max_turn > 1.1, "Locomotion lacks stepping or turning.")
	_check(absf(doll.rig.skeleton.get_bone_pose_rotation(doll.rig.bones["ThighL"]).get_euler().x) < 0.01, "Walk did not settle after arrival.")
	var frozen := doll.body_rig.transform
	var frozen_arm: Transform3D = doll.rig.skeleton.get_bone_pose(doll.rig.bones["UpperArmL"])
	doll.simulate(1, 0)
	_check(doll.body_rig.transform == frozen and doll.rig.skeleton.get_bone_pose(doll.rig.bones["UpperArmL"]) == frozen_arm, "Pause did not freeze animation.")
	game._set_speed(2)
	game._open_doll_details(game.staff[1])
	_check(game._speed == 0 and game._wardrobe.visible, "Wardrobe did not pause.")
	game._close_wardrobe()
	_check(game._speed == 2, "Wardrobe did not restore speed.")
	game._set_speed(0)
	var card: Control = game._cards[game.staff[1].get_instance_id()]
	var start := card.get_global_rect().get_center()
	var destination: Vector2 = game.camera.unproject_position(game.facilities[2]["label_position"])
	_pointer(start, false)
	_button(start, true)
	await process_frame
	_pointer(destination, true)
	await process_frame
	_check(game.dragging_doll == game.staff[1], "Card drag did not start.")
	_button(destination, false)
	await process_frame
	_check(game.dragging_doll == null, "Pointer release did not end deployment.")
	_check(game._staff_jobs[game.staff[1].get_instance_id()]["facility"] == 2, "Card drop did not assign the counter.")
	_check(game._speed == 0, "Deployment discarded a manual pause.")
	var starting_money: int = game._money
	game._set_speed(4)
	for frame in 1200:
		game._process(1.0 / 30.0)
		if frame % 60 == 0:
			await process_frame
	_check(game._money > starting_money, "Autonomous customer flow never produced a sale.")
	_check(game.staff.size() == 3 and game.facilities.size() == 13, "Shop actor or facility contract changed.")
	_check(int(ProjectSettings.get_setting("display/window/size/mode")) == 3, "Fullscreen default was lost.")
	print("VOLUME_CHECKS combinations=", combinations, " leg_swing=", max_leg_swing,
		" turn=", max_turn, " sales_income=", game._money - starting_money, " failures=", failures.size())
	doll.queue_free()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _pointer(point: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)


func _button(point: Vector2, held: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	event.pressed = held
	root.push_input(event, true)
