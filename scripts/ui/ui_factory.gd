extends RefCounted
## Shared menu theme: palette, panels, labels, buttons, sliders and choice
## steppers. Menus are built from these helpers so the look lives in one file
## while each screen owns its own layout.

const CREAM := Color("f8e5bc")
const IVORY := Color("fff3d7")
const TEAL := Color("326b69")
const INK := Color("283f49")
const RED := Color("c84436")
const GOLD := Color("f4bb4d")
const GREEN := Color("68b7a0")
const AMBER := Color("e8bb60")
const DISABLED := Color("8a8577")


static func _box(bg: Color, border: Color, width: int, pad := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(10)
	if pad > 0:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = pad * 0.7
		sb.content_margin_bottom = pad * 0.7
	return sb


static func panel(bg := CREAM, border := TEAL, pad := 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(bg, border, 3, pad))
	return p


static func dark_panel(pad := 20) -> PanelContainer:
	return panel(Color(0.09, 0.14, 0.16, 0.92), GOLD, pad)


static func label(text: String, size: int, color: Color, outline := false) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", INK)
	return l


static func dim(alpha := 0.6) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.06, 0.11, 0.13, alpha)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect


static func button(text: String, min_width := 320.0, size := 21) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 48)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _box(CREAM, TEAL, 3))
	b.add_theme_stylebox_override("hover", _box(AMBER, TEAL, 3))
	b.add_theme_stylebox_override("pressed", _box(GOLD, INK, 3))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), GOLD, 4))
	b.add_theme_stylebox_override("disabled", _box(Color(0.85, 0.82, 0.74), DISABLED, 3))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK)
	b.add_theme_color_override("font_disabled_color", DISABLED)
	return b


static func small_button(text: String, min_width := 44.0) -> Button:
	var b := button(text, min_width, 18)
	b.custom_minimum_size = Vector2(min_width, 40)
	return b


static func toggle_button(on: bool, min_width := 110.0) -> Button:
	var b := button("ON", min_width, 18)
	b.custom_minimum_size = Vector2(min_width, 40)
	refresh_toggle(b, on)
	return b


static func refresh_toggle(b: Button, on: bool) -> void:
	b.text = "ON" if on else "OFF"
	b.add_theme_stylebox_override("normal", _box(GREEN if on else CREAM, TEAL, 3))
	b.add_theme_color_override("font_color", INK if on else TEAL)


static func slider(min_value: float, max_value: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_value
	s.max_value = max_value
	s.step = step
	s.custom_minimum_size = Vector2(240, 34)
	s.focus_mode = Control.FOCUS_ALL
	s.add_theme_stylebox_override("slider", _box(Color(0.16, 0.22, 0.24, 0.9), INK, 2))
	s.add_theme_stylebox_override("grabber_area", _box(GOLD, INK, 0))
	s.add_theme_stylebox_override("grabber_area_highlight", _box(AMBER, INK, 0))
	return s


static func column(separation := 8) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", separation)
	return vb


static func row(separation := 12) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", separation)
	return hb


static func spacer(height: float) -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, height)
	return pad


## Center `content` on `screen` inside a full-rect scroll area. Cards fit any UI
## scale; when the content is taller than the view, it scrolls and focus follows.
static func centered(screen: Control, content: Control, content_name := "Card") -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(scroll)
	var center := CenterContainer.new()
	center.name = "Center"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(center)
	content.name = content_name
	center.add_child(content)
	return scroll


static func scroll(max_height: float) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size = Vector2(0, max_height)
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus = true
	return s
