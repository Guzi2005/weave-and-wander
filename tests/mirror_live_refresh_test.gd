extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.make_current()
	var mirror = load("res://scripts/mirror_reflection.gd").new()
	root.add_child(mirror)
	mirror.set_process(false)
	for frame in 12:
		camera.position.x = float(frame) * .01
		mirror._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mirror._process(1.0 / 120.0)
		assert(mirror._viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Mirror skipped a visible frame")
		assert(absf(mirror._camera.global_position.x - camera.position.x) < .001)
	mirror.reflection_enabled = false
	mirror._process(.001)
	assert(mirror._viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	print("MIRROR_LIVE_REFRESH_TEST passed: 12 successive 120-Hz steps, camera tracking, disabled culling")
	mirror.free()
	camera.free()
	quit()
