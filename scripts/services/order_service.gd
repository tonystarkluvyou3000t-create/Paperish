extends Node
## Synchronous ticket transactions. Signals carry committed, read-only values.
signal ticket_created(event: Dictionary)
signal ticket_ready(event: Dictionary)
signal picked_up(event: Dictionary)
## Immutable handoff receipt; cargo systems can consume this after Phase 07.
signal receipt_created(event: Dictionary)
signal settled(event: Dictionary)
signal timed_out(event: Dictionary)
signal shift_ended(event: Dictionary)

enum Lifecycle { IDLE, AT_SHOP, ON_ROUTE, CLOSED }
enum TicketState { NONE, PREPARING, READY, COLLECTED }
const TICKET_STATES: Array[String] = ["none", "preparing", "ready", "collected"]
var config: Resource
var lifecycle := Lifecycle.IDLE
var money := 0
var deliveries := 0
var strikes := 0
var pizzas := 1
var cargo_count := 0
var ticket_state := TicketState.NONE
var preparation_remaining := 0.0
var remaining := 0.0
var duration := 60.0
var order_id := 0
var generation := 0
var destination_id := ""
var last_destination := ""
var forced_destination := ""
## Itemized earnings for the results screen: every settled ticket accrues here.
var total_base := 0
var total_pizza := 0
var total_tip := 0
var _seed := -1
var _run_closed := false
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func set_seed(value: int) -> void:
	_seed = value
	_rng.seed = value

func reset(next_generation: int) -> void:
	generation = next_generation
	_run_closed = false
	lifecycle = Lifecycle.IDLE
	money = 0
	deliveries = 0
	strikes = 0
	pizzas = 1
	cargo_count = 0
	ticket_state = TicketState.NONE
	preparation_remaining = 0.0
	remaining = 0
	duration = 60
	order_id = 0
	destination_id = ""
	last_destination = ""
	forced_destination = ""
	total_base = 0
	total_pizza = 0
	total_tip = 0
	if _seed >= 0: _rng.seed = _seed

func force_destination(id: String, available: Array[String]) -> bool:
	if id not in available: return false
	forced_destination = id
	return true

func create_ticket(available: Array[String]) -> bool:
	if _run_closed or available.is_empty(): return false
	# Stable ID ordering makes selection independent of scene child ordering.
	var ids := available.duplicate()
	ids.sort()
	var index := _rng.randi_range(0, ids.size() - 1)
	if not forced_destination.is_empty() and forced_destination in ids:
		index = ids.find(forced_destination)
		forced_destination = ""
	elif ids.size() > 1:
		while ids[index] == last_destination:
			index = _rng.randi_range(0, ids.size() - 1)
	destination_id = ids[index]
	last_destination = destination_id
	pizzas = _rng.randi_range(1, 3)
	order_id += 1
	duration = maxf(config.deadline_floor, config.deadline_start - deliveries * config.deadline_decrease)
	# Food freshness begins only when the ready ticket is physically received.
	remaining = 0.0
	preparation_remaining = maxf(config.preparation_duration, 0.0)
	ticket_state = TicketState.PREPARING if preparation_remaining > 0.0 else TicketState.READY
	cargo_count = 0
	lifecycle = Lifecycle.AT_SHOP
	ticket_created.emit(event("created"))
	if ticket_state == TicketState.READY:
		ticket_ready.emit(event("ready"))
	return true

func pickup() -> bool:
	if lifecycle != Lifecycle.AT_SHOP or ticket_state != TicketState.READY or cargo_count != 0: return false
	cargo_count = pizzas
	ticket_state = TicketState.COLLECTED
	preparation_remaining = 0.0
	remaining = duration
	lifecycle = Lifecycle.ON_ROUTE
	var receipt := event("picked_up")
	picked_up.emit(receipt)
	receipt_created.emit(receipt)
	return true

func ticket_state_name() -> String:
	return TICKET_STATES[ticket_state]

func tick(delta: float, available: Array[String]) -> void:
	if lifecycle == Lifecycle.AT_SHOP:
		if ticket_state != TicketState.PREPARING:
			return
		preparation_remaining = maxf(0.0, preparation_remaining - maxf(delta, 0.0))
		if preparation_remaining <= 0.0:
			ticket_state = TicketState.READY
			ticket_ready.emit(event("ready"))
		return
	if lifecycle != Lifecycle.ON_ROUTE:
		return
	remaining = maxf(0, remaining - delta)
	if remaining == 0: expire(available, generation, order_id)

func tip() -> int:
	return int(round(config.max_tip * clampf(remaining / maxf(duration, 0.01), 0, 1)))

func settle(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	if generation != expected_generation or order_id != expected_order: return false
	if lifecycle != Lifecycle.ON_ROUTE or cargo_count != pizzas: return false
	var base: int = config.base_pay
	var pizza_pay: int = config.pay_per_pizza * pizzas
	var tip_pay := tip()
	var pay: int = base + pizza_pay + tip_pay
	lifecycle = Lifecycle.CLOSED
	cargo_count = 0
	money += pay
	deliveries += 1
	total_base += base
	total_pizza += pizza_pay
	total_tip += tip_pay
	settled.emit(event("settled", pay))
	# A listener may restart/reload. Old work must not create a new session's ticket.
	if _run_closed or generation != expected_generation or order_id != expected_order: return true
	if money >= config.goal_money: shift_ended.emit(event("won"))
	else: create_ticket(available)
	return true

func expire(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	if generation != expected_generation or order_id != expected_order or remaining > 0: return false
	if lifecycle != Lifecycle.ON_ROUTE or ticket_state != TicketState.COLLECTED: return false
	lifecycle = Lifecycle.CLOSED
	cargo_count = 0
	ticket_state = TicketState.NONE
	remaining = 0.0
	strikes += 1
	timed_out.emit(event("timed_out"))
	if _run_closed or generation != expected_generation or order_id != expected_order: return true
	if strikes >= config.max_strikes: shift_ended.emit(event("lost"))
	else: create_ticket(available)
	return true

func close() -> void:
	_run_closed = true
	lifecycle = Lifecycle.CLOSED
	ticket_state = TicketState.NONE
	preparation_remaining = 0.0
	remaining = 0.0

func event(outcome: String, pay: int = 0) -> Dictionary:
	var value := {"generation": generation, "order_id": order_id, "destination_id": destination_id,
		"outcome": outcome, "pay": pay, "money": money, "deliveries": deliveries,
		"strikes": strikes, "pizzas": pizzas, "quantity": pizzas, "cargo_count": cargo_count,
		"ticket_state": ticket_state_name(), "preparation_remaining": preparation_remaining,
		"remaining": remaining, "duration": duration}
	value.make_read_only()
	return value
