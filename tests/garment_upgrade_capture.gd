extends SceneTree
const Lab = preload("res://scenes/garment_lab.tscn")
var failures: Array[String] = []
var lab: Control
var report := {"frames": [], "captures": [], "body_unchanged": true}


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _initialize() -> void:
	run.call_deferred()


func capture(name: String, whole := false) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image() if whole else lab.viewport.get_texture().get_image()
	var filename := "res://captures/garment_upgrade_" + name + ".png"
	check(image.save_png(filename) == OK, "Could not save " + filename)
	var background := image.get_pixel(5, 5)
	var visible_pixels := 0
	for y in range(10, image.get_height() - 10, 20):
		for x in range(10, image.get_width() - 10, 20):
			var pixel := image.get_pixel(x, y)
			if absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b) > .08: visible_pixels += 1
	check(visible_pixels > 40, "Blank capture: " + name)
	report.captures.append({"path": filename, "nonblank_samples": visible_pixels})


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = root.size
	lab = Lab.instantiate()
	root.add_child(lab)
	lab.set_process(false)
	await process_frame
	var initial: int = lab._body_hash()
	await capture("lab", true)
	for style in 3:
		lab.style = style
		lab.style_picker.select(style)
		lab._rebuild()
		var body: int = lab._body_hash()
		lab.mode = 0
		lab.yaw = 0.0
		lab._process(1.0 / 60)
		await capture("style_%d_still" % style)
		lab.mode = 1
		for i in 120: lab._process(1.0 / 60)
		await capture("style_%d_turn" % style)
		var during: PackedVector4Array = lab.doll.body_contact.motion.states.duplicate()
		check(during[-1].y > .005, "No real NPC turn response")
		lab.mode = 0
		for i in 9: lab._process(1.0 / 60)
		await capture("style_%d_stop" % style)
		check(lab.doll.body_contact.motion.is_active(), "No after-motion at stop")
		check(lab._body_hash() == body, "Body changed during turn")
		for i in 600: lab._process(1.0 / 60)
		check(not lab.doll.body_contact.motion.is_active(), "Cloth did not settle")
		if style == 0:
			var old_value: float = lab.doll.skirt_fabric.density_gsm
			lab.physics_fields.density_gsm.value = 420
			check(lab.doll.skirt_fabric.density_gsm == 420, "Inspector spinbox not connected")
			lab.physics_fields.density_gsm.value = old_value
			var old_tension: float = lab._shape.bridge_tension
			lab.shape_fields.bridge_tension.value = .25
			check(is_equal_approx(lab._shape.bridge_tension, .25), "Contour tension spinbox not connected")
			check(lab._body_hash() == body, "Contour tension changed accepted body")
			lab.shape_fields.bridge_tension.value = old_tension
	# Exercise actual curve pointer events, not just a resource setter.
	lab.style = 0
	lab._rebuild()
	lab.yaw = 0
	var curve: Curve = lab.curve_editor.curve
	var index := curve.point_count - 1
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = lab.curve_editor._screen(curve.get_point_position(index))
	lab.curve_editor._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.position = press.position + Vector2(0, -25)
	lab.curve_editor._gui_input(drag)
	press.pressed = false
	lab.curve_editor._gui_input(press)
	check(curve.get_point_position(index).y > .01, "Curve drag did not change ease")
	check(lab._body_hash() == initial, "Curve edit changed accepted body")
	lab._process(1.0 / 60)
	await capture("curve_edit", true)
	curve.set_point_value(index, 0.0)
	lab._rebuild()
	# FileDialog callbacks round-trip actual resource files, including disabled
	# switches, without overwriting any user-authored preset.
	var preset_path := ProjectSettings.globalize_path("user://garment-regression-%d.tres" % Time.get_ticks_usec())
	lab.motion_toggle.button_pressed = false
	lab.shape_toggle.button_pressed = false
	lab.physics_fields.density_gsm.value = 315
	lab.shape_fields.bridge_tension.value = .35
	lab._preset_dialog(true)
	var dialog := lab.get_child(lab.get_child_count() - 1) as FileDialog
	check(dialog != null, "Save dialog did not open")
	dialog.file_selected.emit(preset_path)
	await process_frame
	check(FileAccess.file_exists(preset_path), "Preset was not saved")
	lab.motion_toggle.button_pressed = true
	lab.shape_toggle.button_pressed = true
	lab.physics_fields.density_gsm.value = 180
	lab.shape_fields.bridge_tension.value = 0
	lab._preset_dialog(false)
	dialog = lab.get_child(lab.get_child_count() - 1) as FileDialog
	dialog.file_selected.emit(preset_path)
	await process_frame
	check(not lab.doll.skirt_fabric.enabled and not lab._shape.enabled, "Preset lost off switches")
	check(not lab.motion_toggle.button_pressed and not lab.shape_toggle.button_pressed, "Loaded toggles disagree with resources")
	check(lab.doll.skirt_fabric.density_gsm == 315 and lab.physics_fields.density_gsm.value == 315, "Preset density/UI did not round-trip")
	check(is_equal_approx(lab._shape.bridge_tension, .35) and is_equal_approx(lab.shape_fields.bridge_tension.value, .35), "Preset contour tension/UI did not round-trip")
	check(lab._body_hash() == initial, "Preset load changed accepted body")
	check(DirAccess.remove_absolute(preset_path) == OK, "Could not remove temporary test preset")
	lab.motion_toggle.button_pressed = true
	lab.shape_toggle.button_pressed = true
	lab.physics_fields.density_gsm.value = 180
	lab.shape_fields.bridge_tension.value = .85
	lab.mode = 2
	lab.phase = 0
	lab.yaw = 0
	var frames := "res://captures/garment_motion_frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames))
	for i in 64:
		for step in 6: lab._process(1.0 / 120)
		await process_frame
		await RenderingServer.frame_post_draw
		var frame: Image = lab.viewport.get_texture().get_image()
		frame.save_png(frames + "/frame_%03d.png" % i)
		var state: Vector4 = lab.doll.body_contact.motion.states[-1]
		report.frames.append({"frame": i, "yaw": lab.yaw, "hem": [state.x, state.y, state.z, state.w]})
	report.failures = failures
	report.gpu = RenderingServer.get_video_adapter_name()
	FileAccess.open("res://captures/garment_upgrade_manifest.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("GARMENT_UPGRADE_CAPTURE images=", report.captures.size(), " frames=64 failures=", failures.size())
	lab.free()
	quit(0 if failures.is_empty() else 1)
