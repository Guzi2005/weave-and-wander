extends SceneTree
const Doll = preload("res://scripts/mosuo_doll.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const Motion = preload("res://scripts/wiki_preview_motion.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_export.call_deferred()

func _export() -> void:
	var output := ProjectSettings.globalize_path("res://models/mosuo_photo_001")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		if args.size() != 2 or args[0] != "--output" or not args[1].is_absolute_path():
			push_error("Usage: -- --output ABSOLUTE_DIRECTORY")
			quit(1)
			return
		output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var doll := Doll.new()
	root.add_child(doll)
	doll.configure({"outfit":0,"hair":0,"palette":0})
	doll.set_process(false)
	doll.rig.add_animation_player(doll.body_rig)
	_add_handwork_clip(doll)
	_add_rest_clips(doll)
	var source_bones: int = doll.rig.skeleton.get_bone_count()
	for entry in [["mosuo_ensemble",""],["mosuo_headwear_001","headwear"],["mosuo_top_001","top"],["mosuo_skirt_001","bottom"],["mosuo_insole_001","handcraft"],["basic_shoes","shoes"]]:
		var model := doll.body_rig.duplicate() as Node3D
		root.add_child(model)
		model.name = entry[0]
		model.set_meta("asset_stage","game_adaptation")
		model.set_meta("collection_id","" if entry[1] == "shoes" else "mosuo_photo_001")
		var record_ids := {"":"WW-MOS-001","shoes":"WW-GEN-001","headwear":"WW-MOS-001-C01","top":"WW-MOS-001-C02","bottom":"WW-MOS-001-C03","handcraft":"WW-MOS-001-P01"}
		model.set_meta("wiki_record_id",record_ids[entry[1]])
		for part in model.find_children("*","MeshInstance3D",true,false):
			var part_slot := Definition.part_slot(part)
			var semantic := str(part.get_meta("semantic",""))
			if not str(entry[1]).is_empty():
				var keep: bool = semantic.begins_with("shoe") if entry[1] == "shoes" else part_slot == entry[1]
				if not keep:
					part.free()
					continue
			# Blend-shape correctives remain in the native packed scene.
			part.set_meta("wiki_component_slot",part_slot)
		for child in model.find_children("*","",true,false):
			child.owner = model
		# Component exports must not retain morph tracks targeting removed garments.
		var model_player: AnimationPlayer = model.get_node("AnimationPlayer")
		var own_library := model_player.get_animation_library("").duplicate(true)
		model_player.remove_animation_library("")
		model_player.add_animation_library("",own_library)
		for clip_name in own_library.get_animation_list():
			var clip: Animation = own_library.get_animation(clip_name)
			for track in range(clip.get_track_count()-1,-1,-1):
				if clip.track_get_type(track) == Animation.TYPE_BLEND_SHAPE:
					var target := NodePath(str(clip.track_get_path(track)).split(":")[0])
					if model.get_node_or_null(target) == null: clip.remove_track(track)
		var packed := PackedScene.new()
		if packed.pack(model) != OK or ResourceSaver.save(packed,output.path_join(entry[0]+".tscn")) != OK:
			failures.append("Native scene save failed: "+entry[0])
		for part in model.find_children("*","MeshInstance3D",true,false):
			var source: Material = part.material_override
			if source is ShaderMaterial:
				var mat := StandardMaterial3D.new()
				mat.resource_name = "Flat ink / " + str(part.name)
				mat.albedo_color = source.get_shader_parameter("pigment")
				if source.shader == preload("res://shaders/doll_costume.gdshader"):
					mat.vertex_color_use_as_albedo = source.get_shader_parameter("use_vertex_color")
					if source.get_shader_parameter("use_pigment_map"):
						mat.albedo_texture = source.get_shader_parameter("pigment_map")
				mat.roughness = 1.0
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				part.material_override = mat
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := output.path_join(entry[0]+".glb")
		if doc.append_from_scene(model,state) != OK or doc.write_to_filesystem(state,path) != OK:
			failures.append("GLB export failed: "+entry[0])
		else:
			_retain_fabric_extensions(path)
			var roundtrip := GLTFState.new()
			if doc.append_from_file(path,roundtrip) != OK:
				failures.append("GLB reimport failed: "+entry[0])
			else:
				var restored := doc.generate_scene(roundtrip)
				root.add_child(restored)
				var bones := restored.find_children("*","Skeleton3D",true,false)
				var players := restored.find_children("*","AnimationPlayer",true,false)
				if bones.is_empty() or bones[0].get_bone_count() != source_bones or players.is_empty():
					failures.append("Missing skeleton or animation: "+entry[0])
				else:
					var player: AnimationPlayer = players[0]
					var names := player.get_animation_list()
					var walk_name := ""
					var idle_name := ""
					for clip in names:
						if str(clip).ends_with("walk"): walk_name = clip
						if str(clip).ends_with("idle"): idle_name = clip
					if walk_name.is_empty() or idle_name.is_empty():
						failures.append("Idle/walk clips absent: "+entry[0])
					else:
						player.play(walk_name)
						player.advance(.25)
						var skeleton: Skeleton3D = bones[0]
						if skeleton.get_bone_pose_rotation(skeleton.find_bone("ThighL")).angle_to(Quaternion.IDENTITY) < .1:
							failures.append("Walk is static: "+entry[0])
						player.play(idle_name)
						player.seek(1.0,true)
						if skeleton.get_bone_pose_position(skeleton.find_bone("Spine")).y < .002:
							failures.append("Breathing is static: "+entry[0])
				restored.free()
		print("ASSET_EXPORT ",entry[0]," meshes=",model.find_children("*","MeshInstance3D",true,false).size())
		model.free()
	doll.free()
	for failure in failures: push_error(failure)
	print("MOSUO_EXPORT_PASS" if failures.is_empty() else "MOSUO_EXPORT_FAILED")
	quit(0 if failures.is_empty() else 1)


func _add_handwork_clip(doll: Node3D) -> void:
	var player: AnimationPlayer = doll.body_rig.get_node("AnimationPlayer")
	var library := player.get_animation_library("")
	var clip := library.get_animation("idle").duplicate() as Animation
	for track in clip.get_track_count():
		while clip.track_get_key_count(track): clip.track_remove_key(track,0)
	var motion := Motion.new()
	motion.mode = "handwork"
	for frame in 25:
		var time := frame/24.0*4.0
		motion.elapsed = time
		motion.apply(doll)
		for bone in doll.rig.skeleton.get_bone_count():
			clip.rotation_track_insert_key(bone*2,time,doll.rig.skeleton.get_bone_pose_rotation(bone))
			clip.position_track_insert_key(bone*2+1,time,doll.rig.skeleton.get_bone_pose_position(bone))
	library.add_animation("handwork",clip)
	doll.rig.animate(0,0,"idle",0)


func _add_rest_clips(doll: Node3D) -> void:
	var poses = preload("res://scripts/garment_preview_poses.gd")
	var player: AnimationPlayer = doll.body_rig.get_node("AnimationPlayer")
	var library := player.get_animation_library("")
	for mode in ["sit","lie"]:
		var clip := library.get_animation("idle").duplicate() as Animation
		clip.length = 4.0
		clip.loop_mode = Animation.LOOP_NONE
		for track in clip.get_track_count():
			while clip.track_get_key_count(track): clip.track_remove_key(track,0)
		var morph_tracks: Array = []
		for part in doll.rig.meshes:
			if not part.get_meta("rest_cloth",false): continue
			for shape in part.mesh.get_blend_shape_count():
				var track := clip.add_track(Animation.TYPE_BLEND_SHAPE)
				clip.track_set_path(track,NodePath(str(doll.body_rig.get_path_to(part))+":"+str(part.mesh.get_blend_shape_name(shape))))
				morph_tracks.append([track,part,shape])
		for frame in 49:
			doll.rig.animate(0,0,"idle",0)
			poses._pose_rest_frame(doll,mode,frame/48.0)
			for entry in morph_tracks: clip.blend_shape_track_insert_key(entry[0],frame/12.0,entry[1].get_blend_shape_value(entry[2]))
			for bone in doll.rig.skeleton.get_bone_count():
				clip.rotation_track_insert_key(bone*2,frame/12.0,doll.rig.skeleton.get_bone_pose_rotation(bone))
				clip.position_track_insert_key(bone*2+1,frame/12.0,doll.rig.skeleton.get_bone_pose_position(bone))
		library.add_animation(mode,clip)
	doll.rig.animate(0,0,"idle",0)

func _retain_fabric_extensions(path: String) -> void:
	# Godot's exporter omits these StandardMaterial3D properties. Preserve the
	# directional silk highlight for clients supporting the standard glTF extensions.
	var bytes := FileAccess.get_file_as_bytes(path)
	var json_length := bytes.decode_u32(12)
	var document: Dictionary = JSON.parse_string(bytes.slice(20,20+json_length).get_string_from_utf8())
	var used: Array = document.get("extensionsUsed",[])
	for material: Dictionary in document.get("materials",[]):
		var label := str(material.get("name",""))
		if not label.contains("generated textile study"): continue
		var extensions: Dictionary = material.get("extensions",{})
		extensions["KHR_materials_anisotropy"] = {"anisotropyStrength":.65,"anisotropyRotation":0.0}
		extensions["KHR_materials_clearcoat"] = {"clearcoatFactor":.18,"clearcoatRoughnessFactor":.3}
		material["extensions"] = extensions
		for extension in ["KHR_materials_anisotropy","KHR_materials_clearcoat"]:
			if not extension in used: used.append(extension)
	document["extensionsUsed"] = used
	# JSON.parse_string converts all numbers to float. Restore whole numbers to
	# integer tokens for Blender's strict accessor/index parser before re-encoding.
	var encoded := JSON.stringify(_integral_numbers(document)).to_utf8_buffer()
	while encoded.size() % 4: encoded.append(32)
	var tail := bytes.slice(20+json_length)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_32(0x46546C67)
	file.store_32(2)
	file.store_32(20+encoded.size()+tail.size())
	file.store_32(encoded.size())
	file.store_32(0x4E4F534A)
	file.store_buffer(encoded)
	file.store_buffer(tail)

func _integral_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		for key in value: value[key] = _integral_numbers(value[key])
	elif value is Array:
		for index in value.size(): value[index] = _integral_numbers(value[index])
	elif value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

