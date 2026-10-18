extends SceneTree
## Phase 06 dialogue data validation. The shipped conversations must validate, and
## the validator must catch every class of authoring mistake the schema can make -
## including malformed JSON shapes, which must be reported instead of crashing.
## godot --headless --audio-driver Dummy --path . --script res://tools/check_dialogue.gd

const Dialogue = preload("res://scripts/services/dialogue_service.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


## Asserts that a validation result names a particular problem.
func reports(problems: Array[String], needle: String, label: String) -> void:
	check(problems.any(func(problem: String) -> bool: return problem.contains(needle)),
		label + " -> " + JSON.stringify(problems))


## Smallest conversation that validates cleanly; each case mutates a fresh copy.
func sample() -> Dictionary:
	return {
		"id": "probe", "speaker": {"name": "PROBE", "color": "f4bb4d"}, "cancel": "close",
		"entry": [{"node": "greet"}],
		"nodes": [
			{"id": "greet", "text": "Evening.", "choices": [
				{"label": "GO", "next": "done"}, {"label": "LATER", "next": ""}]},
			{"id": "done", "text": "Done."},
		],
	}


func validate(data: Dictionary) -> Array[String]:
	return Dialogue.validate_conversation(str(data.get("id", "")), data)


func run() -> void:
	# ---- the shipped data must be clean
	var files: Array = Dialogue.FILES
	var raw: Dictionary = {}
	for path in files:
		check(FileAccess.file_exists(path), "shipped dialogue file exists: " + path)
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text)
		check(typeof(parsed) == TYPE_DICTIONARY, "shipped dialogue file is a JSON object: " + path)
		if typeof(parsed) == TYPE_DICTIONARY:
			var id := str(parsed.get("id", ""))
			check(not id.is_empty() and not raw.has(id), "shipped dialogue id is unique: " + id)
			raw[id] = parsed
	check(raw.size() == files.size(), "every shipped file loaded once")
	check(Dialogue.validate_set(raw).is_empty(),
		"shipped conversation set validates: " + JSON.stringify(Dialogue.validate_set(raw)))
	check(str(raw["shopkeeper"].get("cancel", "close")) == "pause",
		"the counter conversation is transactional (esc pauses over it)")
	check(str(raw["customer"].get("cancel", "close")) == "close",
		"the street conversation can be left with nothing lost")
	for id in ["shopkeeper", "customer", "gossip"]:
		var commits := 0
		for node in raw[id].get("nodes", []):
			if not str(node.get("commit", "")).is_empty():
				commits += 1
		check(commits >= 1, "%s has a committed end" % id)
	var wrong_address_commits := 0
	for node in raw["wrong_address"].get("nodes", []):
		if not str(node.get("commit", "")).is_empty():
			wrong_address_commits += 1
	check(wrong_address_commits == 0, "wrong-address dialogue cannot commit a handoff")

	# ---- the validator must catch authoring mistakes
	check(validate(sample()).is_empty(), "the probe conversation itself validates")

	var dup := sample()
	dup["nodes"].append({"id": "done", "text": "again"})
	reports(validate(dup), "duplicate node id", "duplicate node ids are refused")

	var missing := sample()
	missing["nodes"][0]["choices"][0]["next"] = "nowhere"
	reports(validate(missing), "points at a missing node", "dangling choice target is refused")

	var dangling_next := sample()
	dangling_next["nodes"][1]["next"] = "nowhere"
	reports(validate(dangling_next), "points at a missing node", "dangling next is refused")

	var unknown := sample()
	unknown["nodes"][0]["wobble"] = 1
	reports(validate(unknown), "unknown field", "unknown node field is refused")

	var unknown_top := sample()
	unknown_top["wobble"] = 1
	reports(validate(unknown_top), "unknown field", "unknown conversation field is refused")

	var token := sample()
	token["nodes"][0]["text"] = "Evening, {{pies}} here."
	reports(validate(token), "unknown text token", "unknown text token is refused")

	var unreachable := sample()
	unreachable["nodes"].append({"id": "orphan", "text": "nobody says this"})
	reports(validate(unreachable), "unreachable node", "unreachable node is refused")

	var trapped := sample()
	trapped["nodes"][0]["choices"][0]["next"] = "loop_a"
	trapped["nodes"].append({"id": "loop_a", "text": "a", "next": "loop_b"})
	trapped["nodes"].append({"id": "loop_b", "text": "b", "next": "loop_a"})
	reports(validate(trapped), "no valid exit", "a choice maze with no exit is refused")

	var bad_fallback := sample()
	bad_fallback["entry"] = [{"when": [{"kind": "mode", "is": "shift"}], "node": "greet"}]
	reports(validate(bad_fallback), "unconditional fallback", "a conditional last entry is refused")

	var bare_order := sample()
	bare_order["nodes"][0]["effects"] = [{"kind": "order", "do": "pick_up"}]
	reports(validate(bare_order), "order effects may only live on a commit node",
		"a transactional effect outside a commit node is refused")

	var bad_command := sample()
	bad_command["nodes"][1]["commit"] = "done"
	bad_command["nodes"][1]["effects"] = [{"kind": "order", "do": "teleport"}]
	reports(validate(bad_command), "unknown order command", "an unknown order command is refused")

	var empty_choices := sample()
	empty_choices["nodes"][0]["choices"] = []
	reports(validate(empty_choices), "choices must not be empty", "empty choice lists are refused")

	var bad_colour := sample()
	bad_colour["speaker"]["color"] = "zzz"
	reports(validate(bad_colour), "six hex digits", "a malformed speaker colour is refused")

	var bad_cancel := sample()
	bad_cancel["cancel"] = "sometimes"
	reports(validate(bad_cancel), "cancel must be close or pause", "an unknown cancel policy is refused")

	var both_ends := sample()
	both_ends["nodes"][1]["commit"] = "done"
	both_ends["nodes"][1]["next"] = "greet"
	reports(validate(both_ends), "cannot also have next", "a commit node with next is refused")

	var bad_condition := sample()
	bad_condition["entry"] = [{"when": [{"kind": "mood", "is": "grumpy"}], "node": "greet"},
		{"node": "greet"}]
	reports(validate(bad_condition), "unknown condition", "an unknown condition kind is refused")

	var numeric := sample()
	numeric["entry"] = [{"when": [{"kind": "cargo", "op": "over", "value": 1}], "node": "greet"},
		{"node": "greet"}]
	reports(validate(numeric), "unknown comparison", "an unknown comparison is refused")

	var no_value := sample()
	no_value["entry"] = [{"when": [{"kind": "cargo", "op": "gt"}], "node": "greet"},
		{"node": "greet"}]
	reports(validate(no_value), "need a value", "a numeric condition without a value is refused")

	# ---- malformed shapes must be reported, never crash
	var shapeless := {"id": "probe", "speaker": "nobody", "entry": "greet", "nodes": "nope"}
	var shapeless_problems := validate(shapeless)
	reports(shapeless_problems, "speaker must be an object", "a string speaker is reported")

	var dict_nodes := sample()
	dict_nodes["nodes"] = {"greet": 1}
	reports(validate(dict_nodes), "nodes must be a list", "a dictionary node list is reported")

	var dict_choices := sample()
	dict_choices["nodes"][0]["choices"] = {"label": "GO"}
	reports(validate(dict_choices), "choices must be a list", "a dictionary choice list is reported")

	var dict_effects := sample()
	dict_effects["nodes"][0]["effects"] = {"kind": "flag"}
	reports(validate(dict_effects), "effects must be a list", "a dictionary effect list is reported")

	var dict_when := sample()
	dict_when["entry"] = [{"when": {"kind": "mode"}, "node": "greet"}, {"node": "greet"}]
	reports(validate(dict_when), "conditions must be a list", "a dictionary condition list is reported")

	var string_entry := sample()
	string_entry["entry"] = ["greet"]
	reports(validate(string_entry), "must be an object", "a string entry is reported")

	var string_choice := sample()
	string_choice["nodes"][0]["choices"] = ["GO"]
	reports(validate(string_choice), "must be an object", "a string choice is reported")

	var empty_effects := sample()
	empty_effects["nodes"][0]["effects"] = [{"kind": "flag"}, {"kind": "toast", "text": ""}]
	var effect_problems := validate(empty_effects)
	reports(effect_problems, "flag effects need an id", "a flag effect without an id is refused")
	reports(effect_problems, "toast effects need text", "a toast effect without text is refused")

	var empty_speaker := sample()
	empty_speaker["speaker"] = {}
	reports(validate(empty_speaker), "speaker needs a name", "a speaker without a name is refused")

	var no_nodes := sample()
	no_nodes["nodes"] = []
	no_nodes["entry"] = []
	reports(validate(no_nodes), "needs at least one node", "a conversation without nodes is refused")

	print("DIALOGUE %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
