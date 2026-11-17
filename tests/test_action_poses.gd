extends SceneTree

const OrigDoll = preload("res://scripts/volume_doll.gd")
const FullDoll = preload("res://scripts/experimental_full_body_doll.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(0)
		return

	root.size = Vector2i(1800, 900)
	root.content_scale_size = root.size

	var stage := Node3D.new()
	root.add_child(stage)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#edf1f2")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#f4f7f8")
	env.environment.ambient_light_energy = 0.42
	stage.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.5
	light.shadow_enabled = true
	stage.add_child(light)

	var floor_m := PlaneMesh.new()
	floor_m.size = Vector2(30, 20)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#cfdbe0")
	floor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_inst := MeshInstance3D.new()
	floor_inst.mesh = floor_m
	floor_inst.material_override = floor_mat
	stage.add_child(floor_inst)

	# 4 clothed dolls doing distinct large-amplitude action poses:
	# 1. Doll 1 (Blue Dress): Dynamic Running Leap / Sprint (大步奔跑跃步)
	# 2. Doll 2 (Ukrainian Outfit): High Folk Dance / Hopak Arms Raised (乌克兰欢庆跳跃舞)
	# 3. Doll 3 (Ukrainian Outfit): Grounded Deep Seated on Wooden Bench (长凳深坐屈膝90°)
	# 4. Doll 4 (Golden Ribbon Dress): High Reach / Dynamic Stretch (探身采摘/大幅度伸展)

	var doll1 := FullDoll.new()
	stage.add_child(doll1)
	doll1.configure({"outfit": 0, "hair": 0, "palette": 0})
	doll1.position = Vector3(-2.25, 0, 0)

	var doll2 := FullDoll.new()
	stage.add_child(doll2)
	doll2.configure({"outfit": 0, "hair": 3, "palette": 0, "shoe_style": 1})
	doll2.wear_ukrainian_set()
	doll2.position = Vector3(-0.75, 0, 0)

	var doll3 := FullDoll.new()
	stage.add_child(doll3)
	doll3.configure({"outfit": 0, "hair": 3, "palette": 0, "shoe_style": 1})
	doll3.wear_ukrainian_set()
	doll3.position = Vector3(0.75, 0, 0)

	# Natural wooden bench grounded on the floor under Doll 3:
	var stool := Node3D.new()
	stool.position = Vector3(0.75, 0, 0)
	stage.add_child(stool)
	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#8B5A2B")
	wood_mat.roughness = 0.65
	var seat_m := BoxMesh.new()
	seat_m.size = Vector3(0.56, 0.05, 0.42)
	var seat_inst := MeshInstance3D.new()
	seat_inst.mesh = seat_m
	seat_inst.material_override = wood_mat
	seat_inst.position = Vector3(0, 0.445, -0.04)
	stool.add_child(seat_inst)
	for dx in [-0.22, 0.22]:
		for dz in [-0.20, 0.12]:
			var leg_m := BoxMesh.new()
			leg_m.size = Vector3(0.05, 0.42, 0.05)
			var leg_inst := MeshInstance3D.new()
			leg_inst.mesh = leg_m
			leg_inst.material_override = wood_mat
			leg_inst.position = Vector3(dx, 0.21, dz)
			stool.add_child(leg_inst)

	var doll4 := FullDoll.new()
	stage.add_child(doll4)
	doll4.configure({"outfit": 0, "hair": 0, "palette": 1})
	doll4.position = Vector3(2.25, 0, 0)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(0, 1.40, 7.0)
	stage.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.30, 0))
	camera.current = true

	# Wait for deferred build and rig binding
	for frame in 8:
		await process_frame

	# Apply Action Poses:
	# Pose 1: Large-Amplitude Running Leap (大步奔跑跃步)
	doll1.rig.animate(0, 0, "idle", 0)
	doll1.rig._rotate("Spine", Vector3(0.14, 0, 0.03))
	doll1.rig._rotate("Head", Vector3(-0.08, 0, 0))
	doll1.rig._rotate("ThighL", Vector3(-0.54, 0, -0.04))
	doll1.rig._rotate("ShinL", Vector3(0.60, 0, 0))
	doll1.rig._rotate("FootL", Vector3(-0.10, 0, 0))
	doll1.rig._rotate("ThighR", Vector3(0.42, 0, 0.04))
	doll1.rig._rotate("ShinR", Vector3(0.48, 0, 0))
	doll1.rig._rotate("FootR", Vector3(0.24, 0, 0))
	doll1.rig._rotate("UpperArmL", Vector3(0.52, -0.15, -0.20))
	doll1.rig._rotate("ForearmL", Vector3(-0.45, 0, 0))
	doll1.rig._rotate("UpperArmR", Vector3(-0.68, 0.18, 0.28))
	doll1.rig._rotate("ForearmR", Vector3(-0.75, 0, 0))
	doll1.rig._offset("HemFront", Vector3(0, 0.06, 0.24))
	doll1.rig._offset("HemBack", Vector3(0, 0.04, -0.22))
	doll1.rig._offset("HemL", Vector3(-0.03, 0, 0.06))
	doll1.rig._offset("HemR", Vector3(0.03, 0, -0.06))
	doll1.rig.skeleton.force_update_all_bone_transforms()

	# Pose 2: Joyful Ukrainian Folk Dance / Hopak Arms Raised (欢庆舞蹈/双臂高举)
	doll2.rig.animate(0, 0, "idle", 0)
	doll2.rig._rotate("Spine", Vector3(-0.05, 0.04, 0.04))
	doll2.rig._rotate("Head", Vector3(-0.08, -0.08, 0.03))
	doll2.rig._rotate("UpperArmL", Vector3(-1.32, -0.22, -0.55))
	doll2.rig._rotate("ForearmL", Vector3(-0.65, 0, 0.16))
	doll2.rig._rotate("UpperArmR", Vector3(-1.28, 0.25, 0.58))
	doll2.rig._rotate("ForearmR", Vector3(-0.60, 0, -0.18))
	doll2.rig._rotate("ThighL", Vector3(-0.42, 0, -0.08))
	doll2.rig._rotate("ShinL", Vector3(0.58, 0, 0))
	doll2.rig._rotate("FootL", Vector3(-0.16, 0, 0))
	doll2.rig._rotate("ThighR", Vector3(0.10, 0, 0.05))
	doll2.rig._rotate("ShinR", Vector3(0.04, 0, 0))
	doll2.rig._offset("HemFront", Vector3(0, 0.04, 0.15))
	doll2.rig._offset("HemL", Vector3(-0.04, 0, 0.03))
	doll2.rig.skeleton.force_update_all_bone_transforms()

	# Pose 3: Grounded Deep Seated 90° Knee Bend on Bench (长凳深坐屈膝90°)
	# Hips drop to seat height (0.47)
	doll3.rig.animate(0, 0, "idle", 0)
	doll3.rig._offset("Hips", Vector3(0, -0.63, 0))
	doll3.rig._rotate("Spine", Vector3(-0.02, 0, 0))
	doll3.rig._rotate("Head", Vector3(-0.04, 0.04, 0))
	# Thighs horizontal forward 90 degrees
	doll3.rig._rotate("ThighL", Vector3(-PI * 0.50, 0, -0.03))
	doll3.rig._rotate("ThighR", Vector3(-PI * 0.50, 0, 0.03))
	# Shins vertical downward 90 degrees, feet flat on the floor
	doll3.rig._rotate("ShinL", Vector3(PI * 0.50, 0, 0))
	doll3.rig._rotate("ShinR", Vector3(PI * 0.50, 0, 0))
	doll3.rig._rotate("FootL", Vector3(0, 0, 0))
	doll3.rig._rotate("FootR", Vector3(0, 0, 0))
	# Gentle hands resting on lap
	doll3.rig._rotate("UpperArmL", Vector3(-0.42, -0.10, -0.10))
	doll3.rig._rotate("ForearmL", Vector3(-0.85, 0, 0.25))
	doll3.rig._rotate("UpperArmR", Vector3(-0.42, 0.10, 0.10))
	doll3.rig._rotate("ForearmR", Vector3(-0.85, 0, -0.25))
	# Skirt drapes over lap and down to the stool
	doll3.rig._offset("HemFront", Vector3(0, 0.42, 0.16))
	doll3.rig._offset("HemBack", Vector3(0, 0.46, 0.06))
	doll3.rig._offset("HemL", Vector3(-0.02, 0.42, 0.10))
	doll3.rig._offset("HemR", Vector3(0.02, 0.42, 0.10))
	doll3.rig.skeleton.force_update_all_bone_transforms()

	# Pose 4: Dynamic Reaching / Apple Picking Stretch (高处采摘/优雅大幅度伸展)
	doll4.rig.animate(0, 0, "stocking", 2.2)
	doll4.rig._rotate("Spine", Vector3(0.18, 0.10, -0.12))
	doll4.rig._rotate("Head", Vector3(-0.20, 0.10, -0.05))
	doll4.rig._rotate("UpperArmR", Vector3(-1.42, 0.18, 0.32))
	doll4.rig._rotate("ForearmR", Vector3(-0.35, 0, 0.06))
	doll4.rig._rotate("UpperArmL", Vector3(0.48, -0.18, -0.30))
	doll4.rig._rotate("ForearmL", Vector3(-0.38, 0, -0.12))
	doll4.rig._rotate("ThighR", Vector3(-0.14, 0, 0.04))
	doll4.rig._rotate("ShinR", Vector3(0.20, 0, 0))
	doll4.rig._rotate("ThighL", Vector3(0.36, 0, -0.12))
	doll4.rig._rotate("ShinL", Vector3(0.32, 0, 0))
	doll4.rig._rotate("FootL", Vector3(0.24, 0, 0))
	doll4.rig._offset("HemBack", Vector3(0, 0, -0.10))
	doll4.rig._offset("HemFront", Vector3(0, 0, 0.08))
	doll4.rig.skeleton.force_update_all_bone_transforms()

	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw

	var img_front := root.get_texture().get_image()
	if img_front != null:
		DirAccess.make_dir_recursive_absolute("res://captures/anatomy_inspection")
		img_front.save_png("res://captures/anatomy_inspection/action_poses_front.png")
		print("ACTION_FRONT_SUCCESS")

	# Rotate dolls to 3/4 quarter angle (PI * 0.25)
	for d in [doll1, doll2, doll3, doll4]:
		d.body_rig.rotation.y = PI * 0.25
	stool.rotation.y = PI * 0.25

	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var img_quarter := root.get_texture().get_image()
	if img_quarter != null:
		img_quarter.save_png("res://captures/anatomy_inspection/action_poses_quarter.png")
		print("ACTION_QUARTER_SUCCESS")

	# Rotate dolls to side profile (PI * 0.50)
	for d in [doll1, doll2, doll3, doll4]:
		d.body_rig.rotation.y = PI * 0.50
	stool.rotation.y = PI * 0.50

	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var img_side := root.get_texture().get_image()
	if img_side != null:
		img_side.save_png("res://captures/anatomy_inspection/action_poses_side.png")
		print("ACTION_SIDE_SUCCESS")

	quit(0)
