extends Node
## Only this input owner and the menus run while paused; Game/world stay pausable.
## Esc is one back stack: menu screens close before the free camera exits, before
## pause toggles, before results return to title. The R shortcut still resets
## immediately (the pause menu offers the confirmed restart), and gameplay
## `interact` never fires while paused - except into an open conversation, where
## the same key drives the line the player just opened.
var game: Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("pause"):
		if game.handle_back():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and (game.paused or not game.is_shift_active()):
		game.restart()
		get_viewport().set_input_as_handled()
	elif game.paused and not game.talking() and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_echo() and event.is_action_pressed("interact"):
		if game.interact_available():
			game.interact()
			get_viewport().set_input_as_handled()
