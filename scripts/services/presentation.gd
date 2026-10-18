extends Node3D
## Derived UI/marker/audio effects only; committed service events are inputs.
const GOLD := Color("f4bb4d")
const GREEN := Color("68b7a0")
const InputBindings = preload("res://scripts/services/input_bindings.gd")
var hud: CanvasLayer
var world: RefCounted
var orders: Node
var actors: Node
var session: Node
var config: Resource
var sound: Node
var interactions: Node
var objective_text := ""
var target_label := ""
var target_sub := ""
var prompt_text := ""
var prompt_id: StringName = &""
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


## Prompt key for the interact action, rendered from the live bindings so a
## remap updates every "[E]" style prompt.
static func interact_label() -> String:
	return InputBindings.prompt("interact")

func reset_view() -> void:
	objective_text = ""
	target_label = ""
	target_sub = ""
	prompt_text = ""
	prompt_id = &""
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
		else:
			sound.play("fail", 0.0)

func on_ticket_created(event: Dictionary) -> void:
	world.pip.set_carrying(event.cargo_count)
	deliver_marker.visible = false
	pickup_marker.visible = true
	pickup_marker.place(world.pickup_point.global_position)
	sound.play("order", -3.0)
	hud.caption("NEW ORDER  ·  %s" % event.destination_id)
	update_objective()

func on_picked_up(event: Dictionary) -> void:
	world.pip.set_carrying(event.cargo_count)
	sound.play("pickup", -2.0)
	pickup_marker.visible = false
	deliver_marker.place(world.destination(event.destination_id).get_node("Door").global_position)
	deliver_marker.visible = true
	hud.caption("ORDER UP  ·  GRAB THE VAN")
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
	if seated: hud.caption("DELIVERY RUN")

func reject_vehicle(message: String) -> void:
	prompt_text = message
	hud.toast(message)

## Prompt and waypoint only: which action a press would run and where to drive
## next. The interaction table owns range, facing, access and blocked reasons, so
## the HUD can never offer something the action itself would refuse.
func update_context() -> void:
	var view: Dictionary = interactions.prompt_view() if interactions != null else {}
	prompt_text = str(view.get("text", ""))
	prompt_id = view.get("id", &"")
	if orders.lifecycle == orders.Lifecycle.ON_ROUTE:
		target_sub = "TIP  $%d" % orders.tip()
	if session.roaming():
		# Free roam: no ticket and no waypoint; only targets in reach speak.
		waypoint_visible = false
		target_label = ""
		target_sub = ""
		return
	var door_pos: Vector3 = (_destination().get_node("Door") as Node3D).global_position if _destination() else Vector3.ZERO
	waypoint_visible = true
	if actors.driving:
		waypoint_position = door_pos if orders.lifecycle == orders.Lifecycle.ON_ROUTE else world.pickup_point.global_position
		waypoint_color = GREEN if orders.lifecycle == orders.Lifecycle.ON_ROUTE else GOLD
		return
	if orders.lifecycle == orders.Lifecycle.AT_SHOP:
		waypoint_position = world.pickup_point.global_position
		waypoint_color = GOLD
	else:
		waypoint_position = door_pos
		waypoint_color = GREEN


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
