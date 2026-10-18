extends RefCounted
## Explicit isolated fixture hooks. Never imported by normal gameplay scripts.
static func money(game: Node, value: int) -> void:
	game.orders.money = value
static func timer(game: Node, value: float) -> void:
	game.orders.remaining = value
static func last_house(game: Node, index: int) -> void:
	game.orders.last_destination = str(game.houses[index].get_meta("address"))
static func expire(game: Node) -> void:
	timer(game, 0)
	game._on_timeout()

static func paused(game: Node, value: bool) -> void:
	if value: game.open_modal(&"fixture")
	else: game.close_modal(&"fixture")
static func driving(game: Node, value: bool) -> void:
	game.actors.mode = game.actors.Mode.DRIVING if value else game.actors.Mode.FOOT

static func retry_delivery(game: Node) -> void:
	game._deliver()
static func finish(game: Node, win: bool) -> void:
	game._finish(win)
## Drives the open conversation to its end the way a player would: reveal, then
## advance, and pick the authored option when choices are offered. Used by the
## phase checks and the scenario runner, never by gameplay code.
static func finish_talk(game: Node, pick := 0, limit := 48) -> void:
	var guard := 0
	while game.dialogue.active() and guard < limit:
		guard += 1
		if game.dialogue.revealing() or game.dialogue.choices().is_empty():
			game.dialogue.advance()
		else:
			game.dialogue.choose(pick)
		await game.get_tree().process_frame
static func cleanup(game: Node) -> void:
	game.session.clear_modals()
	if game.world_ready: game.actors.cancel_motion()
static func place(game: Node, actor_name: String, pos: Vector3, yaw: float = NAN) -> void:
	var actor: CharacterBody3D = game.pip if actor_name == "pip" else game.van
	actor.global_position = pos
	actor.velocity = Vector3.ZERO
	actor.autopilot = Vector3.INF
	if actor_name == "van": game.van.speed = 0
	if not is_nan(yaw): actor.rotation.y = deg_to_rad(yaw)
static func autopilot(game: Node, actor_name: String, pos: Vector3) -> void:
	game.pip.autopilot = pos if actor_name == "pip" else Vector3.INF
	game.van.autopilot = pos if actor_name == "van" else Vector3.INF
