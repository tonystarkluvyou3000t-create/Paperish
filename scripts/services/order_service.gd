extends Node
## Order lifecycle and payment ledger. CargoService is the sole owner of
## package IDs and physical locations; these records own deadlines and outcome.
signal ticket_created(event: Dictionary)
signal ticket_ready(event: Dictionary)
signal picked_up(event: Dictionary)
signal receipt_created(event: Dictionary)
signal settled(event: Dictionary)
signal timed_out(event: Dictionary)
signal shift_ended(event: Dictionary)

enum Lifecycle { IDLE, AT_SHOP, ON_ROUTE, CLOSED }
enum TicketState { NONE, PREPARING, READY, COLLECTED }
const TICKET_STATES: Array[String] = ["none", "preparing", "ready", "collected"]
const LIFECYCLE_NAMES: Array[String] = ["idle", "at_shop", "on_route", "closed"]

var config: Resource
var cargo_service: Node
var route_estimator: Callable
var money := 0
var deliveries := 0
var strikes := 0
var generation := 0
var last_destination := ""
var forced_destination := ""
var total_base := 0
var total_pizza := 0
var total_tip := 0
var total_quality := 0
var _seed := -1
var _run_closed := false
var _next_order_id := 0
var _selected_order_id := 0
var _orders: Dictionary = {} # order ID -> lifecycle record
var _rng := RandomNumberGenerator.new()

var order_id: int:
	get: return _selected_order_id
	set(value): _selected_order_id = value
var lifecycle: Lifecycle:
	get: return int(_current().get("lifecycle", Lifecycle.IDLE))
var ticket_state: TicketState:
	get: return int(_current().get("ticket_state", TicketState.NONE))
var destination_id: String:
	get: return str(_current().get("destination_id", ""))
var pizzas: int:
	get: return int(_current().get("quantity", 0))
var cargo_count: int:
	get: return cargo_service.count_for_order(order_id, ["pip"]) if cargo_service and order_id > 0 else 0
var preparation_remaining: float:
	get: return float(_current().get("preparation_remaining", 0.0))
	set(value): _set_current("preparation_remaining", maxf(value, 0.0))
var remaining: float:
	get: return float(_current().get("remaining", 0.0))
	set(value): _set_current("remaining", maxf(value, 0.0))
var duration: float:
	get: return float(_current().get("duration", 60.0))


func _init() -> void:
	_rng.randomize()


func set_seed(value: int) -> void:
	_seed = value
	_rng.seed = value


func reset(next_generation: int) -> void:
	generation = next_generation
	_run_closed = false
	money = 0
	deliveries = 0
	strikes = 0
	_next_order_id = 0
	_selected_order_id = 0
	_orders.clear()
	last_destination = ""
	forced_destination = ""
	total_base = 0
	total_pizza = 0
	total_tip = 0
	total_quality = 0
	if cargo_service:
		cargo_service.reset()
	if _seed >= 0:
		_rng.seed = _seed


func force_destination(id: String, available: Array[String]) -> bool:
	if id not in available:
		return false
	forced_destination = id
	return true


## The tutorial/default path creates one job. Additional explicitly accepted
## tickets go through queue_ticket(), which applies the same capacity rules.
func create_ticket(available: Array[String]) -> bool:
	return queue_ticket(available, true)


func can_queue(available: Array[String]) -> bool:
	if not _can_accept(available, 1):
		return false
	var has_delivery := false
	for id in outstanding_order_ids():
		if int(_orders[id].lifecycle) == Lifecycle.ON_ROUTE:
			has_delivery = true
			break
	if not has_delivery:
		return false
	var reserved := 0
	for id in outstanding_order_ids():
		reserved += int(_orders[id].quantity)
	return reserved < int(config.van_capacity)


func queue_ticket(available: Array[String], select_after := false) -> bool:
	if not _can_accept(available, 1):
		return false
	if not select_after and not can_queue(available):
		return false
	var chosen := _choose_destination(available)
	if chosen.is_empty():
		return false
	var quantity := _rng.randi_range(1, 3)
	# Acceptance is capacity-aware before any ticket or package is committed.
	var reserved := 0
	for id in outstanding_order_ids():
		reserved += int(_orders[id].quantity)
	if reserved + quantity > int(config.van_capacity):
		return false
	var next_id := _next_order_id + 1
	# Budget = the conservative route estimate (drive + parking + exit + walk +
	# handoff) with a guaranteed minimum slack, never tighter than the classic
	# short-hop deadline: long routes stay feasible while short hops keep their
	# original pacing.
	var deadline := maxf(config.deadline_floor, config.deadline_start - deliveries * config.deadline_decrease)
	if route_estimator.is_valid():
		var estimate := float(route_estimator.call(chosen))
		if not is_finite(estimate):
			return false
		deadline = maxf(deadline, estimate + float(config.deadline_min_slack))
	var prep := maxf(config.preparation_duration, 0.0)
	var record := {
		"generation": generation, "order_id": next_id, "destination_id": chosen,
		"quantity": quantity, "lifecycle": Lifecycle.AT_SHOP,
		"ticket_state": TicketState.PREPARING if prep > 0.0 else TicketState.READY,
		"preparation_remaining": prep, "remaining": 0.0, "duration": deadline,
		"quality": 1.0, "settled": false, "failure": "",
	}
	if cargo_service and not cargo_service.create_order(generation, next_id, chosen, quantity):
		return false
	_next_order_id = next_id
	_orders[next_id] = record
	last_destination = chosen
	if select_after or _selected_order_id == 0 or not is_order_active(_selected_order_id):
		_selected_order_id = next_id
	if forced_destination == chosen:
		forced_destination = ""
	ticket_created.emit(event("created", 0, next_id))
	if int(record.ticket_state) == TicketState.READY:
		ticket_ready.emit(event("ready", 0, next_id))
	return true


func can_pickup(order: int = -1) -> bool:
	var id := order_id if order < 0 else order
	var record: Dictionary = _orders.get(id, {})
	return not record.is_empty() and int(record.lifecycle) == Lifecycle.AT_SHOP \
		and int(record.ticket_state) == TicketState.READY and cargo_service != null \
		and cargo_service.location_for_order(id) == cargo_service.COUNTER


func pickup() -> bool:
	return pickup_order(order_id)


func pickup_order(id: int) -> bool:
	if not can_pickup(id):
		return false
	# Package transfer is validated first. Lifecycle changes only after the whole
	# bundle moved successfully, so a rejected receipt leaves both owners intact.
	if not cargo_service.transfer_order(id, cargo_service.COUNTER, cargo_service.PIP):
		return false
	var record: Dictionary = _orders[id]
	record.ticket_state = TicketState.COLLECTED
	record.preparation_remaining = 0.0
	record.remaining = float(record.duration)
	record.lifecycle = Lifecycle.ON_ROUTE
	record.quality = 1.0
	_orders[id] = record
	_selected_order_id = id
	var receipt := event("picked_up", 0, id)
	picked_up.emit(receipt)
	receipt_created.emit(receipt)
	return true


func ticket_state_name(order: int = -1) -> String:
	var id := order_id if order < 0 else order
	var state := int(_orders.get(id, {}).get("ticket_state", TicketState.NONE))
	return TICKET_STATES[clampi(state, 0, TICKET_STATES.size() - 1)]


func lifecycle_name(order: int = -1) -> String:
	var id := order_id if order < 0 else order
	var state := int(_orders.get(id, {}).get("lifecycle", Lifecycle.IDLE))
	return LIFECYCLE_NAMES[clampi(state, 0, LIFECYCLE_NAMES.size() - 1)]


func select_order(id: int) -> bool:
	if not is_order_active(id):
		return false
	_selected_order_id = id
	return true


func is_order_active(id: int) -> bool:
	var state := int(_orders.get(id, {}).get("lifecycle", Lifecycle.CLOSED))
	return state in [Lifecycle.AT_SHOP, Lifecycle.ON_ROUTE]


func outstanding_order_ids() -> Array[int]:
	var ids: Array[int] = []
	for key in _orders.keys():
		if is_order_active(int(key)):
			ids.append(int(key))
	ids.sort()
	return ids


## Recovery (unstuck) charges the running delivery clocks. The floor guarantees a
## rescue can never itself cause a timeout, and a nearly-expired order is never
## extended. Returns the seconds actually applied.
func apply_recovery_cost(seconds: float, floor_seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	var applied := 0.0
	for id in outstanding_order_ids():
		var record: Dictionary = _orders[id]
		if int(record.lifecycle) != Lifecycle.ON_ROUTE:
			continue
		var remaining := maxf(float(record.get("remaining", 0.0)), 0.0)
		var next := clampf(remaining - seconds, minf(floor_seconds, remaining), remaining)
		record["remaining"] = next
		applied = maxf(applied, remaining - next)
	return applied


func order_data(id: int) -> Dictionary:
	if not _orders.has(id):
		return {}
	var record: Dictionary = _orders[id].duplicate(true)
	record["ticket_state_name"] = ticket_state_name(id)
	record["lifecycle_name"] = lifecycle_name(id)
	record["cargo_location"] = cargo_service.location_for_order(id) if cargo_service else ""
	record["cargo_count"] = cargo_service.count_for_order(id) if cargo_service else 0
	record.make_read_only()
	return record


func tip(order: int = -1) -> int:
	var id := order_id if order < 0 else order
	var record: Dictionary = _orders.get(id, {})
	if record.is_empty():
		return 0
	return int(round(config.max_tip * clampf(float(record.remaining) / maxf(float(record.duration), 0.01), 0, 1)))


func settle(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	return settle_order(available, expected_generation, expected_order, destination_for_order(expected_order))


func settle_order(available: Array[String], expected_generation: int, expected_order: int, customer_id: String) -> bool:
	if expected_generation != generation or not _orders.has(expected_order):
		return false
	var record: Dictionary = _orders[expected_order]
	if int(record.generation) != expected_generation or bool(record.settled):
		return false
	if str(record.destination_id) != customer_id or int(record.lifecycle) != Lifecycle.ON_ROUTE:
		return false
	if float(record.remaining) <= 0.0 or cargo_service == null \
			or cargo_service.location_for_order(expected_order) != cargo_service.PIP \
			or cargo_service.count_for_order(expected_order, [cargo_service.PIP]) != int(record.quantity):
		return false
	var quality := clampf(float(record.remaining) / maxf(float(record.duration), 0.01), 0.0, 1.0)
	if not cargo_service.settle_order(expected_order, quality):
		return false
	var base: int = config.base_pay
	var pizza_pay: int = config.pay_per_pizza * int(record.quantity)
	var tip_pay := tip(expected_order)
	var quality_pay := int(config.quality_bonus) if quality >= float(config.quality_bonus_threshold) \
		else (-int(config.quality_penalty) if quality < float(config.quality_penalty_threshold) else 0)
	var pay := maxi(0, base + pizza_pay + tip_pay + quality_pay)
	record.lifecycle = Lifecycle.CLOSED
	record.settled = true
	record.ticket_state = TicketState.NONE
	record.remaining = 0.0
	record.quality = quality
	record.settlement = {"base": base, "pizza": pizza_pay, "tip": tip_pay,
		"quality": quality_pay, "total": pay}
	record.failure = ""
	_orders[expected_order] = record
	money += pay
	deliveries += 1
	total_base += base
	total_pizza += pizza_pay
	total_tip += tip_pay
	total_quality += quality_pay
	var result := event("settled", pay, expected_order)
	settled.emit(result)
	# Signal listeners may restart or end this run. Never create work for a newer
	# generation or continue after the shift has closed.
	if _run_closed or generation != expected_generation:
		return true
	if money >= config.goal_money:
		shift_ended.emit(event("won", 0, expected_order))
	elif outstanding_order_ids().is_empty():
		_selected_order_id = 0
		queue_ticket(available, true)
	else:
		_select_next_active()
	return true


func expire(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	return expire_order(available, expected_generation, expected_order)


func expire_order(available: Array[String], expected_generation: int, expected_order: int) -> bool:
	if expected_generation != generation or not _orders.has(expected_order):
		return false
	var record: Dictionary = _orders[expected_order]
	if int(record.generation) != expected_generation or int(record.lifecycle) != Lifecycle.ON_ROUTE \
			or float(record.remaining) > 0.0:
		return false
	# Expiry is the explicit, irreversible reclassification path for boxes in Pip
	# or the van. A failed transaction leaves the order live and retryable.
	if cargo_service == null or not cargo_service.discard_order(expected_order):
		return false
	record.lifecycle = Lifecycle.CLOSED
	record.ticket_state = TicketState.NONE
	record.remaining = 0.0
	record.failure = "expired"
	_orders[expected_order] = record
	strikes += 1
	timed_out.emit(event("timed_out", 0, expected_order))
	if _run_closed or generation != expected_generation:
		return true
	if strikes >= config.max_strikes:
		shift_ended.emit(event("lost", 0, expected_order))
	else:
		if outstanding_order_ids().is_empty():
			_selected_order_id = 0
			queue_ticket(available, true)
		else:
			_select_next_active()
	return true


func tick(delta: float, available: Array[String]) -> void:
	if _run_closed:
		return
	var ids := outstanding_order_ids()
	for id in ids:
		if not _orders.has(id) or not is_order_active(id):
			continue
		var record: Dictionary = _orders[id]
		if int(record.lifecycle) == Lifecycle.AT_SHOP and int(record.ticket_state) == TicketState.PREPARING:
			record.preparation_remaining = maxf(0.0, float(record.preparation_remaining) - maxf(delta, 0.0))
			if float(record.preparation_remaining) <= 0.0:
				record.ticket_state = TicketState.READY
				_orders[id] = record
				ticket_ready.emit(event("ready", 0, id))
			else:
				_orders[id] = record
		elif int(record.lifecycle) == Lifecycle.ON_ROUTE:
			record.remaining = maxf(0.0, float(record.remaining) - maxf(delta, 0.0))
			_orders[id] = record
			if float(record.remaining) <= 0.0:
				expire_order(available, generation, id)


func close() -> void:
	_run_closed = true
	for id in outstanding_order_ids():
		if cargo_service:
			cargo_service.discard_order(id)
		var record: Dictionary = _orders[id]
		record.lifecycle = Lifecycle.CLOSED
		record.ticket_state = TicketState.NONE
		record.preparation_remaining = 0.0
		record.remaining = 0.0
		record.failure = "shift_closed"
		_orders[id] = record


func event(outcome: String, pay := 0, order: int = -1) -> Dictionary:
	var id := order_id if order < 0 else order
	var record: Dictionary = _orders.get(id, {})
	var quantity := int(record.get("quantity", 0))
	var location: String = cargo_service.location_for_order(id) if cargo_service and id > 0 else ""
	var cargo: int = cargo_service.count_for_order(id, ["pip"]) if cargo_service and id > 0 else 0
	var total_packages: int = cargo_service.count_for_order(id) if cargo_service and id > 0 else 0
	var value := {
		"generation": generation, "order_id": id, "destination_id": str(record.get("destination_id", "")),
		"outcome": outcome, "pay": pay, "money": money, "deliveries": deliveries,
		"strikes": strikes, "pizzas": quantity, "quantity": quantity, "cargo_count": cargo,
		"package_count": total_packages,
		"cargo_location": location, "ticket_state": ticket_state_name(id),
		"lifecycle": lifecycle_name(id), "preparation_remaining": float(record.get("preparation_remaining", 0.0)),
		"remaining": float(record.get("remaining", 0.0)), "duration": float(record.get("duration", 0.0)),
		"quality": float(record.get("quality", 0.0)), "quality_adjustment": 0,
		"base_pay": int(record.get("settlement", {}).get("base", 0)),
		"pizza_pay": int(record.get("settlement", {}).get("pizza", 0)),
		"tip_pay": int(record.get("settlement", {}).get("tip", 0)),
		"settlement_total": int(record.get("settlement", {}).get("total", pay)),
	}
	if outcome == "settled":
		value.quality_adjustment = int(record.get("settlement", {}).get("quality", 0))
	value.make_read_only()
	return value


func destination_for_order(id: int) -> String:
	return str(_orders.get(id, {}).get("destination_id", ""))


func order_count() -> int:
	return outstanding_order_ids().size()


func inventory_lines() -> String:
	if cargo_service == null:
		return "NO CARGO SERVICE"
	return cargo_service.inventory_lines()


func all_order_summaries() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id in outstanding_order_ids():
		rows.append(order_data(id))
	return rows


func _can_accept(available: Array[String], requested: int) -> bool:
	if _run_closed or available.is_empty() or config == null or cargo_service == null:
		return false
	if outstanding_order_ids().size() + requested > int(config.max_queued_orders):
		return false
	return true


func _choose_destination(available: Array[String]) -> String:
	var ids := available.duplicate()
	ids.sort()
	var active_destinations: Array[String] = []
	for id in outstanding_order_ids():
		active_destinations.append(destination_for_order(id))
	var eligible: Array[String] = []
	for id in ids:
		if id not in active_destinations:
			eligible.append(id)
	if eligible.is_empty():
		return ""
	var index := _rng.randi_range(0, eligible.size() - 1)
	if not forced_destination.is_empty() and forced_destination in eligible:
		return forced_destination
	if eligible.size() > 1 and eligible[index] == last_destination:
		index = (index + 1) % eligible.size()
	return eligible[index]


func _current() -> Dictionary:
	return _orders.get(_selected_order_id, {})


func _set_current(key: String, value: Variant) -> void:
	if _orders.has(_selected_order_id):
		var record: Dictionary = _orders[_selected_order_id]
		record[key] = value
		_orders[_selected_order_id] = record


func _select_next_active() -> void:
	var ids := outstanding_order_ids()
	_selected_order_id = ids[0] if not ids.is_empty() else 0
