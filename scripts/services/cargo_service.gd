extends Node
## Owns the location of every physical pizza package. Orders own deadlines and
## settlement; this service owns package identity, slot assignment and visuals.
signal changed(event: Dictionary)

const COUNTER := "counter"
const PIP := "pip"
const VAN := "van"
const CUSTOMER := "customer"
const DISCARDED := "discarded"
const DELIVERABLE := [COUNTER, PIP, VAN]

var packages: Dictionary = {} # package_id -> immutable-by-convention record
var bundles: Dictionary = {}  # order_id -> Array[String] package IDs
var van_capacity := 6
var player_capacity := 3
var van: Node3D
var selected_van_order := 0
var _visual_root: Node3D
var _box_mesh := BoxMesh.new()
var _lid_mesh := BoxMesh.new()
var _box_material := StandardMaterial3D.new()
var _lid_material := StandardMaterial3D.new()

var cargo_count: int:
	get: return count_at(PIP)


func configure(vehicle: Node3D, slots := 6, carry_limit := 3) -> void:
	van = vehicle
	van_capacity = maxi(slots, 1)
	player_capacity = maxi(carry_limit, 1)
	_build_visuals()


func reset() -> void:
	packages.clear()
	bundles.clear()
	selected_van_order = 0
	_refresh_visuals()
	changed.emit(_change_event("reset", 0))


func create_order(generation: int, order_id: int, destination_id: String, quantity: int) -> bool:
	if generation < 1 or order_id < 1 or destination_id.is_empty() or quantity < 1:
		return false
	if bundles.has(order_id):
		return false
	var ids: Array[String] = []
	for index in range(quantity):
		var package_id := "g%03d-o%03d-p%02d" % [generation, order_id, index + 1]
		if packages.has(package_id):
			return false
		ids.append(package_id)
	for package_id in ids:
		packages[package_id] = {
			"package_id": package_id, "generation": generation, "order_id": order_id,
			"destination_id": destination_id, "quality": 1.0,
			"location": COUNTER, "slot": -1,
		}
	bundles[order_id] = ids
	changed.emit(_change_event("created", order_id))
	return true


func has_order(order_id: int) -> bool:
	return bundles.has(order_id)


func package_ids(order_id: int) -> Array[String]:
	return (bundles.get(order_id, []) as Array).duplicate()


func count_for_order(order_id: int, locations: Array = DELIVERABLE) -> int:
	var count := 0
	for package_id in package_ids(order_id):
		var record: Dictionary = packages.get(package_id, {})
		if str(record.get("location", "")) in locations:
			count += 1
	return count


func location_for_order(order_id: int) -> String:
	var found := ""
	for package_id in package_ids(order_id):
		var location := str(packages.get(package_id, {}).get("location", ""))
		if location == DISCARDED or location == CUSTOMER:
			return location
		if found.is_empty():
			found = location
		elif location != found:
			return "split"
	return found


## Move a whole order bundle as a single transaction. Capacity and expected
## ownership are checked before any package or van slot changes.
func transfer_order(order_id: int, expected_location: String, next_location: String) -> bool:
	if not bundles.has(order_id) or next_location not in [PIP, VAN, CUSTOMER, DISCARDED]:
		return false
	var ids := package_ids(order_id)
	if ids.is_empty():
		return false
	for package_id in ids:
		if str(packages.get(package_id, {}).get("location", "")) != expected_location:
			return false
	var slots: Array[int] = []
	if next_location == VAN:
		var occupied := _occupied_slots()
		if ids.size() > van_capacity - occupied.size():
			return false
		for slot in range(van_capacity):
			if slot not in occupied:
				slots.append(slot)
				if slots.size() == ids.size():
					break
	if next_location == PIP and ids.size() > player_capacity:
		return false
	for index in range(ids.size()):
		var package_id := ids[index]
		var record: Dictionary = packages[package_id].duplicate()
		record["location"] = next_location
		record["slot"] = slots[index] if next_location == VAN else -1
		packages[package_id] = record
	if next_location == VAN:
		selected_van_order = order_id
	elif selected_van_order == order_id:
		selected_van_order = _first_van_order()
	_refresh_visuals()
	changed.emit(_change_event("moved", order_id))
	return true


## Settlement quality is captured at the customer; discarded boxes can never
## be transferred back into a deliverable location.
func settle_order(order_id: int, quality: float) -> bool:
	if location_for_order(order_id) != PIP or count_for_order(order_id, [PIP]) != package_ids(order_id).size():
		return false
	for package_id in package_ids(order_id):
		var record: Dictionary = packages[package_id].duplicate()
		record["location"] = CUSTOMER
		record["quality"] = clampf(quality, 0.0, 1.0)
		packages[package_id] = record
	_refresh_visuals()
	changed.emit(_change_event("delivered", order_id))
	return true


func discard_order(order_id: int) -> bool:
	if not bundles.has(order_id):
		return false
	var location := location_for_order(order_id)
	if location in ["", CUSTOMER, DISCARDED]:
		return false
	for package_id in package_ids(order_id):
		var record: Dictionary = packages[package_id].duplicate()
		record["location"] = DISCARDED
		record["slot"] = -1
		packages[package_id] = record
	if selected_van_order == order_id:
		selected_van_order = _first_van_order()
	_refresh_visuals()
	changed.emit(_change_event("discarded", order_id))
	return true


func select_next_van_order() -> int:
	var ids := van_order_ids()
	if ids.is_empty():
		selected_van_order = 0
		return 0
	var index := ids.find(selected_van_order)
	selected_van_order = ids[(index + 1) % ids.size()]
	changed.emit(_change_event("selection", selected_van_order))
	return selected_van_order


func van_order_ids() -> Array[int]:
	var found: Array[int] = []
	for order_variant in bundles.keys():
		var order_id := int(order_variant)
		if location_for_order(order_id) == VAN:
			found.append(order_id)
	found.sort()
	return found


func count_at(location: String) -> int:
	var count := 0
	for record_variant in packages.values():
		if str(record_variant.get("location", "")) == location:
			count += 1
	return count


func inventory_lines() -> String:
	var rows: Array[String] = ["VAN %d/%d BOX SLOTS" % [count_at(VAN), van_capacity]]
	var ids: Array = bundles.keys()
	ids.sort()
	for order_variant in ids:
		var order_id := int(order_variant)
		var location := location_for_order(order_id)
		if location in [CUSTOMER, DISCARDED, ""]:
			continue
		var count := count_for_order(order_id, DELIVERABLE)
		rows.append("#%02d  %d BOX%s  ·  %s" % [order_id, count, "" if count == 1 else "ES", location.to_upper()])
	if rows.size() == 1:
		rows.append("NO BOXES IN TRANSIT")
	return "\n".join(rows)


func invariant_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for order_variant in bundles.keys():
		var order_id := int(order_variant)
		var ids := package_ids(order_id)
		if ids.is_empty():
			errors.append("order %d has no package records" % order_id)
		var location := ""
		for package_id in ids:
			if seen.has(package_id):
				errors.append("package appears in more than one bundle: " + package_id)
			seen[package_id] = true
			if not packages.has(package_id):
				errors.append("missing package record: " + package_id)
				continue
			var record: Dictionary = packages[package_id]
			var here := str(record.get("location", ""))
			if here not in [COUNTER, PIP, VAN, CUSTOMER, DISCARDED]:
				errors.append("invalid package location: " + package_id)
			if not location.is_empty() and here != location:
				errors.append("order %d package locations are split" % order_id)
			location = here
			if here == VAN and (int(record.get("slot", -1)) < 0 or int(record.get("slot", -1)) >= van_capacity):
				errors.append("van package has an invalid slot: " + package_id)
	if seen.size() != packages.size():
		errors.append("unbundled package records exist")
	var occupied := _occupied_slots()
	if occupied.size() != _van_package_count():
		errors.append("van slot assignment is duplicated")
	return errors


func _build_visuals() -> void:
	if not is_instance_valid(van):
		return
	_visual_root = Node3D.new()
	_visual_root.name = "CargoSlots"
	van.add_child(_visual_root)
	_box_mesh.size = Vector3(0.56, 0.15, 0.52)
	_lid_mesh.size = Vector3(0.58, 0.035, 0.54)
	_box_material.albedo_color = Color("f8e5bc")
	_box_material.roughness = 0.9
	_lid_material.albedo_color = Color("fff3d7")
	_lid_material.roughness = 0.9
	_refresh_visuals()


func _refresh_visuals() -> void:
	if not is_instance_valid(_visual_root):
		return
	for child in _visual_root.get_children():
		child.queue_free()
	var slots: Array[Dictionary] = []
	var by_slot: Dictionary = {}
	for record_variant in packages.values():
		var record: Dictionary = record_variant
		if str(record.get("location", "")) == VAN:
			slots.append(record)
			by_slot[int(record.slot)] = record
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	# Six recessed indicators make free/occupied cargo slots easy to count from
	# the rear without adding hover text to empty space around the van.
	for slot in range(van_capacity):
		var indicator := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.10, 0.045)
		indicator.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("f4bb4d") if by_slot.has(slot) else Color("68b7a0")
		material.roughness = 0.55
		material.metallic = 0.15
		indicator.material_override = material
		var row := slot / 2
		var column := slot % 2
		indicator.position = Vector3(-0.48 + 0.96 * column, 2.25 - 0.19 * row, -1.97)
		_visual_root.add_child(indicator)
	var label_by_order: Dictionary = {}
	for slot in range(van_capacity):
		var row := slot / 2
		var column := slot % 2
		if not by_slot.has(slot):
			continue
		var holder := Node3D.new()
		holder.name = "Slot_%02d" % slot
		# The stack is staged just outside the rear hatch while the van is parked;
		# E can then move the same bundle back to Pip with a single action.
		# Keep cartons fully behind the opaque hatch plane. The flat tray gives
		# them a clear silhouette from the rear while keeping the door readable.
		holder.position = Vector3(-0.34 + 0.68 * column, 0.92 + 0.18 * row, -2.45 - 0.58 * row)
		_visual_root.add_child(holder)
		if column == 0:
			var tray := MeshInstance3D.new()
			var tray_mesh := BoxMesh.new()
			tray_mesh.size = Vector3(1.52, 0.10, 0.66)
			tray.mesh = tray_mesh
			var tray_material := StandardMaterial3D.new()
			tray_material.albedo_color = Color("326b69")
			tray.material_override = tray_material
			tray.position = Vector3(0, 0.80 + 0.18 * row, -2.45 - 0.58 * row)
			_visual_root.add_child(tray)
		var record: Dictionary = by_slot[slot]
		var body := MeshInstance3D.new()
		body.mesh = _box_mesh
		body.material_override = _box_material
		holder.add_child(body)
		var lid := MeshInstance3D.new()
		lid.mesh = _lid_mesh
		lid.material_override = _lid_material
		lid.position.y = 0.09
		holder.add_child(lid)
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(0.43, 0.025, 0.015)
		var stripe := MeshInstance3D.new()
		stripe.mesh = stripe_mesh
		var stripe_material := StandardMaterial3D.new()
		stripe_material.albedo_color = Color("c84436")
		stripe.material_override = stripe_material
		stripe.position = Vector3(0, 0, -0.266)
		holder.add_child(stripe)
		var order_id := int(record.order_id)
		if not label_by_order.has(order_id):
			label_by_order[order_id] = Label3D.new()
			var tag: Label3D = label_by_order[order_id]
			tag.text = "ORDER #%02d" % order_id
			tag.font_size = 32
			tag.pixel_size = 0.0035
			tag.outline_size = 8
			tag.modulate = Color("283f49")
			tag.position = Vector3(0, 0.2, -0.26)
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			holder.add_child(tag)


func _occupied_slots() -> Array[int]:
	var result: Array[int] = []
	for record_variant in packages.values():
		var record: Dictionary = record_variant
		if str(record.get("location", "")) == VAN:
			var slot := int(record.get("slot", -1))
			if slot not in result:
				result.append(slot)
	return result


func _van_package_count() -> int:
	return count_at(VAN)


func _first_van_order() -> int:
	var ids := van_order_ids()
	return ids[0] if not ids.is_empty() else 0


func _change_event(action: String, order_id: int) -> Dictionary:
	var event := {"action": action, "order_id": order_id, "cargo_count": cargo_count,
		"van_count": count_at(VAN), "counter_count": count_at(COUNTER)}
	event.make_read_only()
	return event
