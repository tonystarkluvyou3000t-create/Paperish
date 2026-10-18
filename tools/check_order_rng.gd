extends SceneTree
## Logical RNG isolation, not cross-platform physics determinism.
func _initialize() -> void:
	call_deferred("run")

func sample(game: Node, noise: bool) -> Array:
	game.restart()
	game._start_shift()
	var result := []
	for i in range(12):
		if noise:
			for j in range(37): randf()
		game._new_order()
		var d: Dictionary = game.get_diagnostics()
		result.append([d.order_id, d.destination_id, d.order_pizzas])
		await physics_frame
		await process_frame
	return result

func run() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_order_seed(20261018)
	var first: Array = await sample(game, false)
	var noisy: Array = await sample(game, true)
	var ok := first == noisy
	if not ok: printerr("RNG FAIL: unrelated global RNG changed order sequence")
	else: print("RNG PASS seed=20261018 sequence=", JSON.stringify(first))
	game.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	quit(0 if ok else 1)
