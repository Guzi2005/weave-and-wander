extends SceneTree

class WalkingProbe extends PaperDoll:
	func _update_puppet_motion(_delta: float) -> void:
		pass

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var audio = load("res://scripts/workshop_audio.gd").new()
	root.add_child(audio)
	var actor := WalkingProbe.new()
	root.add_child(actor)
	actor._moving = true
	actor._target = Vector3(0, 0, 5)
	actor.simulate(.2, 1.0)
	actor.simulate(.2, 1.0)
	assert(int(audio.cue_play_counts.footstep) > 0, "Walking did not emit a contact sound")
	assert(audio.last_source_position.distance_to(actor.global_position) < .001)
	var count: int = audio.cue_play_counts.footstep
	actor._moving = false
	actor.simulate(.5, 1.0)
	actor.simulate(.5, 0.0)
	assert(audio.cue_play_counts.footstep == count, "Idle or paused actor emitted footsteps")
	var model := Node3D.new()
	root.add_child(model)
	var rig = load("res://scripts/doll_rig.gd").new()
	rig.bind(model, false)
	rig.animate(0, 1, "walk", 0)
	var high: float = rig.global_pose(rig.bones.Head).origin.y
	var sole: float = rig.global_pose(rig.bones.FootL).origin.y
	rig.animate(PI * .5, 1, "walk", 0)
	var low: float = rig.global_pose(rig.bones.Head).origin.y
	assert(high - low > .02 and high - low < .06, "Whole-body rise is missing or excessive")
	assert(absf(sole - .15) < .001, "Body rise lifted the planted foot")
	assert(absf(rig.global_pose(rig.bones.FootR).origin.y - .15) < .001)
	audio.streams.footstep.save_to_wav("res://captures/footstep_preview.wav")
	print("FOOTSTEP_GAIT_TEST passed: walk contact, source position, idle/pause silence, body rise, planted soles")
	actor.free()
	model.free()
	audio.free()
	quit()
