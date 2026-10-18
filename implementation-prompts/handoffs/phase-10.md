# Phase 10 — Expand the island and districts
Status: VERIFIED

## Implemented behavior

- Expanded the physical island and source catalog to 320 × 240 m, bounded by
  x = -160…160 m and z = -120…120 m. The original Pizza Plaza, first eight
  Marinara Way IDs and their order remain intact.
- Added five connected districts: Downtown (8 addresses), Cedar Grove,
  Harborfront, Summit Hill and Market Works (9 each). The 44 delivery lots
  include a clinic, harbor office, summit lodge, market stall and workshop.
- Every lot has stable address/district/lot IDs plus door, parking, pedestrian
  approach and CustomerSlot markers. Customer placement now uses the authored
  slot, retaining the previous calculation only for older scenes without one.
- Generated looped road and sidewalk geometry from the catalog's centerlines,
  with crossings, parking pads, coast barriers, harbor water, pier access and
  recovery anchors in each district. The expanded ground collider matches the
  visible land bounds.
- Added Cedar Green, the East Pier, Summit Overlook, Market Square and the
  downtown vehicle-service POI. District signs use voxel lettering.
- Indexed road and pedestrian adjacency once in WorldGraphService. The graph
  validator also checks building centers against physical roads and sidewalks.
- Added a no-teleport, real-input traversal for the five-district foot and van
  loops. Corrected the Harbor Road connector after the traversal found a
  house/sidewalk collision, and kept collision-test fixtures outside the
  enlarged island.
- Updated the performance probe to follow authored pedestrian links through
  address parking approaches instead of walking straight through buildings.

## Files and ownership

- `tools/world_data.py` owns bounds, five districts, 44 lots, landmarks, road
  and pedestrian graph source, POIs, recovery anchors and collision validation.
- `tools/build_town.py` creates the island, address exteriors, district props,
  signs and assembled town from that catalog. `tools/build_art.py` continues to
  own the shop/character/vehicle assets; both builders accept isolated
  `--output` roots.
- `scripts/services/world_graph_service.gd` owns graph loading and route
  queries. `scripts/services/world_registry.gd` continues to own active marker
  resolution. `scripts/game.gd` reads CustomerSlot for customer placement.
- `tools/validate_world.py`, `tools/check_town.gd`,
  `tools/world_graph_checks.gd`, `tools/phase10_route_checks.gd` and
  `tools/run_checks.py` provide the validation and acceptance commands.
- Generated town scenes contain 2,419 island, 1,771 address and 789 prop
  geometry pieces. The catalog has 440 directed van lanes and 2,270 pedestrian
  links.
- Updated `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md`,
  `docs/world_graph.dot` and `PHASE_PROGRESS.md`.

## Contracts for Phase 11

- Catalog schema version is 2. Preserve the five district IDs, stable lot and
  marker IDs, first-eight Marinara order, and the downtown shop/plaza transforms.
- Every active delivery address retains Door, Park and CustomerSlot Node3D
  markers, stable `district_id`/`lot_id`, and its catalog-linked access path.
- Road widths, actor clearance and van lane direction remain sourced from the
  catalog. Keep route estimates labeled as estimates; they do not model steering
  or measured driving time.
- Keep `tools/build_art.py` and `tools/build_town.py` staging outputs
  deterministic and source-identical.

## Route estimates

`tools/validate_world.py` reports graph-centerline distance and estimated time
using 4.2 m/s road speed plus an 8-second parking allowance. These are not
measured drive times:

| District | Addresses | Drive distance | Estimated trip |
|---|---:|---:|---:|
| Downtown | 8 | 28–36 m | 17–19 s |
| Cedar Grove | 9 | 139–214 m | 43–61 s |
| Harborfront | 9 | 75–159 m | 28–48 s |
| Summit Hill | 9 | 94–130 m | 32–41 s |
| Market Works | 9 | 102–166 m | 34–50 s |

## Validation evidence

- `tools/validate_world.py` — 44 addresses, five districts, 320 × 240 m,
  440 directed lanes and 2,270 pedestrian links; no topology or physical layout
  validation errors.
- `tools/phase10_route_checks.gd` — 30 checks, 0 failures. Pip walks the POI
  loop and reaches the van with regular movement input; the van then completes
  the five-district road loop with regular steering input and stays supported.
- Rendered capture plan `tools/plans/phase10-world.json` — aerial overview and
  one street view per district, captured on the NVIDIA RTX 3050 at 1920 × 1080
  with Forward+. All six images were inspected. Evidence is under
  `.godot/phase10-evidence/rendered/phase10-world-18984-1822676/`.
- Rendered performance probe at 1920 × 1080 HIGH, VSync/frame cap off,
  900-frame warmup and 1,800 samples: NVIDIA GeForce RTX 3050 6GB Laptop GPU;
  4.85 ms median, 5.61 ms p95/p99, 0 hitches, 730 maximum draw calls,
  26,085 primitives, 5,829 nodes, 113.3 MiB static memory, 0.68 ms median
  physics and 0 timed-out legs. Raw report:
  `.godot/phase10-evidence/perf-high.json`.
- The art and town builders each ran into `.godot/phase10-stage-a/` and
  `.godot/phase10-stage-b/`. All 11 generated files matched across stages and
  both stages matched the working generated files.
- Full integrated suite: `python tools/run_checks.py --godot .\godot-engine\Godot_v4.7.2-stable_win64_console.exe` — **55 commands passed**, including deterministic replay pairs and all negative-fixture checks. Evidence is under `.godot/test-runs/suite-1792352602912724300-3904/`.
- World graph regression: **186 checks, 0 failures**; Phase 10 real-input traversal: **30 checks, 0 failures**.
- `git diff --check`: passed after the final tracker and handoff edits.

## Known limitations and remaining polish

- New buildings are blockout exteriors, not interiors; only Pip's Pizza is
  enterable. Some blocks remain open and sparse so roads, lots and sightlines
  are easy to verify.
- Summit Hill has an overlook and district roads but no graded terrain yet.
  District art, vegetation, traffic, pedestrians, weather and route guidance
  remain later-phase work.
- Graph checks cover every address's route and access markers. The no-teleport
  traversal proves the district loop and POIs, not an individual physical
  doorstep delivery at all 44 lots. Route-time values are estimates.

## Player controls

No player controls changed in Phase 10.

## Next phase entry point

Read `implementation-prompts/phase-11-build-map-and-route-guidance.md` and this
handoff. Use the stable district, address and road catalog to build the map and
route-guidance presentation; do not replace the measured physical network with
a visual-only map.
