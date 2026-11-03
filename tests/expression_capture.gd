extends SceneTree

const Doll = preload("res://scripts/volume_doll.gd")
const States = preload("res://scripts/doll_expressions.gd")
var models: Array[VolumeDoll] = []
var world: Node3D
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This capture requires the GPU renderer.")
		quit(1)
		return
	root.size = Vector2i(1600,900)
	root.content_scale_size = root.size
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("e7eeeb")
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.3
	world.add_child(camera)
	camera.position = Vector3(0,2.0,12)
	camera.current = true
	var ui := CanvasLayer.new()
	world.add_child(ui)
	for index in 8:
		var doll := Doll.new()
		doll.configure({"hair":0,"outfit":0,"palette":0,"skin":1})
		world.add_child(doll)
		doll.position = Vector3((index%4-1.5)*1.42,.47 if index<4 else -.99,0)
		doll.get_node("GroundContact").hide()
		for part in doll.rig.meshes:
			if part.get_meta("semantic","") not in ["head","hair"]:
				part.hide()
		doll.set_expression(States.STATE_NAMES[mini(index,6)],0)
		doll._work_phase = 2
		doll.simulate(.01,1)
		doll.rig.animate(0,0,"idle",0)
		var controller: States = doll.expression_controller()
		doll.rig.look_toward(0,0,Vector2.ZERO,controller.get_eye_closure(),controller.get_eye_offset(-1),controller.get_eye_offset(1))
		if index == 7:
			doll.body_rig.rotation.y = PI*.37
		models.append(doll)
		var label := Label.new()
		label.text = States.STATE_NAMES[index].capitalize() if index<7 else "Asleep / profile"
		label.position = Vector2((index%4)*400,380 if index<4 else 778)
		label.size = Vector2(400,50)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",24)
		label.add_theme_color_override("font_color",Color("394c4c"))
		ui.add_child(label)
	var gallery: Image = await capture("expressions_20261021")
	var escaped_pixels := 0
	for y in range(16,120,2):
		for x in range(0,1600,2):
			if gallery.get_pixel(x,y).get_luminance() < .3:
				escaped_pixels += 1
	if escaped_pixels > 4:
		failures.append("Facial features escaped above the rendered heads.")
	for index in 8:
		var ink := 0
		var bounds := Rect2i((index%4)*400,140 if index<4 else 535,400,210)
		for y in range(bounds.position.y,bounds.end.y,4):
			for x in range(bounds.position.x,bounds.end.x,4):
				if gallery.get_pixel(x,y).get_luminance() < .3: ink += 1
		if ink < 100:
			failures.append("Expression portrait is blank: %d"%index)
	var probe := models[0]
	probe.set_expression("asleep",.6)
	var images: Array[Image] = []
	for frame in 37:
		probe.expression_controller().update(1.0/60)
		probe.rig.animate(0,0,"idle",0)
		var controller: States = probe.expression_controller()
		probe.rig.look_toward(.12,0,Vector2(.2,0),controller.get_eye_closure(),controller.get_eye_offset(-1),controller.get_eye_offset(1))
		if frame in [0,18,36]:
			images.append(await capture("expression_transition_%02d"%frame))
	if images[0].get_data() == images[1].get_data() or images[1].get_data() == images[2].get_data():
		failures.append("Rendered expression transition did not change pixels.")
	for failure in failures: push_error(failure)
	print("EXPRESSION_CAPTURE frames=4 failures=",failures.size())
	world.free()
	quit(0 if failures.is_empty() else 1)


func capture(label: String) -> Image:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.save_png("res://captures/%s.png"%label) != OK:
		failures.append("Could not save "+label)
	return image
