extends Node
## Phase 06: one validated interaction target drives both the prompt and the
## action. Gameplay code registers entries with an anchor, an action label and a
## gate; Presentation reads `prompt()` and Game calls `activate()`, so no
## distance-only logic is duplicated between the HUD and the action anymore.
##
## Entry fields (only `id`, `anchor`, `label` and `on_activate` are required):
##   id           stable StringName, also what the snapshot and checks report
##   anchor       Node3D or a Callable returning one (validated every query)
##   label        String or Callable -> String: what the action does
##   on_activate  Callable(self) -> bool: ran the action (false = refused)
##   enabled      Callable -> bool; when it is false the prompt shows `reason`
##   reason       Callable -> String: why the target is blocked right now
##   active       Callable -> bool: dormant targets are invisible to the query
##   range        metres from the approach point (default 3.0)
##   priority     higher wins a tie (default 0)
##   modes        ActorController modes allowed to use it ([] = any)
##   access       local offset from the anchor: where the actor should stand
##   view         height above the approach point for the line-of-sight target
##   facing       degrees of facing cone required (0 = any direction)
##   los          require a clear ray from the actor's eye (default true)
##
## Selection is deterministic: enabled beats blocked, then priority, then
## distance, then the id string. Activation re-runs the same query, so a stale
## prompt can never fire an action.

const Layers = preload("res://scripts/collision_layers.gd")
const InputBindings = preload("res://scripts/services/input_bindings.gd")
## Line of sight only ever looks at level geometry: actors and vehicles are
## excluded on purpose, so a parked van or a bystander never blinds a prompt.
const LOS_MASK := Layers.WORLD

## A target consumed the press and ran its action.
signal activated(event: Dictionary)
## A press reached an in-range target that is blocked right now.
signal refused(event: Dictionary)

var world: RefCounted
var actors: Node
var dialogue: Node

var _entries: Dictionary = {}
var _order: Array[StringName] = []


func configure(registry: RefCounted, controller: Node, talking: Node) -> void:
	world = registry
	actors = controller
	dialogue = talking


func clear() -> void:
	_entries.clear()
	_order.clear()


func register(entry: Dictionary) -> bool:
	var id := StringName(entry.get("id", ""))
	if id.is_empty() or not entry.has("on_activate"):
		return false
	if entry.get("label", null) == null or entry.get("anchor", null) == null:
		return false
	if not _entries.has(id):
		_order.append(id)
	_entries[id] = entry.duplicate()
	return true


func unregister(id: StringName) -> bool:
	if not _entries.has(id):
		return false
	_entries.erase(id)
	_order.erase(id)
	return true


func ids() -> Array[StringName]:
	return _order.duplicate()


func has(id: StringName) -> bool:
	return _entries.has(id)


## Live entry table copy for checks and diagnostics (never mutated by callers).
func entries() -> Dictionary:
	return _entries.duplicate()


## The actor the query runs for: Pip on foot, the van while driving.
func observer() -> Dictionary:
	var mode: int = actors.mode if actors != null else 0
	var node: Node3D = (world.van if mode == actors.Mode.DRIVING else world.pip) if world != null else null
	if node == null:
		return {}
	var basis := node.global_transform.basis
	var driving: bool = mode == actors.Mode.DRIVING
	return {
		"node": node, "rid": node.get_rid(), "driving": driving,
		"mode": mode, "kind": "driving" if driving else "foot",
		"position": node.global_position,
		"forward": Vector3(-basis.z.x, 0, -basis.z.z).normalized(),
		"eye": node.global_position.y + (1.5 if driving else 1.35),
	}


## Winner of the deterministic query: {} when nothing is in reach.
func select() -> Dictionary:
	if not available():
		return {}
	var obs := observer()
	if obs.is_empty():
		return {}
	var found: Array = []
	for id in _order:
		var entry: Dictionary = _entries[id]
		var anchor := _anchor(entry)
		if anchor == null or not _active(entry):
			continue
		if not _mode_ok(entry, obs.mode):
			continue
		var point: Vector3 = anchor.global_transform * Vector3(entry.get("access", Vector3.ZERO))
		var flat := Vector2(point.x - obs.position.x, point.z - obs.position.z)
		var distance := flat.length()
		if distance > float(entry.get("range", 3.0)) or absf(point.y - obs.position.y) > 2.5:
			continue
		if not _facing_ok(entry, obs, point, distance):
			continue
		if bool(entry.get("los", true)) and not _clear(entry, obs, point):
			continue
		var enabled := _enabled(entry)
		found.append({
			"id": id, "entry": entry, "enabled": enabled, "distance": distance,
			"label": _label(entry), "reason": "" if enabled else _reason(entry),
			"priority": int(entry.get("priority", 0)),
		})
	if found.is_empty():
		return {}
	found.sort_custom(_rank)
	return found[0]


## HUD prompt line: the action when it is legal, else the blocked reason.
func prompt() -> String:
	return str(prompt_view().get("text", ""))


## Prompt text plus the id it belongs to, in a single query, so a HUD line and the
## snapshot can never describe two different targets.
func prompt_view() -> Dictionary:
	var winner := select()
	if winner.is_empty():
		return {"text": "", "id": &""}
	if not winner.enabled:
		return {"text": winner.reason, "id": winner.id}
	return {"text": "[%s]   %s" % [InputBindings.prompt("interact"), winner.label], "id": winner.id}


## The target a press would reach, for snapshots and diagnostics.
func prompt_id() -> StringName:
	return prompt_view().get("id", &"")


## Revalidates and runs the winning target. Returns whether it acted.
func activate() -> bool:
	var winner := select()
	if winner.is_empty():
		return false
	if not winner.enabled:
		refused.emit({"id": winner.id, "reason": winner.reason})
		return false
	var action: Callable = winner.entry.on_activate
	var acted := action.is_valid() and bool(action.call(self))
	if acted:
		activated.emit({"id": winner.id, "label": winner.label})
	else:
		refused.emit({"id": winner.id, "reason": _reason(winner.entry)})
	return acted


## Interaction stays dormant while a conversation owns input and outside play.
func available() -> bool:
	if world == null or actors == null or dialogue == null:
		return false
	if dialogue.has_method("active") and dialogue.active():
		return false
	if world.pip == null or world.van == null:
		return false
	return true


## The target a press would reach, for snapshots and diagnostics.
## (See prompt_view: text and id always come from the same query.)
func _rank(a: Dictionary, b: Dictionary) -> bool:
	if a.enabled != b.enabled:
		return a.enabled
	if a.priority != b.priority:
		return a.priority > b.priority
	if not is_equal_approx(a.distance, b.distance):
		return a.distance < b.distance
	return str(a.id) < str(b.id)


func _anchor(entry: Dictionary) -> Node3D:
	var value = entry.get("anchor")
	var node: Node3D = null
	# A freed anchor is the normal case after a target is removed: `is` on a freed
	# instance is an error, so validity is checked before any type test.
	if is_instance_valid(value):
		if value is Callable:
			var provider: Callable = value
			if provider.is_valid():
				node = provider.call()
		elif value is Node3D:
			node = value
	if not is_instance_valid(node) or not node.is_inside_tree():
		return null
	return node


func _active(entry: Dictionary) -> bool:
	var gate: Callable = entry.get("active", Callable())
	return bool(gate.call()) if gate.is_valid() else true


func _enabled(entry: Dictionary) -> bool:
	var gate: Callable = entry.get("enabled", Callable())
	return bool(gate.call()) if gate.is_valid() else true


func _label(entry: Dictionary) -> String:
	var value = entry.get("label", "")
	if value is Callable:
		var provider: Callable = value
		return str(provider.call()) if provider.is_valid() else ""
	return str(value)


func _reason(entry: Dictionary) -> String:
	var gate: Callable = entry.get("reason", Callable())
	var text := str(gate.call()) if gate.is_valid() else ""
	return text if not text.is_empty() else "NOT AVAILABLE"


func _mode_ok(entry: Dictionary, mode: int) -> bool:
	var modes: Array = entry.get("modes", [])
	return modes.is_empty() or mode in modes


## Facing is measured to the approach point; standing on the point itself can
## never fail it (there is no direction to compare).
func _facing_ok(entry: Dictionary, obs: Dictionary, point: Vector3, distance: float) -> bool:
	var degrees := float(entry.get("facing", 0.0))
	if degrees <= 0.0 or distance < 0.2:
		return true
	var to := Vector3(point.x - obs.position.x, 0, point.z - obs.position.z).normalized()
	return (obs.forward as Vector3).dot(to) >= cos(deg_to_rad(degrees))


## Wall/floor query: WORLD only, with the acting body excluded. Vehicles and
## placeholder people are deliberately not in the mask - access offsets and
## ranges keep vans and bystanders from blinding a prompt.
func _clear(entry: Dictionary, obs: Dictionary, point: Vector3) -> bool:
	var body := obs.node as Node3D
	var from := Vector3(obs.position.x, obs.eye, obs.position.z)
	var to := point + Vector3(0, float(entry.get("view", 1.1)), 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, LOS_MASK)
	query.exclude = [obs.rid]
	return body.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
