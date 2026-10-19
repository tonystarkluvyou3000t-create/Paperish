extends Control
## Phase 11 Milestone B: one top-down renderer shared by the HUD minimap and the
## full town map. It draws only authored catalog data plus the live route state
## handed to it, and every marker is a distinct shape as well as a distinct
## colour, so guidance survives a colour-blind or greyscale screen.
##
## Interactive mode adds drag-pan, wheel zoom, controller pan and optional
## click-a-waypoint placement; the minimap runs the same drawing code with
## interaction off.

signal waypoint_requested(world_position: Vector2)

const LAND := Color("e7d7b4")
const WATER := Color("2f5d78")
const WATER_EDGE := Color("7fb2cc")
const ROAD_MAIN := Color("9c8a66")
const ROAD_LOCAL := Color("b0a184")
const BUILDING := Color("f6ead0")
const BUILDING_EDGE := Color("5d5244")
const INK := Color("283f49")
const ROUTE := Color("d98f2b")
const ROUTE_WALK := Color("68b7a0")
const TARGET := Color("68b7a0")
const TICKET := Color("3f8ea6")
const VAN := Color("c84436")
const PLAYER := Color("326b69")
const SHOP := Color("f4bb4d")
const ANCHOR := Color("8a8577")
const DISTRICT_LINE := Color("6b5f4c")

var model: Dictionary = {}
var view: Dictionary = {}
## World metres per screen pixel. Small = zoomed in.
var metres_per_pixel := 0.24
var center := Vector2.ZERO
var follow_actor := true
var show_labels := false
var interactive := false
var waypoint_mode := false
var clamp_to_bounds := true
## Set by the owner: the label drawn on the empty state.
var empty_text := ""

var _dragging := false
var _drag_moved := 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if not interactive else Control.MOUSE_FILTER_STOP
	queue_redraw()


func setup_map() -> void:
	if not model.is_empty() and center == Vector2.ZERO:
		center = Vector2(model.bounds.position) + Vector2(model.bounds.size) * 0.5


func world_to_screen(point: Vector2) -> Vector2:
	return (point - center) / metres_per_pixel + size * 0.5


func screen_to_world(point: Vector2) -> Vector2:
	return (point - size * 0.5) * metres_per_pixel + center


func zoom_to(scale: float) -> void:
	metres_per_pixel = clampf(scale, 0.06, 1.6)
	queue_redraw()


func zoom_by(factor: float, around := Vector2.INF) -> void:
	var anchor := screen_to_world(around) if around.is_finite() else center
	zoom_to(metres_per_pixel * factor)
	# Keep the anchor point under the same pixel while zooming.
	if around.is_finite():
		center += anchor - screen_to_world(around)
		_clamp_center()
	queue_redraw()


func recenter_on_actor() -> void:
	follow_actor = true
	queue_redraw()


func _process(delta: float) -> void:
	if model.is_empty():
		return
	if follow_actor and view.has("player"):
		center = view.player
	if interactive and has_focus():
		var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if pan.length() > 0.05:
			center += pan * metres_per_pixel * 460.0 * delta
			follow_actor = false
			_clamp_center()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_by(0.85, get_local_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_by(1.18, get_local_mouse_position())
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and waypoint_mode:
				waypoint_requested.emit(screen_to_world(get_local_mouse_position()))
				accept_event()
			else:
				_dragging = event.pressed
				_drag_moved = 0.0
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			follow_actor = true
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += event.relative.length()
		if _drag_moved > 4.0:
			follow_actor = false
		center -= event.relative * metres_per_pixel
		_clamp_center()
		if _drag_moved > 2.0:
			accept_event()
	elif event is InputEventKey and event.pressed and not event.is_echo():
		if event.is_action("ui_accept") and waypoint_mode:
			waypoint_requested.emit(center)
			accept_event()
		elif event.is_action("ui_cancel"):
			waypoint_mode = false
			accept_event()
	elif event is InputEventJoypadButton and event.pressed:
		if event.is_action("ui_accept") and waypoint_mode:
			waypoint_requested.emit(center)
			accept_event()


func _clamp_center() -> void:
	if not clamp_to_bounds or model.is_empty():
		return
	var bounds: Rect2 = model.bounds
	var margin := bounds.grow(24.0)
	center.x = clampf(center.x, margin.position.x, margin.end.x)
	center.y = clampf(center.y, margin.position.y, margin.end.y)


func _draw() -> void:
	if model.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), LAND)
	_draw_water()
	_draw_districts()
	_draw_roads()
	_draw_buildings()
	_draw_recovery()
	_draw_pois()
	_draw_tickets()
	_draw_target()
	_draw_route()
	_draw_waypoint()
	_draw_actors()
	if waypoint_mode:
		_draw_crosshair()
	if empty_text != "":
		var font := ThemeDB.fallback_font
		var box := font.get_string_size(empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15)
		draw_string_outline(font, (size - box) * 0.5, empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 5, INK)
		draw_string(font, (size - box) * 0.5, empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("fdf6e3"))


func _draw_water() -> void:
	for row in model.water:
		var rect: Rect2 = _screen_rect(row.rect)
		draw_rect(rect, WATER)
		draw_rect(rect, WATER_EDGE, false, 1.5)


func _draw_districts() -> void:
	for row in model.districts:
		var rect: Rect2 = _screen_rect(row.rect)
		draw_rect(rect, DISTRICT_LINE, false, 1.0)
		if show_labels and metres_per_pixel < 0.6:
			_label_at(str(row.name).to_upper(), rect.position + Vector2(6.0, 20.0), 15, Color("5c5346"))


func _draw_roads() -> void:
	for row in model.roads:
		var a := world_to_screen(row.from)
		var b := world_to_screen(row.to)
		var width := clampf(float(row.width_m) / metres_per_pixel, 2.5, 30.0)
		var color := ROAD_MAIN if str(row.speed_class) == "main" else ROAD_LOCAL
		draw_line(a, b, INK, width + 2.0)
		draw_line(a, b, color, width)
	# Street names on the wide view only: the minimap stays uncluttered.
	if show_labels and metres_per_pixel < 0.35:
		var placed := {}
		for row in model.roads:
			var street := str(row.street)
			if street.is_empty() or placed.has(street):
				continue
			placed[street] = true
			var mid := (world_to_screen(row.from) + world_to_screen(row.to)) * 0.5
			if mid.x < 0.0 or mid.y < 0.0 or mid.x > size.x or mid.y > size.y:
				continue
			_label_at(street.to_upper(), mid + Vector2(4.0, -6.0), 13, Color("4a4237"))


func _draw_buildings() -> void:
	for row in model.buildings:
		var rect: Rect2 = _screen_rect(row.rect)
		draw_rect(rect, BUILDING)
		draw_rect(rect, BUILDING_EDGE, false, 1.0)
		if show_labels and rect.size.x >= 26.0:
			_label_at(str(row.number), rect.position + Vector2(3.0, rect.size.y - 5.0), 12, Color("6a5f4e"))


func _draw_recovery() -> void:
	if not show_labels:
		return
	for row in model.recovery:
		var p := world_to_screen(row.position)
		draw_arc(p, 7.0, 0.0, TAU, 24, ANCHOR, 2.0)
		draw_line(p + Vector2(-7.0, 0.0), p + Vector2(7.0, 0.0), ANCHOR, 2.0)
		draw_line(p + Vector2(0.0, -7.0), p + Vector2(0.0, 7.0), ANCHOR, 2.0)


func _draw_pois() -> void:
	for row in model.pois:
		var p := world_to_screen(row.position)
		if str(row.kind) == "landmark":
			draw_rect(Rect2(p - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), SHOP)
			draw_rect(Rect2(p - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), INK, false, 1.5)
		else:
			draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), Color("fdf6e3"))
			draw_rect(Rect2(p - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), INK, false, 1.5)
		if show_labels:
			_label_at(str(row.label), p + Vector2(9.0, 4.0), 12, Color("40372c"))
	# The pizza shop is the one building that never moves.
	var shop := world_to_screen(model.shop)
	draw_rect(Rect2(shop - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), SHOP)
	draw_rect(Rect2(shop - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), INK, false, 2.0)
	_label_at("P", shop + Vector2(-4.0, 5.0), 13, INK)
	if show_labels:
		_label_at("PIZZA SHOP", shop + Vector2(11.0, 5.0), 13, Color("40372c"))


func _draw_tickets() -> void:
	for row in view.get("tickets", []):
		var point: Variant = row.get("position")
		if not point is Vector2:
			continue
		var p := world_to_screen(point)
		var size_px := 7.0 if bool(row.get("selected", false)) else 5.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(0.0, -size_px),
			p + Vector2(size_px, size_px), p + Vector2(-size_px, size_px)]), TICKET)
		draw_polyline(PackedVector2Array([p + Vector2(0.0, -size_px),
			p + Vector2(size_px, size_px), p + Vector2(-size_px, size_px), p + Vector2(0.0, -size_px)]), INK, 1.5)


func _draw_target() -> void:
	var point: Variant = view.get("target")
	if not point is Vector2:
		return
	var p := world_to_screen(point)
	var d := Vector2(0.0, -11.0)
	draw_colored_polygon(PackedVector2Array([p + d, p + Vector2(11.0, 0.0), p - d, p + Vector2(-11.0, 0.0)]), TARGET)
	draw_polyline(PackedVector2Array([p + d, p + Vector2(11.0, 0.0), p - d, p + Vector2(-11.0, 0.0), p + d]), INK, 2.0)
	draw_arc(p, 16.0, 0.0, TAU, 32, TARGET, 2.0)


func _draw_route() -> void:
	var route: PackedVector3Array = view.get("route", PackedVector3Array())
	if route.size() < 2:
		return
	var drive_count := clampi(int(view.get("route_drive_count", route.size())), 0, route.size())
	var drive := PackedVector2Array()
	for index in drive_count:
		drive.append(world_to_screen(Vector2(route[index].x, route[index].z)))
	if drive.size() >= 2:
		draw_polyline(drive, INK, 6.0)
		draw_polyline(drive, ROUTE, 3.5)
	var walk := PackedVector2Array()
	var start := maxi(drive_count - 1, 0)
	for index in range(start, route.size()):
		walk.append(world_to_screen(Vector2(route[index].x, route[index].z)))
	if walk.size() >= 2:
		_draw_dotted(walk, INK, 5.0, 7.0)
		_draw_dotted(walk, ROUTE_WALK, 3.0, 7.0)
	_draw_chevrons(drive)


## Direction chevrons so the route can be followed without any text.
func _draw_chevrons(points: PackedVector2Array) -> void:
	var spacing := 68.0
	var travelled := 0.0
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		var side := Vector2(-dir.y, dir.x)
		var at := spacing - fmod(travelled, spacing)
		while at < length:
			var p := a + dir * at
			var tip := p + dir * 6.0
			draw_colored_polygon(PackedVector2Array([tip, p - dir * 2.0 + side * 4.0, p - dir * 2.0 - side * 4.0]), Color("7a4a12"))
			at += spacing
		travelled += length


func _draw_waypoint() -> void:
	var point: Variant = view.get("waypoint")
	if not point is Vector2:
		return
	var p := world_to_screen(point)
	draw_circle(p + Vector2(0.0, -9.0), 7.0, Color("fdf6e3"))
	draw_arc(p + Vector2(0.0, -9.0), 7.0, 0.0, TAU, 24, INK, 2.0)
	draw_line(p + Vector2(0.0, -2.0), p + Vector2(0.0, 6.0), INK, 2.0)
	draw_line(p + Vector2(-3.0, -9.0), p + Vector2(3.0, -9.0), INK, 2.0)


func _draw_actors() -> void:
	if view.has("van"):
		_arrow(world_to_screen(view.van), float(view.get("van_yaw", 0.0)), 12.0, VAN, true)
	if view.has("player") and not bool(view.get("driving", false)):
		_arrow(world_to_screen(view.player), float(view.get("player_yaw", 0.0)), 12.0, PLAYER, false)


func _draw_crosshair() -> void:
	var p := get_local_mouse_position() if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE else center_point()
	var s := 12.0
	draw_line(p + Vector2(-s, 0.0), p + Vector2(s, 0.0), INK, 2.0)
	draw_line(p + Vector2(0.0, -s), p + Vector2(0.0, s), INK, 2.0)
	draw_arc(p, s * 0.6, 0.0, TAU, 20, SHOP, 2.0)


func center_point() -> Vector2:
	return size * 0.5


func _arrow(centre: Vector2, yaw: float, length: float, color: Color, with_bar: bool) -> void:
	var forward := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(-forward.y, forward.x)
	var tip := centre + forward * length
	var back := centre - forward * length * 0.6
	draw_colored_polygon(PackedVector2Array([tip, back + side * length * 0.55, back - side * length * 0.55]), color)
	draw_polyline(PackedVector2Array([tip, back + side * length * 0.55, back - side * length * 0.55, tip]), INK, 2.0)
	if with_bar:
		var bar := centre - forward * length * 0.6
		draw_line(bar + side * length * 0.45, bar - side * length * 0.45, INK, 3.0)


func _draw_dotted(points: PackedVector2Array, color: Color, width: float, dash: float) -> void:
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		var at := 0.0
		while at < length:
			var end := minf(at + dash * 0.6, length)
			draw_line(a + dir * at, a + dir * end, color, width)
			at += dash
	draw_polyline(points, color, width)


func _screen_rect(world: Rect2) -> Rect2:
	var top_left := world_to_screen(world.position)
	var bottom_right := world_to_screen(world.end)
	return Rect2(top_left, bottom_right - top_left)


func _label_at(text: String, position: Vector2, size_px: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(1.0, 0.98, 0.9, 0.8))
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
