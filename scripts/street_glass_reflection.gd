extends "res://scripts/mirror_reflection.gd"
## Low-strength planar reflection, independent of SSR (Compatibility renderer).
## Uses staggered round-robin cadence and distance degradation so 9 street
## panes do not render simultaneously on the same frame.
static var _next_slot := 0
var pane: MeshInstance3D
var cadence := 0
var _slot := 0

func _ready() -> void:
	_slot = _next_slot
	_next_slot = (_next_slot + 1) % 6
	cadence = _slot % 2
	max_reflection_distance = 36.0
	_build()

func _build() -> void:
	if is_instance_valid(_viewport) or pane == null: return
	super._build()
	_viewport.size = Vector2i(384, maxi(128,int(384*mirror_size.y/mirror_size.x)))
	_camera.cull_mask = 1 | 2 | 8
	_surface.hide()
	pane.layers = 4
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/street_glass.gdshader")
	mat.set_shader_parameter("reflection_texture",_viewport.get_texture())
	pane.material_override = mat

func _process(_delta: float) -> void:
	var amount: Variant = pane.material_override.get_shader_parameter("fold_amount")
	reflection_enabled = pane.is_visible_in_tree() and (amount == null or float(amount) > .98)
	var cam := get_viewport().get_camera_3d() if is_instance_valid(get_viewport()) else null
	var dist := global_position.distance_to(cam.global_position) if cam != null else 0.0
	var interval := 2 if dist < 20.0 else 6
	cadence = (cadence + 1) % interval
	if not reflection_enabled or dist > max_reflection_distance:
		if is_instance_valid(_viewport):
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if cadence != (_slot % interval):
		if is_instance_valid(_viewport):
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	update_reflection()
