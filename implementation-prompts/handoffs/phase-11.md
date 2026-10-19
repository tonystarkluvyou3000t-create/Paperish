# Phase 11 — Build map and route guidance
Status: VERIFIED

## Implemented behavior

- Added `RouteService` (`scripts/services/route_service.gd`), one route authority
  that plans from the authored graph: directed van lanes from a legal entry to
  the address parking pad, then the pedestrian leg from that park point — or from
  the actor, when already on foot — to the door. Lane direction, turn
  restrictions, closed lanes and the player's current legal connection come from
  `WorldGraphService`; nothing is drawn through water or buildings.
- Published one ordered result dictionary (`schema()` lists every key): labelled
  segments, drive/walk polylines, per-leg distances and conservative seconds,
  parking/walk/exit/handoff allowances, the published ETA, the park position and
  the door position. Unreachable targets return an actionable state
  (`code`/`reason`/`label`) instead of a misleading line, and the service never
  silently picks another customer.
- Guidance is derived from the same result: the leg the actor owns (`drive` while
  seated, `walk` on foot) with a short manoeuvre line (`TURN LEFT/RIGHT ON
  <street>`, `TURN AROUND`, `CROSS THE ROAD`, `PARK AT <address>`, `WALK TO
  <address>`, `DOOR — INTERACT`, `CONTINUE ON <street>`, `NO ROUTE`) and the
  remaining distance. The van marker stays on the map and minimap while Pip walks.
- Route recomputation is event-driven, never per frame: target change, closures
  or topology change, van/actor deviation past `route_deviate_m` (22 m) /
  `route_deviate_foot_m` (12 m), and driving/foot switches, with a
  `route_recompute_cooldown` (0.8 s) so a missed turn reroutes once, without a
  penalty unrelated to time. `last_reason` and `recomputes` expose both.
- Order budgets use `estimate_from()` plus `deadline_min_slack` (12 s), so long
  routes stretch their own deadline while short hops keep the earlier pacing.
  `INF` estimates refuse ticket creation instead of issuing an impossible run.
- Added `MapModel` (static districts, roads, addresses, POIs, water, recovery
  anchors — built once from the layout; no hand-drawn image) and `MapView`, the
  shared renderer used by both the full map and the HUD minimap. Markers are
  shapes with a legend, so targets read without colour.
- Added `MapScreen` as a pooled menu screen: the stop list with per-stop leg,
  cumulative, arrival and window comparison; row ordering; route selection; zoom,
  pan, follow and waypoint controls; the unstuck button. Every write goes through
  Game (`map_select_order`, `map_move_stop`, `map_set_waypoint`,
  `map_clear_waypoint`, `unstuck`); the screen never mutates orders or session
  state itself.
- The map is a pause reason (`map`) in the shared modal service, so it consumes
  gameplay input, stacks over the pause menu and returns to it when closed. The
  HUD card follows `hud/navigation` (`map`, `compass`, `off`) and shows nothing
  without a live route.
- Added the recovery policy: `unstuck` moves the van and Pip (or only Pip on
  foot) to the nearest authored `recovery:*` anchor and re-faces them along a
  legal lane. It charges each running ticket a flat `unstuck_time_cost` (15 s) off
  its remaining clock, floored at `unstuck_min_remaining` (3 s), never to zero and
  never extending another ticket. Cargo, payouts and strikes are untouched, and
  free roam costs nothing.
- Water is authored data now (`tools/world_data.py` `WATER_SURFACES`, catalog
  schema 3), and the layout emits `water_surfaces`, so the map and the route
  legality check use the same source as the island geometry.
- Controller menus now work end to end: `confirm` carries PAD A and `pause`
  carries PAD START (both still rebindable), so a focused map row/action can be
  pressed and backed out of with a gamepad.

## Files and ownership

- `scripts/services/route_service.gd` owns planning, guidance, stop plans,
  waypoints, closures and the recovery policy surface. `scripts/services/
  world_graph_service.gd` owns graph queries (`vehicle_route`,
  `nearest_legal_entry`, `pedestrian_nodes_near`, `water_surfaces`).
- `scripts/ui/map_model.gd`, `map_view.gd` and `map_screen.gd` own presentation;
  `scripts/game.gd` owns the map/menu wrappers, `_sync_navigation`, the budget
  hook and the snapshot's `nav_*`/`route_*`/`map_open`/`waypoint_set` fields.
  `scripts/hud.gd` owns the navigation card; `scripts/ui/menu_layer.gd` owns the
  reason stack and menu ids (`map` aliases `open_map`).
- `tools/world_data.py` `WATER_SURFACES`, `tools/build_town.py` and the rebuilt
  layout own the water surfaces; `tools/setup_project.gd` and `project.godot`
  own the `map` action (M / PAD Y) and the new pad buttons.
- `tools/phase11_checks.gd`, `tools/phase11_route_checks.gd`,
  `tools/plans/map.json`, `tools/plans/nav-panel.json`, `tools/capture.gd`,
  `tools/perf_probe.gd` and `tools/run_checks.py` provide the acceptance
  commands. `tools/phase07_checks.gd`'s doorway walk is now budgeted instead of
  frame-exact (see the note in `PHASE_PROGRESS.md`).
- Updated `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md` and
  `PHASE_PROGRESS.md`.

## Contracts for Phase 12 and later

- **Route result schema** — keep the keys listed by `RouteService.schema()` and
  the guidance keys (`reachable`, `leg`, `hint`, `detail`, `maneuver`,
  `maneuver_distance_m`, `maneuver_text`, `remaining_m`, `progress_m`, `total_m`,
  `eta_seconds`, `target_address`, `address`, `driving`). The HUD, map, captures
  and checks read them; add, never repurpose.
- **Invalidation events** — recompute only on `target`, `closures`, `topology`
  (`invalidate()`), `deviation` and `actor` (driving/foot switch), plus
  `plan`/`cleared` for explicit calls. New systems (traffic, weather, events)
  should invalidate with their own reason rather than plan every frame: call
  `routes.set_closures(lanes, edges)` for closures, `routes.invalidate(reason)`
  for topology edits, and let `update()` own deviation.
- **Map controls** — `MapScreen` rows (▲/▼ order, ROUTE), `-ZOOM`/`+ZOOM`,
  `WHOLE TOWN`, `FOLLOW ME`, `SET WAYPOINT`/`CLEAR WAYPOINT`, `UNSTUCK`,
  `CLOSE MAP (M / ESC)`; map view drag pans, wheel zooms, right-click resumes
  following, and the `ui_*` actions move focus for a gamepad. `map` opens/closes
  while a shift runs; the screen is reachable from the pause menu's TOWN MAP
  button and the capture step `{"do": "menu", "id": "map"}`.
- **Recovery policy** — 15 s flat per running ticket, 3 s floor, never zero,
  never extending; anchor-based, always re-faced to a legal lane; disabled in
  roam; cargo/payout/strikes unaffected. Any new cost must go through
  `OrderService.apply_recovery_cost()`.
- **Integration hooks** — `routes.configure(graph, balance)`,
  `route_changed` (payload `{reason, reachable, address_id}`),
  `set_stops([{order_id, address_id}])`, `set_target(address_id)`,
  `update(delta, driving, van, actor)`, `stop_estimates(van_pos, remaining)`,
  `estimate_from(pos, address_id)`, waypoint API, and the snapshot fields
  `nav_*`, `route_target`, `route_recomputes`, `plan_ids`, `route_points`,
  `drive_points`, `walk_points`, `ticket_positions`, `waypoint_map`,
  `unstuck_label`.

## Measured drives versus published estimates

`tools/phase11_route_checks.gd` drives each district's longest reachable address
with ordinary throttle and steering capped at the conservative speed, then exits
and walks the pedestrian leg to the door. `drive_estimate` is
`route.drive_seconds`, `eta` the published guidance estimate including
allowances, and `walk_gap` the distance left to the door marker when the walk
stops. No estimate was tuned after measuring: every measured drive stayed well
inside the published ETA, and the largest drive-estimate error was 0.1 s
(Downtown, ratio 1.01).

| District | Address | Drive estimate | Measured | Ratio | Published ETA | Walk gap |
|---|---|---:|---:|---:|---:|---:|
| Downtown | 2 Marinara Way | 9.1 s | 9.2 s | 1.01 | 23.8 s | 1.0 m |
| Cedar Grove | residential 21 | 51.3 s | 50.9 s | 0.99 | 66.0 s | 1.0 m |
| Harborfront | waterfront 39 | 38.2 s | 36.4 s | 0.95 | 52.9 s | 1.1 m |
| Summit Hill | hillside 41 | 31.5 s | 29.1 s | 0.92 | 46.2 s | 1.0 m |
| Market Works | market 59 | 40.0 s | 37.8 s | 0.94 | 54.6 s | 1.0 m |

## Validation evidence

- `tools/phase11_checks.gd` — **98 checks, 0 failures**: route legality (no water
  or building crossings), closures (reroute or explicit unreachable), turn
  vocabulary, deviation and mode-switch recomputation counts, stop plans and
  windows, unstuck policy and floor, budget slack, map modal/screen behaviour, the
  UI-alone pass (real map buttons: ROUTE, zoom, waypoint, UNSTUCK, back to pause),
  the HUD card in all three display modes, and the controller pass (real gamepad
  events moving focus, pressing a focused row, restoring the routed ticket).
- `tools/phase11_route_checks.gd` — **119 checks, 0 failures**, including the
  table above: every measured drive agrees with the game's own deadline clock, and
  every district's walk from the parked van ends 1.0–1.1 m from its door with the
  live hint on `DOOR — INTERACT`.
- Rendered capture `tools/plans/map.json` (10 assertions) and
  `tools/plans/nav-panel.json` (9 assertions), captured windowed on the RTX 3050
  at 1920 × 1080 Forward+: minimap with a live route, the full map over a paused
  world, and one route shown three ways (map, compass, off). All five images were
  inspected. Evidence is under `.godot/phase11-evidence/rendered/`
  (`map-27596-1874557/`, `nav-panel-14172-1714101/`).
- Locked-vantage performance A/B (`--perf-hold=1`, 300 warmup + 600 samples,
  1080p HIGH, VSync off): no ticket 6.04 ms median (repeat 7.36 ms), card off
  5.60 ms (repeat 5.89 ms), compass 6.88 ms, minimap 6.11 ms — all inside the
  session's 0.3–1.3 ms repeat spread with 0 hitches, so the display's per-frame
  cost is below this machine's noise floor. Draw calls are the stable price:
  920 (off) → 933 (compass) → 1,079 (minimap). Captured on battery with a busy
  desktop, so the times are deliberately not compared with the phase-10
  AC/idle baseline; raw reports are
  `.godot/phase11-evidence/perf/perf-hold-*.json`.
- Full integrated suite: `python tools/run_checks.py` — **62 commands passed**
  (`SUITE PASS: 62 commands; logical replays match`, evidence
  `.godot/test-runs/suite-1792403661695510100-20456/`), including the
  deterministic replay pairs for `map` and `nav-panel`, every negative fixture
  (with the new `bad-choice` setting value) and the `perf-harness` probe pass.
- `git diff --check` passed after the final tracker and handoff edits.

## Known limitations and remaining polish

- Guidance is advice, not autopilot: the van still needs real steering, and the
  estimates do not model the player's own throttle or traffic. The service knows
  authored topology, not other vehicles.
- Traffic, pedestrians, weather and event-driven closures are later phases; the
  map already has the hook (`set_closures`, `invalidate`) but nothing authors
  dynamic closures yet.
- The minimap redraws every frame. It is cheap on the reference GPU (below the
  noise floor, ~160 draw calls) but could be throttled to a few hertz later if a
  higher-density town needs the room.
- Address search on the full map is a readable list (stops, plan order and
  routed target), not a typed search field; districts, street names and Zoom make
  addresses findable.
- A saved `user://settings.cfg` from before this phase keeps its stored bindings,
  so an existing profile does not gain PAD A/PAD START until the bindings are
  reset in Controls; fresh profiles ship with them.
- Human play of the map and the controller path was not performed: the rendered
  evidence is automated, and the controller pass drives real gamepad events
  through the same code path rather than a physical pad.

## Player controls

- **M** (or PAD Y) opens and closes the town map while a shift runs; the pause
  screen's TOWN MAP button opens the same screen. `Esc`/PAD START backs out one
  layer at a time and the map returns to the pause menu it opened over.
- Map: drag to pan, wheel to zoom, right-click (or FOLLOW ME) to resume following
  Pip, SET WAYPOINT then click to place one, CLEAR WAYPOINT to remove it, ▲/▼ to
  reorder stops, ROUTE to select a ticket's route, UNSTUCK to pay the flat
  recovery cost.
- The HUD navigation display is switchable in **Options** (MAP + TURNS, COMPASS
  ONLY, OFF); controller users move focus with the d-pad/left stick, confirm with
  PAD A and back out with PAD START.

## Next phase entry point

Read `implementation-prompts/README.md` for the phase 12 prompt and this handoff.
The route schema, invalidation reasons, map controls, recovery policy and the
`nav_*` snapshot fields are the integration points for traffic, weather and
events; keep `RouteService` the single planning authority and re-invalidate rather
than plan per frame.
