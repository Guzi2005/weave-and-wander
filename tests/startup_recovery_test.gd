extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._view_controls.follow(game.staff[0],true)
	game._speed = 0.0
	game._view_controls.pan_offset = Vector2(100,100)
	game._view_controls.pitch = -1.0
	game._recover_startup_view()
	var initial_time: float = game._day_minutes
	await create_timer(.2).timeout
	var ok: bool = game._speed == 1.0 and game._view_controls.follow_target == null and game.camera.current
	ok = ok and game.camera.position.is_finite() and game.camera.position.y > 5.0
	ok = ok and game._view_controls.pan_offset == Vector2.ZERO and game._day_minutes > initial_time
	print("STARTUP_RECOVERY_TEST passed=",ok," camera=",game.camera.position," clock_advanced=",game._day_minutes > initial_time)
	game.free()
	quit(0 if ok else 1)
