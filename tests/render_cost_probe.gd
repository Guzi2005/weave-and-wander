extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._set_speed(0)
	var lights = game.find_children("*","Light3D",true,false).filter(func(l):return l.shadow_enabled)
	var desk = game._pop_up.desk.get_node("PBRWorktable")
	for mode in ["baseline","no_shadows","without_studio","restored"]:
		if mode == "no_shadows" or mode == "restored":
			for l in lights: l.shadow_enabled = mode == "restored"
		desk.visible = mode != "without_studio"
		for i in 12: await process_frame
		var start := Time.get_ticks_usec()
		for i in 30: await process_frame
		print("PROBE ",mode," ms=",snappedf((Time.get_ticks_usec()-start)/30000.0,.1)," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	game.free()
	quit()
