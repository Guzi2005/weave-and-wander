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

