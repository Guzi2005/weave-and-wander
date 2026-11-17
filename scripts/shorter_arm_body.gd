extends "res://scripts/accepted_body_v20.gd"

## Isolated proportion study. Does not replace the game's clothed characters.
@export_range(0.0, 0.09, 0.005) var arm_shortening := 0.045:
	set(value):
		arm_shortening = clampf(value, 0.0, 0.09) if is_finite(value) else 0.0
		if is_instance_valid(body_rig):
			_build_appearance()


func arm_raise_at(height: float) -> float:
	return arm_shortening * (1.0 - smoothstep(1.17, 1.69, height))


func _lathe(parent: Node3D, label: String, rings: Array, color: Color,
		segments: int = 24, folds: float = 0.0, caps: bool = true,
		x_offsets: Array = [], z_offsets: Array = []) -> MeshInstance3D:
	if label == "ArmMannequin":
		rings = rings.duplicate()
		for i in rings.size():
			var ring: Vector3 = rings[i]
			ring.x += arm_raise_at(parent.position.y + ring.x)
			rings[i] = ring
	return super(parent, label, rings, color, segments, folds, caps, x_offsets, z_offsets)


func _ellipsoid(parent: Node3D, label: String, center: Vector3, radius: Vector3,
		color: Color) -> MeshInstance3D:
	if label == "ArmMannequinThumb":
		center.y += arm_shortening
	return super(parent, label, center, radius, color)


func _build_appearance() -> void:
	super()
	# Rebind only this study's skeleton to the shorter rest arm. Shared rig is untouched.
	if arm_shortening > 0.0:
		var elbow_raise := arm_raise_at(1.48)
		for suffix in ["L", "R"]:
			var elbow: int = rig.bones["Forearm" + suffix]
			var hand: int = rig.bones["Hand" + suffix]
			var elbow_rest: Transform3D = rig.skeleton.get_bone_rest(elbow)
			var hand_rest: Transform3D = rig.skeleton.get_bone_rest(hand)
			elbow_rest.origin.y += elbow_raise
			hand_rest.origin.y += arm_shortening - elbow_raise
			rig.skeleton.set_bone_rest(elbow, elbow_rest)
			rig.skeleton.set_bone_rest(hand, hand_rest)
		var skin: Skin = rig.skeleton.create_skin_from_rest_transforms()
		for part in rig.meshes:
			part.skin = skin
		rig.animate(0.0, 0.0, "idle", 0.0)
	set_underbody_mode(true)
