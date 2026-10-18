# Phase progress

**Completed:** 5 of 24 phases

**Remaining:** 19 phases

**Current phase:** 06 — Unify interactions and dialogue (not started)

Phase completion follows the handoffs in `implementation-prompts/handoffs/`. A phase counts as complete only when its handoff is marked verified.

**Reference machine:** RTX 3050 6 GB laptop (95 W), 1920 × 1080, Forward+ renderer, HIGH quality preset. Locked by the [Phase 05b handoff](implementation-prompts/handoffs/phase-05b-render-target.md) before phase 06; the 1080p baseline lives in `tools/perf_probe.gd`.

| Phase | Title | Status | Evidence / notes |
|---:|---|---|---|
| 01 | Core shift, pause, and vehicle correctness | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-01.md). Headless acceptance verified; rendered/manual play remains unrun. |
| 02 | Deterministic regression checks | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-02.md). |
| 03 | Separate gameplay services and data | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-03.md). Handoff says Phase 04 has not started. |
| 04 | Add player-controlled cameras | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-04.md). 58 headless camera checks plus a replayed camera plan; rendered shots verified by inspection. Caveat: the shop awning is visual-only, so the low-roof pull-in clamps on the facade instead. |
| 05 | Build menus and settings | VERIFIED | [Handoff](implementation-prompts/handoffs/phase-05.md). 251 headless menu/settings/free-roam checks (grew from 214 with the Phase 05b render-target rows), a three-process preferences persistence probe and a replayed menu plan (18 assertions); 13 rendered shots at 100/125/150 % UI scale inspected, re-shot at 1920 × 1080 in Forward+ after Phase 05b. Caveats: menu feel judged from rendered shots, not a human session; the Phase 04 awning caveat is unchanged. |
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
| 2026-10-18 | Phase 05: added `scripts/ui/` (`menu_layer.gd` pooled screens + stack/focus/back, `ui_factory.gd` theme + scroll wrapper, `options_screen.gd`, `controls_screen.gd`), `scripts/services/settings_service.gd` (`user://settings.cfg`, `value(key)`, per-key validation, live apply) and `scripts/services/input_bindings.gd` (remap serialization, conflicts, prompts). Game builds the menus/settings, owns `handle_back()` and executes `menu_action`; SessionInput owns the single Esc back stack and the `R` restart rules; HUD keeps gameplay furniture only and clears toasts off-gameplay; SessionService gained the `roam` mode with dormant shop/doors; OrderService tracks base/pizza/tip totals for the results itemization. |
| 2026-10-18 | Phase 05: `tools/setup_project.gd`/`project.godot` moved `free_down` from **E** to **CTRL** (duplicate with `interact`); `tools/capture.gd` gained `menu`/`setting` steps, the `timer_visible` field, richer logical records and hardware-faithful key events; `tools/phase01_checks.gd` keys set the logical keycode too. |
| 2026-10-18 | Phase 05: added `tools/phase05_checks.gd` (214 checks), `tools/settings_probe.gd` (write/read/clean across processes) and `tools/plans/menu.json` (62 steps, 18 assertions, 13 shots); `tools/run_checks.py` wires all three plus `unknown-menu`/`unknown-setting` negatives. Full suite passes 40 commands (Phase 01 137/0, Phase 03 44/0, Phase 04 58/0, Phase 05 214/0); rendered shots at 100/125/150 % UI scale inspected; docs and the Phase 05 handoff written. |
| 2026-10-18 | Phase 05b (owner decision, not a roadmap phase): locked the render target — Forward+ on the RTX 3050 6 GB laptop, 1920 × 1080 default window, 4 × MSAA, a 4096 shadow atlas at filter quality 3, and an AgX/SSAO/glow Environment (`tools/setup_project.gd` + `scenes/game.tscn`). `SettingsService` gained `video/quality` (a macro that writes the fine keys), `video/msaa`, `video/ssao`, `video/glow` and `video/frame_cap` with per-key validation and apply paths; Game applies the scene-owned Environment keys; the options screen refreshes rows changed elsewhere, refreshes on activation and scales its list to the logical view. |
| 2026-10-18 | Phase 05b: added `tools/perf_probe.gd` (fixed rendered route, frame-time percentiles, hitches, draw calls/primitives/nodes/memory; scratch settings file) plus the `perf-harness` suite command (now 41 commands). Recorded the reference baseline: median 4.68–4.76 ms, p99 6.68 ms, 0 hitches, ~1 000 draw calls, 2 073 nodes at 1920 × 1080 HIGH on the RTX 3050; rendered Forward+ evidence re-shot (camera plan 6 shots, menu plan 13 shots). |
| 2026-10-18 | Phase 05b: `tools/phase05_checks.gd` grew to 251 checks (preset → fine keys, MSAA/SSAO/glow/frame-cap apply paths, shadow-distance mapping, vertical card fit at 150 %, 1080p list room, shipped project settings); amended the phase-20/23 prompt lines that still assumed Compatibility and 1280 × 720, and updated `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md` and the phase-05b handoff. Suite: 41 commands, Phase 05 251/0. |
