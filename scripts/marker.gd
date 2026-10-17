extends Node3D
## World marker for the current objective: pulsing ring, spinning chevron and a
## soft light beam so the target reads from across the island.

var tint := Color("f4bb4d")
var _ring: MeshInstance3D
var _arrow: Node3D
var _beam: MeshInstance3D
var _t := 0.0
var _flash := 0.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.05
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var torus := TorusMesh.new()
	torus.inner_radius = 1.02
	torus.outer_radius = 1.42
	torus.rings = 8
	torus.ring_segments = 10
	torus.material = mat
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position.y = 0.1
	add_child(_ring)

	_arrow = Node3D.new()
	_arrow.position.y = 2.6
	add_child(_arrow)
	for s in [-1.0, 1.0]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.52, 0.16, 0.16)
		bm.material = mat
		bar.mesh = bm
		bar.position = Vector3(0.19 * s, 0.0, 0.0)
		bar.rotation.z = deg_to_rad(-38.0 * s)
		_arrow.add_child(bar)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.16)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.disable_receive_shadows = true
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.42
	cyl.height = 15.0
	cyl.radial_segments = 10
	cyl.material = beam_mat
	_beam = MeshInstance3D.new()
	_beam.mesh = cyl
	_beam.position.y = 7.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func place(pos: Vector3) -> void:
	global_position = pos


func flash() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta * 1.6)
	var pulse := 1.0 + sin(_t * 2.8) * 0.07 + _flash * 0.35
	_ring.scale = Vector3(pulse, 1.0, pulse)
	_ring.rotation.y += delta * 0.7
	var mat := _ring.mesh.material as StandardMaterial3D
	mat.emission_energy_multiplier = 1.05 + _flash * 2.0
	_arrow.position.y = 2.6 + sin(_t * 2.2) * 0.22
	_arrow.rotation.y += delta * 1.5
	_beam.scale = Vector3(1.0, 1.0, 1.0)
