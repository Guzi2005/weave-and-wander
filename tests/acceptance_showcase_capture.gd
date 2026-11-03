extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _shot(cam: Camera3D, from: Vector3, to: Vector3, fov: float, filename: String) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	for f in 10: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://captures/" + filename))
	print("SAVED: " + filename)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1600, 1000)

	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	for f in 12: await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)
	game._roof_controls.set_process(false)
	game._pop_up.set_process(false)
	game.get_node("GameInterface").hide()

	var cam: Camera3D = game.camera
	var desk: Node3D = game._pop_up.desk
	desk.set_time(10 * 60, game) # Day lighting

	# 1. 验证项：外层工作台 ABC 减面与裁切垫/钢尺程序化 Shader 刻度 (无立体框条)
	game._pop_up.apply_depth(3.0) # 打开页面
	await _shot(cam, desk.to_global(Vector3(12, 8, 14)), desk.to_global(Vector3(8, -1.1, 7)), 38, "acceptance_01_workbench_mat_shader.png")

	# 2. 验证项：外层工作台窗景 2 三角形折纸菱形树叶与低多边形资产全景
	await _shot(cam, desk.to_global(Vector3(0, 18, 40)), desk.to_global(Vector3(0, 7, -35)), 55, "acceptance_02_workbench_origami_garden.png")

	# 3. 验证项：街景 9 块玻璃实时平面反射 (分帧轮询与距离降级)
	game._pop_up.apply_depth(0.0) # 切到街景展开
	var streets := root.find_children("*", "Node3D", true, false).filter(func(n: Node) -> bool: return n.get_script() == load("res://scripts/street_scene.gd"))
	if not streets.is_empty():
		var street: Node3D = streets[0]
		street.set_exterior(1)
		await _shot(cam, street.to_global(Vector3(6, 4.5, 15)), street.to_global(Vector3(0, 2.0, 3.5)), 45, "acceptance_03_street_glass_reflection.png")

	# 4. 验证项：工坊生产区（染缸、织布机、工作台低耦合联动与 ASMR 特写区域）
	game._pop_up.apply_depth(1.0) # 工坊/店铺展开
	await _shot(cam, Vector3(-4.5, 3.2, 5.5), Vector3(-4.5, 1.2, 0.0), 50, "acceptance_04_workshop_production_flow.png")

	# 5. 验证项：店铺成衣展示区与布料收纳柜（24档网格池驱动布卷厚度与货架陈列）
	await _shot(cam, Vector3(2.5, 2.8, 4.8), Vector3(2.5, 1.0, -0.5), 50, "acceptance_05_shop_display_and_fabric_packages.png")

	print("ALL_ACCEPTANCE_CAPTURES_COMPLETED")
	game.free()
	quit(0)
