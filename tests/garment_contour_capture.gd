extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const Accepted = preload("res://scripts/shorter_arm_body.gd")
const OUTPUT := "res://captures/"
const CELL := Vector2i(480, 640)
const BACKGROUND := Color("edf1f2")
const STYLES := ["Dress", "Apron", "Waistcoat"]
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var caption: Label
var dolls: Array[Node3D] = []
var baseline_hashes: Array[String] = []
var captures: Array = []
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)
		if failures.size() <= 8: push_error(message)
	return ok


func body_hash(doll: Node3D) -> String:
	var data: Array = [doll.arm_shortening]
	for part: MeshInstance3D in doll.rig.meshes:
		var semantic: String = part.get_meta("semantic", "")
		if not part.get_meta("is_underbody", false) and semantic not in ["head", "hair", "shoeL", "shoeR"]: continue
		var label := str(part.name)
		if label.begins_with("@"): label = "generated"
		data.append([semantic, label, part.transform, part.visible, part.mesh.surface_get_arrays(0)])
	var skeleton: Skeleton3D = doll.rig.skeleton
	for bone in skeleton.get_bone_count():
		data.append([skeleton.get_bone_name(bone), skeleton.get_bone_parent(bone), skeleton.get_bone_rest(bone)])
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(var_to_bytes(data))
	return hasher.finish().hex_encode()


func setup() -> void:
	root.size = Vector2i(520, 700)
	viewport = SubViewport.new()
	viewport.size = CELL
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var preview := TextureRect.new()
	preview.texture = viewport.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(preview)
	stage = Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = BACKGROUND
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	stage.add_child(light)
	for style in 3:
		var config := {"outfit": style, "hair": 0, "skin": 0, "palette": style}
		var accepted := Accepted.new()
		stage.add_child(accepted)
		accepted.configure(config)
		accepted.set_underbody_mode(true)
		baseline_hashes.append(body_hash(accepted))
		accepted.free()
		for variant in 2:
			var doll := Doll.new()
			# Assign both independent profiles before static fitting/configuration.
			doll.skirt_shape.bridge_tension = 0.0 if variant == 0 else .85
			doll.shell_shape.bridge_tension = 0.0 if variant == 0 else .8
			stage.add_child(doll)
			doll.configure(config)
			doll.process_mode = Node.PROCESS_MODE_DISABLED
			check(body_hash(doll) == baseline_hashes[style], "Body differs from accepted baseline: style%d variant%d" % [style, variant])
			var ground := doll.get_node_or_null("GroundContact") as Node3D
			if ground != null: ground.hide()
			doll.hide()
			dolls.append(doll)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	caption = Label.new()
	caption.position = Vector2(12, 10)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("27343b"))
	viewport.add_child(caption)


func pose_doll(doll: Node3D, pose: String) -> AABB:
	doll.clear_interaction()
	check(doll.hand_targets.is_empty() and doll.foot_targets.is_empty(), "Reach cleanup failed")
	doll.body_contact.motion.clear()
	doll.body_contact.motion_amount = 0.0
	doll.rig.animate(PI / 2 if pose == "walk" else 0.0, 1.0 if pose == "walk" else 0.0, "idle", .5)
	if pose == "hands_abdomen":
		for side in [-1.0, 1.0]:
			doll.reach("L" if side < 0 else "R", doll.body_rig.to_global(Vector3(side * .08, 1.40, .30)))
		doll.apply_reaches()
		for suffix in ["L", "R"]:
			var hand: Vector3 = doll.body_rig.to_global(doll.rig.global_pose(doll.rig.bones["Hand" + suffix]).origin)
			check(hand.is_finite() and hand.distance_to(doll.hand_targets[suffix]) < .025, "Reach missed abdomen target")
	else:
		doll.body_contact.update()
	var bounds := AABB()
	var first := true
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.visible: continue
		var points: PackedVector3Array = doll.body_contact.evaluate_vertices(part)
		for p in points:
			var world: Vector3 = doll.rig.skeleton.to_global(p)
			if not check(world.is_finite(), "Nonfinite evaluated vertex"): continue
			bounds = AABB(world, Vector3.ZERO) if first else bounds.expand(world)
			first = false
	check(not first and bounds.size.is_finite(), "Invalid framing bounds")
	return bounds


func frame_camera(bounds: AABB) -> void:
	var center := bounds.get_center()
	camera.position = center + Vector3(1.15, 0, 1).normalized() * 12
	camera.look_at(center)
	var half_width := 0.0
	var half_height := 0.0
	for corner in 8:
		var p := camera.global_basis.inverse() * (bounds.get_endpoint(corner) - center)
		half_width = maxf(half_width, absf(p.x))
		half_height = maxf(half_height, absf(p.y))
	camera.size = maxf(half_height * 2, half_width * 2 * CELL.y / CELL.x) * 1.23
	camera.position += camera.global_basis.y * camera.size * .04
	for corner in 8:
		var screen := camera.unproject_position(bounds.get_endpoint(corner))
		check(screen.is_finite() and screen.x >= 8 and screen.x <= CELL.x - 8 and screen.y >= 56 and screen.y <= CELL.y - 8, "Camera clips evaluated bounds")


func reversal(doll: Node3D) -> Variant:
	var skirt: MeshInstance3D
	for part: MeshInstance3D in doll.rig.meshes:
		if str(part.name) == "LongSkirt": skirt = part
	if skirt == null: return null
	var original: PackedVector3Array = skirt.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var points: PackedVector3Array = doll.body_contact.evaluate_vertices(skirt)
	var hip: int = doll.rig.bones.Hips
	var inverse: Transform3D = (doll.rig.global_pose(hip) * doll.rig.skeleton.get_bone_global_rest(hip).affine_inverse()).affine_inverse()
	var sectors := {"left": {}, "right": {}, "back": {}}
	for i in original.size():
		var rest := original[i]
		if rest.y < .8 or rest.y > 1.22001: continue
		var direction := ("left" if rest.x < 0 else "right") if absf(rest.x) > absf(rest.z) else ("back" if rest.z < 0 else "front")
		if direction == "front": continue
		var p: Vector3 = inverse * points[i]
		if not check(p.is_finite(), "Nonfinite contour metric"): continue
		var height := roundi(rest.y * 100000)
		var radius := Vector2(p.x, p.z).length()
		sectors[direction][height] = maxf(sectors[direction].get(height, 0.0), radius)
	var result := {}
	for direction in sectors:
		var heights: Array = sectors[direction].keys()
		heights.sort()
		heights.reverse()
		var rows: Array = []
		var peak := 0.0
		var total := 0.0
		var previous := -1.0
		for height in heights:
			var radius: float = sectors[direction][height]
			var inward := maxf(0, previous - radius) if previous >= 0 else 0.0
			peak = maxf(peak, inward)
			total += inward
			rows.append({"rest_y": float(height) / 100000, "contacted_radius": radius})
			previous = radius
		result[direction] = {"max_inward_step_m": peak, "sum_inward_steps_m": total, "rows": rows}
	return result


func pixels(image: Image) -> Dictionary:
	if not check(image != null and not image.is_empty() and image.get_size() == CELL, "Missing GPU readback"): return {}
	var background := image.get_pixel(4, CELL.y - 4)
	var foreground := 0
	var count := 0
	var colors := {}
	for y in range(64, CELL.y - 8, 6):
		for x in range(8, CELL.x - 8, 6):
			var color := image.get_pixel(x, y)
			if Vector3(color.r - background.r, color.g - background.g, color.b - background.b).length() > .08:
				foreground += 1
				colors[color.to_rgba32()] = true
			count += 1
	var ratio := float(foreground) / count
	check(ratio > .025 and ratio < .85 and colors.size() > 24, "Blank/invalid GPU foreground")
	return {"foreground_fraction": ratio, "sampled_colors": colors.size()}


func capture(pose: String) -> void:
	var sheet := Image.create_empty(CELL.x * 3, CELL.y * 2, false, Image.FORMAT_RGB8)
	var cells: Array = []
	for style in 3:
		var a := dolls[style * 2]
		var b := dolls[style * 2 + 1]
		frame_camera(pose_doll(a, pose).merge(pose_doll(b, pose)))
		for variant in 2:
			var doll := dolls[style * 2 + variant]
			doll.show()
			caption.text = "%d %s | %s\n%s" % [style, STYLES[style], pose, "A legacy: skirt 0 / shell 0" if variant == 0 else "B bridge: skirt .85 / shell .8"]
			for tick in 3: await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var stats := pixels(image)
			if image != null and not image.is_empty():
				image.convert(Image.FORMAT_RGB8)
				sheet.blit_rect(image, Rect2i(Vector2i.ZERO, CELL), Vector2i(style * CELL.x, variant * CELL.y))
			var hash_value := body_hash(doll)
			check(hash_value == baseline_hashes[style], "Accepted body changed during GPU capture")
			cells.append({"style": style, "variant": "legacy" if variant == 0 else "bridge", "body_sha256": hash_value,
				"skirt_bridge_tension": doll.skirt_shape.bridge_tension, "shell_bridge_tension": doll.shell_shape.bridge_tension,
				"pixels": stats, "skirt_reversal": reversal(doll), "camera_transform": str(camera.transform), "camera_size": camera.size})
			doll.hide()
			doll.clear_interaction()
	var filename := "contour_bridge_%s.png" % pose
	check(sheet.save_png(OUTPUT + filename) == OK, "PNG save failed")
	captures.append({"file": filename, "pose": pose, "width": sheet.get_width(), "height": sheet.get_height(), "cells": cells})
	print("CONTOUR_BRIDGE_CAPTURE ", filename)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CONTOUR_BRIDGE_CAPTURE FAIL: native GPU display required")
		quit(1)
		return
	create_timer(120).timeout.connect(func() -> void:
		print("CONTOUR_BRIDGE_CAPTURE FAIL: watchdog")
		quit(1))
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK, "Output directory unavailable")
	var hashes := {}
	for path in ["scripts/game_body_doll.gd", "scripts/accepted_body_fit.gd", "scripts/cloth_body_contact.gd", "components/garment_shape_profile.gd", "shaders/cloth_contact.gdshaderinc"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	setup()
	if failures.is_empty():
		for pose in ["idle", "hands_abdomen", "walk"]: await capture(pose)
	check(captures.size() == 3, "Incomplete A/B capture matrix")
	var manifest := {"schema": "contour-bridge-capture-v1", "captures": captures, "failures": failures, "checks": checks,
		"gpu_display": DisplayServer.get_name(), "gpu_adapter": RenderingServer.get_video_adapter_name(), "rendering_method": RenderingServer.get_current_rendering_method(),
		"source_sha256": hashes, "baseline": "shorter_arm_body.gd default accepted body, matching style/hair/skin/palette; body mesh arrays/transforms/visibility and bone rests",
		"baseline_body_sha256": baseline_hashes, "body_unchanged": failures.is_empty(), "pose_phase": .5, "walk_wave": PI / 2,
		"reversal_definition": "CPU evaluate_vertices in inverse Hips skin frame; original-rest dominant-axis sectors, radial maxima per original height .8..1.22; root-to-hem decrease in radius is inward reversal. No pass threshold; null means no LongSkirt.",
		"layout": "Columns styles 0/1/2, top legacy 0/0, bottom bridge .85/.8; A/B share union-bounds camera per style/pose; secondary motion zero"}
	var file := FileAccess.open(OUTPUT + "contour_bridge_manifest.json", FileAccess.WRITE)
	if check(file != null, "Manifest open failed"):
		file.store_string(JSON.stringify(manifest, "\t"))
		file.flush()
		check(file.get_error() == OK, "Manifest write failed")
		file.close()
	viewport.free()
	print("CONTOUR_BRIDGE_CAPTURE ", "PASS" if failures.is_empty() else "FAIL", " images=", captures.size(), " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
