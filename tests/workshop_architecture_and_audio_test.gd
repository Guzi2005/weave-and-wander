extends SceneTree

## Acceptance test for the Low-Coupling Workshop Architecture ("Lego Bricks + Thin Glue")
## and User Expansion modules (WorkshopAudio ASMR + WorkshopCloseupAndPhoto).

const StationProtocol = preload("res://scripts/work_station_sequence.gd")
const AudioScript = preload("res://scripts/workshop_audio.gd")
const CloseupScript = preload("res://scripts/workshop_closeup_and_photo.gd")
const SpoolScript = preload("res://components/thread_spool.gd")

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
	_test_station_protocol()
	_test_thread_spool_dynamic_fullness()
	_test_audio_synthesizer()
	await _test_main_integration()
	print("WORKSHOP_ARCH_AND_AUDIO_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_station_protocol() -> void:
	var seq := StationProtocol.new("test_station", {
		"labels": {"idle": "待命", "to_cut": "前往裁剪", "cut": "裁剪中"},
		"travel_phases": ["to_cut"],
		"arrival_actions": {"to_cut": "cut"},
		"suspend_immediate": ["cut"],
		"durations": {"cut": 2.5},
	})
	_check(seq.is_travel_phase("to_cut") and not seq.is_travel_phase("cut"), "WorkStationSequence travel phase classification failed.")
	_check(seq.arrival_action_for("to_cut") == "cut", "WorkStationSequence arrival action lookup failed.")
	_check(seq.can_suspend_immediately("cut"), "WorkStationSequence immediate suspension lookup failed.")
	_check(absf(seq.duration_for("cut") - 2.5) < 0.001, "WorkStationSequence duration lookup failed.")

	var order := {"id": "ord_01"}
	var debit_count := [0]
	var first_ok := seq.commit_once(order, "fabric_cut", func() -> bool:
		debit_count[0] += 1
		return true
	)
	var second_ok := seq.commit_once(order, "fabric_cut", func() -> bool:
		debit_count[0] += 1
		return true
	)
	_check(first_ok and not second_ok and debit_count[0] == 1,
		"WorkStationSequence.commit_once() did not prevent duplicate material debit.")


func _test_thread_spool_dynamic_fullness() -> void:
	var spool := SpoolScript.new()
	root.add_child(spool)
	spool.build(0.06, 0.18, Color("496e91"))
	var thread_mesh_before: Mesh = spool._wound_thread_part.mesh
	spool.set_fullness(0.5)
	_check(spool._wound_thread_part.mesh == thread_mesh_before,
		"ThreadSpool.set_fullness() rebuilt ArrayMesh instead of scaling transform.")
	_check(spool._wound_thread_part.scale.x < 0.95 and spool._wound_thread_part.scale.x > 0.35,
		"ThreadSpool.set_fullness() did not scale radial X/Z dimensions.")
	spool.set_fullness(0.0)
	_check(not spool._wound_thread_part.visible, "Empty ThreadSpool did not hide wound thread.")
	spool.free()


func _test_audio_synthesizer() -> void:
	var audio := AudioScript.new()
	root.add_child(audio)
	_check(audio.streams.size() == AudioScript.CUE_NAMES.size(), "Not all 7 ASMR workshop audio streams were synthesized.")
	for cue in AudioScript.CUE_NAMES:
		var stream: AudioStreamWAV = audio.streams.get(cue)
		_check(stream != null and stream.data.size() > 1000, "Synthesized WAV data is empty for cue: " + cue)
		_check(audio.play_cue(cue), "play_cue() failed for cue: " + cue)
	_check(int(audio.cue_play_counts.get("scissors_snip", 0)) == 1, "Audio cue play counter did not increment.")
	audio.free()


func _test_main_integration() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._view_controls.set_process(false)

	_check(game._business_session != null, "BusinessSession Lego brick was not initialized on main.gd.")
	_check(game._work_dispatcher != null, "WorkDispatcher Lego brick was not initialized on main.gd.")
	_check(is_instance_valid(game._workshop_audio), "WorkshopAudio node was not attached to main.gd.")
	_check(is_instance_valid(game._workshop_closeup), "WorkshopCloseupAndPhoto node was not attached to main.gd.")

	var prod_snap: Dictionary = game._production.get_station_snapshot()
	var dye_snap: Dictionary = game._dye.get_station_snapshot()
	_check(prod_snap.get("station_id", "") == "production", "Production station snapshot missing station_id.")
	_check(dye_snap.get("station_id", "") == "dye", "Dye station snapshot missing station_id.")

	# Cycle macro close-up camera across all 4 workshop stations
	for expected_station in CloseupScript.STATION_ORDER:
		var current: String = game._workshop_closeup.cycle_station_closeup()
		_check(current == expected_station, "Workshop closeup did not cycle to " + expected_station)
	game._workshop_closeup.exit_closeup()
	_check(game._workshop_closeup.active_station.is_empty(), "exit_closeup() did not clear active_station.")

	# Capture a specimen postcard and verify framed dimensions
	var postcard_path := "res://.appdata/test_specimen_postcard.png"
	var card: Image = game._workshop_closeup.capture_specimen_postcard(postcard_path)
	_check(card != null and card.get_width() > 640 and card.get_height() > 420,
		"Specimen postcard image was not framed with Polaroid margins.")
	_check(FileAccess.file_exists(postcard_path), "Specimen postcard PNG was not saved to disk.")
	if FileAccess.file_exists(postcard_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(postcard_path))

	game.free()
