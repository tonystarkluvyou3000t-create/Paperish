"""Authoritative authored world catalog and deterministic layout serializer.

Geometry generators, runtime registry, and route services share this schema.
Coordinates are metres in Godot X/Z; vehicle forward is local +Z.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

SCHEMA_VERSION = 1
WORLD_ID = "pip-island"
DECORATION_SEED = 23
BOUNDS = {"min_x": -34.0, "max_x": 34.0, "min_z": -28.0, "max_z": 28.0}
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
ROAD_JUNCTION_ZS = tuple(sorted({-VROAD_Z, MAIN_Z0, 0.0, MAIN_Z1, VROAD_Z}))
CROSSING_SPANS = ((BASIL_X0 - SIDEWALK_WIDTH, BASIL_X0), (BASIL_X1, BASIL_X1 + SIDEWALK_WIDTH),
                  (OLIVE_X0 - SIDEWALK_WIDTH, OLIVE_X0), (OLIVE_X1, OLIVE_X1 + SIDEWALK_WIDTH))
CROSSWALK_XS = tuple((a + b) / 2.0 for a, b in CROSSING_SPANS)

DISTRICTS = [{"id": "downtown", "name": "Downtown", "bounds": [-34, 34, -28, 28],
              "landmark": "Pizza Plaza"}]

# Presentation profiles are kept separate from semantic address identity.
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


def _addr_id(address: str) -> str:
    return address


def _address_records() -> list[dict]:
    rows = []
    for h in HOUSE_STYLES:
        address = f"{h['num']} Marinara Way"
        f = 1 if h['north'] else -1
        side = -1 if h['num'] % 4 == 2 else 1
        rows.append({
            "id": _addr_id(address), "address": address, "label": h["label"],
            "number": h["num"], "district_id": "downtown", "kind": "house",
            "lot_id": f"lot:marinara:{h['num']:02d}", "node_name": f"House_{h['num']:02d}",
            "position": [h["x"], -f * FRONT_OFF], "door_position": [h["x"], -f * FRONT_OFF + f],
            "park_position": [h["x"] + side * 2.75, -f * FRONT_OFF + f * 2.0],
            "footprint_m": [HOUSE_W, HOUSE_D],
            "north": h["north"], "road_node_id": f"road:marinara:{h['num']:02d}",
            "road_connector_m": 6.4, "ped_door_id": f"ped:door:{h['num']:02d}",
            "ped_park_id": f"ped:park:{h['num']:02d}", "entrance_id": f"entrance:{h['num']:02d}",
            "parking_id": f"parking:{h['num']:02d}", "style": "classic",
        })
    return rows


def _road_graph(addresses: list[dict]) -> dict:
    # Centerline vertices split at intersections and address-access branches.
    xs = sorted(set([MAIN_X0, ROAD_JUNCTION_XS[0], 0.0, ROAD_JUNCTION_XS[1], MAIN_X1] + [float(a["position"][0]) for a in addresses]))
    nodes: list[dict] = []
    for x in xs:
        roles = ["marinara"]
        if any(abs(x - junction_x) < .01 for junction_x in ROAD_JUNCTION_XS): roles.append("junction")
        if abs(x) < .01: roles.append("shop_access")
        nodes.append({"id": f"road:main:x{int(round(x*10)):+04d}", "position": [x, 0.0], "roles": roles})
    main_ids = [n["id"] for n in nodes]
    for x, branch in zip(ROAD_JUNCTION_XS, ["basil", "olive"]):
        for z in ROAD_JUNCTION_ZS:
            if abs(z) < .01: continue
            nodes.append({"id": f"road:{branch}:z{int(round(z*10)):+04d}", "position": [x, z],
                          "roles": ["junction" if abs(z) < 3.21 else "street_end"]})
    segments = []

    def add_pair(a: dict, b: dict, street: str, junction: str = "") -> None:
        ax, az = a["position"]; bx, bz = b["position"]
        length = ((bx-ax)**2 + (bz-az)**2)**0.5
        for src, dst, direction in [(a, b, "forward"), (b, a, "reverse")]:
            dx, dz = float(dst["position"][0]) - float(src["position"][0]), float(dst["position"][1]) - float(src["position"][1])
            segments.append({"id": f"lane:{street}:{src['id']}->{dst['id']}",
                             "from": src["id"], "to": dst["id"], "length_m": round(length, 3),
                             "width_m": ROAD_WIDTH_M,
                             "speed_class": "main" if street == "marinara" else "local",
                             "turn_permissions": ["straight", "left", "right", "u_turn"],
                             "junction_id": junction, "vehicle_type": "delivery_van",
                             "direction": direction, "yaw_deg": round(math.degrees(math.atan2(dx, dz)), 3)})

    for left, right in zip(nodes[:len(xs)-1], nodes[1:len(xs)]):
        jid = next((f"junction:marinara-{street}" for street, junction_x in zip(["basil", "olive"], ROAD_JUNCTION_XS)
                    if abs(float(left["position"][0]) - junction_x) < .01 or abs(float(right["position"][0]) - junction_x) < .01), "")
        add_pair(left, right, "marinara", jid)
    for x, street in zip(ROAD_JUNCTION_XS, ["basil", "olive"]):
        vertical = [n for n in nodes if abs(float(n["position"][0])-x) < .01]
        vertical.sort(key=lambda n: n["position"][1])
        for a, b in zip(vertical, vertical[1:]):
            add_pair(a, b, street, f"junction:marinara-{street}" if (abs(a["position"][1]) <= 3.2 and abs(b["position"][1]) <= 3.2) else "")
    for row in addresses:
        x = float(row["position"][0])
        node = min(nodes, key=lambda n: abs(float(n["position"][0])-x) + abs(float(n["position"][1])))
        row["road_node_id"] = node["id"]
    junctions = [{"id": f"junction:marinara-{street}", "node_id": f"road:main:x{int(round(x*10)):+04d}", "min_turn_radius_m": 5.0,
                  "conflict_groups": ["veh:ns", "veh:ew", "ped:north-crossing", "ped:south-crossing"]}
                 for street, x in zip(["basil", "olive"], ROAD_JUNCTION_XS)]
    return {"nodes": nodes, "lanes": segments, "junctions": junctions}


def _pedestrian_graph(addresses: list[dict]) -> dict:
    nodes = []
    edges = []
    def node(ident: str, x: float, z: float, kind: str) -> str:
        nodes.append({"id": ident, "position": [x, z], "kind": kind})
        return ident
    def edge(a: str, b: str, length: float | None = None, kind: str = "walkway", mode: str = "both") -> None:
        aa = next(n for n in nodes if n["id"] == a); bb = next(n for n in nodes if n["id"] == b)
        dist = length if length is not None else (((aa["position"][0]-bb["position"][0])**2 + (aa["position"][1]-bb["position"][1])**2)**0.5)
        edges.append({"id": f"pedlink:{a}:{b}", "from": a, "to": b, "length_m": round(dist, 3), "kind": kind, "direction": mode})
        if mode == "both": edges.append({"id": f"pedlink:{b}:{a}", "from": b, "to": a, "length_m": round(dist, 3), "kind": kind, "direction": "both"})
    xs = sorted(set([MAIN_X0, MAIN_X1, 0.0, BASIL_X0 - SIDEWALK_WIDTH, BASIL_X0, BASIL_X1,
                     BASIL_X1 + SIDEWALK_WIDTH, OLIVE_X0 - SIDEWALK_WIDTH, OLIVE_X0,
                     OLIVE_X1, OLIVE_X1 + SIDEWALK_WIDTH] + list(CROSSWALK_XS) +
                    [float(a["position"][0]) for a in addresses]))
    side_ids = {1: [], -1: []}
    for side in [1, -1]:
        z = side * 5.0
        for i, x in enumerate(xs):
            ident = node(f"ped:sidewalk:{'south' if side > 0 else 'north'}:{i:02d}", x, z, "sidewalk")
            side_ids[side].append(ident)
        for a, b in zip(side_ids[side], side_ids[side][1:]): edge(a, b)
    # Marked crossings tie the two independent sidewalk networks together.
    for cross_index, x in enumerate(CROSSWALK_XS):
        north = min(side_ids[-1], key=lambda ident: abs(next(n for n in nodes if n["id"] == ident)["position"][0]-x))
        south = min(side_ids[1], key=lambda ident: abs(next(n for n in nodes if n["id"] == ident)["position"][0]-x))
        edge(north, south, 10.0, "marked_crossing")
    for a in addresses:
        x, _ = a["position"]
        side = -1 if a["north"] else 1
        sidewalk = min(side_ids[side], key=lambda ident: abs(next(n for n in nodes if n["id"] == ident)["position"][0]-x))
        px, pz = a["park_position"]; dx, dz = a["door_position"]
        park = node(a["ped_park_id"], float(px), float(pz), "parking_approach")
        door = node(a["ped_door_id"], float(dx), float(dz), "door_threshold")
        edge(sidewalk, park, kind="lot_path")
        edge(park, door, kind="door_path")
    # Pizza plaza entrance, counter threshold, pickup, spawn and service access.
    south = min(side_ids[1], key=lambda ident: abs(next(n for n in nodes if n["id"] == ident)["position"][0]))
    entrance = node("entrance:pizza_shop", 0.0, 8.28, "door_threshold")
    counter = node("poi:counter_access", 0.0, 11.05, "interior_threshold")
    pickup = node("poi:pizza_pickup", 0.0, 11.0, "service_point")
    player = node("spawn:player", 3.4, 6.4, "spawn")
    van = node("spawn:van", 0.0, 1.85, "spawn")
    edge(south, entrance, kind="plaza_path")
    edge(entrance, counter, 2.77, "door_threshold")
    edge(counter, pickup, 0.25, "service_path")
    edge(south, player, kind="spawn_path")
    road_edge = node("parking:shop-curb", 0.0, 0.0, "legal_parking")
    edge(road_edge, van, 1.85, "vehicle_spawn_walk")
    return {"nodes": nodes, "edges": edges, "blocked_surfaces": ["surface:pond-water"]}


def get_layout() -> dict:
    addresses = _address_records()
    roads = _road_graph(addresses)
    pedestrians = _pedestrian_graph(addresses)
    pois = [
        {"id": "poi:pizza_plaza", "kind": "landmark", "district_id": "downtown", "position": [0.0, 11.0], "marker_id": "poi:pizza_plaza"},
        {"id": "poi:shop_front_approach", "kind": "vehicle_approach", "district_id": "downtown", "position": [0.0, 7.0], "marker_id": "poi:shop_front_approach"},
        {"id": "poi:central_park", "kind": "public_square", "district_id": "downtown", "position": [0.0, -14.4], "marker_id": "poi:central_park"},
        {"id": "poi:vehicle_service", "kind": "vehicle_service", "district_id": "downtown", "position": [0.0, 16.0], "marker_id": "poi:vehicle_service"},
    ]
    markers = [{"id": "poi:pizza_plaza", "kind": "landmark", "node_path": "WorldMarkers/PizzaPlaza"},
               {"id": "poi:shop_front_approach", "kind": "vehicle_approach", "node_path": "WorldMarkers/ShopFrontApproach"},
               {"id": "entrance:pizza_shop", "kind": "entrance", "node_path": "PizzaShop/ShopEntrance"},
               {"id": "poi:central_park", "kind": "poi", "node_path": "WorldMarkers/CentralPark"},
               {"id": "poi:vehicle_service", "kind": "poi", "node_path": "WorldMarkers/VehicleService"},
               {"id": "spawn:player", "kind": "spawn", "node_path": "PlayerSpawn"},
               {"id": "spawn:van", "kind": "spawn", "node_path": "VanSpawn"},
               {"id": "poi:counter_access", "kind": "service", "node_path": "PizzaShop/CounterAccess"},
               {"id": "poi:pizza_pickup", "kind": "service", "node_path": "PizzaShop/PickupPoint"}]
    for a in addresses:
        markers.extend([
            {"id": a["id"], "kind": "address", "node_path": f"Houses/{a['node_name']}", "district_id": a["district_id"]},
            {"id": a["ped_door_id"], "kind": "door", "node_path": f"Houses/{a['node_name']}/Door", "address_id": a["id"]},
            {"id": a["parking_id"], "kind": "parking", "node_path": f"Houses/{a['node_name']}/Park", "address_id": a["id"]},
        ])
    return {
        "schema_version": SCHEMA_VERSION, "world_id": WORLD_ID, "decoration_seed": DECORATION_SEED,
        "bounds": BOUNDS, "districts": DISTRICTS, "addresses": addresses, "pois": pois,
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
    errors = []
    addresses = data.get("addresses", [])
    ids = [row.get("id") for row in addresses]
    if len(ids) != len(set(ids)): errors.append("duplicate address ID")
    lots = [row.get("lot_id") for row in addresses]
    if len(lots) != len(set(lots)): errors.append("duplicate lot ID")
    road_nodes = {node.get("id") for node in data.get("road_graph", {}).get("nodes", [])}
    for row in addresses:
        if row.get("road_node_id") not in road_nodes: errors.append(f"address {row.get('id')} references missing road node")
        for key in ("position", "door_position", "park_position"):
            pos = row.get(key, [])
            if len(pos) != 2 or any(not isinstance(value, (int, float)) for value in pos): errors.append(f"address {row.get('id')} has invalid {key}")
    for graph_name, collection_name, ref_keys in [("road_graph", "lanes", ("from", "to")), ("pedestrian_graph", "edges", ("from", "to"))]:
        graph = data.get(graph_name, {})
        node_ids = {node.get("id") for node in graph.get("nodes", [])}
        edge_ids = [edge.get("id") for edge in graph.get(collection_name, [])]
        if len(edge_ids) != len(set(edge_ids)): errors.append(f"duplicate {graph_name} edge ID")
        for edge in graph.get(collection_name, []):
            if any(edge.get(key) not in node_ids for key in ref_keys): errors.append(f"{graph_name} edge {edge.get('id')} has missing endpoint")
    marker_ids = [marker.get("id") for marker in data.get("markers", [])]
    if len(marker_ids) != len(set(marker_ids)): errors.append("duplicate marker ID")
    paths = [marker.get("node_path") for marker in data.get("markers", [])]
    if len(paths) != len(set(paths)): errors.append("duplicate marker scene node path")
    bounds = data.get("bounds", {})
    for row in addresses:
        x, z = row.get("position", [0.0, 0.0])
        width, depth = row.get("footprint_m", [HOUSE_W, HOUSE_D])
        if not (bounds.get("min_x", -float("inf")) + width / 2 <= x <= bounds.get("max_x", float("inf")) - width / 2 and
                bounds.get("min_z", -float("inf")) + depth / 2 <= z <= bounds.get("max_z", float("inf")) - depth / 2):
            errors.append(f"address {row.get('id')} outside world bounds")
    for i, first in enumerate(addresses):
        for second in addresses[i + 1:]:
            ax, az = first["position"]; bx, bz = second["position"]
            aw, ad = first.get("footprint_m", [HOUSE_W, HOUSE_D]); bw, bd = second.get("footprint_m", [HOUSE_W, HOUSE_D])
            if abs(ax-bx) < (aw+bw)/2 - .05 and abs(az-bz) < (ad+bd)/2 - .05:
                errors.append(f"overlapping address buildings: {first.get('id')} and {second.get('id')}")
    # A building footprint cannot cover a drivable road centerline clearance envelope.
    lanes = data.get("road_graph", {}).get("lanes", [])
    road_nodes_by_id = {node["id"]: node for node in data.get("road_graph", {}).get("nodes", [])}
    seen_undirected = set()
    for lane in lanes:
        pair = tuple(sorted((lane["from"], lane["to"])))
        if pair in seen_undirected: continue
        seen_undirected.add(pair)
        start = road_nodes_by_id[lane["from"]]["position"]; end = road_nodes_by_id[lane["to"]]["position"]
        for row in addresses:
            x, z = row["position"]; width, depth = row.get("footprint_m", [HOUSE_W, HOUSE_D])
            if abs(start[0]-end[0]) < .01:
                road_x = start[0]
                if abs(x-road_x) < width/2 + float(lane.get("width_m", 0))/2 and min(start[1], end[1]) < z+depth/2 and max(start[1], end[1]) > z-depth/2:
                    errors.append(f"road/building overlap at {row.get('id')}")
            elif abs(start[1]-end[1]) < .01:
                road_z = start[1]
                if abs(z-road_z) < depth/2 + float(lane.get("width_m", 0))/2 and min(start[0], end[0]) < x+width/2 and max(start[0], end[0]) > x-width/2:
                    errors.append(f"road/building overlap at {row.get('id')}")
    clearance = float(data.get("actor_clearance", {}).get("van_width_m", 2.0)) + 2.0 * float(data.get("routing", {}).get("clearance_margin_m", .35))
    for lane in data.get("road_graph", {}).get("lanes", []):
        if float(lane.get("width_m", 0.0)) < clearance:
            errors.append(f"lane {lane.get('id')} is narrower than van clearance")
    min_turn = float(data.get("routing", {}).get("van_min_turn_radius_m", 4.2))
    for junction in data.get("road_graph", {}).get("junctions", []):
        if float(junction.get("min_turn_radius_m", 0.0)) < min_turn:
            errors.append(f"junction {junction.get('id')} is too tight for the van")
    return errors


def write_layout(path: Path) -> None:
    errors = validate_layout()
    if errors: raise ValueError("invalid world layout: " + "; ".join(errors))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(get_layout(), indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    import sys
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "data/world/world_layout.json"
    write_layout(output)
    print(f"WORLD DATA PASS: {output}")
