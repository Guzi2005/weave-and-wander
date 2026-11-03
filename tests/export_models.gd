extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")


func _initialize() -> void:
	_export.call_deferred()


func _export() -> void:
	var output := ProjectSettings.globalize_path("res://models")
	DirAccess.make_dir_recursive_absolute(output)
	var recipes := [
		{"file": "tailor_apron", "hair": 2, "outfit": 1, "palette": 2, "skin": 1},
		{"file": "doll_long_dress", "hair": 0, "outfit": 0, "palette": 0},
		{"file": "doll_waistcoat", "hair": 1, "outfit": 2, "palette": 3, "skin": 2},
		{"file": "hooded_reference", "hair": 1, "outfit": 0, "reference": true},
	]
	for recipe in recipes:
		var doll := Doll.new()
		root.add_child(doll)
		doll.configure(recipe)
		doll.rig.add_animation_player(doll.body_rig)
		var model := doll.body_rig.duplicate() as Node3D
		root.add_child(model)
		model.name = recipe["file"]
		for child in model.find_children("*", "", true, false):
			child.owner = model
		var packed := PackedScene.new()
		if packed.pack(model) != OK or ResourceSaver.save(packed, output.path_join(recipe["file"] + ".tscn")) != OK:
			push_error("Unable to save editable model scene.")
			quit(1)
			return
		for child in model.find_children("*", "MeshInstance3D", true, false):
			var instance := child as MeshInstance3D
			var source := instance.material_override as ShaderMaterial
			var material := StandardMaterial3D.new()
			material.albedo_color = source.get_shader_parameter("pigment")
			material.roughness = 1.0
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			instance.material_override = material
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var path := output.path_join(recipe["file"] + ".glb")
		if document.append_from_scene(model, state) != OK or document.write_to_filesystem(state, path) != OK:
			push_error("Unable to export model: " + path)
			quit(1)
			return
		var roundtrip := GLTFState.new()
		if document.append_from_file(path, roundtrip) != OK:
			push_error("Exported GLB could not be reimported.")
			quit(1)
			return
		var restored := document.generate_scene(roundtrip)
		root.add_child(restored)
		var restored_skeletons := restored.find_children("*", "Skeleton3D", true, false)
		var restored_players := restored.find_children("*", "AnimationPlayer", true, false)
		if restored_skeletons.is_empty() or restored_skeletons[0].get_bone_count() != 20 or restored_players.is_empty() or restored_players[0].get_animation_list().size() < 3:
			push_error("Skeleton or animation data was lost during GLB roundtrip.")
			restored.free()
			quit(1)
			return
		var restored_player := restored_players[0] as AnimationPlayer
		var restored_skeleton := restored_skeletons[0] as Skeleton3D
		restored_player.play("walk")
		restored_player.advance(0.25)
		restored_skeleton.force_update_all_bone_transforms()
		var thigh_index := restored_skeleton.find_bone("ThighL")
		if thigh_index < 0 or restored_skeleton.get_bone_pose_rotation(thigh_index).angle_to(Quaternion.IDENTITY) < 0.1:
			push_error("Reimported walk animation does not move its skeleton.")
			restored.free()
			quit(1)
			return
		print("MODEL_EXPORT_PASS ", path, " meshes=", model.find_children("*", "MeshInstance3D", true, false).size(),
			" bones=", restored_skeletons[0].get_bone_count(), " animations=", restored_players[0].get_animation_list())
		restored.free()
		model.free()
		doll.free()
	quit()
