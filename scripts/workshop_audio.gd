class_name WorkshopAudio
extends Node

## Procedural ASMR & tactile workshop sound synthesizer for 《针脚与远方》 (Weave&Wander).
##
## Synthesizes lightweight 16-bit PCM AudioStreamWAV clips in memory so every
## craft station (loom shuttle clack, treadle step, scissors snip, sewing stitch,
## dye splash, cloth/paper fold, checkout bell) has responsive audio feedback
## without requiring external audio binaries, and immediately silences when
## paused or interrupted.
##
## Every cue is played through a pooled AudioStreamPlayer3D at its real workshop
## source, so the active Camera3D is the default listener. Inverse-distance
## attenuation with a 3 m unit size makes a station naturally louder as the view
## moves closer; there is no per-room volume/attenuation switch.

const SAMPLE_RATE := 22050
const CUE_NAMES := [
	"loom_clack",
	"pedal_step",
	"scissors_snip",
	"sewing_stitch",
	"dye_splash",
	"paper_fold",
	"checkout_chime",
	"footstep",
]
const PLAYER_COUNT := 4
const UNIT_SIZE := 3.0
const MAX_DISTANCE := 40.0

const STATION_NODE_NAMES := {
	"cutting": "CuttingTable",
	"sewing": "SewingWorkbench",
	"dye": "DyeWorkbench",
	"loom": "WeavingLoom",
}
const CUE_STATIONS := {
	"loom_clack": "loom",
	"pedal_step": "loom",
	"scissors_snip": "cutting",
	"sewing_stitch": "sewing",
	"dye_splash": "dye",
	"paper_fold": "cutting",
	"checkout_chime": "checkout",
}

var controller: Node
var muted := false
var master_volume_db := -8.0
var streams: Dictionary = {}
var last_played_cue := ""
var last_source_position := Vector3.ZERO
var last_source_name := ""
var cue_play_counts: Dictionary = {}

var _players: Array[AudioStreamPlayer3D] = []
var _player_cursor := 0
var _station_positions: Dictionary = {}
var _shop_counter: Node3D
var _shop_counter_position := Vector3.ZERO

var _last_prod_phase := "idle"
var _last_dye_phase := "idle"
var _stitch_timer := 0.0
var _snip_timer := 0.0
var _dye_timer := 0.0
var _loom_pick_seen := -1
var _last_sales_count := 0


func _ready() -> void:
	add_to_group("workshop_spatial_audio")
	_build_streams()
	_ensure_players()
	_refresh_sources()


func _build_streams() -> void:
	for cue in CUE_NAMES:
		streams[cue] = _synthesize_cue(cue)
		cue_play_counts[cue] = 0


func _ensure_players() -> void:
	if not _players.is_empty():
		return
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer3D.new()
		player.name = "WorkshopSFXPlayer3D%d" % i
		player.volume_db = master_volume_db
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.unit_size = UNIT_SIZE
		player.max_distance = MAX_DISTANCE
		player.panning_strength = 1.0
		add_child(player)
		_players.append(player)


## Resolve the live fixtures rather than baking room-local coordinates. Furniture
## can be moved while the shop is running, so the source follows the real node.
func _refresh_sources() -> void:
	_station_positions.clear()
	_shop_counter = null
	_shop_counter_position = Vector3.ZERO
	var rooms: Variant = controller.get("_rooms") if is_instance_valid(controller) else null
	if typeof(rooms) != TYPE_DICTIONARY:
		return
	var room_map: Dictionary = rooms
	var workshop: Variant = room_map.get("workshop")
	if is_instance_valid(workshop) and workshop is Node:
		for station in STATION_NODE_NAMES:
			var node: Node = (workshop as Node).get_node_or_null(STATION_NODE_NAMES[station])
			if node is Node3D and is_instance_valid(node):
				_station_positions[station] = (node as Node3D).global_position
	var shop: Variant = room_map.get("shop")
	if not is_instance_valid(shop):
		shop = controller.get("_shop")
	if is_instance_valid(shop) and shop is Node:
		var counter: Node = (shop as Node).get_node_or_null("CheckoutCounter")
		if counter is Node3D and is_instance_valid(counter):
			_shop_counter = counter as Node3D
			_shop_counter_position = _shop_counter.global_position


## Public source lookup used by the focused spatial test and by future cues.
func get_source_position(source: String) -> Vector3:
	_refresh_sources()
	if source == "checkout":
		return _shop_counter_position
	var position: Vector3 = _station_positions.get(source, Vector3.ZERO)
	return position


func has_source(source: String) -> bool:
	_refresh_sources()
	if source == "checkout":
		return is_instance_valid(_shop_counter)
	return _station_positions.has(source)


## Godot uses the viewport's current Camera3D as the 3D audio listener when no
## AudioListener3D overrides it. Falling back to controller.camera keeps the
## listener sensible while a scene is being assembled or driven headlessly.
func get_listener_camera() -> Camera3D:
	if is_inside_tree():
		var viewport := get_viewport()
		if is_instance_valid(viewport):
			var active := viewport.get_camera_3d()
			if is_instance_valid(active):
				return active
	if is_instance_valid(controller):
		var camera: Variant = controller.get("camera")
		var listener := camera as Camera3D
		if is_instance_valid(listener):
			return listener
	return null


func _default_source_position(cue: String) -> Vector3:
	var source := String(CUE_STATIONS.get(cue, "cutting"))
	return get_source_position(source)


func _actor_or_source(flow: Node, fallback_source: String) -> Vector3:
	if is_instance_valid(flow):
		var actor: Variant = flow.get("actor")
		if actor is Node3D and is_instance_valid(actor):
			return (actor as Node3D).global_position
	return get_source_position(fallback_source)


func _synthesize_cue(cue: String) -> AudioStreamWAV:
	if cue == "scissors_snip":
		return _synthesize_scissors_snip()
	var duration := 0.14
	match cue:
		"loom_clack": duration = 0.11
		"pedal_step": duration = 0.09
		"sewing_stitch": duration = 0.06
		"dye_splash": duration = 0.22
		"paper_fold": duration = 0.15
		"checkout_chime": duration = 0.28
		"footstep": duration = 0.095
	var sample_count := maxi(1, int(round(duration * float(SAMPLE_RATE))))
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = cue.hash()
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 24.0)
		var sample := 0.0
		match cue:
			"loom_clack":
				env = exp(-t * 32.0)
				sample = (sin(TAU * 310.0 * t) * 0.55 + sin(TAU * 680.0 * t) * 0.30 + rng.randf_range(-0.25, 0.25)) * env
			"pedal_step":
				env = exp(-t * 36.0)
				sample = (sin(TAU * 145.0 * t) * 0.70 + sin(TAU * 220.0 * t) * 0.25) * env
			"sewing_stitch":
				env = exp(-t * 55.0)
				sample = (sin(TAU * 420.0 * t) * 0.50 + rng.randf_range(-0.4, 0.4)) * env
			"dye_splash":
				env = sin(clampf(t / duration, 0.0, 1.0) * PI) * exp(-t * 8.0)
				sample = (sin(TAU * (260.0 + 80.0 * sin(TAU * 14.0 * t)) * t) * 0.45 + rng.randf_range(-0.25, 0.25)) * env
			"paper_fold":
				env = sin(clampf(t / duration, 0.0, 1.0) * PI) * exp(-t * 14.0)
				sample = rng.randf_range(-0.55, 0.55) * (0.5 + 0.5 * sin(TAU * 520.0 * t)) * env
			"checkout_chime":
				env = exp(-t * 11.0)
				sample = (sin(TAU * 1046.5 * t) * 0.45 + sin(TAU * 1568.0 * t) * 0.35) * env
			"footstep":
				# Muted sole impact with a short fabric/sole scuff, no sharp heel click.
				env = (1.0 - exp(-t * 650.0)) * exp(-t * 65.0)
				sample = (sin(TAU * 105.0 * t) * .60 + rng.randf_range(-.12, .12)) * env
		var pcm_val := clampi(int(round(clampf(sample, -1.0, 1.0) * 18000.0)), -32767, 32767)
		pcm[i * 2] = pcm_val & 0xFF
		pcm[i * 2 + 1] = (pcm_val >> 8) & 0xFF
	return _wav_from_pcm(pcm)


## The old scissors cue was a rising 1.8-2.7 kHz tone: a sharp, synthetic chirp.
## This version is a short, soft blade scrape built from band-limited deterministic
## noise, followed by a filtered closure click. It intentionally has no tonal
## chirp and no external sample download.
func _synthesize_scissors_snip() -> AudioStreamWAV:
	var duration := 0.19
	var sample_count := maxi(1, int(round(duration * float(SAMPLE_RATE))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5C1550
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var scrape_end := 0.112
	var close_at := 0.118
	var fast := 0.0
	var slow := 0.0
	var click_low := 0.0
	var peak := 0.0
	for i in sample_count:
		var t := float(i) / float(SAMPLE_RATE)
		var white := rng.randf_range(-1.0, 1.0)
		# Two one-pole filters leave a narrow, papery band instead of raw hiss.
		fast += (white - fast) * 0.32
		slow += (fast - slow) * 0.055
		var blade := fast - slow
		var sample := 0.0
		if t < scrape_end:
			var u := clampf(t / scrape_end, 0.0, 1.0)
			var scrape_env := pow(sin(PI * u), 1.35)
			var texture := 0.86 + 0.14 * sin(TAU * 24.0 * t + 0.7)
			sample += blade * scrape_env * texture
		if t >= close_at:
			var ct := t - close_at
			var click_env := (1.0 - exp(-ct * 420.0)) * exp(-ct * 86.0)
			click_low += (rng.randf_range(-1.0, 1.0) - click_low) * 0.18
			sample += (click_low * 0.85 + sin(TAU * 190.0 * ct) * 0.22) * click_env * 0.55
		var tail := smoothstep(duration - 0.035, duration, t)
		sample *= 1.0 - tail
		samples[i] = sample
		peak = maxf(peak, absf(sample))
	var gain := 0.45 / maxf(peak, 0.0001)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	for i in sample_count:
		var pcm_val := clampi(int(round(clampf(samples[i] * gain, -1.0, 1.0) * 32767.0)), -32767, 32767)
		pcm[i * 2] = pcm_val & 0xFF
		pcm[i * 2 + 1] = (pcm_val >> 8) & 0xFF
	return _wav_from_pcm(pcm)


func _wav_from_pcm(pcm: PackedByteArray) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = pcm
	return wav


func stop_all() -> void:
	for player in _players:
		if is_instance_valid(player) and player.playing:
			player.stop()


func play_footstep(actor: Node3D) -> void:
	if not is_instance_valid(actor) or not actor.is_visible_in_tree() or get_tree().paused:
		return
	if is_instance_valid(controller) and float(controller.get("_speed")) <= 0.0:
		return
	# Bound accelerated-simulation chatter without detaching sound from a landing.
	var now := Time.get_ticks_msec()
	if now - int(actor.get_meta("last_footstep_ms", -1000)) < 110:
		return
	actor.set_meta("last_footstep_ms", now)
	play_cue("footstep", -12.0, 0.96 + float(actor.get_instance_id() % 7) * .012, actor.global_position)


## Play a cue through a pooled 3D source. The existing three-argument call sites
## remain valid; world_position is an optional fourth argument and may be a
## Vector3 or a Node3D whose global position should be used. The source position
## is assigned before the headless/muted early return so tests can verify it.
func play_cue(cue: String, volume_offset_db: float = 0.0, pitch_scale: float = 1.0, world_position: Variant = null) -> bool:
	if not streams.has(cue):
		return false
	last_played_cue = cue
	cue_play_counts[cue] = int(cue_play_counts.get(cue, 0)) + 1
	var source_position := _default_source_position(cue)
	if world_position is Vector3:
		var position_value: Vector3 = world_position
		source_position = position_value
	elif world_position is Node3D and is_instance_valid(world_position):
		source_position = (world_position as Node3D).global_position
	last_source_position = source_position
	last_source_name = String(CUE_STATIONS.get(cue, ""))
	_ensure_players()
	if _players.is_empty():
		return true
	var player := _players[_player_cursor % _players.size()]
	_player_cursor = (_player_cursor + 1) % _players.size()
	player.stream = streams[cue]
	player.volume_db = master_volume_db + volume_offset_db
	player.pitch_scale = clampf(pitch_scale, 0.6, 1.6)
	player.global_position = source_position
	if muted or DisplayServer.get_name() == "headless":
		return true
	player.play()
	return true


func tick(scaled_delta: float) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	var speed := 1.0
	var speed_value: Variant = controller.get("_speed")
	if speed_value != null:
		speed = float(speed_value)
	var tree := get_tree()
	if scaled_delta <= 0.0 or speed <= 0.0 or (tree != null and tree.paused):
		stop_all()
		return
	_refresh_sources()

	# Track production station phases & rhythmic actions. Folding follows the
	# actual worker whenever one is present, so the rustle moves with them.
	var prod: Node = controller.get("_production")
	if is_instance_valid(prod):
		var phase := String(prod.get("phase"))
		if phase != _last_prod_phase:
			_last_prod_phase = phase
			if phase in ["unfold", "rewind"]:
				play_cue("paper_fold", 0.0, 1.0, _actor_or_source(prod, "cutting"))
			elif phase == "finish":
				play_cue("paper_fold", 0.0, 1.0, _actor_or_source(prod, "sewing"))
		if phase == "cut" and is_instance_valid(prod.get("actor")):
			_snip_timer -= scaled_delta
			if _snip_timer <= 0.0:
				_snip_timer = 0.65
				play_cue("scissors_snip", 0.0, 0.96 + 0.08 * fposmod(float(prod.get("elapsed")), 1.0), get_source_position("cutting"))
		elif phase == "sew" and is_instance_valid(prod.get("actor")):
			_stitch_timer -= scaled_delta
			if _stitch_timer <= 0.0:
				_stitch_timer = 0.18
				play_cue("sewing_stitch", -2.0, 1.0, get_source_position("sewing"))

	# Track dye vat phases. Unwrapping/rewrapping cloth also follows the worker.
	var dye: Node = controller.get("_dye")
	if is_instance_valid(dye):
		var d_phase := String(dye.get("phase"))
		if d_phase != _last_dye_phase:
			_last_dye_phase = d_phase
			if d_phase in ["unwind", "rewrap"]:
				play_cue("paper_fold", 0.0, 0.92, _actor_or_source(dye, "dye"))
		if d_phase in ["dye", "rinse"] and is_instance_valid(dye.get("actor")):
			_dye_timer -= scaled_delta
			if _dye_timer <= 0.0:
				_dye_timer = 1.25
				play_cue("dye_splash", 0.0, 0.95, get_source_position("dye"))

	# Track weaving loom picks at the physical loom.
	var rooms: Variant = controller.get("_rooms")
	if typeof(rooms) == TYPE_DICTIONARY and (rooms as Dictionary).has("workshop"):
		var workshop: Variant = (rooms as Dictionary)["workshop"]
		var loom: Node = (workshop as Node).get_node_or_null("WeavingLoom") if is_instance_valid(workshop) and workshop is Node else null
		if is_instance_valid(loom) and loom.get("picks_lifetime") != null:
			var picks := int(loom.get("picks_lifetime"))
			if picks != _loom_pick_seen:
				if _loom_pick_seen >= 0 and picks > _loom_pick_seen:
					play_cue("loom_clack", 0.0, 1.0, get_source_position("loom"))
					play_cue("pedal_step", -3.0, 0.95, get_source_position("loom"))
				_loom_pick_seen = picks

	# Track shop sales chime at the existing checkout counter.
	var sales := int(controller.get("_sales_count"))
	if sales > _last_sales_count:
		_last_sales_count = sales
		play_cue("checkout_chime", 0.0, 1.0, get_source_position("checkout"))
