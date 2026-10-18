extends Node
## Flow is independent of order lifecycle and seated/on-foot mode.
## `mode` distinguishes a timed shift ("shift") from clock-free roam ("roam").
signal changed(event: Dictionary)
enum Flow { TITLE, PLAYING, RESULT }
var flow := Flow.TITLE
var mode := "shift"
var generation := 0
var outcome := ""
var _reasons: Dictionary = {}
var paused: bool:
	get: return not _reasons.is_empty()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func reset() -> void:
	generation += 1
	flow = Flow.TITLE
	mode = "shift"
	outcome = ""
	_reasons.clear()
	_publish()

func start(mode_name := "shift") -> bool:
	if flow != Flow.TITLE: return false
	flow = Flow.PLAYING
	mode = mode_name
	_publish()
	return true


## True while the clock-free exploration mode is active.
func roaming() -> bool:
	return flow == Flow.PLAYING and mode == "roam"

func finish(win: bool) -> bool:
	if flow != Flow.PLAYING or paused: return false
	flow = Flow.RESULT
	outcome = "won" if win else "lost"
	_reasons.clear()
	_publish()
	return true

func open_modal(reason: StringName) -> bool:
	if flow != Flow.PLAYING or reason.is_empty() or _reasons.has(reason): return false
	_reasons[reason] = true
	_publish()
	return true

func close_modal(reason: StringName) -> bool:
	if not _reasons.has(reason): return false
	_reasons.erase(reason)
	_publish()
	return true

func toggle_pause() -> void:
	if _reasons.has(&"user_pause"): close_modal(&"user_pause")
	else: open_modal(&"user_pause")

func clear_modals() -> void:
	_reasons.clear()
	_publish()

func invalidate_world() -> void:
	flow = Flow.RESULT
	outcome = "lost"
	_reasons.clear()
	_publish()

func reasons() -> Array:
	return _reasons.keys()

func _publish() -> void:
	get_tree().paused = paused
	var event := {"flow": flow, "mode": mode, "generation": generation, "paused": paused, "outcome": outcome}
	event.make_read_only()
	changed.emit(event)

func _exit_tree() -> void:
	# Scene replacement must never leave the next scene inheriting a paused tree.
	if get_tree(): get_tree().paused = false
