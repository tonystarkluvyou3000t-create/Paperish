extends Node3D
## Pip the Pizza Boy - the shift.
## Take the order, grab the pizzas at the shop, drive to the address, park, hop
## out and deliver on foot before the clock runs out. Three timeouts end the day.

enum State { TITLE, TO_SHOP, TO_HOUSE, COMPLETE, FAILED }

const GOAL := 150
const PICKUP_RANGE := 3.6
const DOOR_RANGE := 3.6
const VAN_RANGE := 3.8
const MARK_GOLD := Color("f4bb4d")
const MARK_GREEN := Color("68b7a0")

var state: State = State.TITLE
var money := 0
var goal_money := GOAL
var deliveries := 0
var strikes := 0
var max_strikes := 3

var order_house: Node3D = null
var order_pizzas := 1
var timer := 0.0
var timer_max := 60.0
var timer_visible := false
var last_house := -1
var forced_house := -1
var paused := false

# ---- values the HUD reads every frame
var objective_text := ""
var target_label := ""
var target_sub := ""
var prompt_text := ""
var waypoint_position := Vector3.ZERO
var waypoint_visible := false
var waypoint_color := MARK_GOLD
var speed_kmh := 0.0
var driving := false

@onready var town: Node3D = $Town
@onready var pip: CharacterBody3D = $Pip
@onready var van: CharacterBody3D = $Van
@onready var camera: Camera3D = $Camera

var hud: CanvasLayer
var houses: Array[Node3D] = []
var pickup_point: Node3D
var pickup_marker: Node3D
var deliver_marker: Node3D
var sounds := {}
var _pool: Array[AudioStreamPlayer] = []
var _horn: AudioStreamPlayer3D


func _ready() -> void:
	randomize()
	hud = $HUD
	hud.game = self
	var houses_root := town.get_node_or_null("Houses")
	if houses_root:
		for h in houses_root.get_children():
			if h is Node3D:
				houses.append(h)
	pickup_point = town.get_node("PizzaShop/PickupPoint") as Node3D

	pickup_marker = _make_marker(MARK_GOLD)
	deliver_marker = _make_marker(MARK_GREEN)

	for n in ["ui", "order", "pickup", "deliver", "cash", "fail", "step", "horn", "door", "shift_end"]:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			sounds[n] = load(path)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		_pool.append(p)
	_horn = AudioStreamPlayer3D.new()
	_horn.stream = sounds.get("horn")
	_horn.unit_size = 8.0
	_horn.max_distance = 40.0
	van.add_child(_horn)
	_horn.global_position = van.global_position

	pip.footstep.connect(_on_footstep)
	van.honked.connect(_on_honk)

	var pspawn := town.get_node("PlayerSpawn") as Node3D
	pip.global_position = pspawn.global_position
	pip.rotation.y = deg_to_rad(float(pspawn.get_meta("yaw", 0.0)))
	var vspawn := town.get_node("VanSpawn") as Node3D
	van.global_position = vspawn.global_position
	van.rotation.y = deg_to_rad(float(vspawn.get_meta("yaw", 90.0)))

	camera.target = pip
	camera.orbit = true
	camera.yaw = pip.rotation.y + deg_to_rad(140.0)
	pip.input_enabled = false
	van.input_enabled = false
	hud.show_title(true)
	_set_objective()


func _make_marker(tint: Color) -> Node3D:
	var m := Node3D.new()
	m.set_script(load("res://scripts/marker.gd"))
	m.tint = tint
	m.visible = false
	add_child(m)
	return m


# ------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state != State.TITLE:
		_toggle_pause()
		return
	if paused:
		return
	if event.is_action_pressed("confirm"):
		if state == State.TITLE:
			_start_shift()
		return
	if event.is_action_pressed("restart"):
		if state == State.COMPLETE or state == State.FAILED or state == State.TITLE:
			restart()
		return
	if event.is_action_pressed("interact") and state in [State.TO_SHOP, State.TO_HOUSE]:
		_on_interact()


func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	hud.show_pause(paused)


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _start_shift() -> void:
	money = 0
	deliveries = 0
	strikes = 0
	paused = false
	get_tree().paused = false
	hud.show_title(false)
	hud.show_summary(false)
	camera.orbit = false
	pip.input_enabled = true
	van.input_enabled = true
	_new_order()


# ------------------------------------------------------------------ shift flow
func _new_order() -> void:
	if houses.is_empty():
		return
	var idx := randi_range(0, houses.size() - 1)
	if forced_house >= 0 and forced_house < houses.size():
		idx = forced_house
		forced_house = -1
	if houses.size() > 1:
		while idx == last_house:
			idx = randi_range(0, houses.size() - 1)
	last_house = idx
	order_house = houses[idx]
	order_pizzas = randi_range(1, 3)
	timer_max = maxf(45.0, 82.0 - float(deliveries) * 3.0)
	timer = timer_max
	timer_visible = true
	state = State.TO_SHOP
	pip.set_carrying(0)
	deliver_marker.visible = false
	pickup_marker.visible = true
	pickup_marker.place(pickup_point.global_position)
	_snd("order", -3.0)
	hud.toast("NEW ORDER  ·  %s" % str(order_house.get_meta("address", "")))
	_set_objective()


func _pick_up() -> void:
	pip.set_carrying(order_pizzas)
	_snd("pickup", -2.0)
	pickup_marker.visible = false
	var door: Node3D = order_house.get_node("Door") as Node3D
	deliver_marker.place(door.global_position)
	deliver_marker.visible = true
	state = State.TO_HOUSE
	hud.toast("ORDER UP  ·  GRAB THE VAN")
	_set_objective()


func _deliver() -> void:
	var frac := clampf(timer / maxf(timer_max, 0.01), 0.0, 1.0)
	var tip := int(round(8.0 * frac))
	var pay := 10 + 2 * order_pizzas + tip
	money += pay
	deliveries += 1
	_snd("deliver", -2.0)
	_snd("cash", -4.0)
	deliver_marker.flash()
	var door: Node3D = order_house.get_node("Door") as Node3D
	_float_text("+$%d" % pay, door.global_position + Vector3(0, 2.6, 0))
	pip.set_carrying(0)
	pip.autopilot = Vector3.INF
	van.autopilot = Vector3.INF
	if money >= goal_money:
		_finish(true)
	else:
		_new_order()


func _on_timeout() -> void:
	strikes += 1
	_snd("fail", -2.0)
	pip.set_carrying(0)
	if strikes >= max_strikes:
		_finish(false)
	else:
		hud.toast("TOO SLOW  ·  %d STRIKE%s" % [strikes, "" if strikes == 1 else "S"])
		_new_order()


func _finish(win: bool) -> void:
	state = State.COMPLETE if win else State.FAILED
	timer_visible = false
	objective_text = ""
	target_label = ""
	target_sub = ""
	prompt_text = ""
	waypoint_visible = false
	pickup_marker.visible = false
	deliver_marker.visible = false
	pip.input_enabled = false
	van.input_enabled = false
	if win:
		_snd("shift_end", -2.0)
		hud.set_summary("SHIFT COMPLETE",
			"$%d banked over %d deliveries\n%s" % [money, deliveries,
			"the island is fed and happy" if strikes == 0 else "%d late drop%s" % [strikes, "" if strikes == 1 else "s"]])
	else:
		_snd("fail", 0.0)
		hud.set_summary("SHIFT OVER",
			"$%d banked over %d deliveries\nthe pizzas went cold three times" % [money, deliveries])
	hud.show_summary(true)


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if state == State.TO_SHOP or state == State.TO_HOUSE:
		timer = maxf(0.0, timer - delta)
		if timer <= 0.0:
			_on_timeout()
	speed_kmh = absf(van.speed) * 3.6 if driving else 0.0
	if state == State.COMPLETE or state == State.FAILED or state == State.TITLE:
		prompt_text = ""
		return
	_context()


func _context() -> void:
	prompt_text = ""
	var p := pip.global_position
	var door_pos: Vector3 = (order_house.get_node("Door") as Node3D).global_position if order_house else Vector3.ZERO
	if driving:
		prompt_text = "[E]   HOP OUT"
		waypoint_visible = true
		waypoint_position = door_pos if state == State.TO_HOUSE else pickup_point.global_position
		waypoint_color = MARK_GREEN if state == State.TO_HOUSE else MARK_GOLD
		return
	# on foot
	if state == State.TO_SHOP and p.distance_to(pickup_point.global_position) < PICKUP_RANGE:
		prompt_text = "[E]   PICK UP %d %s" % [order_pizzas, "PIZZA" if order_pizzas == 1 else "PIZZAS"]
	elif state == State.TO_HOUSE and p.distance_to(door_pos) < DOOR_RANGE:
		prompt_text = "[E]   DELIVER %d %s" % [order_pizzas, "PIZZA" if order_pizzas == 1 else "PIZZAS"]
	elif p.distance_to(van.global_position) < VAN_RANGE:
		prompt_text = "[E]   DRIVE"
	if state == State.TO_SHOP:
		waypoint_position = pickup_point.global_position
		waypoint_color = MARK_GOLD
	else:
		waypoint_position = door_pos
		waypoint_color = MARK_GREEN
	waypoint_visible = true
	# live tip countdown as the clock runs down
	if state == State.TO_HOUSE:
		target_sub = "TIP  $%d" % int(round(8.0 * clampf(timer / maxf(timer_max, 0.01), 0.0, 1.0)))


func _set_objective() -> void:
	if state == State.TO_SHOP:
		objective_text = "PICK UP %d %s AT PIP'S PIZZA" % [order_pizzas, "PIZZA" if order_pizzas == 1 else "PIZZAS"]
		target_label = "PIP'S PIZZA  ·  Marinara Way"
		target_sub = ""
	elif state == State.TO_HOUSE:
		objective_text = "DELIVER TO %s" % str(order_house.get_meta("address", "")).to_upper()
		target_label = str(order_house.get_meta("label", "")).to_upper()
		target_sub = "TIP  $8"
	else:
		objective_text = ""
		target_label = ""
		target_sub = ""


func _on_interact() -> void:
	if driving:
		_exit_van()
		return
	_try_pickup_or_deliver()


func _try_pickup_or_deliver() -> void:
	var p := pip.global_position
	var door_pos: Vector3 = (order_house.get_node("Door") as Node3D).global_position if order_house else Vector3.ZERO
	if state == State.TO_SHOP and p.distance_to(pickup_point.global_position) < PICKUP_RANGE:
		_pick_up()
		return
	if state == State.TO_HOUSE and p.distance_to(door_pos) < DOOR_RANGE:
		_deliver()
		return
	if not driving and p.distance_to(van.global_position) < VAN_RANGE:
		_enter_van()


func _enter_van() -> void:
	driving = true
	pip.input_enabled = false
	pip.visible = false
	pip.set_physics_process(false)
	(pip.get_node("Collision") as CollisionShape3D).disabled = true
	van.input_enabled = true
	camera.target = van
	camera.driving = true
	_snd("door", -6.0)
	hud.toast("DELIVERY RUN")


func _exit_van() -> void:
	driving = false
	van.input_enabled = false
	van.speed = 0.0
	var off := van.global_transform * Vector3(1.75, 0.0, 0.15)
	pip.global_position = Vector3(off.x, van.global_position.y + 0.05, off.z)
	pip.velocity = Vector3.ZERO
	pip.autopilot = Vector3.INF
	pip.rotation.y = van.rotation.y + PI * 0.5
	pip.visible = true
	pip.set_physics_process(true)
	(pip.get_node("Collision") as CollisionShape3D).disabled = false
	pip.input_enabled = true
	camera.target = pip
	camera.driving = false
	_snd("door", -6.0)


# ------------------------------------------------------------------ helpers
func _snd(name: String, vol := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = sounds[name]
			p.volume_db = vol
			p.pitch_scale = pitch
			p.play()
			return
	_pool[0].stream = sounds[name]
	_pool[0].volume_db = vol
	_pool[0].pitch_scale = pitch
	_pool[0].play()


func _on_footstep() -> void:
	_snd("step", -9.0, randf_range(0.9, 1.1))


func _on_honk() -> void:
	if _horn.stream:
		_horn.play()


func _debug_state() -> String:
	var door_pos: Vector3 = (order_house.get_node("Door") as Node3D).global_position if order_house else Vector3.ZERO
	return "state=%d money=%d deliveries=%d strikes=%d carrying=%d driving=%s t=%.1f/%.1f house=%s pip=%s van=%s door=%s" % [
		state, money, deliveries, strikes, pip.carrying, str(driving), timer, timer_max,
		str(order_house.get_meta("address", "?")) if order_house else "-",
		str(pip.global_position.round()), str(van.global_position.round()), str(door_pos.round())]


func _float_text(txt: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 128
	l.pixel_size = 0.006
	l.outline_size = 26
	l.outline_modulate = Color("283f49")
	l.modulate = Color("f4bb4d")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "global_position", pos + Vector3(0, 2.2, 0), 1.5)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.5).set_delay(0.55)
	tw.tween_callback(l.queue_free)
