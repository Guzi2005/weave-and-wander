extends SceneTree

var capture := AudioEffectCapture.new()
var audio: Node

func _initialize() -> void:
	_run.call_deferred()

func _measure(position: Vector3) -> Vector2:
	audio.stop_all()
	await create_timer(.15).timeout
	capture.clear_buffer()
	audio.play_cue("scissors_snip", 0.0, 1.0, position)
	await create_timer(.35).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var energy := Vector2.ZERO
	for frame in frames:
		energy += Vector2(frame.x * frame.x, frame.y * frame.y)
	return energy

func _run() -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, "SpatialTest")
	AudioServer.add_bus_effect(bus, capture)
	audio = load("res://scripts/workshop_audio.gd").new()
	root.add_child(audio)
	for player in audio._players:
		player.bus = "SpatialTest"
	audio.streams.scissors_snip.save_to_wav("res://captures/scissors_snip_preview.wav")
	var near_energy := await _measure(Vector3(0, 0, -3))
	var far_energy := await _measure(Vector3(0, 0, -12))
	var left_energy := await _measure(Vector3(-3, 0, -3))
	var right_energy := await _measure(Vector3(3, 0, -3))
	print("SPATIAL_MIX near=", near_energy, " far=", far_energy, " left=", left_energy, " right=", right_energy)
	assert(near_energy.length() > far_energy.length() * 4.0, "Distance did not attenuate actual mixed sound")
	assert(left_energy.x > left_energy.y and right_energy.y > right_energy.x, "Stereo direction did not follow source")
	print("SPATIAL_AUDIO_MIX_TEST passed: actual mixer distance attenuation and stereo direction")
	audio.free()
	camera.free()
	AudioServer.remove_bus(bus)
	quit()
