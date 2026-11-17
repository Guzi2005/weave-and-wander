extends RefCounted
## Preview units: pace is a walk-cycle multiplier; spin speed is degrees/second.
var mode := "idle"
var pace := 1.0
var spin_speed := 35.0
var nonuniformity := 0.0
var paused := false
var elapsed := 0.0
var walk_phase := 0.0
var angle := 0.0
var angular_velocity := 0.0

func step(delta: float) -> void:
	if paused or delta <= 0.0 or not is_finite(delta):
		return
	elapsed += delta
	if mode == "walk":
		walk_phase += delta * TAU * clampf(pace, .25, 2.0)
	angular_velocity = spin_speed * (1.0 + clampf(nonuniformity, 0.0, .9) * sin(elapsed * TAU / 4.0)) if mode == "spin" else 0.0
	if mode == "spin":
		angle = fposmod(angle + deg_to_rad(angular_velocity) * delta, TAU)

func reset() -> void:
	elapsed = 0.0
	walk_phase = 0.0
	angle = 0.0
	angular_velocity = 0.0

func apply(doll: Node3D) -> void:
	if mode == "run":
		var cycle := sin(elapsed * 4.5)
		doll.rig.animate(0, 0, "idle", 0)
		doll.rig._rotate("Spine", Vector3(0.14, 0, cycle * 0.04))
		doll.rig._rotate("Head", Vector3(-0.08, 0, -cycle * 0.02))
		doll.rig._rotate("ThighL", Vector3(-cycle * 0.54, 0, -0.04))
		doll.rig._rotate("ShinL", Vector3(maxf(cycle * 0.60, 0.0), 0, 0))
		doll.rig._rotate("FootL", Vector3(-cycle * 0.10, 0, 0))
		doll.rig._rotate("ThighR", Vector3(cycle * 0.42, 0, 0.04))
		doll.rig._rotate("ShinR", Vector3(maxf(-cycle * 0.48, 0.0), 0, 0))
		doll.rig._rotate("FootR", Vector3(cycle * 0.24, 0, 0))
		doll.rig._rotate("UpperArmL", Vector3(cycle * 0.52, -0.15, -0.20))
		doll.rig._rotate("ForearmL", Vector3(-0.45, 0, 0))
		doll.rig._rotate("UpperArmR", Vector3(-cycle * 0.68, 0.18, 0.28))
		doll.rig._rotate("ForearmR", Vector3(-0.75, 0, 0))
		doll.rig._offset("HemFront", Vector3(0, 0.06, absf(cycle) * 0.24))
		doll.rig._offset("HemBack", Vector3(0, 0.04, -absf(cycle) * 0.22))
		doll.rig.skeleton.force_update_all_bone_transforms()
	elif mode == "dance":
		var wave := sin(elapsed * 3.0)
		doll.rig.animate(0, 0, "idle", 0)
		doll.rig._rotate("Spine", Vector3(-0.05 + wave * 0.02, 0.04, 0.04))
		doll.rig._rotate("Head", Vector3(-0.08, -0.08 + wave * 0.04, 0.03))
		doll.rig._rotate("UpperArmL", Vector3(-1.32 + wave * 0.08, -0.22, -0.55))
		doll.rig._rotate("ForearmL", Vector3(-0.65, 0, 0.16))
		doll.rig._rotate("UpperArmR", Vector3(-1.28 - wave * 0.08, 0.25, 0.58))
		doll.rig._rotate("ForearmR", Vector3(-0.60, 0, -0.18))
		doll.rig._rotate("ThighL", Vector3(-0.42 + wave * 0.10, 0, -0.08))
		doll.rig._rotate("ShinL", Vector3(0.58, 0, 0))
		doll.rig._rotate("FootL", Vector3(-0.16, 0, 0))
		doll.rig._rotate("ThighR", Vector3(0.10, 0, 0.05))
		doll.rig._rotate("ShinR", Vector3(0.04, 0, 0))
		doll.rig._offset("HemFront", Vector3(0, 0.04, 0.15))
		doll.rig._offset("HemL", Vector3(-0.04, 0, 0.03))
		doll.rig.skeleton.force_update_all_bone_transforms()
	elif mode == "reach":
		var reach_blend := (sin(elapsed * 2.2) * 0.5 + 0.5)
		doll.rig.animate(0, 0, "stocking", 2.2)
		doll.rig._rotate("Spine", Vector3(0.18 * reach_blend, 0.10, -0.12 * reach_blend))
		doll.rig._rotate("Head", Vector3(-0.20 * reach_blend, 0.10, -0.05))
		doll.rig._rotate("UpperArmR", Vector3(-1.42 * reach_blend, 0.18, 0.32))
		doll.rig._rotate("ForearmR", Vector3(-0.35, 0, 0.06))
		doll.rig._rotate("UpperArmL", Vector3(0.48 * reach_blend, -0.18, -0.30))
		doll.rig._rotate("ForearmL", Vector3(-0.38, 0, -0.12))
		doll.rig._rotate("ThighR", Vector3(-0.14, 0, 0.04))
		doll.rig._rotate("ShinR", Vector3(0.20, 0, 0))
		doll.rig._rotate("ThighL", Vector3(0.36, 0, -0.12))
		doll.rig._rotate("ShinL", Vector3(0.32, 0, 0))
		doll.rig._rotate("FootL", Vector3(0.24, 0, 0))
		doll.rig._offset("HemBack", Vector3(0, 0, -0.10 * reach_blend))
		doll.rig._offset("HemFront", Vector3(0, 0, 0.08 * reach_blend))
		doll.rig.skeleton.force_update_all_bone_transforms()
	else:
		doll.rig.animate(walk_phase, 1.0 if mode == "walk" else 0.0, "idle", elapsed)
	if mode in ["sit","lie"]:
		preload("res://scripts/garment_preview_poses.gd")._pose_rest_frame(doll,mode,clampf(elapsed/4.0,0.0,1.0))
	if mode == "handwork":
		doll.rig._rest_arm("R",Vector3(.075,1.43,.36),Vector3(.5,1.3,.3),1.0)
		doll.rig._rest_arm("L",Vector3(-.06,1.48,.37),Vector3(-.5,1.3,.3),1.0)
		# Keep the insole upright while the elbow bends to bring it before the chest.
		var hand: int = doll.rig.bones.HandR
		var parent: int = doll.rig.skeleton.get_bone_parent(hand)
		var rotation: Quaternion = doll.rig.global_pose(parent).basis.get_rotation_quaternion().inverse()
		doll.rig.skeleton.set_bone_pose_rotation(hand,rotation)
		doll.rig.skeleton.force_update_all_bone_transforms()
	doll.body_rig.rotation.y = angle

