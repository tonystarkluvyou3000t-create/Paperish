# Phase 04 — Add player-controlled cameras
Read shared rules and 03 handoff. Implement camera control only; preserve delivery gameplay.

## Result
The player can comfortably look around on foot and while driving, zoom, recenter, and enter an independent free camera. The camera must remain usable in narrow streets and the upcoming shop interior.

## Inspect
scripts/camera_rig.gd has fixed height/distance, title orbit and automatic van following. Its point ray plus minimum 3 m offset can cross nearby blockers. Input defaults also live in tools/setup_project.gd.

## Milestone A — Orbit and chase
Add named mouse/gamepad camera actions, configurable sensitivity/invert Y, bounded pitch and zoom. Suggested defaults: right-mouse drag to orbit with visible cursor outside drag, wheel zoom, C recenter, gamepad right stick. Preserve WASD camera-relative walking and van-local steering. Use frame-independent input; mouse deltas should not be multiplied twice by delta.

Provide on-foot orbit and driving chase modes. Manual driving look temporarily suspends automatic recentering, then returns smoothly after a configurable idle grace. Clamp distance/pitch per mode and interpolate transitions without abrupt rotations. Menu/dialogue focus consumes camera actions first.

## Milestone B — Collision and visibility
Use a spring arm or shape sweep representing camera volume, excluding the followed actor and owned colliders. Resolve the final smoothed position against walls; do not smooth through the obstacle after computing a valid endpoint. Handle starting inside geometry, close rear walls, low awnings and large frame deltas. Retain a readable view of Pip/pizzas and show a subtle occluded-target aid if needed. Avoid full-building transparency unless measurement justifies it.

## Milestone C — Free camera
Add F as a documented toggle with distinct remappable free-camera controls: move, rise/fall, speed modifier, mouse look and return. Entering freezes gameplay, AI and deadlines through the shared modal service while camera controls remain active. Save previous target, yaw/pitch, distance, mouse mode and actor mode. Returning restores them safely; no van movement from camera WASD. Limit travel to a generous world envelope. Do not confuse this feature with developer-only capture.gd camera teleport.

Add a brief control hint and mode label. Support cancel/back and prevent toggling during load or conflicting modals. Keep title orbit independent of user gameplay settings.

## Acceptance
Rendered evidence: orbit around Pip, van chase/manual rear view, close building corner, shop-like low roof and independent aerial free camera. Test pause/unpause and focus loss while dragging, toggling free camera when driving and returning without moving the van. Check minimum/maximum zoom and inverted Y. Bindings survive setup_project regeneration and options reload. Headless regressions confirm modes do not change order deadlines while frozen.

Handoff includes controls, camera mode API, collision masks, modal behavior and screenshots. Do not declare camera collision solved based on a single unobstructed view.
