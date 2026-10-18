# Phase progress

**Completed:** 4 of 24 phases

**Remaining:** 20 phases

**Current phase:** 05 — Build menus and settings (not started)

Phase completion follows the handoffs in `implementation-prompts/handoffs/`. A phase counts as complete only when its handoff is marked verified.

| Phase | Title | Status | Evidence / notes |
|---:|---|---|---|
| 01 | Core shift, pause, and vehicle correctness | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-01.md). Headless acceptance verified; rendered/manual play remains unrun. |
| 02 | Deterministic regression checks | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-02.md). |
| 03 | Separate gameplay services and data | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-03.md). Handoff says Phase 04 has not started. |
| 04 | Add player-controlled cameras | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-04.md). 58 headless camera checks plus a replayed camera plan; rendered shots verified by inspection. Caveat: the shop awning is visual-only, so the low-roof pull-in clamps on the facade instead. |
| 05 | Build menus and settings | NOT STARTED | |
| 06 | Unify interactions and dialogue | NOT STARTED | |
| 07 | Build the pizza shop handoff | NOT STARTED | |
| 08 | Implement orders and physical cargo | NOT STARTED | |
| 09 | Author world and road graphs | NOT STARTED | |
| 10 | Expand the island and districts | NOT STARTED | |
| 11 | Build map and route guidance | NOT STARTED | |
| 12 | Populate pedestrian life | NOT STARTED | |
| 13 | Add traffic and road rules | NOT STARTED | |
| 14 | Create day-night lighting and schedules | NOT STARTED | |
| 15 | Add weather with gameplay effects | NOT STARTED | |
| 16 | Improve driving and delivery condition | NOT STARTED | |
| 17 | Create fair delivery hurdles | NOT STARTED | |
| 18 | Write and implement the island story | NOT STARTED | |
| 19 | Add progression and side activities | NOT STARTED | |
| 20 | Enrich world art and animation | NOT STARTED | |
| 21 | Polish sound, onboarding, and accessibility | NOT STARTED | |
| 22 | Persist campaign and resume safely | NOT STARTED | |
| 23 | Balance pacing and optimize performance | NOT STARTED | |
| 24 | Verify and package the complete game | NOT STARTED | |

## Change log

| Date | Change |
|---|---|
| 2026-10-18 | Added the project instructions and initial tracker from the verified Phase 01–03 handoffs. |
| 2026-10-18 | Committed the project instructions and tracker, then branched to `implementation` for phase work. |
| 2026-10-18 | Deleted the fully merged `codex/implement-phases-01-03` branch (local and origin). |
| 2026-10-18 | Phase 04: rewrote `scripts/camera_rig.gd` (foot orbit, driving chase with idle-grace recenter, swept collision boom, occlusion aid, free camera with `free_camera` modal, focus-loss handling); added `cam_*`/`free_*` input actions to `tools/setup_project.gd` and regenerated `project.godot`; wired camera hint/mode through HUD, snapshot, SessionInput and ActorController. |
| 2026-10-18 | Phase 04: added `tools/phase04_checks.gd` (58 checks) and `tools/plans/camera.json` (77 steps, 12 assertions, 7 shots); `tools/run_checks.py` now regenerates settings via `setup-project`, runs the camera checks and replays the camera plan; full suite passes 32 commands (Phase 01 137/0, Phase 03 44/0, Phase 04 58/0). Also fixed Phase 01 checks for Godot 4.7 device IDs. |
| 2026-10-18 | Phase 04: rendered evidence (7 PNGs inspected) under `.godot/phase04-evidence/rendered/`; updated `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md`; wrote the Phase 04 handoff. Caveat recorded: the shop awning has no collider, so the low-roof shot clamps on the facade. |
