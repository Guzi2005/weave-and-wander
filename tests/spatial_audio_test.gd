extends SceneTree

## Focused acceptance test for WorkshopAudio's spatial (AudioStreamPlayer3D)
## workshop cues and the redesigned scissors waveform.

const AudioScript = preload("res://scripts/workshop_audio.gd")
const EPSILON := 0.001

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	_test_stream_synthesis()
	_test_playback_and_sources()
	await _test_main_station_resolution()
	print("SPATIAL_AUDIO_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_stream_synthesis() -> void:
	var audio := AudioScript.new()
	root.add_child(audio)
	_check(audio.streams.size() == AudioScript.CUE_NAMES.size(), "Not all workshop cues were synthesized.")
	_check(audio._players.size() == AudioScript.PLAYER_COUNT, "Audio player pool was not created.")
	for player in audio._players:
		_check(player is AudioStreamPlayer3D, "Workshop cue pool is not using AudioStreamPlayer3D.")
		_check(player.attenuation_model == AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE,
			"Workshop cue does not use inverse-distance attenuation.")
		_check(is_equal_approx(player.unit_size, 3.0), "Workshop cue unit_size is not about 3 m.")
		_check(is_equal_approx(player.max_distance, 40.0), "Workshop cue max_distance is not 40 m.")

	for cue in AudioScript.CUE_NAMES:
		var stream: AudioStreamWAV = audio.streams.get(cue)
		_check(stream != null and stream.data.size() > 1000, "Synthesized WAV data is empty for cue: " + cue)

	var scissors: AudioStreamWAV = audio.streams.get("scissors_snip")
	_check(scissors != null, "Scissors cue stream is missing.")
	if scissors != null:
		_check(scissors.format == AudioStreamWAV.FORMAT_16_BITS and scissors.mix_rate == AudioScript.SAMPLE_RATE,
			"Scissors cue is not 16-bit PCM at the workshop sample rate.")
		var peak := 0
		var nonzero := 0
		for offset in range(0, scissors.data.size(), 2):
			var value := scissors.data.decode_s16(offset)
			peak = maxi(peak, absi(value))
			if value != 0:
				nonzero += 1
		_check(nonzero > scissors.data.size() / 4, "Scissors waveform is mostly silent.")
		_check(peak > 3000, "Scissors waveform is too quiet to be audible.")
		_check(peak < 20000, "Scissors waveform is too harsh/loud compared with the old chirp.")

	var duplicate := AudioScript.new()
	root.add_child(duplicate)
	var duplicate_scissors: AudioStreamWAV = duplicate.streams.get("scissors_snip")
	_check(scissors != null and duplicate_scissors != null and duplicate_scissors.data == scissors.data,
		"Scissors waveform is not deterministic between instances.")
	duplicate.free()

	_check(audio.play_cue("loom_clack"), "Existing one-argument play_cue() call failed.")
	_check(audio.play_cue("loom_clack", -2.0, 1.1), "Existing three-argument play_cue() call failed.")
	_check(int(audio.cue_play_counts.get("loom_clack", 0)) == 2, "Cue play counters did not increment.")
	audio.free()


func _test_playback_and_sources() -> void:
	var audio := AudioScript.new()
	root.add_child(audio)
	var expected := Vector3(12.5, 1.25, -3.5)
	_check(audio.play_cue("scissors_snip", 0.0, 1.0, expected), "play_cue() rejected the optional world position.")
	_check(audio.last_source_position.distance_to(expected) < EPSILON,
		"play_cue() did not record the optional world position before playback.")
	var used_player: AudioStreamPlayer3D = audio._players[(audio._player_cursor - 1 + audio._players.size()) % audio._players.size()]
	_check(used_player.global_position.distance_to(expected) < EPSILON,
		"AudioStreamPlayer3D source was not moved before headless playback returned.")
	if DisplayServer.get_name() == "headless":
		_check(not used_player.playing, "Headless playback should configure the source without starting audio.")
	audio.free()


func _test_main_station_resolution() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	if is_instance_valid(game._view_controls):
		game._view_controls.set_process(false)

	var audio = game._workshop_audio
	_check(is_instance_valid(audio), "WorkshopAudio is not attached to main.gd.")
	if not is_instance_valid(audio):
		game.free()
		return

	var workshop: Node = game._rooms.workshop
	var expected_sources := {
		"cutting": workshop.get_node("CuttingTable"),
		"sewing": workshop.get_node("SewingWorkbench"),
		"dye": workshop.get_node("DyeWorkbench"),
		"loom": workshop.get_node("WeavingLoom"),
	}
	var positions := {}
	for source in expected_sources:
		_check(audio.has_source(source), "Workshop source was not resolved: " + source)
		var position: Vector3 = audio.get_source_position(source)
		var fixture: Node3D = expected_sources[source]
		_check(position.distance_to(fixture.global_position) < EPSILON,
			"Workshop source does not follow the actual fixture: " + source)
		positions[source] = position

	var source_keys := positions.keys()
	for i in source_keys.size():
		for j in range(i + 1, source_keys.size()):
			var first: Vector3 = positions[source_keys[i]]
			var second: Vector3 = positions[source_keys[j]]
			_check(first.distance_to(second) > 0.01,
				"Workshop station sources overlap: %s and %s" % [source_keys[i], source_keys[j]])

	var counter: Node3D = game._rooms.shop.get_node("CheckoutCounter")
	_check(audio.has_source("checkout"), "Checkout counter source was not resolved.")
	_check(audio.get_source_position("checkout").distance_to(counter.global_position) < EPSILON,
		"Checkout chime source does not follow the existing shop counter.")
	_check(audio.get_listener_camera() == game.camera,
		"Active camera was not resolved as the default 3D audio listener.")

	_check(audio.play_cue("loom_clack"), "Loom cue failed in the live scene.")
	_check(audio.last_source_position.distance_to(expected_sources.loom.global_position) < EPSILON,
		"Loom cue defaulted to the wrong source.")
	_check(audio.play_cue("scissors_snip"), "Scissors cue failed in the live scene.")
	_check(audio.last_source_position.distance_to(expected_sources.cutting.global_position) < EPSILON,
		"Scissors cue defaulted to the wrong source.")
	_check(audio.play_cue("sewing_stitch"), "Sewing cue failed in the live scene.")
	_check(audio.last_source_position.distance_to(expected_sources.sewing.global_position) < EPSILON,
		"Sewing cue defaulted to the wrong source.")
	_check(audio.play_cue("dye_splash"), "Dye cue failed in the live scene.")
	_check(audio.last_source_position.distance_to(expected_sources.dye.global_position) < EPSILON,
		"Dye cue defaulted to the wrong source.")
	_check(audio.play_cue("checkout_chime"), "Checkout cue failed in the live scene.")
	_check(audio.last_source_position.distance_to(counter.global_position) < EPSILON,
		"Checkout cue defaulted to the wrong source.")

	# Folding must follow the worker when one exists, not a fixed room anchor.
	var production: Node = game._production
	var original_prod_phase := String(production.get("phase"))
	var original_prod_actor: Variant = production.get("actor")
	var actor: Node3D = game.staff[0]
	production.set("actor", actor)
	production.set("phase", "unfold")
	audio._last_prod_phase = "idle"
	audio._last_dye_phase = String(game._dye.get("phase"))
	audio._dye_timer = 999.0
	audio._loom_pick_seen = int(game._rooms.workshop.get_node("WeavingLoom").get("picks_lifetime"))
	audio._last_sales_count = int(game.get("_sales_count"))
	audio.tick(0.016)
	_check(audio.last_played_cue == "paper_fold", "Unfold phase did not play the folding rustle.")
	_check(audio.last_source_position.distance_to(actor.global_position) < EPSILON,
		"Folding rustle did not follow the actual production actor.")
	production.set("phase", original_prod_phase)
	production.set("actor", original_prod_actor)
	audio._last_prod_phase = original_prod_phase

	var dye: Node = game._dye
	var original_dye_phase := String(dye.get("phase"))
	var original_dye_actor: Variant = dye.get("actor")
	dye.set("actor", actor)
	dye.set("phase", "unwind")
	audio._last_dye_phase = "idle"
	audio.tick(0.016)
	_check(audio.last_played_cue == "paper_fold", "Dye unwind phase did not play the folding rustle.")
	_check(audio.last_source_position.distance_to(actor.global_position) < EPSILON,
		"Dye folding rustle did not follow the actual dye actor.")
	dye.set("phase", original_dye_phase)
	dye.set("actor", original_dye_actor)
	audio._last_dye_phase = original_dye_phase

	game.free()
