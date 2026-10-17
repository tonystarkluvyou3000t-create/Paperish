# Phase 09 — Author world and road graphs
Read rules and 03/08 handoffs. Build authoring foundations before multiplying geometry.

## Result
World geometry, addresses, routes, pedestrian areas and traffic lanes come from coherent data. Generated output is reproducible and can be expanded without hard-coded eight-house assumptions.

## Inspect
tools/townkit.py owns small-island constants; build_town.py embeds house data, road strips, collision plane and edge walls. Runtime iterates direct Houses children. capture.gd contains fixed world coordinates. Audit every consumer of these assumptions.

## Milestone A — World data
Create a documented data source (Python data module, JSON or Godot resources) for districts, bounds, road segments/junctions, lots, address IDs, entrances, parking/service positions, POIs, spawns and decoration seed. Keep metadata semantic: address_id does not depend on a house's child index or cosmetic node name. Validate unique IDs and legal references before writing files.

Establish a WorldRegistry that resolves IDs to active runtime markers and emits registration changes. Adapt order selection, compass, capture fixtures and story entry points to it. Keep a compatibility path for existing eight destinations during migration.

## Milestone B — Traversal graphs
Author directed lane edges with width, speed class, turn permissions, junction ID and allowed vehicle type. Author a separate pedestrian graph or navigation regions with sidewalks, crossings, doors, interior thresholds and blocked surfaces. Connect them intentionally at crossings/parking, not by using road centerlines as sidewalks.

Provide graph queries for route length/travel estimate and nearest legal entry; handle disconnected/closed destinations explicitly. Store crossing and junction conflict data needed by traffic. Preserve +Z vehicle orientation in marker transforms.

Classify geometry: solid building, walkable ground, vehicle barrier, decorative foliage, pond/water and traversable doorway. Create a collision matrix and a navigation clearance check using actual actor dimensions. Visible fences and water should have deliberate consistent affordances.

## Milestone C — Build reliability
Allow staging output so generator tests can run without overwriting live scenes. Use stable seed streams and stable ordering. Add validation for overlapping roads/buildings, addresses with no reachable door, disconnected districts, narrow van turns, unsupported spawn/exit points and duplicate scene node paths. A second identical build must not create spurious geometry diffs.

Keep runtime behavior separate from decorative generator output; establish named runtime attachment anchors. Track counts of meshes/materials/colliders so growth is measurable.

## Acceptance
Current town regenerates and remains playable using IDs. Road graph reaches every current parking marker; pedestrian graph reaches every door/counter. A deliberately disconnected fixture fails validation. Rebuild twice in staging and compare relevant output. Add a diagram/debug overlay for road directions, sidewalks, IDs and blocked links. Verify original resource checks and new topology checks.

Handoff includes data schema, registry API, graph cost units, build/staging commands and collision/navigation conventions. Do not build the full large island until this gate passes.
