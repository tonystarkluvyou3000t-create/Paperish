extends CanvasLayer
## In-game furniture only: cash card, objective + timer, waypoint compass,
## context prompt, speedo, toast and the free-camera hint. Title, pause, options
## and results are owned by the menu layer (scripts/ui/menu_layer.gd); the HUD
## hides all run furniture unless the session reports gameplay visible.

const CREAM := Color("f8e5bc")
const IVORY := Color("fff3d7")
const TEAL := Color("326b69")
const INK := Color("283f49")
const RED := Color("c84436")
const GOLD := Color("f4bb4d")
const GREEN := Color("68b7a0")
const AMBER := Color("e8bb60")

const Snapshot = preload("res://scripts/services/game_snapshot.gd")
const MapView = preload("res://scripts/ui/map_view.gd")
var snapshot_provider: Callable
## Static map layers, handed over by Game once the world is bound.
var map_model: Dictionary = {}

var _cash_card: PanelContainer
var _money: Label
var _goal: Label
var _orders: Label
var _orders_row: HBoxContainer
var _strikes: Array[Label] = []
var _objective_vb: VBoxContainer
var _objective: Label
var _timer: ProgressBar
var _timer_styles: Array[StyleBoxFlat] = []
var _hint_card: PanelContainer
var _hint: Label
var _tip: Label
var _ticket_card: PanelContainer
var _ticket_id: Label
var _ticket_details: Label
var _ticket_status: Label
var _ticket_inventory: Label
var _prompt_panel: PanelContainer
var _prompt: Label
var _speed_panel: PanelContainer
var _speed: Label
var _way: Control
var _nav_card: PanelContainer
var _nav_map: Control
var _nav_hint: Label
var _nav_detail: Label
var _compass: Control
var _toast: Label
var _toast_t := 0.0
var _camera_hint: Label
## Preferences pushed by Game from SettingsService.
var text_speed := 1.0
var subtitles := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_waypoint()
	_build_cash_card()
	_build_objective()
	_build_hint()
	_build_ticket()
	_build_nav()
	_build_prompt()
	_build_camera_hint()
	_build_speed()
	_build_toast()


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
	_cash_card = _panel(CREAM, TEAL)
	_cash_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	_cash_card.offset_left = 18
	_cash_card.offset_top = 16
	add_child(_cash_card)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 2)
	_cash_card.add_child(vb)
	_money = _label("$0", 34, INK)
	vb.add_child(_money)
	_goal = _label("SHIFT GOAL  $150", 14, TEAL)
	vb.add_child(_goal)
	_orders = _label("DELIVERIES  0", 15, TEAL)
	vb.add_child(_orders)
	_orders_row = HBoxContainer.new()
	_orders_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orders_row.add_theme_constant_override("separation", 5)
	vb.add_child(_orders_row)
	for i in 3:
		var d := _label("●", 18, RED)
		_strikes.append(d)
		_orders_row.add_child(d)


func _build_objective() -> void:
	_objective_vb = VBoxContainer.new()
	_objective_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_vb.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE)
	_objective_vb.offset_top = 18
	_objective_vb.add_theme_constant_override("separation", 4)
	add_child(_objective_vb)
	_objective = _label("", 23, IVORY, true)
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_vb.add_child(_objective)
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
	_objective_vb.add_child(_timer)


func _build_hint() -> void:
	_hint_card = _panel(CREAM, TEAL, 10)
	_hint_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_hint_card.offset_left = -18
	_hint_card.offset_right = -18
	_hint_card.offset_top = 16
	_hint_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_hint_card)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_card.add_child(vb)
	_hint = _label("", 17, INK)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_hint)
	_tip = _label("", 14, RED)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_tip)


func _build_ticket() -> void:
	_ticket_card = _panel(CREAM, TEAL, 10)
	_ticket_card.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_ticket_card.offset_left = -18
	_ticket_card.offset_right = -18
	_ticket_card.offset_top = 100
	_ticket_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ticket_card.visible = false
	add_child(_ticket_card)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 3)
	_ticket_card.add_child(vb)
	_ticket_id = _label("ORDER", 16, RED)
	vb.add_child(_ticket_id)
	_ticket_details = _label("", 15, INK)
	_ticket_details.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_ticket_details)
	_ticket_status = _label("", 14, TEAL)
	_ticket_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_ticket_status)
	_ticket_inventory = _label("NO BOXES IN TRANSIT", 12, TEAL)
	_ticket_inventory.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_ticket_inventory)


## Phase 11 navigation display: a minimap with the route drawn on it, the turn
## hint for the active leg and the remaining distance. The mode comes from the
## NAVIGATION DISPLAY setting (map / compass only / off).
func _build_nav() -> void:
	_nav_card = _panel(Color(0.09, 0.14, 0.16, 0.86), GOLD, 10)
	_nav_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	_nav_card.offset_left = 18
	_nav_card.offset_bottom = -18
	_nav_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_nav_card.visible = false
	add_child(_nav_card)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 6)
	_nav_card.add_child(vb)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	_compass = Control.new()
	_compass.custom_minimum_size = Vector2(50.0, 50.0)
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compass.draw.connect(_draw_compass)
	head.add_child(_compass)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 2)
	head.add_child(text)
	_nav_hint = _label("", 20, GOLD)
	text.add_child(_nav_hint)
	_nav_detail = _label("", 14, IVORY)
	text.add_child(_nav_detail)
	_nav_map = MapView.new()
	_nav_map.custom_minimum_size = Vector2(262.0, 170.0)
	_nav_map.interactive = false
	_nav_map.follow_actor = true
	_nav_map.show_labels = false
	_nav_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_map.metres_per_pixel = 0.36
	vb.add_child(_nav_map)


## Draws once per frame: heading ring, north tick and an arrow toward whatever
## the current leg is pointing at, rotated into the actor's own facing.
func _draw_compass() -> void:
	if not snapshot_provider.is_valid():
		return
	var view: Snapshot = snapshot_provider.call()
	var centre := _compass.size * 0.5
	var radius: float = maxf(minf(_compass.size.x, _compass.size.y) * 0.42, 12.0)
	_compass.draw_arc(centre, radius, 0.0, TAU, 32, Color(0.98, 0.90, 0.72), 3.0)
	_compass.draw_line(centre + Vector2(0.0, -radius), centre + Vector2(0.0, -radius + 7.0), IVORY, 2.0)
	_compass.draw_circle(centre, 3.0, IVORY)
	var target: Vector3 = view.nav_target_point
	var delta := Vector2(target.x - view.actor_position.x, target.z - view.actor_position.z)
	if delta.length() < 0.2:
		return
	var bearing := atan2(delta.x, delta.y) - view.actor_yaw
	var dir := Vector2(sin(bearing), cos(bearing))
	var side := Vector2(-dir.y, dir.x)
	var tip := centre + dir * radius
	var tail := centre + dir * 6.0
	_compass.draw_line(tail, tip - dir * 9.0, GOLD, 3.0)
	_compass.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12.0 + side * 7.0,
		tip - dir * 12.0 - side * 7.0]), GOLD)
	_compass.draw_polyline(PackedVector2Array([tip, tip - dir * 12.0 + side * 7.0,
		tip - dir * 12.0 - side * 7.0, tip]), INK, 2.0)


func _update_nav(view: Snapshot, playing: bool) -> void:
	var mode: String = view.nav_mode
	var has_route: bool = view.route_target != "" or view.nav_reachable
	var show := playing and mode != "off" and has_route
	_nav_card.visible = show
	if not show:
		return
	_nav_map.visible = mode == "map"
	_nav_hint.text = view.nav_hint if view.nav_hint != "" else "ROUTE"
	_nav_detail.text = view.nav_detail if view.nav_detail != "" else "%d M" % roundi(view.nav_remaining_m)
	if mode == "map":
		var route_end: Vector3 = view.route_points[view.route_points.size() - 1] \
			if view.route_points.size() > 0 else Vector3.ZERO
		var tickets: Array = []
		for point in view.ticket_positions:
			if route_end != Vector3.ZERO and Vector2(point.x - route_end.x, point.z - route_end.z).length() < 0.8:
				continue
			tickets.append({"position": Vector2(point.x, point.z), "selected": false})
		_nav_map.model = map_model
		_nav_map.view = {
			"driving": view.driving,
			"player": Vector2(view.actor_position.x, view.actor_position.z),
			"player_yaw": view.actor_yaw,
			"van": Vector2(view.van_position.x, view.van_position.z),
			"van_yaw": view.van_yaw,
			"route": view.route_points,
			"route_drive_count": view.route_drive_count,
			"target": Vector2(route_end.x, route_end.z) if route_end != Vector3.ZERO else null,
			"tickets": tickets,
			"waypoint": view.waypoint_map if view.waypoint_set else null,
		}
	_compass.queue_redraw()


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


func toast(text: String) -> void:
	_toast.text = text
	_toast_t = 1.6 * text_speed
	_toast.modulate.a = 1.0
	_toast.scale = Vector2(0.9, 0.9)


## Flavour captions ("NEW ORDER · ...", "TIP · ...") ride the SUBTITLES
## preference: they caption the chimes and the voices this island does not have.
## `toast` stays for feedback the player must not miss (refusals, strikes).
func caption(text: String) -> void:
	if not subtitles:
		return
	toast(text)


func clear_toast() -> void:
	_toast_t = 0.0
	_toast.text = ""
	_toast.modulate.a = 0.0


func _process(delta: float) -> void:
	if not snapshot_provider.is_valid():
		return
	var view: Snapshot = snapshot_provider.call()
	var playing: bool = view.gameplay_visible
	var roam: bool = view.play_mode == "roam"
	_cash_card.visible = playing and not roam
	_goal.visible = playing and not roam
	_orders.visible = playing and not roam
	_orders_row.visible = playing and not roam
	_money.text = "$%d" % view.money
	_goal.text = "SHIFT GOAL  $%d" % view.goal_money
	_orders.text = "DELIVERIES  %d" % view.deliveries
	for i in _strikes.size():
		_strikes[i].add_theme_color_override("font_color", RED if i < view.strikes else Color(0.72, 0.68, 0.60))
	_objective_vb.visible = playing
	_objective.text = view.objective_text
	_objective.visible = view.objective_text != ""
	_timer.visible = view.timer_visible
	if view.timer_visible:
		_timer.max_value = maxf(view.timer_max, 0.01)
		_timer.value = view.timer
		var frac: float = view.timer / maxf(view.timer_max, 0.01)
		var idx: int = 0 if frac > 0.45 else (1 if frac > 0.2 else 2)
		_timer.add_theme_stylebox_override("fill", _timer_styles[idx])
	_hint_card.visible = playing
	if roam:
		_hint.text = "FREE ROAM  ·  no clock"
		_hint.visible = true
		_tip.visible = false
	else:
		_hint.text = view.target_label
		_hint.visible = view.target_label != ""
		_tip.text = view.target_sub
		_tip.visible = view.target_sub != ""
	var has_ticket := view.order_count > 0 and not roam
	_ticket_card.visible = playing and has_ticket
	if has_ticket:
		_ticket_id.text = "ORDER #%02d" % view.order_id
		_ticket_details.text = "%s\n%s  ·  %d %s" % [
			view.destination_id.to_upper(), view.ticket_customer.to_upper(), view.order_pizzas,
			"PIZZA" if view.order_pizzas == 1 else "PIZZAS"]
		match view.ticket_state:
			"preparing":
				_ticket_status.text = "PREPARING  ·  %d SEC" % ceili(view.preparation_remaining)
				_ticket_status.add_theme_color_override("font_color", RED)
			"ready":
				_ticket_status.text = "READY AT THE COUNTER"
				_ticket_status.add_theme_color_override("font_color", TEAL)
			"collected":
				_ticket_status.text = "COLLECTED  ·  %d SEC LEFT" % ceili(view.timer)
				_ticket_status.add_theme_color_override("font_color", TEAL)
			_:
				_ticket_status.text = ""
		_ticket_inventory.text = "TICKETS & CARGO\n%s" % view.cargo_inventory
	_prompt_panel.visible = playing and view.prompt_text != ""
	_prompt.text = view.prompt_text
	_camera_hint.visible = playing and view.camera_hint != ""
	_camera_hint.text = view.camera_hint
	_speed_panel.visible = playing and view.driving
	_speed.text = "%d km/h" % round(view.speed_kmh)
	_update_nav(view, playing)
	# Gameplay feedback must never float over the title or the results screen.
	if not playing:
		_toast_t = 0.0
		_toast.modulate.a = 0.0
	elif _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.9, 0.0, 1.0)
		_toast.scale = _toast.scale.lerp(Vector2(1.0, 1.0), clampf(delta * 8.0, 0.0, 1.0))
	_way.queue_redraw()


func _draw_way() -> void:
	if not snapshot_provider.is_valid():
		return
	var view: Snapshot = snapshot_provider.call()
	if not view.waypoint_visible or not view.gameplay_visible or view.nav_mode == "off":
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var wp: Vector3 = view.waypoint_position
	var behind := cam.is_position_behind(wp)
	# Convert the projected viewport pixel into this Control's canvas space so
	# the marker stays aligned at any UI/content scale.
	var p: Vector2 = _way.get_global_transform_with_canvas().affine_inverse() * cam.unproject_position(wp)
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
