# Source audit and baseline evidence

Audit date: 18 October 2026. Scope: all six gameplay scripts, main/project configuration, world/art generators and authoring kit, resource checks, capture harness and plans, README, existing run logs, and selected historical screenshots. No game implementation files were edited.

## What exists
A Godot 4 voxel delivery prototype: 68 × 56 m flat island, three named streets, eight addressable houses, one shop, one controllable van, on-foot pizza stacks, $150 shift goal, three timeout strikes, shrinking delivery deadlines, procedural sound, title/pause/result overlays and compass markers. It has no implemented pedestrian/traffic population, story/dialogue system, simulation clock, weather, manual camera controls, persistent progression, proper shop interior or cargo ledger.

Main flow is concentrated in `scripts/game.gd`; HUD is built in `scripts/hud.gd`. World geometry is authored in `tools/build_town.py` and `tools/townkit.py`; original objects are authored in `tools/build_art.py`. Existing art has a consistent warm palette worth keeping. The historical title shot still displays the gameplay cash card, has keyboard-only instructions, and labels R as restart even though active-shift restart is ignored.

## Checks actually executed
All three returned exit code 0 with no reported script errors:
- Main scene: engine --headless --audio-driver Dummy --path . --quit-after 180.
- Resource load/instantiate check: --script tools/check_town.gd. Loaded island, houses, props and assembled town; houses container has eight direct children.
- Art check: --script tools/validate_art.gd. Ten scene/GLB files loaded. Original assets total 580 mesh pieces; this is not the full town's draw-call count.

A temporary audit SceneTree script, located outside the project, instantiated the main scene and inspected transitions. It did not modify game source. Outputs:
```text
AUDIT simultaneous inputs pip=true van=true driving=false
AUDIT pause tree=true game_can_process=false hud_can_process=true
AUDIT forced_house_zero actual=6
AUDIT moving_exit accepted driving=false speed=0.0
AUDIT finish leaves_autopilot=true
```
The forced result is one observed random value; the key invariant is that requesting house 0 while last_house=0 did not return 0. Abrupt temporary-probe teardown also emitted ObjectDB/resource-in-use diagnostics; those are not attributed to ordinary game shutdown. No new rendered playthrough or full manual shift was performed. Historical screenshots and capture plans are evidence of prior project artifacts, not newly passed gameplay tests.

## Confirmed findings
Severity reflects current player impact; references use original source functions and approximate original line numbers. Re-locate after refactoring.

| ID | Severity | Evidence / problem | Reproduction and expected fix | Phase |
| --- | --- | --- | --- | --- |
| B01 | High | game.gd _toggle_pause (~134) pauses tree; Game inherits pausable mode. Runtime can_process=false, HUD=true. Resume input is handled only by Game._unhandled_input. | Start, Esc, Esc via real input. Route resume through an always-processing input/UI owner while simulation remains paused. | 01 |
| B02 | High | game.gd _start_shift (~154–155) enables both player and van while driving=false. Both scripts poll the same movement actions. Runtime confirms both flags true. | Start and walk forward; parked van must remain still. Exactly one avatar owns movement. | 01 |
| B03 | High | game.gd _exit_van (~343) accepts exit at any speed, sets van.speed=0, places Pip at one fixed offset without checking solid geometry or support. Runtime accepts exit at 12 m/s. | Attempt exit moving and beside walls/water. Require safe stop and a capsule-clear supported candidate; otherwise remain seated with feedback. | 01 |
| B04 | Medium | game.gd _new_order (~164–169) applies forced_house then rerolls while equal to last_house. Probe forcing 0 with last_house=0 returned 6. | Explicit forced destination must take precedence; random anti-repeat logic applies only to random selection. | 01–02 |
| B05 | Medium | game.gd _finish (~229) disables input flags but leaves autopilot hooks. player.gd/vehicle.gd prioritize autopilot before input_enabled. Probe confirms hook remains. | Finish with active dev movement; no movement/timer continuation after terminal state. Clear/cancel controllers and test residual momentum. | 01 |
| B06 | Medium | game.gd _context and _try_pickup_or_deliver use only distance thresholds (3.6 m); no facing, line of sight or access checks. | Reproduce from blocked side of counter/door. One shared validated target must drive both prompt and action. Exact exploit positions need spatial reproduction. | 06–08 |
| B07 | Medium | check_town.gd only prints resources and always quit(0); no failure branch if a load is null/non-PackedScene. | Feed a missing/broken resource in isolated fixture; must fail nonzero with reason. | 02 |
| B08 | Medium | capture.gd fires timestamped steps and state printouts but never asserts a delivery, money, strikes or target; playfast sets forced order after start. | A failed delivery can still yield successful harness quit. Add waits/assertions/timeouts, seed and set initial order before start. | 02 |
| B09 | Low | README/title advertise R restart broadly; game.gd accepts restart only TITLE/COMPLETE/FAILED. | Either expose active restart through a functional pause menu or accurately describe availability. | 01, 05 |

## Source-confirmed limitations / conditional defects
These are not all observed player-facing failures. Reproduce the risk before reporting it fixed.
- **R01: future collision crash.** vehicle.gd (~120) calls apply_push on any CharacterBody3D without a capability check. It currently masks only environment layer 1, so its own slide query normally does not see Pip on layer 2. Adding cars/NPC collision without a protocol can cause nonexistent-method errors. Establish explicit contact interfaces and collision tests in 01/12/13.
- **R02: reverse impact response.** vehicle.gd frontal speed reduction checks normal dot forward regardless of travel direction. Reverse wall impacts may not reduce signed speed appropriately; reproduce both directions in 01.
- **R03: camera penetration.** camera_rig.gd uses a point ray, forces at least 3 m even if the hit is closer, then smooths through positions. Near walls and corners that can place a camera past a blocker. Use volume collision and rendered edge cases in 04.
- **R04: missing world contracts.** Empty houses makes _new_order return without a usable shift; missing PickupPoint/spawns/door nodes use hard get_node calls. Validate data and present a controlled error instead of a broken session.
- **R05: stale state.** _start_shift clears money/deliveries/strikes but not every driving/visibility/controller field. Normal UI starts once and restarts by scene reload, so repeated-start damage is a future menu/test integration risk. Define restart/enter-session semantics in 01/03.
- **R06: cosmetic obstacles.** Props are predominantly visual meshes; benches, fences, pond and street furniture should be classified deliberately for player, vehicle and NPC collision/navigation. Current ground plane covers pond; visible water is not an actual gap. Do not call this a crash bug, but resolve affordance mismatch in 09/20.
- **R07: van collider ownership.** Vehicle has a CharacterBody collision plus an embedded art StaticBody on layer 4. Audit which body pedestrians hit and avoid treating the art body as an unrelated moving static obstacle.
- **R08: shadow/far-plane scope.** Current camera far=400 and sun shadow distance=95; a much larger town needs explicit budgets, not uniformly bigger values.
- **R09: generated-output drift.** Editing generated world scenes alone gets overwritten. setup_project also rewrites input defaults; new controls must be represented there.
- **R10: food quality is only a countdown.** A box stack is directly tied to Pip; no distinct van cargo, receipt checks, preparation or customer identity. This is a gameplay gap, addressed by 07–08/16.
- **R11: tip presentation lag.** _pick_up calls _set_objective setting TIP $8 regardless of elapsed pickup travel; next _context corrects it on foot, but driving branch returns before updating target_sub. Reproduce stale displayed tip after entering van as time decreases; derive it from order data independently of avatar mode.
- **R12: marker feedback.** _deliver flashes marker then _new_order immediately hides it; validate whether delivery flash is visible at all and give completion a separate short-lived effect if needed.

## Product gaps requested by the user
World scale and meaningful districts; pedestrians, traffic and behavior; day/night and weather; genuine challenge and route decisions; freely controlled camera; useful menus/settings; proper pizza receiving at a staffed counter; conversations, customer identity and story; richer art/animation; gameplay beyond repeating one timer loop. The phases add maps, safe recovery, quality/cargo decisions, upgrades, optional errands, accessibility, saves and robust release checks to make these additions cohere.
