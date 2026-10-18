# Phase 04 — Add player-controlled cameras
Status: VERIFIED

## Implemented behavior

Delivery gameplay, ownership and pause semantics are unchanged; the player now
owns the view.

- On foot (FOLLOW) and driving (CHASE) share one rig: right-mouse drag or gamepad
  right-stick look, wheel zoom, **C** recenter, configurable sensitivity and
  inverted Y. Pitch and distance clamp per mode, each mode remembers its own
  zoom, and transitions ease instead of snapping.
- Manual driving look suspends automatic recentering; after `cam_recenter_grace`
  (1.2 s idle) the chase pose eases back behind the van.
- The boom is collision-aware: a sphere sweep (radius `cam_collision_radius`
  0.35 m, mask WORLD|VEHICLE, followed body excluded by RID) shortens the
  requested distance. Pull-in applies immediately; extension eases at
  `cam_extend_rate` and is capped by the current allowed length. A pivot that
  already overlaps geometry collapses to the mode minimum (1.1 m foot / 2.2 m
  chase) instead of exploding, and the 0.25 m skin is subtracted only when a
  sweep actually hits.
- Occlusion aid: FOLLOW only, when the boom is under 4.5 m the followed actor's
  meshes fade up to 0.55 transparency. No building transparency.
- Free camera (**F**): independent fly camera (WASD move, Q/E rise/fall, Shift
  boost, mouse/pad look) that freezes gameplay, AI and deadlines through the
  session modal reason `free_camera`. Travel is limited to a ±320 m envelope and
  y in [-8, 150]. Returning restores the saved target, mode, yaw/pitch, distance
  and mouse mode with a 0.35 s pose ease; camera WASD never moves the van.
- Hint/mode: the snapshot publishes `camera_mode` (title/foot/chase/free) and
  `camera_hint`; the HUD renders the free-camera controls line, and the title
  screen gained a controls line. The title orbit stays independent of gameplay
  camera settings.
- Focus loss mid-drag ends the drag and releases the captured cursor, then
  re-grabs only for the free camera. **Esc** is cancel/back for the free camera
  (it cannot stack pause); restart, session end or an external modal clear
  force-closes it.

## Files and ownership

| File | Change |
| --- | --- |
| `scripts/camera_rig.gd` | Rewritten: TITLE_ORBIT/FOLLOW/CHASE/FREE modes, smoothed yaw/pitch/boom, swept collision boom with start-overlap handling, occlusion fade, free camera + modal, focus-loss handling, `reset_state()` |
| `scripts/services/balance.gd` | New `cam_*` tuning block (sensitivities, invert, zoom step, per-mode distance/pitch min/max/default, recenter grace/rate, transition/extend/pitch-ease rates, collision radius/skin, per-mode minimum boom, fade start/end/max, free speed/boost/extent/floor/ceiling/return time) |
| `tools/setup_project.gd` | Generator of record for the new mouse/joypad events of every camera action |
| `project.godot` | Regenerated input map (content-identical except the new camera actions) |
| `scripts/game.gd` | `camera.configure(session, balance)`; snapshot gains camera fields |
| `scripts/services/actor_controller.gd` | Calls `camera.reset_state()` before repointing the target |
| `scripts/session_input.gd` | Esc exits the free camera instead of stacking pause |
| `scripts/hud.gd` | Free-camera hint label; decorative labels get MOUSE_FILTER_IGNORE; title controls line |
| `scripts/services/game_snapshot.gd` | `camera_mode` / `camera_hint` getters |
| `tools/capture.gd` | New `mouse_motion` step, generalized key/mouse action events, camera snapshot fields |
| `tools/phase04_checks.gd` | New 58-check headless acceptance suite |
| `tools/plans/camera.json` | New 77-step plan: assertions + 7 rendered shots |
| `tools/run_checks.py` | Runs `setup-project` regeneration, the camera checks and a deterministic `camera` scenario replay; negative-fixture expectation updated to `unknown keyboard/mouse action` |
| `tools/phase01_checks.gd` | Godot 4.7 device-ID fix (`event.device >= 0`) so the existing 137 checks pass on the bundled 4.7.2 engine |
| `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md` | Controls, camera ownership/modes and plan schema updates |

Only the redundant camera code was replaced; Phase 01/02/03 contracts and the
generated art/audio assets were left alone.

## Contracts for the next phase

`scripts/camera_rig.gd` (single owner of the player view):

- `enum Mode { TITLE_ORBIT, FOLLOW, CHASE, FREE }`, `const FREE_MODAL := &"free_camera"`.
- Modes derive from `session.flow` + ActorController's `target`/`driving`;
  `current_mode()` and `mode_name()` ("title"/"foot"/"chase"/"free") expose them.
- Commands: `configure(session: Node, balance: Resource)`, `reset_state()`,
  `apply_look(pixels: Vector2)`, `zoom_by(notches: float)`, `recenter_now()`,
  `enter_free() -> bool`, `exit_free() -> bool`, `toggle_free() -> bool`,
  `is_free() -> bool`, `free_camera_hint() -> String`.
- Read state for tests/read model: `yaw`, `pitch`, `distance_target`,
  `distance`, `boom <= allowed_boom`, `look_idle`, `target`, `driving`, `orbit`.
- Input actions (all remappable, generated by `tools/setup_project.gd`):
  `cam_orbit` (right mouse), `cam_zoom_in` / `cam_zoom_out` (wheel),
  `cam_recenter` (**C**), `cam_free` (**F**), `cam_left/right/up/down` (right
  stick), `free_forward/back/left/right/up/down/boost` (WASD, Q/E, Shift).
- Collision mask for the boom: `Layers.WORLD | Layers.VEHICLE`; the followed
  body's RID is excluded. The rig owns no order/session/actor state and is
  `PROCESS_MODE_ALWAYS` only so the free camera stays live while paused.
- Modal rules: free opens only from unpaused PLAYING and refuses to stack on
  another modal; while any other modal owns pause the rig ignores camera actions;
  restart/session-end/external clear force-closes it; `_exit_tree` restores the
  cursor. `Snapshot.camera_mode` / `camera_hint` are the only view-state fields
  published to HUD/Capture.

## Validation evidence

Engine: bundled `godot-engine\Godot_v4.7.2-stable_win64_console.exe`
(4.7.2.stable.official), Python 3.12.10, Windows. From the repository root:

```powershell
python tools/run_checks.py --godot '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'
```

Result: **SUITE PASS — 32 commands**, seed 20261018, including:

- `PHASE 01: 137 checks, 0 failures` (with the Godot 4.7 device-ID fix),
  `PHASE 03: 44 checks, 0 failures`, `PHASE 04: 58 checks, 0 failures`.
- `setup-project`: settings regenerated from the generator of record, exit 0
  (`project settings saved, err=0`); the camera checks then run against the
  regenerated input map, which also exercises `load_from_project_settings()`.
- `camera-1`, `camera-2` and `deterministic replay camera`: the plan replays to
  identical logical records, asserts 12 times and cleans up (no held actions,
  pause false, time scale 1).
- Town/art/RNG checks, both delivery plans and all deliberate failure fixtures.

Evidence: `.godot/test-runs/suite-1792312925127197500-22856/` (`summary.json`,
per-command logs, camera plan results); console log `.godot/suite-phase04.log`.

The 58 camera checks cover: bindings for mouse/joypad/wheel/keyboard; title-orbit
independence; look direction and inverted Y; min/max zoom clamps; recenter easing;
wall pull-in and eased extension; pivot-inside-geometry minimum boom and finite
position; occlusion fade in/out; modal gating (menu consumes look/zoom, free
refuses to stack); the free camera freeze/restore round trip (deadlines,
van position, zoom, hint clearing); F toggle and Esc cancel; chase handoff, idle
grace and recenter; free camera while driving restoring the chase pose without
moving the van; focus loss mid-drag dropping the drag; restart safety.

Rendered evidence (windowed run):

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --audio-driver Dummy --path . `
  -- --capture-plan=res://tools/plans/camera.json --capture-output=res://.godot/phase04-evidence/rendered
```

12 assertions passed and all seven 1280×720 PNGs were inspected:
`.godot/phase04-evidence/rendered/camera-27880-2743094/`

- `01_foot_orbit` — right-drag orbit around Pip carrying pizzas on the plaza.
- `02_chase_rear` — driving chase view behind/above the van after a manual look.
- `03_zoom_in` / `04_zoom_out` — same chase stance at the zoom clamps: the
  in-shot frames the van body close; the out-shot shows the full street and shop.
- `05_free_aerial` — independent aerial free camera with the PAUSED modal and the
  `FREE CAMERA · WASD move · Q/E rise + fall · SHIFT boost · mouse look · F/ESC return` hint.
- `06_house_corner` — Pip at a house corner; the boom pulls in tight against the
  facade (visible close-up), proving the sweep resolves walls.
- `07_shop_front` — shop-front clamp: facade distance shortens the boom while Pip
  and the shop stay framed (see the awning caveat below).

Headless regressions confirm the frozen-world contract: deadlines do not change
and the van does not move while `camera_mode` is `free`, then the clock resumes
after returning.

## Known defects / incomplete acceptance items

No required Phase 04 acceptance item is missing. Recorded limitations and
unrun checks:

- The "low roof" evidence is the shop front, not the awning: the shop's
  awning/canopy is visual-only in the built art (no collider, y≈2.37–2.57 m),
  while the shop collider is a 6×3.4×4.2 box. The camera therefore clamps
  against the facade and passes under the awning without pulling in. Next action:
  give low roof/awning geometry colliders when the shop interior arrives
  (Phase 07) or during art expansion, then re-run the boom plan shots.
- Feel-dependent tuning (drag speed, recenter feel, free-camera speed) was
  verified headlessly and by rendered shots only; no human play session has
  judged it yet. All values live in `Balance.cam_*` for quick adjustment.
- The free camera has no zoom gesture; wheel zoom is consumed and ignored there.
- No collision against future pedestrians/AI bodies (none exist yet); the boom
  correctly treats all current WORLD/VEHICLE geometry as solid.
- The camera does not ray against the ground plane; positive per-mode pitch
  minima (8°/6°) keep it above the surface.

## Player controls and documentation

- Right-mouse drag / gamepad right stick: look (orbit on foot, chase in the van).
- Mouse wheel: zoom (per-mode clamps, remembered per mode). **C**: recenter.
- **F**: free camera; WASD move, Q/E rise/fall, Shift boost, mouse look,
  **F**/**Esc** return. Esc is cancel/back and never stacks pause here.
- Inverted Y and sensitivity live in `Balance.cam_*` (settings UI is Phase 05).
- Docs updated: `README.md` (controls), `docs/ARCHITECTURE.md` (camera section,
  ownership table), `tools/SCENARIOS.md` (`mouse_motion` step, camera fields).

## Next phase entry point

Phase 05 (menus and settings) can expose `Balance.cam_*` directly; `camera.configure`
applies them at startup and `reset_state()` is the restart hook. Keep the free
camera's modal reason contract and the rig's status as the only consumer of
`cam_*` actions. Inspect `scripts/camera_rig.gd`, `scripts/services/balance.gd`
and `tools/phase04_checks.gd` before changing camera behavior, and keep
`.godot/phase04-evidence/` out of version control (local evidence only).
