# Phase 05 — Build menus and settings
Status: VERIFIED

> Extended by [Phase 05b](phase-05b-render-target.md): the render target moved to
> Forward+ at 1920×1080 and the options screen gained the quality-preset, MSAA,
> ambient-occlusion, glow and frame-cap rows. Everything else in this handoff
> still holds; the check count is now 251.

## Implemented behavior

Gameplay, ownership and pause semantics are unchanged; the game now has a real
front end, persisted preferences and an honest clock-free mode.

- **Title** (over the orbiting diorama): START SHIFT, FREE ROAM · NO CLOCK,
  OPTIONS, CONTROLS, CREDITS, QUIT …. No fake Continue: the only modes that
  exist are the ones the buttons name. Focus starts on START SHIFT and every
  screen works with mouse, keyboard and controller.
- **Pause**: RESUME, OPTIONS, CONTROLS, RESTART RUN …, RETURN TO TITLE …, QUIT ….
  Only the three progress-discarding actions take a confirm step
  (KEEP PLAYING / CONFIRM); RESTART RUN keeps the mode the player chose.
- **Results**: won/lost copy (SHIFT COMPLETE / SHIFT OVER) with the loss reason,
  deliveries, strikes against the limit and itemized earnings (base · pizza ·
  tips). RETRY SHIFT starts a clean shift, RETURN TO TITLE resets.
- **Options** writes live preferences: MASTER/MUSIC/SOUND EFFECTS/AMBIENCE
  volume, WINDOW MODE and WINDOW SIZE (disabled with an explanation where no real
  window exists, e.g. headless), UI SCALE 85/100/125/150 %, SHADOWS, SHADOW
  QUALITY, CAMERA SENSITIVITY, INVERT CAMERA Y, DRIVING AUTO-RECENTER, REDUCED
  CAMERA MOTION, SUBTITLES, TEXT SPEED. Every row is built from
  `SettingsService.SPEC`, so the screen cannot drift from the storage schema.
- **Controls** rebinds the 14 gameplay actions (`move_*`, `interact`,
  `handbrake`, `horn`, `confirm`, `cam_orbit`, `cam_recenter`, `cam_free`,
  `free_up`, `free_down`, `free_boost`) with conflict detection, a status line,
  RESET CONTROLS and a single BACK. `Esc` cancels an active capture instead of
  leaving the screen; critical movement actions can never be unbound.
- **Scalable layout**: every screen is a full-rect `ScrollContainer` +
  `CenterContainer` card, so an oversized card scrolls (`follow_focus`) instead
  of hiding an action, while panels/footers (RESET, BACK, hints) stay pinned.
- **One Esc/back stack**: `SessionInput` -> `Game.handle_back()` unwinds the
  rebind capture, then a subpanel, then the screen below it, then the free
  camera, then pause, then results -> title. `R` remains an instant
  restart/reset at pause/results/title and is ignored during a shift.
- **Preferences**: `user://settings.cfg` (version 1) owned by
  `SettingsService`. The only accessor is `value(key)`; the service applies
  audio buses, window mode/size, UI scale and InputMap itself and emits
  `changed(key)` for scene-owned pieces (camera preferences, sun shadows/quality,
  text speed). Stored values are validated key by key, so a hand-edited or
  truncated file falls back to defaults/clamps instead of breaking startup.
- **Free roam**: a session *mode*, not a second scene — same start path, no
  ticket, no deadline, no strikes. The HUD hides cash, goal, deliveries, strikes,
  objective and timer and shows `FREE ROAM · no clock`; the shop counter and
  house doors stay dormant (`_try_pickup_or_deliver` early-returns pickups and
  deliveries while roaming) so exploring cannot create, deliver or fail a ticket,
  while van entry/exit still works.
- **HUD scope**: gameplay furniture only (cash card, goal, deliveries, strikes,
  objective, timer progress bar, waypoint, prompt, speed, camera hint, toasts).
  It hides everything at title and results and clears a still-fading toast when
  gameplay is not visible, so no gameplay text floats over a menu.

## Files and ownership

| File | Change |
| --- | --- |
| `scripts/ui/menu_layer.gd` | New: CanvasLayer (layer 2) owning the pooled screens, the visible stack, focus memory, confirm dialogs (`_pending`), `activate(id)`, `handle_back()`, `show_message()`; emits `menu_action` for Game |
| `scripts/ui/ui_factory.gd` | New shared theme/factory (palette, fonts, buttons, sliders, chips, `centered()` scroll wrapper) used by the menu screens |
| `scripts/ui/options_screen.gd` | New: rows generated from `SettingsService.SPEC` (slider/choice/toggle), live apply, RESET TO DEFAULTS, BACK, window-row disabling |
| `scripts/ui/controls_screen.gd` | New: per-action chips, capture state machine, conflict messaging, reset, `handle_back()` for Esc-cancels-capture |
| `scripts/services/settings_service.gd` | New: `DEFAULTS`/`SPEC`/`REMAPPABLE`, `value(key)`, `configure(path, autosave)`, `load_settings()`, `save()`, `reset_all()`, `set_value/get_value/set_binding/binding_label`, per-key sanitizing and live application |
| `scripts/services/input_bindings.gd` | New: serialize/deserialize events, `apply`, `capture_all`, `conflict` (skips `ui_*`), `defaults`, prompt/label helpers |
| `scripts/game.gd` | Builds MenuLayer + SettingsService, `handle_back()`, `_on_menu_action()` (including roam-preserving restart), `_on_setting_changed()`, roam gating, results copy, snapshot fields |
| `scripts/session_input.gd` | Esc routes through the single back stack; `R` restart shortcut only at pause/results/title; menus keep working over the title |
| `scripts/services/session_service.gd` | `mode` ("shift"/"roam") and `roaming()`; `reset()` returns to shift; results stay shift-only |
| `scripts/services/order_service.gd` | Running ledger totals (`total_base`, `total_pizza`, `total_tip`) for the results itemization |
| `scripts/services/presentation.gd` | Prompts/HUD text follow the live bindings; `text_speed`/`subtitles` preferences; free-roam objective copy |
| `scripts/services/sound_presenter.gd` | Routes SFX through the `SFX` bus so the volume options are audible |
| `scripts/camera_rig.gd` | Applies sensitivity, inverted Y, auto-recenter and reduced-motion preferences |
| `scripts/services/game_snapshot.gd` | New fields: `play_mode`, `gameplay_visible`, `menu_screen`, `menu_focused`, `timer_visible`, results/ledger values |
| `tools/setup_project.gd`, `project.godot` | `free_down` moved from **E** to **CTRL** (the shipped map had `interact` and `free_down` both on E; the new conflict check exposed the duplicate) |
| `tools/capture.gd` | New `menu` and `setting` steps (validated against menu ids / `SPEC`), `timer_visible` field, richer logical records, and injected key events now carry both `keycode` and `physical_keycode` like real hardware |
| `tools/phase05_checks.gd` | New headless acceptance suite (214 checks) |
| `tools/settings_probe.gd` | New cross-process preference probe (`write`/`read`/`clean`) |
| `tools/plans/menu.json` | New 62-step plan: 18 assertions and 13 rendered shots (menus, roam, pause/confirm, results, gameplay at 100/125/150 %) |
| `tools/run_checks.py` | Runs `menus-settings`, the three probe modes and the `menu` plan twice (determinism); adds `unknown-menu`/`unknown-setting` negative fixtures |
| `tools/phase01_checks.gd` | Synthetic keys now set the logical `keycode` too, because the title starts through the focused button (`ui_accept`) instead of a gameplay `confirm` handler |
| `README.md`, `docs/ARCHITECTURE.md`, `tools/SCENARIOS.md` | Controls, menu/settings/free-roam ownership, new capture steps and fields |

## Contracts for the next phase

`scripts/ui/menu_layer.gd` (single owner of menu navigation):

- `signal menu_action(id: StringName)`; game ids are `start_shift`, `start_roam`,
  `resume`, `restart_shift`, `return_to_title`, `quit`; menu ids are `options`,
  `controls`, `credits`, `back`, `confirm_yes`, `confirm_no`.
- `configure(game, settings)`, `is_open()`, `top_id()`, `focused_id()`,
  `screen(id) -> Control`, `activate(id) -> bool`, `handle_back() -> bool`,
  `show_message(title, body)`. Screen node names are stable
  (`Screen_<id>`, `btn_<id>`, `Title`, `Body`, `Card`, `Scroll`, `Center`,
  `value_<key>`, `chip_<action>`).
- Menus never write session/order/actor state; they emit and let Game execute.
  Esc/back and `R` are owned by `SessionInput` + `Game.handle_back()`.

`scripts/services/settings_service.gd` (single owner of preferences):

- Keys: `audio/{master,music,sfx,ambience}`, `video/{window_mode,window_preset,
  ui_scale,shadows,shadow_quality}`, `camera/{sensitivity,invert_y,recenter,
  reduced_motion}`, `text/{subtitles,speed}`; version 1 file at
  `user://settings.cfg`.
- API: `configure(path, autosave)`, `load_settings()`, `save()`, `value(key)`,
  `set_value(key, value, persist := true)`, `reset_all()`, `set_binding(action,
  event) -> String` ("" on success, else a reason), `binding_label(action)`,
  `defaults()`, signals `changed(key)` and `input_changed`.
- Tests/checks must call `configure(custom_path, ...)`; the real
  `user://settings.cfg` is reserved for players.
- InputMap is the runtime source of truth for prompts; every remappable action is
  generated by `tools/setup_project.gd`, and `_factory_events` captures the
  pristine map once per process so RESET always works.

Session/roam contract for later phases: `SessionService.mode` ("shift"/"roam")
plus `roaming()`; anything that must not happen without a ticket should guard on
`session.roaming()` (as the shop counter and doors now do). Later campaign/save
work (Phase 22) should extend `SettingsService` rather than adding a second
preferences owner, and should put menu routes behind `MenuLayer` ids.

## Validation evidence

Engine: bundled `godot-engine\Godot_v4.7.2-stable_win64_console.exe`
(4.7.2.stable.official), Python 3.12.10, Windows. From the repository root:

```powershell
python tools/run_checks.py --godot '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe'
```

Result: **SUITE PASS — 40 commands**, seed 20261018, including:

- `PHASE 01: 137 checks, 0 failures`, `PHASE 03: 44 checks, 0 failures`,
  `PHASE 04: 58 checks, 0 failures`, `PHASE 05: 214 checks, 0 failures`.
- `settings-write` / `settings-read` / `settings-clean`: three separate processes
  prove that volumes, UI scale, a toggle, camera preferences, text speed and a
  remapped `interact` survive a process boundary through
  `user://phase05-probe.cfg`, and that untouched keys keep defaults.
- `menu-1`, `menu-2`, `deterministic replay menu`: identical logical records,
  18 assertions per run, clean teardown (no held actions, not paused, time scale 1).
- Both `playfast`/`playtest` deliveries, the camera plan, the RNG/town/art checks
  and all deliberate failure fixtures, now including `unknown-menu` and
  `unknown-setting`.

Evidence: `.godot/test-runs/suite-1792319235398733100-28992/` (summary.json and
per-command logs, including `menus-settings.log`, `settings-read.log`).

The 214 checks cover: title/pause/results/credits/confirm copy and visibility;
focus on every screen; arrow-key focus walking and mouse clicks through the real
input pipeline; Esc unwinding capture -> subpanel -> screen -> pause -> results ->
title; `R` restart rules; options rows applying live (bus volume, sun shadows,
UI scale, text speed, reduced motion); window rows disabled headless; rebinding
(capture, conflict refusal, Esc-cancel, critical-action protection, reset, the
`confirm` route); free-roam start/guards/restart; results itemization; HUD
furniture visibility at title, roam and results; layout at 85–150 % scale; and
the settings service (defaults, clamping, garbage values, save/load, reset).

Rendered evidence (windowed run, 13 PNGs inspected):

```powershell
& '.\godot-engine\Godot_v4.7.2-stable_win64_console.exe' --audio-driver Dummy --path . `
  --quit-after 30000 -- --capture-plan=res://tools/plans/menu.json `
  --capture-output=res://.godot/phase05-evidence
```

`.godot/phase05-evidence/menu-8884-1370684/` — `menu-title`,
`menu-title-scale150`, `menu-options`, `menu-options-scale150` (card scrolls,
RESET/BACK stay visible), `menu-controls`, `menu-credits`, `menu-roam` (only the
`FREE ROAM · no clock` hint), `menu-pause`, `menu-confirm` (RESTART THE RUN?),
`menu-gameplay-scale125`, `menu-hud-scale150` (cash card, objective, timer,
target card, waypoint all inside the frame), `menu-pause-shift`, `menu-results`
(clean card after the toast gate).

## Known defects / incomplete acceptance items

No required Phase 05 acceptance item is missing. Recorded limitations:

- Menu typography, spacing and hover/focus feel were judged from rendered
  1280×720 shots and headless geometry checks, not a human play session. The
  rendered plan exercises 100/125/150 %; the 85 % step is covered only by
  headless checks (layout asserts the logical view at the design resolution).
- Headless Godot boots a 64×64 dummy window, so the phase-05 checks pin
  `window.size = 1280×720` before asserting layout; the windowed plan is the
  rendered proof.
- Fullscreen/window-size switching was verified through the sanitized/disabled
  path headlessly plus windowed runs in windowed mode; no interactive
  fullscreen toggle was run on this desktop.
- Free roam has no save/continue (Phase 22) and deliberately no goals: it exists
  to inspect the island. Campaign entry, mission select and a real "Continue"
  arrive with progression/save work.
- The Phase 04 caveat is unchanged: the shop awning is visual-only, so the
  camera clamps on the facade instead of the awning.
- `camera/reduced_motion` shortens menu-free transitions and suppresses the
  title-orbit drift; it does not remove all camera easing.

## Player controls and documentation

- **Esc** is back/cancel everywhere: capture -> panel -> screen -> free camera ->
  pause -> results -> title. **R** restarts from pause/results/title.
  **Enter** (or the rebound `confirm` key) activates the focused action;
  arrows/WASD/left-stick move focus; mouse works on every screen.
- Options live under title/pause OPTIONS; Controls under title/pause CONTROLS.
  Preferences persist in `user://settings.cfg` and apply immediately.
- Free camera rise/fall is now **Q**/**CTRL** (`free_down` was moved off **E** to
  remove the duplicate binding with `interact`).
- Docs updated: `README.md` (controls, menus/settings/free roam, checks), 
  `docs/ARCHITECTURE.md` (new ownership rows plus the "Menus, preferences and
  free roam" section), `tools/SCENARIOS.md` (`menu`/`setting` steps, new fields,
  the probe and plan, Phase 05 checks).

## Next phase entry point

Phase 06 (unify interactions and dialogue) can build on `MenuLayer.activate`/
`show_message` for dialogue boxes and on `SettingsService` for its text
preferences, but interaction *targets* should keep flowing through Game's
validated target pipeline rather than through menu code. Inspect
`scripts/ui/menu_layer.gd`, `scripts/services/settings_service.gd`,
`scripts/game.gd` (`handle_back`, `_on_menu_action`, `_try_pickup_or_deliver`)
and `tools/phase05_checks.gd` before changing menu, settings or roam behavior;
keep `.godot/phase05-evidence/` out of version control (local evidence only).
