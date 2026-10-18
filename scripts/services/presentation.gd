extends Node3D
## Derived UI/marker/audio effects only; committed service events are inputs.
const GOLD := Color("f4bb4d")
const GREEN := Color("68b7a0")
var hud: CanvasLayer
var world: RefCounted
var orders: Node
var actors: Node
var session: Node
var config: Resource
var sound: Node
var objective_text := ""
var target_label := ""
var target_sub := ""
var prompt_text := ""
var waypoint_position := Vector3.ZERO
var waypoint_visible := false
var waypoint_color := GOLD
var pickup_marker: Node3D
var deliver_marker: Node3D

func _ready() -> void:
	pickup_marker = _marker(GOLD)
	deliver_marker = _marker(GREEN)

func _marker(tint: Color) -> Node3D:
	var marker := Node3D.new()
	marker.set_script(preload("res://scripts/marker.gd"))
	marker.tint = tint
	marker.visible = false
	add_child(marker)
	return marker

func configure(ui: CanvasLayer, registry: RefCounted, tickets: Node, controller: Node, flow: Node, balance: Resource, audio: Node) -> void:
	hud = ui
	world = registry
	orders = tickets
	actors = controller
	session = flow
	config = balance
	sound = audio
	orders.ticket_created.connect(on_ticket_created)
	orders.picked_up.connect(on_picked_up)
	orders.settled.connect(on_settled)
	orders.timed_out.connect(on_timeout)
	session.changed.connect(on_flow_changed)
	actors.transitioned.connect(on_actor_changed)
	actors.rejected.connect(reject_vehicle)

func _destination() -> Node3D:
	return world.destination(orders.destination_id)

func reset_view() -> void:
	objective_text = ""
	target_label = ""
	target_sub = ""
	prompt_text = ""
	waypoint_visible = false
	pickup_marker.visible = false
	deliver_marker.visible = false
	pickup_marker._flash = 0
	deliver_marker._flash = 0
	world.pip.set_carrying(0)
	for child in get_children():
		if child.has_meta("shift_feedback"): child.queue_free()
	hud.clear_toast()

func on_flow_changed(event: Dictionary) -> void:
	hud.show_pause(event.paused)
	hud.show_title(event.flow == session.Flow.TITLE)
	hud.show_summary(event.flow == session.Flow.RESULT)
	if event.flow == session.Flow.TITLE: reset_view()
	elif event.flow == session.Flow.RESULT:
		objective_text = ""
		target_label = ""
		target_sub = ""
		prompt_text = ""
		waypoint_visible = false
		pickup_marker.visible = false
		deliver_marker.visible = false
		if event.outcome == "won":
			sound.play("shift_end", -2.0)
			hud.set_summary("SHIFT COMPLETE", "$%d banked over %d deliveries\n%s" % [orders.money, orders.deliveries, "the island is fed and happy" if orders.strikes == 0 else "%d late drop%s" % [orders.strikes, "" if orders.strikes == 1 else "s"]])
		else:
			sound.play("fail", 0.0)
			hud.set_summary("SHIFT OVER", "$%d banked over %d deliveries\nthe pizzas went cold three times" % [orders.money, orders.deliveries])

func on_ticket_created(event: Dictionary) -> void:
	world.pip.set_carrying(event.cargo_count)
	deliver_marker.visible = false
	pickup_marker.visible = true
	pickup_marker.place(world.pickup_point.global_position)
	sound.play("order", -3.0)
	hud.toast("NEW ORDER  ·  %s" % event.destination_id)
	update_objective()

func on_picked_up(event: Dictionary) -> void:
	world.pip.set_carrying(event.cargo_count)
	sound.play("pickup", -2.0)
	pickup_marker.visible = false
	deliver_marker.place(world.destination(event.destination_id).get_node("Door").global_position)
	deliver_marker.visible = true
	hud.toast("ORDER UP  ·  GRAB THE VAN")
	update_objective()

func on_settled(event: Dictionary) -> void:
	world.pip.set_carrying(event.cargo_count)
	sound.play("deliver", -2.0)
	sound.play("cash", -4.0)
	deliver_marker.flash()
	float_text("+$%d" % event.pay, world.destination(event.destination_id).get_node("Door").global_position + Vector3(0, 2.6, 0))

func on_timeout(event: Dictionary) -> void:
	world.pip.set_carrying(event.cargo_count)
	sound.play("fail", -2.0)
	hud.toast("TOO SLOW  ·  %d STRIKE%s" % [event.strikes, "" if event.strikes == 1 else "S"])

func on_actor_changed(seated: bool) -> void:
	sound.play("door", -6.0)
	if seated: hud.toast("DELIVERY RUN")

func reject_vehicle(message: String) -> void:
	prompt_text = message
	hud.toast(message)

func update_context() -> void:
	prompt_text = ""
	if orders.lifecycle == orders.Lifecycle.ON_ROUTE:
		target_sub = "TIP  $%d" % orders.tip()
	var p: Vector3 = world.pip.global_position
	var door_pos: Vector3 = (_destination().get_node("Door") as Node3D).global_position if _destination() else Vector3.ZERO
	if actors.driving:
		prompt_text = "STOP THE VAN TO EXIT" if not actors.stopped() else "[E]   HOP OUT"
		waypoint_visible = true
		waypoint_position = door_pos if orders.lifecycle == orders.Lifecycle.ON_ROUTE else world.pickup_point.global_position
		waypoint_color = GREEN if orders.lifecycle == orders.Lifecycle.ON_ROUTE else GOLD
		return
	# on foot
	if orders.lifecycle == orders.Lifecycle.AT_SHOP and p.distance_to(world.pickup_point.global_position) < config.pickup_range:
		prompt_text = "[E]   PICK UP %d %s" % [orders.pizzas, "PIZZA" if orders.pizzas == 1 else "PIZZAS"]
	elif orders.lifecycle == orders.Lifecycle.ON_ROUTE and p.distance_to(door_pos) < config.door_range:
		prompt_text = "[E]   DELIVER %d %s" % [orders.pizzas, "PIZZA" if orders.pizzas == 1 else "PIZZAS"]
	elif p.distance_to(world.van.global_position) < config.van_range:
		prompt_text = "[E]   DRIVE" if actors.stopped() else "WAIT FOR THE VAN TO STOP"
	if orders.lifecycle == orders.Lifecycle.AT_SHOP:
		waypoint_position = world.pickup_point.global_position
		waypoint_color = GOLD
	else:
		waypoint_position = door_pos
		waypoint_color = GREEN
	waypoint_visible = true


func update_objective() -> void:
	if orders.lifecycle == orders.Lifecycle.AT_SHOP:
		objective_text = "PICK UP %d %s AT PIP'S PIZZA" % [orders.pizzas, "PIZZA" if orders.pizzas == 1 else "PIZZAS"]
		target_label = "PIP'S PIZZA  ·  Marinara Way"
		target_sub = ""
	elif orders.lifecycle == orders.Lifecycle.ON_ROUTE:
		objective_text = "DELIVER TO %s" % str(_destination().get_meta("address", "")).to_upper()
		target_label = str(_destination().get_meta("label", "")).to_upper()
		target_sub = "TIP  $%d" % orders.tip()
	else:
		objective_text = ""
		target_label = ""
		target_sub = ""


func float_text(txt: String, pos: Vector3) -> void:
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
	l.set_meta("shift_feedback", true)
	# Binding to the label also cancels this tween when restart frees it.
	var tw := l.create_tween()
	tw.tween_property(l, "global_position", pos + Vector3(0, 2.2, 0), 1.5)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.5).set_delay(0.55)
	tw.tween_callback(l.queue_free)
