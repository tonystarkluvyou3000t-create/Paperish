extends Node3D
## Phase 06 placeholder people. Each one is a flat-shaded blocky figure standing
## exactly where an interaction anchor expects a person to be, so conversations
## can be authored and tested before the NPC pass.
##
## They carry no collision on purpose: a bystander must never block the van's
## parking pad, a doorway or the player's route, and the interaction line-of-sight
## query only looks at WORLD geometry. Phase 12 replaces these with real
## characters, animation and collision.

@export var shirt := Color("326b69")
@export var trousers := Color("283f49")
@export var skin := Color("e8bb60")
@export var hair := Color("c84436")
## Tiny idle bob so a still figure does not read as a statue. Off for fixtures.
@export var breathing := true

const BOB_HEIGHT := 0.02
const BOB_RATE := 1.3

var body: Node3D
var _materials: Dictionary = {}
var _clock := 0.0


func _ready() -> void:
	build()
	set_process(breathing)


func build() -> void:
	if body != null:
		return
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_box("Legs", Vector3(0, 0.42, 0), Vector3(0.40, 0.84, 0.30), trousers)
	_box("Torso", Vector3(0, 1.16, 0), Vector3(0.58, 0.62, 0.34), shirt)
	_box("Arm_left", Vector3(-0.39, 1.14, 0), Vector3(0.18, 0.58, 0.24), shirt)
	_box("Arm_right", Vector3(0.39, 1.14, 0), Vector3(0.18, 0.58, 0.24), shirt)
	_box("Hands", Vector3(0, 0.86, 0), Vector3(0.78, 0.14, 0.26), skin)
	_box("Neck", Vector3(0, 1.50, 0), Vector3(0.20, 0.10, 0.20), skin)
	_box("Head", Vector3(0, 1.68, 0), Vector3(0.36, 0.36, 0.34), skin)
	_box("Hair", Vector3(0, 1.89, 0.02), Vector3(0.40, 0.12, 0.38), hair)
	_box("Fringe", Vector3(0, 1.83, -0.16), Vector3(0.34, 0.10, 0.06), hair)


func _process(delta: float) -> void:
	_clock += delta
	if body != null:
		body.position.y = sin(_clock * BOB_RATE) * BOB_HEIGHT


## Standing spot for an actor approaching this person: in front, on the ground.
func approach_offset(distance := 0.75) -> Vector3:
	return Vector3(0, 0, -distance)


## Brief arm cue when Mona passes the ready ticket across the counter.
func play_handoff() -> void:
	var arm := body.get_node_or_null("Arm_right") as Node3D if body != null else null
	if arm == null:
		return
	var rest := arm.rotation
	var tween := create_tween()
	tween.tween_property(arm, "rotation", rest + Vector3(-0.62, 0, 0), 0.14)
	tween.tween_property(arm, "rotation", rest, 0.22)


func _box(part_name: String, where: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	var item := MeshInstance3D.new()
	item.name = part_name
	item.mesh = shape
	item.material_override = _material(color)
	item.position = where
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(item)
	return item


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(false)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	material.metallic = 0.0
	_materials[key] = material
	return material
