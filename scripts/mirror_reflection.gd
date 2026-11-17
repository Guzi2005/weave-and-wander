extends Node3D

## A small shared-world reflection camera keeps the fitting-room mirror live.
## It is intentionally low resolution: the mirror is a dollhouse prop, but it
## still reflects the actual customer, garments, lamps and nearby wall.
var mirror_size := Vector2(.80, 2.50)
var max_reflection_distance := 28.0
var _viewport: SubViewport
var _camera: Camera3D
var _surface: MeshInstance3D
var reflection_enabled := true


func configure(size: Vector2) -> void:
	mirror_size = size
	if is_inside_tree():
		_build()


func _ready() -> void:
	# Follow the view controller (priority 200) in the same frame.
	process_priority = 210
	add_to_group("shop_mirrors")
	_build()


func _build() -> void:
	if is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.name = "MirrorReflectionViewport"
	_viewport.size = Vector2i(256, 800)
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	_viewport.world_3d = get_viewport().world_3d
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "MirrorReflectionCamera"
	_camera.cull_mask = 1 | 8
	_camera.near = .05
	_camera.far = 120.0
	_camera.current = true
	_viewport.add_child(_camera)

	_surface = MeshInstance3D.new()
	_surface.name = "ReflectiveGlass"
	var quad := QuadMesh.new()
	quad.size = mirror_size
	_surface.mesh = quad
	_surface.layers = 4
	_surface.position = Vector3(0, 0, .001)
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/mirror_surface.gdshader")
	material.set_shader_parameter("mirror_texture", _viewport.get_texture())
	_surface.material_override = material
	add_child(_surface)


func _process(_delta: float) -> void:
	# Live fitting-room reflection: refresh every visible frame, not at 12 Hz.
	# Street glass overrides this method and retains its staggered cadence.
	update_reflection()


func update_reflection() -> void:
	if not is_instance_valid(_camera) or not is_instance_valid(get_viewport()):
		return
	var source := get_viewport().get_camera_3d()
	if source == null or source == _camera:
		return
	var eye := to_local(source.global_position)
	var active := reflection_enabled and is_visible_in_tree() and eye.z > .05 and eye.length() <= max_reflection_distance
	if active:
		var bounds := AABB(Vector3(-mirror_size.x*.5,-mirror_size.y*.5,-.01),Vector3(mirror_size.x,mirror_size.y,.02))
		var world_bounds: AABB = global_transform * bounds
		for plane in source.get_frustum():
			if plane.distance_to(world_bounds.get_center()) > world_bounds.size.abs().dot(plane.normal.abs())*.5:
				active = false
				break
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED
	if not active:
		return
	# An off-axis frustum passes through the four physical mirror corners.
	# Copying the main camera FOV squeezes the entire room into the mirror.
	var reflected_eye := Vector3(eye.x, eye.y, -eye.z)
	_camera.global_transform = Transform3D(Basis(-global_basis.x, global_basis.y, -global_basis.z), to_global(reflected_eye))
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var near_plane := eye.z + .035
	var ratio := near_plane / eye.z
	_camera.set_frustum(mirror_size.y * ratio, Vector2(eye.x, -eye.y) * ratio, near_plane, near_plane + 90)

