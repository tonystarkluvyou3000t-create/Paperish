# Phase 13 — Add traffic and road rules
Read rules and 09–12 handoffs. Build a small reliable traffic simulation before increasing car counts.

## Result
Cars travel directed lanes, stop for junctions/crossings and react to Pip's van. Target roughly 8–16 nearby moving vehicles at normal density, plus parked vehicles; tune to actual road capacity.

## Milestone A — Lane-following cars
Author at least three lightweight voxel vehicle variants with correct wheel/forward conventions and recognizable brake/head lights. Use lane paths with curvature/speed limits. Vehicles accelerate/brake smoothly, follow at safe gaps and negotiate corners without cutting sidewalks.

Use forward sensing with closing speed and stopping-distance awareness, not a fixed radius that works only at one speed. Distinguish static obstacles, player van, NPC cars and pedestrians. Contact handlers must tolerate any supported actor type and avoid double penalty dispatch through duplicate colliders.

Start with two cars on one loop, then add an intersection. Do not populate the entire town until these work.

## Milestone B — Junctions and crossings
Implement a simple explicit conflict/reservation scheme: stop-line queues, right of way, traffic light phases where authored and clearance before next phase. Reserve intersection space so vehicles do not enter a blocked exit and gridlock it. Pedestrian crossings request safe gaps/phases through the phase 12 interface.

Choose and document one driving side across all roads. Add corresponding stop signs, lane markings, signals and tutorial cues. Player road-rule violations should first give legible warnings; exact consequences belong to difficulty/economy phases. Traffic must never trap the van permanently at the shop.

## Milestone C — Recovery, population and tests
Detect deadlocks/stuck cars by lack of progress; recover through bounded replan/yield and only despawn off-camera as last resort. Spawn only on legal clear lane positions with adequate distance from the player. Parked cars occupy authored bays without blocking deliveries. Support emergency yielding/horn reactions without letting H erase all difficulty.

Keep route behavior driven by road graph and closures. Stagger sensors/path updates; maintain population cap and density settings. Prepare time-of-day density hooks for 14 and wet stopping-distance modifiers for 15/16.

## Acceptance
Run seeded ten-minute simulations at a T-junction, four-way crossing and busy shop loop. Cars stop behind one another, give crossings safe gaps and clear intersections. Player blocks a lane, reverses into traffic and parks near a junction: traffic responds or recovers without an unrecoverable queue. No cars spawn inside the player, drive into water or call nonexistent push methods. Repeat a delivery through traffic using real controls. Record max active count, stuck/deadlock counts and representative frame cost.

Handoff includes lane/junction protocol, collision matrix, driving-side decision, density controls, recovery rules and seed. Do not declare traffic finished based only on moving decoration.
