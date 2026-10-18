# Phase 09 — Author world and road graphs
Status: VERIFIED

## Implemented behavior

- The eight original delivery addresses now carry stable `address_id`, district,
  lot, Door and parking IDs. The original display-address IDs and first-eight
  legacy destination order remain intact.
- A generated JSON catalog is produced from `tools/world_data.py`. It records
  bounds, districts, lots, POIs, spawns, the collision matrix and actor sizes,
  directed delivery-van lanes, junction conflicts and a separate sidewalk,
  crossing, parking-approach and doorway graph.
- `WorldRegistry` resolves stable address/marker IDs and reports registration
  changes. Order selection uses the active catalog order, and legacy index
  requests still map to the original eight destinations.
- `WorldGraphService` provides nearest legal lane entry, directed route length,
  parking access and final walk distance. The order route estimate now uses those
  costs and returns `INF` for missing or disconnected destinations.
- Visible pond water blocks player/van collision. Authored picket fences have
  world barriers; foliage stays decorative. The existing collision layers and
  actual Pip/van collider dimensions are recorded and checked against lane and
  junction clearance.
- Capture's shop-front target reads a registered plaza approach marker, rather
  than a baked-in coordinate. A DOT diagram at `docs/world_graph.dot` shows road
  directions, pedestrian links, address access and blocked water.

## Files and ownership

- `tools/world_data.py` owns world bounds, existing address records, lane/pedestrian
  graph source, marker references, dimensions and JSON validation.
- `tools/build_town.py`, `tools/townkit.py` and `tools/build_art.py` generate the
  scenes and catalog; both builders support isolated `--output` staging.
- `scripts/services/world_registry.gd` owns active marker/address lookup and
  registration events. `scripts/services/world_graph_service.gd` owns graph
  parsing and cost queries. `scripts/game.gd` consumes route estimates.
- `tools/validate_world.py`, `tools/world_graph_checks.gd`, `tools/check_town.gd`
  and `tools/run_checks.py` validate topology and integrate it into the suite.
- Generated outputs: `assets/pizza_shop.tscn`, `assets/town_houses.tscn`,
  `assets/town_island.tscn`, `scenes/town.tscn`, and
  `data/world/world_layout.json`. The other generated art hashes remain stable.
- `README.md`, `docs/ARCHITECTURE.md`, `docs/world_graph.dot`,
  `tools/SCENARIOS.md` and `PHASE_PROGRESS.md` document the new contracts.

## Contracts for the next phase

- Catalog schema `schema_version: 1`: `bounds`, `districts`, `addresses`, `pois`,
  `spawns`, `road_graph.nodes/lanes/junctions`, `pedestrian_graph.nodes/edges`,
  `markers`, `collision_matrix`, `actor_clearance`, `routing` and
  `legacy_destination_order`.
- Address record ID is its `id`/scene `address_id`; display text is `address`.
  Door and Park retain their scene names for existing interactions. Road edges
  have metre costs, widths, speed classes, turn permissions, junction IDs,
  vehicle type and `yaw_deg` using the van's local +Z forward axis.
- WorldRegistry APIs: `ids()`, `address(id)`, `address_record(id)`,
  `destination(id)`, `marker(id)`, `register_marker(id, kind, node)` and
  `unregister_marker(id)`. Its `registration_changed` payload is
  `{id, kind, registered}`. Use `legacy_id(index)` only for the original
  compatibility mapping.
- WorldGraphService APIs: `nearest_legal_entry(position, vehicle_type)`,
  `vehicle_route(position, address_id, closed_lanes)`,
  `pedestrian_route(from_id, to_id, blocked_edges)` and
  `route_seconds(route, road_speed_mps, parking_seconds)`. Route lengths are
  metres; the estimated travel cost is seconds.
- Layer 1 remains environment/barriers, layer 2 Pip and layer 4 van. Roads and
  sidewalks are graph-authoritative travel links; building and water bodies are
  solid, fences are explicit barriers and foliage does not collide.

## Validation evidence

- `python tools/run_checks.py --godot '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'` — **SUITE PASS: 54 commands; logical replays match**. Includes 42 Phase 09 graph/registry checks, the existing 20-check physical delivery route, and all prior capture and negative fixtures. Evidence: `.godot/test-runs/suite-1792348804919522300-21864/`.
- `python tools/validate_world.py --layout data/world/world_layout.json --diagram docs/world_graph.dot` — 8 addresses, 1 connected district, 68 × 56 m, 32 directed lanes and 122 pedestrian links; disconnected-lane fixture rejected.
- `& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/world_graph_checks.gd` — **42 checks, 0 failures**.
- `& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . --script tools/phase08_route_checks.gd` — **20 checks, 0 failures**, using ordinary foot/drive inputs without teleport or autopilot.
- Art and town generators were each run twice into `.godot/phase09-stage-a/` and `.godot/phase09-stage-b/`. **All 11 generated outputs were byte-identical**, and every staged output matched the checkout.
- `git diff --check` passed. No rendered Phase 09 screenshots or human free-play session were recorded.

## Known defects / incomplete acceptance items

- The route estimate uses graph centerlines plus authored lot connectors. It does
  not simulate steering dynamics or compute obstacle-avoiding paths through
  arbitrary terrain; the physical no-teleport route remains the original plaza
  to Marinara address.
- Junction lane records currently allow all four turn classes. Phase 13 should
  enforce turn permissions and junction reservations when traffic is introduced.
- The world is still the 68 × 56 m prototype. Phase 10 must expand the physical
  network and catalog together; do not merely scale the ground plane.

## Player controls and documentation

No player controls changed. Town regeneration:

```powershell
python tools/build_art.py
python tools/build_town.py
```

Use `--output <staging-root>` on either builder for isolated output.

## Next phase entry point

Read `implementation-prompts/phase-10-expand-the-island-and-districts.md` and
this handoff. Expand the authored road/address source first, then generate the
320 × 240 m island, five districts, looped road links and 40+ accessible delivery
lots. Keep the eight Marinara IDs/order, pizza plaza transform and staged builder
contract. Measure route lengths, generated counts and performance; do not claim
whole-world physical traversal from graph-only validation.
