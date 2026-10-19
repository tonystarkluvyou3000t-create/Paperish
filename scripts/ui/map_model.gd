extends RefCounted
## Phase 11 Milestone B: the town map's static layers, derived from the same
## authored catalog (`data/world/world_layout.json`) that generates the world.
## The minimap and the full map both draw this model, so there is no hand-drawn
## image that can drift from the town the player drives through.

## Builds a draw-ready model. Every record keeps the authored ID so checks and
## tooltips can name what the player sees.
static func build(layout: Dictionary) -> Dictionary:
	var bounds: Dictionary = layout.get("bounds", {})
	var min_x := float(bounds.get("min_x", -160.0))
	var min_z := float(bounds.get("min_z", -120.0))
	var model := {
		"bounds": Rect2(min_x, min_z, float(bounds.get("max_x", 160.0)) - min_x,
			float(bounds.get("max_z", 120.0)) - min_z),
		"roads": [], "water": [], "buildings": [], "districts": [],
		"pois": [], "addresses": [], "recovery": [], "shop": Vector2.ZERO,
	}
	for row in layout.get("road_graph", {}).get("segments", []):
		var a: Array = row.get("a", [0.0, 0.0])
		var b: Array = row.get("b", [0.0, 0.0])
		model.roads.append({"from": Vector2(float(a[0]), float(a[1])),
			"to": Vector2(float(b[0]), float(b[1])),
			"width_m": float(row.get("width_m", 6.4)),
			"street": str(row.get("street_name", "")),
			"speed_class": str(row.get("speed_class", "local")),
			"district_id": str(row.get("district_id", ""))})
	for row in layout.get("water_surfaces", []):
		var rect: Array = row.get("rect", [0.0, 0.0, 0.0, 0.0])
		model.water.append({"kind": str(row.get("kind", "water")),
			"rect": Rect2(float(rect[0]), float(rect[2]),
				float(rect[1]) - float(rect[0]), float(rect[3]) - float(rect[2]))})
	for row in layout.get("addresses", []):
		var position: Array = row.get("position", [0.0, 0.0])
		var size: Array = row.get("footprint_m", [6.0, 6.0])
		# The authored position is the door-side face; the footprint hangs behind it.
		var front := 1.0 if bool(row.get("north", true)) else -1.0
		var cx := float(position[0])
		var cz := float(position[1]) - front * float(size[1]) / 2.0
		var door: Array = row.get("door_position", position)
		var park: Array = row.get("park_position", position)
		var address := str(row.get("address", ""))
		var number := address.split(" ")[0] if not address.is_empty() else ""
		model.buildings.append({"id": str(row.get("id", "")), "address": address,
			"number": number, "district_id": str(row.get("district_id", "")),
			"rect": Rect2(cx - float(size[0]) / 2.0, cz - float(size[1]) / 2.0,
				float(size[0]), float(size[1]))})
		model.addresses.append({"id": str(row.get("id", "")), "address": address,
			"number": number, "district_id": str(row.get("district_id", "")),
			"centre": Vector2(cx, float(position[1])),
			"door": Vector2(float(door[0]), float(door[1])),
			"park": Vector2(float(park[0]), float(park[1]))})
	for row in layout.get("districts", []):
		var district: Array = row.get("bounds", [0.0, 0.0, 0.0, 0.0])
		model.districts.append({"id": str(row.get("id", "")), "name": str(row.get("name", "")),
			"landmark": str(row.get("landmark", "")),
			"rect": Rect2(float(district[0]), float(district[2]),
				float(district[1]) - float(district[0]), float(district[3]) - float(district[2]))})
	for row in layout.get("pois", []):
		var poi: Array = row.get("position", [0.0, 0.0])
		model.pois.append({"id": str(row.get("id", "")), "kind": str(row.get("kind", "")),
			"label": label_for(str(row.get("id", ""))),
			"position": Vector2(float(poi[0]), float(poi[1]))})
	for row in layout.get("recovery_anchors", []):
		var anchor: Array = row.get("position", [0.0, 0.0])
		model.recovery.append({"id": str(row.get("id", "")),
			"position": Vector2(float(anchor[0]), float(anchor[1]))})
	var shop: Array = layout.get("routing", {}).get("shop_start_position", [0.0, 8.28])
	model.shop = Vector2(float(shop[0]), float(shop[1]))
	return model


## "poi:pizza_plaza" -> "PIZZA PLAZA", "recovery:downtown" -> "DOWNTOWN".
static func label_for(id: String) -> String:
	return id.split(":")[-1].replace("_", " ").to_upper()


## The tiered address lookup the map screen uses for its list and search.
static func addresses_in(model: Dictionary, district_id: String) -> Array:
	var rows: Array = []
	for row in model.get("addresses", []):
		if district_id.is_empty() or str(row.district_id) == district_id:
			rows.append(row)
	return rows


static func address_by_id(model: Dictionary, address: String) -> Dictionary:
	for row in model.get("addresses", []):
		if str(row.address) == address:
			return row
	return {}


static func district_name(model: Dictionary, district_id: String) -> String:
	for row in model.get("districts", []):
		if str(row.id) == district_id:
			return str(row.name)
	return district_id.to_upper()
