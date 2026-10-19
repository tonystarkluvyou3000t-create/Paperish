extends Control
## Phase 11 Milestone B: the full town map. Districts, addresses, POIs and
## recovery anchors come from the authored catalog; the route, tickets and
## markers come from the live session. It is a planning tool, not a pilot: the
## stop list shows the player's own order, with arrival-window comparisons and
## never an automatic re-order.
##
## Every write it performs goes through the Game (`map_select_order`,
## `map_move_stop`, `map_set_waypoint`, `map_clear_waypoint`, `unstuck`), so no
## screen touches session, order or actor state behind the Game's back.

const UIF = preload("res://scripts/ui/ui_factory.gd")
const MapView = preload("res://scripts/ui/map_view.gd")

const LEGEND := [
	{"shape": "square", "text": "PIZZA SHOP"},
	{"shape": "diamond", "text": "SELECTED DROP-OFF"},
	{"shape": "triangle", "text": "OTHER TICKET"},
	{"shape": "arrow", "text": "DELIVERY VAN"},
	{"shape": "arrow", "text": "PLAYER ON FOOT"},
	{"shape": "pin", "text": "WAYPOINT"},
	{"shape": "ring", "text": "RECOVERY ANCHOR"},
]

var game: Node
var settings: Node
var map: Control

var _stops: VBoxContainer
var _summary: Label
var _hint: Label
var _status: Label
var _zoom_label: Label
var _unstuck: Button
var _waypoint_toggle: Button
var _waypoint_clear: Button
var _back_callback: Callable = func() -> void: pass
var _refresh_t := 0.0
var _stops_signature := ""
var _home_center := Vector2.ZERO
var _home_zoom := 0.24
var _fitted := false


func setup(game_node: Node, settings_node: Node, back_callback: Callable) -> void:
	game = game_node
	settings = settings_node
	_back_callback = back_callback
	_build()
	_refresh()


func _build() -> void:
	add_child(UIF.dim(0.72))
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 18)
	root.add_theme_constant_override("margin_right", 18)
	root.add_theme_constant_override("margin_top", 14)
	root.add_theme_constant_override("margin_bottom", 14)
	add_child(root)
	var column := UIF.column(10)
	root.add_child(column)
	column.add_child(_build_header())
	var body := UIF.row(14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(_build_map())
	body.add_child(_build_side())


func _build_header() -> Control:
	var header := UIF.row(12)
	var title := UIF.label("TOWN MAP", 30, UIF.IVORY, true)
	header.add_child(title)
	_summary = UIF.label("", 17, UIF.CREAM)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_summary)
	_hint = UIF.label("", 17, UIF.GOLD)
	header.add_child(_hint)
	return header


func _build_map() -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("e7d7b4")
	sb.border_color = UIF.TEAL
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", sb)
	map = MapView.new()
	map.name = "MapView"
	map.interactive = true
	map.show_labels = true
	map.follow_actor = false
	map.waypoint_requested.connect(_on_waypoint_requested)
	map.focus_mode = Control.FOCUS_ALL
	map.model = game.map_model()
	var bounds: Rect2 = map.model.bounds
	_home_center = bounds.position + bounds.size * 0.5
	map.center = _home_center
	frame.add_child(map)
	set_meta("initial_focus", map)
	return frame


func _build_side() -> Control:
	var panel := UIF.dark_panel(14)
	panel.custom_minimum_size = Vector2(430.0, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := UIF.column(8)
	panel.add_child(column)

	column.add_child(UIF.label("STOPS  ·  YOUR ORDER, NEVER RE-SORTED", 16, UIF.GOLD))
	_stops = UIF.column(6)
	var stops_scroll := UIF.scroll(360.0)
	stops_scroll.add_child(_stops)
	column.add_child(stops_scroll)

	var map_row := UIF.row(8)
	var zoom_out := UIF.small_button("− ZOOM")
	map_row.add_child(zoom_out)
	var zoom_in := UIF.small_button("+ ZOOM")
	map_row.add_child(zoom_in)
	var recenter := UIF.small_button("WHOLE TOWN")
	map_row.add_child(recenter)
	var follow := UIF.small_button("FOLLOW ME")
	map_row.add_child(follow)
	_zoom_label = UIF.label("", 14, UIF.CREAM)
	map_row.add_child(_zoom_label)
	column.add_child(map_row)
	zoom_out.pressed.connect(func() -> void: map.zoom_by(1.25))
	zoom_in.pressed.connect(func() -> void: map.zoom_by(0.8))
	recenter.pressed.connect(func() -> void:
		map.zoom_to(_home_zoom)
		map.center = _home_center
		map.follow_actor = false)
	follow.pressed.connect(func() -> void: map.recenter_on_actor())

	var way_row := UIF.row(8)
	_waypoint_toggle = UIF.small_button("SET WAYPOINT")
	_waypoint_toggle.toggle_mode = true
	way_row.add_child(_waypoint_toggle)
	_waypoint_clear = UIF.small_button("CLEAR WAYPOINT")
	way_row.add_child(_waypoint_clear)
	column.add_child(way_row)
	_waypoint_toggle.toggled.connect(func(on: bool) -> void: map.waypoint_mode = on; map.queue_redraw())
	_waypoint_clear.pressed.connect(func() -> void:
		game.map_clear_waypoint()
		_refresh())

	column.add_child(UIF.label("SYMBOLS  ·  every marker is a shape, not just a colour", 14, UIF.CREAM))
	for entry in LEGEND:
		var row := UIF.row(8)
		row.add_child(_LegendMark.new(str(entry.shape)))
		row.add_child(UIF.label(str(entry.text), 15, UIF.CREAM))
		column.add_child(row)

	column.add_child(UIF.label("A blocked or unreachable route is named on the map; nothing"
		+ " is delivered or re-ordered for you.", 14, UIF.CREAM))

	_status = UIF.label("", 15, UIF.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	var actions := UIF.row(8)
	_unstuck = UIF.button("UNSTUCK", 210, 18)
	actions.add_child(_unstuck)
	var close := UIF.button("CLOSE MAP  (M / ESC)", 240, 18)
	actions.add_child(close)
	column.add_child(actions)
	_unstuck.pressed.connect(func() -> void:
		game.unstuck()
		_refresh())
	close.pressed.connect(func() -> void: _back_callback.call())
	return panel


## A tiny shape swatch so the legend matches the map exactly.
class _LegendMark extends Control:
	var shape := "square"
	func _init(kind: String) -> void:
		shape = kind
		custom_minimum_size = Vector2(26.0, 26.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		match shape:
			"square":
				draw_rect(Rect2(c - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), UIF.GOLD)
				draw_rect(Rect2(c - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), UIF.INK, false, 2.0)
			"diamond":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -9.0), c + Vector2(9.0, 0.0),
					c + Vector2(0.0, 9.0), c + Vector2(-9.0, 0.0)]), UIF.GREEN)
				draw_arc(c, 12.0, 0.0, TAU, 24, UIF.GREEN, 2.0)
			"triangle":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -9.0), c + Vector2(9.0, 7.0),
					c + Vector2(-9.0, 7.0)]), Color("3f8ea6"))
			"arrow":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0.0, -9.0), c + Vector2(7.0, 8.0),
					c + Vector2(0.0, 3.0), c + Vector2(-7.0, 8.0)]), UIF.RED)
			"pin":
				draw_circle(c + Vector2(0.0, -4.0), 6.0, Color("fdf6e3"))
				draw_arc(c + Vector2(0.0, -4.0), 6.0, 0.0, TAU, 20, UIF.INK, 2.0)
				draw_line(c + Vector2(0.0, 2.0), c + Vector2(0.0, 8.0), UIF.INK, 2.0)
			"ring":
				draw_arc(c, 7.0, 0.0, TAU, 24, Color("8a8577"), 2.0)
				draw_line(c + Vector2(-7.0, 0.0), c + Vector2(7.0, 0.0), Color("8a8577"), 2.0)
				draw_line(c + Vector2(0.0, -7.0), c + Vector2(0.0, 7.0), Color("8a8577"), 2.0)


func _process(delta: float) -> void:
	if map == null:
		return
	if not _fitted and map.size.x > 32.0 and map.size.y > 32.0:
		_fitted = true
		var bounds: Rect2 = map.model.bounds
		_home_zoom = maxf(bounds.size.x / map.size.x, bounds.size.y / map.size.y) * 1.06
		_home_center = bounds.position + bounds.size * 0.5
		map.zoom_to(_home_zoom)
		map.center = _home_center
	map.view = game.map_view_state()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.3
		_refresh()


## The menu layer calls this whenever the map becomes the top screen, so the stop
## list and status line are current the instant it opens instead of waiting for
## the 0.3 s background tick.
func refresh_values() -> void:
	_refresh()


## Rebuilds the stop list and status text from the live order and route state.
## The rows are only rebuilt when their content changed, so a controller or
## keyboard player never loses focus to a background refresh.
func _refresh() -> void:
	if game == null:
		return
	var rows: Array = game.map_ticket_rows()
	var signature := ""
	for row in rows:
		signature += "%d|%s|%s|%d|%d|%d|%d|%d;" % [int(row.order_id), str(row.address),
			str(row.state), roundi(float(row.leg_seconds)), roundi(float(row.cumulative_seconds)),
			roundi(float(row.window_seconds)), 1 if bool(row.window_active) else 0,
			1 if bool(row.selected) else 0]
	if signature != _stops_signature:
		_stops_signature = signature
		for child in _stops.get_children():
			child.queue_free()
		if rows.is_empty():
			_stops.add_child(UIF.label("NO OUTSTANDING TICKETS", 16, UIF.CREAM))
		for row in rows:
			_stops.add_child(_stop_row(row))
	var plan := PackedStringArray()
	for row in rows:
		plan.append("#%02d" % int(row.order_id))
	_summary.text = "PLAN  %s       SELECTED  #%02d" % [
		" → ".join(plan) if plan.size() > 0 else "—", int(game.orders.order_id)]
	var guidance: Dictionary = game.routes.guidance()
	_hint.text = "" if not guidance.has("hint") else "%s  ·  %s" % [
		str(guidance.get("hint", "")), str(guidance.get("detail", ""))]
	var reachable := bool(guidance.get("reachable", false))
	var route_target := str(game.routes.target())
	if route_target.is_empty():
		_status.add_theme_color_override("font_color", UIF.CREAM)
		_status.text = "No active route: collect the order at the counter or accept another ticket."
	elif reachable:
		_status.add_theme_color_override("font_color", UIF.GREEN)
		_status.text = "%s is reachable  ·  conservative estimate %s" % [
			route_target.to_upper(), _clock(float(guidance.get("eta_seconds", INF)))]
	else:
		_status.add_theme_color_override("font_color", UIF.RED)
		_status.text = "NO LEGAL ROUTE TO %s  ·  %s" % [
			route_target.to_upper(), str(guidance.get("detail", "blocked"))]
	_unstuck.text = game.unstuck_label()
	_unstuck.disabled = not game.unstuck_available()
	_waypoint_clear.disabled = not game.routes.has_waypoint()
	_zoom_label.text = "%.2f m/px" % map.metres_per_pixel


func _stop_row(row: Dictionary) -> Control:
	var card := UIF.panel(Color("fdf6e3"), UIF.TEAL, 8)
	var column := UIF.column(2)
	card.add_child(column)
	var header := UIF.row(8)
	var marker := UIF.label("#%02d" % int(row.order_id), 17, UIF.RED if bool(row.selected) else UIF.INK)
	header.add_child(marker)
	var title := UIF.label(str(row.address).to_upper(), 16, UIF.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var district := UIF.label(str(row.district).to_upper(), 13, UIF.TEAL)
	header.add_child(district)
	column.add_child(header)

	var detail := "%s  ·  %s" % [str(row.state).to_upper(), str(row.cargo)]
	column.add_child(UIF.label(detail, 13, UIF.TEAL))
	if bool(row.reachable):
		var timing := "LEG %s  ·  ARRIVAL %s" % [
			_clock(float(row.leg_seconds)), _clock(float(row.cumulative_seconds))]
		if bool(row.window_active):
			timing += "  ·  WINDOW %s" % _clock(float(row.window_seconds))
		column.add_child(UIF.label(timing, 13, UIF.INK))
		if bool(row.window_active):
			var slack := float(row.slack_seconds)
			if slack >= 0.0:
				column.add_child(UIF.label("ON TIME  ·  %s SPARE" % _clock(slack), 14, UIF.GREEN))
			else:
				column.add_child(UIF.label("LATE BY %s" % _clock(-slack), 14, UIF.RED))
		else:
			column.add_child(UIF.label("WINDOW %s STARTS WHEN THE PIZZAS ARE COLLECTED" \
				% _clock(float(row.window_seconds)), 13, UIF.TEAL))
	else:
		column.add_child(UIF.label("NO LEGAL ROUTE  ·  " + str(row.reason), 13, UIF.RED))

	var actions := UIF.row(6)
	var up := UIF.small_button("▲", 44.0)
	var down := UIF.small_button("▼", 44.0)
	var route := UIF.small_button("ROUTE", 96.0)
	actions.add_child(up)
	actions.add_child(down)
	actions.add_child(route)
	column.add_child(actions)
	var order_id := int(row.order_id)
	up.pressed.connect(func() -> void:
		game.map_move_stop(order_id, -1)
		_refresh())
	down.pressed.connect(func() -> void:
		game.map_move_stop(order_id, 1)
		_refresh())
	route.pressed.connect(func() -> void:
		game.map_select_order(order_id)
		_refresh())
	return card


func _on_waypoint_requested(world_position: Vector2) -> void:
	game.map_set_waypoint(world_position)
	_waypoint_toggle.button_pressed = false
	map.waypoint_mode = false
	_refresh()


static func _clock(seconds: float) -> String:
	if not is_finite(seconds) or seconds <= 0.0:
		return "0:00"
	var whole := int(round(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]
