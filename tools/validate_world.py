"""Validate authored world references, graph reachability, and emit a DOT map."""
from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
import sys

from world_data import get_layout, validate_layout, write_layout


def shortest(layout: dict, graph_name: str, start: str, target: str,
             closed: set[str] | None = None) -> tuple[float, list[str]]:
    graph = layout[graph_name]
    edges = graph["lanes"] if graph_name == "road_graph" else graph["edges"]
    closed = closed or set()
    distances = {start: 0.0}
    previous: dict[str, str] = {}
    remaining = set(distances)
    while remaining:
        node = min(remaining, key=distances.get)
        remaining.remove(node)
        if node == target:
            path = [target]
            while path[-1] != start:
                path.append(previous[path[-1]])
            return distances[target], list(reversed(path))
        for edge in edges:
            if edge["from"] != node or edge["id"] in closed:
                continue
            neighbor = edge["to"]
            new_cost = distances[node] + float(edge["length_m"])
            if new_cost < distances.get(neighbor, math.inf):
                distances[neighbor] = new_cost
                previous[neighbor] = node
                remaining.add(neighbor)
    return math.inf, []


def validate_reachability(layout: dict) -> list[str]:
    errors = []
    road = layout["road_graph"]
    shop = layout.get("routing", {}).get("shop_start_position", [0.0, 0.0])
    start = min(road["nodes"], key=lambda n: (n["position"][0] - shop[0]) ** 2 + (n["position"][1] - shop[1]) ** 2)["id"]
    pedestrian = layout["pedestrian_graph"]
    ped_start = "poi:pizza_pickup"
    for row in layout["addresses"]:
        distance, _ = shortest(layout, "road_graph", start, row["road_node_id"])
        if not math.isfinite(distance): errors.append(f"unreachable vehicle parking route: {row['id']}")
        distance, _ = shortest(layout, "pedestrian_graph", row["ped_park_id"], row["ped_door_id"])
        if not math.isfinite(distance): errors.append(f"unreachable door from parking: {row['id']}")
        distance, _ = shortest(layout, "pedestrian_graph", ped_start, row["ped_door_id"])
        if not math.isfinite(distance): errors.append(f"disconnected pedestrian district at: {row['id']}")
    if not any(node["id"] == ped_start for node in pedestrian["nodes"]):
        errors.append("pedestrian graph is missing pickup node")
    district_ids = {district["id"] for district in layout.get("districts", [])}
    for district_id in district_ids:
        if not any(address["district_id"] == district_id for address in layout["addresses"]):
            errors.append(f"district has no reachable delivery address: {district_id}")
    return errors


def write_dot(layout: dict, path: Path) -> None:
    lines = ["digraph world {", "  graph [rankdir=LR, label=\"Road lanes →   Pedestrian links - -   Blocked water: pond\", labelloc=t];",
             "  node [shape=ellipse, fontname=Arial, fontsize=8];"]
    for node in layout["road_graph"]["nodes"]:
        label = node["id"].replace("road:", "")
        lines.append(f'  "{node["id"]}" [label="{label}", color="#c95a4d", fontcolor="#8c302e"];')
    for lane in layout["road_graph"]["lanes"]:
        lines.append(f'  "{lane["from"]}" -> "{lane["to"]}" [color="#c95a4d", penwidth=1.4, label="{lane["speed_class"]}"];')
    for node in layout["pedestrian_graph"]["nodes"]:
        if node["id"].startswith("ped:") or node["kind"] in {"door_threshold", "interior_threshold", "service_point"}:
            label = node["id"].replace("ped:", "").replace("poi:", "")
            lines.append(f'  "{node["id"]}" [label="{label}", shape=box, color="#347a70", fontcolor="#245b55"];')
    for edge in layout["pedestrian_graph"]["edges"]:
        lines.append(f'  "{edge["from"]}" -> "{edge["to"]}" [style=dashed, color="#347a70", label="{edge["kind"]}"];')
    lines.append('  "blocked:water" [shape=note, label="Pond / water\nsolid collision; no walk link", color="#508e9a"];')
    for row in layout["addresses"]:
        lines.append(f'  "{row["road_node_id"]}" -> "{row["ped_park_id"]}" [style=dotted, color="#d5a43a", label="{row["address"]}"];')
    lines.append("}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layout", type=Path, help="validate a generated layout JSON file")
    parser.add_argument("--diagram", type=Path, help="write a Graphviz DOT road/pedestrian diagram")
    args = parser.parse_args()
    if args.layout:
        layout = json.loads(args.layout.read_text(encoding="utf-8"))
    else:
        layout = get_layout()
    errors = validate_layout(layout) + validate_reachability(layout)
    # A deliberately disconnected fixture must be rejected by the same rules.
    disconnected = copy.deepcopy(layout)
    disconnected["road_graph"]["lanes"] = []
    if not validate_reachability(disconnected): errors.append("disconnected fixture was not rejected")
    if args.diagram:
        write_dot(layout, args.diagram)
    if errors:
        print("WORLD VALIDATION FAIL")
        for error in errors: print(" - " + error)
        return 1
    b = layout["bounds"]
    width = b["max_x"] - b["min_x"]
    depth = b["max_z"] - b["min_z"]
    print(f"WORLD VALIDATION PASS: {len(layout['addresses'])} addresses; {len(layout['districts'])} districts; {width:g} x {depth:g} m; {len(layout['road_graph']['lanes'])} directed lanes; {len(layout['pedestrian_graph']['edges'])} pedestrian links")
    if args.diagram: print(f"WORLD GRAPH DIAGRAM: {args.diagram}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
