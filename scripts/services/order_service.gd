extends Node
## Synchronous ticket transactions. Signals carry committed, read-only values.
signal ticket_created(event: Dictionary)
signal picked_up(event: Dictionary)
signal settled(event: Dictionary)
signal timed_out(event: Dictionary)
signal shift_ended(event: Dictionary)

enum Lifecycle { IDLE, AT_SHOP, ON_ROUTE, CLOSED }
var config: Resource
var lifecycle := Lifecycle.IDLE
var money := 0
var deliveries := 0
var strikes := 0
var pizzas := 1
var cargo_count := 0
var remaining := 0.0
var duration := 60.0
var order_id := 0
var generation := 0
var destination_id := ""
var last_destination := ""
var forced_destination := ""
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
	remaining = 0
	duration = 60
	order_id = 0
	destination_id = ""
	last_destination = ""
	forced_destination = ""
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
	remaining = duration
	cargo_count = 0
	lifecycle = Lifecycle.AT_SHOP
	ticket_created.emit(event("created"))
	return true

func pickup() -> bool:
	if lifecycle != Lifecycle.AT_SHOP or cargo_count != 0: return false
	cargo_count = pizzas
	lifecycle = Lifecycle.ON_ROUTE
	picked_up.emit(event("picked_up"))
	return true

func tip() -> int:
	return int(round(config.max_tip * clampf(remaining / maxf(duration, 0.01), 0, 1)))

func settle(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	if generation != expected_generation or order_id != expected_order: return false
	if lifecycle != Lifecycle.ON_ROUTE or cargo_count != pizzas: return false
	var pay: int = config.base_pay + config.pay_per_pizza * pizzas + tip()
	lifecycle = Lifecycle.CLOSED
	cargo_count = 0
	money += pay
	deliveries += 1
	settled.emit(event("settled", pay))
	# A listener may restart/reload. Old work must not create a new session's ticket.
	if _run_closed or generation != expected_generation or order_id != expected_order: return true
	if money >= config.goal_money: shift_ended.emit(event("won"))
	else: create_ticket(available)
	return true

func tick(delta: float, available: Array[String]) -> void:
	if lifecycle not in [Lifecycle.AT_SHOP, Lifecycle.ON_ROUTE]: return
	remaining = maxf(0, remaining - delta)
	if remaining == 0: expire(available, generation, order_id)

func expire(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	if generation != expected_generation or order_id != expected_order or remaining > 0: return false
	if lifecycle not in [Lifecycle.AT_SHOP, Lifecycle.ON_ROUTE]: return false
	lifecycle = Lifecycle.CLOSED
	cargo_count = 0
	strikes += 1
	timed_out.emit(event("timed_out"))
	if _run_closed or generation != expected_generation or order_id != expected_order: return true
	if strikes >= config.max_strikes: shift_ended.emit(event("lost"))
	else: create_ticket(available)
	return true

func close() -> void:
	_run_closed = true
	lifecycle = Lifecycle.CLOSED

func event(outcome: String, pay: int = 0) -> Dictionary:
	var value := {"generation": generation, "order_id": order_id, "destination_id": destination_id,
		"outcome": outcome, "pay": pay, "money": money, "deliveries": deliveries,
		"strikes": strikes, "pizzas": pizzas, "cargo_count": cargo_count}
	value.make_read_only()
	return value
