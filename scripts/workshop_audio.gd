class_name WorkshopAudio
extends Node

## Procedural ASMR & tactile workshop sound synthesizer for 《针脚与远方》 (Weave&Wander).
##
## Synthesizes lightweight 16-bit PCM AudioStreamWAV clips in memory so every
## craft station (loom shuttle clack, treadle step, scissors snip, sewing stitch,
## dye splash, cloth/paper fold, checkout bell) has responsive audio feedback
## without requiring external audio binaries, and immediately silences when
## paused or interrupted.

const SAMPLE_RATE := 22050
const CUE_NAMES := [
	"loom_clack",
	"pedal_step",
	"scissors_snip",
	"sewing_stitch",
	"dye_splash",
	"paper_fold",
	"checkout_chime",
]

var controller: Node
var muted := false
var master_volume_db := -8.0
var streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _player_cursor := 0
var last_played_cue := ""
var cue_play_counts: Dictionary = {}

var _last_prod_phase := "idle"
var _last_dye_phase := "idle"
var _stitch_timer := 0.0
var _snip_timer := 0.0
var _dye_timer := 0.0
var _loom_pick_seen := -1
var _last_sales_count := 0


func _ready() -> void:
	_build_streams()
	for i in 4:
		var player := AudioStreamPlayer.new()
		player.name = "WorkshopSFXPlayer%d" % i
		player.volume_db = master_volume_db
		add_child(player)
		_players.append(player)


func _build_streams() -> void:
	for cue in CUE_NAMES:
		streams[cue] = _synthesize_cue(cue)
		cue_play_counts[cue] = 0


func _synthesize_cue(cue: String) -> AudioStreamWAV:
	var duration := 0.14
	match cue:
		"loom_clack": duration = 0.11
		"pedal_step": duration = 0.09
		"scissors_snip": duration = 0.13
		"sewing_stitch": duration = 0.06
		"dye_splash": duration = 0.22
		"paper_fold": duration = 0.15
		"checkout_chime": duration = 0.28
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
			"scissors_snip":
				env = exp(-t * 28.0)
				var chirp := 1800.0 + 900.0 * (t / duration)
				sample = (sin(TAU * chirp * t) * 0.45 + sin(TAU * 3100.0 * t) * 0.25 + rng.randf_range(-0.35, 0.35) * exp(-t * 40.0)) * env
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
		var pcm_val := clampi(int(round(clampf(sample, -1.0, 1.0) * 18000.0)), -32767, 32767)
		pcm[i * 2] = pcm_val & 0xFF
		pcm[i * 2 + 1] = (pcm_val >> 8) & 0xFF
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


func play_cue(cue: String, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> bool:
	if not streams.has(cue):
		return false
	last_played_cue = cue
	cue_play_counts[cue] = int(cue_play_counts.get(cue, 0)) + 1
	if muted or DisplayServer.get_name() == "headless":
		return true
	if _players.is_empty():
		return true
	var player := _players[_player_cursor % _players.size()]
	_player_cursor = (_player_cursor + 1) % _players.size()
	player.stream = streams[cue]
	player.volume_db = master_volume_db + volume_offset_db
	player.pitch_scale = clampf(pitch_scale, 0.6, 1.6)
	player.play()
	return true


func tick(scaled_delta: float) -> void:
	if controller == null or not is_instance_valid(controller):
		return
	if scaled_delta <= 0.0 or controller.get("_speed") <= 0.0 or get_tree().paused:
		stop_all()
		return
	var room_atten := 0.0 if String(controller.get("_active_room")) == "workshop" else -9.0

	# Track production station phases & rhythmic actions
	var prod: Node = controller.get("_production")
	if is_instance_valid(prod):
		var phase := String(prod.get("phase"))
		if phase != _last_prod_phase:
			_last_prod_phase = phase
			if phase in ["unfold", "rewind", "finish"]:
				play_cue("paper_fold", room_atten, 1.0)
		if phase == "cut" and is_instance_valid(prod.get("actor")):
			_snip_timer -= scaled_delta
			if _snip_timer <= 0.0:
				_snip_timer = 0.65
				play_cue("scissors_snip", room_atten, 0.96 + 0.08 * fposmod(float(prod.get("elapsed")), 1.0))
		elif phase == "sew" and is_instance_valid(prod.get("actor")):
			_stitch_timer -= scaled_delta
			if _stitch_timer <= 0.0:
				_stitch_timer = 0.18
				play_cue("sewing_stitch", room_atten - 2.0, 1.0)

	# Track dye vat phases
	var dye: Node = controller.get("_dye")
	if is_instance_valid(dye):
		var d_phase := String(dye.get("phase"))
		if d_phase != _last_dye_phase:
			_last_dye_phase = d_phase
			if d_phase in ["unwind", "rewrap"]:
				play_cue("paper_fold", room_atten, 0.92)
		if d_phase in ["dye", "rinse"] and is_instance_valid(dye.get("actor")):
			_dye_timer -= scaled_delta
			if _dye_timer <= 0.0:
				_dye_timer = 1.25
				play_cue("dye_splash", room_atten, 0.95)

	# Track weaving loom picks
	var rooms: Variant = controller.get("_rooms")
	if typeof(rooms) == TYPE_DICTIONARY and (rooms as Dictionary).has("workshop"):
		var workshop: Node = rooms["workshop"]
		var loom: Node = workshop.get_node_or_null("WeavingLoom") if is_instance_valid(workshop) else null
		if is_instance_valid(loom) and loom.get("picks") != null:
			var picks := int(loom.get("picks"))
			if picks != _loom_pick_seen:
				if _loom_pick_seen >= 0 and picks > _loom_pick_seen:
					play_cue("loom_clack", room_atten, 1.0)
					play_cue("pedal_step", room_atten - 3.0, 0.95)
				_loom_pick_seen = picks

	# Track shop sales chime
	var sales := int(controller.get("_sales_count"))
	if sales > _last_sales_count:
		_last_sales_count = sales
		play_cue("checkout_chime", 0.0, 1.0)
