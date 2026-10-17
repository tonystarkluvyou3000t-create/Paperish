# Phase 12 — Populate pedestrian life
Read rules and 06/09–11 handoffs. Add people with behavior rather than stationary copies scattered everywhere.

## Result
The town contains residents, staff, shoppers and recurring customers who walk legal routes, pause at meaningful places and react safely to the van. Target roughly 20–35 active pedestrians near the player and at least 12 authored recurring identities; exact density is tunable.

## Milestone A — Character/navigation slice
Create a reusable voxel NPC with varied silhouette, clothing, skin/hair palette and simple idle/walk/talk gestures. Reuse Pip's style, not Pip's delivery controller verbatim. Implement explicit idle, walk-to, wait, converse and yield/recover states with bounded transitions.

Use pedestrian graph/navigation and local avoidance. Validate radius/height against pavement, doors and benches. Detect stuck movement by progress, attempt bounded replans, then relocate only off-camera to a valid anchor with a debug reason. Do not snap visibly through obstacles.

Define a safe vehicle contact protocol now: no arbitrary apply_push dispatch, no ragdoll requirement. Pedestrians should stop/yield before danger, and collisions have readable non-graphic feedback. Player contact should not pin Pip in a doorway.

## Milestone B — Roles and routines
Author shop staff, harbor worker, market vendor, mechanic, a regular customer and other recurring residents with stable IDs, name, dialogue entry and home/work/idle anchors. Add background walkers visiting square, park, shop and waterfront. Routines use phase labels now; phase 14 will bind them to the clock.

Customer appearance at handoff must resolve the authored identity. Do not spawn two copies if that NPC is already walking nearby; use an availability/representation policy (doorstep proxy or rendezvous) and document it. Conversations temporarily reserve the NPC and release them on completion/cancel.

## Milestone C — Population management
Set district density and maximum active/pathfinding counts. Stagger path queries and behavior updates. Spawn/despawn background NPCs out of view, never in front of a moving van or blocking the only exit. Persistent characters retain identity/relationship flags independent of their scene instances.

Prepare a crossing reservation API for phase 13 rather than teaching pedestrians to ignore road traffic. Add debug views for path, role/state and stuck recovery.

## Acceptance
Watch a seeded five-minute street simulation: NPCs walk, idle and converse without accumulating at one node. Speak to a named person then deliver to that customer without duplicate identities. No one walks through buildings/pond or permanently blocks the counter. Test crowd at doorway, player pushing past and van approaching. Check bounded population/path work and absence of nonexistent apply_push errors. Core delivery remains possible.

Handoff: NPC identity data, navigation states, crossing API, population budget and rendered evidence from two districts.
