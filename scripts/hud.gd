extends CanvasLayer
## All on-screen furniture: cash card, objective + timer, waypoint compass,
## context prompt, speedo, title, pause and shift summary. Built in code so the
## whole HUD can be re-tuned from one file.

const CREAM := Color("f8e5bc")
const IVORY := Color("fff3d7")
const TEAL := Color("326b69")
const INK := Color("283f49")
const RED := Color("c84436")
const GOLD := Color("f4bb4d")
const GREEN := Color("68b7a0")
const AMBER := Color("e8bb60")

const Snapshot = preload("res://scripts/services/game_snapshot.gd")
var snapshot_provider: Callable

var _money: Label
var _goal: Label
var _orders: Label
var _strikes: Array[Label] = []
var _objective: Label
var _timer: ProgressBar
var _timer_styles: Array[StyleBoxFlat] = []
var _hint: Label
var _tip: Label
var _prompt_panel: PanelContainer
var _prompt: Label
var _speed_panel: PanelContainer
var _speed: Label
var _way: Control
var _title: Control
var _title_blink: Label
var _summary: Control
var _summary_title: Label
var _summary_body: Label
var _pause: Control
var _toast: Label
var _toast_t := 0.0
var _camera_hint: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_waypoint()
	_build_cash_card()
	_build_objective()
	_build_hint()
	_build_prompt()
	_build_camera_hint()
	_build_speed()
	_build_toast()
	_build_title()
	_build_summary()
	_build_pause()


func _panel(bg: Color, border: Color, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, size: int, color: Color, outline := false) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", INK)
	return l


func _build_cash_card() -> void:
	var card := _panel(CREAM, TEAL)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	card.offset_left = 18
	card.offset_top = 16
	add_child(card)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	_money = _label("$0", 34, INK)
	vb.add_child(_money)
	_goal = _label("SHIFT GOAL  $150", 14, TEAL)
	vb.add_child(_goal)
	_orders = _label("DELIVERIES  0", 15, TEAL)
	vb.add_child(_orders)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	vb.add_child(row)
	for i in 3:
		var d := _label("●", 18, RED)
		_strikes.append(d)
		row.add_child(d)


func _build_objective() -> void:
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	vb.offset_top = 18
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	_objective = _label("", 23, IVORY, true)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_objective)
	_timer = ProgressBar.new()
	_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer.show_percentage = false
	_timer.custom_minimum_size = Vector2(430, 15)
	_timer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_timer.min_value = 0.0
	_timer.max_value = 60.0
	for c in [GREEN, AMBER, RED]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		_timer_styles.append(sb)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.14, 0.16, 0.75)
	bg.set_corner_radius_all(6)
	bg.set_border_width_all(2)
	bg.border_color = INK
	_timer.add_theme_stylebox_override("background", bg)
	_timer.add_theme_stylebox_override("fill", _timer_styles[0])
	vb.add_child(_timer)


func _build_hint() -> void:
	var card := _panel(CREAM, TEAL, 10)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	card.offset_left = -18
	card.offset_right = -18
	card.offset_top = 16
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(card)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)
	_hint = _label("", 17, INK)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_hint)
	_tip = _label("", 14, RED)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_tip)


func _build_prompt() -> void:
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	bottom.offset_top = -74
	bottom.offset_bottom = -22
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom)
	_prompt_panel = _panel(Color(0.09, 0.14, 0.16, 0.82), GOLD, 14)
	bottom.add_child(_prompt_panel)
	_prompt = _label("", 19, IVORY)
	_prompt_panel.add_child(_prompt)


func _build_camera_hint() -> void:
	# One brief mode label + control hint line; only the free camera shows it.
	_camera_hint = _label("", 18, CREAM, true)
	_camera_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	_camera_hint.offset_top = -108
	_camera_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camera_hint.visible = false
	add_child(_camera_hint)


func _build_speed() -> void:
	_speed_panel = _panel(CREAM, TEAL, 12)
	_speed_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_speed_panel.offset_left = -18
	_speed_panel.offset_right = -18
	_speed_panel.offset_top = -20
	_speed_panel.offset_bottom = -20
	_speed_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_speed_panel)
	_speed = _label("0 km/h", 22, INK)
	_speed_panel.add_child(_speed)


func _build_toast() -> void:
	_toast = _label("", 26, GOLD, true)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_toast.offset_top = 96
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.modulate.a = 0.0
	add_child(_toast)


func _build_waypoint() -> void:
	_way = Control.new()
	_way.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_way.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_way)
	_way.draw.connect(_draw_way)


func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.11, 0.13, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	center.add_child(vb)
	var t1 := _label("PIP THE PIZZA BOY", 62, IVORY, true)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t1)
	var t2 := _label("hot pizza, small island, sharp clock", 22, GOLD)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t2)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 18)
	vb.add_child(pad)
	for line in ["W A S D      walk  ·  drive",
			"E               enter van  ·  pick up  ·  deliver",
			"SPACE        handbrake          H   horn",
			"RIGHT-DRAG orbit  ·  WHEEL zoom  ·  C  recenter  ·  F  free camera",
			"ESC           pause                R   restart from pause/results"]:
		var l := _label(line, 18, IVORY)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
	var pad2 := Control.new()
	pad2.custom_minimum_size = Vector2(0, 14)
	vb.add_child(pad2)
	_title_blink = _label("PRESS ENTER TO START YOUR SHIFT", 24, GOLD, true)
	_title_blink.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_title_blink)


func _build_summary() -> void:
	_summary = Control.new()
	_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.visible = false
	add_child(_summary)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.11, 0.13, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary.add_child(center)
	var card := _panel(CREAM, TEAL, 26)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	_summary_title = _label("SHIFT COMPLETE", 42, INK)
	_summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_summary_title)
	_summary_body = _label("", 19, TEAL)
	_summary_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_summary_body)
	vb.add_child(_label("PRESS R TO DRIVE AGAIN", 20, RED))


func _build_pause() -> void:
	_pause = Control.new()
	_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause.visible = false
	add_child(_pause)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(center)
	var card := _panel(Color(0.09, 0.14, 0.16, 0.85), GOLD, 22)
	center.add_child(card)
	var vb := VBoxContainer.new()
	card.add_child(vb)
	vb.add_child(_label("PAUSED", 34, IVORY))
	vb.add_child(_label("ESC to get back on the road", 17, CREAM))
	vb.add_child(_label("R to return to the title and reset the shift", 17, CREAM))


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.6
	_toast.modulate.a = 1.0
	_toast.scale = Vector2(0.9, 0.9)


func clear_toast() -> void:
	_toast_t = 0.0
	_toast.text = ""
	_toast.modulate.a = 0.0


func show_title(on: bool) -> void:
	_title.visible = on


func show_summary(on: bool) -> void:
	_summary.visible = on


func set_summary(title: String, body: String) -> void:
	_summary_title.text = title
	_summary_body.text = body


func show_pause(on: bool) -> void:
	_pause.visible = on


func _process(delta: float) -> void:
	if not snapshot_provider.is_valid():
		return
	var view: Snapshot = snapshot_provider.call()
	_money.text = "$%d" % view.money
	_goal.text = "SHIFT GOAL  $%d" % view.goal_money
	_orders.text = "DELIVERIES  %d" % view.deliveries
	for i in _strikes.size():
		_strikes[i].add_theme_color_override("font_color", RED if i < view.strikes else Color(0.72, 0.68, 0.60))
	_objective.text = view.objective_text
	_objective.visible = view.objective_text != ""
	_timer.visible = view.timer_visible
	if view.timer_visible:
		_timer.max_value = maxf(view.timer_max, 0.01)
		_timer.value = view.timer
		var frac: float = view.timer / maxf(view.timer_max, 0.01)
		var idx: int = 0 if frac > 0.45 else (1 if frac > 0.2 else 2)
		_timer.add_theme_stylebox_override("fill", _timer_styles[idx])
	_hint.text = view.target_label
	_hint.visible = view.target_label != ""
	_tip.text = view.target_sub
	_tip.visible = view.target_sub != ""
	_prompt_panel.visible = view.prompt_text != ""
	_prompt.text = view.prompt_text
	_camera_hint.visible = view.camera_hint != ""
	_camera_hint.text = view.camera_hint
	_speed_panel.visible = view.driving
	_speed.text = "%d km/h" % round(view.speed_kmh)
	if _title.visible:
		_title_blink.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 300.0)
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.9, 0.0, 1.0)
		_toast.scale = _toast.scale.lerp(Vector2(1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	_way.queue_redraw()


func _draw_way() -> void:
	if not snapshot_provider.is_valid():
		return
	var view: Snapshot = snapshot_provider.call()
	if not view.waypoint_visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var wp: Vector3 = view.waypoint_position
	var behind := cam.is_position_behind(wp)
	var p := cam.unproject_position(wp)
	var vp := _way.size
	if behind:
		p = vp * 0.5 - (p - vp * 0.5)
	var m := 60.0
	var on_screen := p.x > m and p.x < vp.x - m and p.y > m and p.y < vp.y - m
	var col: Color = view.waypoint_color
	# measure from the avatar doing the job (van while driving, else Pip),
	# not from the chase camera - the camera sits 13 m back while driving
	var dist := view.actor_position.distance_to(wp)
	if on_screen:
		var d := 15.0
		_way.draw_colored_polygon(PackedVector2Array([
			p + Vector2(0, -d), p + Vector2(d * 0.8, 0), p + Vector2(0, d), p + Vector2(-d * 0.8, 0)]), col)
		_way.draw_polyline(PackedVector2Array([
			p + Vector2(0, -d), p + Vector2(d * 0.8, 0), p + Vector2(0, d), p + Vector2(-d * 0.8, 0),
			p + Vector2(0, -d)]), INK, 2.0)
		_way.draw_string_outline(ThemeDB.fallback_font, p + Vector2(20, 6), "%d m" % round(dist),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, INK)
		_way.draw_string(ThemeDB.fallback_font, p + Vector2(20, 6), "%d m" % round(dist),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, IVORY)
	else:
		var dir := (p - vp * 0.5)
		if dir.length() < 0.01:
			dir = Vector2(0, 1)
		dir = dir.normalized()
		var c := vp * 0.5 + dir * (minf(vp.x, vp.y) * 0.37)
		var side := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array([c + dir * 20.0, c - dir * 12.0 + side * 13.0, c - dir * 12.0 - side * 13.0])
		_way.draw_colored_polygon(pts, col)
		_way.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), INK, 2.0)
		_way.draw_string_outline(ThemeDB.fallback_font, c - dir * 30.0 + Vector2(-24, 6), "%d m" % round(dist),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, INK)
		_way.draw_string(ThemeDB.fallback_font, c - dir * 30.0 + Vector2(-24, 6), "%d m" % round(dist),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, IVORY)
