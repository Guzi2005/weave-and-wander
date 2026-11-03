extends CanvasLayer
## Disposable visual experiment; never edits materials, models or saved data.
var game: Node
var enabled := false
var previous_debug := Viewport.DEBUG_DRAW_DISABLED
var button: Button
var perspective_strength := 0.0
var controls: HBoxContainer
var value_label: Label
var original_shaders: Dictionary = {}
var original_far := 320.0
const FLAT_LIGHT := """
    float facing = dot(normalize(NORMAL), normalize(LIGHT));
    float lit = smoothstep(0.12, 0.18, facing);
    vec3 ink_shade = mix(vec3(0.43, 0.50, 0.64), vec3(1.0), lit);
    // Group both cast shadows and lamp falloff into broad, soft-edged ink shapes.
    float shadow = 0.36 * smoothstep(0.06, 0.10, ATTENUATION)
                 + 0.64 * smoothstep(0.48, 0.54, ATTENUATION);
    DIFFUSE_LIGHT += ink_shade * shadow * LIGHT_COLOR / PI;
"""

func _ready() -> void:
	layer = 30
	process_priority = 100
	button = Button.new()
	button.text = "A · 原版透视"
	button.tooltip_text = "切换 A/B 画风（F8）"
	button.position = Vector2(game.get_viewport().get_visible_rect().size.x*.5-79,18)
	button.custom_minimum_size = Vector2(158,38)
	button.toggle_mode = true
	button.pressed.connect(func(): set_flat(not enabled))
	add_child(button)
	original_far = game.camera.far
	controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation",10)
	var label := Label.new()
	label.text = "透视"
	controls.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(150,28)
	slider.tooltip_text = "0：正交；100：原版透视力度"
	slider.value_changed.connect(func(v):
		perspective_strength = v/100.0
		value_label.text = "%d%%" % v
		game._view_controls.apply_view())
	controls.add_child(slider)
	value_label = Label.new()
	value_label.text = "0%"
	value_label.custom_minimum_size.x = 48
	controls.add_child(value_label)
	add_child(controls)
	controls.hide()
	if "--flat-ab" in OS.get_cmdline_user_args(): set_flat(true)

func set_flat(value: bool) -> void:
	if value == enabled: return
	if value: previous_debug = game.get_viewport().debug_draw
	enabled = value
	game.get_viewport().debug_draw = Viewport.DEBUG_DRAW_DISABLED if value else previous_debug
	_set_lighting(value)
	controls.visible = value
	game.camera.far = original_far
	game.camera.projection = Camera3D.PROJECTION_ORTHOGONAL if value else Camera3D.PROJECTION_PERSPECTIVE
	button.text = "B · 扁平光照" if value else "A · 原版透视"
	button.set_pressed_no_signal(value)
	game._view_controls.apply_view()

func _process(_delta: float) -> void:
	button.position.x = game.get_viewport().get_visible_rect().size.x*.5-79
	controls.position = Vector2(maxf(8,button.position.x-55),62)

func apply_camera() -> void:
	if not enabled: return
	var camera: Camera3D = game.camera
	var base_fov := camera.fov
	var base_distance := camera.size / (2.0*tan(deg_to_rad(base_fov)*.5))
	if is_instance_valid(game._view_controls.follow_target):
		base_distance = maxf(.15,camera.global_position.distance_to(game._view_controls.follow_target.global_position + Vector3(0,1.4,0)))
		camera.size = 2.0*base_distance*tan(deg_to_rad(base_fov)*.5)
	if perspective_strength == 0.0:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.far = original_far
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = maxf(1.0,base_fov*perspective_strength)
		var distance := camera.size / (2.0*tan(deg_to_rad(camera.fov)*.5))
		camera.position += camera.basis.z * (distance-base_distance)
		camera.far = original_far + maxf(0,distance-base_distance)

func _set_lighting(value: bool) -> void:
	if not value:
		for shader in original_shaders: shader.code = original_shaders[shader]
		original_shaders.clear()
		return
	# Keep original pigment, grain, folds, maps and emission; replace only light response.
	for name in ["doll_costume","doll_lining","doll_volume","doll_print","room_paper","paper","material_cloth","upholstery","wound_thread","studio_color_blocks"]:
		var shader := load("res://shaders/%s.gdshader" % name) as Shader
		original_shaders[shader] = shader.code
		var source: String = shader.code.replace("unshaded, ", "")
		if source.contains("void light() {"):
			var start := source.find("void light() {")
			var end := source.find("{",start)+1
			var depth := 1
			while depth > 0 and end < source.length():
				if source[end] == "{": depth += 1
				elif source[end] == "}": depth -= 1
				end += 1
			source = source.substr(0,start)+"void light() {\n"+FLAT_LIGHT+"\n}"+source.substr(end)
		else:
			source += "\nvoid light() {\n"+FLAT_LIGHT+"\n}\n"
		shader.code = source

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		set_flat(not enabled)
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_set_lighting(false)
	if enabled and is_instance_valid(game):
		game.get_viewport().debug_draw = previous_debug
