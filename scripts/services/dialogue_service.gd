extends Node
## Phase 06: data-authored conversations with explicit effects and one committed
## result. Data lives in res://data/dialogue/*.json; `validate_set()` runs at load
## and in tools/check_dialogue.gd, so a broken reference can never reach play.
##
## Schema (see docs/ARCHITECTURE.md):
##   id        unique conversation id
##   speaker   {"name": "MONA", "color": "f4bb4d"} (colour is a chip, not a face)
##   cancel    "close" (esc leaves, nothing lost) or "pause" (esc pauses over it)
##   entry     ordered [{when: [conditions], node: "id"}]; the last has no `when`
##   nodes     [{id, text, next?, choices?, effects?, commit?}]
##
## Conditions: {"kind": "flag", "id"} | {"kind": "cargo"|"deliveries", "op", "value"}
##             | {"kind": "lifecycle", "is"} | {"kind": "mode", "is": "shift"|"roam"}
## Effects:    {"kind": "flag", "id"} | {"kind": "toast", "text"}
##             | {"kind": "order", "do": "pick_up"|"deliver"}  (commit nodes only)
##
## Text tokens: {{pizzas}} {{address}} {{tip}} {{deliveries}} {{money}}. Anything
## else is a validation error; there is no scripting in the data.
##
## Transactional rule: `effects` on a node run when the node is entered, and the
## validator only allows flag/toast there. `order` effects may only live on a
## node with `commit`, which runs exactly once, when the conversation ends at
## that node. Cancelling therefore can never pay out or remove cargo.

signal opened(event: Dictionary)
signal updated(event: Dictionary)
signal closed(event: Dictionary)

const FILES := [
	"res://data/dialogue/shopkeeper.json",
	"res://data/dialogue/customer.json",
	"res://data/dialogue/gossip.json",
]
const CONDITION_KINDS := ["flag", "cargo", "deliveries", "lifecycle", "mode"]
const EFFECT_KINDS := ["flag", "toast", "order"]
const COMMANDS := ["pick_up", "deliver"]
const TOKENS := ["pizzas", "address", "tip", "deliveries", "money"]
const NODE_KEYS := ["id", "text", "next", "choices", "effects", "commit"]
const CHOICE_KEYS := ["label", "next", "effects"]
const BASE_RATE := 42.0

var world: RefCounted
var orders: Node
var session: Node
var settings: Node
var hud: CanvasLayer

var conversations: Dictionary = {}
var errors: Array[String] = []
var flags: Dictionary = {}

var conversation_id := ""
var node_id := ""
var busy_id: StringName = &""
var cancellable := false
var session_id := 0
var generation := 0

var _revealed := 0.0
var _line := ""
var _latch_frame := -1
var _anchor: WeakRef
var _commands: Dictionary = {}
var _log: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func configure(registry: RefCounted, tickets: Node, flow: Node, preferences: Node, ui: CanvasLayer) -> void:
	world = registry
	orders = tickets
	session = flow
	settings = preferences
	hud = ui


func bind_command(command: String, action: Callable) -> void:
	_commands[command] = action


func load_all() -> Array[String]:
	conversations.clear()
	errors.clear()
	var raw: Dictionary = {}
	for path in FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("missing dialogue file: " + path)
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("dialogue file is not a JSON object: " + path)
			continue
		var data: Dictionary = parsed
		var id := str(data.get("id", ""))
		if id.is_empty():
			errors.append("dialogue file has no id: " + path)
			continue
		if raw.has(id):
			errors.append("duplicate conversation id: " + id)
			continue
		raw[id] = data
	errors.append_array(validate_set(raw))
	if errors.is_empty():
		conversations = raw
	return errors


func has(conversation: String) -> bool:
	return conversations.has(conversation)


func has_flag(flag: String) -> bool:
	return flags.has(flag)


func set_flag(flag: String) -> void:
	if not flag.is_empty():
		flags[flag] = true


## Conversation-session generation, bumped by every start.
func sessions() -> int:
	return session_id


func active() -> bool:
	return not conversation_id.is_empty()


func state() -> String:
	if not active():
		return ""
	if _revealing():
		return "revealing"
	return "choices" if not _choices_of(_node(node_id)).is_empty() else "line"


func speaker() -> Dictionary:
	if not active():
		return {}
	return _root().get("speaker", {})


func text() -> String:
	return _line


func visible_text() -> String:
	return _line.substr(0, clampi(int(_revealed), 0, _line.length()))


func revealing() -> bool:
	return active() and _revealing()


func choices() -> Array[String]:
	var out: Array[String] = []
	if not active() or _revealing():
		return out
	for choice in _choices_of(_node(node_id)):
		out.append(_tokens(str(choice.get("label", ""))))
	return out


func snapshot() -> Dictionary:
	return {
		"dialogue_id": conversation_id, "dialogue_node": node_id,
		"dialogue_state": state(), "dialogue_choices": choices().size(),
		"dialogue_busy": str(busy_id), "dialogue_flags": flags.size(),
	}


## Opens a conversation. `busy` and `anchor` name the target that owns it, so a
## deleted target can close the session instead of hanging on a freed actor.
func start(conversation: String, busy: StringName = &"", anchor: Node3D = null) -> bool:
	if active() or not has(conversation):
		return false
	if session == null or session.flow != session.Flow.PLAYING:
		return false
	var data: Dictionary = conversations[conversation]
	var entry := _resolve_entry(data)
	if entry.is_empty():
		_log.append("no entry matched: " + conversation)
		return false
	conversation_id = conversation
	busy_id = busy
	cancellable = str(data.get("cancel", "close")) == "close"
	_anchor = weakref(anchor) if anchor != null else null
	_revealed = 0.0
	session_id += 1
	generation = session.generation
	_latch_frame = Engine.get_process_frames()
	session.open_modal(&"dialogue")
	_enter(str(entry.get("node", "")))
	opened.emit(_event())
	return true


## One confirm reveals a partial line; the next one advances. A node with
## choices never advances - the player has to pick one.
func advance() -> bool:
	if not active() or _latched():
		return false
	if _revealing():
		_revealed = float(_line.length())
		updated.emit(_event())
		return true
	var node := _node(node_id)
	if not _choices_of(node).is_empty():
		return false
	var next := str(node.get("next", ""))
	if next.is_empty():
		return end()
	_enter(next)
	return true


func choose(index: int) -> bool:
	if not active() or _latched() or _revealing():
		return false
	var options := _choices_of(_node(node_id))
	if index < 0 or index >= options.size():
		return false
	var choice: Dictionary = options[index]
	_apply_effects(choice.get("effects", []), false)
	var next := str(choice.get("next", ""))
	if next.is_empty():
		# Authored exit: an explicit way to leave without committing anything.
		return _close("", false)
	_enter(next)
	return true


## Authored cancel path: only conversations that allow it can be left with esc.
func cancel() -> bool:
	if not active() or not cancellable or _latched():
		return false
	return _close("", false)


## Ends the conversation at the current node, applying its commit exactly once.
func end() -> bool:
	if not active() or _latched():
		return false
	var node := _node(node_id)
	var commit := str(node.get("commit", ""))
	if commit.is_empty():
		return _close("", false)
	_apply_effects(node.get("effects", []), true)
	return _close(commit, true)


## Restart/world-reload path: drops the session without applying anything.
func reset() -> void:
	if active():
		_close("", false)
	flags.clear()
	_log.clear()


func problems() -> Array[String]:
	return errors.duplicate()


func log_lines() -> Array[String]:
	return _log.duplicate()


func _process(delta: float) -> void:
	if not active() or session == null:
		return
	if _revealing():
		_revealed = minf(float(_line.length()), _revealed + BASE_RATE * text_speed() * delta)
	# Sessions die with their target or their shift; neither may leave input hung.
	if generation != session.generation or session.flow != session.Flow.PLAYING:
		_close("", false)
		return
	if _anchor != null:
		var target = _anchor.get_ref()
		if target == null or not is_instance_valid(target) or not (target as Node3D).is_inside_tree():
			_close("", false)


func text_speed() -> float:
	if settings == null:
		return 1.0
	return clampf(float(settings.value("text/speed")), 0.25, 4.0)


func _latched() -> bool:
	return Engine.get_process_frames() <= _latch_frame


func _revealing() -> bool:
	return not active() or _revealed < float(_line.length())


func _root() -> Dictionary:
	return conversations.get(conversation_id, {})


func _node(id: String) -> Dictionary:
	for node in _root().get("nodes", []):
		if str(node.get("id", "")) == id:
			return node
	return {}


func _choices_of(node: Dictionary) -> Array:
	return _choice_list(node)


## Choices are an array or nothing: a malformed node must not crash play.
static func _choice_list(node: Dictionary) -> Array:
	var raw = node.get("choices", [])
	return raw if raw is Array else []


func _resolve_entry(data: Dictionary) -> Dictionary:
	var entries = data.get("entry", [])
	if not (entries is Array):
		return {}
	for candidate in entries:
		# Unwritten shapes are refused by validation; play must survive them too.
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		if _when_matches(candidate.get("when", [])) and not str(candidate.get("node", "")).is_empty():
			return candidate
	return {}


func _enter(id: String) -> void:
	node_id = id
	_revealed = 0.0
	var node := _node(id)
	_line = _tokens(str(node.get("text", "")))
	var commit := str(node.get("commit", ""))
	if commit.is_empty():
		_apply_effects(node.get("effects", []), false)
	updated.emit(_event())


func _close(result: String, committed: bool) -> bool:
	var event := {
		"id": conversation_id, "result": result, "committed": committed,
		"node": node_id, "session": session_id, "generation": generation,
	}
	conversation_id = ""
	node_id = ""
	_line = ""
	_revealed = 0.0
	_anchor = null
	busy_id = &""
	if session != null:
		session.close_modal(&"dialogue")
	closed.emit(event)
	return true


func _event() -> Dictionary:
	return {
		"id": conversation_id, "node": node_id, "state": state(),
		"cancellable": cancellable, "busy": busy_id,
	}


func _apply_effects(effects: Array, transactional: bool) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		match str(effect.get("kind", "")):
			"flag":
				set_flag(str(effect.get("id", "")))
			"toast":
				if hud != null and hud.has_method("caption"):
					hud.caption(str(effect.get("text", "")))
			"order":
				# Defence in depth: the validator keeps these on commit nodes.
				if not transactional:
					_log.append("skipped transactional effect outside a commit: " + str(effect))
					continue
				_command(str(effect.get("do", "")))


func _command(command: String) -> bool:
	var action: Callable = _commands.get(command, Callable())
	if not action.is_valid():
		_log.append("unbound dialogue command: " + command)
		return false
	return bool(action.call())


func _when_matches(conditions: Array) -> bool:
	for condition in conditions:
		if typeof(condition) != TYPE_DICTIONARY or not _condition_ok(condition):
			return false
	return true


func _condition_ok(condition: Dictionary) -> bool:
	match str(condition.get("kind", "")):
		"flag":
			return has_flag(str(condition.get("id", "")))
		"cargo":
			return _compare(float(orders.cargo_count), condition)
		"deliveries":
			return _compare(float(orders.deliveries), condition)
		"lifecycle":
			return _lifecycle() == str(condition.get("is", ""))
		"mode":
			return ("roam" if session.roaming() else "shift") == str(condition.get("is", ""))
	return false


func _lifecycle() -> String:
	return ["idle", "at_shop", "on_route", "closed"][orders.lifecycle]


func _compare(value: float, condition: Dictionary) -> bool:
	var target := float(condition.get("value", 0))
	match str(condition.get("op", "eq")):
		"eq": return is_equal_approx(value, target)
		"ne": return not is_equal_approx(value, target)
		"gt": return value > target
		"gte": return value >= target
		"lt": return value < target
		"lte": return value <= target
	return false


func _tokens(text: String) -> String:
	if not text.contains("{{"):
		return text
	var address := ""
	if world != null and orders != null and not orders.destination_id.is_empty():
		var house: Node3D = world.destination(orders.destination_id)
		if house != null:
			address = str(house.get_meta("address", ""))
	# Explicit replacement rather than String.format: tokens are validated at load
	# and a stray brace stays literal instead of being treated as a placeholder.
	var values := {
		"pizzas": orders.pizzas if orders != null else 0,
		"address": address, "tip": orders.tip() if orders != null else 0,
		"deliveries": orders.deliveries if orders != null else 0,
		"money": orders.money if orders != null else 0,
	}
	var out := text
	for key in values:
		out = out.replace("{{%s}}" % key, str(values[key]))
	return out


# ------------------------------------------------------------------ validation
## Validates a conversation set (id -> data) without touching the world.
static func validate_set(all: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	for id in all.keys():
		var data = all[id]
		if not (data is Dictionary):
			problems.append(str(id) + ": conversation must be an object")
			continue
		problems.append_array(validate_conversation(str(id), data))
	return problems


static func validate_conversation(id: String, data: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var prefix := id + ": "
	for key in data.keys():
		if key not in ["id", "speaker", "cancel", "entry", "nodes"]:
			problems.append(prefix + "unknown field: " + str(key))
	var speaker = data.get("speaker", {})
	if not (speaker is Dictionary):
		problems.append(prefix + "speaker must be an object")
	elif str(speaker.get("name", "")).is_empty():
		problems.append(prefix + "speaker needs a name")
	elif not is_valid_color(str(speaker.get("color", ""))):
		problems.append(prefix + "speaker colour must be six hex digits")
	if str(data.get("cancel", "close")) not in ["close", "pause"]:
		problems.append(prefix + "cancel must be close or pause")
	# Shapes are checked, never trusted: a malformed file is reported, not crashed.
	var raw_nodes = data.get("nodes", [])
	if not (raw_nodes is Array):
		problems.append(prefix + "nodes must be a list")
		raw_nodes = []
	var nodes: Array = raw_nodes
	if nodes.is_empty():
		problems.append(prefix + "needs at least one node")
	var objects: Array = []
	for node in nodes:
		if typeof(node) != TYPE_DICTIONARY:
			problems.append(prefix + "node entries must be objects")
			continue
		objects.append(node)
	var ids: Array[String] = []
	for node in objects:
		var node_id := str(node.get("id", ""))
		if node_id.is_empty():
			problems.append(prefix + "node without an id")
		elif node_id in ids:
			problems.append(prefix + "duplicate node id: " + node_id)
		ids.append(node_id)
	for node in objects:
		problems.append_array(_validate_node(prefix, node, ids))
	var raw_entries = data.get("entry", [])
	if not (raw_entries is Array):
		problems.append(prefix + "entry must be a list")
		raw_entries = []
	var entries: Array = raw_entries
	if entries.is_empty():
		problems.append(prefix + "needs at least one entry")
	for i in range(entries.size()):
		if typeof(entries[i]) != TYPE_DICTIONARY:
			problems.append(prefix + "entry %d must be an object" % i)
			continue
		var entry: Dictionary = entries[i]
		var node := str(entry.get("node", ""))
		if node not in ids:
			problems.append(prefix + "entry %d points at a missing node: %s" % [i, node])
		problems.append_array(_validate_conditions(prefix, entry.get("when", [])))
		if i == entries.size() - 1 and entry.has("when"):
			problems.append(prefix + "the last entry must be the unconditional fallback")
	var reachable := _reachable(entries, objects)
	for node in objects:
		if str(node.get("id", "")) not in reachable:
			problems.append(prefix + "unreachable node: " + str(node.get("id", "")))
	problems.append_array(_validate_exits(prefix, objects))
	return problems


static func _validate_node(prefix: String, node: Dictionary, ids: Array[String]) -> Array[String]:
	var problems: Array[String] = []
	var node_id := str(node.get("id", ""))
	var here := prefix + node_id + ": "
	for key in node.keys():
		if key not in NODE_KEYS:
			problems.append(here + "unknown field: " + str(key))
	if str(node.get("text", "")).is_empty():
		problems.append(here + "needs text")
	for token in _unknown_tokens(str(node.get("text", ""))):
		problems.append(here + "unknown text token: " + token)
	var next := str(node.get("next", ""))
	if not next.is_empty() and next not in ids:
		problems.append(here + "next points at a missing node: " + next)
	var commit := str(node.get("commit", ""))
	if not commit.is_empty() and not next.is_empty():
		problems.append(here + "a commit node cannot also have next")
	problems.append_array(_validate_effects(here, node.get("effects", []), not commit.is_empty()))
	var raw_choices = node.get("choices", [])
	if not (raw_choices is Array):
		problems.append(here + "choices must be a list")
		return problems
	var choices: Array = raw_choices
	if node.has("choices") and choices.is_empty():
		problems.append(here + "choices must not be empty")
	for i in range(choices.size()):
		if typeof(choices[i]) != TYPE_DICTIONARY:
			problems.append(here + "choice %d must be an object" % i)
			continue
		var choice: Dictionary = choices[i]
		var where := here + "choice %d: " % i
		for key in choice.keys():
			if key not in CHOICE_KEYS:
				problems.append(where + "unknown field: " + str(key))
		if str(choice.get("label", "")).is_empty():
			problems.append(where + "needs a label")
		for token in _unknown_tokens(str(choice.get("label", ""))):
			problems.append(where + "unknown text token: " + token)
		var target := str(choice.get("next", ""))
		if not target.is_empty() and target not in ids:
			problems.append(where + "points at a missing node: " + target)
		problems.append_array(_validate_effects(where, choice.get("effects", []), false))
	return problems


static func _validate_effects(where: String, raw_effects, transactional: bool) -> Array[String]:
	var problems: Array[String] = []
	if raw_effects != null and not (raw_effects is Array):
		problems.append(where + "effects must be a list")
		return problems
	var effects: Array = raw_effects if raw_effects is Array else []
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			problems.append(where + "effects must be objects")
			continue
		var kind := str(effect.get("kind", ""))
		if kind not in EFFECT_KINDS:
			problems.append(where + "unknown effect: " + kind)
			continue
		if kind == "order":
			if not transactional:
				problems.append(where + "order effects may only live on a commit node")
			elif str(effect.get("do", "")) not in COMMANDS:
				problems.append(where + "unknown order command: " + str(effect.get("do", "")))
		elif kind == "flag" and str(effect.get("id", "")).is_empty():
			problems.append(where + "flag effects need an id")
		elif kind == "toast" and str(effect.get("text", "")).is_empty():
			problems.append(where + "toast effects need text")
	return problems


static func _validate_conditions(where_path: String, raw_conditions) -> Array[String]:
	var problems: Array[String] = []
	if raw_conditions != null and not (raw_conditions is Array):
		problems.append(where_path + "conditions must be a list")
		return problems
	var conditions: Array = raw_conditions if raw_conditions is Array else []
	for condition in conditions:
		if typeof(condition) != TYPE_DICTIONARY:
			problems.append(where_path + "conditions must be objects")
			continue
		var kind := str(condition.get("kind", ""))
		if kind not in CONDITION_KINDS:
			problems.append(where_path + "unknown condition: " + kind)
			continue
		match kind:
			"flag":
				if str(condition.get("id", "")).is_empty():
					problems.append(where_path + "flag conditions need an id")
			"lifecycle":
				if str(condition.get("is", "")) not in ["idle", "at_shop", "on_route", "closed"]:
					problems.append(where_path + "unknown lifecycle: " + str(condition.get("is", "")))
			"mode":
				if str(condition.get("is", "")) not in ["shift", "roam"]:
					problems.append(where_path + "mode must be shift or roam")
			_:
				if str(condition.get("op", "eq")) not in ["eq", "ne", "gt", "gte", "lt", "lte"]:
					problems.append(where_path + "unknown comparison: " + str(condition.get("op", "")))
				if not (condition.get("value") is float or condition.get("value") is int):
					problems.append(where_path + "numeric conditions need a value")
	return problems


static func _reachable(entries: Array, nodes: Array) -> Array[String]:
	var table: Dictionary = {}
	for node in nodes:
		table[str(node.get("id", ""))] = node
	var seen: Array[String] = []
	var queue: Array[String] = []
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var start := str(entry.get("node", ""))
		if table.has(start) and start not in queue:
			queue.append(start)
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current in seen:
			continue
		seen.append(current)
		var node: Dictionary = table[current]
		var next := str(node.get("next", ""))
		if table.has(next) and next not in seen:
			queue.append(next)
		for choice in _choice_list(node):
			if typeof(choice) != TYPE_DICTIONARY:
				continue
			var target := str(choice.get("next", ""))
			if table.has(target) and target not in seen:
				queue.append(target)
	return seen


## Every reachable node must be able to reach a commit or an authored exit;
## a choice maze with no way out is the "no valid exit" error.
static func _validate_exits(prefix: String, nodes: Array) -> Array[String]:
	var table: Dictionary = {}
	for node in nodes:
		table[str(node.get("id", ""))] = node
	var exits: Dictionary = {}
	for id in table.keys():
		var node: Dictionary = table[id]
		var ends := not str(node.get("commit", "")).is_empty()
		if not ends and str(node.get("next", "")).is_empty() and _choice_list(node).is_empty():
			ends = true
		if not ends:
			for choice in _choice_list(node):
				if typeof(choice) == TYPE_DICTIONARY and str(choice.get("next", "")).is_empty():
					ends = true
		exits[id] = ends
	var settled := true
	while settled:
		settled = false
		for id in table.keys():
			if exits[id]:
				continue
			var targets: Array[String] = _targets(table[id], table)
			if not targets.is_empty() and targets.any(func(target: String) -> bool: return bool(exits[target])):
				exits[id] = true
				settled = true
	var problems: Array[String] = []
	for id in table.keys():
		if not exits[id]:
			problems.append(prefix + "no valid exit from node: " + str(id))
	return problems


static func _targets(node: Dictionary, table: Dictionary) -> Array[String]:
	var targets: Array[String] = []
	var next := str(node.get("next", ""))
	if table.has(next):
		targets.append(next)
	for choice in _choice_list(node):
		if typeof(choice) != TYPE_DICTIONARY:
			continue
		var target := str(choice.get("next", ""))
		if table.has(target):
			targets.append(target)
	return targets


static func _unknown_tokens(text: String) -> Array[String]:
	var found: Array[String] = []
	var cursor := 0
	while true:
		var start := text.find("{{", cursor)
		if start < 0:
			break
		var stop := text.find("}}", start + 2)
		if stop < 0:
			found.append(text.substr(start))
			break
		var token := text.substr(start + 2, stop - start - 2)
		if token not in TOKENS:
			found.append(token)
		cursor = stop + 2
	return found


static func is_valid_color(value: String) -> bool:
	if value.length() != 6:
		return false
	for i in range(value.length()):
		var c := value[i]
		if not (c >= "0" and c <= "9") and not (c >= "a" and c <= "f") and not (c >= "A" and c <= "F"):
			return false
	return true
