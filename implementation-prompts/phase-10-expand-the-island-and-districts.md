# Phase 10 — Expand the island and districts
Read rules and 09 handoff. Implement a substantially larger connected world, not an enlarged empty ground plane.

## Result and targets
Aim for approximately 320 × 240 m (versus existing 68 × 56 m), five distinct districts and at least 40 genuinely reachable delivery addresses. Measure actual extents and address counts. Keep the original pizza plaza as a recognizable central landmark.

## Milestone A — Connected blockout
Lay out a compact downtown/shop district, leafy residential area, waterfront/harbor, hillside neighborhood and market/industrial edge. Give each a clear landmark and at least two connections where possible. Main routes form useful loops; add one or two bridges/underpasses only if collision and grade transitions can work reliably.

Plan main roads, side streets, shortcuts on foot, parking, crossings, safe shoulders and boundary treatment before decorating. Target typical safe delivery drives of roughly 30–120 seconds depending on district, to be tuned later. Keep home doors close enough to sensible parking to avoid tedious walks. Add readable street names and address ranges.

Implement low-detail blockout for all districts first; drive the whole network and resolve narrow turns, dead ends, steep slopes and vehicle grounding before detailed art.

## Milestone B — Addresses and landmarks
Author 40+ unique address records distributed across districts, including a few non-house deliveries (harbor office, market stall, workshop). Each needs an interaction entrance, parking point, approach path, customer slot and district label. Vary lots/building silhouettes without duplicating unreadable door placements.

Add a public square, overlook, pier, small market and vehicle service point as POIs with purpose for later story/side activity phases. Only the shop must be fully enterable now; avoid spending scope making every house an interior. Use accessible thresholds for routine doorstep deliveries.

## Milestone C — World limits and budgets
Expand collision/support geometry to match visible land and deliberate water boundaries. Use shoreline, terrain, fences or gates instead of mysterious invisible walls. Place reset/recovery anchors on legal roads in each district.

Organize by district/chunks with sensible visibility ranges. Do not immediately enable aggressive scene unloading that invalidates active order references; keep registry handles stable. Profile representative draw calls/node counts and tune generator batching where straightforward. Keep debug overlays available but off by default.

## Acceptance
Traverse a loop through all five districts on foot and by van where allowed, without teleport or falling through seams. Every address passes graph reachability and has a usable safe exit/approach. No decorative layout blocks the only route. Capture an aerial overview and one street view per district. Measure world bounds, generated counts and current performance honestly; do not claim an FPS target without rendering measurements. Rebuild in staging and confirm source/output consistency.

Handoff: district/address catalog, boundaries/recovery points, route measurements and areas intentionally left for polish.
