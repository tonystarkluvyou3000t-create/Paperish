extends Node
## Local sound adapter; it cannot award money or change session/order state.
var sounds := {}
var _pool: Array[AudioStreamPlayer] = []
var _horn: AudioStreamPlayer3D

func configure(van: CharacterBody3D) -> void:
	for name in ["ui", "order", "pickup", "deliver", "cash", "fail", "step", "horn", "door", "shift_end"]:
		var path := "res://assets/audio/%s.wav" % name
		if ResourceLoader.exists(path): sounds[name] = load(path)
	for i in range(4):
		var player := AudioStreamPlayer.new()
		add_child(player)
		_pool.append(player)
	_horn = AudioStreamPlayer3D.new()
	_horn.stream = sounds.get("horn")
	_horn.unit_size = 8
	_horn.max_distance = 40
	van.add_child(_horn)

func play(name: String, vol := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	for p in _pool:
		if not p.playing:
			p.stream = sounds[name]
			p.volume_db = vol
			p.pitch_scale = pitch
			p.play()
			return
	_pool[0].stream = sounds[name]
	_pool[0].volume_db = vol
	_pool[0].pitch_scale = pitch
	_pool[0].play()


func footstep() -> void:
	play("step", -9.0, randf_range(0.9, 1.1))


func honk() -> void:
	if _horn.stream:
		_horn.play()
