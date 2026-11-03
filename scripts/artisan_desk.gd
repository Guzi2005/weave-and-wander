extends Node3D

const MODEL = preload("res://assets/workbench/artisan_workbench.glb")
const OUTER_WORLD_LAYER := 2
const STUDIO_SETBACK := 10.0
const COLOR_BLOCKS = preload("res://shaders/studio_color_blocks.gdshader")
const DayCycle = preload("res://scripts/studio_day_cycle.gd")
var _page_layers: Array[Node3D] = []
var glass_panes: Array[MeshInstance3D] = []
var _last_time := -1.0
var lamp: SpotLight3D
var window_light: DirectionalLight3D
var _bulb_materials: Array[ShaderMaterial] = []
var _customer_lights: Array[OmniLight3D] = []
var shop_open := true
var _front_leaf: Node3D
var _garden_props: Array[Node3D] = []
var _far_garden_props: Array[Node3D] = []


func _ready() -> void:
	var model := MODEL.instantiate()
	model.name = "PBRWorktable"
	model.position.z = -STUDIO_SETBACK
	add_child(model)
	var adjusted: Dictionary = {}
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		mesh.layers = OUTER_WORLD_LAYER
		if mesh is MeshInstance3D:
			var mesh_name := String(mesh.name)
			var parent_name := String(mesh.get_parent().name) if mesh.get_parent() != null else ""
			if "MatInk" in mesh_name or "CuttingGrid" in mesh_name or "RulerTick" in mesh_name:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.visibility_range_end = 95.0
			elif "GardenFern" in parent_name or "GardenTreeFar" in parent_name:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mesh.visibility_range_end = 185.0
			for surface in mesh.mesh.get_surface_count():
				var mat: Material = mesh.get_active_material(surface)
				if mat is StandardMaterial3D:
					if "desk_lamp" in mat.resource_name:
						# The bulb is inside a closed scan; the spotlight supplies its aperture.
						mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					if not adjusted.has(mat):
						adjusted[mat] = _studio_material(mat)
					mesh.set_surface_override_material(surface, adjusted[mat])
	for plant in model.find_children("Garden*", "Node3D", true, false):
		if "Tree" in plant.name or "Fern" in plant.name:
			_garden_props.append(plant)
			if "Far" in plant.name or "Fern" in plant.name:
				_far_garden_props.append(plant)
	_build_book()
	_build_window_light()
	_build_glass()
	_build_customer_lights()


func _studio_material(source: StandardMaterial3D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = COLOR_BLOCKS
	mat.set_shader_parameter("base_color", source.albedo_color)
	mat.set_shader_parameter("normal_strength", minf(source.normal_scale, .28))
	mat.set_shader_parameter("roughness", maxf(source.roughness, .3))
	mat.set_shader_parameter("metalness", source.metallic)
	if "Walnut" in source.resource_name:
		# Matte walnut should read as quiet, deep wood rather than orange varnish.
		mat.set_shader_parameter("base_color", Color(.57,.56,.55))
		mat.set_shader_parameter("wood_mode", true)
		mat.set_shader_parameter("texture_softening", 1.15)
		mat.set_shader_parameter("roughness", .88)
		mat.set_shader_parameter("metalness", 0.0)
		mat.set_shader_parameter("highlight_strength", .008)
	if "CuttingMat" in source.resource_name:
		mat.set_shader_parameter("cutting_mat_grid", true)
	if "RulerSteel" in source.resource_name:
		mat.set_shader_parameter("ruler_ticks", true)
	if "leaves" in source.resource_name.to_lower() or "fern" in source.resource_name.to_lower():
		mat.set_shader_parameter("foliage_mode", true)
		mat.set_shader_parameter("texture_softening", 2.5)
		mat.set_shader_parameter("normal_strength", .08)
		mat.set_shader_parameter("roughness", .94)
		mat.set_shader_parameter("highlight_strength", 0.0)
		mat.set_shader_parameter("painted_leaf", "PaintedGardenLeaves" in source.resource_name)
	if source.albedo_texture != null:
		mat.set_shader_parameter("albedo_map", source.albedo_texture)
	mat.set_shader_parameter("has_normal", source.normal_enabled and source.normal_texture != null)
	mat.set_shader_parameter("normal_map", source.normal_texture)
	if "leaves" in source.resource_name.to_lower() or "fern" in source.resource_name.to_lower():
		mat.set_shader_parameter("has_normal", false)
	if "desk_lamp" in source.resource_name and "light" in source.resource_name:
		_bulb_materials.append(mat)
	return mat


func _block(label: String, dimensions: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .88
	node.material_override = mat
	node.position = at
	node.layers = OUTER_WORLD_LAYER
	add_child(node)
	return node


func _build_book() -> void:
	_block("BookCover", Vector3(45.2, .22, 21.4), Vector3(0, -1.08, -6.9), Color("455f65"))
	for i in 5:
		var page := _block("StoredPaperPage%d" % i, Vector3(44.7 - i * .08, .085, 21.1 - i * .02), Vector3(0, -.89 + i * .12, -6.75), [Color("ede9dc"), Color("cedad2"), Color("e3c9c9")][i % 3])
		_page_layers.append(page)
	_block("TopBoard", Vector3(44.2, .17, 20.9), Vector3(0, -.28, -6.65), Color("e5e2d8"))
	_front_leaf = Node3D.new()
	_front_leaf.name = "StreetSupportLeaf"
	_front_leaf.position = Vector3(0, 0, 3.8)
	add_child(_front_leaf)
	for index in 7:
		var color := Color("455f65") if index == 0 else Color("e5e2d8")
		var leaf := _block("StreetPaperLayer%d" % index, Vector3(44.2, .12, 9.65), Vector3(0, -1.04 + index * .12, 8.625), color)
		leaf.reparent(_front_leaf, true)


func _build_window_light() -> void:
	window_light = DirectionalLight3D.new()
	window_light.name = "RealWorldWindowSun"
	window_light.light_cull_mask = OUTER_WORLD_LAYER
	window_light.shadow_caster_mask = OUTER_WORLD_LAYER
	window_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	window_light.shadow_enabled = true
	window_light.directional_shadow_max_distance = 170
	window_light.shadow_bias = .025
	window_light.shadow_normal_bias = .8
	add_child(window_light)
	lamp = SpotLight3D.new()
	lamp.name = "EveningDeskLamp"
	var emitter: Node3D = find_child("TaskLampEmitter", true, false)
	lamp.position = to_local(emitter.global_position) if emitter != null else Vector3(27.3, 11.3, -11.45)
	lamp.light_color = Color("ffd097")
	lamp.light_cull_mask = OUTER_WORLD_LAYER | 1 | 8
	lamp.spot_range = 52
	lamp.spot_angle = 42
	lamp.spot_angle_attenuation = .7
	lamp.spot_attenuation = .6
	lamp.shadow_enabled = true
	lamp.shadow_bias = .025
	add_child(lamp)
	lamp.look_at(to_global(Vector3(16, -1, 8 - STUDIO_SETBACK)), Vector3.UP)


func _build_glass() -> void:
	for x in [-14.6, 14.6]:
		var pane := MeshInstance3D.new()
		pane.name = "WindowGlassLeft" if x < 0 else "WindowGlassRight"
		var mesh := QuadMesh.new()
		mesh.size = Vector2(28.55, 34.65)
		pane.mesh = mesh
		pane.position = Vector3(x, 23.45, -18.25 - STUDIO_SETBACK)
		pane.layers = OUTER_WORLD_LAYER
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glass := ShaderMaterial.new()
		glass.shader = preload("res://shaders/window_glass.gdshader")
		pane.material_override = glass
		add_child(pane)
		glass_panes.append(pane)


func _build_customer_lights() -> void:
	# These are invisible fill sources, not extra ceiling fixtures. They keep
	# browsing, fitting, mirror and checkout readable while the shop is open.
	for index in 3:
		var fill := OmniLight3D.new()
		fill.name = "CustomerAreaFill%d" % index
		fill.position = Vector3((index - 1) * 14.4, 2.35, .65)
		fill.omni_range = 8.6
		fill.omni_attenuation = .72
		fill.light_color = Color("ffe2b2")
		fill.light_cull_mask = 1 | 8
		fill.shadow_enabled = false
		add_child(fill)
		_customer_lights.append(fill)


func set_shop_open(value: bool) -> void:
	shop_open = value
	_last_time = -INF


func set_page(depth: float) -> void:
	for i in _page_layers.size():
		_page_layers[i].position.y = -.89 + i * .12 + depth * .012
	var closed := smoothstep(1.05, 1.65, depth)
	_front_leaf.rotation.x = closed * PI * .5
	_front_leaf.visible = closed < .999
	for light in get_tree().get_nodes_in_group("shop_lamps"):
		light.visible = depth < 1.18
	for light in _customer_lights:
		light.visible = depth < 2.4
	for prop in _far_garden_props:
		if is_instance_valid(prop):
			prop.visible = depth < 1.85


func set_time(minutes: float, controller: Node) -> void:
	if absf(minutes - _last_time) < .25:
		return
	_last_time = minutes
	var phase := DayCycle.sample(minutes)
	var hour: float = phase.hour
	# Both scales share the sky; separate key lights preserve the miniature's softer contrast.
	var sun: DirectionalLight3D = controller.get_node("SoftWindowLight")
	sun.light_cull_mask = 1 | 8
	sun.light_energy = phase.sun_energy * .48
	sun.light_color = phase.sun
	var altitude := maxf(10, sin(clampf((hour-6)/13, 0, 1)*PI)*58)
	var azimuth := 135 + clampf(hour-6,0,13)*5.0
	if hour < 6 or hour > 19:
		var night_progress := fposmod(hour-19,24.0)/11.0
		azimuth = lerpf(200,135,smoothstep(0,1,night_progress))
		altitude = 10 + sin(night_progress*PI)*20
	sun.rotation_degrees = Vector3(-altitude, azimuth, 0)
	sun.directional_shadow_max_distance = 75
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_caster_mask = 1 | 8
	var fill: OmniLight3D = controller.get_node("CoolFill")
	fill.light_cull_mask = 1 | 8
	fill.light_color = phase.ambient
	fill.light_energy = phase.ambient_energy * .1
	window_light.light_energy = phase.sun_energy
	window_light.light_color = phase.sun
	window_light.rotation_degrees = sun.rotation_degrees
	var environment: Environment = controller.get_node("WorldEnvironment").environment
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_energy = phase.ambient_energy
	environment.ambient_light_color = phase.ambient
	if environment.sky == null:
		var sky := Sky.new()
		var sky_mat := ProceduralSkyMaterial.new()
		sky.sky_material = sky_mat
		environment.sky = sky
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = phase.sky
	sky_material.sky_horizon_color = phase.horizon
	sky_material.ground_horizon_color = phase.horizon
	sky_material.ground_bottom_color = Color("526451").lerp(Color("192a3b"), phase.lamps)
	lamp.light_energy = lerpf(.05, 3.8, phase.lamps)
	lamp.shadow_enabled = phase.lamps > .1
	for material in _bulb_materials:
		material.set_shader_parameter("lamp_glow", phase.lamps * 1.8)
	for indoor in get_tree().get_nodes_in_group("shop_lamps"):
		var room_id: String = controller._navigation.room_at(indoor.global_position)
		var enabled: bool = controller._room_lights.get(room_id, false)
		indoor.light_energy = 1.18 if enabled else 0.0
		if room_id == "workshop" and enabled:
			indoor.light_energy = .20
		var diffuser: MeshInstance3D = indoor.get_parent().get_node("Diffuser")
		diffuser.material_override.set_shader_parameter("lamp_glow", .78 if enabled else 0.0)
	for customer_fill in _customer_lights:
		customer_fill.light_energy = 1.05 if shop_open else 0.0
		if customer_fill.global_position.x < -7.2 and shop_open:
			customer_fill.light_energy = .16
