extends Node
## Player-facing furniture editing. Preview never changes the live fixture.

var game: Node
var active := false
var fixture: Node3D
var proposed := Transform3D.IDENTITY
var _return_speed := 1.0
var _canvas: CanvasLayer
var _panel: PanelContainer
var _items: OptionButton
var _status: Label
var _ghost: MeshInstance3D
var _fixtures: Array[Node3D] = []
var _footprint := Rect2()
var _undo: Array[Dictionary] = []
var _pointer_placement := false
var _dragging := false
var _drag_offset := Vector3.ZERO
var _drag_start := Transform3D.IDENTITY
var _hud_was_visible := true
var _roof_pins: Dictionary = {}

const NAMES := {"GarmentDisplay":"成衣展示架", "SmallGoodsCabinet":"帽饰柜", "CheckoutCounter":"收银柜台", "StandingMirror":"试衣镜", "TeaCorner":"茶歇角", "FittingBooth":"试衣间", "LaundryBasket":"衣篓", "SewingWorkbench":"缝纫台", "CuttingTable":"裁剪台", "MaterialStorage":"材料柜", "Loom":"织机", "DyeVat":"染缸"}

func setup(host: Node) -> void:
	game = host
	_canvas = CanvasLayer.new()
	_canvas.layer = 24
	add_child(_canvas)
	_panel = PanelContainer.new()
	_panel.position = Vector2(22, 74)
	_panel.custom_minimum_size = Vector2(310, 0)
	_panel.add_theme_stylebox_override("panel", game._panel_style(Color("eee2cb"), Color("826348"), 2, 4))
	_canvas.add_child(_panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 14)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	column.add_child(game._section_label("布置小铺 · 暂停经营"))
	_items = OptionButton.new()
	_items.custom_minimum_size = Vector2(280, 40)
	_items.item_selected.connect(select_fixture)
	column.add_child(_items)
	var help := Label.new()
	help.text = "直接拖动家具，松手摆放。\nR / 滚轮旋转 · Shift 精细移动\n右键取消拖动 · Ctrl+Z 撤回"
	help.add_theme_color_override("font_color", Color("684c3e"))
	column.add_child(help)
	var move_grid := GridContainer.new()
	move_grid.columns = 2
	column.add_child(move_grid)
	for pair in [["向左", Vector2(-.25,0)], ["向右",Vector2(.25,0)], ["向后",Vector2(0,-.25)], ["向前",Vector2(0,.25)]]:
		var button: Button = game._make_text_button(pair[0], Vector2(138, 36))
		button.pressed.connect(move_preview.bind(pair[1]))
		move_grid.add_child(button)
	_add_button(column, "旋转 90°", rotate_preview)
	_add_button(column, "点击地面选位置", func() -> void:
		_pointer_placement = true
		_status.text = "请点击房间地面；右键取消选点。")
	_add_button(column, "确认摆放", commit)
	_add_button(column, "撤回上次摆放", undo)
	_add_button(column, "取消预览 / 返回经营", close)
	_status = Label.new()
	_status.custom_minimum_size.x = 280
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("684c3e"))
	column.add_child(_status)
	_panel.hide()
	_ghost = MeshInstance3D.new()
	_ghost.name = "FurniturePlacementOutline"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("dfa94a")
	mat.no_depth_test = true
	_ghost.material_override = mat
	game.add_child(_ghost)
	_ghost.hide()

func _add_button(parent: Node, title: String, callback: Callable) -> void:
	var button: Button = game._make_text_button(title, Vector2(280, 36))
	button.pressed.connect(callback)
	parent.add_child(button)

func open() -> void:
	if active: return
	if game.dragging_doll != null: return
	if game._wardrobe.visible: game._close_wardrobe()
	_return_speed = game._speed
	game._speed = 0.0
	game._view_controls.set_desktop(false)
	game._view_controls.set_page(1)
	game._view_controls.depth = 1.0
	game._view_controls.interaction_locked = true
	game._world_pressed_doll = null
	active = true
	_roof_pins.clear()
	for room in game._rooms.values():
		var roof: Node3D = room.get_node("HingedRoof")
		_roof_pins[roof] = roof._pinned.duplicate()
		roof._pinned = {-1:true,1:true}
		roof.animate_lids(1.0,0)
	_hud_was_visible = game.get_node("GameInterface/FloatingHUD").visible
	game.get_node("GameInterface/FloatingHUD").hide()
	_undo.clear()
	_items.clear()
	_fixtures.clear()
	for room_id in ["shop", "workshop", "archive"]:
		var room: Node3D = game._rooms[room_id]
		for entry in room._footprints:
			var node := entry.node as Node3D
			if not is_instance_valid(node): continue
			_fixtures.append(node)
			_items.add_item("%s / %s" % [game.ROOM_NAMES[room_id], NAMES.get(str(node.name), str(node.name))])
	_panel.show()
	var actions := game.get_node_or_null("ChapterActions")
	if actions != null: actions.hide()
	if not _fixtures.is_empty(): select_fixture(0)

func select_fixture(index: int, focus_camera := true) -> void:
	if index < 0 or index >= _fixtures.size(): return
	fixture = _fixtures[index]
	_items.select(index)
	proposed = fixture.transform
	for entry in fixture.get_parent()._footprints:
		if entry.node == fixture: _footprint = entry.rect
	if focus_camera:
		game._view_controls.focus_x = fixture.get_parent().global_position.x
		game._view_controls.pan_offset = Vector2.ZERO
		game._view_controls.apply_view()
	_status.text = "金色轮廓为预览；确认前家具保持原位。"
	_pointer_placement = false
	_refresh_ghost()

func move_preview(offset: Vector2) -> void:
	if not active or not is_instance_valid(fixture): return
	proposed.origin += Vector3(offset.x,0,offset.y)
	_refresh_ghost()

func rotate_preview() -> void:
	if not active or not is_instance_valid(fixture): return
	proposed.basis = Basis(Vector3.UP, PI * .5) * proposed.basis
	_refresh_ghost()

func _refresh_ghost() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners := [_footprint.position, Vector2(_footprint.end.x,_footprint.position.y), _footprint.end, Vector2(_footprint.position.x,_footprint.end.y)]
	for i in 4:
		for corner: Vector2 in [corners[i], corners[(i+1)%4]]:
			mesh.surface_add_vertex(Vector3(corner.x,.06,corner.y))
	# Crosshair and a front-direction tick make rotation legible.
	for point in [Vector3(-.2,.06,0),Vector3(.2,.06,0),Vector3(0,.06,-.2),Vector3(0,.06,.2),Vector3(0,.06,_footprint.end.y),Vector3(0,.06,_footprint.end.y+.4)]:
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	_ghost.mesh = mesh
	_ghost.global_transform = fixture.get_parent().global_transform * proposed
	_ghost.show()

func commit() -> Dictionary:
	if not active or not is_instance_valid(fixture): return {"ok":false,"reason":"请先选择家具"}
	var before := fixture.transform
	var result: Dictionary = game.try_place_fixture(fixture, proposed)
	if result.ok:
		_undo.append({"fixture":weakref(fixture),"before":before})
		_status.text = "已摆放。通道与操作空间检查通过。"
	else:
		_status.text = result.reason + "；预览保留，请调整后重试。"
	return result

func undo() -> void:
	if _undo.is_empty():
		_status.text = "本次布置尚无已确认的移动。"
		return
	var record: Dictionary = _undo.back()
	var node: Node3D = record.fixture.get_ref()
	if not is_instance_valid(node):
		_undo.pop_back()
		return
	var result: Dictionary = game.try_place_fixture(node, record.before)
	if result.ok:
		_undo.pop_back()
		if node == fixture:
			proposed = node.transform
			_refresh_ghost()
		_status.text = "已撤回上次摆放。"
	else: _status.text = result.reason

func close() -> void:
	if not active: return
	active = false
	_pointer_placement = false
	_dragging = false
	_panel.hide()
	_ghost.hide()
	game._view_controls.interaction_locked = false
	game._speed = _return_speed
	game._world_pressed_doll = null
	fixture = null
	for roof in _roof_pins:
		if is_instance_valid(roof): roof._pinned = _roof_pins[roof]
	_roof_pins.clear()
	game.get_node("GameInterface/FloatingHUD").visible = _hud_was_visible
	var actions := game.get_node_or_null("ChapterActions")
	if actions != null: actions.show()

func _ground_point(screen: Vector2) -> Variant:
	return Plane(Vector3.UP,0).intersects_ray(game.camera.project_ray_origin(screen),game.camera.project_ray_normal(screen))

func pick_fixture(screen: Vector2) -> int:
	var origin: Vector3 = game.camera.project_ray_origin(screen)
	var direction: Vector3 = game.camera.project_ray_normal(screen)
	var nearest := INF
	var selected := -1
	for i in _fixtures.size():
		for part in _fixtures[i].find_children("*","MeshInstance3D",true,false):
			if not part.is_visible_in_tree() or part.mesh == null: continue
			var inverse: Transform3D = part.global_transform.affine_inverse()
			var hit: Variant = part.get_aabb().intersects_ray(inverse * origin,inverse.basis * direction)
			if hit == null: continue
			var distance: float = origin.distance_squared_to(part.global_transform * hit)
			if distance < nearest:
				nearest = distance
				selected = i
	return selected

func _drag_to(screen: Vector2, fine: bool) -> void:
	var hit: Variant = _ground_point(screen)
	if hit == null or not is_instance_valid(fixture): return
	var local: Vector3 = fixture.get_parent().to_local(hit) + _drag_offset
	var step := .05 if fine else .25
	proposed.origin = Vector3(snappedf(local.x,step),0,snappedf(local.z,step))
	_refresh_ghost()
	_status.text = "拖动预览 · 松手摆放 · 右键取消\n位置 %.2f, %.2f" % [proposed.origin.x,proposed.origin.z]

func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseMotion and _dragging:
		_drag_to(event.position,event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			undo()
			get_viewport().set_input_as_handled()
			return
		match event.keycode:
			KEY_ESCAPE:
				if _dragging:
					_dragging = false
					proposed = _drag_start
					_refresh_ghost()
				else: close()
			KEY_LEFT: move_preview(Vector2(-.25,0))
			KEY_RIGHT: move_preview(Vector2(.25,0))
			KEY_UP: move_preview(Vector2(0,-.25))
			KEY_DOWN: move_preview(Vector2(0,.25))
			KEY_R:
				if not event.echo: rotate_preview()
			KEY_ENTER: commit()
			_: return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if not _dragging and _panel.get_global_rect().has_point(event.position): return
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_pointer_placement = false
			if _dragging:
				_dragging = false
				proposed = _drag_start
				_refresh_ghost()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			rotate_preview()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _pointer_placement and is_instance_valid(fixture):
			var origin: Vector3 = game.camera.project_ray_origin(event.position)
			var direction: Vector3 = game.camera.project_ray_normal(event.position)
			var hit: Variant = Plane(Vector3.UP,0).intersects_ray(origin,direction)
			if hit != null:
				var local: Vector3 = fixture.get_parent().to_local(hit)
				proposed.origin = Vector3(snappedf(local.x,.25),0,snappedf(local.z,.25))
				_refresh_ghost()
			_pointer_placement = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var picked := pick_fixture(event.position)
				if picked >= 0:
					select_fixture(picked, false)
					var hit: Variant = _ground_point(event.position)
					if hit != null:
						_drag_offset = proposed.origin - fixture.get_parent().to_local(hit)
						_drag_start = proposed
						_dragging = true
			elif _dragging:
				_dragging = false
				commit()
		get_viewport().set_input_as_handled()
