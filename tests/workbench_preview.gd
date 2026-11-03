extends SceneTree

var images := {}
var failures := 0

func _initialize() -> void:
	_run.call_deferred()


func _capture(label: String) -> void:
	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	images[label] = image
	if image.save_png(ProjectSettings.globalize_path("res://captures/workbench_%s_%dx%d.png" % [label, root.size.x, root.size.y])) != OK:
		failures += 1
		push_error("Could not save workbench capture")


func _mean(label: String, area := Rect2(.05,.2,.9,.65)) -> Color:
	var image: Image = images[label]
	var sum := Color(0,0,0,0)
	var samples := 0
	for x in range(int(area.position.x*image.get_width()),int(area.end.x*image.get_width()),8):
		for y in range(int(area.position.y*image.get_height()),int(area.end.y*image.get_height()),8):
			sum += image.get_pixel(x,y)
			samples += 1
	return sum / samples


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._set_speed(0)
	game._toast_label.hide()
	var view: Node = game._view_controls
	view.zoom = .35
	view.apply_view()
	game._update_ui()
	await _capture("play")
	for phase in [["dawn",6.0],["noon",12.0],["sunset",18.0],["blue_hour",19.5],["lit_shop",22.0]]:
		game._day_minutes = float(phase[1])*60
		view.apply_view()
		game._update_ui()
		await _capture(phase[0])
	game._day_minutes = 12*60
	view.depth = 0
	view.target_depth = 0
	view.zoom = .5
	view.apply_view()
	game._update_ui()
	await _capture("overview")
	view.yaw = deg_to_rad(24)
	view.pitch = deg_to_rad(29)
	view.apply_view()
	await _capture("rotated")
	view.reset_angle()
	game._day_minutes = 22 * 60
	view.apply_view()
	game._update_ui()
	await _capture("night")
	game._day_minutes = 9 * 60
	view.apply_view()
	game.get_node("GameInterface").hide()
	game.camera.position = Vector3(-12, 37, 91)
	game.camera.look_at(Vector3(0, 9, -8))
	game.camera.fov = 48
	await _capture("studio")
	game._day_minutes = 22*60
	game._pop_up.desk.set_time(game._day_minutes,game)
	await _capture("studio_lamp_on")
	game._pop_up.desk.lamp.light_energy = 0
	await _capture("studio_lamp_off")
	var light_delta: float = _mean("studio_lamp_on").get_luminance()-_mean("studio_lamp_off").get_luminance()
	if light_delta < .002:
		push_error("Task lamp must visibly illuminate the worktable")
		failures += 1
	game._day_minutes = 9*60
	game._pop_up.desk.set_time(game._day_minutes,game)
	game.camera.position = Vector3(28, 15, 33)
	game.camera.look_at(Vector3(27, 2, 4))
	game.camera.fov = 35
	game.camera.h_offset = 0
	game.camera.v_offset = 0
	await _capture("materials")
	game.camera.position = Vector3(0, 21, 9)
	game.camera.look_at(Vector3(-3, 19, -50))
	game.camera.fov = 58
	await _capture("window")
	var noon := _mean("noon")
	var night := _mean("lit_shop")
	var sunset := _mean("sunset")
	var blue := _mean("blue_hour")
	if noon.get_luminance() < night.get_luminance()*1.15 or blue.b/blue.r < sunset.b/sunset.r + .05:
		push_error("Rendered day/night or golden/blue-hour colors are insufficiently distinct")
		failures += 1
	print("WORKBENCH_PREVIEW noon=",noon.get_luminance()," night=",night.get_luminance()," lamp_delta=",light_delta," failures=",failures)
	game.free()
	quit(0 if failures == 0 else 1)
