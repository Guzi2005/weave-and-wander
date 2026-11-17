extends Node
## Diegetic desktop: real 3D books and papers are the menu hit targets.
signal page_requested(key: String)

var game: Node
var active := false
var objects: Array[Dictionary] = []
var _root: Node3D
var _canvas: CanvasLayer
var _bar: HBoxContainer
var _hint: Label
var _return_speed := 1.0
var _hud_visible := true
var _hovered := ""
const FONT = preload("res://assets/fonts/jiangcheng-500w.ttf")

func setup(host: Node) -> void:
	game = host
	_root = Node3D.new()
	_root.name = "DeskManuscripts"
	game._pop_up.desk.add_child(_root)
	# Art direction: assets/art_direction/vendor_desk_direction.png, lower right.
	# Indigo cloth boards, ivory paper, sewn spines, red wax and gold tooling.
	_build_book("magazine", "织间来信", Vector3(-29,-1.14,4.0), -.12, Color("8e3e37"), true)
	_build_book("skills", "手艺札记", Vector3(-29,-1.14,14.0), .10, Color("284e5d"), false, .72)
	_build_book("strategy", "小铺方略", Vector3(39,-1.14,-4.0), -.16, Color("283f58"), false, .72)
	_build_book("ledger", "每日账簿", Vector3(29,-1.14,4.0), .13, Color("6d5646"), true)
	_build_envelope("save", "旅程存笺", Vector3(-37,-1.14,10.0), -.14)
	_build_book("catalog", "服饰图鉴", Vector3(37,-1.14,10.0), .18, Color("384b60"), false, .72)
	_canvas = CanvasLayer.new()
	_canvas.layer = 12
	add_child(_canvas)
	_bar = HBoxContainer.new()
	_bar.position = Vector2(24,24)
	_bar.add_theme_constant_override("separation",16)
	_canvas.add_child(_bar)
	var back: Button = game._make_text_button("收起手稿 · 返回小铺",Vector2(230,44))
	back.pressed.connect(leave_desktop)
	_bar.add_child(back)
	_hint = Label.new()
	_hint.text = "点击桌上的书册与信笺"
	_hint.add_theme_font_size_override("font_size",20)
	_hint.add_theme_color_override("font_color",Color("f2e4c5"))
	_hint.add_theme_color_override("font_outline_color",Color("302823"))
	_hint.add_theme_constant_override("outline_size",5)
	_bar.add_child(_hint)
	_bar.hide()

func _material(color: Color, paper := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = .94 if paper else .78
	if paper:
		mat.albedo_texture = preload("res://assets/workbench/artisan_workbench_book_encyclopedia_set_01_paper_diff_1k.jpg")
	else:
		mat.normal_enabled = true
		mat.normal_texture = preload("res://assets/workbench/artisan_workbench_rough_linen_nor_gl_1k.jpg")
		mat.normal_scale = .25
	return mat

func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, color: Color, paper := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = _material(color,paper)
	node.layers = 2
	parent.add_child(node)
	return node

func _text(parent: Node3D, title: String, at: Vector3, size := 85) -> void:
	var text := Label3D.new()
	text.text = title
	text.font = FONT
	text.font_size = size
	text.pixel_size = .018
	text.outline_size = 0
	text.modulate = Color("dec28b")
	text.position = at
	text.rotation_degrees.x = -90
	text.no_depth_test = false
	text.layers = 2
	parent.add_child(text)

func _build_book(key: String, title: String, at: Vector3, angle: float, color: Color, manuscript: bool, scale_value := 1.0) -> void:
	var book := Node3D.new()
	book.name = key.capitalize()
	book.position = at
	book.rotation.y = angle
	book.scale = Vector3.ONE * scale_value
	_root.add_child(book)
	_box(book,"LowerBoard",Vector3(0,.10,0),Vector3(8.8,.20,8.5),color)
	for i in 7:
		_box(book,"PaperSignature%d"%i,Vector3(0,.24+i*.065,0),Vector3(8.35,.055,8.05),Color("f1e1bc"),true)
	var top := .77
	_box(book,"Cover",Vector3(0,top,0),Vector3(8.8,.18,8.5),Color("ead9b0") if manuscript else color,manuscript)
	_box(book,"SewnSpine",Vector3(-4.38,.43,0),Vector3(.30,.76,8.5),color.darkened(.12))
	for z in [-3.5,-1.8,1.8,3.5]:
		_box(book,"SpineCord",Vector3(-4.55,.45,z),Vector3(.10,.86,.12),Color("c8aa65"))
	# A narrow gold-rule inset and cloth bookmark echo the approved study.
	for x in [-3.92,3.92]: _box(book,"Tooling",Vector3(x,top+.105,0),Vector3(.045,.015,7.7),Color("c4a65b"))
	for z in [-3.84,3.84]: _box(book,"Tooling",Vector3(0,top+.105,z),Vector3(7.88,.015,.045),Color("c4a65b"))
	_box(book,"Ribbon",Vector3(2,.20,4.6),Vector3(.85,.035,2.0),Color("993c36"))
	_box(book,"RibbonGold",Vector3(2,.225,4.8),Vector3(.06,.012,1.5),Color("d7b767"))
	if manuscript:
		for i in 7:
			_box(book,"RuledManuscript",Vector3(.1,top+.106,-1.0+i*.52),Vector3(6.6 if i%3 else 4.8,.012,.025),Color("ad9980"))
		for x in [-2.2,0.0,2.2]: _box(book,"LedgerRule",Vector3(x,top+.108,1.0),Vector3(.02,.012,4.3),Color("b9a98a"))
	_text(book,title,Vector3(0,top+.13,-2.3),82)
	_text(book,"WEAVE & WANDER",Vector3(0,top+.13,3.0),27)
	objects.append({"key":key,"title":title,"node":book,"bounds":Rect2(-4.5,-4.3,9,9.6),"height":top+.2})

func _build_envelope(key: String,title: String,at:Vector3,angle:float) -> void:
	var letter := Node3D.new()
	letter.name = "SealedSaveLetter"
	letter.position = at
	letter.rotation.y = angle
	_root.add_child(letter)
	_box(letter,"Envelope",Vector3(0,.08,0),Vector3(7.2,.16,4.5),Color("ebd6aa"),true)
	for side in [-1,1]:
		var seam := _box(letter,"FoldSeam",Vector3(side*1.8,.18,-.1),Vector3(4.5,.012,.035),Color("b5956b"))
		seam.rotation.y = side*.50
	var seal := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .63
	cylinder.bottom_radius = .70
	cylinder.height = .16
	cylinder.radial_segments = 14
	seal.mesh = cylinder
	seal.position = Vector3(0,.26,.05)
	seal.material_override = _material(Color("9e3938"))
	seal.layers = 2
	letter.add_child(seal)
	_text(letter,"W",Vector3(0,.35,.05),34)
	_text(letter,title,Vector3(0,.20,1.55),58)
	objects.append({"key":key,"title":title,"node":letter,"bounds":Rect2(-3.6,-2.25,7.2,4.5),"height":.35})

func enter_desktop() -> void:
	if active: return
	if game.dragging_doll != null: return
	if game._wardrobe.visible: game._close_wardrobe()
	if game._view_controls.interaction_locked: return
	active = true
	_return_speed = game._speed
	game._speed = 0.0
	var hud := game.get_node("GameInterface/FloatingHUD")
	_hud_visible = hud.visible
	hud.hide()
	var actions := game.get_node_or_null("ChapterActions")
	if actions != null: actions.hide()
	game._view_controls.set_desktop(true)
	_bar.show()

func leave_desktop() -> void:
	if not active: return
	if game.get("_progression_panel") != null and game._progression_panel.opened:
		game._progression_panel.close_page()
	active = false
	game._view_controls.set_desktop(false)
	game._speed = _return_speed
	game.get_node("GameInterface/FloatingHUD").visible = _hud_visible
	_bar.hide()
	var actions := game.get_node_or_null("ChapterActions")
	if actions != null: actions.show()
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func pick(point: Vector2) -> Dictionary:
	var origin: Vector3 = game.camera.project_ray_origin(point)
	var direction: Vector3 = game.camera.project_ray_normal(point)
	var best := {}
	var nearest := INF
	for entry in objects:
		var node: Node3D = entry.node
		var inverse := node.global_transform.affine_inverse()
		var local_origin: Vector3 = inverse * origin
		var local_direction: Vector3 = inverse.basis * direction
		var hit: Variant = Plane(Vector3.UP,float(entry.height)).intersects_ray(local_origin,local_direction)
		if hit != null and entry.bounds.has_point(Vector2(hit.x,hit.z)):
			var distance: float = origin.distance_squared_to(node.global_transform*hit)
			if distance < nearest:
				best = entry
				nearest = distance
	return best

func _process(_delta: float) -> void:
	if not active: return
	if game.get("_progression_panel") != null and game._progression_panel.opened: return
	var found := pick(get_viewport().get_mouse_position())
	var key := str(found.get("key",""))
	if key != _hovered:
		_hovered = key
		_hint.text = found.get("title","点击桌上的书册与信笺")
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if not key.is_empty() else Input.CURSOR_ARROW)

func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		leave_desktop()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var found := pick(event.position)
			if not found.is_empty(): page_requested.emit(found.key)
		get_viewport().set_input_as_handled()
