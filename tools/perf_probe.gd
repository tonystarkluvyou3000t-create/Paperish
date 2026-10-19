extends SceneTree
## Rendered performance probe for the reference machine (RTX 3050 6 GB laptop,
## 95 W). It starts a shift, walks a fixed street route with the real follow
## camera, and reports frame-time percentiles plus renderer counters, so "is it
## fast enough?" is a measurement instead of an opinion.
##
##   godot --path . -- --perf-quality=high --perf-res=1920x1080 --perf-frames=900
##   godot --headless --audio-driver Dummy --path . --script res://tools/perf_probe.gd
##
## `--perf-nav=map|compass|off` collects the first ticket first, so the HUD
## navigation display (minimap/compass card) draws a live route during sampling.
## `--perf-hold=1` pins Pip at the authored spawn with that live route, so runs
## differ only in what is being compared (the locked-vantage A/B).
##
## Timings need a real window: a headless run exercises the same harness and
## prints PERF HARNESS OK (with a percentile self-check) instead of numbers.
## Settings always go to a scratch file, never to the player's settings.cfg.
const Fixture = preload("res://tools/dev_fixture.gd")

const SETTINGS_PATH := "user://perf-probe.cfg"
const QUALITIES := ["low", "medium", "high"]
const LEG_TIMEOUT := 14.0
const HARNESS_FRAMES := 40

var frames := 600
var warmup := 120
var quality := "high"
var resolution := Vector2i(1920, 1080)
var output_path := ""
var nav := ""
var hold := false

var game: Node
var headless := false
var samples: Array[float] = []
var physics_samples: Array[float] = []
var legs: Array[Vector3] = []
var leg_labels: Array[String] = []
var stalled_leg_labels: Array[String] = []
var leg_index := 0
var leg_elapsed := 0.0
var stalled := 0
var warm_left := 0
var draw_calls := 0
var primitives := 0
var nodes := 0
var static_mb := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	frames = maxi(int(_arg(args, "--perf-frames", "600")), 10)
	warmup = maxi(int(_arg(args, "--perf-warm", "120")), 0)
	quality = _arg(args, "--perf-quality", "high").to_lower()
	if quality not in QUALITIES:
		quality = "high"
	var res := _arg(args, "--perf-res", "1920x1080").to_lower().split("x")
	if res.size() == 2:
		resolution = Vector2i(maxi(int(res[0]), 320), maxi(int(res[1]), 240))
	output_path = _arg(args, "--perf-output", "")
	nav = _arg(args, "--perf-nav", "").to_lower()
	if nav not in ["map", "compass", "off"]:
		nav = ""
	hold = _arg(args, "--perf-hold", "") != ""
	call_deferred("run")


static func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(key + "="):
			return arg.substr(key.length() + 1)
	return fallback


func run() -> void:
	headless = DisplayServer.get_name() == "headless"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	if not game.world_ready:
		print("PERF FAIL world bind: %s" % ", ".join(game.world_errors))
		quit(2)
		return
	# The player's own preferences are never read or written here.
	game.settings.configure(SETTINGS_PATH, false)
	game.settings.load_settings()
	game.settings.set_value("video/quality", quality)
	game.settings.set_value("video/frame_cap", 0)
	game.settings.apply_all()
	if not headless:
		game.get_window().size = resolution
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		# Measurement, not a screensaver: raise the window and stay out of the
		# lowered-power loop so a background window cannot inflate frame times.
		OS.low_processor_usage_mode = false
		DisplayServer.window_move_to_foreground()
		DisplayServer.window_set_position(Vector2i(0, 0))
	await process_frame
	game.set_order_seed(20261018)
	game.start_shift()
	await process_frame
	if nav != "":
		# Collect the ticket so a live route exists: the navigation display then
		# pays its real per-frame cost (route guidance, minimap/compass redraw).
		game.settings.set_value("hud/navigation", nav)
		game.settings.apply_all()
		game.orders.tick(game.orders.preparation_remaining + 0.1, game.destination_ids())
		game.orders.pickup()
		await process_frame
	if hold:
		# Locked vantage: the same authored spot with the same live route, so two
		# runs differ only in the navigation display being measured.
		Fixture.place(game, "pip", game.world.player_spawn.global_position)
		game.camera.yaw = PI
		await process_frame
	else:
		_build_route()
	warm_left = 0 if headless else warmup
	var budget := HARNESS_FRAMES if headless else frames
	while samples.size() < budget:
		await process_frame
		_step()
	_report(budget)


## Follow the authored foot graph through every address parking approach and back.
## This keeps the performance route representative without cutting through buildings.
func _build_route() -> void:
	var current_id := "spawn:player"
	for house in game.world.houses:
		var address_id := str(house.get_meta("address_id", ""))
		var row: Dictionary = game.world.graph.address_data(address_id)
		var target_id := str(row.get("ped_park_id", ""))
		if target_id.is_empty(): continue
		_append_graph_route(current_id, target_id)
		current_id = target_id
	_append_graph_route(current_id, "spawn:player")


func _append_graph_route(from_id: String, to_id: String) -> void:
	var route: Dictionary = game.world.graph.pedestrian_route(from_id, to_id)
	if not route.get("reachable", false):
		stalled_leg_labels.append("unreachable:%s->%s" % [from_id, to_id])
		return
	for index in range(1, route.path.size()):
		var node_id := str(route.path[index])
		var node: Dictionary = game.world.graph.pedestrian_nodes.get(node_id, {})
		var position: Array = node.get("position", [])
		if position.size() != 2: continue
		legs.append(Vector3(float(position[0]), 0.0, float(position[1])))
		leg_labels.append(node_id)


func _step() -> void:
	if warm_left > 0:
		warm_left -= 1
		_advance()
		return
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	if frame_ms > 0.0:
		samples.append(frame_ms)
		physics_samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	draw_calls = maxi(draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	primitives = maxi(primitives, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	nodes = maxi(nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	static_mb = maxf(static_mb, float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0)
	_advance()


## Re-issue the current waypoint; move on when the player reports arrival or the
## leg times out (a stalled leg is counted, never hidden).
func _advance() -> void:
	if legs.is_empty():
		return
	leg_elapsed += 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	if game.pip.autopilot == Vector3.INF or leg_elapsed > LEG_TIMEOUT:
		if leg_elapsed > LEG_TIMEOUT:
			stalled += 1
			var label := leg_labels[leg_index] if leg_index < leg_labels.size() else str(leg_index)
			stalled_leg_labels.append(label)
			print("PERF ROUTE STALL leg=%d target=%s actual=%s" % [leg_index, label, str(game.pip.global_position)])
		leg_index = (leg_index + 1) % legs.size()
		leg_elapsed = 0.0
	Fixture.autopilot(game, "pip", legs[leg_index])


static func _percentile(sorted_samples: Array, fraction: float) -> float:
	if sorted_samples.is_empty():
		return 0.0
	var index := clampi(int(round(fraction * float(sorted_samples.size() - 1))), 0, sorted_samples.size() - 1)
	return float(sorted_samples[index])


func _report(budget: int) -> void:
	if headless:
		# The harness itself is real; frame times are not (no window, no GPU).
		var probe := _percentile([1.0, 2.0, 3.0, 4.0, 5.0], 0.95)
		print("PERF HARNESS OK headless sampled=%d legs=%d percentile=%.2f nodes=%d" % [
			samples.size(), legs.size(), probe, nodes])
		await _finish()
		return
	var times := samples.duplicate()
	times.sort()
	physics_samples.sort()
	var median := _percentile(times, 0.5)
	var p95 := _percentile(times, 0.95)
	var p99 := _percentile(times, 0.99)
	var worst := 0.0 if times.is_empty() else float(times[times.size() - 1])
	var hitches := 0
	for value in times:
		if float(value) > median * 2.0:
			hitches += 1
	var physics_median := _percentile(physics_samples, 0.5)
	var adapter := str(RenderingServer.get_video_adapter_name())
	var size := game.get_window().size
	print("PERF adapter=\"%s\" quality=%s res=%dx%d vsync=off cap=0 frames=%d warm=%d median=%.2fms p95=%.2fms p99=%.2fms max=%.2fms hitches=%d fps=%.1f draw_calls=%d primitives=%d nodes=%d static=%.1fmb physics_median=%.2fms legs=%d stalled=%d stalled_targets=%s nav=%s hold=%s" % [
		adapter, quality, size.x, size.y, times.size(), warmup, median, p95, p99, worst,
		hitches, 1000.0 / maxf(median, 0.01), draw_calls, primitives, nodes, static_mb,
		physics_median, legs.size(), stalled, JSON.stringify(stalled_leg_labels),
		nav if nav != "" else "default", str(hold)])
	if not output_path.is_empty():
		var report := {
			"adapter": adapter, "quality": quality, "resolution": [size.x, size.y],
			"vsync": "off", "frame_cap": 0, "frames": times.size(), "warmup": warmup,
			"median_ms": median, "p95_ms": p95, "p99_ms": p99, "max_ms": worst,
			"hitches": hitches, "hitch_ms": median * 2.0,
			"median_fps": 1000.0 / maxf(median, 0.01), "draw_calls": draw_calls,
			"primitives": primitives, "nodes": nodes, "static_mb": static_mb,
			"physics_median_ms": physics_median, "legs": legs.size(), "stalled": stalled,
			"stalled_targets": stalled_leg_labels, "nav": nav if nav != "" else "default",
			"hold": hold,
			"budget": budget,
		}
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "  "))
			print("PERF REPORT %s" % output_path)
	await _finish()


## Free the scene and let the frame drain: the runner treats a leaked ObjectDB
## instance or resource at exit as a failure.
func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	if game:
		game.settings.reset_to_defaults(false)
		game.queue_free()
		game = null
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	quit(0)
