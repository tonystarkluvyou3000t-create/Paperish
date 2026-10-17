# Phase 11 — Build map and route guidance
Read rules and 09–10 handoffs. Replace straight-line-only guidance with readable navigation for the larger town.

## Result
Players can plan a delivery route, identify streets/addresses and recover from missed turns. Guidance follows legal roads and ends at useful parking, then switches to the customer on foot.

## Milestone A — Route service
Use the road graph for van travel and pedestrian graph for final approach. Produce ordered route segments, total distance and conservative travel estimate. Respect directed lanes, turn restrictions, road closures and the player's current legal connection. Snap to plausible edges without jumping across water/buildings. Recompute on meaningful deviation or topology change rather than every render frame.

For unreachable targets show an actionable state; do not draw a misleading line through a building or silently choose a different customer. Map routing is advice rather than autopilot. Order budgets use route estimate plus preparation-independent parking/exit/walk/handoff allowances.

## Milestone B — Map presentation
Add a minimap or compact navigation panel showing player/van heading, streets, active target, shop and relevant POIs. Add a full town map with district names, readable address search/list, legend, zoom/pan, current tickets, route selection and optional waypoint. Use road/world data as the map source to avoid a stale manually drawn image.

Map input consumes gameplay input and pauses simulation via the shared modal service. Support mouse and controller navigation, large text and color-independent target symbols. Distinguish accepted jobs, selected route and optional exploration markers.

Add short turn guidance and remaining road distance; avoid constant noisy prompts. In final approach, point to the correct entrance rather than house center. Show a van marker when Pip walks away. Keep a compact compass option for players who prefer less HUD.

## Milestone C — Recovery and batch planning
Support selecting an active ticket from up to three jobs, ordering the visible stop list and comparing estimated arrival windows. Do not automatically optimize away the player's choice. Late/missed turns should reroute without a penalty unrelated to time.

Provide an unstuck action in pause that returns the van/player to a validated recovery anchor, with transparent time/cost policy disabled in tutorial/free roam. Preserve cargo and avoid duplicated payout or teleporting across locked story gates.

## Acceptance
Find and complete deliveries in each district using UI alone. A route never uses an illegal edge or crosses water. Force a road closure and verify rerouting or explicit unreachable response. Walk from parked van to the correct door. Miss two turns and recover. Test map pause, nested settings and controller selection. Compare estimates with measured safe drive times and record error before tuning.

Handoff includes route result schema, invalidation events, map controls, recovery policy and integration hooks for traffic/weather/events.
