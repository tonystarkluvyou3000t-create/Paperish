# Phase 07 — Build the pizza shop handoff
Read rules, audit and 06 handoff. This phase replaces the existing behind-the-shop radius pickup with a believable staffed pickup sequence.

## Result
Pip walks through a clear entrance, speaks to shop staff, checks the ticket and receives visible pizza boxes at a service counter. The back yard remains a service area, not the main receiving mechanic.

## Inspect
tools/build_art.py shop() creates a solid shop shell and one box collider; tools/build_town.py town_scene() rotates the shop PI and places PickupPoint locally at (0, .1, -3), behind the building in world space. Moving that marker alone does not make a usable shop.

## Milestone A — Enterable space
Modify the generator source to author a modest interior with a real doorway, floor, counter, kitchen/oven backdrop, pickup shelf and staff station. Split solid shell collision around openings; no full-building collider spanning the entrance. Keep geometry simple and readable. Ensure entrance, queue and turning areas fit Pip's capsule/camera. Keep the van outside with clear pickup parking. Add visible OPEN/PICKUP signage and warm counter lighting.

Use generated geometry plus runtime behavior scenes/components. Preserve/reconcile PizzaShop/PickupPoint for compatibility, but move gameplay ownership to actual counter interaction anchors. Test world rotation and marker positions after rebuild.

## Milestone B — Staff and order receiving
Create a shopkeeper/cook with idle and handoff feedback, named dialogue and role. Show a ticket containing order ID, address/customer, quantity and preparation status. Present at least ready/not-ready/collected states. Staff can prepare orders in the background later; for now use a short bounded preparation duration with visible feedback, not a long idle wait.

Only the assigned ready ticket can be collected. On confirmation: consume ready stock once, transfer boxes to Pip, update order state and start the delivery freshness/deadline. Never start a food countdown before the player receives it. In tutorial mode explain the next step; outside tutorial keep repeat pickup fast.

## Milestone C — Failure and presentation
Reject wrong counter side, obstructed staff, van-seated interaction, double collection and full hands. Cancelling a ticket or conversation leaves it available and unchanged. Show a physical stack appearing through a short handoff animation/sound; staff response uses the dialogue service. Handle timeout/cancel/restart so old shelf boxes cannot be collected for a new ticket.

Keep the service yard with crates/dumpster as world detail; remove misleading default pickup marker and instructions there.

## Acceptance
Walk from street into shop and back out without clipping; camera remains readable. Receive exactly the correct quantity from staff once. Wait near the building's back wall and press interact: no pickup. Verify ready state and ticket identity, cancelled dialogue, repeated E, restart during preparation and counter collision. Rebuild art/town in staging and rerun scenario; functionality survives. Capture exterior entrance, interior/ticket and visible handoff.

Handoff includes shop scene/generator changes, counter/staff IDs and receipt events used by phase 08.
