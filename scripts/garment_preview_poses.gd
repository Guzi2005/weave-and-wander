extends RefCounted
## Shared with the pleated-skirt editor: seated foot IK and seated-to-lying transition.
const HIP_REST_Y := 1.14
const HIP_DROP := .32
const SEAT_HIP_Y := .82
const NAP_PELVIS := Vector3(0,.60,0)

static func _ease(factor: float) -> float:
	return factor * factor * (3.0 - 2.0 * factor)


static func _pose_sit(doll: Node3D, factor: float) -> void:
	# Standing -> seated: lower the hips onto the seat, then re-plant the feet
	# with two-bone IK so the soles stay grounded and the knees point forward.
	doll.rig.pose_rest("sit", factor, 0.0, Vector4(1, 0, 0, 0))
	var hips: int = doll.rig.bones.Hips
	var rest: Vector3 = doll.rig.skeleton.get_bone_rest(hips).origin
	doll.rig.skeleton.set_bone_pose_position(hips, rest + Vector3(0, -HIP_DROP * factor, 0))
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0 else "R"
		var standing := Vector3(side * .15, .15, .095)
		var seated := Vector3(side * .15, .15, .25)
		doll.rig.place_foot(suffix, standing.lerp(seated, factor))


static func _pose_lie(doll: Node3D, factor: float) -> void:
	# Seated -> nap: slerp every bone from the full sit pose toward the nap
	# targets, then translate the root so the pelvis rides from [0,.82,0] to
	# [0,.98,0] instead of tipping about the origin.
	var amount := _ease(factor)
	_pose_sit(doll, 1.0)
	var hips: int = doll.rig.bones.Hips
	var hip_y := lerpf(SEAT_HIP_Y, HIP_REST_Y, amount)
	doll.rig.skeleton.set_bone_pose_position(hips, Vector3(0, hip_y, 0))
	# pose_rest slerps the root from identity toward (0,0,PI/2) by amount, so
	# the rotation after the call is known; pre-place the matching translation
	# to let the nap arm IK solve in the final bench frame.
	var rotation := Quaternion.IDENTITY.slerp(Quaternion.from_euler(Vector3(0, 0, PI * .5)), amount)
	var pelvis := Vector3(0, SEAT_HIP_Y, 0).lerp(NAP_PELVIS, amount)
	doll.rig.skeleton.set_bone_pose_position(doll.rig.bones.Root, pelvis - rotation * Vector3(0, hip_y, 0))
	doll.rig.pose_rest("nap", amount, 0.0, Vector4(1, 0, 0, 0))
	# Crossfade the rest-cloth correctives from the sit shape to the nap shape.
	for part in doll.rig.meshes:
		if part.get_meta("rest_cloth", false):
			part.set_blend_shape_value(0, 1.0 - amount)
	doll.rig.skeleton.force_update_all_bone_transforms()


static func _pose_rest_frame(doll: Node3D, action: String, factor: float) -> void:
	if action == "sit":
		_pose_sit(doll, _ease(factor))
	elif factor <= .4:
		# The first 40% of the lie clip replays the exact sit clip.
		_pose_sit(doll, _ease(factor / .4))
	elif factor <= .5:
		# Brief settle on the seat before reclining.
		_pose_sit(doll, 1.0)
	else:
		_pose_lie(doll, (factor - .5) / .5)


