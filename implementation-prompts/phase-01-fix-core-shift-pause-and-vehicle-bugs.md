# Phase 01 — Fix core shift, pause, and vehicle bugs
Read IMPLEMENTATION_RULES.md and PROJECT_AUDIT.md first. Implement this phase only. Prerequisites: none.

## Result
The existing small delivery game must remain playable while its input, pause, vehicle and state transitions become reliable. Do not expand the town or add new gameplay systems yet.

## Inspect
scripts/game.gd (_unhandled_input, _toggle_pause, _start_shift, _new_order, _enter_van, _exit_van, _finish), scripts/player.gd, scripts/vehicle.gd, scenes/game.tscn and project.godot. Read B01–B05/B09 and R01/R02/R04/R05/R07/R11 in the audit.

## Milestone A — Session and input correctness
1. Reproduce Esc pause/resume with actual input. Put pause/resume handling on an always-processing owner. Keep physics, delivery clocks and world simulation paused. Do not mark the whole Game always-processing without also guarding its timers and descendants.
2. Centralize movement ownership: title/result -> neither actor; on foot -> Pip only; driving -> van only; paused/modal -> neither receives gameplay actions.
3. Make restart deterministic from title, active pause menu and results. Reset tree pause, avatar visibility/collider, driving mode, velocity, autopilot, timers, markers and camera state. Prevent duplicate starts.
4. Fix forced_house precedence. An explicitly forced repeated house is valid; random orders avoid immediate repeats only where more than one destination exists.
5. Derive displayed tips from authoritative remaining time in all avatar modes; avoid a stale driving tip or a hard-coded initial $8.

## Milestone B — Safe vehicle transitions
1. Reject entering/exiting during illegal states or above a small configurable stopped-speed threshold, with an explanatory prompt.
2. Probe candidate exits on both sides and rear using Pip's actual capsule size and world-space transforms. Require floor support, slope clearance and no blocking body. Exclude the source vehicle correctly; do not accept floor checks that hit its roof.
3. If every exit is blocked, keep the player seated and state unchanged. Never teleport inside a wall or outside the island.
4. Do not implement E as an instant brake. A valid stop should come from vehicle controls.
5. Resolve duplicate collider ownership deliberately. Add named collision constants/matrix comments. Replace arbitrary CharacterBody3D.apply_push dispatch with an explicit capability/type contract.
6. Test signed forward/reverse contact response before changing it; use actual travel direction for impact logic if reproduced.

## Milestone C — Guardrails
Validate houses, spawns and pickup references on startup; reject invalid world contracts with actionable diagnostics. Terminal states must cancel dev autopilot and stop new interactions, deadlines and movement. Ensure start/restart restores a seated player's body safely. Keep art and current payment rules unchanged except correctness fixes.

## Acceptance
- Three Esc pause/resume cycles work, with no timer or actor movement during pause.
- Walking in each direction leaves a parked van stationary; driving does not move hidden Pip.
- Exit while fast is rejected; clear left/right exits succeed; fully blocked exit is rejected.
- Force house 0 twice; both selections are 0. Random selection still supports one house without looping.
- Finish with active autopilot: actor motion and order progression stop.
- Repeat title/start/restart/result paths without invisible player, stale prompt or duplicate reward.
- Run baseline engine/resource checks. Record the reproduction and result for each fixed audit ID; defer full reusable regression infrastructure to 02.

Write a phase handoff with exact input/pause/collision decisions. Do not claim safe exit verified using only a distance check.
