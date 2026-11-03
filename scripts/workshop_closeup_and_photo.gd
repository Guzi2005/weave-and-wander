class_name WorkshopCloseupAndPhoto
extends Node

## Workshop Macro Close-Up Camera, Seamless Manual/Auto Craft Assist,
## and Specimen Postcard / Polaroid Screenshot Generator for 《针脚与远方》.

const STATION_ORDER := ["loom", "cutting", "sewing", "dye"]
const STATION_TITLES := {
	"loom": "织布机梭口微距",
	"cutting": "裁剪台量布微距",
	"sewing": "缝纫机压脚微距",
	"dye": "染缸浸染微距",
}
const STATION_OFFSETS := {
	"loom": {"eye": Vector3(0.0, 2.05, 2.35), "look": Vector3(0.0, 1.18, 0.0)},
	"cutting": {"eye": Vector3(0.0, 2.25, 2.15), "look": Vector3(-0.15, 1.12, 0.05)},
	"sewing": {"eye": Vector3(0.0, 1.95, 1.85), "look": Vector3(-0.10, 1.12, 0.10)},
	"dye": {"eye": Vector3(0.0, 2.20, 2.25), "look": Vector3(0.0, 1.05, 0.0)},
}

var controller: Node
var active_station := ""
var _station_index := -1
var last_postcard_path := ""
var _closeup_bar: HBoxContainer
var _closeup_label: Label


func setup(host: Node, hud: Control) -> void:
	controller = host
	_build_hud_controls(hud)


func _build_hud_controls(hud: Control) -> void:
	if hud == null:
		return
	_closeup_bar = HBoxContainer.new()
	_closeup_bar.name = "WorkshopCloseupBar"
	_closeup_bar.add_theme_constant_override("separation", 8)
	_closeup_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_closeup_bar)
	_closeup_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_closeup_bar.offset_left = -280
	_closeup_bar.offset_right = 280
	_closeup_bar.offset_top = -68
	_closeup_bar.offset_bottom = -24

	_closeup_label = Label.new()
	_closeup_label.add_theme_font_size_override("font_size", 15)
	_closeup_label.add_theme_color_override("font_color", Color("5a4038"))
	_closeup_label.add_theme_color_override("font_outline_color", Color("f2ead9"))
	_closeup_label.add_theme_constant_override("outline_size", 5)
	_closeup_bar.add_child(_closeup_label)

	var next_btn := Button.new()
	next_btn.text = "切换工位微距"
	next_btn.focus_mode = Control.FOCUS_NONE
	next_btn.pressed.connect(cycle_station_closeup)
	_closeup_bar.add_child(next_btn)

	var assist_btn := Button.new()
	assist_btn.text = "亲手推进工序 · 助工"
	assist_btn.focus_mode = Control.FOCUS_NONE
	assist_btn.pressed.connect(func() -> void: manual_craft_step(0.55))
	_closeup_bar.add_child(assist_btn)

	var photo_btn := Button.new()
	photo_btn.text = "拍摄标本明信片"
	photo_btn.focus_mode = Control.FOCUS_NONE
	photo_btn.pressed.connect(func() -> void: capture_specimen_postcard())
	_closeup_bar.add_child(photo_btn)

	var exit_btn := Button.new()
	exit_btn.text = "退出微距"
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.pressed.connect(exit_closeup)
	_closeup_bar.add_child(exit_btn)
	_closeup_bar.hide()


func _station_node(station_id: String) -> Node3D:
	if controller == null or not controller._rooms.has("workshop"):
		return null
	var workshop: Node3D = controller._rooms["workshop"]
	match station_id:
		"loom": return workshop.get_node_or_null("WeavingLoom")
		"cutting": return workshop.get_node_or_null("CuttingTable")
		"sewing": return workshop.get_node_or_null("SewingWorkbench")
		"dye": return workshop.get_node_or_null("DyeWorkbench")
	return null


func focus_station(station_id: String) -> bool:
	if not (station_id in STATION_ORDER):
		return false
	var target_node := _station_node(station_id)
	if not is_instance_valid(target_node):
		return false
	active_station = station_id
	_station_index = STATION_ORDER.find(station_id)
	if controller.has_method("_switch_room") and controller._active_room != "workshop":
		controller._switch_room("workshop")
	if is_instance_valid(_closeup_bar):
		_closeup_label.text = "工坊微距 · %s" % String(STATION_TITLES.get(station_id, station_id))
		_closeup_bar.show()
	_apply_closeup_camera()
	return true


func cycle_station_closeup() -> String:
	_station_index = (_station_index + 1) % STATION_ORDER.size()
	var next_id: String = STATION_ORDER[_station_index]
	focus_station(next_id)
	if controller != null and controller.has_method("_show_toast"):
		controller._show_toast("已切入%s（可随时点击『亲手推进工序』或交回店员）" % String(STATION_TITLES.get(next_id, next_id)))
	return active_station


func exit_closeup() -> void:
	if active_station.is_empty():
		return
	active_station = ""
	if is_instance_valid(_closeup_bar):
		_closeup_bar.hide()
	if controller != null and is_instance_valid(controller._view_controls):
		controller._view_controls.apply_view()


func _apply_closeup_camera() -> void:
	if active_station.is_empty() or controller == null or not is_instance_valid(controller.camera):
		return
	var node := _station_node(active_station)
	if not is_instance_valid(node):
		return
	var spec: Dictionary = STATION_OFFSETS.get(active_station, STATION_OFFSETS["sewing"])
	var eye_world: Vector3 = node.to_global(spec["eye"])
	var look_world: Vector3 = node.to_global(spec["look"])
	controller.camera.global_position = eye_world
	controller.camera.look_at(look_world, Vector3.UP)


func tick(_delta: float) -> void:
	if not active_station.is_empty():
		_apply_closeup_camera()


## Allows the player to manually advance the active craft step alongside or in
## place of the staff member without violating ledger/state-machine invariants.
func manual_craft_step(seconds: float = 0.55) -> bool:
	if controller == null:
		return false
	var target := active_station if not active_station.is_empty() else "sewing"
	var audio: Node = controller.get("_workshop_audio")
	if target in ["cutting", "sewing"] and is_instance_valid(controller._production):
		if controller._production.nudge_manual_step(seconds):
			if is_instance_valid(audio):
				audio.play_cue("scissors_snip" if controller._production.phase == "cut" else "sewing_stitch")
			return true
	if target == "dye" and is_instance_valid(controller._dye):
		if controller._dye.nudge_manual_step(seconds):
			if is_instance_valid(audio):
				audio.play_cue("dye_splash")
			return true
	if target == "loom":
		var loom := _station_node("loom")
		if is_instance_valid(loom) and is_instance_valid(loom.get("worker")):
			loom.advance(loom.worker, seconds)
			if is_instance_valid(audio):
				audio.play_cue("loom_clack")
			return true
	# Fallback: try production or dye if either is currently in a stationary phase
	if is_instance_valid(controller._production) and controller._production.nudge_manual_step(seconds):
		return true
	if is_instance_valid(controller._dye) and controller._dye.nudge_manual_step(seconds):
		return true
	if controller.has_method("_show_toast"):
		controller._show_toast("当前工位暂无进行中的平稳工序，可先安排制衣或染色单")
	return false


## Generates a Polaroid / fabric-specimen postcard image framed with paper
## margins and provenance swatch stamps. Works in both windowed and headless modes.
func capture_specimen_postcard(output_path: String = "") -> Image:
	var target_path := output_path
	if target_path.is_empty():
		var day := int(controller.get("_day_index")) if controller != null else 1
		target_path = "res://captures/specimen_postcard_day%d.png" % day
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target_path.get_base_dir()))

	var ui: CanvasLayer = controller.get_node_or_null("GameInterface") if controller != null else null
	var was_ui_visible := ui.visible if ui != null else false
	if ui != null:
		ui.hide()

	var viewport_img: Image = null
	if DisplayServer.get_name() != "headless" and controller != null and is_instance_valid(controller.get_viewport()) and controller.get_viewport().get_texture() != null:
		viewport_img = controller.get_viewport().get_texture().get_image()
	if ui != null:
		ui.visible = was_ui_visible

	if viewport_img == null or viewport_img.is_empty():
		viewport_img = Image.create_empty(640, 420, false, Image.FORMAT_RGBA8)
		viewport_img.fill(Color("e8dfd1"))
	else:
		viewport_img.convert(Image.FORMAT_RGBA8)

	var card := _frame_as_specimen_postcard(viewport_img)
	card.save_png(ProjectSettings.globalize_path(target_path))
	last_postcard_path = target_path
	if controller != null and controller.has_method("_show_toast"):
		controller._show_toast("已保存工坊标本明信片：%s" % target_path.get_file())
	return card


func _frame_as_specimen_postcard(source: Image) -> Image:
	var pad_side := 28
	var pad_top := 28
	var pad_bottom := 84
	var w := source.get_width() + pad_side * 2
	var h := source.get_height() + pad_top + pad_bottom
	var card := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var paper := Color("f4efe4")
	var ink := Color("5a4038")
	card.fill(paper)

	# Outer ink border
	card.fill_rect(Rect2i(8, 8, w - 16, 2), ink)
	card.fill_rect(Rect2i(8, h - 10, w - 16, 2), ink)
	card.fill_rect(Rect2i(8, 8, 2, h - 16), ink)
	card.fill_rect(Rect2i(w - 10, 8, 2, h - 16), ink)

	# Blit viewport snapshot
	card.blit_rect(source, Rect2i(0, 0, source.get_width(), source.get_height()), Vector2i(pad_side, pad_top))

	# Inner photo keyline
	card.fill_rect(Rect2i(pad_side - 2, pad_top - 2, source.get_width() + 4, 2), ink)
	card.fill_rect(Rect2i(pad_side - 2, pad_top + source.get_height(), source.get_width() + 4, 2), ink)

	# Stamp 4 fabric/dye provenance swatches along the bottom specimen footer
	var swatches := [Color("4d7b73"), Color("c75f50"), Color("d5aa48"), Color("779ab1")]
	var footer_y := pad_top + source.get_height() + 24
	for i in swatches.size():
		var sx := pad_side + i * 44
		card.fill_rect(Rect2i(sx - 1, footer_y - 1, 30, 30), ink)
		card.fill_rect(Rect2i(sx, footer_y, 28, 28), swatches[i])
	return card
