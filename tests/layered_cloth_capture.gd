extends SceneTree

const Doll = preload("res://scripts/game_body_doll.gd")
const Bench = preload("res://components/rest_bench.gd")
const Definition = preload("res://scripts/garment_definition.gd")
const OUTPUT := "res://captures/"
const STYLES := ["Dress", "Apron", "Waistcoat"]
const SLEEP_NAMES := ["Palms under cheek", "Curled", "Loose legs", "Relaxed arm"]
const BACKGROUND := Color("edf1f2")

var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var caption: Label
var dolls: Array[Node3D] = []
var benches: Array[Node3D] = []
var body_signatures: Array[int] = []
var failures: Array[String] = []
var captures: Array = []
var exported: Array = []
var quick := false
var export_contact := false
var contact_evaluator := false
var sample_count := 0
var started := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok and message not in failures:
		failures.append(message)
		if failures.size() <= 12: push_error("LAYERED_CAPTURE: " + message)
	return ok


func _run() -> void:
	started = Time.get_ticks_msec()
	quick = "--quick" in OS.get_cmdline_user_args()
	export_contact = "--export-contact" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless":
		print("LAYERED_CLOTH_CAPTURE FAIL: a real GPU display is required")
		quit(1)
		return
	if not _check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK,
			"Cannot create capture directory"):
		quit(1)
		return
	create_timer(240.0).timeout.connect(func() -> void:
		print("LAYERED_CLOTH_CAPTURE FAIL: 240 second watchdog expired")
		quit(1))
	_setup_stage()
	if not failures.is_empty():
		_finish()
		return
	contact_evaluator = dolls[0].body_contact != null and dolls[0].body_contact.has_method("evaluate_vertices")
	if export_contact and not contact_evaluator:
		print("LAYERED_CONTACT fallback: rig.deformed_vertices; UNCORRECTED shader contact/lift")
	var poses: Array = [{"name": "idle", "wave": 0.0, "activity": "idle"},
		{"name": "raised_work", "wave": 0.0, "activity": "sewing"},
		{"name": "raised_reach", "wave": 0.0, "activity": "idle", "reach_space": "body_rig local",
			"reaches": {"L": [-0.38, 2.15, 0.28], "R": [0.38, 2.15, 0.28]}},
		{"name": "hands_abdomen", "wave": 0.0, "activity": "idle", "reach_space": "body_rig local",
			"reaches": {"L": [-0.08, 1.40, 0.30], "R": [0.08, 1.40, 0.30]}}]
	for phase in 4:
		poses.append({"name": "walk_%d" % phase, "wave": TAU * phase / 4.0, "activity": "idle"})
	for pose: Dictionary in poses:
		for doll in dolls:
			_clear_reaches(doll)
			doll.rig.animate(pose.wave, 1.0 if str(pose.name).begins_with("walk") else 0.0, pose.activity, 0.5)
			if pose.has("reaches"):
				_apply_pose_reaches(doll, pose)
			else:
				doll.body_contact.update()
		await _capture_pose(pose, false)
		for doll in dolls: _clear_reaches(doll)
		if not failures.is_empty(): break
	if not quick and failures.is_empty():
		_prepare_rest(false)
		_settle(130)
		_check_supports(false)
		await _capture_pose({"name": "bench_sit", "activity": "resting"}, true)
		if failures.is_empty():
			for style in 3: benches[style].release(dolls[style])
			_settle(130)
			for doll in dolls: _check(doll._rest_blend <= 0.001, "Sit exit did not settle")
			_prepare_rest(true)
			for pose in 4:
				for doll in dolls: doll.nap_pose = pose
				_settle(150)
				_check_supports(true, pose)
				await _capture_pose({"name": "sleep_%d" % pose, "activity": "napping",
					"nap_pose": pose, "description": SLEEP_NAMES[pose]}, true, true)
				if not failures.is_empty(): break
	_finish()


func _setup_stage() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(640, 720)
	root.content_scale_size = root.size
	viewport = SubViewport.new()
	viewport.size = Vector2i(480, 640)
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
	environment.environment.ambient_light_color = Color("f4f7f8")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.65
	stage.add_child(light)
	for style in 3:
		var group := Node3D.new()
		stage.add_child(group)
		group.position.x = style * 12.0
		var doll := Doll.new()
		group.add_child(doll)
		doll.configure({"outfit": style, "hair": 0, "skin": 0, "palette": style})
		doll.process_mode = Node.PROCESS_MODE_DISABLED
		if not _check(doll.rig != null and doll.body_contact != null, "Unbound style %d" % style): return
		_check(doll.body_rig.get_meta("accepted_body_version", "") == "v20-short-arm-0045",
			"Unexpected accepted body version")
		var ground := doll.get_node_or_null("GroundContact") as Node3D
		if ground != null: ground.hide()
		dolls.append(doll)
		body_signatures.append(_body_signature(doll))
		var bench := Bench.new()
		group.add_child(bench)
		bench.set_process(false)
		bench.hide()
		benches.append(bench)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	caption = Label.new()
	caption.position = Vector2(14, 10)
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_color", Color("27343b"))
	viewport.add_child(caption)


func _body_signature(doll: Node3D) -> int:
	var values: Array = [doll.arm_shortening]
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.get_meta("is_underbody", false): continue
		values.append([part.get_instance_id(), part.visible, part.transform, part.mesh.surface_get_arrays(0)])
	for bone in doll.rig.skeleton.get_bone_count():
		values.append(doll.rig.skeleton.get_bone_rest(bone))
	return hash(var_to_bytes(values))


func _clear_reaches(doll: Node3D) -> void:
	doll.clear_interaction()
	_check(doll.hand_targets.is_empty() and doll.foot_targets.is_empty(), "Reach targets survived cleanup")


func _apply_pose_reaches(doll: Node3D, pose: Dictionary) -> void:
	for side: String in pose.reaches:
		var xyz: Array = pose.reaches[side]
		var target: Vector3 = doll.body_rig.to_global(Vector3(xyz[0], xyz[1], xyz[2]))
		if not _check(target.is_finite(), "Nonfinite reach target: " + pose.name): return
		doll.reach(side, target)
	# GameBodyDoll updates body contact after the public IK solve.
	doll.apply_reaches()
	for side: String in pose.reaches:
		for bone in ["UpperArm", "Forearm", "Hand"]:
			var transform: Transform3D = doll.rig.global_pose(doll.rig.bones[bone + side])
			if not _check(transform.is_finite(), "Nonfinite reach bone: %s/%s%s" % [pose.name, bone, side]): return
		var hand: Vector3 = doll.rig.global_pose(doll.rig.bones["Hand" + side]).origin
		var actual: Vector3 = doll.body_rig.to_global(hand)
		_check(actual.is_finite() and actual.distance_to(doll.hand_targets[side]) < 0.025,
			"Reach missed target: %s/%s/style%d" % [pose.name, side, doll.outfit_style])
		if pose.name == "raised_reach":
			var shoulder: Vector3 = doll.rig.global_pose(doll.rig.bones["UpperArm" + side]).origin
			_check(hand.y > shoulder.y + 0.20, "Raised reach did not lift hand above shoulder: " + side)
		elif pose.name == "hands_abdomen":
			_check(absf(hand.x) < 0.18 and hand.y > 1.25 and hand.y < 1.55 and hand.z > 0.22 and hand.z < 0.42,
				"Abdomen reach escaped lower-torso contact region: " + side)


func _prepare_rest(nap: bool) -> void:
	for style in 3:
		var doll := dolls[style]
		var bench := benches[style]
		_clear_reaches(doll)
		bench.show()
		_check(bench.reserve(doll, nap) != null, "Rest reservation failed")
		bench.support_actor(doll)
		doll._moving = false


func _settle(frames: int) -> void:
	# Run the actual supported transition; never pose_rest/rotate a sleeper directly.
	for frame in frames:
		for doll in dolls: doll.simulate(1.0 / 60.0, 1.0)


func _check_supports(nap: bool, pose := 0) -> void:
	for style in 3:
		var doll := dolls[style]
		var reservation: Dictionary = benches[style].reservations.get(doll.get_instance_id(), {})
		_check(not reservation.is_empty(), "Missing bench reservation")
		if reservation.is_empty(): continue
		_check(reservation.seats.size() == (2 if nap else 1), "Incorrect reserved seat span")
		_check(doll.rest_mode == ("nap" if nap else "sit") and doll._rest_blend > 0.999,
			"Supported rest transition incomplete")
		var support: Node3D = doll.rest_support.get_ref() if doll.rest_support != null else null
		_check(is_instance_valid(support), "Missing real rest support")
		if is_instance_valid(support):
			var hip: Vector3 = doll.body_rig.to_global(doll.rig.global_pose(doll.rig.bones.Hips).origin)
			_check(hip.distance_to(support.global_position) < 0.005, "Hips not attached to bench support")
		if nap: _check(doll._nap_pose_weights[pose] > 0.999, "Sleep pose transition incomplete")


func _evaluated_points(doll: Node3D, part: MeshInstance3D) -> PackedVector3Array:
	if doll.body_contact != null and doll.body_contact.has_method("evaluate_vertices"):
		return doll.body_contact.call("evaluate_vertices", part)
	# Explicit fallback: skinning and rest morphs only, not shader contact or lift.
	return doll.rig.deformed_vertices(part)


func _sample(doll: Node3D, pose: Dictionary) -> Dictionary:
	var entry := {"style": doll.outfit_style, "style_name": STYLES[doll.outfit_style],
		"pose": pose.name, "pose_parameters": pose, "body": [], "cloth": [],
		"coordinate_space": "world-in-model: doll.to_local(skeleton.to_global(posed_vertex)); staging/camera excluded",
		"contact": "body_contact.evaluate_vertices" if contact_evaluator else "UNCORRECTED rig.deformed_vertices; shader contact/lift excluded",
		"corrected": contact_evaluator}
	var bounds := AABB()
	var initialized := false
	var to_model: Transform3D = doll.global_transform.affine_inverse() * doll.rig.skeleton.global_transform
	for part: MeshInstance3D in doll.rig.meshes:
		if not part.is_visible_in_tree(): continue
		if not _check(part.mesh != null and part.mesh.get_surface_count() == 1, "Expected one baked mesh surface"): continue
		var body: bool = part.get_meta("is_underbody", false)
		var cloth: bool = not body and Definition.part_slot(part) in ["top", "bottom", "outer"] \
			and not Definition.is_button(part) and not Definition.is_flower(part)
		var points := _evaluated_points(doll, part)
		var arrays := part.mesh.surface_get_arrays(0)
		_check(points.size() == arrays[Mesh.ARRAY_VERTEX].size() and not points.is_empty(), "Invalid evaluated vertex count")
		var vertices: Array = []
		for point in points:
			var world: Vector3 = doll.rig.skeleton.to_global(point)
			if not _check(world.is_finite(), "Nonfinite posed vertex"): continue
			bounds = bounds.expand(world) if initialized else AABB(world, Vector3.ZERO)
			initialized = true
			if export_contact and (body or cloth):
				var p := to_model * point
				vertices.append([snappedf(p.x, 0.000001), snappedf(p.y, 0.000001), snappedf(p.z, 0.000001)])
		if export_contact and (body or cloth):
			var indices: Array = Array(arrays[Mesh.ARRAY_INDEX]) if arrays[Mesh.ARRAY_INDEX] != null else []
			if indices.is_empty(): indices = range(vertices.size())
			_check(indices.size() % 3 == 0, "Nontriangle exported mesh")
			for index: int in indices:
				if not _check(index >= 0 and index < vertices.size(), "Export index out of bounds"): break
			var item := {"name": str(part.name), "path": str(doll.body_rig.get_path_to(part)),
				"vertices": vertices, "indices": indices}
			if body: entry.body.append(item)
			else: entry.cloth.append(item)
	_check(initialized, "Empty doll bounds")
	_check(_body_signature(doll) == body_signatures[doll.outfit_style], "Approved body/rest skeleton changed during capture")
	if export_contact:
		_check(not entry.body.is_empty() and not entry.cloth.is_empty(), "Empty contact sample")
		exported.append(entry)
	sample_count += 1
	return {"bounds": bounds}


func _bench_bounds(bench: Node3D, bounds: AABB) -> AABB:
	for part: MeshInstance3D in bench.find_children("*", "MeshInstance3D", true, false):
		if not part.is_visible_in_tree(): continue
		var local := part.mesh.get_aabb()
		for corner in 8: bounds = bounds.expand(part.to_global(local.get_endpoint(corner)))
	return bounds


func _frame(bounds: AABB, view: String) -> void:
	if not _check(bounds.position.is_finite() and bounds.size.is_finite(), "Nonfinite frame bounds: " + view): return
	var direction: Vector3 = {"front": Vector3.BACK, "quarter": Vector3(1, 0, 1),
		"top": Vector3.UP, "side": Vector3(0, 0.12, 1)}[view]
	var center := bounds.get_center()
	camera.position = center + direction.normalized() * 12.0
	camera.look_at(center, Vector3.FORWARD if view == "top" else Vector3.UP)
	var half_width := 0.0
	var half_height := 0.0
	for corner in 8:
		var p := camera.global_basis.inverse() * (bounds.get_endpoint(corner) - center)
		half_width = maxf(half_width, absf(p.x))
		half_height = maxf(half_height, absf(p.y))
	var aspect := float(viewport.size.x) / viewport.size.y
	camera.size = maxf(half_height * 2.0, half_width * 2.0 / aspect) * 1.22
	camera.position += camera.global_basis.y * camera.size * 0.035
	for corner in 8:
		var screen := camera.unproject_position(bounds.get_endpoint(corner))
		_check(screen.is_finite() and screen.x >= 8 and screen.x <= viewport.size.x - 8 and screen.y >= 48 \
			and screen.y <= viewport.size.y - 8, "Camera clips bounds: " + view)


func _image_stats(image: Image) -> Dictionary:
	if not _check(image != null and not image.is_empty() and image.get_size() == viewport.size, "Empty/wrong-size GPU image"):
		return {}
	var background := image.get_pixel(4, image.get_height() - 4)
	var foreground := 0
	var count := 0
	var colors := {}
	for y in range(56, image.get_height() - 8, 6):
		for x in range(8, image.get_width() - 8, 6):
			var color := image.get_pixel(x, y)
			if Vector3(color.r - background.r, color.g - background.g, color.b - background.b).length() > 0.08:
				foreground += 1
				colors[color.to_rgba32()] = true
			count += 1
	var ratio := float(foreground) / maxi(1, count)
	_check(ratio > 0.025 and ratio < 0.85 and colors.size() > 24, "Blank/invalid GPU foreground")
	return {"foreground_fraction": snappedf(ratio, 0.0001), "sampled_colors": colors.size()}


func _capture_pose(pose: Dictionary, resting: bool, sleeping := false) -> void:
	if not failures.is_empty(): return
	viewport.size = Vector2i(640, 480) if resting else Vector2i(480, 640)
	var sheet := Image.create_empty(viewport.size.x * 3, viewport.size.y * 2, false, Image.FORMAT_RGB8)
	sheet.fill(BACKGROUND)
	var views := ["top", "side"] if sleeping else ["front", "quarter"]
	var cells: Array = []
	for style in 3:
		var sample := _sample(dolls[style], pose)
		var bounds: AABB = sample.bounds
		if resting: bounds = _bench_bounds(benches[style], bounds)
		for row in 2:
			caption.text = "%d %s | %s | %s" % [style, STYLES[style], pose.name, views[row]]
			_frame(bounds, views[row])
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var stats := _image_stats(image)
			if not failures.is_empty(): return
			image.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, viewport.size), Vector2i(style * viewport.size.x, row * viewport.size.y))
			cells.append({"style": style, "view": views[row], "pixels": stats})
	var filename := "layered_%s.png" % pose.name
	_check(sheet.save_png(OUTPUT + filename) == OK, "PNG save failed: " + filename)
	captures.append({"file": filename, "pose": pose.name, "width": sheet.get_width(), "height": sheet.get_height(), "cells": cells})
	print("LAYERED_CAPTURE ", filename)


func _write_json(filename: String, data: Variant) -> void:
	var file := FileAccess.open(OUTPUT + filename, FileAccess.WRITE)
	if not _check(file != null, "Cannot write " + filename): return
	file.store_string(JSON.stringify(data))
	file.flush()
	_check(file.get_error() == OK, "Write failed: " + filename)
	file.close()


func _finish() -> void:
	var expected := 8 if quick else 13
	_check(captures.size() == expected and sample_count == expected * 3, "Incomplete capture matrix")
	if export_contact:
		_check(exported.size() == expected * 3, "Incomplete contact matrix")
		_write_json("layered_contact_input.json", exported)
	_write_json("layered_capture_manifest.json", {"schema_version": 1, "quick": quick,
		"gpu_display": DisplayServer.get_name(), "gpu_adapter": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"elapsed_seconds": (Time.get_ticks_msec() - started) / 1000.0,
		"contact_export": export_contact, "contact_corrected": contact_evaluator,
		"contact_limit": "CPU evaluator diagnostic, not a GPU vertex readback or collision acceptance; fallback is uncorrected",
		"samples": sample_count, "captures": captures, "failures": failures,
		"approved_body_unchanged": failures.is_empty()})
	if is_instance_valid(viewport): viewport.free()
	print("LAYERED_CLOTH_CAPTURE %s images=%d samples=%d contact=%s body_unchanged=%s" % [
		"PASS" if failures.is_empty() else "FAIL", captures.size(), sample_count,
		("evaluated" if contact_evaluator else "UNCORRECTED") if export_contact else "off", str(failures.is_empty())])
	quit(0 if failures.is_empty() else 1)
