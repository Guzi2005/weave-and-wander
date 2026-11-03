extends Button

const INK := Color("445758")
const ACTIVE := Color("487d74")


func configure(symbol: String, description: String, toggle: bool = false) -> void:
	custom_minimum_size = Vector2(48,48)
	icon = load("res://assets/icons/%s.svg"%symbol)
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_constant_override("icon_max_width",24)
	tooltip_text = description
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	toggle_mode = toggle
	add_theme_color_override("icon_normal_color",INK)
	add_theme_color_override("icon_hover_color",INK)
	add_theme_color_override("icon_pressed_color",Color.WHITE)
	add_theme_color_override("icon_hover_pressed_color",Color.WHITE)
	add_theme_color_override("icon_disabled_color",Color("a6b4b0"))
	add_theme_stylebox_override("normal",_style(Color("f5f5ed"),Color(1,1,1,.6)))
	add_theme_stylebox_override("hover",_style(Color("e1ede5"),Color("91b1a5")))
	add_theme_stylebox_override("pressed",_style(ACTIVE,ACTIVE.lightened(.15)))
	var inactive := _style(Color("e5eae5"),Color.TRANSPARENT)
	inactive.shadow_size = 0
	add_theme_stylebox_override("disabled",inactive)
	var focus := _style(Color(0,0,0,0),Color("d3a84e"))
	focus.shadow_size = 0
	focus.set_border_width_all(2)
	add_theme_stylebox_override("focus",focus)


func _style(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(0)
	style.set_corner_radius_all(24)
	style.shadow_color = Color(.16,.23,.24,.13)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0,3)
	style.set_content_margin_all(10)
	return style
