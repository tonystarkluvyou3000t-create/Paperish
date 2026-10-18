# Phase 01 — Core shift, pause, and vehicle correctness
Status: VERIFIED (headless acceptance; rendered/manual play remains unrun)

## Implemented behavior

- Ordinary keyboard events work: the original defaults only matched device 16.
  Project defaults and their generator now match any device (`-1`).
- `Game/SessionInput` processes Esc, Enter and allowed R input while Game and
  its world stay pausable. Three Esc cycles freeze both actors and deadlines.
- Game owns exclusive movement flags: title/results/paused -> neither;
  on foot -> Pip; seated -> van. Dev autopilot obeys that same ownership.
- R from title, active pause or either result resets the existing scene to title;
  Enter starts once. Reset clears scores, orders, timers, pause, controller hooks,
  motion, seated body/collider state, markers, prompts, transient feedback and
  camera targeting. Duplicate starts and settlements do not reset/reward again.
- Forced house selection takes precedence over random anti-repeat logic,
  including repeated house 0. Single-house selection terminates normally.
- Tip display and settlement use the same remaining-time formula on foot and
  while driving. Base pay, tip scale, town geometry and art remain unchanged.
- Entry requires an active, unpaused session, range and a stopped van. Exit
  requires an active, unpaused seated player and signed/horizontal speed at or
  below 0.25 m/s. Rejection changes only feedback; E does not brake.
- Exit tries local +X, -X, then rear, transformed into world space. Each candidate
  needs five floor samples, acceptable floor normals/height differences, full
  capsule clearance, and a capsule sweep from the van. Pip and the source van
  are excluded by RID. Feet-height rays cannot use the source van's roof as a
  floor. Fully blocked, steep, unsupported and partial-ledge exits fail safely.
- The moving van's CharacterBody owns all van collision. The embedded art
  StaticBody is disabled at runtime; standalone art retains its collider.
- Contact damping uses actual signed travel direction. Push dispatch accepts
  only the player script that implements `apply_push`, not arbitrary characters.
- Startup validates world references, house markers/unique nonempty addresses,
  actor types and exit-probe shapes. Broken worlds show actionable diagnostics
  and cannot start. Results cancel motion/controllers and reject progression.

## Files and ownership

- `scripts/game.gd`: session state/reset, order guards, world validation, tip
  derivation, entry/exit rules and collision probes.
- `scripts/session_input.gd`: always-processing input owner, created by Game.
- `scripts/collision_layers.gd`: named masks and collision matrix comments.
- `scripts/player.gd`, `scripts/vehicle.gd`: actor ownership, explicit collision
  contracts, moving collider ownership and signed contact response.
- `scripts/hud.gd`: accurate restart hints, pause restart instruction, toast reset.
- `project.godot`, `tools/setup_project.gd`: keyboard device defaults and generator.
- `tools/phase01_checks.gd`: focused acceptance assertions; no general JSON runner.
- `README.md`: controls, Linux invocation, acceptance command and limitations.
- No generated art/world scenes, audio files, screenshots or historic audit files
  were changed. The starting working tree was clean.

## Contracts for the next phase

- Existing `State` enum remains TITLE/TO_SHOP/TO_HOUSE/COMPLETE/FAILED.
- `is_shift_active() -> bool` also requires `world_ready`.
- `_sync_movement()` is the authoritative actor ownership coordinator.
- `restart()` resets in place to TITLE, rather than reloading the main scene.
  `forced_house` resets to -1; inject it after reset and **before** starting.
- `_start_shift()` is legal only from valid TITLE. `_on_timeout()` requires an
  active unpaused order with `timer <= 0`; resetting the new deadline prevents
  repeat calls from striking the next order. `_deliver()` requires TO_HOUSE,
  matching carried pizza count, on-foot ownership and an unpaused active shift.
- `_enter_van() -> bool`, `_exit_van() -> bool` report success. They must not be
  bypassed by tests that set `driving` directly. Rejection must preserve state.
- Exported exit balance: `stopped_speed=0.25`, `exit_clearance=0.20`,
  `exit_max_step=0.45`, `exit_max_drop=0.75`; floor gap 0.04 m, query margin 0.02 m.
- `world_ready: bool`, `world_errors: Array[String]` expose startup diagnostics.
  House `Door`/`Park`, pickup, spawn and existing limb/wheel contracts remain.
- Collision bit masks: WORLD=1, PLAYER=2, VEHICLE=4, NONE=0. Pip mask=5,
  van mask=1; seated Pip layer=0 and collision shape deferred-disabled. Floor
  probes use WORLD; clearance/sweep use Pip's mask. Source van/Pip RIDs excluded.
- Only HUD and SessionInput run while paused; never make all of Game always
  processing. No new input actions, data schemas or service signals yet.
- Random order selection still uses global RNG; isolated seeded ownership,
  public structured diagnostics and the general runner belong to Phase 02.

## Validation evidence

Executed on Linux x86_64 using Godot `4.6.3.stable.official.7d41c59c4`. The
documented Windows 4.7.2 executable is unavailable and was not claimed tested.
In this environment, prefix commands with:

```sh
cd /workspace/Paperish
source /workspace/.paperish-env/activate.sh
```

Commands executed:

```sh
godot --headless --audio-driver Dummy --path . --script tools/phase01_checks.gd
godot --headless --audio-driver Dummy --path . --quit-after 180
godot --headless --audio-driver Dummy --path . --script tools/check_town.gd
godot --headless --audio-driver Dummy --path . --script tools/validate_art.gd
git diff --check
```

- Focused acceptance: **137 assertions, zero failures**, exit 0. Includes raw
  device-0 Enter/E/Esc/R events through `Viewport.push_input`; polling movement
  uses held Input actions. Includes three paused seated restart cycles; positive
  and negative side/rear/rotated/capsule/support/slope fixtures; actual forward
  and reverse wall contacts; handbrake input followed by safe E exit; a thin
  wall before a clear endpoint; plain CharacterBody contact without push API;
  terminal controller/momentum cancellation; single and repeated destinations;
  single settlement/strike; invalid startup contracts. The only five ERROR lines
  are intentional missing-world diagnostics. No script errors or shutdown leaks
  remain. Fixture teardown allows 0.15 seconds for Dummy audio's mix-thread cleanup.
- Main scene: exit 0 with no errors/warnings. Town: all four resources instantiate,
  eight house children, seven assembled town children. Art: all ten scene/GLB
  files load, 580 original mesh pieces. Whitespace check passes.
- `tools/setup_project.gd` ran against a separate minimal project under
  `/workspace/.paperish-env/setup-config-check`. Exit 0, save err=0; a Python
  assertion confirmed all 15 generated key events have device -1. No authoring
  generators ran against the checkout, since none of their output changed.
- Evidence logs: `/workspace/.paperish-env/logs/phase01-checks.log`,
  `phase01-main.log`, `phase01-town.log`, `phase01-art.log`,
  `phase01-config-check.log`. Initial reproduction: `phase01-before.log`.
- Initial-state probe reloaded original HEAD gameplay scripts into an isolated
  scene. Original device-16 restriction was independently demonstrated by event
  matching (device 0 false, device 16 true); after fixing that prerequisite,
  original pause stayed true after the second Esc. Other initial results:
  both input flags true, forced 0 became 6, 12 m/s exit accepted and set speed 0,
  driving tip stayed $8 at 25% time, terminal autopilot remained set, reverse
  collision retained -3.83 m/s while forward contact damped to 0.
- The existing `playfast` plan also ran with screenshot steps removed in an
  external copy (no original plan or image overwritten):

  ```sh
  timeout 65 godot --headless --audio-driver Dummy --path . --max-fps 60 --quit-after 6000 -- --capture-plan=/workspace/.paperish-env/playfast-headless.json
  ```

  Log: `/workspace/.paperish-env/logs/phase01-playfast.log`. Exit 0 and plan
  completion, but **zero deliveries**, so this is not a passing delivery smoke.
  Pickup and entering/driving now succeed with ordinary input. The timed exit
  at 27 seconds occurs before arrival/stop and is rejected; its walk step runs
  while still seated, then the later E exits instead of delivering. Phase 02
  must wait for stop/exit/arrival conditions and assert payment. Focused tests
  separately verify braking then exiting, delivery-once payout, and new order.

| Audit ID | Reproduction and verified result |
| --- | --- |
| B01 | Actual Esc events paused but could not resume old Game; three complete cycles now pass with clocks/motion frozen. |
| B02 | Old start enabled both actors; all four walking inputs now leave parked van still, and driving leaves hidden Pip still. |
| B03 | Old fast exit stopped the van instantly; fast entry/exit now reject unchanged, physical exit fixtures pass/fail as appropriate. |
| B04 | Old forced repeat rerolled; two forced house-0 orders and single-house selection now pass. |
| B05 | Old finish retained hooks; finish clears hooks/momentum and injected terminal hooks cannot move actors. |
| B09 | Old R was ignored during active play with misleading hint; Esc then R now resets to title and hints describe the path. |
| R01 | Plain CharacterBody contact now passes without any unchecked push call. |
| R02 | Actual reverse wall contact reproduced bad signed response; both directions now damp below 1 m/s in fixture. |
| R04 | Five missing-node fixtures now reject startup with diagnostics and no usable broken shift. |
| R05 | Duplicate start, title/result restarts and three seated paused restarts restore consistent session state. |
| R07 | Embedded body is disabled; the existing van body alone owns parked/driven collision. |
| R11 | Display at pickup reflects 25% time ($2), and a driving update reflects zero time ($0). |

## Known defects / incomplete acceptance items

- No required headless Phase 01 acceptance items remain. No display server is
  available: rendered appearance, manual keyboard driving and audible output
  were not tested. Teleport fixtures do not prove human route reachability.
- The original screenshot harness still lacks assertions, bounded conditional
  waits and seed isolation, and check_town still always exits 0. Those are
  explicitly Phase 02 scope; inspect output, not just their exit codes.
- Audit B06 and later product gaps remain outside this phase. Floor support is
  conservative and uses the current player capsule/Y-up van geometry; future
  changed vehicle rigs or collision layers must update and retest these probes.

## Player controls and documentation

Controls remain WASD/arrows, E interact/vehicle, Space handbrake, H horn, Esc
pause/resume, Enter start. R returns to title and clears the shift from title,
pause or result. E requires stopped, clear, supported exits. No art regeneration
is needed. If regenerating project defaults, use the updated setup_project.gd;
do not reintroduce device 16.

## Next phase entry point

Phase 01 is the completed assignment. Continue with Phase 02 in a subsequent
assignment per the pack's one-phase rule. Read this handoff, then
`phase-02-build-deterministic-regression-checks.md`, `tools/phase01_checks.gd`,
`tools/capture.gd`, `tools/check_town.gd`, the existing plans and the flow methods
above. Preserve historical screenshots and make failed scenarios exit nonzero.
