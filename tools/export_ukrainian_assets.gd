extends SceneTree

## Export only the Ukrainian costume and its accessories on the unchanged rig.
## Component selection uses semantic mesh names because the undershirt spans
## top/bottom slots and the apron, overskirt and sash share the bottom slot.

const Doll = preload("res://scripts/ukrainian_doll.gd")
const Stripe = preload("res://components/motifs/stripe_motif.gd")
const Tassel = preload("res://components/motifs/tassel_motif.gd")

var failures: Array[String] = []

const GROUPS := [
	{"model": "ukrainian_ensemble", "record": "WW-UKR-001", "prefixes": ["Ukr"]},
	{"model": "ukrainian_undershirt_001", "record": "WW-UKR-001-C01", "prefixes": ["UkrShirt", "UkrCuffs", "UkrNeckBow", "UkrUnderskirt"]},
	{"model": "ukrainian_overskirt_001", "record": "WW-UKR-001-C02", "prefixes": ["UkrOverskirt"]},
	{"model": "ukrainian_apron_001", "record": "WW-UKR-001-C03", "prefixes": ["UkrApron"]},
	{"model": "ukrainian_sash_001", "record": "WW-UKR-001-C04", "prefixes": ["UkrSash", "UkrTassel"]},
	{"model": "ukrainian_beads_001", "record": "WW-UKR-001-C05", "prefixes": ["UkrBeads"]},
]


func _initialize() -> void:
	_export.call_deferred()


func _export() -> void:
	var output := ProjectSettings.globalize_path("res://tools/ww-wiki/public/assets/models")
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
	doll.configure({"outfit": 0, "hair": 3, "shoe_style": 1, "palette": 0})
	doll.set_process(false)
	doll.rig.add_animation_player(doll.body_rig)
	var source_bones: int = doll.rig.skeleton.get_bone_count()
	for entry: Dictionary in GROUPS:
		var model := doll.body_rig.duplicate() as Node3D
		root.add_child(model)
		model.name = entry.model
		model.set_meta("asset_stage", "game_adaptation")
		model.set_meta("collection_id", "ukrainian_photo_001")
		model.set_meta("wiki_record_id", entry.record)
		for part in model.find_children("*", "MeshInstance3D", true, false):
			var keep: bool = entry.model == "ukrainian_ensemble"
			for prefix: String in entry.prefixes:
				if str(part.name).begins_with(prefix):
					keep = true
					break
			if not keep:
				part.free()
				continue
			part.set_meta("wiki_component_slot", str(part.get_meta("garment_slot", "")))
		var mesh_count := model.find_children("*", "MeshInstance3D", true, false).size()
		if mesh_count == 0:
			failures.append("Empty component: " + entry.model)
		for child in model.find_children("*", "", true, false):
			child.owner = model
		var packed := PackedScene.new()
		if packed.pack(model) != OK or ResourceSaver.save(packed, output.path_join(entry.model + ".tscn")) != OK:
			failures.append("Native scene save failed: " + entry.model)
		for part in model.find_children("*", "MeshInstance3D", true, false):
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
				if str(part.name).begins_with("Ukr") or str(part.name) == "ReferenceBob":
					mat.roughness = .38 if str(part.name).begins_with("UkrBeads") else .92
				else:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				part.material_override = mat
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := output.path_join(entry.model + ".glb")
		if doc.append_from_scene(model, state) != OK or doc.write_to_filesystem(state, path) != OK:
			failures.append("GLB export failed: " + entry.model)
		else:
			var roundtrip := GLTFState.new()
			if doc.append_from_file(path, roundtrip) != OK:
				failures.append("GLB reimport failed: " + entry.model)
			else:
				var restored := doc.generate_scene(roundtrip)
				root.add_child(restored)
				var bones := restored.find_children("*", "Skeleton3D", true, false)
				var players := restored.find_children("*", "AnimationPlayer", true, false)
				if bones.is_empty() or bones[0].get_bone_count() != source_bones or players.is_empty():
					failures.append("Missing skeleton or animation: " + entry.model)
				else:
					var player: AnimationPlayer = players[0]
					var names := player.get_animation_list()
					var walk_name := ""
					var idle_name := ""
					for clip in names:
						if str(clip).ends_with("walk"): walk_name = clip
						if str(clip).ends_with("idle"): idle_name = clip
					if walk_name.is_empty() or idle_name.is_empty():
						failures.append("Idle/walk clips absent: " + entry.model)
					else:
						player.play(walk_name)
						player.advance(.25)
						var skeleton: Skeleton3D = bones[0]
						if skeleton.get_bone_pose_rotation(skeleton.find_bone("ThighL")).angle_to(Quaternion.IDENTITY) < .1:
							failures.append("Walk is static: " + entry.model)
						player.play(idle_name)
						player.seek(1.0, true)
						if skeleton.get_bone_pose_position(skeleton.find_bone("Spine")).y < .002:
							failures.append("Breathing is static: " + entry.model)
				restored.free()
		print("ASSET_EXPORT ", entry.model, " meshes=", mesh_count)
		model.free()
	doll.free()
	var motif_dir := ProjectSettings.globalize_path("res://tools/ww-wiki/public/assets/motifs")
	DirAccess.make_dir_recursive_absolute(motif_dir)
	_write_manifest(motif_dir)
	for failure in failures: push_error(failure)
	print("UKRAINIAN_EXPORT_PASS" if failures.is_empty() else "UKRAINIAN_EXPORT_FAILED")
	quit(0 if failures.is_empty() else 1)


func _write_manifest(motif_dir: String) -> void:
	# Read the exact .tres recipes exposed in the wiki, not duplicate defaults.
	var stripe := load("res://assets/collections/ukrainian_photo_001/stripe_overskirt.tres") as Stripe
	var tassel := load("res://assets/collections/ukrainian_photo_001/tassel_sash.tres") as Tassel
	if stripe == null or tassel == null:
		failures.append("Motif recipe load failed")
		return
	var manifest := {
		"schema": "ww-motifs-v1",
		"title": "织物与流苏 · 可调参 motif",
		"description": "乌克兰套装当前使用的条纹布料和毛线团流苏。下载 .tres 配方，在 Godot 中调整参数并重新生成几何；本页数值来自同一份配方。",
		"entries": [
			{"id": "stripe-overskirt", "label": "黄紫绿经向条纹布料", "record_id": "WW-UKR-001-M01",
				"image": "/assets/motifs/stripe-overskirt.png", "recipe": "/assets/motifs/stripe-overskirt.tres",
				"parameters": stripe.parameters(), "evidence_status": "用户参考适配",
				"note": "%d 个重复单元；彩条按裙身周向 u 坐标生成。配方驱动罩裙彩条，不代替原物的纤维或织法鉴定。" % stripe.repeat_count},
			{"id": "tassel-sash", "label": "黄紫混色毛线团流苏", "record_id": "WW-UKR-001-M02",
				"image": "/assets/motifs/tassel-sash.png", "recipe": "/assets/motifs/tassel-sash.tres",
				"parameters": tassel.parameters(), "evidence_status": "用户参考适配",
				"note": "毛线段、末端绒球、长度、散开程度、半径、双色和随机种子均可调。当前应用于高位黄色腰带两端。"},
		],
	}
	var text := JSON.stringify(manifest, "\t") + "\n"
	if FileAccess.open(motif_dir.path_join("manifest.json"), FileAccess.WRITE).store_string(text) == false:
		failures.append("Motif manifest write failed")
