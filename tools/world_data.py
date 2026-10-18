"""Authoritative world catalog, road/pedestrian graphs, and layout serializer.

All coordinates are metres in Godot X/Z. Roads, lots, POIs and generated scene
anchors share this source. Vehicle forward is local +Z.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

SCHEMA_VERSION = 2
WORLD_ID = "pip-island"
DECORATION_SEED = 20261019
BOUNDS = {"min_x": -160.0, "max_x": 160.0, "min_z": -120.0, "max_z": 120.0}
GROUND_TOP = 0.07
ROAD_TOP = 0.07
WALK_TOP = 0.08
MARK_TOP = 0.083
RIM_TOP = 0.09
MAIN_Z0, MAIN_Z1 = -3.2, 3.2
MAIN_X0, MAIN_X1 = -31.0, 31.0
BASIL_X0, BASIL_X1 = -16.4, -10.0
OLIVE_X0, OLIVE_X1 = 10.0, 16.4
VROAD_Z = 26.0
SIDEWALK_WIDTH = 1.8
SHOP_Z = 11.0
FRONT_OFF = 8.4
HOUSE_W, HOUSE_D = 7.4, 6.4
ROAD_WIDTH_M = 6.4
ROAD_JUNCTION_XS = ((BASIL_X0 + BASIL_X1) / 2.0, (OLIVE_X0 + OLIVE_X1) / 2.0)
CROSSING_SPANS = ((BASIL_X0 - SIDEWALK_WIDTH, BASIL_X0), (BASIL_X1, BASIL_X1 + SIDEWALK_WIDTH),
                  (OLIVE_X0 - SIDEWALK_WIDTH, OLIVE_X0), (OLIVE_X1, OLIVE_X1 + SIDEWALK_WIDTH))
CROSSWALK_XS = tuple((a + b) / 2.0 for a, b in CROSSING_SPANS)

DISTRICTS = [
    {"id": "downtown", "name": "Downtown", "bounds": [-45, 45, -38, 38], "landmark": "Pizza Plaza"},
    {"id": "residential", "name": "Cedar Grove", "bounds": [-150, -50, -100, -30], "landmark": "Cedar Green"},
    {"id": "waterfront", "name": "Harborfront", "bounds": [50, 155, -45, 72], "landmark": "East Pier"},
    {"id": "hillside", "name": "Summit Hill", "bounds": [-58, 58, -116, -40], "landmark": "Summit Overlook"},
    {"id": "market", "name": "Market Works", "bounds": [-68, 68, 42, 116], "landmark": "Market Square"},
]

# Original eight homes keep their artwork, addresses and order-index mapping.
HOUSE_STYLES = [
    dict(num=2, x=-29.5, north=True, wall='cream', roof='tile', style='gable', trim='red_dark', door='teal', plinth='red_dark', label='the cream cottage', porch=True, garden=False, fence=False, chimney=True),
    dict(num=4, x=-20.9, north=True, wall='mint_light', roof='red_dark', style='hip', trim='red_dark', door='gold', plinth='teal', label='the mint house', porch=False, garden=False, fence=True, chimney=False),
    dict(num=6, x=20.9, north=True, wall='ivory', roof='teal', style='gable', trim='teal', door='red', plinth='mint', label='the blue rooftop', porch=True, garden=False, fence=False, chimney=True),
    dict(num=8, x=29.5, north=True, wall='crust', roof='red_dark', style='gable', trim='red_dark', door='cream', plinth='bark', label='the wooden house', porch=False, garden=False, fence=True, chimney=True),
    dict(num=10, x=-29.5, north=False, wall='paving_light', roof='tile', style='flat', trim='paving', door='red_dark', plinth='paving', label='the sandstone house', porch=False, garden=True, fence=False, chimney=False),
    dict(num=12, x=-20.9, north=False, wall='mint', roof='tile_light', style='gable', trim='red_dark', door='ivory', plinth='teal', label='the green house', porch=True, garden=False, fence=False, chimney=True),
    dict(num=14, x=20.9, north=False, wall='cream', roof='mint', style='hip', trim='mint', door='red', plinth='red_dark', label='the garden house', porch=False, garden=False, fence=True, chimney=False),
    dict(num=16, x=29.5, north=False, wall='ivory', roof='tile', style='gable', trim='red_dark', door='mint', plinth='teal', label='the corner house', porch=True, garden=False, fence=True, chimney=True),
]


def _road(ident: str, street: str, a: tuple[float, float], b: tuple[float, float],
          width: float = ROAD_WIDTH_M, speed: str = "local", district: str = "") -> dict:
    return {"id": ident, "street_name": street, "a": list(a), "b": list(b),
            "width_m": width, "speed_class": speed, "district_id": district}


# The same centerlines feed road mesh generation and the directed lane graph.
ROAD_SEGMENTS = [
    _road("marinara", "Marinara Way", (-145, 0), (145, 0), 6.4, "main", "downtown"),
    _road("basil", "Basil Street", (-13.2, -110), (-13.2, 110), 6.4, "main", "downtown"),
    _road("olive", "Olive Street", (13.2, -110), (13.2, 110), 6.4, "main", "downtown"),
    _road("west-spine", "Cedar Loop", (-80, -100), (-80, 100), 8.0, "main", "residential"),
    _road("east-spine", "Harbor Road", (80, -100), (80, 100), 8.0, "main", "waterfront"),
    _road("outer-west", "Island Loop", (-145, -100), (-145, 100), 8.0, "main"),
    _road("outer-east", "Island Loop", (145, -100), (145, 100), 8.0, "main"),
    _road("north-ring", "North Ring", (-145, -100), (145, -100), 8.0, "main"),
    _road("west-cross", "Cedar Grove Road", (-145, -70), (145, -70), 8.0, "main"),
    _road("south-cross", "Market Road", (-145, 70), (145, 70), 8.0, "main"),
    _road("residential-west", "Cedar Grove Road", (-145, -40), (-55, -40), 6.4, "local", "residential"),
    _road("hill-lower", "Summit Drive", (-55, -45), (55, -45), 6.4, "local", "hillside"),
    _road("hill-mid", "Summit Drive", (-55, -85), (55, -85), 6.4, "local", "hillside"),
    _road("hill-upper", "Summit Drive", (-55, -110), (55, -110), 6.4, "local", "hillside"),
    _road("waterfront-south", "Harbor Road", (55, -40), (145, -40), 6.4, "local", "waterfront"),
    _road("waterfront-north", "Harbor Road", (55, 35), (145, 35), 6.4, "local", "waterfront"),
    _road("market-west", "Market Street", (-65, 50), (65, 50), 6.4, "local", "market"),
    _road("market-upper", "Market Street", (-65, 95), (65, 95), 6.4, "local", "market"),
    _road("market-yard", "Workshop Lane", (-65, 112), (65, 112), 6.4, "local", "market"),
]
for x in (-125, -105, -55):
    ROAD_SEGMENTS.append(_road(f"cedar-cross-{abs(x)}", "Cedar Grove Road", (x, -100), (x, 0), 6.4, "local", "residential"))
for x in (-55, -25, 0, 25, 55):
    ROAD_SEGMENTS.append(_road(f"hill-cross-{x:+03d}", "Summit Drive", (x, -110), (x, -45), 6.4, "local", "hillside"))
for x in (55, 105, 125):
    ROAD_SEGMENTS.append(_road(f"harbor-cross-{x}", "Harbor Road", (x, -40), (x, 100), 6.4, "local", "waterfront"))
for x in (-60, -40, 40, 60):
    ROAD_SEGMENTS.append(_road(f"market-cross-{x:+03d}", "Market Street", (x, 50), (x, 112), 6.4, "local", "market"))

RECOVERY_ANCHORS = [
    {"id": "recovery:downtown", "district_id": "downtown", "position": [0.0, 0.0]},
    {"id": "recovery:residential", "district_id": "residential", "position": [-80.0, -70.0]},
    {"id": "recovery:waterfront", "district_id": "waterfront", "position": [80.0, 35.0]},
    {"id": "recovery:hillside", "district_id": "hillside", "position": [13.2, -85.0]},
    {"id": "recovery:market", "district_id": "market", "position": [-13.2, 70.0]},
]


def _record(district: str, number: int, street: str, x: float, road_z: float,
            north: bool, kind: str = "house", label: str = "", lot_front: float = 8.0) -> dict:
    f = 1 if north else -1
    side = -1 if number % 2 == 0 else 1
    address = f"{number} {street}"
    ident = address if district == "downtown" else f"address:{district}:{number:02d}"
    node_name = f"House_{number:02d}" if district == "downtown" else f"Lot_{district.title()}_{number:02d}"
    widths = {"house": 6.4, "clinic": 8.0, "harbor_office": 8.0,
              "summit_lodge": 8.0, "market_stall": 6.0, "workshop": 9.0}
    depths = {"house": 5.4, "clinic": 6.0, "harbor_office": 6.0,
              "summit_lodge": 6.0, "market_stall": 4.8, "workshop": 7.0}
    lot_front = float(lot_front)
    pos = [float(x), float(road_z - f * lot_front)]
    park = [float(x + side * 2.75), float(pos[1] + f * 2.0)]
    door = [float(x), float(pos[1] + f * 1.0)]
    customer = [float(x - side * .95), float(pos[1] + f * 1.95)]
    road_access = [float(x), float(road_z)]
    return {
        "id": ident, "address": address, "label": label or address,
        "number": number, "district_id": district, "kind": kind,
        "lot_id": f"lot:{district}:{number:02d}", "node_name": node_name,
        "street_name": street, "position": pos, "door_position": door,
        "park_position": park, "customer_slot_position": customer,
        "road_access_position": road_access,
        "footprint_m": [widths[kind], depths[kind]], "north": bool(north),
        "road_node_id": "", "road_connector_m": round(math.dist(road_access, park), 3),
        "ped_door_id": f"ped:door:{district}:{number:02d}",
        "ped_park_id": f"ped:park:{district}:{number:02d}",
        "customer_slot_id": f"customer-slot:{district}:{number:02d}",
        "entrance_id": f"entrance:{district}:{number:02d}",
        "parking_id": f"parking:{district}:{number:02d}",
        "park_yaw_deg": 90.0 if side > 0 else -90.0,
        "style": "classic" if district == "downtown" else "district",
    }


def _address_records() -> list[dict]:
    rows: list[dict] = []
    for h in HOUSE_STYLES:
        f = 1 if h["north"] else -1
        row = _record("downtown", h["num"], "Marinara Way", h["x"], 0.0,
                      h["north"], "house", h["label"])
        row["position"] = [h["x"], -f * FRONT_OFF]
        row["door_position"] = [h["x"], -f * FRONT_OFF + f]
        side = -1 if h["num"] % 4 == 2 else 1
        row["park_position"] = [h["x"] + side * 2.75, -f * FRONT_OFF + f * 2.0]
        row["customer_slot_position"] = [h["x"] - side * .95, -f * FRONT_OFF + f * 1.95]
        row["road_access_position"] = [h["x"], 0.0]
        row["road_connector_m"] = round(math.dist(row["road_access_position"], row["park_position"]), 3)
        row["lot_id"] = f"lot:marinara:{h['num']:02d}"
        row["park_yaw_deg"] = 90.0 if side > 0 else -90.0
        rows.append(row)
    # Each outer district has nine reachable doorstep/customer locations.
    for i, x in enumerate([-137, -117, -92, -67]):
        for north in (True, False):
            number = 21 + len([r for r in rows if r["district_id"] == "residential"])
            rows.append(_record("residential", number, "Cedar Grove Road", x, -70.0,
                                north, "house", f"Cedar Grove home {number}"))
    rows.append(_record("residential", 29, "Cedar Grove Road", -92, -40.0,
                        True, "clinic", "Cedar Grove Community Clinic"))
    for i, x in enumerate([68, 92, 117, 137]):
        for north in (True, False):
            number = 31 + len([r for r in rows if r["district_id"] == "waterfront"])
            rows.append(_record("waterfront", number, "Harbor Road", x, 0.0,
                                north, "house", f"Harborfront home {number}"))
    rows.append(_record("waterfront", 39, "Harbor Road", 117, 35.0,
                        True, "harbor_office", "East Harbor Office"))
    for x in [-42, -34, 34, 42]:
        for north in (True, False):
            number = 41 + len([r for r in rows if r["district_id"] == "hillside"])
            rows.append(_record("hillside", number, "Summit Drive", x, -85.0,
                                north, "house", f"Summit Hill home {number}",
                                lot_front=4.0))
    rows.append(_record("hillside", 49, "Summit Drive", 42, -45.0,
                        True, "summit_lodge", "Summit View Lodge"))
    for x in [-50, -25, 0, 25]:
        for north in (True, False):
            number = 51 + len([r for r in rows if r["district_id"] == "market"])
            kind = "market_stall" if (x == 25 and not north) else "house"
            rows.append(_record("market", number, "Market Road", x, 70.0,
                                north, kind, "Market Stall" if kind == "market_stall" else f"Market home {number}"))
    rows.append(_record("market", 59, "Workshop Lane", -50, 112.0,
                        True, "workshop", "Miller's Repair Workshop", lot_front=5.0))
    return rows


def _coord_id(x: float, z: float) -> str:
    return f"road:x{int(round(x * 10)):+05d}:z{int(round(z * 10)):+05d}"


def _road_graph(addresses: list[dict]) -> dict:
    segment_points: list[set[tuple[float, float]]] = []
    for road in ROAD_SEGMENTS:
        segment_points.append({tuple(map(float, road["a"])), tuple(map(float, road["b"]))})
    # Split both centerlines at every perpendicular intersection.
    for i, first in enumerate(ROAD_SEGMENTS):
        ax, az = first["a"]; bx, bz = first["b"]
        for j in range(i + 1, len(ROAD_SEGMENTS)):
            second = ROAD_SEGMENTS[j]
            cx, cz = second["a"]; dx, dz = second["b"]
            first_horizontal, second_horizontal = abs(az - bz) < .01, abs(cz - dz) < .01
            if first_horizontal == second_horizontal: continue
            horizontal, vertical = (first, second) if first_horizontal else (second, first)
            hx, hz = horizontal["a"][0], horizontal["a"][1]
            vx, vz = vertical["a"][0], vertical["a"][1]
            if min(horizontal["a"][0], horizontal["b"][0]) <= vx <= max(horizontal["a"][0], horizontal["b"][0]) and min(vertical["a"][1], vertical["b"][1]) <= hz <= max(vertical["a"][1], vertical["b"][1]):
                point = (float(vx), float(hz))
                segment_points[i].add(point); segment_points[j].add(point)
    for row in addresses:
        x, z = row["road_access_position"]
        candidates = []
        for index, road in enumerate(ROAD_SEGMENTS):
            ax, az = road["a"]; bx, bz = road["b"]
            if abs(az - bz) < .01 and min(ax, bx) - .01 <= x <= max(ax, bx) + .01:
                candidates.append((abs(z - az), index, (float(x), float(az))))
            elif abs(ax - bx) < .01 and min(az, bz) - .01 <= z <= max(az, bz) + .01:
                candidates.append((abs(x - ax), index, (float(ax), float(z))))
        if not candidates:
            row["road_node_id"] = ""
            continue
        distance, index, point = min(candidates, key=lambda item: item[0])
        if distance > 2.0:
            row["road_node_id"] = ""
            continue
        segment_points[index].add(point)
        row["road_node_id"] = _coord_id(*point)
        row["road_connector_m"] = round(math.dist(point, row["park_position"]), 3)
    for x, z in [[0.0, 0.0]] + [anchor["position"] for anchor in RECOVERY_ANCHORS]:
        for index, road in enumerate(ROAD_SEGMENTS):
            ax, az = road["a"]; bx, bz = road["b"]
            if abs(az-bz) < .01 and abs(z-az) < .01 and min(ax,bx)-.01 <= x <= max(ax,bx)+.01:
                segment_points[index].add((float(x), float(z)))
            elif abs(ax-bx) < .01 and abs(x-ax) < .01 and min(az,bz)-.01 <= z <= max(az,bz)+.01:
                segment_points[index].add((float(x), float(z)))
    coordinate_roles: dict[tuple[float, float], set[str]] = {}
    lane_rows = []
    for index, road in enumerate(ROAD_SEGMENTS):
        ax, az = road["a"]; bx, bz = road["b"]
        horizontal = abs(az - bz) < .01
        points = sorted(segment_points[index], key=(lambda p: p[0]) if horizontal else (lambda p: p[1]))
        for point in points:
            coordinate_roles.setdefault(point, set()).add(road["id"])
        for a, b in zip(points, points[1:]):
            if math.dist(a, b) < .05: continue
            length = math.dist(a, b)
            for src, dst, direction in ((a, b, "forward"), (b, a, "reverse")):
                dx, dz = dst[0] - src[0], dst[1] - src[1]
                lane_id = f"lane:{road['id']}:{_coord_id(*src)}->{_coord_id(*dst)}"
                lane_rows.append({"id": lane_id, "from": _coord_id(*src), "to": _coord_id(*dst),
                                  "road_id": road["id"], "street_name": road["street_name"],
                                  "length_m": round(length, 3), "width_m": road["width_m"],
                                  "speed_class": road["speed_class"],
                                  "turn_permissions": ["straight", "left", "right", "u_turn"],
                                  "junction_id": "", "vehicle_type": "delivery_van",
                                  "direction": direction,
                                  "yaw_deg": round(math.degrees(math.atan2(dx, dz)), 3)})
    nodes = []
    for point, road_ids in sorted(coordinate_roles.items()):
        orientation_count = 0
        for ident in road_ids:
            road = next(item for item in ROAD_SEGMENTS if item["id"] == ident)
            orientation_count += 1
        roles = ["road"]
        if orientation_count > 1: roles.append("junction")
        if abs(point[1]) < .01 and abs(point[0]) < .01: roles.append("shop_access")
        nodes.append({"id": _coord_id(*point), "position": [point[0], point[1]],
                      "roles": roles, "road_ids": sorted(road_ids)})
    junction_nodes = {node["id"] for node in nodes if "junction" in node["roles"]}
    for lane in lane_rows:
        if lane["from"] in junction_nodes:
            lane["junction_id"] = "junction:" + lane["from"]
        elif lane["to"] in junction_nodes:
            lane["junction_id"] = "junction:" + lane["to"]
    junctions = [{"id": "junction:" + node["id"], "node_id": node["id"],
                  "min_turn_radius_m": 6.0,
                  "conflict_groups": ["vehicle:north_south", "vehicle:east_west", "pedestrian:crossing"]}
                 for node in nodes if node["id"] in junction_nodes]
    return {"nodes": nodes, "lanes": lane_rows, "junctions": junctions,
            "segments": ROAD_SEGMENTS}


def _pedestrian_graph(addresses: list[dict], road_graph: dict) -> dict:
    nodes: dict[str, dict] = {}
    edges: list[dict] = []
    junction_members: dict[str, set[str]] = {}

    def add_node(ident: str, x: float, z: float, kind: str, **extra) -> str:
        nodes.setdefault(ident, {"id": ident, "position": [round(x, 3), round(z, 3)], "kind": kind, **extra})
        return ident

    def add_edge(a: str, b: str, kind: str, length: float | None = None, conflict: str = "") -> None:
        pa, pb = nodes[a]["position"], nodes[b]["position"]
        dist = float(length) if length is not None else math.dist(pa, pb)
        for src, dst in ((a, b), (b, a)):
            edges.append({"id": f"pedlink:{src}:{dst}:{kind}", "from": src, "to": dst,
                          "length_m": round(dist, 3), "kind": kind, "direction": "both",
                          "conflict_id": conflict})

    road_edges: dict[tuple[str, str, str], dict] = {}
    for lane in road_graph["lanes"]:
        key = (lane["road_id"], *sorted((lane["from"], lane["to"])))
        road_edges[key] = lane
    for (road_id, _low, _high), lane in sorted(road_edges.items()):
        road = next(item for item in ROAD_SEGMENTS if item["id"] == road_id)
        a = road_graph["nodes"]
        node_map = {item["id"]: item for item in a}
        start = node_map[lane["from"]]; end = node_map[lane["to"]]
        # Keep the same physical edge orientation while representing sidewalks
        # as parallel offset paths, never as road-centerline walk links.
        p0 = start["position"]; p1 = end["position"]
        horizontal = abs(p0[1] - p1[1]) < .01
        sidewalk_width = SIDEWALK_WIDTH
        offset = float(road["width_m"]) / 2.0 + sidewalk_width / 2.0
        for side in (-1, 1):
            # The legacy Marinara homes occupy the outside shoulder of these
            # two center streets. Keep the continuous accessible walk on the
            # opposite side instead of routing pedestrians through house walls.
            if road["id"] == "basil" and side < 0: continue
            if road["id"] == "olive" and side > 0: continue
            if horizontal:
                x0, z0 = p0[0], p0[1] + side * offset
                x1, z1 = p1[0], p1[1] + side * offset
            else:
                x0, z0 = p0[0] + side * offset, p0[1]
                x1, z1 = p1[0] + side * offset, p1[1]
            n0 = add_node(f"ped:sidewalk:{road_id}:{start['id']}:{side:+d}", x0, z0, "sidewalk",
                          road_node_id=start["id"], road_id=road_id, side=side)
            n1 = add_node(f"ped:sidewalk:{road_id}:{end['id']}:{side:+d}", x1, z1, "sidewalk",
                          road_node_id=end["id"], road_id=road_id, side=side)
            add_edge(n0, n1, "sidewalk")
            for node_id, ped_id in ((start["id"], n0), (end["id"], n1)):
                junction_members.setdefault(node_id, set()).add(ped_id)
    # Junction crossings connect sidewalk corners and are explicit conflict links.
    junction_ids = {item["node_id"]: item["id"] for item in road_graph["junctions"]}
    for road_node_id, members in junction_members.items():
        if road_node_id not in junction_ids: continue
        members_list = sorted(members)
        for i, first in enumerate(members_list):
            for second in members_list[i + 1:]:
                distance = math.dist(nodes[first]["position"], nodes[second]["position"])
                if distance <= 18.0:
                    add_edge(first, second, "marked_crossing" if distance > 4.0 else "corner_walk",
                             conflict=junction_ids[road_node_id])
    node_lookup = list(nodes.values())
    for row in addresses:
        road_node_id = row["road_node_id"]
        side = 1 if row["north"] else -1
        candidates = [node for node in node_lookup if node.get("kind") == "sidewalk"
                      and node.get("road_node_id") == road_node_id and int(node.get("side", 0)) == side]
        if not candidates:
            candidates = [node for node in node_lookup if node.get("kind") == "sidewalk"]
        target = min(candidates, key=lambda node: math.dist(node["position"], row["park_position"]))
        px, pz = row["park_position"]; dx, dz = row["door_position"]
        park_id = add_node(row["ped_park_id"], px, pz, "parking_approach", address_id=row["id"])
        door_id = add_node(row["ped_door_id"], dx, dz, "door_threshold", address_id=row["id"])
        add_edge(target["id"], park_id, "lot_approach")
        add_edge(park_id, door_id, "door_threshold")
        row["ped_sidewalk_node_id"] = target["id"]
    # The Pizza Plaza entrance and counter join the south plaza sidewalk.
    sidewalk_candidates = [node for node in node_lookup if node.get("kind") == "sidewalk" and
                          abs(float(node["position"][0])) < 20.0 and float(node["position"][1]) > 0.0]
    plaza_sidewalk = min(sidewalk_candidates, key=lambda node: math.dist(node["position"], [0.0, 8.28]))
    add_node("entrance:pizza_shop", 0.0, 8.28, "door_threshold")
    add_node("poi:counter_access", 0.0, 11.05, "interior_threshold")
    add_node("poi:pizza_pickup", 0.0, 11.0, "service_point")
    add_node("spawn:player", 3.4, 6.4, "spawn")
    add_node("spawn:van", 0.0, 1.85, "spawn")
    add_edge(plaza_sidewalk["id"], "entrance:pizza_shop", "plaza_path")
    add_edge("entrance:pizza_shop", "poi:counter_access", "door_threshold", 2.77)
    add_edge("poi:counter_access", "poi:pizza_pickup", "service_path", .25)
    add_edge(plaza_sidewalk["id"], "spawn:player", "spawn_path")
    add_node("parking:shop-curb", 0.0, 0.0, "legal_parking")
    add_edge("parking:shop-curb", "spawn:van", "vehicle_spawn_walk", 1.85)
    for poi in _poi_records():
        x, z = poi["position"]
        poi_node = add_node(poi["id"], x, z, "poi")
        candidates = [node for node in nodes.values() if node.get("kind") == "sidewalk"]
        nearest = min(candidates, key=lambda node: math.dist(node["position"], [x, z]))
        if math.dist(nearest["position"], [x, z]) <= 24.0:
            add_edge(nearest["id"], poi_node, "poi_path")
    return {"nodes": list(nodes.values()), "edges": edges,
            "blocked_surfaces": ["surface:harbor-water", "surface:coastal-water"]}


def _poi_records() -> list[dict]:
    return [
        {"id": "poi:pizza_plaza", "kind": "landmark", "district_id": "downtown", "position": [0.0, 11.0], "marker_id": "poi:pizza_plaza"},
        {"id": "poi:shop_front_approach", "kind": "vehicle_approach", "district_id": "downtown", "position": [0.0, 7.0], "marker_id": "poi:shop_front_approach"},
        {"id": "poi:central_park", "kind": "public_square", "district_id": "downtown", "position": [0.0, -14.4], "marker_id": "poi:central_park"},
        {"id": "poi:vehicle_service", "kind": "vehicle_service", "district_id": "downtown", "position": [0.0, 16.0], "marker_id": "poi:vehicle_service"},
        {"id": "poi:cedar_green", "kind": "neighborhood_square", "district_id": "residential", "position": [-108.0, -23.0], "marker_id": "poi:cedar_green"},
        {"id": "poi:east_pier", "kind": "pier", "district_id": "waterfront", "position": [128.0, 20.0], "marker_id": "poi:east_pier"},
        {"id": "poi:summit_overlook", "kind": "overlook", "district_id": "hillside", "position": [0.0, -108.0], "marker_id": "poi:summit_overlook"},
        {"id": "poi:market_square", "kind": "public_market", "district_id": "market", "position": [0.0, 88.0], "marker_id": "poi:market_square"},
    ]


def get_layout() -> dict:
    addresses = _address_records()
    roads = _road_graph(addresses)
    pedestrians = _pedestrian_graph(addresses, roads)
    pois = _poi_records()
    recovery = RECOVERY_ANCHORS
    markers = [
        {"id": "poi:pizza_plaza", "kind": "landmark", "node_path": "WorldMarkers/Poi_pizza_plaza"},
        {"id": "poi:shop_front_approach", "kind": "vehicle_approach", "node_path": "WorldMarkers/Poi_shop_front_approach"},
        {"id": "entrance:pizza_shop", "kind": "entrance", "node_path": "PizzaShop/ShopEntrance"},
        {"id": "poi:counter_access", "kind": "service", "node_path": "PizzaShop/CounterAccess"},
        {"id": "poi:pizza_pickup", "kind": "service", "node_path": "PizzaShop/PickupPoint"},
        {"id": "poi:central_park", "kind": "poi", "node_path": "WorldMarkers/Poi_central_park"},
        {"id": "poi:vehicle_service", "kind": "poi", "node_path": "WorldMarkers/Poi_vehicle_service"},
        {"id": "poi:cedar_green", "kind": "poi", "node_path": "WorldMarkers/Poi_cedar_green"},
        {"id": "poi:east_pier", "kind": "poi", "node_path": "WorldMarkers/Poi_east_pier"},
        {"id": "poi:summit_overlook", "kind": "poi", "node_path": "WorldMarkers/Poi_summit_overlook"},
        {"id": "poi:market_square", "kind": "poi", "node_path": "WorldMarkers/Poi_market_square"},
        {"id": "spawn:player", "kind": "spawn", "node_path": "PlayerSpawn"},
        {"id": "spawn:van", "kind": "spawn", "node_path": "VanSpawn"},
    ]
    for anchor in recovery:
        markers.append({"id": anchor["id"], "kind": "recovery", "node_path": "WorldMarkers/" + anchor["id"].replace(":", "_")})
    for row in addresses:
        markers.extend([
            {"id": row["id"], "kind": "address", "node_path": f"Houses/{row['node_name']}", "district_id": row["district_id"]},
            {"id": row["ped_door_id"], "kind": "door", "node_path": f"Houses/{row['node_name']}/Door", "address_id": row["id"]},
            {"id": row["parking_id"], "kind": "parking", "node_path": f"Houses/{row['node_name']}/Park", "address_id": row["id"]},
            {"id": row["customer_slot_id"], "kind": "customer_slot", "node_path": f"Houses/{row['node_name']}/CustomerSlot", "address_id": row["id"]},
        ])
    return {
        "schema_version": SCHEMA_VERSION, "world_id": WORLD_ID, "decoration_seed": DECORATION_SEED,
        "bounds": BOUNDS, "districts": DISTRICTS, "addresses": addresses, "pois": pois,
        "recovery_anchors": recovery,
        "spawns": [{"id": "spawn:player", "position": [3.4, 6.4], "yaw_deg": -35.0},
                   {"id": "spawn:van", "position": [0.0, 1.85], "yaw_deg": 90.0}],
        "road_graph": roads, "pedestrian_graph": pedestrians, "markers": markers,
        "routing": {"shop_start_position": [0.0, 8.28], "shop_start_marker_id": "entrance:pizza_shop",
                    "van_min_turn_radius_m": 4.2, "clearance_margin_m": 0.35},
        "collision_matrix": {"world": {"layer": 1, "blocks": ["player", "van"]},
                             "player": {"layer": 2, "mask": ["world", "vehicle"]},
                             "van": {"layer": 4, "mask": ["world"]},
                             "vehicle_barrier": {"layer": 1, "blocks": ["player", "van"]},
                             "foliage": {"collision": False},
                             "water": {"blocks": ["player", "van"], "walkable": False},
                             "door_threshold": {"traversable": "interaction boundary"}},
        "actor_clearance": {"player_capsule_radius_m": 0.34, "player_capsule_height_m": 1.9,
                            "van_width_m": 2.0, "van_height_m": 2.4, "van_length_m": 3.85},
        "legacy_destination_order": [row["id"] for row in addresses[:8]],
    }


def validate_layout(layout: dict | None = None) -> list[str]:
    data = layout or get_layout()
    errors: list[str] = []
    addresses = data.get("addresses", [])
    ids = [row.get("id") for row in addresses]
    if len(ids) != len(set(ids)): errors.append("duplicate address ID")
    lots = [row.get("lot_id") for row in addresses]
    if len(lots) != len(set(lots)): errors.append("duplicate lot ID")
    road_nodes = {node.get("id") for node in data.get("road_graph", {}).get("nodes", [])}
    for row in addresses:
        if row.get("road_node_id") not in road_nodes: errors.append(f"address {row.get('id')} references missing road node")
        for key in ("position", "door_position", "park_position", "road_access_position", "customer_slot_position"):
            pos = row.get(key, [])
            if len(pos) != 2 or any(not isinstance(value, (int, float)) for value in pos): errors.append(f"address {row.get('id')} has invalid {key}")
    for graph_name, collection_name in (("road_graph", "lanes"), ("pedestrian_graph", "edges")):
        graph = data.get(graph_name, {})
        node_ids = {node.get("id") for node in graph.get("nodes", [])}
        edge_ids = [edge.get("id") for edge in graph.get(collection_name, [])]
        if len(edge_ids) != len(set(edge_ids)): errors.append(f"duplicate {graph_name} edge ID")
        for edge in graph.get(collection_name, []):
            if edge.get("from") not in node_ids or edge.get("to") not in node_ids:
                errors.append(f"{graph_name} edge {edge.get('id')} has missing endpoint")
    marker_ids = [marker.get("id") for marker in data.get("markers", [])]
    if len(marker_ids) != len(set(marker_ids)): errors.append("duplicate marker ID")
    paths = [marker.get("node_path") for marker in data.get("markers", [])]
    if len(paths) != len(set(paths)): errors.append("duplicate marker scene node path")
    bounds = data.get("bounds", {})
    for row in addresses:
        x, z = row["position"]; width, depth = row["footprint_m"]
        building_z = z - (1.0 if row["north"] else -1.0) * depth / 2.0
        if not (bounds["min_x"] + width/2 <= x <= bounds["max_x"] - width/2 and
                bounds["min_z"] + depth/2 <= building_z <= bounds["max_z"] - depth/2):
            errors.append(f"address {row['id']} outside world bounds")
    for i, first in enumerate(addresses):
        for second in addresses[i+1:]:
            ax, az = first["position"]; bx, bz = second["position"]
            aw, ad = first["footprint_m"]; bw, bd = second["footprint_m"]
            az -= (1.0 if first["north"] else -1.0) * ad / 2.0
            bz -= (1.0 if second["north"] else -1.0) * bd / 2.0
            if abs(ax-bx) < (aw+bw)/2 - .05 and abs(az-bz) < (ad+bd)/2 - .05:
                errors.append(f"overlapping address buildings: {first['id']} and {second['id']}")
    pedestrian_nodes = {node["id"]: node for node in data["pedestrian_graph"]["nodes"]}
    for row in addresses:
        sidewalk = pedestrian_nodes.get(row.get("ped_sidewalk_node_id", ""), {})
        if sidewalk:
            sx, sz = sidewalk["position"]
            x, z = row["position"]; width, depth = row["footprint_m"]
            z -= (1.0 if row["north"] else -1.0) * depth / 2.0
            if abs(sx - x) < width / 2 + 0.65 and abs(sz - z) < depth / 2 + 0.65:
                errors.append(f"sidewalk conflicts with the building approach at {row['id']}")
    node_by_id = {node["id"]: node for node in data["road_graph"]["nodes"]}
    seen_segments: set[tuple[str, str, str]] = set()
    for lane in data["road_graph"]["lanes"]:
        key = (lane.get("road_id", ""), *sorted((lane["from"], lane["to"])))
        if key in seen_segments: continue
        seen_segments.add(key)
        a, b = node_by_id[lane["from"]]["position"], node_by_id[lane["to"]]["position"]
        for row in addresses:
            x, z = row["position"]; width, depth = row["footprint_m"]
            z -= (1.0 if row["north"] else -1.0) * depth / 2.0
            if abs(a[0]-b[0]) < .01:
                if abs(x-a[0]) < (width + .3)/2 + float(lane["width_m"])/2 and min(a[1], b[1]) < z+(depth+.3)/2 and max(a[1], b[1]) > z-(depth+.3)/2:
                    errors.append(f"road/building overlap at {row['id']}")
            elif abs(a[1]-b[1]) < .01:
                if abs(z-a[1]) < (depth + .3)/2 + float(lane["width_m"])/2 and min(a[0], b[0]) < x+(width+.3)/2 and max(a[0], b[0]) > x-(width+.3)/2:
                    errors.append(f"road/building overlap at {row['id']}")
    clearance = float(data["actor_clearance"]["van_width_m"]) + 2 * float(data["routing"]["clearance_margin_m"])
    for lane in data["road_graph"]["lanes"]:
        if float(lane["width_m"]) < clearance: errors.append(f"lane {lane['id']} is narrower than van clearance")
    for junction in data["road_graph"]["junctions"]:
        if float(junction["min_turn_radius_m"]) < float(data["routing"]["van_min_turn_radius_m"]):
            errors.append(f"junction {junction['id']} is too tight for the van")
    district_ids = {district["id"] for district in data.get("districts", [])}
    for district_id in district_ids:
        if not any(row["district_id"] == district_id for row in addresses): errors.append(f"district has no addresses: {district_id}")
    for anchor in data.get("recovery_anchors", []):
        x, z = anchor["position"]
        if not any(math.dist([x, z], node["position"]) < 1.0 for node in data["road_graph"]["nodes"]):
            errors.append(f"recovery anchor is not on a legal road: {anchor['id']}")
    return errors


def write_layout(path: Path) -> None:
    layout = get_layout()
    errors = validate_layout(layout)
    if errors: raise ValueError("invalid world layout: " + "; ".join(errors[:20]))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(layout, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    import sys
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "data/world/world_layout.json"
    write_layout(output)
    print(f"WORLD DATA PASS: {output}")
